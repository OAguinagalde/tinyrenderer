const std = @import("std");
const builtin = @import("builtin");
const core = @import("core.zig");
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
const BGRA = @import("pixels.zig").BGRA;
const RGBA = @import("pixels.zig").RGBA;
const RGB = @import("pixels.zig").RGB;
const GraphicsPipelineConfiguration = @import("graphics.zig").GraphicsPipelineConfiguration;
const GraphicsPipeline = @import("graphics.zig").GraphicsPipeline;
const wasm = @import("wasm.zig");
const windows =  @import("windows.zig");
const Platform = if (builtin.os.tag == .windows) windows.Platform else wasm.Platform;
const ScreenPixelType = if (builtin.os.tag == .windows) BGRA else RGBA;

const GouraudShader = @import("shaders/gouraud.zig").Shader(ScreenPixelType, RGB);
const QuadShaderRgb = @import("shaders/quad.zig").Shader(ScreenPixelType, RGB, false, false);
const QuadShaderRgba = @import("shaders/quad.zig").Shader(ScreenPixelType, RGBA, false, false);
const TextRenderer = @import("text.zig").TextRenderer(ScreenPixelType, 1024, 1024);

const Camera = struct {
    position: Vector3f,
    direction: Vector3f,
    looking_at: Vector3f,
    up: Vector3f,
};

const App = struct {
    text_renderer: TextRenderer,
    depth_buffer: Buffer2D(f32),
    texture: Buffer2D(RGB),
    vertex_buffer: std.ArrayList(GouraudShader.Vertex),
    camera: Camera,
    time: f64,
    page_index: usize,
};

var app: App = undefined;

const ReadTgaContext = struct {
    allocator: std.mem.Allocator,
    texture: *Buffer2D(RGB)
};
fn read_tga_texture(bytes: []const u8, context: []const u8) !void {
    var ctx: ReadTgaContext = undefined;
    core.value(&ctx, context);
    defer ctx.allocator.free(bytes);
    ctx.texture.* = try TGA.from_bytes(RGB, ctx.allocator, bytes);
}
const ReadObjContext = struct {
    allocator: std.mem.Allocator,
    vertex_buffer: *std.ArrayList(GouraudShader.Vertex)
};
fn read_obj_model(bytes: []const u8, context: []const u8) !void {
    var ctx: ReadObjContext = undefined;
    core.value(&ctx, context);
    defer ctx.allocator.free(bytes);
    ctx.vertex_buffer.* = blk: {
        const buffer = try OBJ.from_bytes(ctx.allocator, bytes);
        defer ctx.allocator.free(buffer);
        var i: usize = 0;
        var vertex_buffer = try std.ArrayList(GouraudShader.Vertex).initCapacity(ctx.allocator, @divExact(buffer.len, 8));
        while (i < buffer.len) : (i = i + 8) {
            const pos: Vector3f = .{ .x=buffer[i+0], .y=buffer[i+1], .z=buffer[i+2] };
            const uv: Vector2f = .{ .x=buffer[i+3], .y=buffer[i+4] };
            const normal: Vector3f = .{ .x=buffer[i+5], .y=buffer[i+6], .z=buffer[i+7] };
            vertex_buffer.appendAssumeCapacity(.{ .pos = pos, .uv = uv, .normal = normal });
        }
        break :blk vertex_buffer;
    };
}

