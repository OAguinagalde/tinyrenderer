#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <strsafe.h>
#include <cassert>
#include <cstdlib>

#pragma comment(lib, "User32")
#pragma comment(lib, "gdi32")

// clears the console associated with the stdout
void ClearConsole() {
    HANDLE consoleStdOut = GetStdHandle(STD_OUTPUT_HANDLE);
    // First we have to activate the virtual terminal processing for this to work
    // We might want to keep the original mode to restore it if necessary. For example when using with other command lines utilities...
    DWORD mode = 0;
    DWORD originalMode = 0;
    GetConsoleMode(consoleStdOut, &mode);
    originalMode = mode;
    mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    SetConsoleMode(consoleStdOut, mode);
    // 2J only clears the visible window and 3J only clears the scroll back.
    PCWSTR clearConsoleSequence = L"\x1b[2J";
    WriteConsoleW(consoleStdOut, clearConsoleSequence, sizeof(clearConsoleSequence)/sizeof((clearConsoleSequence)[0]), NULL, NULL);
    // Restore original mode
    SetConsoleMode(consoleStdOut, originalMode);
}

// Prints a string to stdout
void Print(const char* str) {
    WriteConsoleA(GetStdHandle(STD_OUTPUT_HANDLE), (const void*) str, lstrlenA(LPCSTR(str)), NULL, NULL);
}

// printf but wrong lol
// Max output is 1024 bytes long!
void FormattedPrint(const char* format, ...) {
    static const size_t buffer_size = 1024;
    static char buffer[buffer_size];
    va_list args;
    va_start(args, format);
    // https://docs.microsoft.com/en-us/windows/win32/menurc/strsafe-ovw
    // https://docs.microsoft.com/en-us/windows/win32/api/strsafe/nf-strsafe-stringcbvprintfa
    StringCbVPrintfA(buffer, buffer_size, format, args);
    va_end(args);
    Print(buffer);
}

// Given a char buffer, and a format str, puts the resulting str in the buffer
void FormatBuffer(char* buffer, const char* format, ...) {
    va_list args;
    va_start(args, format);
    wvsprintfA(LPSTR(buffer), LPCSTR(format), args);
    va_end(args);
}

// Given a windowHandle, queries the width, height and position (x, y) of the window
void GetWindowSizeAndPosition(HWND windowHandle, int* width, int* height, int* x, int* y) {
    RECT rect;
    GetWindowRect(windowHandle, &rect);
    *x = rect.left;
    *y = rect.top;
    *width = rect.right - rect.left;
    *height = rect.bottom - rect.top;
}

// Given a windowHandle, queries the width and height of the client size (The drawable area)
void GetClientSize(HWND windowHandle, int* width, int* height) {
    RECT rect;
    // This just gives us the "drawable" part of the window
    GetClientRect(windowHandle, &rect);
    *width = rect.right - rect.left;
    *height = rect.bottom - rect.top;
}

// Try to get a console, for situations where there might not be one
// Return true when an external consolle (new window) has been allocated
bool GetConsole() {
    bool consoleFound = false;
    bool consoleIsExternal = false;
    if (AttachConsole(ATTACH_PARENT_PROCESS)) {
        // Situation example:
        // Opening a Windows Subsystem process from a cmd.exe process. It the process will attach to cmd.exe's console
        consoleFound = true;
        Print("Console hijacked!\n");
    }
    else {
        DWORD error = GetLastError();
        switch (error) {
            // If the calling process is already attached to a console, the error code returned is ERROR_ACCESS_DENIED.
            case ERROR_ACCESS_DENIED: {
                // Already attached to a console so that's it
                consoleFound = true;
            } break;
            // If the specified process does not have a console, the error code returned is ERROR_INVALID_HANDLE.
            case ERROR_INVALID_HANDLE: {
                
            } break;
            // If the specified process does not exist, the error code returned is ERROR_INVALID_PARAMETER. 
            case ERROR_INVALID_PARAMETER: {
                FormattedPrint("Unreachable at %s, %s\n", __FUNCTIONW__, __FILE__);
            } break;
        }

    }

    if (!consoleFound) {
        // If we still don't have a console then create a new one
        if (AllocConsole()) {
            // Creates a new console
            consoleFound = true;
            consoleIsExternal = true;
        }
        else {
            // AllocConsole function fails if the calling process already has a console
            FormattedPrint("Unreachable at %s, %s\n", __FUNCTIONW__, __FILE__);
        }
    }
    
    return consoleIsExternal;
}

