// #include <cmath>
// #include <limits>
// #include <cstdlib>
#include "my_gl.h"

#undef MAX
#define MAX(a,b) ((a) > (b) ? (a) : (b))
#undef MIN
#define MIN(a,b) ((a) < (b) ? (a) : (b))
#undef ABSOLUTE
#define ABSOLUTE(a) ((a) < 0 ? (-a) : (a))
static void swap_int(int* a, int* b) { int c = *a; *a = *b; *b = c; }
static void swap_float(float* a, float* b) { float c = *a; *a = *b; *b = c; }

// mallocs the data buffer. free with `destroy()`
FloatBuffer::FloatBuffer(int w, int h) : data(NULL), width(w), height(h) {
    data = (float*)malloc(width * height * sizeof(float));
}

// doesn't malloc anything, manage the buffer yourself!
FloatBuffer::FloatBuffer(int w, int h, float* data) : data(data), width(w), height(h) {}

float FloatBuffer::get(int x, int y) {
    return data[x + y * width];
}

void FloatBuffer::set(int x, int y, float value) {
    data[x + y * width] = value;
}

void FloatBuffer::destroy() {
    free(data);
}

// set every to input value
void FloatBuffer::clear(float value) {
    for (int i = 0; i < width * height; i++) {
        data[i] = value;
    }
}

// assumes same sizes!
void FloatBuffer::load(FloatBuffer* other) {
    for (int i = 0; i < width * height; i++) {
        data[i] = other->data[i];
    }
}

PixelBuffer::PixelBuffer(): width(0), height(0), data(NULL) {}
PixelBuffer::PixelBuffer(int w, int h) : width(w), height(h) {
    data = (uint32_t*)malloc(width * height * sizeof(uint32_t));
}

PixelBuffer::PixelBuffer(int w, int h, uint32_t* buffer) : data(buffer), width(w), height(h) {}

void PixelBuffer::destroy() {
    if (data) free(data);
}

void PixelBuffer::clear(uint32_t c) {
    for (int i = 0; i < width * height; i++) {
        data[i] = c;
    }
}

// assumes buffers are the same size
void PixelBuffer::load(PixelBuffer other) {
    for (int y = 0; y < other.height; y++) {
        for (int x = 0; x < other.width; x++) {
            data[x + y * width] = other.data[x + y * width];
        }
    }
}

uint32_t PixelBuffer::get(int x, int y) {
    return data[x + y * width];
}

void PixelBuffer::set(int x, int y, uint32_t pixel) {
    data[x + y * width] = pixel;
}

namespace gl {

    // Builds a "viewport matrix".
    // So, a viewport is just a matrix that will translate and map every point,
    // mapping every point in the original 3 dimensional cube with ranges[-1, 1] * [-1, 1] * [-1, 1]
    // onto the screen cube [x, x + w] * [y, y + h] * [0, d], where d is the depth (and resolution) of the z-buffer and of value 255.
    // opengl calls this the viewport matrix
    Matrix viewport(int x, int y, int w, int h, int depth) {

        Matrix m = Matrix::identity(4);
        
        // 1 0 0 translation_x
        // 0 1 0 translation_y
        // 0 0 1 translation_z
        // 0 0 0 1

        float translation_x = x + (w / 2.f);
        float translation_y = y + (h / 2.f);
        float translation_z = depth / 2.f;

        m[0][3] = translation_x;
        m[1][3] = translation_y;
        m[2][3] = translation_z;

        // scale_x 0       0       0
        // 0       scale_y 0       0
        // 0       0       scale_z 0
        // 0       0       0       1
        
        float scale_x = w / 2.f;
        float scale_y = h / 2.f;
        float scale_z = depth / 2.f;

        m[0][0] = scale_x;
        m[1][1] = scale_y;
        m[2][2] = scale_z;

        // resulting in matrix m...
        // w/2     0       0       x+(w/2)
        // 0       h/2     0       y+(h/w)
        // 0       0       d/2     d/2
        // 0       0       0       1

        // https://github.com/ssloy/tinyrenderer/wiki/Lesson-5:-Moving-the-camera#viewport
        // In this function, we are basically mapping a cube [-1,1]*[-1,1]*[-1,1] onto the screen cube [x,x+w]*[y,y+h]*[0,d]
        // Its a cube (and not a rectangle) since there is a `d`epth variable to it, which acts as the resolution of the z-buffer.

        // viewport_matrix
        return m;
    }

