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
void line(int x0, int y0, int x1, int y1, TGAImage& image, TGAColor color) {
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

void triangle(Vec2i t0, Vec2i t1, Vec2i t2, TGAImage& image, TGAColor color) {

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
            int x0 = (v0.x + 1.0f) * width  / 2.0f;
            int y0 = (v0.y + 1.0f) * height / 2.0f;
            int x1 = (v1.x + 1.0f) * width  / 2.0f;
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
    lesson1_obj_to_tga("res/african_head.obj", 800, 800, "output.tga");
    return 0;
}

