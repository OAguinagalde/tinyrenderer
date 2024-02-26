const std = @import("std");
const builtin = @import("builtin");
const math = @import("math.zig");
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const M33 = math.M33;
const BoundingBox = math.BoundingBox;
const Buffer2D = @import("buffer.zig").Buffer2D;
const RGB = @import("pixels.zig").RGB;
const RGBA = @import("pixels.zig").RGBA;
const BGR = @import("pixels.zig").BGR;
const graphics = @import("graphics.zig");
const font = @import("text.zig").font;

const windows = @import("windows.zig");
const wasm = @import("wasm.zig");
const platform = if (builtin.os.tag == .windows) windows else wasm;
const Application = platform.Application(.{
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
    if (@This() == @import("root")) {
        _ = Application.run;
    }
}

pub fn main() !void {
    try Application.run();
}

const State = struct {
    camera: Vec3(f32),
    renderer: Renderer(platform.OutPixelType)
};

var state: State = undefined;

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    state.camera = Vec3(f32).from(0, 0, 0);
    state.renderer = try Renderer(platform.OutPixelType).init(allocator);
}

pub fn update(ud: *platform.UpdateData) anyerror!bool {
    
    ud.pixel_buffer.clear(platform.OutPixelType.from(RGBA, RGBA.make(100, 149, 237,255)));

    const h: f32 = @floatFromInt(ud.pixel_buffer.height);
    const w: f32 = @floatFromInt(ud.pixel_buffer.width);
    
    if (ud.key_pressing('W')) state.camera = state.camera.add(Vec3(f32).from(0, 1, 0));
    if (ud.key_pressing('A')) state.camera = state.camera.add(Vec3(f32).from(-1, 0, 0));
    if (ud.key_pressing('S')) state.camera = state.camera.add(Vec3(f32).from(0, -1, 0));
    if (ud.key_pressing('D')) state.camera = state.camera.add(Vec3(f32).from(1, 0, 0));
    
    const view_matrix = M33.look_at(Vec2(f32).from(state.camera.x, state.camera.y), Vector2f.from(0, 1));
    const projection_matrix = M33.orthographic_projection(0, w, h, 0);
    const viewport_matrix = M33.viewport(0, 0, w, h);
    const mvp_matrix = projection_matrix.multiply(view_matrix);

    state.renderer.set_context(ud.pixel_buffer, mvp_matrix, viewport_matrix);
    try state.renderer.add_quad_from_bb(BoundingBox(f32).from(h+100, -100, -100, w+100), RGBA.make(0,0,0,255));
    try state.renderer.add_text(Vec2(f32).from(10, 10), "Hello from (10, 10)!", .{}, @bitCast(@as(u32, 0xFF00FFFF)));
    try state.renderer.add_blit_texture_to_bb(BoundingBox(f32).from(100, 50, 50, 100), ud.pixel_buffer);
    try state.renderer.flush_all();

    const text_color: RGBA = @bitCast(@as(u32, 0xffffffff));
    const text_height = 6;
    state.renderer.set_context(ud.pixel_buffer, projection_matrix, viewport_matrix);
    try state.renderer.add_text(Vec2(f32).from(0, h - (text_height*1)), "ms {d: <9.2}", .{ud.ms}, text_color);
    try state.renderer.add_text(Vec2(f32).from(0, h - (text_height*2)), "frame {}", .{ud.frame}, text_color);
    try state.renderer.add_text(Vec2(f32).from(0, h - (text_height*3)), "camera {d:.8}, {d:.8}, {d:.8}", .{state.camera.x, state.camera.y, state.camera.z}, text_color);
    try state.renderer.add_text(Vec2(f32).from(0, h - (text_height*4)), "mouse {} {}", .{ud.mouse.x, ud.mouse.y}, text_color);
    try state.renderer.add_text(Vec2(f32).from(0, h - (text_height*5)), "dimensions {} {}", .{w, h}, text_color);
    try state.renderer.flush_all();
    
    return true;
}