pub fn init(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(ScreenPixelType)) !void {
    app.depth_buffer = Buffer2D(f32).from(try allocator.alloc(f32, @intCast(pixel_buffer.width * pixel_buffer.height)), @intCast(pixel_buffer.width));
    app.camera.position = Vector3f { .x = 0, .y = 0, .z = 0 };
    app.camera.up = Vector3f { .x = 0, .y = 1, .z = 0 };
    app.camera.direction = Vector3f { .x = 0, .y = 0, .z = 1 };
    app.time = 0;
    app.text_renderer = try TextRenderer.init(allocator, pixel_buffer);

    if (builtin.os.tag == .windows) {
        app.texture = try TGA.from_file(RGB, allocator, "res/african_head_diffuse.tga");
        app.vertex_buffer = blk: {
            const buffer = try OBJ.from_file(allocator, "res/african_head.obj");
            defer allocator.free(buffer);
            var i: usize = 0;
            var vertex_buffer = try std.ArrayList(GouraudShader.Vertex).initCapacity(allocator, @divExact(buffer.len, 8));
            while (i < buffer.len) : (i = i + 8) {
                const pos: Vector3f = .{ .x=buffer[i+0], .y=buffer[i+1], .z=buffer[i+2] };
                const uv: Vector2f = .{ .x=buffer[i+3], .y=buffer[i+4] };
                const normal: Vector3f = .{ .x=buffer[i+5], .y=buffer[i+6], .z=buffer[i+7] };
                vertex_buffer.appendAssumeCapacity(.{ .pos = pos, .uv = uv, .normal = normal });
            }
            break :blk vertex_buffer;
        };
    }
    else {
        app.texture = undefined;
        try wasm.read_file("res/african_head_diffuse.tga", read_tga_texture, ReadTgaContext { .allocator = allocator, .texture = &app.texture });

        app.vertex_buffer = undefined;
        try wasm.read_file("res/african_head.obj", read_obj_model, ReadObjContext { .allocator = allocator, .vertex_buffer = &app.vertex_buffer });
    }
}

