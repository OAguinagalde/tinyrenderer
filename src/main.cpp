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
    float light_intensities[3];
    Vec2f text_uvs[3];

    // vertex shader params
    // precomputed: viewport_matrix * projection_matrix * view_matrix * model_matrix
    Matrix transformations_matrix;
    Matrix view_model_matrix;

    // resources used during fragment shader
    Vec3f light_position;
    PixelBuffer texture;

    virtual Vec3f vertex(int iface, int nthvert) {

        int offset = (iface * 3 * 8) + (8 * nthvert);

        Vec3f vertex_position(
            vertex_buffer[offset + 0],
            vertex_buffer[offset + 1],
            vertex_buffer[offset + 2]
        );
        Vec2f vertex_uv(
            vertex_buffer[offset + 3] * texture.width,
            vertex_buffer[offset + 4] * texture.height
        );
        Vec3f vertex_normal( // assume that vertex normals are normalized
            vertex_buffer[offset + 5],
            vertex_buffer[offset + 6],
            vertex_buffer[offset + 7]
        );

        Matrix world_position = view_model_matrix * gl::embed_in_4d(vertex_position);
        Vec3f screen_position = gl::retro_project_back_into_3d(transformations_matrix * world_position);
        
        // calculate light intensity in the current vertex

        // Vec3f light_dir = gl::retro_project_back_into_3d(world_position) - light_position;
        // Vec3f light_dir = light_position - gl::retro_project_back_into_3d(world_position);
        // Vec3f light_dir = Vec3f(0.1,0.1,0.1) - light_position;
        // Vec3f light_dir = light_position - Vec3f(0.1,0.1,0.1);
        // Vec3f light_dir = Vec3f(1,0,1);
        
        Vec3f light_dir = light_position;
        float light_intensity = vertex_normal.normalized() * light_dir;
        light_intensities[nthvert] = MAX(0.f, light_intensity);
        text_uvs[nthvert] = vertex_uv;

        return screen_position;
    }

    virtual bool fragment(Vec3f bar, uint32_t* out_color) {

        // interpolate the light intensity in this particular pixel
        float intensity = 0;
        intensity += light_intensities[0] * bar.w;
        intensity += light_intensities[1] * bar.u;
        intensity += light_intensities[2] * bar.v;

        // clamp light intensity to 1 of 6 different levels (not needed but cool)
        // if (intensity>.85) intensity = 1;
        // else if (intensity>.60) intensity = .80;
        // else if (intensity>.45) intensity = .60;
        // else if (intensity>.30) intensity = .45;
        // else if (intensity>.15) intensity = .30;
        // else intensity = .0;

        // interpolate texture_uv for the current pixel and sample texture
        Vec2f interpolated_text_uv = gl::barycentric_inverse(text_uvs, bar);
        uint32_t texture_sample = texture.get(interpolated_text_uv.x, interpolated_text_uv.y);

        // final color is the texture color times the intensity of the light
        u32rgba_unpack(texture_sample, r, g, b, a);
        *out_color = u32rgba(intensity * r, intensity * g, intensity * b, intensity * a);

        // Do not discard the pixel
        return false;
    }
};

void render(PixelBuffer pixel_buffer, float* vertex_buffer, int faces, PixelBuffer texture_data, camera camera, Vec3f light_position, float scale_factor, Vec3f pos, FloatBuffer* z_buffer) {
    
    Matrix view_matrix = gl::lookat(camera.position, camera.looking_at, camera.up);
    Matrix viewport_matrix = gl::viewport(0, 0, pixel_buffer.width, pixel_buffer.height);
    Matrix projection_matrix = Matrix::identity();
    
    float c = 0.8f;
    if (c != 0) projection_matrix[3][2] = -1 / c;

    Matrix light_matrix = Matrix::t(light_position);
    Matrix model_matrix = Matrix::t(pos) * Matrix::s(scale_factor);
    Matrix transformations_matrix = viewport_matrix * projection_matrix;

    GouraudShader shader;
    shader.view_model_matrix = view_matrix * model_matrix;
    shader.vertex_buffer = vertex_buffer;
    shader.transformations_matrix = transformations_matrix;
    shader.texture = texture_data;
    shader.light_position = gl::retro_project_back_into_3d(view_matrix * light_matrix * gl::embed_in_4d(Vec3f(0,0,0)));
    // shader.light_position = light_position;

    for (int i = 0; i < faces; i++) {

        Vec3f screen_coords[3];

        for (int j=0; j<3; j++) {
            screen_coords[j] = shader.vertex(i, j);
        }

        gl::triangle(screen_coords, &shader, pixel_buffer, z_buffer);
    }

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
    pixels.clear(white);

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
            firstFrame = false;
        }
        
        // "advance time" and others
        time += dt_ms;
        float factor = 2000;
        Vec3f horizontally_spinning_position(cos(time / factor), 0, sin(time / factor));
        horizontally_spinning_position.y += 0.4;
        Vec3f vertically_spinning_position(0, cos(time / factor), sin(time / factor));
        uint32_t smooth_color = u32rgba(cos(time / factor) * 255, sin(time / factor) * 255, tan(time / factor) * 255, 255);

        // clear the depth buffer
        z_buffer.clear(-9999999);
        
        // update camera
        cam.position = Vec3f(.2, .35, 1);
        // cam.position.y += 0.2f;
        // cam.position = horizontally_spinning_position;
        cam.looking_at = Vec3f(0, 0, 0);
        cam.up = Vec3f(0, 1, 0);
        
        // move light
        Vec3f light_position = horizontally_spinning_position;

        render(pixels, vertex_buffer, triangles, texture, cam, light_position, 1.0f, Vec3f(0.0f, 0.0f, 0.0f), &z_buffer);
        // render(pixels, vertex_buffer, triangles, texture, cam, light_position, 0.1f, Vec3f(1.0f, 0.0f, 0.0f), &z_buffer);
        // render(pixels, vertex_buffer, triangles, texture, cam, light_position, 0.1f, Vec3f(0.0f, 1.0f, 0.0f), &z_buffer);
        // render(pixels, vertex_buffer, triangles, texture, cam, light_position, 0.1f, Vec3f(0.0f, 0.0f, 1.0f), &z_buffer);
        // render(pixels, vertex_buffer, triangles, texture, cam, light_position, 0.1f, light_position, &z_buffer);
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

bool window_callback(HWND window, UINT messageType, WPARAM param1, LPARAM param2) {
    // nothing is explicitly handled
    return false;
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
