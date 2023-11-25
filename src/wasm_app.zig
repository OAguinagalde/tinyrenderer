const std = @import("std");
const core = @import("core.zig");
const platform = @import("wasm.zig");
const Runtime = platform.Runtime;
const TaskManager = @import("TaskManager.zig");
const math = @import("math.zig");
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vector4f = math.Vector4f;
const M44 = math.M44;
const OBJ = @import("obj.zig");
const TGA = @import("tga.zig");
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
    vertex_buffer: std.ArrayList(GouraudShader.Vertex),
    camera: Camera,
    view_matrix: M44,
    viewport_matrix: M44,
    projection_matrix: M44,
    frame_index: usize,
    
    text_renderer: TextRenderer,
    page_index: usize,
};

// This is necessary so that the exported functions are referenced and zig actually compiles it
comptime { _ = @import("wasm.zig"); }
pub const callbacks = struct {


    pub fn get_static_buffer() []u8 {
        return &static_buffer_for_runtime_use;
    }
    pub fn get_canvas_pixels() *void {
        return @ptrCast(state.pixel_buffer.data.ptr);
    }
    pub fn get_canvas_size() platform.Callbacks.Dimensions {
        return .{
            .w = state.pixel_buffer.width,
            .h = state.pixel_buffer.height
        };
    }
    pub fn send_event(event: []const u8, a: usize, b: usize) void {
        platform.flog("event received {s}", .{event});
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
            tasks.?.finish(id, data);
        }
    }
    pub fn request_buffer(len: usize) []u8 {
        return runtime.allocator.alloc(u8, len) catch |e| panic(e);
    }
    pub fn init() void {
        initialize();
    }
    pub fn tick() void {
        update();
    }
};

fn panic(e: anyerror) noreturn {
    // NOTE for some reason when wasm panichs with a message the message is not exposed in the browser, hence the separate log message
    platform.flog("panic {any}", .{e});
    @panic("ERROR");
}

var tasks: ?TaskManager = undefined;
var runtime: Runtime = undefined;
var state: State = undefined;
var static_buffer_for_runtime_use: [1024]u8 = undefined;

fn initialize() void {
    platform.flog("Initializing...", .{});
    runtime.init(platform.milli_since_epoch());
    tasks = TaskManager.init(runtime.allocator);

    state.running = true;
    state.keys = [1]bool{false} ** 256;
    state.pixel_buffer = Buffer2D(RGBA).from(runtime.allocator.alloc(RGBA, 420*340) catch |e| panic(e), 420);
    state.depth_buffer = Buffer2D(f32).from(runtime.allocator.alloc(f32, @intCast(state.pixel_buffer.width * state.pixel_buffer.height)) catch |e| panic(e), @intCast(state.pixel_buffer.width));
    state.text_renderer = TextRenderer.init(runtime.allocator, state.pixel_buffer) catch |e| panic(e);
    state.texture = undefined;
    state.mouse = undefined;
    state.vertex_buffer = undefined;
    state.camera = Camera {
        .position = Vector3f { .x = 0, .y = 0, .z = 0 },
        .up = Vector3f { .x = 0, .y = 1, .z = 0 },
        .direction = Vector3f { .x = 0, .y = 0, .z = 1 },
    };
    state.view_matrix = undefined;
    state.viewport_matrix = undefined;
    state.projection_matrix = undefined;
    state.frame_index = 0;
    state.time = 0;
    state.page_index = 0;

    _ = callbacks.get_canvas_pixels();

    const texture_file = "res/african_head_diffuse.tga";
    tasks.?.register(texture_file, struct {
        fn f(regist_context: []const u8, completion_context: []const u8) void {
            var cc: struct { ptr: [*]u8, len: usize } = undefined;
            var rc: struct { texture: *Buffer2D(RGB) } = undefined;
            core.value(&rc, regist_context);
            core.value(&cc, completion_context);
            const file_bytes = cc.ptr[0..cc.len];
            defer runtime.allocator.free(file_bytes);
            state.texture = TGA.from_bytes(RGB, runtime.allocator, file_bytes) catch |e| panic(e);
        }
    }.f, struct { texture: *Buffer2D(RGB) } { .texture = &state.texture }) catch |e| panic(e);
    platform.fetch(texture_file.ptr, texture_file.len);

    const model_file = "res/african_head.obj";
    tasks.?.register(model_file, struct {
        fn f(regist_context: []const u8, completion_context: []const u8) void {
            var cc: struct { ptr: [*]u8, len: usize } = undefined;
            var rc: struct { texture: *Buffer2D(RGB) } = undefined;
            core.value(&rc, regist_context);
            core.value(&cc, completion_context);
            const file_bytes = cc.ptr[0..cc.len];
            defer runtime.allocator.free(file_bytes);
            state.vertex_buffer = blk: {
                const buffer = OBJ.from_bytes(runtime.allocator, file_bytes) catch |e| panic(e);
                var i: usize = 0;
                var vertex_buffer = std.ArrayList(GouraudShader.Vertex).initCapacity(runtime.allocator, @divExact(buffer.len, 8)) catch |e| panic(e);
                while (i < buffer.len) : (i = i + 8) {
                    const pos: Vector3f = .{ .x=buffer[i+0], .y=buffer[i+1], .z=buffer[i+2] };
                    const uv: Vector2f = .{ .x=buffer[i+3], .y=buffer[i+4] };
                    const normal: Vector3f = .{ .x=buffer[i+5], .y=buffer[i+6], .z=buffer[i+7] };
                    vertex_buffer.appendAssumeCapacity(.{ .pos = pos, .uv = uv, .normal = normal });
                }
                break :blk vertex_buffer;
            };
        }
    }.f, struct { texture: *Buffer2D(RGB) } { .texture = &state.texture }) catch |e| panic(e);
    platform.fetch(model_file.ptr, model_file.len);

}

