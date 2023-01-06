#ifndef __MY_GL_H__
#define __MY_GL_H__


#include "geometry.h"

// https://learn.microsoft.com/en-us/previous-versions//dd183376(v=vs.85)?redirectedfrom=MSDN
// Windows does something weird with the order of bytes in a "rgb" pixel
// (Also, windows decides to ignore Alpha channel even thought it DOES use 4 bytes per pixel... What the heck ? )
#define pack_4_u8_in_a_single_u32(a,b,c,d) ((uint32_t)(((uint8_t)(a) << 8*3) | ((uint8_t)(b) << 8*2) | ((uint8_t)(c) << 8*1) | ((uint8_t)(d) << 8*0) ))
#define unpack_single_u32_in_4_u8(in,out3,out2,out1,out0) \
    uint8_t out3 = (uint8_t)((in) >> 8 * 3);\
    uint8_t out2 = (uint8_t)((in) >> 8 * 2);\
    uint8_t out1 = (uint8_t)((in) >> 8 * 1);\
    uint8_t out0 = (uint8_t)((in) >> 8 * 0);
#define u32rgba(r,g,b,a) pack_4_u8_in_a_single_u32(a,r,g,b)
#define u32rgba_unpack(input,r,g,b,a) unpack_single_u32_in_4_u8(input,a,r,g,b)

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

    // bgra
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

    uint32_t get(int x, int y);
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

    Vec3f barycentric(Vec2f abc[3], Vec2f p);
    Vec3f barycentric(Vec2i abc[3], Vec2i p);
    Vec2f barycentric_inverse(Vec2f triangle[3], Vec3f barycentric);
    Vec3f barycentric_inverse(Vec3f triangle[3], Vec3f barycentric);

    struct IShader {
        virtual Vec3f vertex(int iface, int nthvert) = 0;
        virtual bool fragment(Vec3f bar, uint32_t* out_color) = 0;
    };

    void line(PixelBuffer pixels, FloatBuffer depth, Vec3f a, Vec3f b, uint32_t color);
    void line(PixelBuffer pixels, Vec2i a, Vec2i b, uint32_t color);
    void dot(PixelBuffer pixels, FloatBuffer depth, Vec3f p, uint32_t color);
    void fat_dot(PixelBuffer pixels, Vec2i p, uint32_t color);
    void triangle_outline(PixelBuffer pixels, Vec2i t[3], uint32_t color);
    void triangle(PixelBuffer pixels, Vec3f pts[3], IShader* shader);
    void triangle(PixelBuffer pixels, FloatBuffer depth, Vec3f pts[3], IShader* shader);
    void triangle2(PixelBuffer pixels, FloatBuffer depth, Vec3f pts[3], IShader* shader);
}

#endif //__MY_GL_H__