pub fn ShapeRenderer(comptime output_pixel_type: type, comptime color: RGB) type {
    return struct {

        const shader = struct {

            pub const Context = struct {
                mvp_matrix: M33,
            };

            pub const Invariant = struct {
                tint: RGBA,
            };

            pub const Vertex = struct {
                pos: Vector2f,
                tint: RGBA,
            };

            pub const pipeline_configuration = graphics.GraphicsPipelineQuads2DConfiguration {
                .blend_with_background = true,
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
                        out_invariant.tint = vertex.tint;
                        return context.mvp_matrix.apply_to_vec2(vertex.pos);
                    }
                }.vertex_shader,
                struct {
                    inline fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                        _ = context;
                        const out_color = comptime output_pixel_type.from(RGB, color);
                        const tint = output_pixel_type.from(RGBA, invariants.tint);
                        return out_color.tint(tint);
                    }
                }.fragment_shader,
            );
        };
        
        const Self = @This();

        allocator: std.mem.Allocator,
        vertex_buffer: std.ArrayList(shader.Vertex),

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
            return self;
        }

        pub fn add_quad_from_bb(self: *Self, bb: BoundingBox(f32), tint: RGBA) !void {
            const pos = Vector2f.from(bb.left, bb.bottom);
            const size = Vector2f.from(bb.right - bb.left, bb.top - bb.bottom);
            const vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
            };
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub fn add_quad_border(self: *Self, bb: BoundingBox(f32), thickness: f32, tint: RGBA) !void {
            const line_left = BoundingBox(f32).from(bb.top+thickness, bb.bottom-thickness, bb.left-thickness, bb.left);
            const line_bottom = BoundingBox(f32).from(bb.bottom, bb.bottom-thickness, bb.left-thickness, bb.right+thickness);
            const line_right = BoundingBox(f32).from(bb.top+thickness, bb.bottom-thickness, bb.right, bb.right+thickness);
            const line_top = BoundingBox(f32).from(bb.top+thickness, bb.top, bb.left-thickness, bb.right+thickness);
            try self.add_quad_from_bb(line_left, tint);
            try self.add_quad_from_bb(line_bottom, tint);
            try self.add_quad_from_bb(line_right, tint);
            try self.add_quad_from_bb(line_top, tint);
        }
        
        pub fn add_quad(self: *Self, pos: Vector2f, size: Vector2f, tint: RGBA) !void {
            const vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
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

        const Batch = struct {
            vertex_buffer: std.ArrayList(shader.Vertex),
            pixel_buffer: Buffer2D(output_pixel_type),
            mvp_matrix: M33,
            viewport_matrix: M33,

            fn init(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) Batch {
                return .{
                    .vertex_buffer = std.ArrayList(shader.Vertex).init(allocator),
                    .pixel_buffer = pixel_buffer,
                    .mvp_matrix = mvp_matrix,
                    .viewport_matrix = viewport_matrix,
                };
            }

            pub fn add_quad_from_bb(self: *Batch, bb: BoundingBox(f32), tint: RGBA) !void {
                const size = Vector2f.from(bb.right - bb.left, bb.top - bb.bottom);
                if (size.x == 0 or size.y == 0) return;
                const pos = Vector2f.from(bb.left, bb.bottom);
                const vertices = [4] shader.Vertex {
                    .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                    .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                    .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                    .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
                };
                try self.vertex_buffer.appendSlice(&vertices);
            }

            pub fn add_quad_border(self: *Batch, bb: BoundingBox(f32), thickness: f32, tint: RGBA) !void {
                const line_left = BoundingBox(f32).from(bb.top+thickness, bb.bottom-thickness, bb.left-thickness, bb.left);
                const line_bottom = BoundingBox(f32).from(bb.bottom, bb.bottom-thickness, bb.left-thickness, bb.right+thickness);
                const line_right = BoundingBox(f32).from(bb.top+thickness, bb.bottom-thickness, bb.right, bb.right+thickness);
                const line_top = BoundingBox(f32).from(bb.top+thickness, bb.top, bb.left-thickness, bb.right+thickness);
                try self.add_quad_from_bb(line_left, tint);
                try self.add_quad_from_bb(line_bottom, tint);
                try self.add_quad_from_bb(line_right, tint);
                try self.add_quad_from_bb(line_top, tint);
            }
            
            pub fn add_quad(self: *Batch, pos: Vector2f, size: Vector2f, tint: RGBA) !void {
                const vertices = [4] shader.Vertex {
                    .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                    .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                    .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                    .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
                };
                try self.vertex_buffer.appendSlice(&vertices);
            }

            pub fn flush(self: *Batch) void {
                const context = shader.Context {
                    .mvp_matrix = self.mvp_matrix,
                };
                shader.Pipeline.render(self.pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = self.viewport_matrix, });
                self.vertex_buffer.clearAndFree();
            }
        };
    
    };
}

