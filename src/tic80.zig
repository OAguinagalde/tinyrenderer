const std = @import("std");

const core = @import("core.zig");
const math = @import("math.zig");
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vector4f = math.Vector4f;
const BoundingBox = math.BoundingBox;
const M44 = math.M44;
const M33 = math.M33;
const Plane = math.Plane;
const Frustum = math.Frustum;
const win32 = @import("win32.zig");
const OBJ = @import("obj.zig");
const TGA = @import("tga.zig");
const imgui = @import("imgui.zig");
const Buffer2D = @import("buffer.zig").Buffer2D;
const RGBA = @import("pixels.zig").RGBA;
const RGB = @import("pixels.zig").RGB;
const BGRA = @import("pixels.zig").BGRA;
const BGR = @import("pixels.zig").BGR;
const GraphicsPipelineConfiguration = @import("graphics.zig").GraphicsPipelineConfiguration;
const GraphicsPipeline = @import("graphics.zig").GraphicsPipeline;
const GraphicsPipelineQuads2DConfiguration = @import("graphics.zig").GraphicsPipelineQuads2DConfiguration;
const GraphicsPipelineQuads2D = @import("graphics.zig").GraphicsPipelineQuads2D;

pub const palette_size = 16;
pub const Palette = [palette_size]u24;
pub const PaletteIndex = u4;
/// An `Sprite` is [8*8]u4 PaletteIndexes
pub const sprite_size = 8;
/// A top to bottom, left to right, `[8*8]u4` where each `u4` indexes into a `Palette`
pub const SpriteData = [sprite_size*sprite_size]PaletteIndex;
/// `SpriteAtlas` has 16 * 16 = 256 Sprites in total 
pub const atlas_size = 16;
pub const sprites_per_atlas = 256;
/// An array of 256 sprites
pub const SpriteAtlas = [sprites_per_atlas]SpriteData;
pub const AtlasIndex = u8;
pub const map_width = 240;
pub const map_height = 136;
pub const MapRow = [map_width]AtlasIndex;
pub const Map = [map_height]MapRow;
pub const SpriteFlags = u8;
pub const Flags = [sprites_per_atlas]SpriteFlags;

