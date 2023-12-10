const std = @import("std");
const builtin = @import("builtin");
const core = @import("core.zig");
const TaskManager = @import("TaskManager.zig");
const math = @import("math.zig");
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const M44 = math.M44;
const M33 = math.M33;
const OBJ = @import("obj.zig");
const TGA = @import("tga.zig");
const Buffer2D = @import("buffer.zig").Buffer2D;
const RGBA = @import("pixels.zig").RGBA;
const RGB = @import("pixels.zig").RGB;
const BGRA = @import("pixels.zig").BGRA;
const windows = @import("windows.zig");
const wasm = @import("wasm.zig");
const platform = if (builtin.os.tag == .windows) windows else wasm;

const GouraudShader = @import("shaders/gouraud.zig").Shader(Platform.OutPixelType, RGB);
const QuadShaderRgb = @import("shaders/quad.zig").Shader(Platform.OutPixelType, RGB, false, false);
const QuadShaderRgba = @import("shaders/quad.zig").Shader(Platform.OutPixelType, RGBA, false, false);
const TextRenderer = @import("text.zig").TextRenderer(Platform.OutPixelType, 1024, 1);

const Platform = platform.Application(.{
    .init = init,
    .update = update,
    .dimension_scale = 4,
    .desired_width = 240,
    .desired_height = 136,
});

// TODO: currently the wasm target only works if the exported functions are explicitly referenced.
// The reason for this is that zig compiles lazily. By referencing Platform.run, the comptime code
// in that funciton is executed, which in turn references the exported functions, making it so
// that those are "found" by zig and properly exported.
comptime {
    _ = Platform.run;
}

pub fn main() !void {
    try Platform.run();
}

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

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    app.depth_buffer = Buffer2D(f32).from(try allocator.alloc(f32, Platform.height*Platform.width), @intCast(Platform.width));
    app.camera.position = Vector3f { .x = 0, .y = 0, .z = 0 };
    app.camera.up = Vector3f { .x = 0, .y = 1, .z = 0 };
    app.camera.direction = Vector3f { .x = 0, .y = 0, .z = 1 };
    app.time = 0;
    app.text_renderer = try TextRenderer.init(allocator);
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
        try Platform.read_file("res/african_head_diffuse.tga", read_tga_texture, ReadTgaContext { .allocator = allocator, .texture = &app.texture });
        app.vertex_buffer = undefined;
        try Platform.read_file("res/african_head.obj", read_obj_model, ReadObjContext { .allocator = allocator, .vertex_buffer = &app.vertex_buffer });
    }

}

