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
    
    triangle_outline(t0, t1, t2, image, white);
    fat_dot(top->x, top->y, image, green);
    fat_dot(mid->x, mid->y, image, blue);
    fat_dot(bot->x, bot->y, image, red);
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

    image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    image.write_tga_file(outputTgaFileName);
}

int main(int argc, char** argv) {
    TGAImage image(200, 200, TGAImage::RGB);

    Vec2i t0[3] = { Vec2i(10, 70),   Vec2i(50, 160),  Vec2i(70, 80) };
    triangle(t0[0], t0[1], t0[2], image, whiteTransparent);
    Vec2i t1[3] = { Vec2i(180, 50),  Vec2i(150, 1),   Vec2i(70, 180) };
    triangle(t1[0], t1[1], t1[2], image, whiteTransparent);
    Vec2i t2[3] = { Vec2i(180, 150), Vec2i(120, 160), Vec2i(130, 180) };
    triangle(t2[0], t2[1], t2[2], image, whiteTransparent);
    Vec2i t4[3] = { Vec2i(100, 190),   Vec2i(110, 150),  Vec2i(170, 100) };
    triangle(t4[0], t4[1], t4[2], image, whiteTransparent);
    Vec2i t5[3] = { Vec2i(50, 70),   Vec2i(20, 40),  Vec2i(40, 10) };
    triangle(t5[0], t5[1], t5[2], image, whiteTransparent);
    Vec2i t6[3] = { Vec2i(90, 100),   Vec2i(80, 70),  Vec2i(30, 20) };
    triangle(t6[0], t6[1], t6[2], image, whiteTransparent);

    image.flip_vertically(); // I want to have the origin at the left bot corner of the image
    image.write_tga_file("output.tga");
    return 0;
}

