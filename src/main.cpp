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

void line(int x0, int y0, int x1, int y1, TGAImage& image, const TGAColor& color) {
    int differenceX = x1 - x0;
    int differenceXAbs = absolute(differenceX);

    int differenceY = y1 - y0;
    int differenceYAbs = absolute(differenceY);

    if (differenceXAbs > differenceYAbs) {
        // draw horizontally

        if (differenceX < 0) {
            swap(x0, x1);
            swap(y0, y1);
        }

        float percentageOfLineDone = 0.0;
        float increment = 1.0 / (float)differenceXAbs;
        for (int x = x0; x <= x1; x++) {
            int y = y0 + (y1 - y0) * percentageOfLineDone;
            image.set(x, y, color);
            percentageOfLineDone += increment;
        }
    }
    else {
        // draw vertically

        if (differenceY < 0) {
            swap(x0, x1);
            swap(y0, y1);
        }

        float percentageOfLineDone = 0.0;
        float increment = 1.0 / (float)differenceYAbs;
        for (int y = y0; y <= y1; y++) {
            int x = x0 + (x1 - x0) * percentageOfLineDone;
            image.set(x, y, color);
            percentageOfLineDone += increment;
        }
    }
}

void triangle_outline(Vec2i t0, Vec2i t1, Vec2i t2, TGAImage& image, const TGAColor& color) {
    line(t0.x, t0.y, t1.x, t1.y, image, color);
    line(t1.x, t1.y, t2.x, t2.y, image, color);
    line(t2.x, t2.y, t0.x, t0.y, image, color);
}

void fat_dot(int x, int y, TGAImage& image, const TGAColor& color) {
    image.set(x, y, color);
    image.set(x+1, y, color);
    image.set(x-1, y, color);
    image.set(x, y+1, color);
    image.set(x, y-1, color);
}

// Aparently this is an "old school" single cpu approach. The cool kids just brute-force it with the power of multi-threading, example below in `triangle2`
void triangle(Vec2i t0, Vec2i t1, Vec2i t2, TGAImage& image, const TGAColor& color) {
    // 1. find the highest vertex and the lowest vertex
    
    // Aparently this works too, but I'll leave it as I have it and that's another thing I can do without relying on the Standard library lol
    // // sort the vertices, t0, t1, t2 lower−to−upper (bubblesort yay!) 
    // if (t0.y>t1.y) std::swap(t0, t1); 
    // if (t0.y>t2.y) std::swap(t0, t2); 
    // if (t1.y>t2.y) std::swap(t1, t2);

    Vec2i* top;
    Vec2i* mid;
    Vec2i* bot;
    if (t0.y > t1.y) {
        if (t0.y > t2.y) {
            top = &t0;
            if (t1.y > t2.y) {
                mid = &t1;
                bot = &t2;
            }
            else {
                mid = &t2;
                bot = &t1;
            }
        }
        else {
            top = &t2;
            mid = &t0;
            bot = &t1;
        }
    }
    else {
        if (t1.y > t2.y) {
            top = &t1;
            if (t0.y > t2.y) {
                mid = &t0;
                bot = &t2;
            }
            else {
                mid = &t2;
                bot = &t0;
            }
        }
        else {
            top = &t2;
            mid = &t1;
            bot = &t0;
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
        line(side1, y, side2, y, image, color);
        
        // We don't really need to know which side will be in the "left" or "right", since the increments are already signed
        // Just get the current "horizontal line"'s positions and add the increments (substract* since we are drawing the triangle top to bottom)
        side1 -= incrementLongLine;
        side2 -= incrementShortLine1;
    }

    // 4. Repeat for lines between mid and bot
    for (int y  = mid->y; y >= bot-> y; y--) {
        line(side1, y, side2, y, image, color);
        side1 -= incrementLongLine;
        side2 -= incrementShortLine2;
    }
    
    // triangle_outline(t0, t1, t2, image, white);
    // fat_dot(top->x, top->y, image, green);
    // fat_dot(mid->x, mid->y, image, blue);
    // fat_dot(bot->x, bot->y, image, red);
}

void lesson1_obj_to_tga(const char* inputObjModelFileName, const int width, const int height, const char* outputTgaFileName) {
    Model* model = NULL;
    model = new Model(inputObjModelFileName);


    TGAImage image(width, height, TGAImage::RGB);
    auto start = measure_time();
    for (int i = 0; i < model->nfaces(); i++) {
        std::vector<int> face = model->face(i).location;

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

            Vec3f v0 = model->vert(face[j]);
            // the % 3 (module 3) is here so that when we are drawing the
            // last line [2-0] j wraps around and instead of j == 3 have j == 0
            Vec3f v1 = model->vert(face[(j + 1) % 3]);

            // draw a line between the 2 vertices ignoring it's z coordinate
            int x0 = (v0.x + 1.0f) * width / 2.0f;
            int y0 = (v0.y + 1.0f) * height / 2.0f;
            int x1 = (v1.x + 1.0f) * width / 2.0f;
            int y1 = (v1.y + 1.0f) * height / 2.0f;

            line(x0, y0, x1, y1, image, white);
        }
    }

    measure_since(start);
    delete model;

    image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    image.write_tga_file(outputTgaFileName);
}

