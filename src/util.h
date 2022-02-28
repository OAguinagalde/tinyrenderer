#pragma once
#include <chrono>

int absolute(int value);
int maximum(int a, int b);
void swap(int& a, int& b);
std::chrono::steady_clock::time_point measure_time();
void measure_since(std::chrono::steady_clock::time_point start);
