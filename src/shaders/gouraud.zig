const std = @import("std");

const math = @import("../math.zig");
const graphics = @import("../graphics.zig");
const buffer = @import("../buffer.zig");

const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vector4f = math.Vector4f;
const M44 = math.M44;
const Buffer2D = buffer.Buffer2D;
const GraphicsPipelineConfiguration = graphics.GraphicsPipelineConfiguration;
const GraphicsPipeline = graphics.GraphicsPipeline;

// TODO force `output_pixel_type` to have `fn from(texture_pixel_type) output_pixel_type`
pub fn Shader(comptime output_pixel_type: type, comptime texture_pixel_type: type) type {
    return struct {

        pub const Context = struct {
            texture: Buffer2D(texture_pixel_type),
            texture_width: usize,
            texture_height: usize,
            view_model_matrix: M44,
            projection_matrix: M44,
            light_position_camera_space: Vector3f,
        };

        pub const Invariant = struct {
            texture_uv: Vector2f,
            light_intensity: f32,
        };

        pub const Vertex = struct {
            pos: Vector3f,
            uv: Vector2f,
            normal: Vector3f,
        };

        pub const pipeline_configuration = GraphicsPipelineConfiguration {
            .blend_with_background = false,
            .use_index_buffer = false,
            .do_triangle_clipping = true,
            .do_depth_testing = true,
            .do_perspective_correct_interpolation = true,
            .do_scissoring = false,
            .use_triangle_2 = false,
        };

        pub const Pipeline = GraphicsPipeline(
            output_pixel_type, Context, Invariant, Vertex, pipeline_configuration,
            struct {
                fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                    const position_camera_space = context.view_model_matrix.apply_to_vec3(vertex.pos);
                    const light_direction = context.light_position_camera_space.substract(position_camera_space.perspective_division()).normalized();
                    out_invariant.light_intensity = std.math.clamp(vertex.normal.normalized().dot(light_direction), 0, 1);
                    out_invariant.texture_uv = vertex.uv;
                    return context.projection_matrix.apply_to_vec4(position_camera_space);
                }
            }.vertex_shader,
            struct {
                fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                    const sample = context.texture.point_sample(true, invariants.texture_uv);
                    const rgba = sample.scale(invariants.light_intensity);
                    return output_pixel_type.from(texture_pixel_type, rgba);
                }
            }.fragment_shader,
        );
    };
}