// https://www.scratchapixel.com/lessons/3d-basic-rendering/ray-tracing-rendering-a-triangle/barycentric-coordinates#:~:text=To%20compute%20the%20position%20of,(barycentric%20coordinates%20are%20normalized)
// https://www.youtube.com/watch?v=HYAgJN3x4GA
// Why did I make u, v, w and isInside pointers?????
void baricenter_coordinates(Vec2f &a, Vec2f &b, Vec2f &c, Vec2f &p, float *u, float *v, float *w, bool *isInside /*, TGAImage& image*/) {
    #ifdef BARICENTER_NO_USE_OPTIMIZATION_1
    Vec2i ab = b - a;
    Vec2i ac = c - a;
    Vec2i ap = p - a;
    Vec2i bp = p - b;
    Vec2i ca = a - c;
    // the magnitude of the cross product can be interpreted as the area of the parallelogram.
    float paralelogramAreaABC = ab.cross_product_magnitude(ac);
    float triangleAreaABC = paralelogramAreaABC / 2.0f;
    float paralelogramAreaABP = ab.cross_product_magnitude(bp);
    float paralelogramAreaCAP = ca.cross_product_magnitude(ap);
    *u = (paralelogramAreaABP / 2.0f) / triangleAreaABC;
    *v = (paralelogramAreaCAP / 2.0f) / triangleAreaABC;
    #else
    Vec2f ab = b - a;
    Vec2f ac = c - a;
    Vec2f ap = p - a;
    Vec2f bp = p - b;
    Vec2f ca = a - c;
    // There is actually no need to do the "/ 2.0f" divisions we can instead do...
    *u = (ab ^ bp) / (ab ^ ac);
    *v = (ca ^ ap) / (ab ^ ac);
    #endif // BARICENTER_NO_USE_OPTIMIZATION_1

    // since we have u and v we can figure out w
    *w = (1.0f - *u - *v);
    // figure out if the point is inside the triangle
    *isInside = true;
    if (*u < 0.0f || *u > 1.0f) { *isInside = false; }
    if (*v < 0.0f || *v > 1.0f) { *isInside = false; }
    if (*w < 0.0f || *w > 1.0f) { *isInside = false; }

    // if (*isInside) {
    //     fat_dot(p.x, p.y, image, green);
    // }
    // else {
    //     fat_dot(p.x, p.y, image, red);
    // }
}

void baricenter_coordinates(Vec2i &a, Vec2i &b, Vec2i &c, Vec2i &p, float *u, float *v, float *w, bool *isInside /*, TGAImage& image*/) {
    baricenter_coordinates(Vec2f(a.x, a.y), Vec2f(b.x, b.y), Vec2f(c.x, c.y), Vec2f(p.x, p.y), u, v, w, isInside);
}


// usage
// 
//     Vec2i tl;
//     Vec2i br;
//     find_bounding_box(t0, t1, t2, &tl, &br);
// 
void find_bounding_box(Vec2i t0, Vec2i t1, Vec2i t2, Vec2i* outTopLeft, Vec2i* outBottomRight) {
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
    outTopLeft->x = MIN(t0.x, MIN(t1.x, t2.x));
    outTopLeft->y = MAX(t0.y, MAX(t1.y, t2.y));

    outBottomRight->x = MAX(t0.x, MAX(t1.x, t2.x));
    outBottomRight->y = MIN(t0.y, MIN(t1.y, t2.y));
}