    // This should probably go something like...
    // 
    //     float c = -1 / (camera.looking_at - camera.position).norm();
    //     projection(c);
    // 
    Matrix projection(float coeff) {
        Matrix m = Matrix::identity();
        m[3][2] = coeff;
        // projection_matrix = m;
        return m;
    }

    // This is here just for reference. It contains details on how projection matrix is built.
    Matrix get_projection_on_plane_xy_and_camera_on_axis_z(float distance_from_origin) {

        // the camera will be in the axis z
        Vec3f camera(0.f, 0.f, distance_from_origin);
        
        // https://github.com/ssloy/tinyrenderer/wiki/Lesson-4:-Perspective-projection
        // > So to compute a central projection with a camera located on the z-axis with distance c from the origin,
        // > (A) we embed the point into 4D by augmenting it with 1,
        // > (B) then we multiply it with the following matrix,
        // > (C) and retro-project it into 3D.
        // > 
        // >      (B)      (A)                    (C)
        // > |1 0   0  0|  |x|    |   x   |    |   x / (1-z/c)   |
        // > |0 1   0  0|  |y| => |   y   | => |   y / (1-z/c)   |
        // > |0 0   1  0|  |z|    |   z   |    |   z / (1-z/c)   |
        // > |0 0 -1/c 1|  |1|    | 1-z/c |
        // > 
        // > We deformed our object in a way, that simply forgetting its z-coordinate we will get a drawing in a perspective.

        float c = camera.z;

        Matrix projection = Matrix::identity(4);
        projection[3][2] = -1/c;

        return projection;
    }

    // param `camera_location` commonly referred to as `eye`.
    // param `point_looked_at` commonly referred to as `center`.
    // This is RIGHT HANDED COLUMN MAJOR
    // http://www.songho.ca/opengl/gl_transform.html
    // https://stackoverflow.com/questions/349050/calculating-a-lookat-matrix
    // https://stackoverflow.com/questions/53143175/writing-a-lookat-function
    // https://github.com/ssloy/tinyrenderer/wiki/Lesson-5:-Moving-the-camera
    // https://github.com/ssloy/tinyrenderer/blob/f037c7a0517a632c7391b35131f9746a8f8bb235/our_gl.cpp
    // https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/lookat-function
    // https://github.com/HandmadeMath/HandmadeMath/blob/master/HandmadeMath.h
    Matrix lookat(Vec3f camera_location, Vec3f point_looked_at, Vec3f up) {

        // just in case, normalize the up direction
        up.normalize();

        // here z is technically -z
        Vec3f z = (camera_location - point_looked_at).normalized();
        Vec3f x = (up ^ z).normalized();
        Vec3f y = (z ^ x).normalized();

        Matrix transformation_matrix = Matrix::identity();
        transformation_matrix[0][0] = x.x;
        transformation_matrix[0][1] = x.y;
        transformation_matrix[0][2] = x.z;
        
        transformation_matrix[1][0] = y.x;
        transformation_matrix[1][1] = y.y;
        transformation_matrix[1][2] = y.z;
        
        transformation_matrix[2][0] = z.x;
        transformation_matrix[2][1] = z.y;
        transformation_matrix[2][2] = z.z;
        
        transformation_matrix[0][3] = point_looked_at.raw[0] * -1;
        transformation_matrix[1][3] = point_looked_at.raw[1] * -1;
        transformation_matrix[2][3] = point_looked_at.raw[2] * -1;

        return transformation_matrix;
    }

    // Retro-project a point in "4d" back into "3d"
    //     
    //     | x |    | x/w |
    //     | y | => | y/w |
    //     | z |    | z/w |
    //     | w |         
    //
    Vec3f retro_project_back_into_3d(Matrix m) {
        if (m.ncols() != 1) {int a=1;a=a/0;}
        if (m.nrows() != 4) {int a=1;a=a/0;}
        return Vec3f(
            // x / w
            m[0][0]/m[3][0],
            // y / w
            m[1][0]/m[3][0],
            // z / w
            m[2][0]/m[3][0]
        );
    }

