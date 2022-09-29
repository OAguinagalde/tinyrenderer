#pragma once
#include <chrono>
#include <functional>

int absolute(int value);
void swap(int& a, int& b);
std::chrono::steady_clock::time_point measure_time();
void measure_since(std::chrono::steady_clock::time_point start);

#define MAX(a,b) ((a) > (b) ? (a) : (b))
#define MIN(a,b) ((a) < (b) ? (a) : (b))

// usage example:
// 
//     defer  ([](){ printf("Dont use unnamed deffer instances! this will run straight away! Bad!");
//     defer d([](){ printf("Hello from the end of the scope!"); });
// 
class defer {
    std::function<void()> deferred_action;
public:
    defer(std::function<void()> f) : deferred_action(f) {}
    ~defer() {
        deferred_action();
    }
    defer& operator=(const defer&) = delete;
    defer(const defer&) = delete;
};

