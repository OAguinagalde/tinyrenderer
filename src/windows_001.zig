const std = @import("std");
const math = @import("math.zig");
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const M44 = math.M44;
const Buffer2D = @import("buffer.zig").Buffer2D;
const BGRA = @import("pixels.zig").BGRA;
const tic80 = @import("tic80.zig");
const TextRenderer = @import("text.zig").TextRenderer(BGRA, 1024, 1024);
const Platform = @import("windows.zig").Platform;

const App = struct {
    camera_position: Vector3f,
    text_renderer: TextRenderer,
    renderer: tic80.Renderer(BGRA),
};

var app: App = undefined;

pub fn init(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(BGRA)) !void {
    app.camera_position = Vector3f { .x = 0, .y = 0, .z = 0 };
    app.text_renderer = try TextRenderer.init(allocator, pixel_buffer);
    app.renderer = try tic80.Renderer(BGRA).init(allocator, tic80.penguknight_original_assets.palette, tic80.penguknight_original_assets.tiles);
}

pub fn update(platform: *Platform) !bool {
    
    platform.pixel_buffer.clear(BGRA.make(100, 149, 237,255));
    
    const unit: f32 = 2*(platform.ms / 16.6666);
    if (platform.keys['A']) app.camera_position.x -= unit;
    if (platform.keys['D']) app.camera_position.x += unit;
    if (platform.keys['W']) app.camera_position.y += unit;
    if (platform.keys['S']) app.camera_position.y -= unit;

    const view_matrix = M44.lookat_left_handed(app.camera_position, app.camera_position.add(Vector3f.from(0, 0, 1)), Vector3f.from(0, 1, 0));
    const projection_matrix = M44.orthographic_projection(0, @floatFromInt(@divExact(platform.w,4)), @floatFromInt(@divExact(platform.h,4)), 0, 0, 2);
    const viewport_matrix = M44.viewport_i32_2(0, 0, platform.w, platform.h, 255);

    const w = 8;
    const h = 8;
    try app.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.weird_block, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*0, h*0));
    try app.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.slime1, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*2, h*2));
    try app.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.slime2, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*3, h*3));
    try app.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.pengu1, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*4, h*4));
    try app.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.pengu2, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*5, h*5));
    try app.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.id0, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*0, h*0));
    try app.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.id255, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*15, h*15));
    try app.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.id15, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*15, h*0));
    try app.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.id240, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*0, h*15));
    app.renderer.render(
        platform.pixel_buffer,
        projection_matrix.multiply(view_matrix.multiply(M44.translation(Vector3f.from(0, 0, 1)))),
        viewport_matrix
    );

    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*1) - 4 }, "ms {d: <9.2}", .{platform.ms});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*2) - 4 }, "fps {}", .{platform.fps});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*3) - 4 }, "frame {}", .{platform.frame});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*4) - 4 }, "camera {d:.8}, {d:.8}, {d:.8}", .{app.camera_position.x, app.camera_position.y, app.camera_position.z});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*5) - 4 }, "mouse {} {}", .{platform.mouse.x, platform.mouse.y});
    try app.text_renderer.print(Vector2i { .x = 5, .y = platform.h - (12*6) - 4 }, "dimensions {} {}", .{platform.w, platform.h});
    try app.text_renderer.print(Vector2i { .x = 0, .y = 0 }, "hello from (0, 0), the lowest possible text!!!", .{});
    app.text_renderer.render_all(
        // projection_matrix,
        M44.orthographic_projection(0, @floatFromInt(platform.w), @floatFromInt(platform.h), 0, 0, 10),
        viewport_matrix
    );

    return true;
}