pub fn update(platform: *Platform) !bool {
    
    platform.pixel_buffer.clear(ScreenPixelType.make(100, 149, 237,255));
    app.depth_buffer.clear(999999);

    app.time += platform.ms;

    // camera movement with mouse
    const mouse_sensitivity = 0.01;
    const up = Vector3f {.x = 0, .y = 1, .z = 0 };
    const real_right = app.camera.direction.cross_product(up).scale(-1).normalized();
    const real_up = app.camera.direction.cross_product(real_right).normalized();
    if (platform.mouse_d.x != 0 or platform.mouse_d.y != 0) {
        app.camera.direction = app.camera.direction.add(real_right.scale(@as(f32, @floatFromInt(platform.mouse_d.x))*mouse_sensitivity));
        if (app.camera.direction.y < 0.95 and app.camera.direction.y > -0.95) {
            app.camera.direction = app.camera.direction.add(real_up.scale(-@as(f32, @floatFromInt(platform.mouse_d.y))*mouse_sensitivity));
        }
        app.camera.direction.normalize();
    }
    
    // camera position with AWSD and QE
    const unit: f32 = 0.02*(platform.ms / 16.6666);
    if (platform.keys['W']) app.camera.position = app.camera.position.add(app.camera.direction.scale(unit));
    if (platform.keys['S']) app.camera.position = app.camera.position.add(app.camera.direction.scale(-unit));
    if (platform.keys['A']) app.camera.position = app.camera.position.add(real_right.scale(-unit));
    if (platform.keys['D']) app.camera.position = app.camera.position.add(real_right.scale(unit));
    if (platform.keys['Q']) app.camera.position.y += unit;
    if (platform.keys['E']) app.camera.position.y -= unit;

    // calculate view_matrix, projection_matrix and viewport_matrix
    const looking_at: Vector3f = app.camera.position.add(app.camera.direction);
    const view_matrix = M44.lookat_left_handed(app.camera.position, looking_at, Vector3f.from(0, 1, 0));
    const aspect_ratio = @as(f32, @floatFromInt(platform.w)) / @as(f32, @floatFromInt(platform.h));
    const projection_matrix = M44.perspective_projection(60, aspect_ratio, 0.1, 255);
    const viewport_matrix = M44.viewport_i32_2(0, 0, platform.w, platform.h, 255);

    // Example rendering OBJ model with Gouraud Shading
    if (true) {
        const horizontally_spinning_position = Vector3f { .x = std.math.cos(@as(f32, @floatCast(app.time)) / 2000), .y = 0, .z = 4 + std.math.sin(@as(f32, @floatCast(app.time)) / 2000) };
        const render_context = GouraudShader.Context {
            .light_position_camera_space = view_matrix.apply_to_vec3(horizontally_spinning_position).discard_w(),
            .projection_matrix = projection_matrix,
            .texture = app.texture,
            .texture_height = app.texture.height,
            .texture_width = app.texture.width,
            .view_model_matrix = view_matrix.multiply(
                M44.translation(Vector3f { .x = 0, .y = 0, .z = 4 }).multiply(M44.scaling_matrix(Vector3f.from(0.5, 0.5, -0.5)))
            ),
        };
        // var i: usize = 0;
        // var vertex_buffer = std.ArrayList(GouraudShader.Vertex).initCapacity(platform.allocator, @divExact(app.vertex_buffer.len, 8)) catch unreachable;
        // defer vertex_buffer.clearAndFree();
        // while (i < app.vertex_buffer.len) : (i = i + 8) {
        //     const pos: Vector3f = .{ .x=app.vertex_buffer[i+0], .y=app.vertex_buffer[i+1], .z=app.vertex_buffer[i+2] };
        //     const uv: Vector2f = .{ .x=app.vertex_buffer[i+3], .y=app.vertex_buffer[i+4] };
        //     const normal: Vector3f = .{ .x=app.vertex_buffer[i+5], .y=app.vertex_buffer[i+6], .z=app.vertex_buffer[i+7] };
        //     vertex_buffer.appendAssumeCapacity(.{ .pos = pos, .uv = uv, .normal = normal });
        // }
        const render_requirements: GouraudShader.pipeline_configuration.Requirements() = .{
            .depth_buffer = app.depth_buffer,
            .viewport_matrix = viewport_matrix,
        };
        GouraudShader.Pipeline.render(platform.pixel_buffer, render_context, app.vertex_buffer.items, @divExact(app.vertex_buffer.items.len, 3), render_requirements);
    }

    // render the model texture as a quad
    if (true) {
        // const texture_data = app.texture.rgba.data;
        const w: f32 = @floatFromInt(app.texture.width);
        const h: f32 = @floatFromInt(app.texture.height);
        var quad_context = QuadShaderRgb.Context {
            .texture = app.texture,
            .projection_matrix =
                projection_matrix.multiply(
                    view_matrix.multiply(
                        M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1.5 }).multiply(M44.scale(1/w))
                    )
                ),
        };
        const vertex_buffer = [_]QuadShaderRgb.Vertex{
            .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
            .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=0} },
            .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=1} },
            .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=1} },
        };
        const index_buffer = [_]u16{0,1,2,0,2,3};
        const requirements = QuadShaderRgb.pipeline_configuration.Requirements() {
            .depth_buffer = app.depth_buffer,
            .viewport_matrix = viewport_matrix,
            .index_buffer = &index_buffer,
        };
        QuadShaderRgb.Pipeline.render(platform.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
    }
    
    // render the font texture as a quad
    if (true) {
        const texture = @import("text.zig").font.texture;
        const w: f32 = @floatFromInt(texture.width);
        const h: f32 = @floatFromInt(texture.height);
        var quad_context = QuadShaderRgba.Context {
            .texture = texture,
            .projection_matrix =
                projection_matrix.multiply(
                    view_matrix.multiply(
                        M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1 }).multiply(M44.scale(1/@as(f32, @floatFromInt(texture.width))))
                    )
                ),
        };
        const vertex_buffer = [_]QuadShaderRgba.Vertex{
            .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
            .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=0} },
            .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=1} },
            .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=1} },
        };
        const index_buffer = [_]u16{0,1,2,0,2,3};
        const requirements = QuadShaderRgba.pipeline_configuration.Requirements() {
            .depth_buffer = app.depth_buffer,
            .viewport_matrix = viewport_matrix,
            .index_buffer = &index_buffer,
        };
        QuadShaderRgba.Pipeline.render(platform.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
    }

    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*1) - 5 }, "ms {d: <9.2}", .{platform.ms});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*2) - 5 }, "fps {}", .{platform.fps});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*3) - 5 }, "frame {}", .{platform.frame});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*4) - 5 }, "camera {d:.8}, {d:.8}, {d:.8}", .{app.camera.position.x, app.camera.position.y, app.camera.position.z});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*5) - 5 }, "mouse {} {}", .{platform.mouse.x, platform.mouse.y});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*6) - 5 }, "dimensions {} {}", .{platform.w, platform.h});
    try app.text_renderer.print(Vector2i { .x = 100, .y = platform.h - (12*8) - 4 }, "use wasd qe + mouse for camera movement", .{});
    try app.text_renderer.print(Vector2i { .x = 0, .y = 0 }, "hello from (0, 0), the lowest possible text!!!", .{});
    app.text_renderer.render_all(
        M44.orthographic_projection(0, @floatFromInt(platform.w), @floatFromInt(platform.h), 0, 0, 10),
        viewport_matrix
    );

    return true;
}