pub fn StandardQuadRenderer(comptime output_pixel_type: type, comptime texture_pixel_type: type) type {
    return struct {

        const shader = struct {

            pub const Context = struct {
                texture: Buffer2D(texture_pixel_type),
                mvp_matrix: M33,
            };

            pub const Invariant = struct {
                uv: Vector2f,
            };

            pub const Vertex = struct {
                pos: Vector2f,
                uv: Vector2f,
            };

            pub const pipeline_configuration = graphics.GraphicsPipelineQuads2DConfiguration {
                .blend_with_background = false,
                .do_quad_clipping = true,
                .do_scissoring = false,
                .trace = false,
            };

            pub const Pipeline = graphics.GraphicsPipelineQuads2D(
                output_pixel_type,
                Context,
                Invariant,
                Vertex,
                pipeline_configuration,
                struct {
                    inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector3f {
                        out_invariant.uv = vertex.uv;
                        return context.mvp_matrix.apply_to_vec2(vertex.pos);
                    }
                }.vertex_shader,
                struct {
                    inline fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                        const sample = context.texture.point_sample(true, invariants.uv);
                        return output_pixel_type.from(texture_pixel_type, sample);
                    }
                }.fragment_shader,
            );
        };
        
        const Self = @This();

        allocator: std.mem.Allocator,
        vertex_buffer: std.ArrayList(shader.Vertex),
        texture: Buffer2D(texture_pixel_type),

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
            self.texture = undefined;
            return self;
        }

        pub fn add_blit_texture_to_bb(self: *Self, bb: BoundingBox(f32), texture: Buffer2D(texture_pixel_type)) !void {
            self.texture = texture;
            const vertex_buffer = [4] shader.Vertex {
                .{ .pos = bb.bl(), .uv = Vec2(f32).from(0, 0) }, // 0 - bottom left
                .{ .pos = bb.br(), .uv = Vec2(f32).from(1, 0) }, // 1 - bottom right
                .{ .pos = bb.tr(), .uv = Vec2(f32).from(1, 1) }, // 2 - top right
                .{ .pos = bb.tl(), .uv = Vec2(f32).from(0, 1) }, // 3 - top left
            };
            try self.vertex_buffer.appendSlice(&vertex_buffer);
        }

        pub fn render(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            const context = shader.Context {
                .texture = self.texture,
                .mvp_matrix = mvp_matrix,
            };
            shader.Pipeline.render(pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = viewport_matrix, });
            self.vertex_buffer.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            self.vertex_buffer.clearAndFree();
        }

        const Batch = struct {
            vertex_buffer: std.ArrayList(shader.Vertex),
            texture: Buffer2D(texture_pixel_type),
            pixel_buffer: Buffer2D(output_pixel_type),
            mvp_matrix: M33,
            viewport_matrix: M33,

            fn init(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33, texture: Buffer2D(texture_pixel_type)) Batch {
                return .{
                    .vertex_buffer = std.ArrayList(shader.Vertex).init(allocator),
                    .texture = texture,
                    .pixel_buffer = pixel_buffer,
                    .mvp_matrix = mvp_matrix,
                    .viewport_matrix = viewport_matrix,
                };
            }

            pub fn add_blit_texture_to_bb(self: *Batch, bb: BoundingBox(f32)) !void {
                const vertex_buffer = [4] shader.Vertex {
                    .{ .pos = bb.bl(), .uv = Vec2(f32).from(0, 0) }, // 0 - bottom left
                    .{ .pos = bb.br(), .uv = Vec2(f32).from(1, 0) }, // 1 - bottom right
                    .{ .pos = bb.tr(), .uv = Vec2(f32).from(1, 1) }, // 2 - top right
                    .{ .pos = bb.tl(), .uv = Vec2(f32).from(0, 1) }, // 3 - top left
                };
                try self.vertex_buffer.appendSlice(&vertex_buffer);
            }

            pub fn flush(self: *Batch) void {
                const context = shader.Context {
                    .texture = self.texture,
                    .mvp_matrix = self.mvp_matrix,
                };
                shader.Pipeline.render(self.pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = self.viewport_matrix, });
                self.vertex_buffer.clearAndFree();
            }
        };
    };
}