    // Embed the point into "4D" by augmenting it with 1, so that we can work with it.
    // 
    //     | x |    | x |
    //     | y | => | y |
    //     | z |    | z |
    //              | 1 |
    //     
    Matrix embed_in_4d(Vec3f p) {
        Matrix m(4, 1);
        m[0][0] = p.x;
        m[1][0] = p.y;
        m[2][0] = p.z;
        m[3][0] = 1.f;
        return m;
    }

    BoundingBox triangle_bb(Vec3f t[3]) {
        BoundingBox bb;

        bb.tl.x = MIN(t[0].x, MIN(t[1].x, t[2].x));
        bb.tl.y = MAX(t[0].y, MAX(t[1].y, t[2].y));

        bb.br.x = MAX(t[0].x, MAX(t[1].x, t[2].x));
        bb.br.y = MIN(t[0].y, MIN(t[1].y, t[2].y));

        return bb;
    }
    
    BoundingBox triangle_bb(Vec2i t[3]) {
        BoundingBox bb;

        bb.tl.x = MIN(t[0].x, MIN(t[1].x, t[2].x));
        bb.tl.y = MAX(t[0].y, MAX(t[1].y, t[2].y));

        bb.br.x = MAX(t[0].x, MAX(t[1].x, t[2].x));
        bb.br.y = MIN(t[0].y, MIN(t[1].y, t[2].y));

        return bb;
    }

    // returns the barycentric coordenates of the point p relative to triangle t
    // https://www.scratchapixel.com/lessons/3d-basic-rendering/ray-tracing-rendering-a-triangle/barycentric-coordinates#:~:text=To%20compute%20the%20position%20of,(barycentric%20coordinates%20are%20normalized)
    // https://www.youtube.com/watch?v=HYAgJN3x4GA
    Vec3f barycentric(Vec2f abc[3], Vec2f p) {

        Vec2f& a = abc[0];
        Vec2f& b = abc[1];
        Vec2f& c = abc[2];
        float u, v, w;

        Vec2f ab = b - a;
        Vec2f ac = c - a;
        Vec2f ap = p - a;
        Vec2f bp = p - b;
        Vec2f ca = a - c;
        
        // the magnitude of the cross product can be interpreted as the area of the parallelogram.
        float paralelogram_area_abc = ab ^ ac;
        float paralelogram_area_abp = ab ^ bp;
        float paralelogram_area_cap = ca ^ ap;

        #ifdef BARICENTER_NO_USE_OPTIMIZATION_1
        
        float triangle_area_abc = paralelogram_area_abc / 2.0f;
        float triangle_area_abp = paralelogram_area_abp / 2.0f;
        float triangle_area_cap = paralelogram_area_cap / 2.0f;
        
        u = triangle_area_cap / triangle_area_abc;
        v = triangle_area_abp / triangle_area_abc;
        
        #else
        
        // There is actually no need to do the "/ 2.0f" divisions we can instead do...
        u = paralelogram_area_cap / paralelogram_area_abc;
        v = paralelogram_area_abp / paralelogram_area_abc;
        
        #endif // BARICENTER_NO_USE_OPTIMIZATION_1

        // since we have u and v we can figure out w
        w = (1.0f - u - v);
        
        return Vec3f(u, v, w);
    }

    Vec3f barycentric(Vec2i abc[3], Vec2i p) {

        Vec2f aux[3];
        aux[0] = Vec2f(abc[0].x, abc[0].y);
        aux[1] = Vec2f(abc[1].x, abc[1].y);
        aux[2] = Vec2f(abc[2].x, abc[2].y);
        
        return barycentric(
            aux,
            Vec2f(p.x, p.y)
        );
    }

    Vec2f barycentric_inverse(Vec2f t[3], Vec3f barycentric) {

        float u = barycentric.u;
        float v = barycentric.v;
        float w = barycentric.w;

        Vec2f a = t[0];
        Vec2f b = t[1];
        Vec2f c = t[2];

        // P=wA+uB+vC
        Vec2f point = (a * w) + (b * u) + (c * v);

        return point;
    }

    Vec3f barycentric_inverse(Vec3f t[3], Vec3f barycentric) {

        float u = barycentric.u;
        float v = barycentric.v;
        float w = barycentric.w;

        Vec3f a = t[0];
        Vec3f b = t[1];
        Vec3f c = t[2];

        // P=wA+uB+vC
        Vec3f point = (a * w) + (b * u) + (c * v);

        return point;
    }

