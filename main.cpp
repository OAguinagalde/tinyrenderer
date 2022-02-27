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

void line(TGAImage &image, TGAColor color, int x0, int y0, int x1, int y1) {
    for (float t = 0; t < 1.0f; t += 0.1f) {
        int x = x0 + (x1-x0) * t;
        int y = y0 + (y1-y0) * t;
        image.set(x, y, color);
    }
}


const TGAColor white = TGAColor(255, 255, 255, 255);
const TGAColor red   = TGAColor(255, 0,   0,   255);

int main(int argc, char** argv) {
    TGAImage image(100, 100, TGAImage::RGB);
    line(image, white, 1,1, 90,90);
    image.flip_vertically(); // i want to have the origin at the left bottom corner of the image
    image.write_tga_file("output.tga");
    return 0;
}

