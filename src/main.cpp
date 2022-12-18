// Note: I'm using http://schmittl.github.io/tgajs/ to visualize the tga images generated

#include "tgaimage.h"
#include <vector>
#include <cmath>
#include <iostream>

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

void triangle_zbuffer_textured(Vec2i screen[3], Vec3f world[3], Vec2f texture[3], IPixelBuffer& image, IPixelBuffer& texture_data, float z_buffer[], const TGAColor& color) {

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

    int image_witdth = image.get_width();
    int image_height = image.get_height();

    // first, draw the top half of the triangle
    for (int y = top->y; y > bot->y; y--) {

        // TODO I probably dont need to check this in each line
        int left = side1;
        int right = side2;
        if (left > right) {
            swap(left, right);
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
            float z = 0;
            z += world[0].z * bar.u;
            z += world[1].z * bar.v;
            z += world[2].z * bar.w;

            // This is equivalent to this but without the extra uneeded calculations
            //
            //     Vec3f point_in_world_space = barycentric_inverse(world, bar);
            //     z = point_in_world_space.z;
            //     float z = 0;
            //


            // calculate z-buffer value's index
            int idx = int(x + y * image_witdth);

            // if (x < 0 || x >= image_witdth) continue;
            // if (y < 0 || y >= image_height) continue;

            if (z_buffer[idx] < z) {
                z_buffer[idx] = z;

                TGAColor texture_sample = sample(texture_data, texture, bar);

                image.set(x, y, TGAColor(
                    color.r / 255.0f * texture_sample.r,
                    color.g / 255.0f * texture_sample.g,
                    color.b / 255.0f * texture_sample.b,
                    color.a
                ));
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

void triangle_zbuffer_textured_gouraud(Vec2i screen[3], Vec3f world[3], Vec2f texture[3], Vec3f normals[3], IPixelBuffer& image, IPixelBuffer& texture_data, float z_buffer[]) {

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

    int image_witdth = image.get_width();
    int image_height = image.get_height();

    // first, draw the top half of the triangle
    for (int y = top->y; y > bot->y; y--) {

        // TODO I probably dont need to check this in each line
        int left = side1;
        int right = side2;
        if (left > right) {
            swap(left, right);
        }
        
        // draw a horizontal line (left, y) to (right, y)
        for (int x = left; x <= right; x++) {
            
            // barycentric coordinates for `z-buffer` and `texture sampling`
            Vec3f bar = barycentric(screen, Vec2i(x, y));

            // the intensity of illumination is equal to the scalar product of the light vector and the triangle normal normal.
            // the normal is taken from the precomputed vertex normal this time, however we want to interpolate between the normals in each of the vertex of the triangle
            // which means that instead of calculating it once per triangle here, like before, we need to do it once per fragment
            
            
            static Vec3f light_dir(0, 0, -1);
            Vec3f normal = /*interpolated normal*/ barycentric_inverse(normals, bar);
            float intensity = normal * light_dir;
            // I'm not sure why I used to make this check inversed previously...
            if (intensity > 0) continue;
            TGAColor color(intensity * 255, intensity * 255, intensity * 255, 255);

            // > the idea is to take the barycentric coordinates version of triangle rasterization,
            // > and for every pixel we want to draw simply to multiply its barycentric coordinates [u, v, w]
            // > by the z-values [3rd element] of the vertices of the triangle [t0, t1 and t2] we rasterize
            // This is basically finding the z value of an specific pixel in a triangle by interpolating the 3 values of z that we know.
            // The same as how we sample the texture, except in this case we only care about the z components.
            float z = 0;
            z += world[0].z * bar.u;
            z += world[1].z * bar.v;
            z += world[2].z * bar.w;

            // This is equivalent to this but without the extra uneeded calculations
            //
            //     Vec3f point_in_world_space = barycentric_inverse(world, bar);
            //     z = point_in_world_space.z;
            //     float z = 0;
            //

            // calculate z-buffer value's index
            int idx = int(x + y * image_witdth);

            // if (x < 0 || x >= image_witdth) continue;
            // if (y < 0 || y >= image_height) continue;

            if (z_buffer[idx] < z) {
                z_buffer[idx] = z;

                TGAColor texture_sample = sample(texture_data, texture, bar);

                image.set(x, y, TGAColor(
                    color.r / 255.0f * texture_sample.r,
                    color.g / 255.0f * texture_sample.g,
                    color.b / 255.0f * texture_sample.b,
                    color.a
                ));

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
                // https://github.com/ssloy/tinyrenderer/wiki/Lesson-5:-Moving-the-camera#viewport
                // So v0.x is a number from [-1, 1]. Instead we want to map it to [0, 1], which
                // can map directly to our "image". So we do `(v0.x + 1.0f) / 2.0f` and now we have mapped
                // the origin [-1, 1] to a [0, 1] space!
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

    // Initialize the zbuffer
    static float* z_buffer = (float*)malloc(sizeof(float) * pixel_buffer.get_width() * pixel_buffer.get_height());
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

            texture[j] = model.text(text[j]);
            Vec3f v = model.vert(face[j]);
            world[j] = v;
            // TODO apply matrix transformation to world coords, then calcualte screen coords

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
            // using single threaded optimized version
            triangle_zbuffer_textured(screen, world, texture, pixel_buffer, texture_data, z_buffer, TGAColor(intensity * 255, intensity * 255, intensity * 255, 255));
            // using brute force version lol
            // triangle2_zbuffer_textured(screen, world, texture, pixel_buffer, texture_data, z_buffer, TGAColor(intensity*255, intensity*255, intensity*255, 255)); 
        }

        // Left over code from back when I was debugging why my texture wasn't being shown properly... Never forgeti
        if (false && i == 0) {
            
            static bool once = true;
            if (once) {
                once = false;
                std::cerr << "texture:\n" << texture[0] << texture[1] << texture[2] << std::endl;
                std::cerr << "world:\n" << world[0] << world[1] << world[2] << std::endl;
                std::cerr << "screen:\n" << screen[0] << screen[1] << screen[2] << std::endl;
                
                // bar at a
                Vec3f bara = barycentric(screen, screen[0]);
                std::cerr << "bar screen at a:\n" << bara << std::endl;
                Vec2f bara_ = barycentric_inverse(texture, bara);
                std::cerr << "at texture:\n" << bara_ << std::endl;
                Vec2i bara_text = Vec2i(bara_.x * texture_data.get_width(), bara_.y * texture_data.get_height());
                std::cerr << "scaled: " << bara_text << std::endl;

                Vec3f barb = barycentric(screen, screen[1]);
                std::cerr << "bar screen at b:\n" << barb << std::endl;
                Vec2f barb_ = barycentric_inverse(texture, barb);
                std::cerr << "at texture:\n" << barb_ << std::endl;
                Vec2i barb_text = Vec2i(barb_.x * texture_data.get_width(), barb_.y * texture_data.get_height());
                std::cerr << "scaled: " << barb_text << std::endl;

                Vec3f barc = barycentric(screen, screen[2]);
                std::cerr << "bar screen at c:\n" << barc << std::endl;
                Vec2f barc_ = barycentric_inverse(texture, barc);
                std::cerr << "at texture:\n" << barc_ << std::endl;
                Vec2i barc_text = Vec2i(barc_.x * texture_data.get_width(), barc_.y * texture_data.get_height());
                std::cerr << "scaled: " << barc_text << std::endl;
            }

            triangle_outline(screen, pixel_buffer, TGAColor(0, 255, 0, 255));
        }
    }

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

// Builds a "viewport matrix".
// So, a viewport is just a matrix that will translate and map every point,
// mapping every point in the original 3 dimensional cube with ranges[-1, 1] * [-1, 1] * [-1, 1]
// onto the screen cube [x, x + w] * [y, y + h] * [0, d], where d is the depth (and resolution) of the z-buffer and of value 255.
// opengl calls this the viewport matrix
Matrix viewport(int x, int y, int w, int h, int depth = 255) {

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

    return m;
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
Matrix lookat(Vec3f camera_location, Vec3f point_looked_at, Vec3f up) {

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
    return model_view;
}

// Lesson 4. Now with perspective projection (and other 3d space transformations and stuff)
void obj_to_tga_illuminated_zbuffer_textured_perspective(Model& model, IPixelBuffer& texture_data, IPixelBuffer& pixel_buffer, Vec3f camera) {

    // Initialize the zbuffer
    static float* z_buffer = (float*)malloc(sizeof(float) * pixel_buffer.get_width() * pixel_buffer.get_height());
    for (int i = 0; i < pixel_buffer.get_width() * pixel_buffer.get_height(); i++) {
        z_buffer[i] = -std::numeric_limits<float>::max();
    }

    // Where the light is "coming from"
    Vec3f light_dir(0, 0, -1);
    
    // The Model matrix describes how we are placing the Model in the world.
    // 
    //     > Model maps from an object's local coordinate space into world space
    // 
    // Since we want the model to be in the same place as it is in the object coordinates, we just set it to the Identity matrix.
    // That means that a point in object coordinates (0.31, 0.47, 0.32) will be in the point (0.31, 0.47, 0.32) in the world coordinates.
    // If we were to want to apply transformations, rotations, scaling... to the model, we would do so here.
    Matrix model_matrix = Matrix::identity();

    Vec3f camera_location(0.f, 0.f, 1.f);
    Matrix view_matrix = lookat(camera_location, camera_location + Vec3f(0.f, 0.f, -1.f), Vec3f(0.f, 1.f, 0.f));

    Matrix projection_matrix = Matrix::identity();
    // https://github.com/ssloy/tinyrenderer/wiki/Lesson-4:-Perspective-projection
    // The Projection matrix deforms the scene to create a sense of perspective.
    // This projection matrix assumes that the camera is on z-axis, meaning that the distance to the origin will be the z element.
    // TODO projections for arbitrary camera position, how? what does it mean that this assumes camera on z axis?
    float c = camera_location.z;
    if (c != 0) {
        projection_matrix[3][2] = -1 / c;
    }

    Matrix viewport_matrix = viewport(0, 0, pixel_buffer.get_width(), pixel_buffer.get_height());

    // For each triangle that froms the object...
    for (int i = 0; i < model.nfaces(); i++) {

        std::vector<int> face = model.face(i).location;
        std::vector<int> text = model.face(i).texture;
        
        Vec2i screen[3]; // the 3 points in our screen (2D) that form the triangle
        Vec3f world[3]; // the 3 points in the world (3D) that form the triangle
        Vec2f texture[3]; // the 3 points in the texture (2d) that form triangle that will be used to "paint" the triangle in the "world"

        bool skip = false;
        
        // For each vertex in this triangle
        for (int j = 0; j < 3; j++) {

            texture[j] = model.text(text[j]);
            world[j] = model.vert(face[j]);
            
            Matrix point_object_coords = embed_in_4d(world[j]);
            Matrix point_world_coords = model_matrix * point_object_coords;
            Matrix point_camera_coords = view_matrix * point_world_coords;
            Matrix point_clip_coords = projection_matrix * point_camera_coords;
            Matrix point_screen_coords = viewport_matrix * point_clip_coords;
            Vec3f final_point = retro_project_back_into_3d(point_screen_coords);

            screen[j] = Vec2i(
                final_point.x, final_point.y
            );

            if ((int)final_point.x < 0 || (int)final_point.x >= pixel_buffer.get_width()) { skip = true; continue; }
            if ((int)final_point.y < 0 || (int)final_point.y >= pixel_buffer.get_height()) { skip = true; continue; }
        }

        // any face which contains a vertex outside the screen, skip it
        if (skip) continue;

        // the intensity of illumination is equal to the scalar product of the light vector and the triangle normal normal.
        // the normal to the triangle can be calculated simply as the cross product of its two sides.
        // 
        //     v3 normal = cross_product(AC, BC)
        //     float intensity = normal * light_direction
        // 
        Vec3f normal = ((world[2] - world[0]) ^ (world[1] - world[0])).normalized();
        float intensity = normal * light_dir;
        if (intensity <= 0) continue;

        triangle_zbuffer_textured(screen, world, texture, pixel_buffer, texture_data, z_buffer, TGAColor(intensity * 255, intensity * 255, intensity * 255, 255));
    }

}

// Lesson 5. Now the same but applying gouraud lightning, using the vertex normals in Model
void obj_to_tga_illuminated_gouraud_zbuffer_textured_perspective(Model& model, IPixelBuffer& texture_data, IPixelBuffer& pixel_buffer, Vec3f camera) {

    // Initialize the zbuffer
    static float* z_buffer = (float*)malloc(sizeof(float) * pixel_buffer.get_width() * pixel_buffer.get_height());
    for (int i = 0; i < pixel_buffer.get_width() * pixel_buffer.get_height(); i++) {
        z_buffer[i] = -std::numeric_limits<float>::max();
    }

    // Where the light is "coming from"
    Vec3f light_dir(0, 0, -1);
    
    // The Model matrix describes how we are placing the Model in the world.
    // 
    //     > Model maps from an object's local coordinate space into world space
    // 
    // Since we want the model to be in the same place as it is in the object coordinates, we just set it to the Identity matrix.
    // That means that a point in object coordinates (0.31, 0.47, 0.32) will be in the point (0.31, 0.47, 0.32) in the world coordinates.
    // If we were to want to apply transformations, rotations, scaling... to the model, we would do so here.
    Matrix model_matrix = Matrix::identity();

    Vec3f camera_location(0.f, 0.f, 1.f);
    Matrix view_matrix = lookat(camera_location, camera_location + Vec3f(0.f, 0.f, -1.f), Vec3f(0.f, 1.f, 0.f));

    Matrix projection_matrix = Matrix::identity();
    // https://github.com/ssloy/tinyrenderer/wiki/Lesson-4:-Perspective-projection
    // The Projection matrix deforms the scene to create a sense of perspective.
    // This projection matrix assumes that the camera is on z-axis, meaning that the distance to the origin will be the z element.
    // TODO projections for arbitrary camera position, how? what does it mean that this assumes camera on z axis?
    float c = camera_location.z;
    if (c != 0) {
        projection_matrix[3][2] = -1 / c;
    }

    Matrix viewport_matrix = viewport(0, 0, pixel_buffer.get_width(), pixel_buffer.get_height());

    // For each triangle that froms the object...
    for (int i = 0; i < model.nfaces(); i++) {

        std::vector<int> face = model.face(i).location;
        std::vector<int> text = model.face(i).texture;
        std::vector<int> norm = model.face(i).normals;
        
        Vec2i screen[3]; // the 3 points in our screen (2D) that form the triangle
        Vec3f world[3]; // the 3 points in the world (3D) that form the triangle
        Vec2f texture[3]; // the 3 points in the texture (2d) that form triangle that will be used to "paint" the triangle in the "world"
        Vec3f normals[3]; // the 3 precomputed normals of each vertex of this triangle

        bool skip = false;
        
        // For each vertex in this triangle
        for (int j = 0; j < 3; j++) {

            texture[j] = model.text(text[j]);
            world[j] = model.vert(face[j]);
            normals[j] = model.normal(norm[j]);
            
            Matrix point_object_coords = embed_in_4d(world[j]);
            Matrix point_world_coords = model_matrix * point_object_coords;
            Matrix point_camera_coords = view_matrix * point_world_coords;
            Matrix point_clip_coords = projection_matrix * point_camera_coords;
            Matrix point_screen_coords = viewport_matrix * point_clip_coords;
            Vec3f final_point = retro_project_back_into_3d(point_screen_coords);

            screen[j] = Vec2i(
                final_point.x, final_point.y
            );

            if ((int)final_point.x < 0 || (int)final_point.x >= pixel_buffer.get_width()) { skip = true; continue; }
            if ((int)final_point.y < 0 || (int)final_point.y >= pixel_buffer.get_height()) { skip = true; continue; }
        }

        // any face which contains a vertex outside the screen, skip it
        if (skip) continue;

        triangle_zbuffer_textured_gouraud(screen, world, texture, normals, pixel_buffer, texture_data, z_buffer);
    }

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

#include "win32.h"

#define rgb(r,g,b) ((uint32_t)(((uint8_t)r << 16) | ((uint8_t)g << 8) | (uint8_t)b))

struct PixelBuffer: public IPixelBuffer {
protected:
    uint32_t* data;
    int width;
    int height;
    bool managed;

public:
    PixelBuffer(int w, int h) : data(NULL), width(w), height(h), managed(true) {
        data = (uint32_t*)malloc(width * height * sizeof(uint32_t));
    }
    PixelBuffer(int w, int h, uint32_t clear_color) : data(NULL), width(w), height(h), managed(true) {
        data = (uint32_t*)malloc(width * height * sizeof(uint32_t));
        clear(clear_color);
    }
    PixelBuffer(int w, int h, uint32_t* data, uint32_t clear_color) : data(data), width(w), height(h), managed(false) {
        clear(clear_color);
    }
    PixelBuffer(int w, int h, uint32_t* data) : data(data), width(w), height(h), managed(false) {
    }
    TGAColor get(int x, int y) {
        if (!data || x<0 || y<0 || x>=width || y>=height) {
            return TGAColor();
        }

        int idx = int(x + y * width);
        return TGAColor((uint8_t)(data[idx] >> 16), (uint8_t)(data[idx] >> 8), (uint8_t)(data[idx]), 255);
    }
    bool set(int x, int y, TGAColor c) {
        if (!data || x<0 || y<0 || x>=width || y>=height) {
            return false;
        }
        int idx = int(x + y * width);
        data[idx] = rgb(c.r, c.g, c.b);
        return true;
    }
    uint32_t at(int x, int y) {
        if (!data || x<0 || y<0 || x>=width || y>=height) {
            return 0;
        }

        int idx = int(x + y * width);
        return data[idx];
    }
    bool set(int x, int y, uint32_t c) {
        if (!data || x<0 || y<0 || x>=width || y>=height) {
            return false;
        }
        int idx = int(x + y * width);
        data[idx] = c;
        return true;
    }
    ~PixelBuffer() {
        if (managed) free(data);
    }
    int get_width() { return width; }
    int get_height() { return height; }
    uint32_t *buffer() { return data; }
    void clear(uint32_t c) {
        for (int i = 0; i < width * height; i++) {
            data[i] = c;
        }
    }
    // assumes buffers are the same size
    void load(IPixelBuffer& pixel_buffer) {
        for (int y = 0; y < pixel_buffer.get_height(); y++) {
            for (int x = 0; x < pixel_buffer.get_width(); x++) {
                set(x, y, pixel_buffer.get(x, y));
            }
        }
    }
};

void paint(IPixelBuffer& dest, IPixelBuffer& source) {
    for (int y = 0; y < dest.get_height(); y++) {
        for (int x =  0; x < dest.get_width(); x++) {
            dest.set(x, y, source.get(x, y));
        }
    }
}

bool window_callback(HWND window, UINT messageType, WPARAM param1, LPARAM param2) {
    // nothing is explicitly handled
    return false;
}

bool onUpdate(double dt_ms, unsigned long long fps) {

    // static TGAImage image("barycentric_test.tga");
    // static TGAImage image("res/african_head_diffuse.tga");
    // static TGAImage image("textured.tga");
    // static TGAImage image("wireframe.tga");
    // static TGAImage image("object.tga");
    // static TGAImage image("zbuffer.tga");
    // static TGAImage image("quad.tga");
    // static TGAImage image("test_bar.tga");
    
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
    
    PixelBuffer s(wc->width, wc->height, wc->pixels);

    /* clear the buffer */ {
        for (int y = 0; y < s.get_height(); y++) {
            for (int x =  0; x < s.get_width(); x++) {
                // s.set(x, y, TGAColor(255, 255, 255, 255));
                s.set(x, y, TGAColor(0, 0, 0, 255));
            }
        }
    }

    /* render to pixel buffer */ {
        
        static bool firstFrame = true;

        // Load the resources
        static Model model("res/african_head.obj");
        static TGAImage texture("res/african_head_diffuse.tga");

        if (firstFrame) {
            texture.flip_vertically();
        }

        // obj_to_tga_illuminated_zbuffer_textured(model, texture, s);
        // obj_to_tga_illuminated_zbuffer_textured_perspective(model, texture, s, Vec3f(0,0,1));
        obj_to_tga_illuminated_gouraud_zbuffer_textured_perspective(model, texture, s, Vec3f(0,0,1));

        if (firstFrame) {
            // We want to keep the output of the render in a TGA file, but only needs to happen once
            TGAImage output(render_width, render_height, TGAImage::RGB);
            // copy the pixel buffer to my output image file
            paint(output, s);
            output.flip_vertically();
            output.write_tga_file(render_name);
        }

        firstFrame = false;
    }

    /* stats and debugging stuff */ {
    
        // Some kind of performance visualizer
        TGAColor performance_color = TGAColor(255, 0, 0, 255);
        float performance_base = 128.0f;
        if (dt_ms < 64.0f) { performance_base = 64.0f; performance_color = TGAColor(255, 150, 0, 255); }
        if (dt_ms < 32.0f) { performance_base = 32.0f; performance_color = TGAColor(240, 204, 0, 255); }
        if (dt_ms < 16.0f) { performance_base = 16.0f; performance_color = TGAColor(174, 255, 0, 255); }
        line(Vec2i(0,0), Vec2i( min((dt_ms / performance_base) * s.get_width(), s.get_width()), 0), s, performance_color);
        line(Vec2i(0,1), Vec2i( min((dt_ms / performance_base) * s.get_width(), s.get_width()), 1), s, performance_color);

        // mouse pos
        POINT mouse;
        GetCursorPos(&mouse);
        fat_dot(Vec2i(mouse.x, mouse.y), s, TGAColor(255, 0, 0, 255));
        
        static short cursorx, cursory;
        if (win32::ConsoleGetCursorPosition(&cursorx, &cursory)) {
            win32::FormattedPrint("fps %d, ms %f", fps, dt_ms);
            win32::ConsoleSetCursorPosition(cursorx, cursory);
        }
    }

    return true;
}

DWORD WINAPI backgroundTask(LPVOID lpParam) {
    // do something
    return 0;
}

int main(int argc, char** argv) {
    srand(time(NULL));
    
    /* old render to TGAImage methods */
    if (false) {
        test_barycentric("barycentric_test.tga");
        test_textured_object("textured.tga");
        test_wireframe("wireframe.tga");
        test_object("object.tga");
        test_zbuffer_object("zbuffer.tga");
        test_textured_quad("quad.tga");
        test_barycentric_2("test_bar.tga");
    }

    void* someData = NULL;
    HANDLE handle = 0;
    handle = CreateThread(NULL, 0, backgroundTask, someData, 0, NULL);
    if (!handle) return 1;
    defer _1([handle]() {
        WaitForSingleObject(handle, INFINITE);
        CloseHandle(handle);
    });

    /* window scope */ {
        auto window = win32::NewWindow("myWindow", "tinyrenderer", 100, 100, 10, 10, &window_callback);
        defer _2([window]() { win32::CleanWindow("myWindow", window); });

        //int w, h, x, y;
        //win32::SetWindowClientSize(window, image.get_width(), image.get_height());
        //win32::GetWindowSizeAndPosition(window, &w, &h, &x, &y);

        bool haveConsole = true;
        if (win32::ConsoleAttach() != win32::ConsoleAttachResult::SUCCESS) {
            haveConsole = false;
            if (win32::ConsoleCreate() == win32::ConsoleCreateResult::SUCCESS) {
                auto consoleWindow = win32::ConsoleGetWindow();
                //win32::SetWindowPosition(consoleWindow, x+w, y);
                haveConsole = true;
            }
        }
        defer _3([haveConsole]() { if (haveConsole) win32::ConsoleFree(); });

        win32::NewWindowLoopStart(window, onUpdate);
        
        win32::CleanWindowRenderTarget();
    }
}
