#include "tgaimage.h"
#include <chrono>

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
    auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(stop - start);
    long long ns = duration.count();
    printf("Measured %lldns\n", ns);
}

const TGAColor white = TGAColor(255, 255, 255, 255);
const TGAColor red = TGAColor(255, 0, 0, 255);
const TGAColor green = TGAColor(0, 255, 0, 255);
const TGAColor blue = TGAColor(0, 0, 255, 255);

// Copyed from the lesson to test performance, I win!!!
void line4th(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) { 
    auto start = std::chrono::high_resolution_clock::now();
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
    measure_since(start);
}

void line5th(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) { 
    auto start = std::chrono::high_resolution_clock::now();

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
    measure_since(start);
} 

void line5thImprovedIssue28(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) { 
    auto start = std::chrono::high_resolution_clock::now();

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
    measure_since(start);
} 

void line1(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) {
    auto start = std::chrono::high_resolution_clock::now();

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

    measure_since(start);
    image.set(x0, y0, green);
    image.set(x1, y1, blue);
}

int main(int argc, char** argv) {
    TGAImage image(100, 100, TGAImage::RGB);

    line4th(13, 20, 80, 40, image, white); 
    line4th(20, 13, 40, 80, image, red); 
    line4th(80, 40, 13, 20, image, red);

    line5th(13, 20, 80, 40, image, white); 
    line5th(20, 13, 40, 80, image, red); 
    line5th(80, 40, 13, 20, image, red);

    line5thImprovedIssue28(13, 20, 80, 40, image, white); 
    line5thImprovedIssue28(20, 13, 40, 80, image, red); 
    line5thImprovedIssue28(80, 40, 13, 20, image, red);
    
    line1(13, 20, 80, 40, image, white); 
    line1(20, 13, 40, 80, image, red); 
    line1(80, 40, 13, 20, image, red);
    
    image.flip_vertically(); // i want to have the origin at the left bottom corner of the image
    image.write_tga_file("output.tga");
    return 0;
}

