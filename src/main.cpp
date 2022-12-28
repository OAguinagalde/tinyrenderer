#include <vector>
#include <cmath>
#include <iostream>

#include "win32.h"
#include "tgaimage.h"
#include "model.h"
#include "my_gl.h"

const uint32_t whiteTransparent = u32rgba(255, 255, 255, 50);
const uint32_t white = u32rgba(255, 255, 255, 255);
const uint32_t red = u32rgba(255, 0, 0, 255);
const uint32_t green = u32rgba(0, 255, 0, 255);
const uint32_t blue = u32rgba(0, 0, 255, 255);
const uint32_t aaa = u32rgba(125, 55, 255, 255);

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

struct GouraudShader : public gl::IShader {

    // Expected data:
    // { location_x, location_y, location_z, text_u, text_v, normal_x, normal_y, normal_z } * 3 * tirangle_count
    float* vertex_buffer;
    
    // Invariants (written by vertex shader, read by fragment shader)
    Vec3f vertices[3];
    Vec3f normals[3];
    Vec2f text_uv[3];

    // vertex shader params
    // precomputed: viewport_matrix * projection_matrix * view_matrix * model_matrix
    Matrix transformations_matrix;

    // resources used during fragment shader
    Vec3f light_position;
    PixelBuffer texture;

    virtual Vec3f vertex(int iface, int nthvert) {

        int offset = (iface * 3 * 8) + (8 * nthvert);
        // Get current vertex's data from vertex_buffer

        Vec3f vertex_position;
        vertex_position.raw[0] = vertex_buffer[offset + 0];
        vertex_position.raw[1] = vertex_buffer[offset + 1];
        vertex_position.raw[2] = vertex_buffer[offset + 2];

        Matrix position = gl::embed_in_4d(vertex_position);
        Vec3f final_point = gl::retro_project_back_into_3d(transformations_matrix * position);

        // save some data about the vertex for the fragment to use later
        text_uv[nthvert].raw[0] = vertex_buffer[offset + 3] * texture.width;
        text_uv[nthvert].raw[1] = vertex_buffer[offset + 4] * texture.height;
        normals[nthvert].raw[0] = vertex_buffer[offset + 5];
        normals[nthvert].raw[1] = vertex_buffer[offset + 6];
        normals[nthvert].raw[2] = vertex_buffer[offset + 7];
        vertices[nthvert] = final_point;
        
        return final_point;
    }

    virtual bool fragment(Vec3f bar, uint32_t* out_color) {

        // interpolate intensity for the current pixel
        Vec3f interpolated_normal = gl::barycentric_inverse(normals, bar);
        
        // calculate the intensity of the light
        // Vec3f light_dir = light_position;
        
        Vec3f interpolated_position = gl::barycentric_inverse(vertices, bar);
        Vec3f light_dir = interpolated_position - light_position;
        float intensity = MAX(0.0f, interpolated_normal.normalize() * light_dir.normalized());
        
        // cool shader to make the light have 6 intensities
        if (intensity>.85) intensity = 1;
        else if (intensity>.60) intensity = .80;
        else if (intensity>.45) intensity = .60;
        else if (intensity>.30) intensity = .45;
        else if (intensity>.15) intensity = .30;
        else intensity = 0;

        // interpolate texture_uv for the current pixel        
        Vec2f interpolated_text_uv = gl::barycentric_inverse(text_uv, bar);
        // sample texture
        uint32_t texture_sample = texture.get(interpolated_text_uv.x, interpolated_text_uv.y);
        *out_color = (texture_sample * intensity);

        // Do not discard the pixel
        return false;
    }
};

void render(PixelBuffer pixel_buffer, float* vertex_buffer, int faces, PixelBuffer texture_data, camera camera, Vec3f light_position, float scale_factor, Vec3f pos, FloatBuffer* z_buffer) {
    
    int w = pixel_buffer.width;
    int h = pixel_buffer.height;

    // Where the light is "coming from"
    Matrix model_matrix = Matrix::t(pos) * Matrix::s(scale_factor);
    Matrix view_matrix = gl::lookat(camera.position, camera.looking_at, camera.up);
    Matrix viewport_matrix = gl::viewport(0, 0, w, h);
    Matrix projection_matrix = Matrix::identity();
    // float c = camera.position.z;
    float c = 0.5f;
    if (c != 0) projection_matrix[3][2] = -1 / c;

    Matrix point_camera_coords = view_matrix * model_matrix;
    Matrix point_clip_coords = projection_matrix * point_camera_coords;
    Matrix transformations_matrix = viewport_matrix * point_clip_coords;

    GouraudShader shader;
    shader.vertex_buffer = vertex_buffer;
    shader.transformations_matrix = transformations_matrix;
    shader.texture = texture_data;
    shader.light_position = gl::retro_project_back_into_3d(transformations_matrix * gl::embed_in_4d(light_position));

    for (int i = 0; i < faces; i++) {

        Vec3f screen_coords[3];

        for (int j=0; j<3; j++) {
            screen_coords[j] = shader.vertex(i, j);
        }

        gl::triangle2(screen_coords, &shader, pixel_buffer, z_buffer);
    }

}

