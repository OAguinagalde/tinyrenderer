# Software Renderer

This is a software renderer. Originally a fork of `ssloy/tinyrenderer`, a fantastic and brief computer graphics/rendering course. I followed the course until I added a `win32` platform layer, deviated from the original path and slowly became something else. Now its a software renderer written in `zig`.

# Quickstart

```
> zig version
0.12.0-dev.312+cb6201715
> zig build
> .\zig-out\bin\windows.exe
```

You should now see a 3D world with different things being rendered on screen where you can move around.

# The Source

The old `c++` is still there, although **only `src/windows.zig` is relevant** right now. Everything is there, the math, the pipeline, the rasterer, the .obj and .tga files reader... everything.

If you are curious, the way the application works is:

1. You define a rendering pipeline with comptine known information. Here is a rendering pipeline which renders a 3D object using gouraud shading.

```zig
const gouraud_renderer = struct {
    
    const Context = struct {
        texture: Buffer2D(RGB),
        texture_width: usize,
        texture_height: usize,
        view_model_matrix: M44,
        projection_matrix: M44,
        light_position_camera_space: Vector3f,
    };
    
    const Invariant = struct {
        texture_uv: Vector2f,
        light_intensity: f32,
    };
    
    const Vertex = struct {
        pos: Vector3f,
        uv: Vector2f,
        normal: Vector3f,
    };
    
    const pipeline_configuration = GraphicsPipelineConfiguration {
        .blend_with_background = false,
        .use_index_buffer = false,
        .do_triangle_clipping = false,
        .do_depth_testing = true,
        .do_perspective_correct_interpolation = true,
        .do_scissoring = false,
        .use_triangle_2 = use_triangle_2,
    };

    const Pipeline = GraphicsPipeline(
        win32.RGBA, Context, Invariant, Vertex, pipeline_configuration,
        struct {
            fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                const position_camera_space = context.view_model_matrix.apply_to_vec3(vertex.pos);
                const light_direction = context.light_position_camera_space.substract(position_camera_space.discard_w()).normalized();
                out_invariant.light_intensity = std.math.clamp(vertex.normal.normalized().dot(light_direction), 0, 1);
                out_invariant.texture_uv = vertex.uv;
                return context.projection_matrix.apply_to_vec4(position_camera_space);
            }
        }.vertex_shader,
        struct {
            fn fragment_shader(context: Context, invariants: Invariant) win32.RGBA {
                const sample =
                    if (bilinear) texture_bilinear_sample(RGB, true, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv)
                    else texture_point_sample(RGB, true, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv);
                const rgba = sample.scale(invariants.light_intensity);
                return win32.rgba(rgba.r, rgba.g, rgba.b, 255);
            }
        }.fragment_shader,
    );

};
```

2. Then you execute the pipeline with some input.

```zig
const render_requirements: gouraud_renderer.pipeline_configuration.Requirements() = .{
    .depth_buffer = state.depth_buffer,
    .viewport_matrix = state.viewport_matrix,
};
gouraud_renderer.Pipeline.render(state.pixel_buffer, render_context, vertex_buffer.items, @divExact(vertex_buffer.items.len, 3), render_requirements);
```

All the rendering stuff hapens in `GraphicsPipeline::render()`. For now the pipeline is constructed out of `comptime` known values, which means there is no branching when checking whether a renderer feature is active or not.

This is all very much a learning project and is not particularly fast, but it's probably alright for simple 2D games that dont aim to have 1080p resolutions, which is neat.
