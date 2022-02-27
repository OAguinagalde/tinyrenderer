#include "tgaimage.h"
#include <chrono>
#include <vector>
#include <cmath>

#include "model.h"
#include "geometry.h"

int absolute(int value) {
    if (value < 0) {
        return -value;
    }
    return value;
}

int maximum(int a, int b) {
    return a > b ? a : b;
}

void swap(int &a, int &b) {
    int c = a;
    a = b;
    b = c;
}

// Usage:
// auto start = std::chrono::high_resolution_clock::now();
// measure_since(start);
void measure_since(std::chrono::steady_clock::time_point start) {
    auto stop = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(stop - start);
    long long ns = duration.count();
    printf("Measured %lldns\n", ns);
}

const TGAColor white = TGAColor(255, 255, 255, 255);
const TGAColor red = TGAColor(255, 0, 0, 255);
const TGAColor green = TGAColor(0, 255, 0, 255);
const TGAColor blue = TGAColor(0, 0, 255, 255);

// Copyed from the lesson to test performance, I win!!!
void line4th(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) { 
    bool steep = false; 
    if (std::abs(x0-x1)<std::abs(y0-y1)) { 
        std::swap(x0, y0); 
        std::swap(x1, y1); 
        steep = true; 
    } 
    if (x0>x1) { 
        std::swap(x0, x1); 
        std::swap(y0, y1); 
    } 
    int dx = x1-x0; 
    int dy = y1-y0; 
    float derror = std::abs(dy/float(dx)); 
    float error = 0; 
    int y = y0; 
    for (int x=x0; x<=x1; x++) { 
        if (steep) { 
            image.set(y, x, color); 
        } else { 
            image.set(x, y, color); 
        } 
        error += derror; 
        if (error>.5) { 
            y += (y1>y0?1:-1); 
            error -= 1.; 
        } 
    } 
}

void line5th(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) { 
    bool steep = false; 
    if (std::abs(x0-x1)<std::abs(y0-y1)) { 
        std::swap(x0, y0); 
        std::swap(x1, y1); 
        steep = true; 
    } 
    if (x0>x1) { 
        std::swap(x0, x1); 
        std::swap(y0, y1); 
    } 
    int dx = x1-x0; 
    int dy = y1-y0; 
    int derror2 = std::abs(dy)*2; 
    int error2 = 0; 
    int y = y0; 
    for (int x=x0; x<=x1; x++) { 
        if (steep) { 
            image.set(y, x, color); 
        } else { 
            image.set(x, y, color); 
        } 
        error2 += derror2; 
        if (error2 > dx) { 
            y += (y1>y0?1:-1); 
            error2 -= dx*2; 
        } 
    }
} 

void line5thImprovedIssue28(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) { 
    bool steep = false; 
    if (std::abs(x0-x1)<std::abs(y0-y1)) { 
        std::swap(x0, y0); 
        std::swap(x1, y1); 
        steep = true; 
    } 
    if (x0>x1) { 
        std::swap(x0, x1); 
        std::swap(y0, y1); 
    } 
    int dx = x1-x0; 
    int dy = y1-y0; 
    int derror2 = std::abs(dy)*2; 
    int error2 = 0; 
    int y = y0;
    const int yincr = (y1>y0? 1 : -1);
    if(steep) {
        for(int x = x0; x<=x1; ++x) {
            image.set(y, x, color);
            error2 += derror2;
            if(error2 > dx) {
                y += (y1>y0? 1 : -1);
                error2 -= dx*2;
            }
        }
    } else {
        for(int x = x0; x<=x1; ++x) {
            image.set(x, y, color);
            error2 += derror2;
            if(error2 > dx) {
                y += yincr;
                error2 -= dx*2;
            }
        }
    }
} 

void line1(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) {
    int differenceX = x1-x0;
    int differenceXAbs = absolute(differenceX);

    int differenceY = y1-y0;
    int differenceYAbs = absolute(differenceY);

    if (differenceXAbs > differenceYAbs) {
        // draw horizontally
        
        if (differenceX < 0) {
            swap(x0, x1);
            swap(y0, y1);
        }

        double percentageOfLineDone = 0.0;
        double increment = 1.0 / (double) differenceXAbs;
        for (int x = x0; x <= x1; x++) {
            int y = y0 + (y1-y0) * percentageOfLineDone;
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
        double increment = 1.0 / (double) differenceYAbs;
        for (int y = y0; y <= y1; y++) {
            int x = x0 + (x1-x0) * percentageOfLineDone;
            image.set(x, y, color);
            percentageOfLineDone += increment;
        }
    }
}

int main(int argc, char** argv) {
    Model *model = NULL;
    const int width  = 800;
    const int height = 800;
    model = new Model("african_head.obj");

    TGAImage image(width, height, TGAImage::RGB);
    auto start = std::chrono::high_resolution_clock::now();
    for (int i=0; i<model->nfaces(); i++) {
        std::vector<int> face = model->face(i);
        for (int j=0; j<3; j++) {
            Vec3f v0 = model->vert(face[j]);
            Vec3f v1 = model->vert(face[(j+1)%3]);
            int x0 = (v0.x+1.)*width/2.;
            int y0 = (v0.y+1.)*height/2.;
            int x1 = (v1.x+1.)*width/2.;
            int y1 = (v1.y+1.)*height/2.;
            // line4th(x0, y0, x1, y1, image, white);
            // line5th(x0, y0, x1, y1, image, white); // 2800 - 1400
            // line5thImprovedIssue28(x0, y0, x1, y1, image, white);  //2700 - 1400
            line1(x0, y0, x1, y1, image, white); // 2700 - 1200
        }
    }
    measure_since(start);
    delete model;
    
    image.flip_vertically(); // i want to have the origin at the left bottom corner of the image
    image.write_tga_file("output.tga");
    return 0;
}

