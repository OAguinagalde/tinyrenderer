#include "win32.h"
#include "my_gl.h"
#include "tgaimage.h" // for loading the texutre since its in .tga format
#include "model.h" // for loading .obj models

const uint32_t whiteTransparent = u32rgba(255, 255, 255, 50);
const uint32_t white = u32rgba(255, 255, 255, 255);
const uint32_t black = u32rgba(0, 0, 0, 255);
const uint32_t red = u32rgba(255, 0, 0, 255);
const uint32_t green = u32rgba(0, 255, 0, 255);
const uint32_t blue = u32rgba(0, 0, 255, 255);
const uint32_t orange = u32rgba(255, 191, 0, 255);

#undef MAX
#define MAX(a,b) ((a) > (b) ? (a) : (b))
#undef MIN
#define MIN(a,b) ((a) < (b) ? (a) : (b))
#undef ABSOLUTE
#define ABSOLUTE(a) ((a) < 0 ? (-a) : (a))
void swap_int(int* a, int* b) { int c = *a; *a = *b; *b = c; }

#include <chrono>

std::chrono::steady_clock::time_point measure_time() {
    return std::chrono::high_resolution_clock::now();
}

void measure_since(std::chrono::steady_clock::time_point start) {
    auto stop = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(stop - start);
    long long ns = duration.count();
    printf("Measured %lldns\n", ns);
}

#include <functional>

// usage example:
// 
//     defer  ([](){ printf("Dont use unnamed defer instances! this will run straight away! Bad!");
//     defer d([](){ printf("Hello from the end of the scope!"); });
// 
class defer {
    std::function<void()> deferred_action;
public:
    defer(std::function<void()> f) : deferred_action(f) {}
    ~defer() {
        deferred_action();
    }
    defer& operator=(const defer&) = delete;
    defer(const defer&) = delete;
};

struct TextureQuadShader : public gl::IShader {

    TextureQuadShader(float* data, PixelBuffer texture) : vertex_buffer(data), texture(texture) {}
    
    // { location_x, location_y, location_z, text_u, text_v } * 3 * tirangle_count
    // 2 triangles per character
    float* vertex_buffer;

    // resources used during fragment shader
    PixelBuffer texture;

    // Invariants (written by vertex shader, read by fragment shader)
    Vec2f text_uvs[3];

    virtual bool vertex(int iface, int nthvert, Vec3f* screen_position) {
        int offset = (iface * 3 * 5) + (5 * nthvert);
        Vec3f vertex_position(
            vertex_buffer[offset + 0],
            vertex_buffer[offset + 1],
            vertex_buffer[offset + 2]
        );
        Vec2f vertex_uv(
            vertex_buffer[offset + 3],
            vertex_buffer[offset + 4]
        );
        text_uvs[nthvert] = vertex_uv;
        *screen_position = vertex_position;
        return false;
    }

    virtual bool fragment(Vec3f bar, uint32_t* out_color) {
        Vec2f interpolated_text_uv = gl::barycentric_inverse(text_uvs, bar);
        uint32_t texture_sample = texture.get(interpolated_text_uv.x, interpolated_text_uv.y);
        *out_color = texture_sample;
        return false;
    }
};

struct GouraudShader : public gl::IShader {

    // Expected data:
    // { location_x, location_y, location_z, text_u, text_v, normal_x, normal_y, normal_z } * 3 * tirangle_count
    float* vertex_buffer;
    
    // Invariants (written by vertex shader, read by fragment shader)
    float light_intensities[3];
    Vec2f text_uvs[3];

    // vertex shader params
    // precomputed: viewport_matrix * projection_matrix * view_matrix * model_matrix
    m44 viewport_matrix;
    m44 projection_matrix;
    m44 view_model_matrix;
    Vec3f light_source;

    // resources used during fragment shader
    PixelBuffer texture;