    // returns true if the given barycentric coordinates represent a point inside a triangle
    bool barycentric_inside(Vec3f bar) {
        if (bar.x < 0.0f || bar.x >= 1.0f) { return false; }
        if (bar.y < 0.0f || bar.y >= 1.0f) { return false; }
        if (bar.z < 0.0f || bar.z >= 1.0f) { return false; }
        return true;
    }

    // sample a texture using barycentric interpolation
    // sample the texture data (PixelBuffer& sampled_data) by giving the the 3 points of the triangle (Vec2f uv[3]) and the barycentric coordenates
    uint32_t sample_texture(PixelBuffer& sampled_data, Vec2f uv[3], Vec3f barycentric) {
        Vec2f point = barycentric_inverse(uv, barycentric);
        return sampled_data.get(point.x, point.y);
    }

    void line(PixelBuffer pixels, FloatBuffer depth, Vec3f a, Vec3f b, uint32_t color) {
        float differenceX = b.x - a.x;
        float differenceXAbs = ABSOLUTE(differenceX);

        float differenceY = b.y - a.y;
        float differenceYAbs = ABSOLUTE(differenceY);

        if (differenceXAbs > differenceYAbs) {
            // draw horizontally

            if (differenceX < 0) {
                swap_float(&a.x, &b.x);
                swap_float(&a.y, &b.y);
                swap_float(&a.z, &b.z);
            }

            float percentageOfLineDone = 0.0;
            float increment = 1.0 / differenceXAbs;
            for (int x = a.x; x <= b.x; x++) {
                int y = a.y + (b.y - a.y) * percentageOfLineDone;
                int z = a.z + (b.z - a.z) * percentageOfLineDone;
                if (x < 0 || x >= pixels.width || y < 0 || y >= pixels.height || z < 0) continue;
                int idx = x + y * pixels.width;
                if (depth.data[idx] < z) {
                    pixels.set(x, y, color);
                }
                else {
                    u32rgba_unpack(pixels.get(x, y), r, g, b, a);
                    pixels.set(x, y, u32rgba(r*0.5f, g*0.5f, b*0.5f, a*0.5f));
                }
                percentageOfLineDone += increment;
            }
        }
        else {
            // draw vertically

            if (differenceY < 0) {
                swap_float(&a.x, &b.x);
                swap_float(&a.y, &b.y);
                swap_float(&a.z, &b.z);
            }

            float percentageOfLineDone = 0.0;
            float increment = 1.0 / differenceYAbs;
            for (int y = a.y; y <= b.y; y++) {
                int x = a.x + (b.x - a.x) * percentageOfLineDone;
                int z = a.z + (b.z - a.z) * percentageOfLineDone;
                if (x < 0 || x >= pixels.width || y < 0 || y >= pixels.height || z < 0) continue;
                int idx = x + y * pixels.width;
                if (depth.data[idx] < z) {
                    pixels.set(x, y, color);
                }
                else {
                    u32rgba_unpack(pixels.get(x, y), r, g, b, a);
                    pixels.set(x, y, u32rgba(r*0.5f, g*0.5f, b*0.5f, a*0.5f));
                }
                percentageOfLineDone += increment;
            }
        }
    }

    void line(Vec2i a, Vec2i b, PixelBuffer image, uint32_t color) {
        int differenceX = b.x - a.x;
        int differenceXAbs = ABSOLUTE(differenceX);

        int differenceY = b.y - a.y;
        int differenceYAbs = ABSOLUTE(differenceY);

        if (differenceXAbs > differenceYAbs) {
            // draw horizontally

            if (differenceX < 0) {
                swap_int(&a.x, &b.x);
                swap_int(&a.y, &b.y);
            }

            float percentageOfLineDone = 0.0;
            float increment = 1.0 / (float)differenceXAbs;
            for (int x = a.x; x <= b.x; x++) {
                int y = a.y + (b.y - a.y) * percentageOfLineDone;
                image.set(x, y, color);
                percentageOfLineDone += increment;
            }
        }
        else {
            // draw vertically

            if (differenceY < 0) {
                swap_int(&a.x, &b.x);
                swap_int(&a.y, &b.y);
            }

            float percentageOfLineDone = 0.0;
            float increment = 1.0 / (float)differenceYAbs;
            for (int y = a.y; y <= b.y; y++) {
                int x = a.x + (b.x - a.x) * percentageOfLineDone;
                image.set(x, y, color);
                percentageOfLineDone += increment;
            }
        }
    }

