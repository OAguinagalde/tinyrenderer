const std = @import("std");
const builtin = @import("builtin");
const TaskManager = @import("TaskManager.zig");
const math = @import("math.zig");
const core = @import("core.zig");
const Vector2i = math.Vector2i;
const Buffer2D = @import("buffer.zig").Buffer2D;
const RGBA = @import("pixels.zig").RGBA;
const RGB = @import("pixels.zig").RGB;

// functions provided by the wasm module caller (in js, the `env` object passed to `instantiateStreaming`)
pub extern fn console_log(str: [*]const u8, len: usize) void;
pub extern fn milli_since_epoch() usize;
pub extern fn fetch(str: [*]const u8, len: usize) void;

pub fn Application(comptime app: ApplicationDescription) type {
    return struct {
        
        pub fn run() !void {
            comptime {
                // For wasm builds, the application is built as a library. This library also MUST export certain functions
                // that the js side of will use to communicate with the module. Since zig is lazily analized, we need to explicitly
                // reference these functions so that during buildtime the compiler "finds" them, and exports them.
                // So, if you application is going to be built for wasm targets, you can either directly reference them, or just "call"
                // this function which does nothing other than reference one of the exports during compile time.
                _ = @This().wasm_init;
            }
        }

        pub const OutPixelType = RGBA;
        pub const width = app.desired_width;
        pub const height = app.desired_height;
        pub const dimension_scale = app.dimension_scale;

        pub export fn wasm_get_static_buffer() [*]u8 {
            return @ptrCast(&static_buffer_for_runtime_use);
        }
        pub export fn wasm_get_canvas_pixels() [*]u8 {
            return @ptrCast(state.pixel_buffer.data.ptr);
        }
        pub export fn wasm_get_canvas_scaling() u32 {
            return app.dimension_scale;
        }
        pub export fn wasm_get_canvas_size(out_w: *u32, out_h: *u32) void {
            out_w.* = app.desired_width;
            out_h.* = app.desired_height;
        }
        pub export fn wasm_send_event(len: usize, a: usize, b: usize) void {
            const event: []const u8 = wasm_get_static_buffer()[0..len];
            flog("event received {s}", .{event});
            var tokens = std.mem.tokenize(u8, event, ":");
            const event_type = tokens.next().?;
            if (std.mem.eql(u8, event_type, "mouse")) {
                if (std.mem.eql(u8, tokens.next().?, "down")) {
                    flog("mouse down!", .{});
                }
            }
            else if (std.mem.eql(u8, event_type, "buffer")) {
                const id = tokens.next().?;
                const data: struct { ptr: [*]u8, len: usize } = .{ .ptr = @ptrFromInt(a), .len = b };
                state.tasks.?.finish(id, data);
            }
            else {
                flog("unrecognized event received!", .{});
                @panic("");
            }
        }
        pub export fn wasm_request_buffer(len: usize) [*]u8 {
            return @ptrCast(state.allocator.alloc(u8, len) catch |e| panic(e));
        }
        pub export fn wasm_init() void {
            init();
        }
        pub export fn wasm_tick() void {
            tick();
        }
        pub export fn wasm_set_dt(dt: f32) void {
            delta_time = dt;
        }
        pub export fn wasm_set_mouse(x: i32, y: i32, down: i32) void {
            mousex = x;
            mousey = y;
            mousedown = down == 1;
        }

        const WasmLoggingAllocator = struct {

            child_allocator: std.mem.Allocator,

            pub fn init(child_allocator: std.mem.Allocator) WasmLoggingAllocator {
                return .{
                    .child_allocator = child_allocator,
                };
            }

            pub fn allocator(self: *WasmLoggingAllocator) std.mem.Allocator {
                return .{
                    .ptr = self,
                    .vtable = &.{
                        .alloc = alloc,
                        .resize = resize,
                        .free = free,
                    },
                };
            }

            fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
                var self = ptrCast(WasmLoggingAllocator, ctx);
                const res = self.child_allocator.rawAlloc(len, ptr_align, ret_addr);
                flog("Allocator alloc {} at {any}", .{len, res});
                return res;
            }

            fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
                var self = ptrCast(WasmLoggingAllocator, ctx);
                const res = self.child_allocator.rawResize(buf, buf_align, new_len, ret_addr);
                flog("Allocator resize from {} at {any} to {} -> {}", .{buf.len, buf.ptr, new_len, res});
                return res;
            }

            fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
                var self = ptrCast(WasmLoggingAllocator, ctx);
                flog("Allocator free {} bytes at {any}", .{buf.len, buf.ptr});
                self.child_allocator.rawFree(buf, buf_align, ret_addr);
            }

            fn ptrCast(comptime T: type, ptr: *anyopaque) *T {
                if (@alignOf(T) == 0) @compileError(@typeName(T));
                return @ptrCast(@alignCast(ptr));
            }

        };

        const Out = struct {
            len: usize = 0,
            buffer: [1024]u8 = undefined,
            /// buffers until the last character of `fmt` is '\n', then flush to the console with `flog`
            pub fn print(self: *Out, comptime fmt: []const u8, args: anytype) !void {
                const result = std.fmt.bufPrint(self.buffer[self.len..], fmt, args) catch |e| {
                    flog("Error {any} found in `Out` buffered writer used on Allocator logging", .{e});
                    panic(e);
                };
                self.len = self.len + result.len;
                if (fmt[fmt.len-1] == '\n') {
                    flog("{s}", .{self.buffer[0..result.len]});
                    self.len = 0;
                }
                else return;
            }
        };

        const State = struct {
            w: i32,
            h: i32,
            
            mouse: Vector2i,
            keys: [256]bool,
            keys_old: [256]bool,
            pixel_buffer: Buffer2D(RGBA),
            frame_index: usize,
            tasks: ?TaskManager,
            mouse_down: bool,
            mouse_clicked: bool,
            
            fba: std.heap.FixedBufferAllocator,
            wla: WasmLoggingAllocator,
            // wtwla: std.heap.LogToWriterAllocator(Out),
            allocator: std.mem.Allocator,
            random: std.rand.Random,
            random_internal_implementation: std.rand.Xoshiro256,
            
            __memory_base: [*]u8,
            __table_base: [*]u8,
            __stack_pointer: [*]u8,
            __data_end: [*]u8,
            __heap_base: [*]u8,
            __heap_end: [*]u8,
        };

        var state: State = undefined;
        var delta_time: f32 = undefined;
        var mousex: i32 = undefined;
        var mousey: i32 = undefined;
        var mousedown: bool = undefined;
        var static_buffer_for_runtime_use: [1024]u8 = undefined;

        fn init() void {
            
            const random_seed = milli_since_epoch();
            state.random_internal_implementation = std.rand.DefaultPrng.init(random_seed);
            state.random = state.random_internal_implementation.random();

            // https://github.com/WebAssembly/tool-conventions/blob/main/DynamicLinking.md
            state.__memory_base = @extern(?[*]u8, .{.name = "__memory_base"}).?;
            flog("__memory_base {any} {}", .{state.__memory_base, @as(usize, @intFromPtr(state.__memory_base))});
            state.__table_base = @extern(?[*]u8, .{.name = "__table_base"}).?;
            flog("__table_base {any} {}", .{state.__table_base, @as(usize, @intFromPtr(state.__table_base))});
            // TODO for some reason ever since I updated zig and change this to be an executable without entry point rather than a dynamic library,
            // trying to get the `__stack_pointer` triggers the error `wasm-ld: invalid relocation data index`... Why?
            // 
            //     state.__stack_pointer = @extern(?[*]u8, .{.name = "__stack_pointer"}).?;
            //     flog("__stack_pointer {any} {}", .{state.__stack_pointer, @as(usize, @intFromPtr(state.__stack_pointer))});
            // 
            state.__data_end = @extern(?[*]u8, .{.name = "__data_end"}).?;
            flog("__data_end {any} {}", .{state.__data_end, @as(usize, @intFromPtr(state.__data_end))});
            state.__heap_base = @extern(?[*]u8, .{.name = "__heap_base"}).?;
            flog("__heap_base {any} {}", .{state.__heap_base, @as(usize, @intFromPtr(state.__heap_base))});
            state.__heap_end = @extern(?[*]u8, .{.name = "__heap_end"}).?;
            flog("__heap_end {any} {}", .{state.__heap_end, @as(usize, @intFromPtr(state.__heap_end))});
            var zero: [*]allowzero u8 = @ptrFromInt(0);
            const heap: []u8 = @ptrCast(zero[@intFromPtr(state.__heap_base)..@intFromPtr(state.__heap_end)]);
            flog("heap length {}", .{heap.len});
            
            state.fba = std.heap.FixedBufferAllocator.init(heap);
            // state.wtwla = std.heap.LogToWriterAllocator(Out).init(state.fba.allocator(), .{});
            // state.allocator = state.wtwla.allocator();
            state.wla = WasmLoggingAllocator { .child_allocator = state.fba.allocator() };
            state.allocator = state.wla.allocator();

            state.tasks = TaskManager.init(state.allocator);
            state.keys = [1]bool{false} ** 256;
            state.pixel_buffer = Buffer2D(RGBA).from(state.allocator.alloc(RGBA, app.desired_height * app.desired_width) catch |e| panic(e), app.desired_width);
            state.w = @intCast(state.pixel_buffer.width);
            state.h = @intCast(state.pixel_buffer.height);
            state.mouse = undefined;
            state.frame_index = 0;
            state.mouse_down = false;
            state.mouse_clicked = false;

            app.init(state.allocator) catch |e| panic(e);
        }
        fn tick() void {
            
            // wait for every task resgistered at init() to finish
            if (state.tasks) |tm| {
                if (!tm.finished()) return;
                state.tasks.?.deinit();
                state.tasks = null;
            }

            for (static_buffer_for_runtime_use[0..256], 0..) |byte, i| state.keys[i] = byte == 1;
            const mouse_d = Vector2i { .x = mousex - state.mouse.x, .y = mousey - state.mouse.y };
            state.mouse = Vector2i { .x = mousex, .y = mousey };
            
            if (!state.mouse_down and mousedown) {
                state.mouse_clicked = true;
            }
            state.mouse_down = mousedown;

            var platform = UpdateData {
                .pixel_buffer = state.pixel_buffer,
                .keys_old = state.keys_old,
                .keys = state.keys,
                .allocator = state.allocator,
                .w = state.w,
                .h = state.h,
                .frame = state.frame_index,
                .mouse = state.mouse,
                .mouse_d = mouse_d,
                .fps = undefined,
                .ms = delta_time,
                .mouse_left_down = state.mouse_down,
                .mouse_left_clicked = state.mouse_clicked,
                .mwheel = undefined,
            };

            const keep_running = app.update(&platform) catch |e| panic(e);
            if (!keep_running) {
                // Too bad, there is no stopping!!!
            }
            state.mouse_clicked = false;
            state.keys_old = state.keys;
            state.frame_index += 1;
        }
        fn finish_read_file_task(regist_context: []const u8, completion_context: []const u8) void {
            var cc: struct { ptr: [*]u8, len: usize } = undefined;
            core.value(&cc, completion_context);
            const file_bytes = cc.ptr[0..cc.len];
            defer state.allocator.free(file_bytes);

            const original_callback_storage = regist_context[0..@sizeOf(*const ReadFileCallback)];
            var original_callback: *const ReadFileCallback = undefined;
            core.value(&original_callback, original_callback_storage);

            const original_context_storage = regist_context[@sizeOf(*const ReadFileCallback)..];
            original_callback(file_bytes, original_context_storage) catch |e| panic(e);
        }

        pub const ReadFileCallback = fn (bytes: []const u8, context: []const u8) anyerror!void;
        pub fn read_file(file: []const u8, callback: *const ReadFileCallback, context_value: anytype) !void {
            const self: *TaskManager = &state.tasks.?;
            const context_size = @sizeOf(@TypeOf(context_value));
            const callback_size = @sizeOf(@TypeOf(callback));
            
            // allocate enough space to store the task until it gets completed and freed on `finish`
            const size = context_size+file.len+callback_size;
            var task_storage = try self.arena.allocator().alloc(u8, size);
            
            const file_storage: []u8 = task_storage[0..file.len];
            const callback_storage: []u8 = task_storage[file.len..file.len+callback_size];
            const context_storage: []u8 = task_storage[file.len+callback_size..size];
            const context_and_callback = task_storage[file.len..size];
            
            std.debug.assert(context_size == context_storage.len);
            @memcpy(file_storage, file);
            @memcpy(context_storage, core.byte_slice(&context_value));        
            @memcpy(callback_storage, core.byte_slice(&callback));        
            // the task itself just contains a pointer to the context (its memory is manually managed), and a pointer to the callback (which is static code, so no need to manage its lifetime)
            try self.tasks.put(file_storage, .{ .callback = finish_read_file_task, .context = context_and_callback });
            
            fetch(file.ptr, file.len);
        }
        pub fn flog(comptime fmt: []const u8, args: anytype) void {
            var buffer: [1024*2]u8 = undefined;
            const str = std.fmt.bufPrint(&buffer, fmt, args) catch "flog failed"[0..];
            console_log(str.ptr, str.len);
        }
        fn panic(e: anyerror) noreturn {
            flog("panic {any}", .{e});
            @panic("ERROR");
        }

    };
}

pub const UpdateData = struct {
    allocator: std.mem.Allocator,
    w: i32,
    h: i32,
    mouse: Vector2i,
    mouse_d: Vector2i,
    keys_old: [256]bool,
    keys: [256]bool,
    pixel_buffer: Buffer2D(RGBA),
    fps: usize,
    ms: f32,
    frame: usize,
    mouse_left_down: bool,
    mouse_left_clicked: bool,
    mwheel: i32,

    pub fn key_pressing(ud: *const UpdateData, key: usize) bool {
        return ud.keys[key];
    }
    
    pub fn key_pressed(ud: *const UpdateData, key: usize) bool {
        return ud.keys[key] and !ud.keys_old[key];
    }

};
pub const OutPixelType = RGBA;
pub const InitFn = fn (allocator: std.mem.Allocator) anyerror!void;
pub const UpdateFn = fn (update_data: *UpdateData) anyerror!bool;
pub const ApplicationDescription = struct {
    init: InitFn,
    update: UpdateFn,
    dimension_scale: comptime_int,
    desired_width: comptime_int,
    desired_height: comptime_int,
};

pub fn timestamp() i64 {
    return @intCast(milli_since_epoch());
}