bool window_callback(HWND window, UINT messageType, WPARAM param1, LPARAM param2) {
    // nothing is explicitly handled
    return false;
}

bool onUpdate(double dt_ms, unsigned long long fps) {

    auto wc = win32::GetWindowContext();
    static int render_width = 800;
    static int render_height = 800;
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
    pixels.clear(u32rgb(0, 0, 0));

    /* render to pixel buffer */ {
        
        static bool firstFrame = true;
        static PixelBuffer texture(0,0);
        static int triangles;
        static float* vertex_buffer;
        static camera cam;
        static float time = 0.0f;
        static Vec3f light_direction;
        static FloatBuffer z_buffer(pixels.width, pixels.height);

        if (firstFrame) {
            TGAImage diffuse_texture_data("res/african_head_diffuse.tga");
            diffuse_texture_data.flip_vertically();
            texture.width = diffuse_texture_data.get_width();
            texture.height = diffuse_texture_data.get_height();
            texture.data = (uint32_t*)malloc(sizeof(uint32_t) * texture.width * texture.height);
            for (int i = 0; i < texture.width * texture.height; i++) {
                int y = i % texture.width;
                int x = i / texture.width;
                TGAColor c = diffuse_texture_data.get(x, y);
                texture.data[i] = u32rgba(c.r, c.g, c.b, c.a);
            }

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
        
        time += dt_ms;
        float factor = 2000;
        Vec3f horizontally_spinning_position(cos(time / factor), 0, sin(time / factor));
        Vec3f vertically_spinning_position(0, cos(time / factor), sin(time / factor));
        uint32_t smooth_color = u32rgba(cos(time / factor) * 255, sin(time / factor) * 255, tan(time / factor) * 255, 255);

        cam.position = horizontally_spinning_position;
        cam.position = Vec3f(.2, .4, 2);
        cam.position.y += 0.2f;
        cam.looking_at = Vec3f(0, 0, 0);
        cam.up = Vec3f(0, 1, 0);
        
        Vec3f light_position = horizontally_spinning_position;

        z_buffer.clear(-99999);

        render(pixels, vertex_buffer, triangles, texture, cam, light_position, 0.3f, Vec3f(0.0f, 0.0f, 0.0f), &z_buffer);
        render(pixels, vertex_buffer, triangles, texture, cam, light_position, 0.1f, Vec3f(1.0f, 0.0f, 0.0f), &z_buffer);
        render(pixels, vertex_buffer, triangles, texture, cam, light_position, 0.1f, Vec3f(0.0f, 1.0f, 0.0f), &z_buffer);
        render(pixels, vertex_buffer, triangles, texture, cam, light_position, 0.1f, Vec3f(0.0f, 0.0f, 1.0f), &z_buffer);
        render(pixels, vertex_buffer, triangles, texture, cam, light_position, 0.1f, light_position, &z_buffer);

        firstFrame = false;
    }

    /* stats and debugging stuff */ {
    
        // Some kind of performance visualizer
        uint32_t performance_color = u32rgba(255, 0, 0, 255);
        float performance_base = 128.0f;
        if (dt_ms < 64.0f) { performance_base = 64.0f; performance_color = u32rgba(255, 150, 0, 255); }
        if (dt_ms < 32.0f) { performance_base = 32.0f; performance_color = u32rgba(240, 204, 0, 255); }
        if (dt_ms < 16.0f) { performance_base = 16.0f; performance_color = u32rgba(174, 255, 0, 255); }
        gl::line(Vec2i(0,0), Vec2i( MIN((dt_ms / performance_base) * pixels.width, pixels.width), 0), pixels, performance_color);
        gl::line(Vec2i(0,1), Vec2i( MIN((dt_ms / performance_base) * pixels.width, pixels.width), 1), pixels, performance_color);

        // mouse pos
        POINT mouse;
        GetCursorPos(&mouse);
        // gl::fat_dot(Vec2i(mouse.x, mouse.y), pixels, TGAColor(255, 0, 0, 255));
        
        static short cursorx, cursory;
        if (win32::ConsoleGetCursorPosition(&cursorx, &cursory)) {
            win32::FormattedPrint("fps %d, ms %f", fps, dt_ms);
            win32::ConsoleSetCursorPosition(cursorx, cursory);
        }
    }

    return true;
}

int main(int argc, char** argv) {
    srand(time(NULL));
    
    /* window scope */ {
        auto window = win32::NewWindow("myWindow", "tinyrenderer", 100, 100, 10, 10, &window_callback);
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