    void triangle_outline(Vec2i t[3], PixelBuffer image, uint32_t color) {
        line(t[0], t[1], image, color);
        line(t[1], t[2], image, color);
        line(t[2], t[0], image, color);
    }

    void fat_dot(Vec2i p, PixelBuffer image, uint32_t color) {
        image.set(p.x, p.y, color);
        image.set(p.x+1, p.y, color);
        image.set(p.x-1, p.y, color);
        image.set(p.x, p.y+1, color);
        image.set(p.x, p.y-1, color);
    }
    
    void dot(PixelBuffer pixels, FloatBuffer depth, Vec3f p, uint32_t color) {
        if (p.x < 0 || p.x >= pixels.width || p.y < 0 || p.y >= pixels.height || p.z < 0) return;
        int idx = p.x + p.y * pixels.width;
        if (depth.data[idx] < p.z) {
            pixels.set(p.x, p.y, color);
            // pixels.set(p.x + 1, p.y, color);
            // pixels.set(p.x - 1, p.y, color);
            // pixels.set(p.x, p.y + 1, color);
            // pixels.set(p.x, p.y - 1, color);
        }
        else {
            u32rgba_unpack(pixels.get(p.x, p.y), r, g, b, a);
            pixels.set(p.x, p.y, u32rgba(r*0.5f, g*0.5f, b*0.5f, a*0.5f));
        }
    }

    // The algorith proposed puts the depth directly into the Vec2i (making it a Vec3i), but I chose to put it separately
    // so that its easier to understand whats going on. Its used for z-buffer calculations
    void triangle(Vec3f pts[3], IShader* shader, PixelBuffer image, FloatBuffer* z_buffer) {
        
        // TODO make this calculations with floats rather than ints
        Vec2i screen[3];
        screen[0] = Vec2i(pts[0].x, pts[0].y);
        screen[1] = Vec2i(pts[1].x, pts[1].y);
        screen[2] = Vec2i(pts[2].x, pts[2].y);

        Vec3i depth(pts[0].z, pts[1].z, pts[2].z);
        
        // 1. find the highest vertex and the lowest vertex
        Vec2i* top = &screen[0];
        Vec2i* mid = &screen[1];
        Vec2i* bot = &screen[2];
        Vec2i* aux;
        
        if (bot->y > mid->y) {
            aux = mid;
            mid = bot;
            bot = aux;
        }

        if (bot->y > top->y) {
            aux = top;
            top = bot;
            bot = aux;
        }

        if (mid->y > top->y) {
            aux = top;
            top = mid;
            mid = aux;
        }

        // The poor mans assert lol
        if (!(top->y >= mid->y && top->y >= bot->y)) { int a=1;a=a/0; }
        if (!(mid->y <= top->y && mid->y >= bot->y)) { int a=1;a=a/0; }
        if (!(bot->y <= top->y && bot->y <= mid->y)) { int a=1;a=a/0; }

        // 2. calculate dy between them
        int dyTopMid = top->y - mid->y;
        int dyMidBot = mid->y - bot->y;
        int dyTopBot = top->y - bot->y;

        int dxTopMid = top->x - mid->x;
        int dxTopBot = top->x - bot->x;
        int dxMidBot = mid->x - bot->x;

        // So we know that line(T-B) is going to be longer than line(T-M) or (M-B)
        // So we can split the triangle in 2 triangles, divided by the horizontal line where y == mid.y

        // Calculate the increments (the steepness?) of the segments of the triangle as we progress with the filling
        float incrementLongLine = dxTopBot / (float)dyTopBot;
        float incrementShortLine1 = dxTopMid / (float)dyTopMid;
        float incrementShortLine2 = dxMidBot / (float)dyMidBot;
        
        // 3. loop though each "horizontal line" between top and bottom
        // Starting position is the top so both side's x position will be tops's x position
        float side1 = top->x;
        float side2 = top->x;

        // If the first half of the triangle "does't exist" then draw only the second part
        if (dyTopMid == 0) {
            incrementShortLine1 = dxTopMid;
            side2 -= incrementShortLine1;
        }

        int image_witdth = image.width;
        int image_height = image.height;

        // first, draw the top half of the triangle
        for (int y = top->y; y > bot->y; y--) {

            // TODO I probably dont need to check this in each line
            int left = side1;
            int right = side2;
            if (left > right) {
                // swap!
                int c = left;
                left = right;
                right = c;
            }
            
            // draw a horizontal line (left, y) to (right, y)
            for (int x = left; x <= right; x++) {
                
                // barycentric coordinates for `z-buffer` and `texture sampling`
                Vec3f bar = barycentric(screen, Vec2i(x, y));

                if (bar.x < 0 || bar.y < 0 || bar.z < 0 || bar.x > 1.0 || bar.y > 1.0 || bar.z > 1.0) continue; //{ int a=1;a=a/0; }

                // > the idea is to take the barycentric coordinates version of triangle rasterization,
                // > and for every pixel we want to draw simply to multiply its barycentric coordinates [u, v, w]
                // > by the z-values [3rd element] of the vertices of the triangle [t0, t1 and t2] we rasterize
                // This is basically finding the z value of an specific pixel in a triangle by interpolating the 3 values of z that we know.
                // The same as how we sample the texture, except in this case we only care about the z components.
                // Also, this is equivalent to this but without the extra uneeded calculations...
                //
                //     Vec3f point_in_world_space = barycentric_inverse(world, bar);
                //     z = point_in_world_space.z;
                //     float z = 0;
                //
                float z = 0;
                z += depth.raw[0] * bar.w;
                z += depth.raw[1] * bar.u;
                z += depth.raw[2] * bar.v;

                if (x < 0 || x >= image.width || y < 0 || y >= image.height || z < 0) continue;

                // calculate z-buffer value's index
                int idx = int(x + y * image_witdth);

                // Other algorithms might check using the barycentric that the current pixel is inside (usually run multithreaded)
                // but this algorithm is more of an old school single threaded one which will directly only run on the right pixels
                if (z_buffer->data[idx] < z) {
                    uint32_t color;
                    bool discard = shader->fragment(bar, &color);
                    if (!discard) {
                        z_buffer->data[idx] = z;
                        image.set(x, y, color);
                    }
                }
            }

            // We don't really need to know which side will be in the "left" or "right", since the increments are already signed
            // Just get the current "horizontal line"'s positions and add the increments (substract* since we are drawing the triangle top to bottom)
            side1 -= incrementLongLine;
            if (y > mid->y) {
                side2 -= incrementShortLine1;
            }
            else {
                side2 -= incrementShortLine2;
            }
        }
    }

