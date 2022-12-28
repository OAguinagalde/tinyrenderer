#ifndef __MY_GL_H__
#define __MY_GL_H__


#include "geometry.h"

#define u32rgba(r,g,b,a) ((uint32_t)(((uint8_t)r << 8*3) | ((uint8_t)g << 8*2) | ((uint8_t)b << 8*1) | ((uint8_t)a << 8*0) ))
#define u32rgb(r,g,b) u32rgba(r,g,b,255)

struct FloatBuffer {

    float* data;
    int width;
    int height;

    // mallocs the data buffer. free with `destroy()`
    FloatBuffer(int w, int h);

    // doesn't malloc anything, manage the buffer yourself!
    FloatBuffer(int w, int h, float* data);

    float get(int x, int y);

    void set(int x, int y, float value);

    void destroy();
    
    // set every to input value
    void clear(float value);

    // assumes same sizes!
    void load(FloatBuffer* other);

};

struct PixelBuffer {

    uint32_t* data;
    int width;
    int height;

    PixelBuffer();
    PixelBuffer(int w, int h);
    PixelBuffer(int w, int h, uint32_t* buffer);
    void destroy();

    void clear(uint32_t c);
    
    // assumes buffers are the same size
    void load(PixelBuffer other);

    float get(int x, int y);
    void set(int x, int y, uint32_t pixel);
};

struct camera {
    Vec3f position;
    Vec3f looking_at;
    Vec3f up;
};

namespace gl {

    Matrix viewport(int x, int y, int w, int h, int depth = 255);
    Matrix projection(float coeff = 0.f);
    Matrix lookat(Vec3f eye, Vec3f center, Vec3f up);

    // Retro-project a point in "4d" back into "3d"
    //     
    //     | x |    | x/w |
    //     | y | => | y/w |
    //     | z |    | z/w |
    //     | w |         
    //
    Vec3f retro_project_back_into_3d(Matrix point_4d);
    
    // Embed the point into "4D" by augmenting it with 1, so that we can work with it.
    // 
    //     | x |    | x |
    //     | y | => | y |
    //     | z |    | z |
    //              | 1 |
    //     
    Matrix embed_in_4d(Vec3f point);


    Vec2f barycentric_inverse(Vec2f triangle[3], Vec3f barycentric);
    Vec3f barycentric_inverse(Vec3f triangle[3], Vec3f barycentric);

    struct IShader {
        virtual Vec3f vertex(int iface, int nthvert) = 0;
        virtual bool fragment(Vec3f bar, uint32_t* out_color) = 0;
    };

    void line(Vec2i a, Vec2i b, PixelBuffer image, uint32_t color);
    void triangle_outline(Vec2i t[3], PixelBuffer image, uint32_t color);
    void fat_dot(Vec2i p, PixelBuffer image, uint32_t color);
    void triangle(Vec3f pts[3], IShader* shader, PixelBuffer image, FloatBuffer* z_buffer);
    void triangle2(Vec3f pts[3], IShader* shader, PixelBuffer image, FloatBuffer* z_buffer);
}

#endif //__MY_GL_H__