pub fn Renderer(comptime output_pixel_type: type, comptime shader: type) type {
    return struct {
        
        const Self = @This();

        allocator: std.mem.Allocator,
        palette: Palette,
        texture: Buffer2D(PaletteIndex),
        vertex_buffer: std.ArrayList(shader.Vertex),

        /// Will manage its own state, esentially has its own copy of the `sprite_atlas` and `palette`
        pub fn init(allocator: std.mem.Allocator, palette: Palette, sprite_atlas: SpriteAtlas) !Self {
            // convert the sprite_atlas into a texture
            const pixels_per_row = sprite_size * atlas_size;
            const texture_data = try allocator.alloc(PaletteIndex, pixels_per_row*pixels_per_row);
            for (sprite_atlas, 0..) |sprite, sprite_index| {
                const atlas_col = sprite_index % atlas_size;
                const atlas_row = @divFloor(sprite_index, atlas_size);
                for (sprite, 0..) |palette_index, pixel_index| {
                    const sprite_col = pixel_index % sprite_size;
                    const sprite_row = @divFloor(pixel_index, sprite_size);
                    const x = atlas_col*sprite_size + sprite_col;
                    const y = atlas_row*sprite_size + sprite_row;
                    texture_data[x + y*pixels_per_row] = palette_index;
                }
            }
            var self: Self = undefined;
            self.allocator = allocator;
            self.texture = Buffer2D(PaletteIndex).from(texture_data, pixels_per_row);
            @memcpy(&self.palette, &palette);
            self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
            return self;
        }

        /// `sprite_id` is an `enum` field, and `sprite_map` is an array of length is equal to the length of the enum, and maps the enum to `AtlasPositions`
        pub fn add_sprite(self: *Self, col: i32, row: i32, pos: Vector2f) !void {
            const colf: f32 = @floatFromInt(col);
            const rowf: f32 = @floatFromInt(row);
            const vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,               .y = pos.y               }, .uv = .{ .x = colf*sprite_size + 0,           .y = rowf*sprite_size + sprite_size } }, // 0 - bottom left
                .{ .pos = .{ .x = pos.x + sprite_size, .y = pos.y               }, .uv = .{ .x = colf*sprite_size + sprite_size, .y = rowf*sprite_size + sprite_size } }, // 1 - bottom right
                .{ .pos = .{ .x = pos.x + sprite_size, .y = pos.y + sprite_size }, .uv = .{ .x = colf*sprite_size + sprite_size, .y = rowf*sprite_size + 0           } }, // 2 - top right
                .{ .pos = .{ .x = pos.x,               .y = pos.y + sprite_size }, .uv = .{ .x = colf*sprite_size + 0,           .y = rowf*sprite_size + 0           } }, // 3 - top left
            };
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub const AddSpriteParameters = struct {
            mirror: bool = false
        };
        pub fn add_sprite_from_atlas_index(self: *Self, index: u8, pos: Vector2f, parameters: AddSpriteParameters) !void {
            const colf: f32 = @floatFromInt(index%16);
            const rowf: f32 = @floatFromInt(@divFloor(index,16));
            var vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,               .y = pos.y               }, .uv = .{ .x = colf*sprite_size + 0,           .y = rowf*sprite_size + sprite_size } }, // 0 - bottom left
                .{ .pos = .{ .x = pos.x + sprite_size, .y = pos.y               }, .uv = .{ .x = colf*sprite_size + sprite_size, .y = rowf*sprite_size + sprite_size } }, // 1 - bottom right
                .{ .pos = .{ .x = pos.x + sprite_size, .y = pos.y + sprite_size }, .uv = .{ .x = colf*sprite_size + sprite_size, .y = rowf*sprite_size + 0           } }, // 2 - top right
                .{ .pos = .{ .x = pos.x,               .y = pos.y + sprite_size }, .uv = .{ .x = colf*sprite_size + 0,           .y = rowf*sprite_size + 0           } }, // 3 - top left
            };
            if (parameters.mirror) {
                vertices[0].uv.x = colf*sprite_size + sprite_size;
                vertices[1].uv.x = colf*sprite_size + 0;
                vertices[2].uv.x = colf*sprite_size + 0;
                vertices[3].uv.x = colf*sprite_size + sprite_size;
            }
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub fn add_map(self: *Self, comptime map: Map, tl: Vector2i, br: Vector2i, pos: Vector2f) !void {
            const top: usize = @intCast(tl.y);
            const bottom: usize = @intCast(br.y);
            const left: usize = @intCast(tl.x);
            const right: usize = @intCast(br.x);
            for (map[top..bottom], 0..) |map_row, row_i| {
                for (map_row[left..right], 0..) |atlas_index, col_i| {
                    // NOTE(Oscar) aparently the embedded map data has the indices rows and columns inversed? not sure if my fault or just how it is
                    const row: f32 = @floatFromInt(atlas_index%16);
                    const col: f32 = @floatFromInt(@divFloor(atlas_index, 16));
                    const offset = Vector2f.from(@floatFromInt(col_i*8), @floatFromInt(((bottom-top-1)*8)-(row_i*8)));
                    const vertices = [4] shader.Vertex {
                        .{ .pos = .{ .x = offset.x + pos.x,               .y = offset.y + pos.y               }, .uv = .{ .x = col*sprite_size + 0,           .y = row*sprite_size + sprite_size } }, // 0 - bottom left
                        .{ .pos = .{ .x = offset.x + pos.x + sprite_size, .y = offset.y + pos.y               }, .uv = .{ .x = col*sprite_size + sprite_size, .y = row*sprite_size + sprite_size } }, // 1 - bottom right
                        .{ .pos = .{ .x = offset.x + pos.x + sprite_size, .y = offset.y + pos.y + sprite_size }, .uv = .{ .x = col*sprite_size + sprite_size, .y = row*sprite_size + 0           } }, // 2 - top right
                        .{ .pos = .{ .x = offset.x + pos.x,               .y = offset.y + pos.y + sprite_size }, .uv = .{ .x = col*sprite_size + 0,           .y = row*sprite_size + 0           } }, // 3 - top left
                    };
                    try self.vertex_buffer.appendSlice(&vertices);
                }
            }
        }

        pub fn render(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), projection_matrix: M44, viewport_matrix: M44) void {
            const context = shader.Context {
                .texture = self.texture,
                .palette = self.palette,
                .projection_matrix = projection_matrix,
            };
            shader.Pipeline.render(pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 2), .{ .viewport_matrix = viewport_matrix });
            self.vertex_buffer.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.texture.data);
            self.vertex_buffer.clearAndFree();
        }
    };
}