    void triangle(Vec3f pts[3], IShader* shader, PixelBuffer image) {
        
        // TODO make this calculations with floats rather than ints
        Vec2i screen[3];
        screen[0] = Vec2i(pts[0].x, pts[0].y);
        screen[1] = Vec2i(pts[1].x, pts[1].y);
        screen[2] = Vec2i(pts[2].x, pts[2].y);

        Vec3i depth(pts[0].z, pts[1].z, pts[2].z);
        
        // 1. find the highest vertex and the lowest vertex
        Vec2i* top = &screen[0];
        Vec2i* mid = &screen[1];
        Vec2i* bot = &screen[2];
        Vec2i* aux;
        
        if (bot->y > mid->y) {
            aux = mid;
            mid = bot;
            bot = aux;
        }

        if (bot->y > top->y) {
            aux = top;
            top = bot;
            bot = aux;
        }

        if (mid->y > top->y) {
            aux = top;
            top = mid;
            mid = aux;
        }

        // The poor mans assert lol
        if (!(top->y >= mid->y && top->y >= bot->y)) { int a=1;a=a/0; }
        if (!(mid->y <= top->y && mid->y >= bot->y)) { int a=1;a=a/0; }
        if (!(bot->y <= top->y && bot->y <= mid->y)) { int a=1;a=a/0; }

        // 2. calculate dy between them
        int dyTopMid = top->y - mid->y;
        int dyMidBot = mid->y - bot->y;
        int dyTopBot = top->y - bot->y;

        int dxTopMid = top->x - mid->x;
        int dxTopBot = top->x - bot->x;
        int dxMidBot = mid->x - bot->x;

        // So we know that line(T-B) is going to be longer than line(T-M) or (M-B)
        // So we can split the triangle in 2 triangles, divided by the horizontal line where y == mid.y

        // Calculate the increments (the steepness?) of the segments of the triangle as we progress with the filling
        float incrementLongLine = dxTopBot / (float)dyTopBot;
        float incrementShortLine1 = dxTopMid / (float)dyTopMid;
        float incrementShortLine2 = dxMidBot / (float)dyMidBot;
        
        // 3. loop though each "horizontal line" between top and bottom
        // Starting position is the top so both side's x position will be tops's x position
        float side1 = top->x;
        float side2 = top->x;

        // If the first half of the triangle "does't exist" then draw only the second part
        if (dyTopMid == 0) {
            incrementShortLine1 = dxTopMid;
            side2 -= incrementShortLine1;
        }

        int image_witdth = image.width;
        int image_height = image.height;

        // first, draw the top half of the triangle
        for (int y = top->y; y > bot->y; y--) {

            // TODO I probably dont need to check this in each line
            int left = side1;
            int right = side2;
            if (left > right) {
                // swap!
                int c = left;
                left = right;
                right = c;
            }
            
            // draw a horizontal line (left, y) to (right, y)
            for (int x = left; x <= right; x++) {
                
                // barycentric coordinates for `z-buffer` and `texture sampling`
                Vec3f bar = barycentric(screen, Vec2i(x, y));

                if (bar.x < 0 || bar.y < 0 || bar.z < 0 || bar.x > 1.0 || bar.y > 1.0 || bar.z > 1.0) continue; //{ int a=1;a=a/0; }

                if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

                // calculate z-buffer value's index

                // Other algorithms might check using the barycentric that the current pixel is inside (usually run multithreaded)
                // but this algorithm is more of an old school single threaded one which will directly only run on the right pixels
                uint32_t color;
                bool discard = shader->fragment(bar, &color);
                if (!discard) {
                    image.set(x, y, color);
                }
            }

            // We don't really need to know which side will be in the "left" or "right", since the increments are already signed
            // Just get the current "horizontal line"'s positions and add the increments (substract* since we are drawing the triangle top to bottom)
            side1 -= incrementLongLine;
            if (y > mid->y) {
                side2 -= incrementShortLine1;
            }
            else {
                side2 -= incrementShortLine2;
            }
        }
    }

