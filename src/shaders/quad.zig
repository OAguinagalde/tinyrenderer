const std = @import("std");

const math = @import("../math.zig");
const graphics = @import("../graphics.zig");
const buffer = @import("../buffer.zig");

const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vector4f = math.Vector4f;
const M44 = math.M44;
const Buffer2D = buffer.Buffer2D;
const GraphicsPipelineConfiguration = graphics.GraphicsPipelineConfiguration;
const GraphicsPipeline = graphics.GraphicsPipeline;
const RGBA = @import("../pixels.zig").RGBA;

pub fn Shader(comptime output_pixel_type: type, comptime texture_pixel_type: type, comptime use_bilinear: bool, comptime config_interface_text: bool) type {
    return struct {

        pub const Context = struct {
            texture: Buffer2D(texture_pixel_type),
            projection_matrix: M44,
        };

        pub const Invariant = struct {
            texture_uv: Vector2f,
        };

        pub const Vertex = struct {
            pos: Vector2f,
            uv: Vector2f,
        };

        pub const pipeline_configuration = if (config_interface_text) GraphicsPipelineConfiguration {
            .blend_with_background = true,
            .use_index_buffer_auto = true,
            .use_index_buffer = false,
            .do_triangle_clipping = false,
            .do_depth_testing = false,
            .do_perspective_correct_interpolation = false,
            .do_scissoring = false,
            .use_triangle_2 = false,
        } else GraphicsPipelineConfiguration {
            .blend_with_background = true,
            .use_index_buffer = true,
            .do_triangle_clipping = true,
            .do_depth_testing = true,
            .do_perspective_correct_interpolation = true,
            .do_scissoring = false,
            .use_triangle_2 = false,
            .trace = false,
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
                    return context.projection_matrix.apply_to_vec3(Vector3f { .x = vertex.pos.x, .y = vertex.pos.y, .z = 1 });
                }
            }.vertex_shader,
            struct {
                fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                    const sample = if (use_bilinear) context.texture.bilinear_sample(!config_interface_text, invariants.texture_uv) else context.texture.point_sample(!config_interface_text, invariants.texture_uv);
                    return output_pixel_type.from(texture_pixel_type, sample);
                }
            }.fragment_shader,
        );
    };
}