    virtual bool vertex(int iface, int nthvert, Vec3f* screen_position) {

        int offset = (iface * 3 * 8) + (8 * nthvert);

        Vec3f vertex_position(
            vertex_buffer[offset + 0],
            vertex_buffer[offset + 1],
            vertex_buffer[offset + 2]
        );
        Vec3f world_position = gl::retro_project_back_into_3d(view_model_matrix * gl::embed_in_4d(vertex_position));
        Vec3f clip_position = gl::retro_project_back_into_3d(projection_matrix * gl::embed_in_4d(world_position));

        if (clip_position.x >= 1.0f || clip_position.x <= -1.0f || clip_position.y >= 1.0f || clip_position.y <= -1.0f || clip_position.z >= 1.0f || clip_position.z <= -1.0f) {
            // If the triangle is not fully visible, skip it
            return true;
        }

        *screen_position = gl::retro_project_back_into_3d(viewport_matrix * gl::embed_in_4d(clip_position));
        
        Vec3f vertex_normal(
            vertex_buffer[offset + 5],
            vertex_buffer[offset + 6],
            vertex_buffer[offset + 7]
        );
        vertex_normal.normalize();
        Vec3f light_direction = (light_source - world_position).normalized();
        light_intensities[nthvert] = MIN(MAX(0.f, vertex_normal * light_direction), 1.f);

        Vec2f vertex_uv(
            vertex_buffer[offset + 3] * texture.width,
            vertex_buffer[offset + 4] * texture.height
        );
        text_uvs[nthvert] = vertex_uv;

        return false;
    }

    virtual bool fragment(Vec3f bar, uint32_t* out_color) {

        // interpolate the light intensity in this particular pixel
        float intensity = 0;
        intensity += light_intensities[0] * bar.w;
        intensity += light_intensities[1] * bar.u;
        intensity += light_intensities[2] * bar.v;

        // clamp light intensity to 1 of 6 different levels (not needed but cool)
        if (intensity>.85) intensity = 1;
        else if (intensity>.60) intensity = .80;
        else if (intensity>.45) intensity = .60;
        else if (intensity>.30) intensity = .45;
        else if (intensity>.15) intensity = .30;
        else intensity = .15;

        // interpolate texture_uv for the current pixel and sample texture
        Vec2f interpolated_text_uv = gl::barycentric_inverse(text_uvs, bar);
        uint32_t texture_sample = texture.get(interpolated_text_uv.x, interpolated_text_uv.y);

        // final color is the texture color times the intensity of the light
        u32rgba_unpack(texture_sample, r, g, b, a);
        // r = 255; g = 255; b = 255; a = 255;
        *out_color = u32rgba(intensity * r, intensity * g, intensity * b, intensity * a);

        // Do not discard the pixel
        return false;
    }
};

char char_lower(char c) {
    if (c >= 65 && c <= 90) c += 32;
    return c;
}
struct float4 { float f[4]; };
float4 char_uv(char c) {
    float4 uv;
    c = char_lower(c);
    uv.f[0] = (c%16)*8;
    uv.f[1] = (c/16)*8;
    uv.f[2] = 4;
    uv.f[3] = 8;
    return uv;
}
    
void render_text(PixelBuffer pixel_buffer, Vec2i pos, uint32_t color, const char* text, size_t text_size) {
    // bitmap font embeded in the executable
    #include "texture_font.cpp"
    static PixelBuffer texture(texture_font_width, texture_font_height, texture_font_data);
    // 1 vertex = 5 floats { location_x, location_y, location_z, text_u, text_v }
    // 1 triangle = 3 vertices
    // 1 quad = 2 triangles
    // 1 char = 1 quad
    // Up to 1024 characters
    static float vertices[5*3*2*1024] = {0};

    float size_factor = 1.0f;
    // size_factor = 2.0f;
    // size_factor = 0.5f;
    int offset_x = 0;
    int offset_y = 0;
    for(int i = 0; i < text_size; i++) {
        // if (text[i] == '\n') {
        //     offset_y += (8*size_factor);
        //     offset_x = -((i+1)*(4*size_factor));
        //     continue;
        // }
        char c = text[i];
        int x = offset_x + (pos.x + i * (4 * size_factor));
        int y = offset_y + pos.y;
        int u1 = (c%16) * 8;
        int v1 = (c/16) * 8;
        int u2 = u1 + 4;
        int v2 = v1 + 8;
        int w = 4.0f * size_factor;
        int h = 8.0f * size_factor;
        int offset = i*5*3*2;

        vertices[offset + 0] = x;
        vertices[offset + 1] = y;
        vertices[offset + 2] = 0;
        vertices[offset + 3] = u1;
        vertices[offset + 4] = v1;

        vertices[offset + 5] = x + w;
        vertices[offset + 6] = y;
        vertices[offset + 7] = 0;
        vertices[offset + 8] = u2;
        vertices[offset + 9] = v1;

        vertices[offset + 10] = x;
        vertices[offset + 11] = y - h;
        vertices[offset + 12] = 0;
        vertices[offset + 13] = u1;
        vertices[offset + 14] = v2;

        vertices[offset + 15] = x;
        vertices[offset + 16] = y - h;
        vertices[offset + 17] = 0;
        vertices[offset + 18] = u1;
        vertices[offset + 19] = v2;

        vertices[offset + 20] = x + w;
        vertices[offset + 21] = y - h;
        vertices[offset + 22] = 0;
        vertices[offset + 23] = u2;
        vertices[offset + 24] = v2;

        vertices[offset + 25] = x + w;
        vertices[offset + 26] = y;
        vertices[offset + 27] = 0;
        vertices[offset + 28] = u2;
        vertices[offset + 29] = v1;
    }

    TextureQuadShader shader(vertices, texture);
    for (int i = 0; i < text_size*2; i++) {
        bool skip = false;
        Vec3f screen_coords[3];
        for (int j=0; j<3; j++) {
            skip = shader.vertex(i, j, &screen_coords[j]);
            if (skip) break;
        }
        if (skip) continue;
        gl::triangle(pixel_buffer, screen_coords, &shader);
    }
}

