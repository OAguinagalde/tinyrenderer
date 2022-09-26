// Note: I'm using http://schmittl.github.io/tgajs/ to visualize the tga images generated

#include "tgaimage.h"
#include <vector>
#include <cmath>

#include "model.h"
#include "geometry.h"
#include "util.h"

const TGAColor whiteTransparent = TGAColor(255, 255, 255, 50);
const TGAColor white = TGAColor(255, 255, 255, 255);
const TGAColor red = TGAColor(255, 0, 0, 255);
const TGAColor green = TGAColor(0, 255, 0, 255);
const TGAColor blue = TGAColor(0, 0, 255, 255);
const TGAColor aaa = TGAColor(125, 55, 255, 255);

void line(Vec2i a, Vec2i b, IPixelBuffer& image, const TGAColor& color) {
    int differenceX = b.x - a.x;
    int differenceXAbs = absolute(differenceX);

    int differenceY = b.y - a.y;
    int differenceYAbs = absolute(differenceY);

    if (differenceXAbs > differenceYAbs) {
        // draw horizontally

        if (differenceX < 0) {
            swap(a.x, b.x);
            swap(a.y, b.y);
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
            swap(a.x, b.x);
            swap(a.y, b.y);
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

void triangle_outline(Vec2i t[3], IPixelBuffer& image, const TGAColor& color) {
    line(t[0], t[1], image, color);
    line(t[1], t[2], image, color);
    line(t[2], t[0], image, color);
}

void fat_dot(Vec2i p, IPixelBuffer& image, const TGAColor& color) {
    image.set(p.x, p.y, color);
    image.set(p.x+1, p.y, color);
    image.set(p.x-1, p.y, color);
    image.set(p.x, p.y+1, color);
    image.set(p.x, p.y-1, color);
}

// returns the barycentric coordenates of the point p relative to triangle t
// https://www.scratchapixel.com/lessons/3d-basic-rendering/ray-tracing-rendering-a-triangle/barycentric-coordinates#:~:text=To%20compute%20the%20position%20of,(barycentric%20coordinates%20are%20normalized)
// https://www.youtube.com/watch?v=HYAgJN3x4GA
Vec3f barycentric(Vec2f t[3], Vec2f p) {

    Vec2f& a = t[0];
    Vec2f& b = t[1];
    Vec2f& c = t[2];
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
    
    u = triangle_area_abp / triangle_area_abc;
    v = triangle_area_cap / triangle_area_abc;
    
    #else
    
    // There is actually no need to do the "/ 2.0f" divisions we can instead do...
    u = paralelogram_area_abp / paralelogram_area_abc;
    v = paralelogram_area_cap / paralelogram_area_abc;
    
    #endif // BARICENTER_NO_USE_OPTIMIZATION_1

    // since we have u and v we can figure out w
    w = (1.0f - u - v);
    
    return Vec3f(u, v, w);
}

Vec3f barycentric(Vec2i t[3], Vec2i p) {

    Vec2f aux[3];
    aux[0] = Vec2f(t[0].x, t[0].y);
    aux[1] = Vec2f(t[1].x, t[1].y);
    aux[2] = Vec2f(t[2].x, t[2].y);
    
    return barycentric(
        aux,
        Vec2f(p.x, p.y)
    );
}

bool barycentric_inside(Vec3f bar) {
    if (bar.x < 0.0f || bar.x > 1.0f) { return false; }
    if (bar.y < 0.0f || bar.y > 1.0f) { return false; }
    if (bar.z < 0.0f || bar.z > 1.0f) { return false; }
    return true;
}

Vec2f barycentric_inverse(Vec2f t[3], Vec3f barycentric) {

    float u = barycentric.u;
    float v = barycentric.v;
    float w = barycentric.w;

    Vec2f a = t[0];
    Vec2f b = t[1];
    Vec2f c = t[2];

    // P=uA+vB+wC
    Vec2f point = a * u + b * v + c * w;

    return point;
}

TGAColor sample(IPixelBuffer& sampled_data, Vec2f t[3], Vec3f barycentric) {

    float u = barycentric.u;
    float v = barycentric.v;
    float w = barycentric.w;

    Vec2f a = t[0];
    Vec2f b = t[1];
    Vec2f c = t[2];

    // P=uA+vB+wC
    // TODO I think the problem might be here... Or when I calculate the barycentric coords. What I think is A seems to not quite be A...
    Vec2f point = a * u + b * v + c * w;

    // aparently in tga the coordinates seem to be normalized so everything is between 0 and 1 for the texture coords so gotta scale them with the textures size
    Vec2f scaled(point.x * sampled_data.get_width(), point.y * sampled_data.get_height());

    // printf("in texture triangle %f, %f - %f, %f - %f, %f\n", a.x, a.y, b.x, b.y, c.x, c.y);
    // printf("samples to p %f - %f\n", point.x, point.y);
    // printf("scaled to p %f - %f\n", scaled.x, scaled.y);

    return sampled_data.get(scaled.x, scaled.y);
}

BoundingBox triangle_bb(Vec2i t[3]) {
    #ifdef A
    // I have not tested this but its ugly lol
    // Figure out top and bottom
    if (t0.y > t1.y) {
        if (t0.y > t2.y) {
            outTopLeft->y = t0.y;
            if (t1.y > t2.y) {
                outBottomRight->y = t2.y;
            }
            else {
                outBottomRight->y = t1.y;
            }
        }
        else {
            outTopLeft->y = t2.y;
            outBottomRight->y = t1.y;
        }
    }
    else {
        if (t1.y > t2.y) {
            outTopLeft->y = t1.y;
            if (t0.y > t2.y) {
                outBottomRight->y = t2.y;
            }
            else {
                outBottomRight->y = t0.y;
            }
        }
        else {
            outTopLeft->y = t2.y;
            outBottomRight->y = t0.y;
        }
    }

    // Figure out left and right
    if (t0.x < t1.x) {
        if (t0.x < t2.x) {
            outTopLeft->x = t0.x;
            if (t1.x < t2.x) {
                outBottomRight->x = t2.x;
            }
            else {
                outBottomRight->x = t1.x;
            }
        }
        else {
            outTopLeft->x = t2.x;
            outBottomRight->x = t1.x;
        }
    }
    else {
        if (t1.x < t2.x) {
            outTopLeft->x = t1.x;
            if (t0.x < t2.x) {
                outBottomRight->x = t2.x;
            }
            else {
                outBottomRight->x = t0.x;
            }

        }
        else {
            outTopLeft->x = t2.x;
            outBottomRight->x = t1.x;
        }
    }
    #endif
    BoundingBox bb;

    bb.tl.x = MIN(t[0].x, MIN(t[1].x, t[2].x));
    bb.tl.y = MAX(t[0].y, MAX(t[1].y, t[2].y));

    bb.br.x = MAX(t[0].x, MAX(t[1].x, t[2].x));
    bb.br.y = MIN(t[0].y, MIN(t[1].y, t[2].y));

    return bb;
}

// Aparently this is an "old school" single cpu approach.
// The cool kids just brute - force it with the power of multi - threading, example below in `triangle2`
void triangle(Vec2i t[3], IPixelBuffer& image, const TGAColor& color) {
    
    // 1. find the highest vertex and the lowest vertex

    // Aparently this works too, but I'll leave it as I have it and that's another thing I can do without relying on the Standard library lol
    // 
    //     // sort the vertices, t0, t1, t2 lower−to−upper (bubblesort yay!) 
    //     if (t0.y>t1.y) std::swap(t0, t1); 
    //     if (t0.y>t2.y) std::swap(t0, t2); 
    //     if (t1.y>t2.y) std::swap(t1, t2);

    Vec2i* top;
    Vec2i* mid;
    Vec2i* bot;
    if (t[0].y > t[1].y) {
        if (t[0].y > t[2].y) {
            top = &t[0];
            if (t[1].y > t[2].y) {
                mid = &t[1];
                bot = &t[2];
            }
            else {
                mid = &t[2];
                bot = &t[1];
            }
        }
        else {
            top = &t[2];
            mid = &t[0];
            bot = &t[1];
        }
    }
    else {
        if (t[1].y > t[2].y) {
            top = &t[1];
            if (t[0].y > t[2].y) {
                mid = &t[0];
                bot = &t[2];
            }
            else {
                mid = &t[2];
                bot = &t[0];
            }
        }
        else {
            top = &t[2];
            mid = &t[1];
            bot = &t[0];
        }
    }

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
    // Frist draw the triangle that forms the top part of the triangle
    for (int y  = top->y; y > mid-> y; y--) {
        
        // draw a line now that we know both the x and the y of both extremes
        line(Vec2i(side1, y), Vec2i(side2, y), image, color);
        
        // We don't really need to know which side will be in the "left" or "right", since the increments are already signed
        // Just get the current "horizontal line"'s positions and add the increments (substract* since we are drawing the triangle top to bottom)
        side1 -= incrementLongLine;
        side2 -= incrementShortLine1;
    }

    // 4. Repeat for lines between mid and bot
    for (int y  = mid->y; y >= bot-> y; y--) {
        line(Vec2i(side1, y), Vec2i(side2, y), image, color);
        side1 -= incrementLongLine;
        side2 -= incrementShortLine2;
    }
}

void triangle2(Vec2i t[3], IPixelBuffer& image, const TGAColor& color) {
    BoundingBox bb = triangle_bb(t);

    float u;
    float v;
    float w;
    bool isInside;
    for (int y = bb.tl.y; y > bb.br.y; y--) { // top to bottom
        for (int x = bb.tl.x; x < bb.br.x; x++) { // left to right
            Vec3f bar = barycentric(t, Vec2i(x, y));
            if (barycentric_inside(bar)) {
                image.set(x, y, color);
            }
        }
    }
}

void triangle2_zbuffer(Vec2i screen[3], Vec3f world[3], IPixelBuffer& image, float* z_buffer, const TGAColor& color) {
    BoundingBox bb = triangle_bb(screen);
    
    int image_witdth = image.get_width();
    for (int y = bb.tl.y; y > bb.br.y; y--) { // top to bottom
        for (int x = bb.tl.x; x < bb.br.x; x++) { // left to right

            Vec3f bar = barycentric(screen, Vec2i(x, y));
            if (!barycentric_inside(bar)) {
                continue;
            }

            // > the idea is to take the barycentric coordinates version of triangle rasterization,
            // > and for every pixel we want to draw simply to multiply its barycentric coordinates [u, v, w]
            // > by the z-values [3rd element] of the vertices of the triangle [t0, t1 and t2] we rasterize
            float z = 0;
            z += (float) world[0].z * bar.u;
            z += (float) world[1].z * bar.v;
            z += (float) world[2].z * bar.w;

            // calculate z-buffer value's index
            int idx = int(x + y * image_witdth);
            
            if (z_buffer[idx] < z) {
                z_buffer[idx] = z;
                image.set(x, y, color);
            }

        }
    }
}

void triangle2_zbuffer_textured(Vec2i screen[3], Vec3f world[3], Vec2f texture[3], IPixelBuffer& image, IPixelBuffer& texture_data, float z_buffer[],  const TGAColor& color) {
    BoundingBox bb = triangle_bb(screen);
    
    int image_witdth = image.get_width();
    for (int y = bb.tl.y; y > bb.br.y; y--) { // top to bottom
        for (int x = bb.tl.x; x < bb.br.x; x++) { // left to right

            Vec3f bar = barycentric(screen, Vec2i(x, y));
            if (!barycentric_inside(bar)) {
                continue;
            }

            // > the idea is to take the barycentric coordinates version of triangle rasterization,
            // > and for every pixel we want to draw simply to multiply its barycentric coordinates [u, v, w]
            // > by the z-values [3rd element] of the vertices of the triangle [t0, t1 and t2] we rasterize
            float z = 0;
            z += (float) world[0].z * bar.u;
            z += (float) world[1].z * bar.v;
            z += (float) world[2].z * bar.w;

            // calculate z-buffer value's index
            int idx = int(x + y * image_witdth);
            
            if (z_buffer[idx] < z) {
                z_buffer[idx] = z;

                // printf("x %d, y %d with bar %f, %f, %f\n", x, y, bar.u, bar.v, bar.w);
                // barycentric interpolation... I think
                // TODO so it doesnt work yet and I think the reason is that the uvw were taken respective to the screen while the texture coordinates
                // are in the context fo world coordinates. If that is correct, that means that I just need to get the u v w from the world perspective.
                // The only stopper is that I dont quite understand how to get the baricenter coordinates with a 3rd coordinate, last time I barely managed
                // and it was in 2D... I need to refresh my math fr
                TGAColor texture_sample = sample(texture_data, texture, bar);

                // TODO take into account input color
                image.set(x, y, TGAColor(
                    color.r / 255.0f * texture_sample.r,
                    color.g / 255.0f * texture_sample.g,
                    color.b / 255.0f * texture_sample.b,
                    color.a
                ));
            }

        }
    }
}

//////////////////////////////////////////////////////////////

// Lesson 1 exercise. Given an input .obj file, output an image .tga of every triangle (wireframe only) in the object. 
void obj_wireframe_to_tga(Model& model, IPixelBuffer& pixel_buffer) {

    auto start = measure_time();
    
    for (int i = 0; i < model.nfaces(); i++) {
        std::vector<int> face = model.face(i).location;

        // A face is a group of 3 Vertices in space, which form a triangle
        // for each vertex, draw a line between the vertex and the next one on the triangle:
        //     [j == 0]             [j == 1]              [j == 2]   
        //   [line 0 - 1]         [line 1 - 2]          [line 2 - 0] 
        //                                                           
        //       .(0)                 .(0)                  .(0)     
        //     >/                                             \      
        //  (1).    .(2)         (1).____.(2)          (1).    .(2)  
        //                                                           
        for (int j = 0; j < 3; j++) {
            // Draw a line between 2 vertices

            Vec3f v0 = model.vert(face[j]);
            // the % 3 (module 3) is here so that when we are drawing the
            // last line [2-0] j wraps around and instead of j == 3 have j == 0
            Vec3f v1 = model.vert(face[(j + 1) % 3]);

            // convert the vertices from "world space" (obj format, normalized) to our "image space"
            Vec2i a(
                // TODO: I still dont know why we need the `+ 1.0`...
                (v0.x + 1.0f)* pixel_buffer.get_width() / 2.0f,
                (v0.y + 1.0f) * pixel_buffer.get_height() / 2.0f
            );
            
            Vec2i b(
                (v1.x + 1.0f) * pixel_buffer.get_width() / 2.0f,
                (v1.y + 1.0f) * pixel_buffer.get_height() / 2.0f
            );

            line(a, b, pixel_buffer, white);
        }
    }

    measure_since(start);
}

// Lesson 2 exercise. Given an input .obj file, output an image .tga of every triangle in the object with very plain "illumination".
// warning: this is using `triangle2`, not `triangle`
void obj_to_tga_illuminated(Model& model, IPixelBuffer& pixel_buffer) {

    auto start = measure_time();
    
    // Where the light is "coming from"
    Vec3f light_dir(0,0,-1);

    // For each triangle that froms the object...
    for (int i=0; i < model.nfaces(); i++) {
        
        std::vector<int> face = model.face(i).location;
        
        Vec2i screen[3]; // the 3 points in our screen (2D) that form the triangle
        Vec3f world[3]; // the 3 points in the world (3D) that form the triangle
        
        // For each vertex in this triangle
        for (int j = 0; j < 3; j++) {
        
            Vec3f v = model.vert(face[j]);
            world[j] = v;

            screen[j] = Vec2i(
                (v.x + 1.0) * pixel_buffer.get_width() / 2.0,
                (v.y + 1.0) * pixel_buffer.get_height() / 2.0
            );

        }

        // the intensity of illumination is equal to the scalar product of the light vector and the triangle normal normal.
        // the normal to the triangle can be calculated simply as the cross product of its two sides.
        // 
        //     v3 normal = cross_product(AC, BC)
        //     float intensity = normal * light_direction
        // 
        Vec3f normal = ((world[2]-world[0]) ^ (world[1]-world[0])).normalized();
        float intensity = normal * light_dir;

        if (intensity > 0) {
            triangle2(screen, pixel_buffer, TGAColor(intensity*255, intensity*255, intensity*255, 255)); 
        } 
    }

    measure_since(start);
}

// Lesson 3 exercise. Given an input .obj file, output an image .tga of every triangle in the object with very plain "illumination" and not draw hidden faces using z-buffer.
// warning: this is using `triangle2`, not `triangle`
void obj_to_tga_illuminated_zbuffer(Model& model, IPixelBuffer& pixel_buffer) {

    auto start = measure_time();

    // Initialize the zbuffer
    float* z_buffer = (float*)malloc(sizeof(float) * pixel_buffer.get_width() * pixel_buffer.get_height());
    for (int i = 0; i < pixel_buffer.get_width() * pixel_buffer.get_height(); i++) {
        z_buffer[i] = -std::numeric_limits<float>::max();
    }

    // Where the light is "coming from"
    Vec3f light_dir(0, 0, -1);

    // For each triangle that froms the object...
    for (int i = 0; i < model.nfaces(); i++) {

        std::vector<int> face = model.face(i).location;

        Vec2i screen[3]; // the 3 points in our screen (2D) that form the triangle
        Vec3f world[3]; // the 3 points in the world (3D) that form the triangle

        // For each vertex in this triangle
        for (int j = 0; j < 3; j++) {

            Vec3f v = model.vert(face[j]);
            world[j] = v;
            screen[j] = Vec2i(
                (v.x + 1.0) * pixel_buffer.get_width() / 2.0,
                (v.y + 1.0) * pixel_buffer.get_height() / 2.0
            );

        }

        // the intensity of illumination is equal to the scalar product of the light vector and the triangle normal normal.
        // the normal to the triangle can be calculated simply as the cross product of its two sides.
        // 
        //     v3 normal = cross_product(AC, BC)
        //     float intensity = normal * light_direction
        // 
        Vec3f normal = ((world[2]-world[0]) ^ (world[1]-world[0])).normalized();
        float intensity = normal * light_dir;

        if (intensity > 0) {
            triangle2_zbuffer(screen, world, pixel_buffer, z_buffer, TGAColor(intensity*255, intensity*255, intensity*255, 255)); 
        }
    }

    free(z_buffer);
    
    measure_since(start);
}

// Lesson 3 exercise extra. Given an input .obj file, output an image .tga of every triangle in the object with very plain "illumination" and not draw hidden faces using z-buffer.
// Also uses texture sampling, using the given texture path.
// warning: this is using `triangle2`, not `triangle`
void obj_to_tga_illuminated_zbuffer_textured(Model& model, IPixelBuffer& texture_data, IPixelBuffer& pixel_buffer) {
    auto start = measure_time();

    // Initialize the zbuffer
    float* z_buffer = (float*)malloc(sizeof(float) * pixel_buffer.get_width() * pixel_buffer.get_height());
    for (int i = 0; i < pixel_buffer.get_width() * pixel_buffer.get_height(); i++) {
        z_buffer[i] = -std::numeric_limits<float>::max();
    }

    // Where the light is "coming from"
    Vec3f light_dir(0, 0, -1);

    // For each triangle that froms the object...
    for (int i = 0; i < model.nfaces(); i++) {

        std::vector<int> face = model.face(i).location;
        std::vector<int> text = model.face(i).texture;
        
        Vec2i screen[3]; // the 3 points in our screen (2D) that form the triangle
        Vec3f world[3]; // the 3 points in the world (3D) that form the triangle
        Vec2f texture[3]; // the 3 points in the texture (2d) that form triangle that will be used to "paint" the triangle in the "world"

        // For each vertex in this triangle
        for (int j = 0; j < 3; j++) {

            texture[j] = model.text(face[j]);
            Vec3f v = model.vert(face[j]);
            world[j] = v;

            screen[j] = Vec2i(
                (v.x + 1.0) * pixel_buffer.get_width() / 2.0,
                (v.y + 1.0) * pixel_buffer.get_height() / 2.0
            );
        
        }

        // the intensity of illumination is equal to the scalar product of the light vector and the triangle normal normal.
        // the normal to the triangle can be calculated simply as the cross product of its two sides.
        // 
        //     v3 normal = cross_product(AC, BC)
        //     float intensity = normal * light_direction
        // 
        Vec3f normal = ((world[2] - world[0]) ^ (world[1] - world[0])).normalized();
        float intensity = normal * light_dir;

        if (intensity > 0) {
            triangle2_zbuffer_textured(screen, world, texture, pixel_buffer, texture_data, z_buffer, TGAColor(intensity*255, intensity*255, intensity*255, 255)); 
        } 
    }

    measure_since(start);
}

//////////////////////////////////////////////////////////////

void test_wireframe(const char* out_file) {

    Model model("res/african_head.obj");
    TGAImage output(800, 800, TGAImage::RGB);

    obj_wireframe_to_tga(model, output);

    output.flip_vertically();
    output.write_tga_file(out_file);
    
}

void test_object(const char* out_file) {

    Model model("res/african_head.obj");
    TGAImage output(800, 800, TGAImage::RGB);

    obj_to_tga_illuminated(model, output);

    output.flip_vertically();
    output.write_tga_file(out_file);
    
}

void test_zbuffer_object(const char* out_file) {

    Model model("res/african_head.obj");
    TGAImage output(800, 800, TGAImage::RGB);

    obj_to_tga_illuminated_zbuffer(model, output);

    output.flip_vertically();
    output.write_tga_file(out_file);
    
}

void test_textured_object(const char* out_file) {

    Model model("res/african_head.obj");
    TGAImage texture("res/african_head_diffuse.tga");
    texture.flip_vertically();

    TGAImage output(800, 800, TGAImage::RGB);

    obj_to_tga_illuminated_zbuffer_textured(model, texture, output);

    output.flip_vertically();
    output.write_tga_file(out_file);
    
}

void test_textured_quad(const char* out_file) {
    Model model;
    TGAImage texture(2, 2, TGAImage::RGB);
    texture.set(0, 0, red);
    texture.set(1, 0, green);
    texture.set(1, 1, blue);
    texture.set(0, 1, white);
    
    TGAImage output(400, 400, TGAImage::RGB);

    obj_to_tga_illuminated_zbuffer_textured(model, texture, output);

    output.flip_vertically();
    output.write_tga_file(out_file);
}

void test_barycentric(const char* out_file) {
    TGAImage image(200, 200, TGAImage::RGB);

    Vec2i t0[3] = { Vec2i(10, 70), Vec2i(50, 160), Vec2i(70, 80) };
    triangle(t0, image, whiteTransparent);
    
    Vec2i t1[3] = { Vec2i(180, 50), Vec2i(150, 1), Vec2i(70, 180) };
    triangle(t1, image, whiteTransparent);
    
    Vec2i t2[3] = { Vec2i(180, 150), Vec2i(120, 160), Vec2i(130, 180) };
    triangle(t2, image, whiteTransparent);
    
    Vec2i t4[3] = { Vec2i(100, 190), Vec2i(110, 150), Vec2i(170, 100) };
    triangle(t4, image, whiteTransparent);
    
    Vec2i t5[3] = { Vec2i(50, 70), Vec2i(20, 40), Vec2i(40, 10) };
    triangle(t5, image, whiteTransparent);
    
    Vec2i t6[3] = { Vec2i(90, 100), Vec2i(80, 70), Vec2i(30, 20) };
    triangle(t6, image, whiteTransparent);

    for (int i = 0; i < 100; i++) {
        Vec2i random_point(rand() % 200 + 1, rand() % 200 + 1);
        Vec3f bar = barycentric(t1, random_point);
        if (barycentric_inside(bar)) {
            fat_dot(random_point, image, green);
        }
        else {
            fat_dot(random_point, image, red);
        }
    }

    image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    image.write_tga_file(out_file);
}

void test_barycentric_2(const char* out_file) {
    TGAImage image(200, 200, TGAImage::RGB);

    Vec2i t[3] = { Vec2i(0,0), Vec2i(200,0), Vec2i(100, 200) };
    // Vec2i random_point(rand() % 200 + 1, rand() % 200 + 1);
    Vec2i random_point(103, 7);
    Vec3f bar = barycentric(t, random_point);
    printf("original %d, %d\n", random_point.x, random_point.y);

    Vec2f aux[3];
    aux[0] = Vec2f(t[0].x, t[0].y);
    aux[1] = Vec2f(t[1].x, t[1].y);
    aux[2] = Vec2f(t[2].x, t[2].y);
    Vec2f result = barycentric_inverse(aux, bar);
    printf("calculat %f, %f\n", result.x, result.y);

    Vec2i t2[3] = { Vec2i(50, 50), Vec2i(100,0), Vec2i(100, 50) };
    Vec2f aux2[3];
    aux2[0] = Vec2f(t2[0].x, t2[0].y);
    aux2[1] = Vec2f(t2[1].x, t2[1].y);
    aux2[2] = Vec2f(t2[2].x, t2[2].y);
    Vec2f result2 = barycentric_inverse(aux2, bar);
    printf("calculat %f, %f\n", result2.x, result2.y);

    // TODO: triangle is broken now?
    triangle2(t, image, white);
    triangle2(t2, image, blue);
    fat_dot(random_point, image, red);
    fat_dot(Vec2i(result.x, result.y), image, green);
    fat_dot(Vec2i(result2.x, result2.y), image, aaa);

    image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    image.write_tga_file(out_file);
}

int main(int argc, char** argv) {
    srand(time(NULL));
    // test_barycentric("barycentric_test.tga");
    // test_textured_object("textured.tga");
    // test_wireframe("wireframe.tga");
    // test_object("object.tga");
    // test_zbuffer_object("zbuffer.tga");
    // test_textured_quad("quad.tga");
    test_barycentric_2("test_bar.tga");
}