// A very basic, default, WindowProc.
// This is a mess, and basically it just handles some quitting messages such as x and ESC
LRESULT CALLBACK BasicWindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    switch (uMsg)
    {
        // case WM_SIZE: {
        //     RECT win32_rect = (RECT) {0};
        //     // This just gives us the "drawable" part of the window
        //     win32_ GetClientRect(hwnd, &win32_rect);
        //     int width = win32_rect.right - win32_rect.left;
        //     int height = win32_rect.bottom - win32_rect.top;
        //     win32_printf("WIDTH: %d, height: %d\n", width, height);
            
        //     // UINT width = LOWORD(lParam);
        //     // UINT height = HIWORD(lParam);
        // } break;
        case WM_DESTROY: {
            // TODO: turn win32_running to false
            Print("WM_DESTROY\n");
        } // break;
        Print("and\n");
        case WM_CLOSE: {
            // TODO: turn win32_running to false
            Print("WM_CLOSE\n");
            // Basically makes the application post a WM_QUIT message
            // win32_ DestroyWindow(hwnd); // This only closes the main window
            PostQuitMessage(0); // This sends the quit message which the main loop will read and end the loop
            return 0;
        } break;
        // case WM_PAINT: {
        //     win32_print("WM_PAINT\n");
        // } break;
        case WM_SYSKEYDOWN:
        case WM_KEYDOWN: {
            if (wParam == VK_ESCAPE) {
                // TODO: There is too many points where I want to quite the application... Which one does what?
                PostQuitMessage(0);
            }
            return 0;
        } break;
    }
    // Events that I'm consciously not capturing:
    // . WM_SETCURSOR Sent to a window if the mouse causes the cursor to move within a window and mouse input is not captured
    return DefWindowProc(hwnd, uMsg, wParam, lParam);
}

WNDCLASSA MakeWindowClass(const char* windowClassName, WNDPROC pfnWindowProc, HINSTANCE hInstance) {
    WNDCLASSA windowClass = {};
    windowClass.lpfnWndProc = pfnWindowProc;
    windowClass.hInstance = hInstance;
    windowClass.lpszClassName = LPCSTR(windowClassName);
    windowClass.hCursor = LoadCursor(NULL, IDC_ARROW);
    RegisterClassA(&windowClass);
    return windowClass;
}

HWND MakeWindow(const char* windowClassName, const char* title, HINSTANCE hInstance, int nCmdShow) {
    int windowPositionX = 100;
    int windowPositionY = 100;
    int windowWidth = 0;
    int windowHeight = 0;
    int clientWidth = 0;
    int clientHeight = 0;
    // The size for the window will be the whole window and not the drawing area, so we will have to adjust it later on and it doesn't matter much here
    HWND windowHandle = CreateWindowExA(0, LPCSTR(windowClassName), LPCSTR(title), WS_POPUP | WS_OVERLAPPED | WS_THICKFRAME | WS_CAPTION | WS_SYSMENU  | WS_MINIMIZEBOX | WS_MAXIMIZEBOX,
        windowPositionX, windowPositionY, 10, 10,
        NULL, NULL, hInstance, NULL
    );
    Print("Window created\n");
    GetWindowSizeAndPosition(windowHandle,&windowWidth,&windowHeight,&windowPositionX,&windowPositionY);
    
    // let's figure out the real size of the client area (drawable part of window) and adjust it
    int desiredClientWidth = 500;
    int desiredClientHeight = 600;
    // Get client size
    GetClientSize(windowHandle, &clientWidth, &clientHeight);
    // Calculate difference between initial size of window and current size of drawable area, that should be the difference to make the window big enough to have our desired drawable area
    int difference_w = abs(clientWidth - desiredClientWidth);
    int difference_h = abs(clientHeight - desiredClientHeight);
    // Set the initially desired position and size now
    MoveWindow(windowHandle, windowPositionX, windowPositionY, windowWidth + difference_w, windowHeight + difference_h, 0);
    // It should have the right size about now
    Print("Window adjusted\n");
    GetWindowSizeAndPosition(windowHandle, &windowWidth, &windowHeight, &windowPositionX, &windowPositionY);
    GetClientSize(windowHandle, &clientWidth, &clientHeight);
    ShowWindow(windowHandle, nCmdShow);
    return windowHandle;
}