pub fn TextRenderer(comptime out_pixel_type: type, comptime max_size_per_print: usize, comptime size: comptime_float) type {
    return struct {

        const texture = font.texture;
        const char_width: f32 = (base_width - pad_left - pad_right) * size;
        const char_height: f32 = (base_height - pad_top - pad_bottom) * size;
        // NOTE the font has quite a lot of padding so rather than rendering the whole 8x8 quad, only render the relevant part of the quad
        // the rest is just transparent anyway
        const base_width: f32 = 8;
        const base_height: f32 = 8;
        const pad_top: f32 = 0;
        const pad_bottom: f32 = 3;
        const pad_left: f32 = 0;
        const pad_right: f32 = 5;
        const space_between_characters: f32 = 1;
        
        const Shader = struct {

            pub const Context = struct {
                mvp_matrix: M33,
            };

            pub const Invariant = struct {
                tint: RGBA,
                uv: Vector2f,
            };

            pub const Vertex = struct {
                pos: Vector2f,
                uv: Vector2f,
                tint: RGBA,
            };

            pub const pipeline_configuration = graphics.GraphicsPipelineQuads2DConfiguration {
                .blend_with_background = true,
                .do_quad_clipping = true,
                .do_scissoring = false,
                .trace = false
            };

            pub const Pipeline = graphics.GraphicsPipelineQuads2D(
                out_pixel_type,
                Context,
                Invariant,
                Vertex,
                pipeline_configuration,
                struct {
                    inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector3f {
                        out_invariant.tint = vertex.tint;
                        out_invariant.uv = vertex.uv;
                        return context.mvp_matrix.apply_to_vec2(vertex.pos);
                    }
                }.vertex_shader,
                struct {
                    inline fn fragment_shader(context: Context, invariants: Invariant) out_pixel_type {
                        _ = context;
                        const sample = texture.point_sample(false, invariants.uv);
                        const sample_adapted = out_pixel_type.from(RGBA, sample); 
                        const tint = out_pixel_type.from(RGBA, invariants.tint);
                        return sample_adapted.tint(tint);
                    }
                }.fragment_shader,
            );
        };

        vertex_buffer: std.ArrayList(Shader.Vertex),
        
        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .vertex_buffer = std.ArrayList(Shader.Vertex).init(allocator)
            };
        }

        pub fn deinit(self: *Self) void {
            self.vertex_buffer.clearAndFree();
        }

        pub fn print(self: *Self, pos: Vector2f, comptime fmt: []const u8, args: anytype, tint: RGBA) !void {
            var buff: [max_size_per_print]u8 = undefined;
            const str = try std.fmt.bufPrint(&buff, fmt, args);
            for (str, 0..) |_c, i| {
                    
                const c = switch (_c) {
                    // NOTE for whatever reason the font I'm using has uppercase and lowercase reversed?
                    // so make everything lower case (which will show up as an upper case and looks better)
                    // 'A'..'Z' -> 'a'..'z'
                    65...90 => _c+32,
                    else => _c
                };
                
                // x and y are the bottom left of the quad
                const x: f32 = pos.x + @as(f32, @floatFromInt(i)) * char_width + @as(f32, @floatFromInt(i));
                const y: f32 = pos.y;
                
                const cy: f32 = @floatFromInt(15 - @divFloor(c,16));
                const cx: f32 = @floatFromInt(c % 16);
                
                // texture left and right
                const u_1: f32 = cx * base_width + pad_left;
                const u_2: f32 = (cx+1) * base_width - pad_right;
                
                // texture top and bottom. Note that the texture is invertex so the mat here is also inverted
                const v_1: f32 = cy * base_height + pad_bottom;
                const v_2: f32 = (cy+1) * base_height - pad_top;

                // NOTE the texture is reversed hence the weird uv coordinates
                const vertices = [4] Shader.Vertex {
                    .{ .pos = .{ .x = x,              .y = y               }, .uv = .{ .x = u_1, .y = v_1 }, .tint = tint },
                    .{ .pos = .{ .x = x + char_width, .y = y               }, .uv = .{ .x = u_2, .y = v_1 }, .tint = tint },
                    .{ .pos = .{ .x = x + char_width, .y = y + char_height }, .uv = .{ .x = u_2, .y = v_2 }, .tint = tint },
                    .{ .pos = .{ .x = x,              .y = y + char_height }, .uv = .{ .x = u_1, .y = v_2 }, .tint = tint }
                };
                
                try self.vertex_buffer.appendSlice(&vertices);                
            }
        }

        pub fn width(self: *Self) f32 {
            _ = self;
            return char_width;
        }
        
        pub fn height(self: *Self) f32 {
            _ = self;
            return char_height;
        }

        pub fn render_all(self: *Self, pixel_buffer: Buffer2D(out_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            Shader.Pipeline.render(
                pixel_buffer,
                .{ .mvp_matrix = mvp_matrix, },
                self.vertex_buffer.items,
                self.vertex_buffer.items.len/4,
                .{ .viewport_matrix = viewport_matrix, }
            );
            self.vertex_buffer.clearRetainingCapacity();
        }
    
        const Batch = struct {
            vertex_buffer: std.ArrayList(Shader.Vertex),
            pixel_buffer: Buffer2D(out_pixel_type),
            mvp_matrix: M33,
            viewport_matrix: M33,

            fn init(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(out_pixel_type), mvp_matrix: M33, viewport_matrix: M33) Batch {
                return .{
                    .vertex_buffer = std.ArrayList(Shader.Vertex).init(allocator),
                    .pixel_buffer = pixel_buffer,
                    .mvp_matrix = mvp_matrix,
                    .viewport_matrix = viewport_matrix,
                };
            }

            pub fn add_text(self: *Batch, pos: Vector2f, comptime fmt: []const u8, args: anytype, tint: RGBA) !void {
                var buff: [max_size_per_print]u8 = undefined;
                const str = try std.fmt.bufPrint(&buff, fmt, args);
                for (str, 0..) |_c, i| {
                    
                    const c = switch (_c) {
                        // NOTE for whatever reason the font I'm using has uppercase and lowercase reversed?
                        // so make everything lower case (which will show up as an upper case and looks better)
                        // 'A'..'Z' -> 'a'..'z'
                        65...90 => _c+32,
                        else => _c
                    };
                    
                    // x and y are the bottom left of the quad
                    const x: f32 = pos.x + @as(f32, @floatFromInt(i)) * char_width + @as(f32, @floatFromInt(i));
                    const y: f32 = pos.y;
                    
                    const cy: f32 = @floatFromInt(15 - @divFloor(c,16));
                    const cx: f32 = @floatFromInt(c % 16);
                    
                    // texture left and right
                    const u_1: f32 = cx * base_width + pad_left;
                    const u_2: f32 = (cx+1) * base_width - pad_right;
                    
                    // texture top and bottom. Note that the texture is invertex so the mat here is also inverted
                    const v_1: f32 = cy * base_height + pad_bottom;
                    const v_2: f32 = (cy+1) * base_height - pad_top;

                    // NOTE the texture is reversed hence the weird uv coordinates
                    const vertices = [4] Shader.Vertex {
                        .{ .pos = .{ .x = x,              .y = y               }, .uv = .{ .x = u_1, .y = v_1 }, .tint = tint },
                        .{ .pos = .{ .x = x + char_width, .y = y               }, .uv = .{ .x = u_2, .y = v_1 }, .tint = tint },
                        .{ .pos = .{ .x = x + char_width, .y = y + char_height }, .uv = .{ .x = u_2, .y = v_2 }, .tint = tint },
                        .{ .pos = .{ .x = x,              .y = y + char_height }, .uv = .{ .x = u_1, .y = v_2 }, .tint = tint }
                    };
                    
                    try self.vertex_buffer.appendSlice(&vertices);                
                }
            }

            pub fn flush(self: *Batch) void {
                Shader.Pipeline.render(
                    self.pixel_buffer,
                    .{ .mvp_matrix = self.mvp_matrix, },
                    self.vertex_buffer.items,
                    self.vertex_buffer.items.len/4,
                    .{ .viewport_matrix = self.viewport_matrix, }
                );
                self.vertex_buffer.clearAndFree();
            }
        };
    
    };
}

