#include "tgaimage.h"
#include "geometry.h"

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

namespace gl {

    void viewport(int x, int y, int w, int h);
    void projection(float coeff=0.f); // coeff = -1/c
    void lookat(Vec3f eye, Vec3f center, Vec3f up);

    struct IShader {
        virtual Vec3f vertex(int iface, int nthvert) = 0;
        virtual bool fragment(Vec3f bar, TGAColor* out_color) = 0;
    };

    void triangle(Vec3f pts[3], IShader* shader, IPixelBuffer* image, FloatBuffer* z_buffer);
}
