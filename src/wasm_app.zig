const std = @import("std");

// functions provided by the wasm module caller (in js, the `env` object passed to `instantiateStreaming`)
const external = struct {
    pub extern fn console_log(str: [*]const u8, len: usize) void;
    pub extern fn milli_since_epoch() usize;
    pub extern fn fetch(str: [*]const u8, len: usize) void;

    const util = struct {
        
        pub fn log(str: []const u8) void {
            console_log(str.ptr, str.len);
        }

        pub fn log_1024(comptime fmt: []const u8, args: anytype) void {
            var buffer: [1024*2]u8 = undefined;
            log(std.fmt.bufPrint(&buffer, fmt, args) catch |e| Platform.panic(e));
        }
    };
};

/// This buffer is used as a communications buffer between js and wasm
var wasm_interface_buffer: [256]u8 = undefined;
pub export fn wasm_get_interface_buffer() [*]u8 {
    return @ptrCast(&wasm_interface_buffer);
}

/// NOTE the pointer provided is basically an offset in the wasm module memory
/// provided byt the wasm runtime
pub export fn wasm_get_pixel_buffer_ptr() [*]u8 {
    return @ptrCast(state.pixel_buffer.data.ptr);
}

pub export fn wasm_get_canvas_size(out_w: *u32, out_h: *u32) void {
    out_w.* = state.pixel_buffer.width;
    out_h.* = state.pixel_buffer.height;
}

pub export fn wasm_send_event(len: usize, a: usize, b: usize) void {
    const event: []u8 = wasm_interface_buffer[0..len];
    external.util.log_1024("event received {s}", .{event});
    var tokens = std.mem.tokenize(u8, event, ":");
    var event_type = tokens.next().?;
    if (std.mem.eql(u8, event_type, "mouse")) {
        if (std.mem.eql(u8, tokens.next().?, "down")) {
            state.page_index += 1;
        }
    }
    else if (std.mem.eql(u8, event_type, "buffer")) {
        const id = tokens.next().?;
        const data: struct { ptr: [*]u8, len: usize } = .{ .ptr = @ptrFromInt(a), .len = b };
        tasks.finish(id, data);
    }
}

pub export fn wasm_request_buffer(len: usize) [*]u8 {
    external.util.log_1024("buffer request received {}", .{len});
    return (wasm.allocator.alloc(u8, len) catch |e| Platform.panic(e)).ptr;
}

pub export fn wasm_init() void {
    init();
}
pub export fn wasm_tick() void {
    update();
}

pub const TaskManager = struct {
    const CallbackType = fn(context_register: []const u8, context_finish: []const u8) void;
    const Task = struct {
        callback: *const CallbackType,
        context: []const u8
    };

    arena: std.heap.ArenaAllocator,
    /// key: the id of the task. value: the task itself, which contains a callback and a context provided to the callback on execution.
    tasks: std.StringHashMap(Task),
    
    pub fn init(allocator: std.mem.Allocator) TaskManager {
        var arena = std.heap.ArenaAllocator.init(allocator);
        var task_map = std.StringHashMap(Task).init(allocator);
        return .{
            .arena = arena,
            .tasks = task_map,
        };
    }

    pub fn deinit(self: *TaskManager) void {
        self.tasks.deinit();
        self.arena.deinit();
    }
    
    /// clones context and id and manages internally
    pub fn register(self: *TaskManager, id: []const u8, cb: *const CallbackType, context_value: anytype) void {
        const context_size = @sizeOf(@TypeOf(context_value));
        // allocate enough space to store the task until it gets completed and freed on `finish`
        const size = context_size+id.len;
        var task_storage = self.arena.allocator().alloc(u8, size) catch |e| Platform.panic(e);
        var id_storage: []u8 = task_storage[0..id.len];
        var context_storage: []u8 = task_storage[id.len..size];
        std.debug.assert(context_size == context_storage.len);
        std.mem.copy(u8, id_storage, id);
        std.mem.copy(u8, context_storage, byte_slice(&context_value));        
        // the task itself just contains a pointer to the context (its memory is manually managed), and a pointer to the callback (which is static code, so no need to manage its lifetime)
        self.tasks.put(id_storage, .{ .callback = cb, .context = context_storage }) catch |e| Platform.panic(e);
    }

    pub fn finish(self: *TaskManager, id: []const u8, context_value: anytype) void {
        const task = self.tasks.get(id).?;
        task.callback(task.context, byte_slice(&context_value));
        _ = self.tasks.remove(id);
    }

};