pub fn PaletteBasedTexturedQuadRenderer(comptime output_pixel_type: type, comptime key_color: ?u4) type {
    return struct {
        
        const Self = @This();

        const shader = struct {

            pub const Context = struct {
                palette_based_texture: Buffer2D(u4),
                palette: *[16]u24,
                mvp_matrix: M33,
            };

            pub const Invariant = struct {
                uv: Vector2f,
            };

            pub const Vertex = struct {
                pos: Vector2f,
                uv: Vector2f,
            };

            pub const pipeline_configuration = graphics.GraphicsPipelineQuads2DConfiguration {
                .blend_with_background = key_color != null,
                .do_quad_clipping = true,
                .do_scissoring = false,
                .trace = false
            };

            inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector3f {
                out_invariant.uv = vertex.uv;
                return context.mvp_matrix.apply_to_vec2(vertex.pos);
            }

            inline fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                const palette_index = context.palette_based_texture.point_sample(false, invariants.uv);
                const key_color_enabled = comptime key_color != null;
                if (key_color_enabled) {
                    if (palette_index == key_color.?) return output_pixel_type.from(RGBA, RGBA.make(0,0,0,0));
                }
                return output_pixel_type.from(BGR, @bitCast(context.palette[palette_index]));
            }
            
            pub const Pipeline = graphics.GraphicsPipelineQuads2D(
                output_pixel_type,
                Context,
                Invariant,
                Vertex,
                pipeline_configuration,
                vertex_shader,
                fragment_shader
            );
            
        };

        allocator: std.mem.Allocator,
        palette_based_texture: Buffer2D(u4),
        palette: *[16]u24,
        vertex_buffer: std.ArrayList(shader.Vertex),

        pub fn init(allocator: std.mem.Allocator, palette: *[16]u24, palette_based_texture: Buffer2D(u4)) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.palette_based_texture = palette_based_texture;
            self.palette = palette;
            self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
            return self;
        }

        pub const ExtraParameters = struct {
            mirror_horizontally: bool = false
        };

        pub fn add_sprite_from_atlas_by_index(self: *Self, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), sprite_index: usize, dest_bb: BoundingBox(f32), parameters: ExtraParameters) !void {
            const colf: f32 = @floatFromInt(sprite_index % grid_dimensions.x);
            const rowf: f32 = @floatFromInt(@divFloor(sprite_index, grid_dimensions.x));
            var vertices = [4] shader.Vertex {
                .{ .pos = dest_bb.bl(), .uv = Vec2(f32).from(colf*grid_cell_dimensions.x + 0                      , rowf*grid_cell_dimensions.y + 0) }, // 0 - bottom left
                .{ .pos = dest_bb.br(), .uv = Vec2(f32).from(colf*grid_cell_dimensions.x + grid_cell_dimensions.x , rowf*grid_cell_dimensions.y + 0) }, // 1 - bottom right
                .{ .pos = dest_bb.tr(), .uv = Vec2(f32).from(colf*grid_cell_dimensions.x + grid_cell_dimensions.x , rowf*grid_cell_dimensions.y + grid_cell_dimensions.y ) }, // 2 - top right
                .{ .pos = dest_bb.tl(), .uv = Vec2(f32).from(colf*grid_cell_dimensions.x + 0                      , rowf*grid_cell_dimensions.y + grid_cell_dimensions.y ) }, // 3 - top left
            };
            if (parameters.mirror_horizontally) {
                vertices[0].uv.x = colf*grid_cell_dimensions.x + grid_cell_dimensions.x;
                vertices[1].uv.x = colf*grid_cell_dimensions.x + 0;
                vertices[2].uv.x = colf*grid_cell_dimensions.x + 0;
                vertices[3].uv.x = colf*grid_cell_dimensions.x + grid_cell_dimensions.x;
            }
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub fn add_map(self: *Self, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), map: *[136][240]u8, map_bb: BoundingBox(usize), dest_bb: BoundingBox(f32)) !void {
            for (map[map_bb.bottom..map_bb.top+1], 0..) |map_row, i| {
                for (map_row[map_bb.left..map_bb.right+1], 0..) |sprite_index, j| {
                    const offset = Vector2f.from(@floatFromInt(j*8), @floatFromInt(i*8));
                    const map_tile_dest_bb = BoundingBox(f32).from(
                        dest_bb.bottom + offset.y + grid_cell_dimensions.y,
                        dest_bb.bottom + offset.y,
                        dest_bb.left + offset.x,
                        dest_bb.left + offset.x + grid_cell_dimensions.x
                    );
                    try self.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, map_tile_dest_bb, .{});
                }
            }
        }

        pub fn render(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            const context = shader.Context {
                .texture = self.palette_based_texture,
                .palette = self.palette,
                .mvp_matrix = mvp_matrix,
            };
            shader.Pipeline.render(pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = viewport_matrix });
            self.vertex_buffer.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            self.vertex_buffer.clearAndFree();
        }

        const Batch = struct {
            
            palette_based_texture: Buffer2D(u4),
            palette: *[16]u24,
            vertex_buffer: std.ArrayList(shader.Vertex),
            pixel_buffer: Buffer2D(output_pixel_type),
            mvp_matrix: M33,
            viewport_matrix: M33,

            pub fn init(allocator: std.mem.Allocator, palette: *[16]u24, palette_based_texture: Buffer2D(u4), pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) !Batch {
                var self: Batch = undefined;
                self.palette_based_texture = palette_based_texture;
                self.palette = palette;
                self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
                self.pixel_buffer = pixel_buffer;
                self.mvp_matrix = mvp_matrix;
                self.viewport_matrix = viewport_matrix;
                return self;
            }

            pub fn add_palette_based_textured_quad(self: *Batch, dest_bb: BoundingBox(f32), src_bb: BoundingBox(f32)) !void {
                var vertices = [4] shader.Vertex {
                    .{ .pos = dest_bb.bl(), .uv = src_bb.bl() }, // 0 - bottom left
                    .{ .pos = dest_bb.br(), .uv = src_bb.br() }, // 1 - bottom right
                    .{ .pos = dest_bb.tr(), .uv = src_bb.tr() }, // 2 - top right
                    .{ .pos = dest_bb.tl(), .uv = src_bb.tl() }, // 3 - top left
                };
                try self.vertex_buffer.appendSlice(&vertices);
            }

            pub fn add_sprite_from_atlas_by_index(self: *Batch, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), sprite_index: usize, dest_bb: BoundingBox(f32), parameters: ExtraParameters) !void {
                const colf: f32 = @floatFromInt(sprite_index % grid_dimensions.x);
                const rowf: f32 = @floatFromInt(@divFloor(sprite_index, grid_dimensions.x));
                var vertices = [4] shader.Vertex {
                    .{ .pos = dest_bb.bl(), .uv = Vec2(f32).from((colf+0)*grid_cell_dimensions.x, (rowf+0)*grid_cell_dimensions.y) }, // 0 - bottom left
                    .{ .pos = dest_bb.br(), .uv = Vec2(f32).from((colf+1)*grid_cell_dimensions.x, (rowf+0)*grid_cell_dimensions.y) }, // 1 - bottom right
                    .{ .pos = dest_bb.tr(), .uv = Vec2(f32).from((colf+1)*grid_cell_dimensions.x, (rowf+1)*grid_cell_dimensions.y) }, // 2 - top right
                    .{ .pos = dest_bb.tl(), .uv = Vec2(f32).from((colf+0)*grid_cell_dimensions.x, (rowf+1)*grid_cell_dimensions.y) }, // 3 - top left
                };
                if (parameters.mirror_horizontally) {
                    vertices[0].uv.x = colf*grid_cell_dimensions.x + grid_cell_dimensions.x;
                    vertices[1].uv.x = colf*grid_cell_dimensions.x + 0;
                    vertices[2].uv.x = colf*grid_cell_dimensions.x + 0;
                    vertices[3].uv.x = colf*grid_cell_dimensions.x + grid_cell_dimensions.x;
                }
                try self.vertex_buffer.appendSlice(&vertices);
            }

            pub fn add_map(self: *Batch, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), map: *[136][240]u8, map_bb: BoundingBox(usize), dest_bb: BoundingBox(f32)) !void {
                for (map[map_bb.bottom..map_bb.top+1], 0..) |map_row, i| {
                    for (map_row[map_bb.left..map_bb.right+1], 0..) |sprite_index, j| {
                        const offset = Vector2f.from(@floatFromInt(j*8), @floatFromInt(i*8));
                        const map_tile_dest_bb = BoundingBox(f32).from(
                            dest_bb.bottom + offset.y + grid_cell_dimensions.y,
                            dest_bb.bottom + offset.y,
                            dest_bb.left + offset.x,
                            dest_bb.left + offset.x + grid_cell_dimensions.x
                        );
                        try self.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, map_tile_dest_bb, .{});
                    }
                }
            }

            pub fn flush(self: *Batch) void {
                const context = shader.Context {
                    .palette_based_texture = self.palette_based_texture,
                    .palette = self.palette,
                    .mvp_matrix = self.mvp_matrix,
                };
                shader.Pipeline.render(self.pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = self.viewport_matrix });
                self.vertex_buffer.clearAndFree();
            }
            
        };
        
    };
}