    void triangle2(Vec3f pts[3], IShader* shader, PixelBuffer image, FloatBuffer* z_buffer) {

        // TODO make this calculations with floats rather than ints
        Vec2i screen[3];
        screen[0] = Vec2i(pts[0].x, pts[0].y);
        screen[1] = Vec2i(pts[1].x, pts[1].y);
        screen[2] = Vec2i(pts[2].x, pts[2].y);

        Vec3i depth(pts[0].z, pts[1].z, pts[2].z);

        BoundingBox bb = triangle_bb(screen);

        int image_witdth = image.width;
        for (int y = bb.tl.y; y > bb.br.y; y--) { // top to bottom
            for (int x = bb.tl.x; x < bb.br.x; x++) { // left to right

                // barycentric coordinates for bounds checking, `z-buffer`, `texture sampling`
                Vec3f bar = barycentric(screen, Vec2i(x, y));
                if (!barycentric_inside(bar)) {
                    continue;
                }

                // > the idea is to take the barycentric coordinates version of triangle rasterization,
                // > and for every pixel we want to draw simply to multiply its barycentric coordinates [u, v, w]
                // > by the z-values [3rd element] of the vertices of the triangle [t0, t1 and t2] we rasterize
                // This is basically finding the z value of an specific pixel in a triangle by interpolating the 3 values of z that we know.
                // The same as how we sample the texture, except in this case we only care about the z components.
                // Also, this is equivalent to this but without the extra uneeded calculations...
                //
                //     Vec3f point_in_world_space = barycentric_inverse(world, bar);
                //     z = point_in_world_space.z;
                //     float z = 0;
                //
                float z = 0;
                z += depth.raw[0] * bar.w;
                z += depth.raw[1] * bar.u;
                z += depth.raw[2] * bar.v;

                // calculate z-buffer value's index
                int idx = int(x + y * image_witdth);

                // Other algorithms might check using the barycentric that the current pixel is inside (usually run multithreaded)
                // but this algorithm is more of an old school single threaded one which will directly only run on the right pixels
                if (z_buffer->data[idx] < z) {
                    uint32_t color;
                    bool discard = shader->fragment(bar, &color);
                    if (!discard) {
                        z_buffer->data[idx] = z;
                        image.set(x, y, color);
                    }
                }
            }
        }
    }   

}