/// given a pointer to a value, returns a const byte slice of the underlying bytes
fn byte_slice(v_ptr: anytype) []const u8 {
    return @as([]const u8, @as([*]const u8, @ptrCast(v_ptr))[0..@sizeOf(@typeInfo(@TypeOf(v_ptr)).Pointer.child)]);
}

/// from byte slice to value
fn value(out_ptr: anytype, bytes: []const u8) void {
    const bs: []u8 = @as([*]u8, @ptrCast(out_ptr))[0..@sizeOf(@typeInfo(@TypeOf(out_ptr)).Pointer.child)];
    @memcpy(bs, bytes);
}

pub const Platform = struct {
    // const memory_info = @import("comptime_memory_info");
    
    fba: std.heap.FixedBufferAllocator,
    allocator: std.mem.Allocator,
    random: std.rand.Random,
    random_internal_implementation: std.rand.Xoshiro256,
    
    __memory_base: [*]u8,
    __table_base: [*]u8,
    __stack_pointer: [*]u8,
    __data_end: [*]u8,
    __heap_base: [*]u8,
    __heap_end: [*]u8,
    
    orig_vtable: *const std.mem.Allocator.VTable,

    pub fn init(platform: *Platform, random_seed: u64) void {

        platform.random_internal_implementation = std.rand.DefaultPrng.init(random_seed);
        platform.random = platform.random_internal_implementation.random();

        // https://github.com/WebAssembly/tool-conventions/blob/main/DynamicLinking.md
        platform.__memory_base = @extern(?[*]u8, .{.name = "__memory_base"}).?; external.util.log_1024("__memory_base {any} {}", .{platform.__memory_base, @as(usize, @intFromPtr(platform.__memory_base))});
        platform.__table_base = @extern(?[*]u8, .{.name = "__table_base"}).?; external.util.log_1024("__table_base {any} {}", .{platform.__table_base, @as(usize, @intFromPtr(platform.__table_base))});
        platform.__stack_pointer = @extern(?[*]u8, .{.name = "__stack_pointer"}).?; external.util.log_1024("__stack_pointer {any} {}", .{platform.__stack_pointer, @as(usize, @intFromPtr(platform.__stack_pointer))});
        platform.__data_end = @extern(?[*]u8, .{.name = "__data_end"}).?; external.util.log_1024("__data_end {any} {}", .{platform.__data_end, @as(usize, @intFromPtr(platform.__data_end))});
        platform.__heap_base = @extern(?[*]u8, .{.name = "__heap_base"}).?; external.util.log_1024("__heap_base {any} {}", .{platform.__heap_base, @as(usize, @intFromPtr(platform.__heap_base))});
        platform.__heap_end = @extern(?[*]u8, .{.name = "__heap_end"}).?; external.util.log_1024("__heap_end {any} {}", .{platform.__heap_end, @as(usize, @intFromPtr(platform.__heap_end))});
        
        var zero: [*]allowzero u8 = @ptrFromInt(0);
        var heap: []u8 = @ptrCast(zero[@intFromPtr(platform.__heap_base)..@intFromPtr(platform.__heap_end)]);
        external.util.log_1024("heap length {}", .{heap.len});
        platform.fba = std.heap.FixedBufferAllocator.init(heap);
        platform.orig_vtable = platform.fba.allocator().vtable;
        platform.allocator = .{
            .ptr = &platform.fba,
            .vtable = &.{
                .alloc = wrappers.alloc,
                .resize = wrappers.resize,
                .free = wrappers.free,
            },
        };

    }

    const wrappers = struct {
        fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            const res = wasm.orig_vtable.alloc(ctx, len, ptr_align, ret_addr);
            external.util.log_1024("Allocator alloc {} at {any}", .{len, res});
            return res;
        }
        fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            const res = wasm.orig_vtable.resize(ctx, buf, buf_align, new_len, ret_addr);
            external.util.log_1024("Allocator resize from {} at {any} to {} -> {}", .{buf.len, buf.ptr, new_len, res});
            return res;
        }
        fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            external.util.log_1024("Allocator free {} bytes at {any}", .{buf.len, buf.ptr});
            wasm.orig_vtable.free(ctx, buf, buf_align, ret_addr);
        }
    };

    pub fn slice(ptr: [*]u8, len: usize) []u8 {
        return ptr[0..len];
    }
    
    pub fn panic(e: anyerror) noreturn {
        external.util.log_1024("panic {any}", .{e});
        @panic("ERROR");
    }
};