void MoveAWindow(HWND windowHandle, int x, int y, int w, int h) {
    // Moving the console doesn't redraw it, so parts of the window that were originally hidden won't be rendered.
    MoveWindow(windowHandle, x, y, w, h, 0);
    // So after moving the window, redraw it.
    // https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-redrawwindow
    // "If both the hrgnUpdate and lprcUpdate parameters are NULL, the entire client area is added to the update region."
    RedrawWindow(windowHandle, NULL, NULL, RDW_INVALIDATE);
}

void AllocateOnWindowsStuff() {
    // Heap allocation and free on win32...
    // unsigned char* data = NULL;
    // data = win32_ HeapAlloc(win32_ GetProcessHeap(), 0, sizeof(unsigned char)*texture_data_size);
    // win32_ memcpy(data, &texture_data[0], sizeof(unsigned char)*texture_data_size);
    // win32_ HeapFree(win32_ GetProcessHeap(), 0, (LPVOID) data);
}

// unsigned long long cpuFrequencySeconds;
// unsigned long long cpuCounter;
// GetCpuCounterAndFrequencySeconds(&cpuCounter, &cpuFrequencySeconds);
void GetCpuCounterAndFrequencySeconds(unsigned long long* cpuCounter, unsigned long long* cpuFrequencySeconds) {
    LARGE_INTEGER counter;
    QueryPerformanceCounter(&counter);
    // Internal Counter at this point
    *cpuCounter = counter.QuadPart;
    // The internal counter alone is not enough to know how much time has passed.
    // However, we can query the system for the performance of the cpu, which tells us how many cycles happen per second
    // and with that calculate the time.
    LARGE_INTEGER performanceFrequency;
    QueryPerformanceFrequency(&performanceFrequency);
    // Cycles per second
    *cpuFrequencySeconds = performanceFrequency.QuadPart;

    // TODO: There is some other ways of getting performance information such as __rdtsc()...
    // I should try it since (I think) might be more precise, since it is an intrinsic function from the compiler?
    // uint64 cyclecount = __rdtsc();
}

// Given the previous cpu counter to compare with, and the cpu frequency (Use GetCpuCounterAndFrequencySeconds)
// Calculate timeDifferenceMs and fps. Returns the current value of cpuCounter.
unsigned long long GetTimeDifferenceMsAndFPS(unsigned long long cpuPreviousCounter, unsigned long long cpuFrequencySeconds, double* timeDifferenceMs, unsigned long long* fps) {
    // Internal Counter at this point
    LARGE_INTEGER cpuCounter;
    QueryPerformanceCounter(&cpuCounter);
    // Difference since last update to this new update
    unsigned long long counterDifference = cpuCounter.QuadPart - cpuPreviousCounter;
    // Since we know the frequency we can calculate some times
    *timeDifferenceMs = 1000.0 * (double)counterDifference / (double)cpuFrequencySeconds;
    *fps = cpuFrequencySeconds / counterDifference;
    return cpuCounter.QuadPart;
}

bool GetConsoleCursorPosition(short *cursorX, short *cursorY) {
    CONSOLE_SCREEN_BUFFER_INFO cbsi;
    if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &cbsi)) {
        *cursorX = cbsi.dwCursorPosition.X;
        *cursorY = cbsi.dwCursorPosition.Y;
        return true;
    }
    else {
        return false;
    }
}
// The handle must have the GENERIC_READ access right
bool SetConsoleCursorPosition(short posX, short posY) {
    COORD position;
    position.X = posX;
    position.Y = posY;
    return SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), position);
}

// This is not a function, it's just a reference for me for when I want to do a message loop and I dont remember...
void LoopWindowsMessages() {
    // GetMessage blocks until a message is found.
    // Instead, PeekMessage can be used.
    MSG msg = {0};
    // Look if there is a message and if so remove it
    while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
        TranslateMessage(&msg); 
        DispatchMessage(&msg);

        switch (msg.message) {
            case WM_QUIT: {
            } break;
            case WM_SIZE: {
            } break;
        }
    }
}

HDC GetDeviceContextHandle(HWND windowHandle) {
    HDC hdc = GetDC(windowHandle);
    return hdc;
}

void SwapPixelBuffers(HDC deviceContextHandle) {
    // The SwapBuffers function exchanges the front and back buffers if the
    // current pixel format for the window referenced by the specified device context includes a back buffer.
    SwapBuffers(deviceContextHandle);
}