fn update() void {

    // wait for every task registered at init() to finish
    if (tasks) |tm| {
        if (!tm.finished()) return;
        tasks.?.deinit();
        tasks = null;
    }

    state.pixel_buffer.clear(RGBA.make(100, 149, 237,255));
    state.depth_buffer.clear(999999);

    const looking_at: Vector3f = state.camera.position.add(state.camera.direction);                
    state.view_matrix = M44.lookat_right_handed(state.camera.position, looking_at, Vector3f.from(0, 1, 0));
    const aspect_ratio = @as(f32, @floatFromInt(state.pixel_buffer.width)) / @as(f32, @floatFromInt(state.pixel_buffer.height));
    state.projection_matrix = M44.perspective_projection(60, aspect_ratio, 0.1, 5);
    state.viewport_matrix = M44.viewport_i32_2(0, 0, @intCast(state.pixel_buffer.width), @intCast(state.pixel_buffer.height), 255);

    // render the model texture as a quad
    if (false) {
        const w: f32 = @floatFromInt(state.texture.width);
        const h: f32 = @floatFromInt(state.texture.height);
        var quad_context = QuadShaderRgb.Context {
            .texture = state.texture,
            .projection_matrix =
                state.projection_matrix.multiply(
                    state.view_matrix.multiply(
                        M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1.5 }).multiply(M44.scale(1/w))
                    )
                ),
        };
        const vertex_buffer = [_]QuadShaderRgb.Vertex{
            .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=1} },
            .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=1} },
            .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=0} },
            .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=0} },
        };
        const index_buffer = [_]u16{0,1,2,0,2,3};
        const requirements = QuadShaderRgb.pipeline_configuration.Requirements() {
            .depth_buffer = state.depth_buffer,
            .viewport_matrix = state.viewport_matrix,
            .index_buffer = &index_buffer,
        };
        QuadShaderRgb.Pipeline.render(state.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
    }

    // render the font texture as a quad
    if (false) {
        const texture = @import("text.zig").font.texture;
        const w: f32 = @floatFromInt(texture.width);
        const h: f32 = @floatFromInt(texture.height);
        const vertex_buffer = [_]QuadShaderRgba.Vertex{
            .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=1} },
            .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=1} },
            .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=0} },
            .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=0} },
        };
        const index_buffer = [_]u16{0,1,2,0,2,3};
        var quad_context = QuadShaderRgba.Context {
            .texture = texture,
            .projection_matrix =
                state.projection_matrix.multiply(
                    state.view_matrix.multiply(
                        M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1 }).multiply(M44.scale(1/w))
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

    // Example rendering OBJ model with Gouraud Shading
    if (true) {
        const horizontally_spinning_position = Vector3f {
            .x = std.math.cos(@as(f32, @floatFromInt(state.frame_index)) / 10),
            .y = 0,
            .z = 1 + std.math.sin(@as(f32, @floatFromInt(state.frame_index)) / 10)
        };
        const render_context = GouraudShader.Context {
            .light_position_camera_space = state.view_matrix.apply_to_vec3(horizontally_spinning_position).discard_w(),
            .projection_matrix = state.projection_matrix,
            .texture = state.texture,
            .texture_height = state.texture.height,
            .texture_width = state.texture.width,
            .view_model_matrix = state.view_matrix.multiply(
                M44.translation(Vector3f { .x = 0, .y = 0, .z = 1 }).multiply(M44.scaling_matrix(Vector3f.from(0.5, 0.5, 0.5)))
            ),
        };
        const render_requirements: GouraudShader.pipeline_configuration.Requirements() = .{
            .depth_buffer = state.depth_buffer,
            .viewport_matrix = state.viewport_matrix,
        };
        GouraudShader.Pipeline.render(state.pixel_buffer, render_context, state.vertex_buffer.items, @divExact(state.vertex_buffer.items.len, 3), render_requirements);
    }

    state.text_renderer.print(Vector2i { .x = 3, .y = 0 }, "wasm!", .{}) catch |e| panic(e);
    state.text_renderer.print(Vector2i { .x = 10, .y = @intCast(state.pixel_buffer.height-10) }, "camera {d:.8}, {d:.8}, {d:.8}", .{state.camera.position.x, state.camera.position.y, state.camera.position.z}) catch |e| panic(e);
    state.text_renderer.print(Vector2i { .x = 10, .y = @intCast(state.pixel_buffer.height-10 - (12*1)) }, "direction {d:.8}, {d:.8}, {d:.8}", .{state.camera.direction.x, state.camera.direction.y, state.camera.direction.z}) catch |e| panic(e);
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