const math = @import("math.zig");
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vector4f = math.Vector4f;
const M44 = math.M44;
// const OBJ = @import("obj.zig");
// const TGA = @import("tga.zig");
// const imgui = @import("imgui.zig");
const Buffer2D = @import("buffer.zig").Buffer2D;
const RGBA = @import("pixels.zig").RGBA;
const RGB = @import("pixels.zig").RGB;
const GraphicsPipelineConfiguration = @import("graphics.zig").GraphicsPipelineConfiguration;
const GraphicsPipeline = @import("graphics.zig").GraphicsPipeline;

const GouraudShader = @import("shaders/gouraud.zig").Shader(RGBA, RGB);
const QuadShaderRgb = @import("shaders/quad.zig").Shader(RGBA, RGB, false, false);
const QuadShaderRgba = @import("shaders/quad.zig").Shader(RGBA, RGBA, false, false);
const TextRenderer = @import("text.zig").TextRenderer(RGBA, 1024, 1024);

const Camera = struct {
    position: Vector3f,
    direction: Vector3f,
    up: Vector3f,
};

const State = struct {
    running: bool,
    mouse: Vector2i,
    keys: [256]bool,
    time: f64,
    
    pixel_buffer: Buffer2D(RGBA),
    depth_buffer: Buffer2D(f32),
    texture: Buffer2D(RGB),
    vertex_buffer: []f32,
    camera: Camera,
    view_matrix: M44,
    viewport_matrix: M44,
    projection_matrix: M44,
    frame_index: usize,
    
    text_renderer: TextRenderer,
    page_index: usize,
};

var tasks: TaskManager = undefined;
var wasm: Platform = undefined;
var state: State = undefined;

fn init() void {
    external.util.log("Initializing...");
    wasm.init(external.milli_since_epoch());
    const w: usize = 420;
    const h: usize = 340;
    var pixel_buffer = Buffer2D(RGBA).from(wasm.allocator.alloc(RGBA, w*h) catch |e| Platform.panic(e), w);
    var text_renderer = TextRenderer.init(wasm.allocator, pixel_buffer) catch |e| Platform.panic(e);
    var depth_buffer = Buffer2D(f32).from(wasm.allocator.alloc(f32, @intCast(pixel_buffer.width * pixel_buffer.height)) catch |e| Platform.panic(e), @intCast(pixel_buffer.width));
    const file = "index.html";
    tasks = TaskManager.init(wasm.allocator);
    tasks.register(file, struct {
        fn f(regist_context: []const u8, completion_context: []const u8) void {
            var cc: struct { ptr: [*]u8, len: usize } = undefined;
            var rc: struct { texture: *Buffer2D(RGB) } = undefined;
            value(&rc, regist_context);
            value(&cc, completion_context);
            external.util.log_1024("gotta load index.html located at {d} len {} into texture {d}", .{@intFromPtr(cc.ptr), cc.len, @intFromPtr(rc.texture) });
            defer wasm.allocator.free(cc.ptr[0..cc.len]);
        }
    }.f, struct { texture: *Buffer2D(RGB) } { .texture = &state.texture });
    external.fetch(file.ptr, file.len);

    // state.texture = TGA.from_file(RGB, allocator, "res/african_head_diffuse.tga")
    //     catch |err| { std.debug.print("error reading `res/african_head_diffuse.tga` {?}", .{err}); return; };
    // state.vertex_buffer = OBJ.from_file(allocator, "res/african_head.obj")
    //     catch |err| { std.debug.print("error reading `res/african_head.obj` {?}", .{err}); return; };
    var camera = Camera {
        .position = Vector3f { .x = 0, .y = 0, .z = 0 },
        .up = Vector3f { .x = 0, .y = 1, .z = 0 },
        .direction = Vector3f { .x = 0, .y = 0, .z = 1 },
    };
    state = .{
        .pixel_buffer = pixel_buffer,
        .running = true,
        .mouse = undefined,
        .keys = [1]bool{false} ** 256,
        .depth_buffer = depth_buffer,
        .texture = undefined,
        .vertex_buffer = undefined,
        .camera = camera,
        .view_matrix = undefined,
        .viewport_matrix = undefined,
        .projection_matrix = undefined,
        .frame_index = 0,
        .time = 0,
        .text_renderer = text_renderer,
        .page_index = 0
    };
}