void find_bounding_box(Vec2i* t, Vec2i* outTopLeft, Vec2i* outBottomRight) {
    outTopLeft->x = MIN(t[0].x, MIN(t[1].x, t[2].x));
    outTopLeft->y = MAX(t[0].y, MAX(t[1].y, t[2].y));

    outBottomRight->x = MAX(t[0].x, MAX(t[1].x, t[2].x));
    outBottomRight->y = MIN(t[0].y, MIN(t[1].y, t[2].y));
}

void triangle2(Vec2i t0, Vec2i t1, Vec2i t2, TGAImage& image, const TGAColor& color) {
    Vec2i tl;
    Vec2i br;
    find_bounding_box(t0, t1, t2, &tl, &br);
    
    float u;
    float v;
    float w;
    bool isInside;
    for (int y = tl.y; y > br.y; y--) { // top to bottom
        for (int x = tl.x; x < br.x; x++) { // left to right
            // image.set(x, y, color);
            baricenter_coordinates(t0, t1, t2, Vec2i(x, y), &u, &v, &w, &isInside);
            if (isInside) {
                image.set(x, y, color);
            }
        }
    }

    // triangle_outline(t0, t1, t2, image, white);
    // fat_dot(tl.x, tl.y, image, green);
    // fat_dot(br.x, br.y, image, blue);
}

// t0, t1 and t2, expected to be a 2d point + z-buffer on the 3rd element (hence them being vec3i instead of vec2i)
void triangle2_zbuffer(Vec3i t0, Vec3i t1, Vec3i t2, float* zbuffer, TGAImage& image, const TGAColor& color) {
    Vec2i tl, br;
    // Transform the input vertices to vec2i since I don't have the implementation for find_bounding_box
    // and baricenter_coordinates with input being vec3i lol
    Vec2i _t0(t0), _t1(t1), _t2(t2);
    find_bounding_box(_t0, _t1, _t2, &tl, &br);
    
    int image_witdth = image.get_width();
    for (int y = tl.y; y > br.y; y--) { // top to bottom
        for (int x = tl.x; x < br.x; x++) { // left to right
            float u, v, w;
            bool isInside;
            baricenter_coordinates(_t0, _t1, _t2, Vec2i(x, y), &u, &v, &w, &isInside);
            if (!isInside) continue;

            // > the idea is to take the barycentric coordinates version of triangle rasterization,
            // > and for every pixel we want to draw simply to multiply its barycentric coordinates [u, v, w]
            // > by the z-values [3rd element] of the vertices of the triangle [t0, t1 and t2] we rasterize
            float z = 0;
            z += (float) t0.z * u;
            z += (float) t1.z * v;
            z += (float) t2.z * w;

            // calculate z-buffer value's index
            int idx = int(x + y * image_witdth);
            if (zbuffer[idx] < z) {
                zbuffer[idx] = z;
                image.set(x, y, color);
            }

        }
    }

    // triangle_outline(t0, t1, t2, image, white);
    // fat_dot(tl.x, tl.y, image, green);
    // fat_dot(br.x, br.y, image, blue);
}

// usage:
// 
//     int main(int argc, char** argv) {
//         srand (time(NULL));
//         lesson2_obj_to_tga_triangle1("res/african_head.obj", 800, 800, "output1.tga");
//     }
// 
void lesson2_obj_to_tga_triangle1(const char* inputObjModelFileName, const int width, const int height, const char* outputTgaFileName) {
    Model* model = NULL;
    model = new Model(inputObjModelFileName);

    TGAImage image(width, height, TGAImage::RGB);
    auto start = measure_time();
    
    // Where the light is "coming from"
    Vec3f light_dir(0,0,-1);

    // For each triangle that froms the object...
    for (int i=0; i < model->nfaces(); i++) {
        
        std::vector<int> face = model->face(i).location;
        
        Vec2i screen_coords[3]; // the 3 points in our screen (2D) that form the triangle
        Vec3f world_coords[3]; // the 3 points in the world (3D) that form the triangle
        
        // For each vertex in this triangle
        for (int j = 0; j < 3; j++) {
        
            Vec3f v = model->vert(face[j]);

            screen_coords[j] = Vec2i( (v.x+1.0) * width / 2.0, (v.y+1.0) * height / 2.0);
            world_coords[j] = v;
        
        }

        // the intensity of illumination is equal to
        // the scalar product of
        // the light vector AND the triangle normal normal.
        //
        // The normal to the triangle can be calculated simply as the cross product of its two sides.
        // 
        //     v3 normal = cross_product(AC, BC)
        //     float intensity = normal * light_direction
        // 
        Vec3f normal = (world_coords[2]-world_coords[0])^(world_coords[1]-world_coords[0]); // normal
        normal.normalize();
        float intensity = normal * light_dir;

        if (intensity>0) { 
            triangle(screen_coords[0], screen_coords[1], screen_coords[2], image, TGAColor(intensity*255, intensity*255, intensity*255, 255)); 
        } 
    }

    measure_since(start);
    delete model;

    image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    image.write_tga_file(outputTgaFileName);
}