// TODO allow to continue batches if not explicitly asked to use a different batch, or if the continuation is just imposible (for example, when textures used are different)
// TODO add layers!
pub fn Renderer(comptime output_pixel_type: type) type {
    return struct {

        const Self = @This();

        const TextRendererImpl = TextRenderer(output_pixel_type, 1024, 1);
        const ShapeRendererImpl = ShapeRenderer(output_pixel_type, RGB.from(255,255,255));
        const SurfaceRendererImpl = StandardQuadRenderer(output_pixel_type, output_pixel_type);
        const PaletteBasedTexturedQuadRendererImpl = PaletteBasedTexturedQuadRenderer(output_pixel_type, null);
        const PaletteBasedTexturedQuadRendererBlendedImpl = PaletteBasedTexturedQuadRenderer(output_pixel_type, 0);

        pub const ExtraParameters = struct {
            mirror_horizontally: bool = false,
            blend: bool = false,
        };

        const total_number_of_renderer_types = @typeInfo(RendererType).Enum.fields.len;
        batches_created_per_type: [total_number_of_renderer_types] usize,

        allocator: std.mem.Allocator,

        batches: std.ArrayList(BatchDescriptor),
        current_batch: BatchDescriptor,

        batches_text: std.ArrayList(TextRendererImpl.Batch),
        batches_shapes: std.ArrayList(ShapeRendererImpl.Batch),
        batches_palette_based_textured_quads: std.ArrayList(PaletteBasedTexturedQuadRendererImpl.Batch),
        batches_palette_based_textured_quads_blended: std.ArrayList(PaletteBasedTexturedQuadRendererBlendedImpl.Batch),
        batches_surfaces: std.ArrayList(SurfaceRendererImpl.Batch),

        pixel_buffer: Buffer2D(output_pixel_type),
        mvp_matrix: M33,
        viewport_matrix: M33,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
                        
            self.batches_text = std.ArrayList(TextRendererImpl.Batch).init(allocator);
            self.batches_shapes = std.ArrayList(ShapeRendererImpl.Batch).init(allocator);
            self.batches_surfaces = std.ArrayList(SurfaceRendererImpl.Batch).init(allocator);
            self.batches_palette_based_textured_quads = std.ArrayList(PaletteBasedTexturedQuadRendererImpl.Batch).init(allocator);
            self.batches_palette_based_textured_quads_blended = std.ArrayList(PaletteBasedTexturedQuadRendererBlendedImpl.Batch).init(allocator);

            self.batches = std.ArrayList(BatchDescriptor).init(allocator);

            self.current_batch = .{
                .index = 0,
                .renderer_type = .none
            };

            for (0..total_number_of_renderer_types) |i| self.batches_created_per_type[i] = 0;

            return self;
        }

        pub fn set_context(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            self.pixel_buffer = pixel_buffer;
            self.mvp_matrix = mvp_matrix;
            self.viewport_matrix = viewport_matrix;
        }

        pub fn add_quad_from_bb(self: *Self, bb: BoundingBox(f32), tint: RGBA) !void {
            const correct_renderer = RendererType.shape;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_shapes.items[self.batches_shapes.items.len-1];
                try batch.add_quad_from_bb(bb, tint);
                return;
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);
            // set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_shapes.items.len
            };
            self.batches_created_per_type[@intFromEnum(correct_renderer)] += 1;
            const new_batch = try self.batches_shapes.addOne();
            new_batch.* = ShapeRendererImpl.Batch.init(self.allocator, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_quad_from_bb(bb, tint);
        }
        
        pub fn add_quad_border(self: *Self, bb: BoundingBox(f32), thickness: f32, tint: RGBA) !void {
            const correct_renderer = RendererType.shape;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_shapes.items[self.current_batch.index];
                try batch.add_quad_border(bb, thickness, tint);
                return;
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);
            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_shapes.items.len
            };
            self.batches_created_per_type[@intFromEnum(correct_renderer)] += 1;
            const new_batch = try self.batches_shapes.addOne();
            new_batch.* = ShapeRendererImpl.Batch.init(self.allocator, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_quad_border(bb, thickness, tint);
        }
        
        pub fn add_palette_based_textured_quad(self: *Self, dest_bb: BoundingBox(f32), src_bb: BoundingBox(f32), palette_based_texture: Buffer2D(u4), palette: *[16]u24) !void {
            const correct_renderer = RendererType.palette_based_textured_quad_renderer;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_palette_based_textured_quads.items[self.current_batch.index];
                // if the batch is using same palette and texture, keep using it
                if (batch.palette_based_texture.data.ptr == palette_based_texture.data.ptr and batch.palette == palette) {
                    try batch.add_palette_based_textured_quad(dest_bb, src_bb);
                    return;
                }
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);

            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_palette_based_textured_quads.items.len
            };
            self.batches_created_per_type[@intFromEnum(correct_renderer)] += 1;
            const new_batch = try self.batches_palette_based_textured_quads.addOne();
            new_batch.* = try PaletteBasedTexturedQuadRendererImpl.Batch.init(self.allocator, palette, palette_based_texture, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_palette_based_textured_quad(dest_bb, src_bb);
        }

        pub fn add_blit_texture_to_bb(self: *Self, bb: BoundingBox(f32), texture: Buffer2D(output_pixel_type)) !void {
            const correct_renderer = RendererType.surface;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_surfaces.items[self.current_batch.index];
                if (batch.texture.data.ptr == texture.data.ptr) {
                    try batch.add_blit_texture_to_bb(bb);
                    return;
                }
            }
            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);
            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_surfaces.items.len
            };
            self.batches_created_per_type[@intFromEnum(correct_renderer)] += 1;
            const new_batch = try self.batches_surfaces.addOne();
            new_batch.* = SurfaceRendererImpl.Batch.init(self.allocator, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix, texture);
            try new_batch.add_blit_texture_to_bb(bb);
        }
        
        pub fn add_text(self: *Self, pos: Vector2f, comptime fmt: []const u8, args: anytype, tint: RGBA) !void {
            const correct_renderer = RendererType.text;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_text.items[self.current_batch.index];
                try batch.add_text(pos, fmt, args, tint);
                return;
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);
            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_text.items.len
            };
            self.batches_created_per_type[@intFromEnum(correct_renderer)] += 1;
            const new_batch = try self.batches_text.addOne();
            new_batch.* = TextRendererImpl.Batch.init(self.allocator, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_text(pos, fmt, args, tint);
        }
        
        pub fn add_sprite_from_atlas_by_index(self: *Self, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), palette: *[16]u24, palette_based_texture: Buffer2D(u4), sprite_index: usize, dest_bb: BoundingBox(f32), parameters: ExtraParameters) !void {
            if (parameters.blend) {
                const correct_renderer = RendererType.palette_based_textured_quad_blended_renderer;
                if (self.current_batch.renderer_type == correct_renderer) {
                    const batch = &self.batches_palette_based_textured_quads_blended.items[self.current_batch.index];
                    // if the batch is using same palette and texture, keep using it
                    if (batch.palette_based_texture.data.ptr == palette_based_texture.data.ptr and batch.palette == palette) {
                        try batch.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, dest_bb, .{ .mirror_horizontally = parameters.mirror_horizontally });
                        return;
                    }
                }

                // save previous batch
                if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);

                // initialize and set new batch
                self.current_batch = .{
                    .renderer_type = correct_renderer,
                    .index = self.batches_palette_based_textured_quads_blended.items.len
                };
                self.batches_created_per_type[@intFromEnum(correct_renderer)] += 1;
                const new_batch = try self.batches_palette_based_textured_quads_blended.addOne();
                new_batch.* = try PaletteBasedTexturedQuadRendererBlendedImpl.Batch.init(self.allocator, palette, palette_based_texture, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
                try new_batch.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, dest_bb, .{ .mirror_horizontally = parameters.mirror_horizontally });
            }
            else {
                const correct_renderer = RendererType.palette_based_textured_quad_renderer;
                if (self.current_batch.renderer_type == correct_renderer) {
                    const batch = &self.batches_palette_based_textured_quads.items[self.current_batch.index];
                    // if the batch is using same palette and texture, keep using it
                    if (batch.palette_based_texture.data.ptr == palette_based_texture.data.ptr and batch.palette == palette) {
                        try batch.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, dest_bb, .{ .mirror_horizontally = parameters.mirror_horizontally });
                        return;
                    }
                }

                // save previous batch
                if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);

                // initialize and set new batch
                self.current_batch = .{
                    .renderer_type = correct_renderer,
                    .index = self.batches_palette_based_textured_quads.items.len
                };
                self.batches_created_per_type[@intFromEnum(correct_renderer)] += 1;
                const new_batch = try self.batches_palette_based_textured_quads.addOne();
                new_batch.* = try PaletteBasedTexturedQuadRendererImpl.Batch.init(self.allocator, palette, palette_based_texture, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
                try new_batch.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, dest_bb, .{ .mirror_horizontally = parameters.mirror_horizontally });
            }
        }

        pub fn add_map(self: *Self, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), palette: *[16]u24, palette_based_texture: Buffer2D(u4), map: *[136][240]u8, map_bb: BoundingBox(usize), dest_bb: BoundingBox(f32)) !void {
            const correct_renderer = RendererType.palette_based_textured_quad_renderer;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_palette_based_textured_quads.items[self.current_batch.index];
                // if the batch is using same palette and texture, keep using it
                if (batch.palette_based_texture.data.ptr == palette_based_texture.data.ptr and batch.palette == palette) {
                    try batch.add_map(grid_cell_dimensions, grid_dimensions, map, map_bb, dest_bb);
                    return;
                }
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);

            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_palette_based_textured_quads.items.len
            };
            self.batches_created_per_type[@intFromEnum(correct_renderer)] += 1;
            const new_batch = try self.batches_palette_based_textured_quads.addOne();
            new_batch.* = try PaletteBasedTexturedQuadRendererImpl.Batch.init(self.allocator, palette, palette_based_texture, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_map(grid_cell_dimensions, grid_dimensions, map, map_bb, dest_bb);
        }

        pub fn flush_all(self: *Self) !void {
            if (self.current_batch.renderer_type == .none) return;
            try self.batches.append(self.current_batch);

            // TODO count the number of batches that have been created per pipeline
            // and then here count the number of batches gone through. The numbers should match, and if not, then there is a bug and memory is leaking
            var batch_counter_per_type: [total_number_of_renderer_types] usize = undefined;
            for (0..total_number_of_renderer_types) |i| batch_counter_per_type[i] = 0;

            var total: usize = 0;
            for (self.batches.items) |batch| {
                batch_counter_per_type[@intFromEnum(batch.renderer_type)] += 1;
                const index = batch.index;
                switch (batch.renderer_type) {
                    .shape => {
                        const batch_to_render = &self.batches_shapes.items[index];
                        batch_to_render.flush();
                    },
                    .text => {
                        const batch_to_render = &self.batches_text.items[index];
                        batch_to_render.flush();
                    },
                    .surface => {
                        const batch_to_render = &self.batches_surfaces.items[index];
                        batch_to_render.flush();
                    },
                    .palette_based_textured_quad_renderer => {
                        const batch_to_render = &self.batches_palette_based_textured_quads.items[index];
                        batch_to_render.flush();
                    },
                    .palette_based_textured_quad_blended_renderer => {
                        const batch_to_render = &self.batches_palette_based_textured_quads_blended.items[index];
                        batch_to_render.flush();
                    },
                    .none => unreachable
                }
                total += 1;
            }

            // Dont check on .none
            for (1..total_number_of_renderer_types) |i| std.debug.assert(batch_counter_per_type[i] == self.batches_created_per_type[i]);
            for (0..total_number_of_renderer_types) |i| self.batches_created_per_type[i] = 0;

            self.batches.clearRetainingCapacity();
            self.batches_shapes.clearRetainingCapacity();
            self.batches_surfaces.clearRetainingCapacity();
            self.batches_text.clearRetainingCapacity();
            self.batches_palette_based_textured_quads.clearRetainingCapacity();
            self.batches_palette_based_textured_quads_blended.clearRetainingCapacity();
            self.current_batch = .{
                .index = 0,
                .renderer_type = .none
            };
        }

        const RendererType = enum {
            none, text, shape, surface, palette_based_textured_quad_renderer, palette_based_textured_quad_blended_renderer
        };

        const BatchDescriptor = struct {
            renderer_type: RendererType,
            index: usize,
        };
    };
}