m44 view_matrix;
m44 viewport_matrix;
m44 projection_matrix;
bool keys[256] = {};

void render_dot(PixelBuffer pixel_buffer, FloatBuffer z_buffer, camera camera, Vec3f p, uint32_t color) {
    Vec3f p_real = gl::retro_project_back_into_3d(viewport_matrix * projection_matrix * view_matrix * gl::embed_in_4d(p));
    gl::dot(pixel_buffer, z_buffer, p_real, color);
}

void render_line(PixelBuffer pixel_buffer, FloatBuffer z_buffer, camera camera, Vec3f start, Vec3f end, uint32_t color) {
    Vec3f start_clip = gl::retro_project_back_into_3d(projection_matrix * view_matrix * gl::embed_in_4d(start));
    if (start_clip.x <= -1 || start_clip.y <= -1 || start_clip.z <= -1 || start_clip.x >= 1 || start_clip.y >= 1 || start_clip.z >= 1) return;
    Vec3f end_clip = gl::retro_project_back_into_3d(projection_matrix * view_matrix * gl::embed_in_4d(end));
    if (end_clip.x <= -1 || end_clip.y <= -1 || end_clip.z <= -1 || end_clip.x >= 1 || end_clip.y >= 1 || end_clip.z >= 1) return;

    Vec3f start_real = gl::retro_project_back_into_3d(viewport_matrix * gl::embed_in_4d(start_clip));
    Vec3f end_real = gl::retro_project_back_into_3d(viewport_matrix * gl::embed_in_4d(end_clip));
    gl::line(pixel_buffer, z_buffer, start_real, end_real, color);
}

void render_model(PixelBuffer pixel_buffer, FloatBuffer z_buffer, camera camera, float* vertex_buffer, int faces, PixelBuffer texture_data, Vec3f light_source, float scale_factor, Vec3f pos) {
    GouraudShader shader;
    shader.view_model_matrix = view_matrix * m44::translation(pos) * m44::scaling(scale_factor);
    shader.vertex_buffer = vertex_buffer;
    shader.projection_matrix = projection_matrix;
    shader.viewport_matrix = viewport_matrix;
    shader.texture = texture_data;
    shader.light_source = gl::retro_project_back_into_3d(view_matrix * gl::embed_in_4d(light_source));

    for (int i = 0; i < faces; i++) {
        bool skip = false;
        Vec3f screen_coords[3];
        for (int j=0; j<3; j++) {
            skip = shader.vertex(i, j, &screen_coords[j]);
            if (skip) break;
        }
        if (skip) continue;
        gl::triangle2(pixel_buffer, z_buffer, screen_coords, &shader);
    }

}