// usage:
// 
//     int main(int argc, char** argv) {
//         srand (time(NULL));
//         lesson2_obj_to_tga_triangle2("res/african_head.obj", 800, 800, "output2.tga");
//     }
// 
void lesson2_obj_to_tga_triangle2(const char* inputObjModelFileName, const int width, const int height, const char* outputTgaFileName) {
    Model* model = NULL;
    model = new Model(inputObjModelFileName);

    TGAImage image(width, height, TGAImage::RGB);
    
    auto start = measure_time();
    
    // Where the light is "coming from"
    Vec3f light_dir(0,0,-1);

    // For each triangle that froms the object...
    for (int i=0; i < model->nfaces(); i++) {
        
        std::vector<int> face = model->face(i).location;
        
        Vec2i screen_coords[3]; // the 3 points in our screen (2D) that form the triangle
        Vec3f world_coords[3]; // the 3 points in the world (3D) that form the triangle
        
        // For each vertex in this triangle
        for (int j = 0; j < 3; j++) {
        
            Vec3f v = model->vert(face[j]);

            screen_coords[j] = Vec2i( (v.x+1.0) * width / 2.0, (v.y+1.0) * height / 2.0);
            world_coords[j] = v;
        
        }

        // the intensity of illumination is equal to
        // the scalar product of
        // the light vector AND the triangle normal normal.
        //
        // The normal to the triangle can be calculated simply as the cross product of its two sides.
        // 
        //     v3 normal = cross_product(AC, BC)
        //     float intensity = normal * light_direction
        // 
        Vec3f normal = (world_coords[2]-world_coords[0])^(world_coords[1]-world_coords[0]); // normal
        normal.normalize();
        float intensity = normal * light_dir;

        if (intensity>0) { 
            triangle2(screen_coords[0], screen_coords[1], screen_coords[2], image, TGAColor(intensity*255, intensity*255, intensity*255, 255)); 
        } 
    }

    measure_since(start);
    delete model;

    image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    image.write_tga_file(outputTgaFileName);
}

void lesson3_obj_to_tga_triangle_zbuffer(const char* inputObjModelFileName, const int width, const int height, const char* outputTgaFileName) {
    Model* model = NULL;
    model = new Model(inputObjModelFileName);

    TGAImage image(width, height, TGAImage::RGB);
    
    auto start = measure_time();
    
    // Where the light is "coming from"
    Vec3f light_dir(0,0,-1);

    // Initialize the zbuffer
    float* zbuffer = (float*)malloc(sizeof(float) * width * height);
    for (int i = 0; i < width * height; i++) zbuffer[i] = -std::numeric_limits<float>::max();

    // For each triangle that froms the object...
    for (int i = 0; i < model->nfaces(); i++) {
        
        std::vector<int> face = model->face(i).location;
        
        Vec3i screen_coords[3]; // the 3 points in our screen (2D) that form the triangle
        Vec3f world_coords[3]; // the 3 points in the world (3D) that form the triangle
        
        // For each vertex in this triangle
        for (int j = 0; j < 3; j++) {
        
            Vec3f v = model->vert(face[j]);

            screen_coords[j] = Vec3i(
                (v.x + 1.0) * width / 2.0,
                (v.y + 1.0) * height / 2.0,
                (v.z)
            );
            world_coords[j] = v;
        
        }

        // the intensity of illumination is equal to
        // the scalar product of
        // the light vector AND the triangle normal normal.
        //
        // The normal to the triangle can be calculated simply as the cross product of its two sides.
        // 
        //     v3 normal = cross_product(AC, BC)
        //     float intensity = normal * light_direction
        // 
        Vec3f normal = (world_coords[2]-world_coords[0])^(world_coords[1]-world_coords[0]); // normal
        normal.normalize();
        float intensity = normal * light_dir;

        if (intensity>0) { 
            triangle2_zbuffer(screen_coords[0], screen_coords[1], screen_coords[2], zbuffer, image, TGAColor(intensity*255, intensity*255, intensity*255, 255)); 
        } 
    }

    measure_since(start);
    delete model;

    image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    image.write_tga_file(outputTgaFileName);
}