pub fn update(ud: *platform.UpdateData) anyerror!bool {
    const h: f32 = @floatFromInt(ud.pixel_buffer.height);
    const w: f32 = @floatFromInt(ud.pixel_buffer.width);
    ud.pixel_buffer.clear(Platform.OutPixelType.make(100, 149, 237,255));
    app.depth_buffer.clear(999999);

    app.time += ud.ms;

    // camera movement with mouse
    const mouse_sensitivity = 0.01;
    const up = Vector3f {.x = 0, .y = 1, .z = 0 };
    const real_right = app.camera.direction.cross_product(up).scale(-1).normalized();
    const real_up = app.camera.direction.cross_product(real_right).normalized();
    if (ud.mouse_d.x != 0 or ud.mouse_d.y != 0) {
        app.camera.direction = app.camera.direction.add(real_right.scale(@as(f32, @floatFromInt(ud.mouse_d.x))*mouse_sensitivity));
        if (app.camera.direction.y < 0.95 and app.camera.direction.y > -0.95) {
            app.camera.direction = app.camera.direction.add(real_up.scale(-@as(f32, @floatFromInt(ud.mouse_d.y))*mouse_sensitivity));
        }
        app.camera.direction.normalize();
    }
    
    // camera position with AWSD and QE
    const unit: f32 = 0.02*(ud.ms / 16.6666);
    if (ud.keys['W']) app.camera.position = app.camera.position.add(app.camera.direction.scale(unit));
    if (ud.keys['S']) app.camera.position = app.camera.position.add(app.camera.direction.scale(-unit));
    if (ud.keys['A']) app.camera.position = app.camera.position.add(real_right.scale(-unit));
    if (ud.keys['D']) app.camera.position = app.camera.position.add(real_right.scale(unit));
    if (ud.keys['Q']) app.camera.position.y += unit;
    if (ud.keys['E']) app.camera.position.y -= unit;

    // calculate view_matrix, projection_matrix and viewport_matrix
    const looking_at: Vector3f = app.camera.position.add(app.camera.direction);
    const view_matrix = M44.lookat_left_handed(app.camera.position, looking_at, Vector3f.from(0, 1, 0));
    const aspect_ratio = w / h;
    const projection_matrix = M44.perspective_projection(60, aspect_ratio, 0.1, 255);
    const viewport_matrix = M44.viewport(0, 0, w, h, 255);

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
        const render_requirements: GouraudShader.pipeline_configuration.Requirements() = .{
            .depth_buffer = app.depth_buffer,
            .viewport_matrix = viewport_matrix,
        };
        GouraudShader.Pipeline.render(ud.pixel_buffer, render_context, app.vertex_buffer.items, @divExact(app.vertex_buffer.items.len, 3), render_requirements);
    }

    // render the model texture as a quad
    if (true) {
        // const texture_data = app.texture.rgba.data;
        const tw: f32 = @floatFromInt(app.texture.width);
        const th: f32 = @floatFromInt(app.texture.height);
        var quad_context = QuadShaderRgb.Context {
            .texture = app.texture,
            .projection_matrix =
                projection_matrix.multiply(
                    view_matrix.multiply(
                        M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1.5 }).multiply(M44.scale(1/tw))
                    )
                ),
        };
        const vertex_buffer = [_]QuadShaderRgb.Vertex{
            .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
            .{ .pos = .{.x=tw,.y=0}, .uv = .{.x=1,.y=0} },
            .{ .pos = .{.x=tw,.y=th}, .uv = .{.x=1,.y=1} },
            .{ .pos = .{.x=0,.y=th}, .uv = .{.x=0,.y=1} },
        };
        const index_buffer = [_]u16{0,1,2,0,2,3};
        const requirements = QuadShaderRgb.pipeline_configuration.Requirements() {
            .depth_buffer = app.depth_buffer,
            .viewport_matrix = viewport_matrix,
            .index_buffer = &index_buffer,
        };
        QuadShaderRgb.Pipeline.render(ud.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
    }
    
    // render the font texture as a quad
    if (true) {
        const texture = @import("text.zig").font.texture;
        const tw: f32 = @floatFromInt(texture.width);
        const th: f32 = @floatFromInt(texture.height);
        var quad_context = QuadShaderRgba.Context {
            .texture = texture,
            .projection_matrix =
                projection_matrix.multiply(
                    view_matrix.multiply(
                        M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1 }).multiply(M44.scale(1/tw))
                    )
                ),
        };
        const vertex_buffer = [_]QuadShaderRgba.Vertex{
            .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
            .{ .pos = .{.x=tw,.y=0}, .uv = .{.x=1,.y=0} },
            .{ .pos = .{.x=tw,.y=th}, .uv = .{.x=1,.y=1} },
            .{ .pos = .{.x=0,.y=th}, .uv = .{.x=0,.y=1} },
        };
        const index_buffer = [_]u16{0,1,2,0,2,3};
        const requirements = QuadShaderRgba.pipeline_configuration.Requirements() {
            .depth_buffer = app.depth_buffer,
            .viewport_matrix = viewport_matrix,
            .index_buffer = &index_buffer,
        };
        QuadShaderRgba.Pipeline.render(ud.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
    }

    const debug_color = RGBA.from(RGBA, @bitCast(@as(u32, 0xffffffff)));
    const text_height = app.text_renderer.height() + 1;
    try app.text_renderer.print(Vector2f.from(1, h - (text_height*1)), "ms {d: <9.2}", .{ud.ms}, debug_color);
    try app.text_renderer.print(Vector2f.from(1, h - (text_height*2)), "frame {}", .{ud.frame}, debug_color);
    try app.text_renderer.print(Vector2f.from(1, h - (text_height*3)), "camera {d:.8}, {d:.8}, {d:.8}", .{app.camera.position.x, app.camera.position.y, app.camera.position.z}, debug_color);
    try app.text_renderer.print(Vector2f.from(1, h - (text_height*4)), "mouse {} {}", .{ud.mouse.x, ud.mouse.y}, debug_color);
    try app.text_renderer.print(Vector2f.from(1, h - (text_height*5)), "dimensions {} {}", .{ud.w, ud.h}, debug_color);
    app.text_renderer.render_all(
        ud.pixel_buffer,
        M33.orthographic_projection(0, w, h, 0),
        M33.viewport(0, 0, w, h)
    );

    return true;
}