fn update() void {
    state.pixel_buffer.clear(RGBA.make(100, 149, 237,255));
    state.depth_buffer.clear(999999);

    const looking_at: Vector3f = state.camera.position.add(state.camera.direction);                
    state.view_matrix = M44.lookat_right_handed(state.camera.position, looking_at, Vector3f.from(0, 1, 0));
    const aspect_ratio = -@as(f32, @floatFromInt(state.pixel_buffer.width)) / @as(f32, @floatFromInt(state.pixel_buffer.height));
    state.projection_matrix = M44.perspective_projection(60, aspect_ratio, 0.1, 5);
    state.viewport_matrix = M44.viewport_i32_2(0, 0, @intCast(state.pixel_buffer.width), @intCast(state.pixel_buffer.height), 255);

    // render the font texture as a quad
    if (true) {
        const texture = @import("text.zig").font.texture;
        const w: f32 = @floatFromInt(texture.width);
        const h: f32 = @floatFromInt(texture.height);
        const vertex_buffer = [_]QuadShaderRgba.Vertex{
            .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
            .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=0} },
            .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=1} },
            .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=1} },
        };
        const index_buffer = [_]u16{0,1,2,0,2,3};
        var quad_context = QuadShaderRgba.Context {
            .texture = texture,
            .projection_matrix =
                state.projection_matrix.multiply(
                    state.view_matrix.multiply(
                        M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1 }).multiply(M44.scale(1/@as(f32, @floatFromInt(texture.width))))
                    )
                ),
        };
        const requirements = QuadShaderRgba.pipeline_configuration.Requirements() {
            .depth_buffer = state.depth_buffer,
            .viewport_matrix = state.viewport_matrix,
            .index_buffer = &index_buffer,
        };
        QuadShaderRgba.Pipeline.render(state.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
    }

    state.text_renderer.print(Vector2i { .x = 10, .y = @intCast(state.pixel_buffer.height-10) }, "camera {d:.8}, {d:.8}, {d:.8}", .{state.camera.position.x, state.camera.position.y, state.camera.position.z}) catch |e| Platform.panic(e);
    state.text_renderer.print(Vector2i { .x = 10, .y = @intCast(state.pixel_buffer.height-10 - (12*1)) }, "direction {d:.8}, {d:.8}, {d:.8}", .{state.camera.direction.x, state.camera.direction.y, state.camera.direction.z}) catch |e| Platform.panic(e);
    state.text_renderer.render_all(
        M44.orthographic_projection(0, @floatFromInt(state.pixel_buffer.width), 0, @floatFromInt(state.pixel_buffer.height), 0, 10),
        state.viewport_matrix
    );

    state.frame_index += 1;
}


fn visualize_bytes(pixel_buffer: Buffer2D(RGBA), bytes_to_display: []u8) void {
    // TODO use channels to differentiate stack heap static etc
    var bytes: []u8 = bytes_to_display;
    const showable_bytes = pixel_buffer.data.len * 3;
    if (bytes_to_display.len > showable_bytes) {
        bytes = bytes_to_display[0..showable_bytes];
    }

    const pixels_to_be_used = @divFloor(bytes.len, 3);
    for (pixel_buffer.data[0..pixels_to_be_used], 0..) |*p, i| {
        p.* = RGBA { .r = bytes[i*3 + 0], .g = bytes[i*3 + 1], .b = bytes[i*3 + 2], .a = 255, };
    }
    
    const extra_bytes = @mod(bytes.len, 3);
    if (pixels_to_be_used < pixel_buffer.data.len and extra_bytes != 0) {
        std.debug.assert(extra_bytes == 1 or extra_bytes == 2);
        if (extra_bytes >= 1) pixel_buffer.data[pixels_to_be_used+1].r = bytes[pixels_to_be_used+1*3 + 0];
        if (extra_bytes >= 2) pixel_buffer.data[pixels_to_be_used+1].g = bytes[pixels_to_be_used+1*3 + 1];
    }
}