TGAColor sample(TGAImage& texture_data, Vec2f* texture_triangle, Vec3f barycentric) {

    float u = barycentric.x;
    float v = barycentric.y;
    float w = barycentric.z;

    Vec2f a = texture_triangle[0];
    Vec2f b = texture_triangle[1];
    Vec2f c = texture_triangle[2];

    // P=uA+vB+wC
    Vec2f point = a * u + b * v + c * w;

    // aparently in tga the coordinates seem to be normalized so everything is between 0 and 1 for the texture coords so gotta scale them with the textures size
    return texture_data.get(point.x * texture_data.get_width(), point.y * texture_data.get_height());
}

void triangle2_zbuffer_texture_sampling(Vec2i* screen, Vec3f* world, Vec2f* texture, float* zbuffer, TGAImage& image, TGAImage& texture_data, const TGAColor& color) {
    Vec2i tl, br;
    int image_witdth = image.get_width();

    // find the 2d square that contains the screen triangle, as that is where we will render it
    find_bounding_box(screen, &tl, &br);
    
    for (int y = tl.y; y > br.y; y--) { // top to bottom
        for (int x = tl.x; x < br.x; x++) { // left to right

            float u, v, w;
            bool isInside;
            baricenter_coordinates(screen[0], screen[1], screen[2], Vec2i(x, y), &u, &v, &w, &isInside);
            if (!isInside) continue;

            // > the idea is to take the barycentric coordinates version of triangle rasterization,
            // > and for every pixel we want to draw simply to multiply its barycentric coordinates [u, v, w]
            // > by the z-values [3rd element] of the vertices of the triangle [t0, t1 and t2] we rasterize
            float z = 0;
            z += (float) world[0].z * u;
            z += (float) world[1].z * v;
            z += (float) world[2].z * w;

            // calculate z-buffer value's index
            int idx = int(x + y * image_witdth);

            if (zbuffer[idx] < z) {
                zbuffer[idx] = z;

                // barycentric interpolation... I think
                // TODO so it doesnt work yet and I think the reason is that the uvw were taken respective to the screen while the texture coordinates
                // are in the context fo world coordinates. If that is correct, that means that I just need to get the u v w from the world perspective.
                // The only stopper is that I dont quite understand how to get the baricenter coordinates with a 3rd coordinate, last time I barely managed
                // and it was in 2D... I need to refresh my math fr
                TGAColor texture_sample = sample(texture_data, texture, Vec3f(u, v, w));
                image.set(x, y, texture_sample);
            }

        }
    }

    // triangle_outline(t0, t1, t2, image, white);
    // fat_dot(tl.x, tl.y, image, green);
    // fat_dot(br.x, br.y, image, blue);
}