/// The tic80 shader is basically a quad shader, except the texture is a `Buffer2D(PaletteIndex)`
/// and the final pixel color is taken out of the `palette` provided in the context.
pub fn Shader(comptime output_pixel_type: type) type {
    return struct {

        pub const Context = struct {
            texture: Buffer2D(PaletteIndex),
            palette: Palette,
            projection_matrix: M44,
        };

        pub const Invariant = struct {
            texture_uv: Vector2f,
        };

        pub const Vertex = struct {
            pos: Vector2f,
            uv: Vector2f,
        };

        pub const pipeline_configuration = GraphicsPipelineConfiguration {
            .blend_with_background = false,
            .do_depth_testing = false,
            .do_perspective_correct_interpolation = false,
            .do_scissoring = false,
            .do_triangle_clipping = true,
            .trace = false,
            .use_index_buffer = false,
            .use_index_buffer_auto = true,
            .use_triangle_2 = false,
        };

        pub const Pipeline = GraphicsPipeline(
            output_pixel_type,
            Context,
            Invariant,
            Vertex,
            pipeline_configuration,
            struct {
                fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                    out_invariant.texture_uv = vertex.uv;
                    return context.projection_matrix.apply_to_vec3(Vector3f { .x = vertex.pos.x, .y = vertex.pos.y, .z = 0 });
                }
            }.vertex_shader,
            struct {
                fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                    const palette_index = context.texture.point_sample(false, invariants.texture_uv);
                    const bgr = context.palette[palette_index];
                    return output_pixel_type.from(BGR, @bitCast(bgr));
                }
            }.fragment_shader,
        );
    };
}

/// The same as the Shader above, but color blending is enabled and the fragment shader will return a transparent pixel if the palette matches the key_color
pub fn ShaderWithBlendAndKeyColor(comptime output_pixel_type: type, comptime key_color: PaletteIndex) type {
    return struct {

        pub const Context = struct {
            texture: Buffer2D(PaletteIndex),
            palette: Palette,
            projection_matrix: M44,
        };

        pub const Invariant = struct {
            texture_uv: Vector2f,
        };

        pub const Vertex = struct {
            pos: Vector2f,
            uv: Vector2f,
        };

        pub const pipeline_configuration = GraphicsPipelineConfiguration {
            .blend_with_background = true,
            .do_depth_testing = false,
            .do_perspective_correct_interpolation = false,
            .do_scissoring = false,
            .do_triangle_clipping = true,
            .trace = false,
            .use_index_buffer = false,
            .use_index_buffer_auto = true,
            .use_triangle_2 = false,
        };

        pub const Pipeline = GraphicsPipeline(
            output_pixel_type,
            Context,
            Invariant,
            Vertex,
            pipeline_configuration,
            struct {
                fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                    out_invariant.texture_uv = vertex.uv;
                    return context.projection_matrix.apply_to_vec3(Vector3f { .x = vertex.pos.x, .y = vertex.pos.y, .z = 0 });
                }
            }.vertex_shader,
            struct {
                fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                    const palette_index = context.texture.point_sample(false, invariants.texture_uv);
                    if (palette_index == key_color) return output_pixel_type.from(BGRA, BGRA.make(0,0,0,0));
                    const bgr = context.palette[palette_index];
                    return output_pixel_type.from(BGR, @bitCast(bgr));
                }
            }.fragment_shader,
        );
    };
}

