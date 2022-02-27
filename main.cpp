#include "tgaimage.h"

/*
# First attempt

The goal of the first lesson is to render the wire mesh. To do this, we should learn how to draw line segments.
We can simply read what Bresenham’s line algorithm is, but let’s write code ourselves. How does the simplest code
that draws a line segment between (x0, y0) and (x1, y1) points look like? Apparently, something like this:

void line(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) { 
    for (float t=0.; t<1.; t+=.01) { 
        int x = x0 + (x1-x0)*t; 
        int y = y0 + (y1-y0)*t; 
        image.set(x, y, color); 
    } 
}
*/

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

const TGAColor white = TGAColor(255, 255, 255, 255);
const TGAColor red = TGAColor(255, 0, 0, 255);
const TGAColor green = TGAColor(0, 255, 0, 255);
const TGAColor blue = TGAColor(0, 0, 255, 255);

void line(int x0, int y0, int x1, int y1, TGAImage &image, TGAColor color) {
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
        for (int pixel = x0; pixel != x1; ) {
            int x = pixel;
            int y = y0 + (y1-y0) * percentageOfLineDone;
            image.set(x, y, color);
            percentageOfLineDone += increment;
            pixel++;
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
        for (int pixel = y0; pixel != y1; ) {
            int x = x0 + (x1-x0) * percentageOfLineDone;
            int y = pixel;
            image.set(x, y, color);
            percentageOfLineDone += increment;
            pixel++;
        }
    }

    image.set(x0, y0, green);
    image.set(x1, y1, blue);
}

int main(int argc, char** argv) {
    TGAImage image(100, 100, TGAImage::RGB);
    line(13, 20, 80, 40, image, white); 
    line(20, 13, 40, 80, image, red); 
    line(80, 40, 13, 20, image, red);
    image.flip_vertically(); // i want to have the origin at the left bottom corner of the image
    image.write_tga_file("output.tga");
    return 0;
}