void lesson3_obj_to_tga_triangle_zbuffer_with_texture(const char* inputObjModelFileName, const char* inputTextureFileName, const int width, const int height, const char* outputTgaFileName) {
    Model* model = NULL;
    model = new Model(inputObjModelFileName);

    TGAImage output_image(width, height, TGAImage::RGB);
    
    TGAImage texture_data;
    texture_data.read_tga_file(inputTextureFileName); // TODO load the texture
    
    auto start = measure_time();
    
    // Where the light is "coming from"
    Vec3f light_dir(0,0,-1);

    // Initialize the zbuffer
    float* zbuffer = (float*)malloc(sizeof(float) * width * height);
    for (int i = 0; i < width * height; i++) zbuffer[i] = -std::numeric_limits<float>::max();

    // For each triangle that froms the object...
    for (int i = 0; i < model->nfaces(); i++) {
        
        std::vector<int> face = model->face(i).location;
        std::vector<int> text = model->face(i).texture;
        
        Vec2i screen_coords[3]; // the 3 points in our screen (2D) that form the triangle
        Vec3f world_coords[3]; // the 3 points in the world (3D) that form the triangle
        Vec2f texture_coords[3]; // the 3 points in the texture (2d) that form triangle that will be used to "paint" the triangle in the "world"

        // For each vertex in this triangle
        for (int j = 0; j < 3; j++) {
        
            Vec3f v = model->vert(face[j]);

            texture_coords[j] = model->text(face[j]);
            world_coords[j] = model->vert(face[j]);
            screen_coords[j] = Vec2i(
                (v.x + 1.0) * (double)width / 2.0,
                (v.y + 1.0) * (double)height / 2.0
            );
        
        }

        // the intensity of illumination is equal to
        // the scalar product of
        // the light vector AND the triangle normal normal.
        //
        // The normal to the triangle can be calculated simply as the cross product of its two sides.
        // 
        //     v3 normal = cross_product(AC, BC)
        //     float intensity = normal * light_direction
        // 
        Vec3f normal = (world_coords[2]-world_coords[0]) ^ (world_coords[1]-world_coords[0]); // normal
        float intensity = normal.normalized() * light_dir;

        if (intensity > 0) {
            triangle2_zbuffer_texture_sampling(screen_coords, world_coords, texture_coords, zbuffer, output_image, texture_data, TGAColor(intensity*255, intensity*255, intensity*255, 255)); 
        } 
    }

    measure_since(start);
    delete model;
    texture_data.clear();

    output_image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    output_image.write_tga_file(outputTgaFileName);
}

int main(int argc, char** argv) {
    srand (time(NULL));
    // lesson2_obj_to_tga_triangle1("res/african_head.obj", 800, 800, "output1.tga");
    // lesson2_obj_to_tga_triangle2("res/african_head.obj", 800, 800, "output2.tga");
    // lesson3_obj_to_tga_triangle_zbuffer("res/african_head.obj", 800, 800, "output3.tga");
    lesson3_obj_to_tga_triangle_zbuffer_with_texture("res/african_head.obj", "res/african_head_diffuse.tga", 800, 800, "output4.tga");
}

int main2(int argc, char** argv) {
    TGAImage image(200, 200, TGAImage::RGB);

    #define tri triangle2
    Vec2i t0[3] = { Vec2i(10, 70),   Vec2i(50, 160),  Vec2i(70, 80) };
    tri(t0[0], t0[1], t0[2], image, whiteTransparent);
    Vec2i t1[3] = { Vec2i(180, 50),  Vec2i(150, 1),   Vec2i(70, 180) };
    tri(t1[0], t1[1], t1[2], image, whiteTransparent);
    Vec2i t2[3] = { Vec2i(180, 150), Vec2i(120, 160), Vec2i(130, 180) };
    tri(t2[0], t2[1], t2[2], image, whiteTransparent);
    Vec2i t4[3] = { Vec2i(100, 190),   Vec2i(110, 150),  Vec2i(170, 100) };
    tri(t4[0], t4[1], t4[2], image, whiteTransparent);
    Vec2i t5[3] = { Vec2i(50, 70),   Vec2i(20, 40),  Vec2i(40, 10) };
    tri(t5[0], t5[1], t5[2], image, whiteTransparent);
    Vec2i t6[3] = { Vec2i(90, 100),   Vec2i(80, 70),  Vec2i(30, 20) };
    tri(t6[0], t6[1], t6[2], image, whiteTransparent);

    srand (time(NULL));
    float t0u, t0v, t0w; bool t0inside;
    for (int i = 0; i < 100; i++) {
        #define T t1
        // baricenter_coordinates(T[0], T[1], T[2], Vec2i(rand() % 200 + 1, rand() % 200 + 1), &t0u, &t0v, &t0w, &t0inside, image);
    }

    image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    // Note: I'm using http://schmittl.github.io/tgajs/ to visualize the image
    image.write_tga_file("output.tga");
    return 0;
}