bool onUpdate(double dt_ms, unsigned long long fps) {

    auto wc = win32::GetWindowContext();
    static int render_width = 200;
    static int render_height = 200;
    static const char* render_name = "textured.tga";
    
    /* setup the window */ {

        // Initialize the pixel buffer of the window
        if (!wc->IsActive()) {
            win32::NewWindowRenderTarget(render_width, render_height);
        }

        // Make sure the size of the window is correct
        int cw, ch;
        win32::GetClientSize(wc->window_handle, &cw, &ch);
        if (cw != wc->width) {
            win32::SetWindowClientSize(wc->window_handle, wc->width, wc->height);
        }
    }
    
    PixelBuffer pixels(wc->width, wc->height, wc->pixels);
    pixels.clear(black);

    /* render to pixel buffer */ {
        
        // camera
        static camera cam;
        // depth buffer
        static FloatBuffer z_buffer(pixels.width, pixels.height);
        // texture
        static PixelBuffer texture(0, 0);
        // model
        static float* vertex_buffer;
        static int triangles;
        // total time
        static float time = 0.0f;
        
        static bool firstFrame = true;
        if (firstFrame) {
            /* Load texture into a pixel buffer */ {
                TGAImage diffuse_texture_data("res/african_head_diffuse.tga");
                diffuse_texture_data.flip_vertically();
                texture.width = diffuse_texture_data.get_width();
                texture.height = diffuse_texture_data.get_height();
                texture.data = (uint32_t*)malloc(sizeof(uint32_t) * texture.width * texture.height);
                for (int i = 0; i < texture.width * texture.height; i++) {
                    int row = i / texture.width;
                    int column = i - row * texture.width;
                    TGAColor c = diffuse_texture_data.get(column, row);
                    texture.data[i] = u32rgba(c.r, c.g, c.b, c.a);
                }
            }
            /* Load model into a vertex buffer */ {
                Model model("res/african_head.obj");
                // Model model("res/quad.obj");
                triangles = model.nfaces();
                int required_size = model.get_vertex_buffer_size();
                vertex_buffer = (float*)malloc(required_size);
                model.load_vertex_buffer(vertex_buffer);

                // Aparently in obj the coordinates seem to be normalized so everything is between 0 and 1
                // So, for the texture coords, gotta scale them with the textures size. But, if
                // 
                //     for (int i = 0; i < triangles; i++) {
                //         for (int j = 0; j < 3; j++) {
                //             vertex_buffer[(i*3*8)+(j*8)+3] *= texture.get_width();
                //             vertex_buffer[(i*3*8)+(j*8)+4] *= texture.get_height();
                //         }
                //     }
                // 
            }
            cam.position = Vec3f(1, 1, 3);
            cam.up = Vec3f(0, 1, 0);
            cam.direction = Vec3f(0, 0, 1);
            firstFrame = false;
        }
        
        // advance time
        if (keys['T']) time += dt_ms;

        static POINT mouse1 = {0,0};
        static POINT mouse2 = {0,0};
        static float factor1 = 0.02f;
        static Vec3f direction(0, 0, 0);
        GetCursorPos(&mouse2);
        float dx = (mouse2.x - mouse1.x) * factor1;
        float dy = (mouse2.y - mouse1.y) * factor1 * -1.0f;
        mouse1 = mouse2;
        
        Vec3f up(0,1,0);
        Vec3f real_right = (cam.direction ^ up).normalized();
        Vec3f real_up = (cam.direction ^ real_right).normalized() * -1.f;
        if (dx != 0 || dy != 0) {
            cam.direction = cam.direction + (real_right * dx);
            if (cam.direction.y <0.95 && cam.direction.y > -0.95) {
                cam.direction = cam.direction + (real_up * dy);
            }
            cam.direction.normalize();
        }

        float factor = 2000;
        Vec3f horizontally_spinning_position(cos(time / factor), .0, sin(time / factor));
        Vec3f vertically_spinning_position(0, cos(time / factor), sin(time / factor));
        uint32_t smooth_color = u32rgba(cos(time / factor) * 255, sin(time / factor) * 255, tan(time / factor) * 255, 255);

        if (keys['W']) cam.position = cam.position + (cam.direction * factor1);
        if (keys['S']) cam.position = cam.position + (cam.direction * factor1) * -1.0f;
        if (keys['A']) cam.position = cam.position + (real_right * factor1) * -1.0f;
        if (keys['D']) cam.position = cam.position + (real_right * factor1);
        if (keys['Q']) cam.position.y += factor1;
        if (keys['E']) cam.position.y -= factor1;

        cam.looking_at = cam.position + cam.direction;
        // cam.looking_at.x = cam.position.x;
        // cam.looking_at.y = cam.position.y;
        // cam.looking_at.z = cam.position.z-2;


        Vec3f light_source = horizontally_spinning_position;

        view_matrix = gl::lookat2(cam.position, cam.looking_at, cam.up);
        viewport_matrix = gl::viewport(0, 0, pixels.width, pixels.height);
        projection_matrix = gl::projection(-1 / (cam.position - cam.looking_at).norm());

        if (keys['P']) projection_matrix = m44::identity();
        if (keys['V']) viewport_matrix = m44::identity();

        z_buffer.clear(-9999999);
        
        if (true) render_model(pixels, z_buffer, cam, vertex_buffer, triangles, texture, light_source, 1.0f, Vec3f(0.0f, 0.0f, -1.0f));
        if (false) render_model(pixels, z_buffer, cam, vertex_buffer, triangles, texture, light_source, 2.3f, Vec3f(0.0f, 0.0f, -4.0f));

        if (true) {
            // draw a cube made out of lines
            // plane z = 2
            render_line(pixels, z_buffer, cam, Vec3f(-2, -2, 2), Vec3f(2, -2, 2), red);
            render_line(pixels, z_buffer, cam, Vec3f(2, -2, 2), Vec3f(2, 2, 2), red);
            render_line(pixels, z_buffer, cam, Vec3f(2, 2, 2), Vec3f(-2, 2, 2), red);
            render_line(pixels, z_buffer, cam, Vec3f(-2, 2, 2), Vec3f(-2, -2,  2), red);
            // plane z = -2
            render_line(pixels, z_buffer, cam, Vec3f(-2, -2, -2), Vec3f(2, -2, -2), orange);
            render_line(pixels, z_buffer, cam, Vec3f(2, -2, -2), Vec3f(2, 2, -2), orange);
            render_line(pixels, z_buffer, cam, Vec3f(2, 2, -2), Vec3f(-2, 2, -2), orange);
            render_line(pixels, z_buffer, cam, Vec3f(-2, 2, -2), Vec3f(-2, -2, -2), orange);

            // draw the unit vectors at (0, 0, 0)
            render_line(pixels, z_buffer, cam, Vec3f(-1, 0, 0), Vec3f(1, 0, 0), blue);
            render_line(pixels, z_buffer, cam, Vec3f(0, -1, 0), Vec3f(0, 1, 0), red);
            render_line(pixels, z_buffer, cam, Vec3f(0, 0, -1), Vec3f(0, 0, 1), green);
        }

        // TODO For some reason, points that are not normalized (0, 1), dont render properly,
        // Although it seems like the model renderer has no issue with that tho?
        render_line(pixels, z_buffer, cam, Vec3f(-100, 0, 0), Vec3f(100, 0, 0), white);
        render_line(pixels, z_buffer, cam, Vec3f(0,-100,0), Vec3f(0,100,0), white);
        render_line(pixels, z_buffer, cam, Vec3f(0,0,100), Vec3f(0,0,-100), white);

        // render_dot(pixels, z_buffer, cam, Vec3f(1, 1, 1), green);
        // render_dot(pixels, z_buffer, cam, Vec3f(-1, 1, 1), green);
        // render_dot(pixels, z_buffer, cam, Vec3f(1,-1,1), green);
        // render_dot(pixels, z_buffer, cam, Vec3f(1,1,-1), red);
        // render_dot(pixels, z_buffer, cam, Vec3f(-1,-1,-1), red);
        // render_dot(pixels, z_buffer, cam, Vec3f(1,-1,-1), red);
        // render_dot(pixels, z_buffer, cam, Vec3f(-1,1,-1), red);
        // render_dot(pixels, z_buffer, cam, Vec3f(-1,-1,1), green);

        // render_dot(pixels, z_buffer, cam, light_source, white);

        // auto distance = (Vec3f(0, 0, 0) - Vec3f(1, 0, 2)).norm();
        // auto m = gl::lookat(Vec3f(1, 0, 2), Vec3f(0, 0, 0), Vec3f(0, 1, 0));
        // auto viewport = gl::viewport(0, 0, pixels.width, pixels.height);
        // auto p = Vec3f(0, 0, 1);
        // auto p_ = gl::retro_project_back_into_3d(viewport * m * gl::embed_in_4d(p));
        // auto c_ = gl::retro_project_back_into_3d(viewport * m * gl::embed_in_4d(Vec3f(0,0,0)));
        // gl::fat_dot(Vec2i(p_.x, p_.y), pixels, blue);
        // gl::fat_dot(Vec2i(c_.x, c_.y), pixels, red);

        static char text[1024];
        static int total_chars;
        int line = 1;
        total_chars = snprintf(text, 1024, "FPS %llu, ms %f", fps, dt_ms);
        render_text(pixels, Vec2i(10, pixels.height - line++ *10), red, text, total_chars);
        total_chars = snprintf(text, 1024, "camera: %f, %f, %f", cam.position.x, cam.position.y, cam.position.z);
        render_text(pixels, Vec2i(10, pixels.height - line++ *10), red, text, total_chars);
        total_chars = snprintf(text, 1024, "mouse %d, %d", mouse2.x, mouse2.y);
        render_text(pixels, Vec2i(10, pixels.height - line++ *10), red, text, total_chars);
        total_chars = snprintf(text, 1024, "distance: %f", (cam.position - cam.looking_at).norm());
        render_text(pixels, Vec2i(10, pixels.height - line++ * 10), red, text, total_chars);
        total_chars = snprintf(text, 1024, "cam direction: %f, %f, %f", cam.direction.x, cam.direction.y, cam.direction.z);
        render_text(pixels, Vec2i(10, pixels.height - line++ *10), red, text, total_chars);


        // total_chars = snprintf(text, 1024, "p_: %f, %f, %f", p_.x, p_.y, p_.z);
        // render_text(pixels, Vec2i(10, pixels.height - line++ *15), red, text, total_chars);
        
        // total_chars = snprintf(text, 1024, "m: %f, %f, %f, %f", m[0][0], m[0][1], m[0][2], m[0][3]);
        // render_text(pixels, Vec2i(10, pixels.height - line++ *15), red, text, total_chars);
        // total_chars = snprintf(text, 1024, "   %f, %f, %f, %f", m[1][0], m[1][1], m[1][2], m[1][3]);
        // render_text(pixels, Vec2i(10, pixels.height - line++ *15), red, text, total_chars);
        // total_chars = snprintf(text, 1024, "   %f, %f, %f, %f", m[2][0], m[2][1], m[2][2], m[2][3]);
        // render_text(pixels, Vec2i(10, pixels.height - line++ *15), red, text, total_chars);
        // total_chars = snprintf(text, 1024, "   %f, %f, %f, %f", m[3][0], m[3][1], m[3][2], m[0][3]);
        // render_text(pixels, Vec2i(10, pixels.height - line++ *15), red, text, total_chars);
    }

    /* stats and debugging stuff */ {
    
        // Some kind of performance visualizer
        uint32_t performance_color = u32rgba(255, 0, 0, 255);
        float performance_base = 128.0f;
        if (dt_ms < 64.0f) { performance_base = 64.0f; performance_color = u32rgba(255, 150, 0, 255); }
        if (dt_ms < 32.0f) { performance_base = 32.0f; performance_color = u32rgba(240, 204, 0, 255); }
        if (dt_ms < 16.0f) { performance_base = 16.0f; performance_color = u32rgba(174, 255, 0, 255); }
        gl::line(pixels, Vec2i(0,0), Vec2i( MIN((dt_ms / performance_base) * pixels.width, pixels.width), 0), performance_color);
        gl::line(pixels, Vec2i(0,1), Vec2i( MIN((dt_ms / performance_base) * pixels.width, pixels.width), 1), performance_color);
        
        // static short cursorx, cursory;
        // if (win32::ConsoleGetCursorPosition(&cursorx, &cursory)) {
        //     win32::FormattedPrint("fps %d, ms %f, space_pressed %d", fps, dt_ms, space_pressed);
        //     win32::ConsoleSetCursorPosition(cursorx, cursory);
        // }
    }

    return true;
}

