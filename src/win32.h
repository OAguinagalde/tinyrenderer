#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <strsafe.h>
#include <cassert>
#include <cstdlib>

#pragma comment(lib, "User32")
#pragma comment(lib, "gdi32")

// clears the console associated with the stdout
void ClearConsole();

// Prints a string to stdout
void Print(const char* str);

// printf but wrong lol
// Max output is 1024 bytes long!
void FormattedPrint(const char* format, ...);

// Given a char buffer, and a format str, puts the resulting str in the buffer
void FormatBuffer(char* buffer, const char* format, ...);

// Given a windowHandle, queries the width, height and position (x, y) of the window
void GetWindowSizeAndPosition(HWND windowHandle, int* width, int* height, int* x, int* y);

// Given a windowHandle, queries the width and height of the client size (The drawable area)
void GetClientSize(HWND windowHandle, int* width, int* height);

// Try to get a console, for situations where there might not be one
// Return true when an external consolle (new window) has been allocated
bool GetConsole();

WNDCLASSA MakeWindowClass(const char* windowClassName, WNDPROC pfnWindowProc, HINSTANCE hInstance);

HWND MakeWindow(const char* windowClassName, const char* title, HINSTANCE hInstance, int nCmdShow);

void MoveAWindow(HWND windowHandle, int x, int y, int w, int h);

void AllocateOnWindowsStuff();

// unsigned long long cpuFrequencySeconds;
// unsigned long long cpuCounter;
// GetCpuCounterAndFrequencySeconds(&cpuCounter, &cpuFrequencySeconds);
void GetCpuCounterAndFrequencySeconds(unsigned long long* cpuCounter, unsigned long long* cpuFrequencySeconds);

// Given the previous cpu counter to compare with, and the cpu frequency (Use GetCpuCounterAndFrequencySeconds)
// Calculate timeDifferenceMs and fps. Returns the current value of cpuCounter.
unsigned long long GetTimeDifferenceMsAndFPS(unsigned long long cpuPreviousCounter, unsigned long long cpuFrequencySeconds, double* timeDifferenceMs, unsigned long long* fps);

bool GetConsoleCursorPosition(short *cursorX, short *cursorY);

// The handle must have the GENERIC_READ access right
bool SetConsoleCursorPosition(short posX, short posY);

// This is not a function, it's just a reference for me for when I want to do a message loop and I dont remember...
void LoopWindowsMessages();

HDC GetDeviceContextHandle(HWND windowHandle);

void SwapPixelBuffers(HDC deviceContextHandle);
