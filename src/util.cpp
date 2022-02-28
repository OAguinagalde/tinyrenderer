#include "util.h"

int absolute(int value) {
    if (value < 0) {
        return -value;
    }
    return value;
}

int maximum(int a, int b) {
    return a > b ? a : b;
}

void swap(int& a, int& b) {
    int c = a;
    a = b;
    b = c;
}

std::chrono::steady_clock::time_point measure_time() {
    return std::chrono::high_resolution_clock::now();
}

void measure_since(std::chrono::steady_clock::time_point start) {
    auto stop = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(stop - start);
    long long ns = duration.count();
    printf("Measured %lldns\n", ns);
}
