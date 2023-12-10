const std = @import("std");
const builtin = @import("builtin");
const math = @import("math.zig");
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const M44 = math.M44;
const M33 = math.M33;
const Buffer2D = @import("buffer.zig").Buffer2D;
const RGB = @import("pixels.zig").RGB;
const BGRA = @import("pixels.zig").BGRA;
const RGBA = @import("pixels.zig").RGBA;
const tic80 = @import("tic80.zig");
const TextRenderer = @import("text.zig").TextRenderer(BGRA, 1024, 1);
const windows = @import("windows.zig");
const Platform = windows.Platform;
const graphics = @import("graphics.zig");


pub const main = if (builtin.os.tag == .windows) windows.main else undefined;
pub const dimension_scale = 4;
pub const desired_width = 240;
pub const desired_height = 136;

const App = struct {
    text_renderer: TextRenderer,
    shape_renderer: ShapeRenderer(BGRA, RGB.from(0,0,0)),
    camera: Camera,
};

var app: App = undefined;

pub fn init(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(BGRA)) !void {
    _ = pixel_buffer;
    app.text_renderer = try TextRenderer.init(allocator);
    app.shape_renderer = try ShapeRenderer(BGRA, RGB.from(0,0,0)).init(allocator);
    app.camera = Camera.init(Vector3f { .x = 0, .y = 0, .z = 0 });
}

pub fn update(platform: *Platform) !bool {
    const h: f32 = @floatFromInt(platform.pixel_buffer.height);
    const w: f32 = @floatFromInt(platform.pixel_buffer.width);
    platform.pixel_buffer.clear(BGRA.make(100, 149, 237,255));
    
    if (platform.keys['W']) app.camera.pos = app.camera.pos.add(Vector3f.from(0, 1, 0));
    if (platform.keys['A']) app.camera.pos = app.camera.pos.add(Vector3f.from(-1, 0, 0));
    if (platform.keys['S']) app.camera.pos = app.camera.pos.add(Vector3f.from(0, -1, 0));
    if (platform.keys['D']) app.camera.pos = app.camera.pos.add(Vector3f.from(1, 0, 0));
    
    const view_matrix = M33.look_at(Vector2f.from(app.camera.pos.x, app.camera.pos.y), Vector2f.from(0, 1));
    const projection_matrix = M33.orthographic_projection(0, w, h, 0);
    const viewport_matrix = M33.viewport(0, 0, w, h);
    const mvp_matrix = projection_matrix.multiply(view_matrix);

    try app.shape_renderer.add_quad(Vector2f.from(-100, -100), Vector2f.from(w+100, h+100));
    app.shape_renderer.render(platform.pixel_buffer, mvp_matrix, viewport_matrix);
    
    const text_height = app.text_renderer.height() + 1;
    const text_color = RGBA.from(RGBA, @bitCast(@as(u32, 0xffffffff)));
    try app.text_renderer.print(Vector2f { .x = 5, .y = h - (text_height*0) }, "ms {d: <9.2}", .{platform.ms}, text_color);
    try app.text_renderer.print(Vector2f { .x = 5, .y = h - (text_height*1) }, "frame {}", .{platform.frame}, text_color);
    try app.text_renderer.print(Vector2f { .x = 5, .y = h - (text_height*2) }, "camera {d:.8}, {d:.8}, {d:.8}", .{app.camera.pos.x, app.camera.pos.y, app.camera.pos.z}, text_color);
    try app.text_renderer.print(Vector2f { .x = 5, .y = h - (text_height*3) }, "mouse {} {}", .{platform.mouse.x, platform.mouse.y}, text_color);
    try app.text_renderer.print(Vector2f { .x = 5, .y = h - (text_height*4) }, "dimensions {} {}", .{w, h}, text_color);
    app.text_renderer.render_all(
        platform.pixel_buffer,
        M33.orthographic_projection(0, w, h, 0),
        M33.viewport(0, 0, w, h)
    );
    return true;
}

const Camera = struct {
    pos: Vector3f,
    bound_right: f32,
    bound_left: f32,
    bound_top: f32,
    bound_bottom: f32,
    
    pub fn init(pos: Vector3f) Camera {
        return Camera {
            .pos = pos,
            .bound_right = undefined,
            .bound_left = undefined,
            .bound_top = undefined,
            .bound_bottom = undefined,
        };
    }

    pub fn set_bounds(self: *Camera, bound_right: f32, bound_left: f32, bound_top: f32, bound_bottom: f32) void {
        self.bound_right = bound_right;
        self.bound_left = bound_left;
        self.bound_top = bound_top;
        self.bound_bottom = bound_bottom;
    }

    pub fn move_bounded(self: *Camera, pos: Vector2f, real_width: f32, real_height: f32) void {
        const bound_width = self.bound_right - self.bound_left;
        const bound_height = self.bound_top - self.bound_bottom;

        // center the camera on the bound area
        self.pos.x = self.bound_left - (real_width/2) + (bound_width/2);
        if (bound_width > real_width) {
            // if the bounds are bigger than the screen, pan it without showing the outside of the bounds
            const half_diff = (bound_width - real_width)/2;
            const c = self.pos.x;
            self.pos.x = std.math.clamp(pos.x-(real_width/2), c-half_diff, c+half_diff);
        }
        
        self.pos.y = self.bound_bottom - (real_height/2) + (bound_height/2);
        if (bound_height > real_height) {
            const half_diff = (bound_height - real_height)/2;
            const c = self.pos.y;
            self.pos.y = std.math.clamp(pos.y-(real_height/2), c-half_diff, c+half_diff);
        }

    }

};

pub fn ShapeRenderer(comptime output_pixel_type: type, comptime color: RGB) type {
    return struct {
        
        const Self = @This();
        const shader = QuadShapeShader(output_pixel_type, color);

        allocator: std.mem.Allocator,
        vertex_buffer: std.ArrayList(shader.Vertex),

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
            return self;
        }

        pub fn add_quad(self: *Self, pos: Vector2f, size: Vector2f) !void {
            const vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,          .y = pos.y          } },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          } },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y } },
                .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y } },
            };
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub fn render(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            const context = shader.Context {
                .mvp_matrix = mvp_matrix,
            };
            shader.Pipeline.render(pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = viewport_matrix, });
            self.vertex_buffer.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            self.vertex_buffer.clearAndFree();
        }
    };
}

pub fn QuadShapeShader(comptime output_pixel_type: type, comptime color: RGB) type {
    return struct {

        pub const Context = struct {
            mvp_matrix: M33,
        };

        pub const Invariant = struct {
        };

        pub const Vertex = struct {
            pos: Vector2f,
        };

        pub const pipeline_configuration = graphics.GraphicsPipelineQuads2DConfiguration {
            .blend_with_background = false,
            .do_quad_clipping = true,
            .do_scissoring = false,
            .trace = false
        };

        pub const Pipeline = graphics.GraphicsPipelineQuads2D(
            output_pixel_type,
            Context,
            Invariant,
            Vertex,
            pipeline_configuration,
            struct {
                inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector3f {
                    _ = out_invariant;
                    return context.mvp_matrix.apply_to_vec2(vertex.pos);
                }
            }.vertex_shader,
            struct {
                inline fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                    _ = context;
                    _ = invariants;
                    const out_color = comptime output_pixel_type.from(RGB, color);
                    return out_color;
                }
            }.fragment_shader,
        );
    };
}