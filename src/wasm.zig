const std = @import("std");
const builtin = @import("builtin");
const math = @import("math.zig");
const core = @import("core.zig");
const Vector2i = math.Vector2i;
const Buffer2D = @import("buffer.zig").Buffer2D;
const RGBA = @import("pixels.zig").RGBA;
const RGB = @import("pixels.zig").RGB;

// functions provided by the wasm module caller (in js, the `env` object passed to `instantiateStreaming`)
pub extern fn js_console_log(str: [*]const u8, len: usize) void;
pub extern fn js_milli_since_epoch() usize;
pub extern fn js_read_file_synch(file_name_ptr: [*]const u8, file_name_len: usize, out_ptr: *[*]u8, out_size: *usize) void;
pub extern fn js_calls(id: u32) void;

pub fn js(comptime unique_identifier: u32, comptime js_code: []const u8) type {
    
    // the `js_code` is only ever used by the build.zig file, when creating the `inlined.js` file
    _ = js_code;

    return struct {
    
        // TODO somehow make the identifier be automatically generated
        const id: u32 = unique_identifier;

        fn call() void {
            js_calls(id);
        }
    };
}



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

        export fn wasm_get_static_buffer() [*]u8 {
            return @ptrCast(&static_buffer_for_runtime_use);
        }
        export fn wasm_get_canvas_pixels() [*]u8 {
            return @ptrCast(state.pixel_buffer.data.ptr);
        }
        export fn wasm_get_canvas_scaling() u32 {
            return app.dimension_scale;
        }
        export fn wasm_get_canvas_size(out_w: *u32, out_h: *u32) void {
            out_w.* = app.desired_width;
            out_h.* = app.desired_height;
        }
        export fn wasm_send_event(len: usize, a: usize, b: usize) void {
            _ = a;
            _ = b;
            const event: []const u8 = wasm_get_static_buffer()[0..len];
            flog("event received {s}", .{event});
            var tokens = std.mem.tokenize(u8, event, ":");
            const event_type = tokens.next().?;
            if (std.mem.eql(u8, event_type, "mouse")) {
                if (std.mem.eql(u8, tokens.next().?, "down")) {
                    flog("mouse down!", .{});
                }
            }
            else {
                flog("unrecognized event received!", .{});
                @panic("");
            }
        }
        export fn wasm_request_buffer(len: usize) [*]u8 {
            const allocator = allocator_set_somewhere_else orelse {
                flog("`wasm_request_buffer` failed because no allocator was set beforehand!", .{});
                panic(error.allocatorNeverSet);
            };
            return @ptrCast(allocator.alloc(u8, len) catch |e| {
                flog("`wasm_request_buffer` failed!", .{});
                panic(e);
            });
        }
        export fn wasm_init() void {
            init();
        }
        export fn wasm_tick() void {
            
            js(0,
                \\console.log("tick");
            ).call();

            tick();
        }
        export fn wasm_set_dt(dt: f32) void {
            delta_time = dt;
        }
        export fn wasm_set_mouse(x: i32, y: i32, down: i32) void {
            mousex = x;
            mousey = y;
            mousedown = down == 1;
        }

        fn FixedBufferAllocatorWrapper(comptime name: []const u8, comptime log: bool) type {
            return struct {

                const Self = @This();

                fba: std.heap.FixedBufferAllocator,
                one_percent_aprox: usize,

                pub fn init(buffer: []u8) Self {
                    return .{
                        .fba = std.heap.FixedBufferAllocator.init(buffer),
                        .one_percent_aprox = @intFromFloat(@as(f32, @floatFromInt(buffer.len))/100.0),
                    };
                }

                pub fn allocator(self: *Self) std.mem.Allocator {
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
                    var self = ptrCast(Self, ctx);
                    const res = self.fba.allocator().rawAlloc(len, ptr_align, ret_addr);
                    if (log) flog("Allocator " ++ name ++ " alloc {} ({}%) at {any}", .{len, @divFloor(len, self.one_percent_aprox), res});
                    return res;
                }

                fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
                    var self = ptrCast(Self, ctx);
                    const res = self.fba.allocator().rawResize(buf, buf_align, new_len, ret_addr);
                    if (log) flog("Allocator " ++ name ++ " resize from {} ({}%) at {any} to {} ({}%) at {}", .{buf.len, @divFloor(buf.len, self.one_percent_aprox), buf.ptr, new_len, @divFloor(new_len, self.one_percent_aprox), res});
                    return res;
                }

                fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
                    var self = ptrCast(Self, ctx);
                    const is_last_allocation = self.fba.isLastAllocation(buf);
                    if (log) if (is_last_allocation) {
                        flog("Allocator " ++ name ++ " free {} ({}%) bytes at {any}", .{buf.len, @divFloor(buf.len, self.one_percent_aprox), buf.ptr});
                    }
                    else {
                        flog("Allocator " ++ name ++ " free {} ({}%) bytes at {any} (will not free!)", .{buf.len, @divFloor(buf.len, self.one_percent_aprox), buf.ptr});
                    };
                    self.fba.allocator().rawFree(buf, buf_align, ret_addr);
                }

                fn ptrCast(comptime T: type, ptr: *anyopaque) *T {
                    if (@alignOf(T) == 0) @compileError(@typeName(T));
                    return @ptrCast(@alignCast(ptr));
                }
            };

        }

        const State = struct {
            w: i32,
            h: i32,
            
            mouse: Vector2i,
            keys: [256]bool,
            keys_old: [256]bool,
            pixel_buffer: Buffer2D(RGBA),
            frame_index: usize,
            mouse_down: bool,
            mouse_clicked: bool,
            
            main_allocator: FixedBufferAllocatorWrapper("Main", true),
            app_long_allocator: FixedBufferAllocatorWrapper("AppLong", true),
            app_short_allocator: FixedBufferAllocatorWrapper("AppShort", false),
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
        var allocator_set_somewhere_else: ?std.mem.Allocator = null;

        fn init() void {
            
            const random_seed = js_milli_since_epoch();
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
            
            state.main_allocator = FixedBufferAllocatorWrapper("Main", true).init(heap);
            state.pixel_buffer = Buffer2D(RGBA).from(state.main_allocator.allocator().alloc(RGBA, app.desired_height * app.desired_width) catch |e| panic(e), app.desired_width);
            state.app_long_allocator = FixedBufferAllocatorWrapper("AppLong", true).init(state.main_allocator.allocator().alloc(u8, std.wasm.page_size * 256) catch |e| {
                flog("Failed to allocate memory for the application's long term reserved memory", .{});
                panic(e);
            });
            state.app_short_allocator = FixedBufferAllocatorWrapper("AppShort", false).init(state.main_allocator.allocator().alloc(u8, std.wasm.page_size * 256) catch |e| {
                flog("Failed to allocate memory for the application's update memory", .{});
                panic(e);
            });

            state.keys = [1]bool{false} ** 256;
            state.w = @intCast(state.pixel_buffer.width);
            state.h = @intCast(state.pixel_buffer.height);
            state.mouse = undefined;
            state.frame_index = 0;
            state.mouse_down = false;
            state.mouse_clicked = false;

            app.init(state.app_long_allocator.allocator()) catch |e| panic(e);
        }
        
        fn tick() void {
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
                .allocator = state.app_short_allocator.allocator(),
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
            flog("Memory used on frame {}: {} ({}%) {} ({}%)", .{ state.frame_index, state.app_short_allocator.fba.end_index, @divFloor(state.app_short_allocator.fba.end_index, state.app_short_allocator.one_percent_aprox), state.app_long_allocator.fba.end_index, @divFloor(state.app_long_allocator.fba.end_index, state.app_long_allocator.one_percent_aprox) });
            if (!keep_running) {
                // Too bad, there is no stopping!!!
            }
            state.mouse_clicked = false;
            state.keys_old = state.keys;
            state.frame_index += 1;
            
            state.app_short_allocator.fba.reset();
        }

        pub fn read_file_sync(allocator: std.mem.Allocator, file: []const u8) ![]const u8 {
            std.debug.assert(allocator_set_somewhere_else == null);
            var out_ptr: [*]u8 = undefined;
            var out_size: usize = undefined; 
            {
                // `js_read_file_synch` will call `wasm_request_buffer`, which in turn will rely on `allocator_set_somewhere_else` to be set.
                // this is a bit of a hack that I'm playing with while I figure out a good strategy to work with allocations and wasm/js and the like.
                allocator_set_somewhere_else = allocator;
                defer allocator_set_somewhere_else = null;
                js_read_file_synch(file.ptr, file.len, &out_ptr, &out_size);
            }
            return out_ptr[0..out_size];
        }
        
        pub fn flog(comptime fmt: []const u8, args: anytype) void {
            var buffer: [1024*2]u8 = undefined;
            const str = std.fmt.bufPrint(&buffer, fmt, args) catch "flog failed"[0..];
            js_console_log(str.ptr, str.len);
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
    return @intCast(js_milli_since_epoch());
}