bool window_callback(HWND window, UINT messageType, WPARAM param1, LPARAM param2) {

    // if (messageType == WM_KEYDOWN && param1 == VK_SPACE)
    if (messageType == WM_KEYDOWN && param1 < 256 && param1 >= 0) {
        keys[param1] = true;
    }
    if (messageType == WM_KEYUP && param1 < 256 && param1 >= 0) {
        keys[param1] = false;
    }
    
    return false;
}

int main(int argc, char** argv) {
    srand(time(NULL));

    /* window scope */ {
        int w = 100, h = 100;
        int x = 1920 + 1920 - 500;
        // x = 100;
        int y = 1080 - 500;
        // y = 100;
        auto window = win32::NewWindow("myWindow", "tinyrenderer", x, y, w, h, &window_callback);
        defer _([window]() { win32::CleanWindow("myWindow", window); });

        // make sure there is a console attached, or create one if not
        bool haveConsole = true;
        if (win32::ConsoleAttach() != win32::ConsoleAttachResult::SUCCESS) {
            haveConsole = false;
            if (win32::ConsoleCreate() == win32::ConsoleCreateResult::SUCCESS) {
                auto consoleWindow = win32::ConsoleGetWindow();
                //win32::SetWindowPosition(consoleWindow, x+w, y);
                haveConsole = true;
            }
        }
        defer __([haveConsole]() { if (haveConsole) win32::ConsoleFree(); });

        win32::NewWindowLoopStart(window, onUpdate);
        win32::CleanWindowRenderTarget();
    }
}
