const std = @import("std");

// functions provided by the wasm module caller (in js, the `env` object passed to `instantiateStreaming`)
const external = struct {
    pub extern fn console_log(str: [*]const u8, len: usize) void;
    pub extern fn milli_since_epoch() usize;

    const util = struct {
        
        pub fn log(str: []const u8) void {
            console_log(str.ptr, str.len);
        }

        pub fn log_1024(comptime fmt: []const u8, args: anytype) void {
            var buffer: [1024*10]u8 = undefined;
            log (std.fmt.bufPrint(&buffer, fmt, args) catch @panic("used log_1024 on string longer than 1024 bytes"));
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

pub export fn wasm_send_event(len: usize) void {
    const event: []u8 = wasm_interface_buffer[0..len];
    var tokens = std.mem.tokenize(u8, event, ".");
    if (std.mem.eql(u8, tokens.next().?, "mouse")) {
        if (std.mem.eql(u8, tokens.next().?, "down")) {
            state.page_index += 1;
        }
    }
}

pub export fn wasm_init() void {
    init();
}
pub export fn wasm_tick() void {
    update();
}

pub const Platform = struct {
    /// memory_info is a compile time generated file that has information on how the module
    /// was generated, such as stack size, max memory, etc...
    const memory_info = @import("comptime_memory_info");
    
    all: []u8,
    memory: std.heap.FixedBufferAllocator,
    random: std.rand.Random,
    random_internal_implementation: std.rand.Xoshiro256,
    heap_base: usize,
    total_mem: usize,
    stack_size: usize,
    
    pub fn init(random_seed: u64) Platform {
        var aux = std.rand.DefaultPrng.init(random_seed);

        if (memory_info.initial_memory != memory_info.max_memory) @panic("memory_info.initial_memory != memory_info.max_memory");
        // > __heap_base is where the statically allocated memory ends,and __heap_end is the value of the initial memory
        // > (either passed by --initial-memory or __heap_base), aligned to page size.
        // > `heap_base` is a special symbol provided by the linker during linking phase.
        // - Luuk
        const heap_base = @extern(?[*]u8, .{.name = "__heap_base"}).?;
        
        const heap_base_int = @intFromPtr(heap_base);
        // TODO This might not be necessary since the heap_base might be aligned by default?
        const heap_base_int_aligned_16 = std.mem.alignForward(usize, heap_base_int, 16);
        const size_of_total_free_memory = memory_info.max_memory - heap_base_int_aligned_16;
        const memory = @as([*]u8, @ptrFromInt(heap_base_int_aligned_16))[0..size_of_total_free_memory];
        // const size_of_static_data_section = heap_base_int - memory_info.global_base;
        // const padding = heap_base_int_aligned_16 - heap_base_int;
        const zero: [*]allowzero u8 = @ptrFromInt(0);
        return Platform {
            .memory = std.heap.FixedBufferAllocator.init(memory),
            .random = aux.random(),
            .random_internal_implementation = aux,
            .heap_base = @intFromPtr(heap_base),
            .total_mem = memory_info.max_memory,
            .stack_size = memory_info.stack_size,
            .all = zero[0..memory_info.max_memory]
        };
    }

};

// APP

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

var wasm: Platform = undefined;
var state: State = undefined;

fn init() void {
    wasm = Platform.init(external.milli_since_epoch());
    external.util.log("Initialized");
    const w: usize = 420;
    const h: usize = 340;
    var pixel_buffer = Buffer2D(RGBA).from(wasm.memory.allocator().alloc(RGBA, w*h) catch @panic("OOM"), w);
    var text_renderer = TextRenderer.init(wasm.memory.allocator(), pixel_buffer) catch @panic("OOM");
    var depth_buffer = Buffer2D(f32).from(wasm.memory.allocator().alloc(f32, @intCast(pixel_buffer.width * pixel_buffer.height)) catch @panic("OOM"), @intCast(pixel_buffer.width));
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

    if (false) {
        const bytes_per_page = state.pixel_buffer.data.len*3;
        const total_pages = @divFloor(wasm.all.len, bytes_per_page) + @as(usize, if (@mod(wasm.all.len, bytes_per_page) != 0) 1 else 0);
        if (state.page_index>=total_pages) state.page_index = 0;
        external.util.log_1024("page: {}", .{state.page_index});
        visualize_bytes(state.pixel_buffer, wasm.all[state.page_index*bytes_per_page..@min(state.page_index*bytes_per_page+bytes_per_page, wasm.all.len)]);
    }

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

    state.text_renderer.print(Vector2i { .x = 10, .y = @intCast(state.pixel_buffer.height-10) }, "camera {d:.8}, {d:.8}, {d:.8}", .{state.camera.position.x, state.camera.position.y, state.camera.position.z}) catch @panic("OOM");
    state.text_renderer.print(Vector2i { .x = 10, .y = @intCast(state.pixel_buffer.height-10 - (12*1)) }, "direction {d:.8}, {d:.8}, {d:.8}", .{state.camera.direction.x, state.camera.direction.y, state.camera.direction.z}) catch @panic("OOM");
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
