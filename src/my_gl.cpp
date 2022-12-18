// #include <cmath>
// #include <limits>
// #include <cstdlib>
#include "my_gl.h"

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

namespace gl {

    // AKA model_view_matrix
    Matrix view_matrix;
    Matrix viewport_matrix;
    Matrix projection_matrix;

    // Builds a "viewport matrix".
    // So, a viewport is just a matrix that will translate and map every point,
    // mapping every point in the original 3 dimensional cube with ranges[-1, 1] * [-1, 1] * [-1, 1]
    // onto the screen cube [x, x + w] * [y, y + h] * [0, d], where d is the depth (and resolution) of the z-buffer and of value 255.
    // opengl calls this the viewport matrix
    void viewport(int x, int y, int w, int h) {

        int depth = 255;

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

        viewport_matrix = m;
    }

    // This should probably go something like...
    // 
    //     float c = camera.position.z;
    //     if (c != 0) c = -1 / c;
    //     projection(c);
    // 
    void projection(float coeff) {
        Matrix m = Matrix::identity();
        m[3][2] = coeff;
        projection_matrix = m;
    }

    // Builds a lookat matrix. More infor below.
    // param `camera_location` commonly referred to as `eye`.
    // param `point_looked_at` commonly referred to as `center`.
    // 
    //     http://www.songho.ca/opengl/gl_transform.html
    //     > Note that there is no separate camera (view) matrix in OpenGL.
    //     > Therefore, in order to simulate transforming the camera or view, the scene(3D objects and lights) must be transformed with the inverse
    //     > of the view transformation. In other words, OpenGL defines that the camera is always located at(0, 0, 0) and
    //     > facing to - Z axis in the eye space coordinates, and cannot be transformed
    // 
    // As that says, OpenGl and this renderer are able to draw scenes only with the camera located on the z-axis.
    // TODO I dont quite understand why that is...???
    // So a lookat Matrix is basically a Matrix that moves a point simulating that we do have a camera.
    // And once that Matrix is obtained, if you transform every single point in the world with it, we have basially moved the world to simulated our camera.
    // 
    // Some other notes from random sources:
    // 
    //     > View Matrix defines the position (location and orientation) of the camera
    // 
    //     > The reason for two separate matrices, instead of one, is that lighting is applied after the modelview view matrix (i.e. on eye coordinates) and before the projection matrix
    // 
    // https://github.com/ssloy/tinyrenderer/wiki/Lesson-5:-Moving-the-camera
    void lookat(Vec3f camera_location, Vec3f point_looked_at, Vec3f up) {

        // We are basically calculating the 3 axis centered on `center`, where:
        //     
        //      A (up)               A (+y)
        //      |                    |
        //     eye    (+z) <----- center
        //                            \  (+x)
        //                             V
        // 
        Vec3f z = (camera_location - point_looked_at).normalize();
        Vec3f x = (up ^ z).normalize();
        Vec3f y = (z ^ x).normalize();

        // I think Tr stands for Translation
        Matrix Tr = Matrix::identity();
        Tr[0][3] = -camera_location.x;
        Tr[1][3] = -camera_location.y;
        Tr[2][3] = -camera_location.z;

        // I think Minv stands for Matrix inversed
        // TODO Why exactly do we need this?
        Matrix Minv = Matrix::identity();
        Minv[0][0] = x.x;
        Minv[1][0] = y.x;
        Minv[2][0] = z.x;

        Minv[0][1] = x.y;
        Minv[1][1] = y.y;
        Minv[2][1] = z.y;

        Minv[0][2] = x.z;
        Minv[1][2] = y.z;
        Minv[2][2] = z.z;

        // Not sure why Minv and this mutiplication of matrices is necessary or what its doing
        // > The last step is a translation of the origin to the point of viewer e and our transformation matrix is ready
        Matrix model_view = Minv * Tr;
        view_matrix = model_view;
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

    // sample a texture using barycentric interpolation
    TGAColor sample(IPixelBuffer& sampled_data, Vec2f t[3], Vec3f barycentric) {

        Vec2f point = barycentric_inverse(t, barycentric);

        // aparently in tga the coordinates seem to be normalized so everything is between 0 and 1 for the texture coords so gotta scale them with the textures size
        Vec2f scaled(point.x * sampled_data.get_width(), point.y * sampled_data.get_height());

        // printf("in texture triangle %f, %f - %f, %f - %f, %f\n", a.x, a.y, b.x, b.y, c.x, c.y);
        // printf("samples to p %f - %f\n", point.x, point.y);
        // printf("scaled to p %f - %f\n", scaled.x, scaled.y);

        return sampled_data.get(scaled.x, scaled.y);
    }

    
    // The algorith proposed puts the depth directly into the Vec2i (making it a Vec3i), but I chose to put it separately
    // so that its easier to understand whats going on. Its used for z-buffer calculations
    void triangle(Vec3f pts[3], IShader* shader, IPixelBuffer* image, FloatBuffer* z_buffer) {
        
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

        int image_witdth = image->get_width();
        int image_height = image->get_height();

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
                z += depth.raw[0] * bar.u;
                z += depth.raw[1] * bar.v;
                z += depth.raw[2] * bar.w;

                // calculate z-buffer value's index
                int idx = int(x + y * image_witdth);

                // Other algorithms might check using the barycentric that the current pixel is inside (usually run multithreaded)
                // but this algorithm is more of an old school single threaded one which will directly only run on the right pixels
                if (z_buffer->data[idx] < z) {
                    TGAColor color;
                    bool discard = shader->fragment(bar, &color);
                    if (!discard) {
                        z_buffer->data[idx] = z;
                        image->set(x, y, color);
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
}

