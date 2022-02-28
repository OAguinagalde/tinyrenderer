#include "tgaimage.h"
#include <vector>
#include <cmath>

#include "model.h"
#include "geometry.h"
#include "util.h"

const TGAColor white = TGAColor(255, 255, 255, 255);
const TGAColor red = TGAColor(255, 0, 0, 255);
const TGAColor green = TGAColor(0, 255, 0, 255);
const TGAColor blue = TGAColor(0, 0, 255, 255);

//
// Line sources for comparison, mine is best however >:D
//
void line4th(int x0, int y0, int x1, int y1, TGAImage& image, TGAColor color)
{
    bool steep = false;
    if (std::abs(x0 - x1) < std::abs(y0 - y1))
    {
        std::swap(x0, y0);
        std::swap(x1, y1);
        steep = true;
    }
    if (x0 > x1)
    {
        std::swap(x0, x1);
        std::swap(y0, y1);
    }
    int dx = x1 - x0;
    int dy = y1 - y0;
    float derror = std::abs(dy / float(dx));
    float error = 0;
    int y = y0;
    for (int x = x0; x <= x1; x++)
    {
        if (steep)
        {
            image.set(y, x, color);
        }
        else
        {
            image.set(x, y, color);
        }
        error += derror;
        if (error > .5)
        {
            y += (y1 > y0 ? 1 : -1);
            error -= 1.;
        }
    }
}

void line5th(int x0, int y0, int x1, int y1, TGAImage& image, TGAColor color)
{
    bool steep = false;
    if (std::abs(x0 - x1) < std::abs(y0 - y1))
    {
        std::swap(x0, y0);
        std::swap(x1, y1);
        steep = true;
    }
    if (x0 > x1)
    {
        std::swap(x0, x1);
        std::swap(y0, y1);
    }
    int dx = x1 - x0;
    int dy = y1 - y0;
    int derror2 = std::abs(dy) * 2;
    int error2 = 0;
    int y = y0;
    for (int x = x0; x <= x1; x++)
    {
        if (steep)
        {
            image.set(y, x, color);
        }
        else
        {
            image.set(x, y, color);
        }
        error2 += derror2;
        if (error2 > dx)
        {
            y += (y1 > y0 ? 1 : -1);
            error2 -= dx * 2;
        }
    }
}

void line5thImprovedIssue28(int x0, int y0, int x1, int y1, TGAImage& image, TGAColor color)
{
    bool steep = false;
    if (std::abs(x0 - x1) < std::abs(y0 - y1))
    {
        std::swap(x0, y0);
        std::swap(x1, y1);
        steep = true;
    }
    if (x0 > x1)
    {
        std::swap(x0, x1);
        std::swap(y0, y1);
    }
    int dx = x1 - x0;
    int dy = y1 - y0;
    int derror2 = std::abs(dy) * 2;
    int error2 = 0;
    int y = y0;
    const int yincr = (y1 > y0 ? 1 : -1);
    if (steep)
    {
        for (int x = x0; x <= x1; ++x)
        {
            image.set(y, x, color);
            error2 += derror2;
            if (error2 > dx)
            {
                y += (y1 > y0 ? 1 : -1);
                error2 -= dx * 2;
            }
        }
    }
    else
    {
        for (int x = x0; x <= x1; ++x)
        {
            image.set(x, y, color);
            error2 += derror2;
            if (error2 > dx)
            {
                y += yincr;
                error2 -= dx * 2;
            }
        }
    }
}

//
// My line!
//
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

        double percentageOfLineDone = 0.0;
        double increment = 1.0 / (double)differenceXAbs;
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

        double percentageOfLineDone = 0.0;
        double increment = 1.0 / (double)differenceYAbs;
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

void triangle(Vec2i t0, Vec2i t1, Vec2i t2, TGAImage& image, const TGAColor& color) {
    triangle_outline(t0, t1, t2, image, white);
    // 1. find the highest vertex and the lowest vertex
    // 2. calculate dy between them
    // 3. loop though each "horizontal line" between them
    //     1. get the x position in the current height for both the left and right line
    //     2. draw a line now that we know both the x and the y of both extremes

    // 1. find the highest vertex and the lowest vertex
    Vec2i* top;
    Vec2i* mid;
    Vec2i* bottom;
    if (t0.y > t1.y) {
        if (t0.y > t2.y) {
            top = &t0;
            if (t1.y > t2.y) {
                mid = &t1;
                bottom = &t2;
            }
            else {
                mid = &t2;
                bottom = &t1;
            }
        }
        else {
            top = &t2;
            mid = &t0;
            bottom = &t1;
        }
    }
    else {
        if (t1.y > t2.y) {
            top = &t1;
            if (t0.y > t2.y) {
                mid = &t0;
                bottom = &t2;
            }
            else {
                mid = &t2;
                bottom = &t1;
            }
        }
        else {
            top = &t2;
            mid = &t1;
            bottom = &t0;
        }
    }
    image.set(top->x, top->y, green);
    image.set(mid->x, mid->y, blue);
    image.set(bottom->x, bottom->y, red);
    // 2. calculate dy between them
    // 3. loop though each "horizontal line" between them
    //     1. get the x position in the current height for both the left and right line
    //     2. draw a line now that we know both the x and the y of both extremes


}

void lesson1_obj_to_tga(const char* inputObjModelFileName, const int width, const int height, const char* outputTgaFileName) {
    Model* model = NULL;
    model = new Model(inputObjModelFileName);


    TGAImage image(width, height, TGAImage::RGB);
    auto start = measure_time();
    for (int i = 0; i < model->nfaces(); i++) {
        std::vector<int> face = model->face(i);

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

    image.flip_vertically(); // I want to have the origin at the left bottom corner of the image
    image.write_tga_file(outputTgaFileName);
}

int main(int argc, char** argv) {
    TGAImage image(200, 200, TGAImage::RGB);

    Vec2i t0[3] = { Vec2i(10, 70),   Vec2i(50, 160),  Vec2i(70, 80) };
    Vec2i t1[3] = { Vec2i(180, 50),  Vec2i(150, 1),   Vec2i(70, 180) };
    Vec2i t2[3] = { Vec2i(180, 150), Vec2i(120, 160), Vec2i(130, 180) };
    triangle(t0[0], t0[1], t0[2], image, red);
    triangle(t1[0], t1[1], t1[2], image, white);
    triangle(t2[0], t2[1], t2[2], image, green);

    image.flip_vertically(); // I want to have the origin at the left bottom corner of the image
    image.write_tga_file("output.tga");
    return 0;
}