pub fn QuadShader(comptime output_pixel_type: type) type {
    return struct {

        pub const Context = struct {
            texture: Buffer2D(PaletteIndex),
            palette: Palette,
            mvp_matrix: M33,
        };

        pub const Invariant = struct {
            texture_uv: Vector2f,
        };

        pub const Vertex = struct {
            pos: Vector2f,
            uv: Vector2f,
        };

        pub const pipeline_configuration = GraphicsPipelineQuads2DConfiguration {
            .blend_with_background = false,
            .do_quad_clipping = true,
            .do_scissoring = false,
            .trace = false
        };

        pub const Pipeline = GraphicsPipelineQuads2D(
            output_pixel_type,
            Context,
            Invariant,
            Vertex,
            pipeline_configuration,
            struct {
                inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector3f {
                    out_invariant.texture_uv = vertex.uv;
                    return context.mvp_matrix.apply_to_vec2(vertex.pos);
                }
            }.vertex_shader,
            struct {
                inline fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                    const palette_index = context.texture.point_sample(false, invariants.texture_uv);
                    const bgr = context.palette[palette_index];
                    return output_pixel_type.from(BGR, @bitCast(bgr));
                }
            }.fragment_shader,
        );
    };
}

pub fn QuadRenderer(comptime output_pixel_type: type, comptime shader: type) type {
    return struct {
        
        const Self = @This();

        allocator: std.mem.Allocator,
        palette: Palette,
        texture: Buffer2D(PaletteIndex),
        vertex_buffer: std.ArrayList(shader.Vertex),

        /// Will manage its own state, esentially has its own copy of the `sprite_atlas` and `palette`
        pub fn init(allocator: std.mem.Allocator, palette: Palette, sprite_atlas: SpriteAtlas) !Self {
            // convert the sprite_atlas into a texture
            const pixels_per_row = sprite_size * atlas_size;
            const texture_data = try allocator.alloc(PaletteIndex, pixels_per_row*pixels_per_row);
            for (sprite_atlas, 0..) |sprite, sprite_index| {
                const atlas_col = sprite_index % atlas_size;
                const atlas_row = @divFloor(sprite_index, atlas_size);
                for (sprite, 0..) |palette_index, pixel_index| {
                    const sprite_col = pixel_index % sprite_size;
                    const sprite_row = @divFloor(pixel_index, sprite_size);
                    const x = atlas_col*sprite_size + sprite_col;
                    const y = atlas_row*sprite_size + sprite_row;
                    texture_data[x + y*pixels_per_row] = palette_index;
                }
            }
            var self: Self = undefined;
            self.allocator = allocator;
            self.texture = Buffer2D(PaletteIndex).from(texture_data, pixels_per_row);
            @memcpy(&self.palette, &palette);
            self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
            return self;
        }

        /// `sprite_id` is an `enum` field, and `sprite_map` is an array of length is equal to the length of the enum, and maps the enum to `AtlasPositions`
        pub fn add_sprite(self: *Self, col: i32, row: i32, pos: Vector2f) !void {
            const colf: f32 = @floatFromInt(col);
            const rowf: f32 = @floatFromInt(row);
            const vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,               .y = pos.y               }, .uv = .{ .x = colf*sprite_size + 0,           .y = rowf*sprite_size + sprite_size } }, // 0 - bottom left
                .{ .pos = .{ .x = pos.x + sprite_size, .y = pos.y               }, .uv = .{ .x = colf*sprite_size + sprite_size, .y = rowf*sprite_size + sprite_size } }, // 1 - bottom right
                .{ .pos = .{ .x = pos.x + sprite_size, .y = pos.y + sprite_size }, .uv = .{ .x = colf*sprite_size + sprite_size, .y = rowf*sprite_size + 0           } }, // 2 - top right
                .{ .pos = .{ .x = pos.x,               .y = pos.y + sprite_size }, .uv = .{ .x = colf*sprite_size + 0,           .y = rowf*sprite_size + 0           } }, // 3 - top left
            };
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub const AddSpriteParameters = struct {
            mirror: bool = false
        };
        pub fn add_sprite_from_atlas_index(self: *Self, index: u8, pos: Vector2f, parameters: AddSpriteParameters) !void {
            const colf: f32 = @floatFromInt(index%16);
            const rowf: f32 = @floatFromInt(@divFloor(index,16));
            var vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,               .y = pos.y               }, .uv = .{ .x = colf*sprite_size + 0,           .y = rowf*sprite_size + sprite_size } }, // 0 - bottom left
                .{ .pos = .{ .x = pos.x + sprite_size, .y = pos.y               }, .uv = .{ .x = colf*sprite_size + sprite_size, .y = rowf*sprite_size + sprite_size } }, // 1 - bottom right
                .{ .pos = .{ .x = pos.x + sprite_size, .y = pos.y + sprite_size }, .uv = .{ .x = colf*sprite_size + sprite_size, .y = rowf*sprite_size + 0           } }, // 2 - top right
                .{ .pos = .{ .x = pos.x,               .y = pos.y + sprite_size }, .uv = .{ .x = colf*sprite_size + 0,           .y = rowf*sprite_size + 0           } }, // 3 - top left
            };
            if (parameters.mirror) {
                vertices[0].uv.x = colf*sprite_size + sprite_size;
                vertices[1].uv.x = colf*sprite_size + 0;
                vertices[2].uv.x = colf*sprite_size + 0;
                vertices[3].uv.x = colf*sprite_size + sprite_size;
            }
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub fn add_map(self: *Self, map: Map, bb: BoundingBox(usize), pos: Vector2f) !void {
            for (map[bb.bottom..bb.top+1], 0..) |map_row, i| {
                for (map_row[bb.left..bb.right+1], 0..) |sprite_index, j| {
                    // figure out the uv of the sprite_index
                    const col: f32 = @floatFromInt(sprite_index%16);
                    const row: f32 = @floatFromInt(@divFloor(sprite_index, 16));
                    // offset for this particular tile of the map
                    const offset = Vector2f.from(@floatFromInt(j*8), @floatFromInt(i*8));
                    const vertices = [4] shader.Vertex {
                        .{ .pos = .{ .x = offset.x + pos.x,               .y = offset.y + pos.y               }, .uv = .{ .x = col*sprite_size + 0,           .y = row*sprite_size + sprite_size } }, // 0 - bottom left
                        .{ .pos = .{ .x = offset.x + pos.x + sprite_size, .y = offset.y + pos.y               }, .uv = .{ .x = col*sprite_size + sprite_size, .y = row*sprite_size + sprite_size } }, // 1 - bottom right
                        .{ .pos = .{ .x = offset.x + pos.x + sprite_size, .y = offset.y + pos.y + sprite_size }, .uv = .{ .x = col*sprite_size + sprite_size, .y = row*sprite_size + 0           } }, // 2 - top right
                        .{ .pos = .{ .x = offset.x + pos.x,               .y = offset.y + pos.y + sprite_size }, .uv = .{ .x = col*sprite_size + 0,           .y = row*sprite_size + 0           } }, // 3 - top left
                    };
                    try self.vertex_buffer.appendSlice(&vertices);
                }
            }
        }

        pub fn render(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            const context = shader.Context {
                .texture = self.texture,
                .palette = self.palette,
                .mvp_matrix = mvp_matrix,
            };
            shader.Pipeline.render(pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = viewport_matrix });
            self.vertex_buffer.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.texture.data);
            self.vertex_buffer.clearAndFree();
        }
    };
}