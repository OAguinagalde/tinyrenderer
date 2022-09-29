#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>

#pragma comment(lib, "User32")
#pragma comment(lib, "gdi32")
#pragma comment(lib, "Msimg32")

namespace win32 {
    
    // 
    // ** Console stuff **
    // 
    
    enum class ConsoleAttachResult {
        // success
        SUCCESS,
        // Use FreeConsole() to detach from any console
        ALREADY_ATTACHED,
        // Parent process has no console attached to it so there is nothing to attach to
        NO_CONSOLE_TO_ATTACH
    };
    
    // Get the handles to this console with GetStdHandle(STD_INPUT_HANDLE/STD_OUTPUT_HANDLE/STD_ERROR_HANDLE)
    ConsoleAttachResult ConsoleAttach();
    
    enum class ConsoleCreateResult {
        SUCCESS,
        // Use FreeConsole() to detach from any console
        ALREADY_ATTACHED
    };

    // Get the handles to this console with GetStdHandle(STD_INPUT_HANDLE/STD_OUTPUT_HANDLE/STD_ERROR_HANDLE)
    ConsoleCreateResult ConsoleCreate();

    // clears the console associated with the stdout
    void ConsoleClear();

    bool ConsoleGetCursorPosition(short *x, short *y);

    // The handle must have the GENERIC_READ access right
    bool ConsoleSetCursorPosition(short x, short y);

    HWND ConsoleGetWindow();
    
    bool ConsoleFree();

    
    // 
    // ** Window stuff **
    // 

    // return true if you handle a message, else return false and the internal code will handle it
    typedef bool windowsCallback(HWND window, UINT messageType, WPARAM param1, LPARAM param2);

    // Warning: Probably its a bad idea to call this more than once lol
    // Warning: Uses GetModuleHandleA(NULL) as the hInstance, so might not work if used as a DLL
    HWND NewWindow(const char* identifier, const char* windowTitle, int x, int y, int w, int h, windowsCallback* callback);

    // Use the same identifier used on NewWindow
    bool CleanWindow(const char* identifier, HWND window);

    // Sets the client size (not the window size!)
    void SetWindowClientSize(HWND window, int width, int height);

    // Given a windowHandle, queries the width, height and position (x, y) of the window
    void GetWindowSizeAndPosition(HWND windowHandle, int* width, int* height, int* x, int* y);

    // Given a windowHandle, queries the width and height of the client size (The drawable area)
    void GetClientSize(HWND windowHandle, int* width, int* height);

    void SetWindowPosition(HWND window, int x, int y);

    HDC GetDeviceContextHandle(HWND windowHandle);

    void SwapPixelBuffers(HDC deviceContextHandle);

    // Everytime this is called it resets the render target
    // 0,0 is top left and w,h is bottom right
    uint32_t* NewWindowRenderTarget(int w, int h);

    void CleanWindowRenderTarget(uint32_t* buffer);

    // if returns false, loop will end
    typedef bool OnUpdate(double dt_ms, unsigned long long fps);

    // enters a blocking loop in which keeps on reading and dispatching the windows messages, until the running flag is set to false
    void NewWindowLoopStart(HWND window, OnUpdate* onUpdate);


    // 
    // ** windows timers and stuff **
    // 

    // usage example:
    // 
    //     unsigned long long cpuFrequencySeconds, cpuCounter, fps;
    //     double ms;
    //     win32::GetCpuCounterAndFrequencySeconds(&cpuCounter, &cpuFrequencySeconds);
    //     while (true) {
    //         // input
    //         // update
    //         // render
    //         cpuCounter = win32::GetTimeDifferenceMsAndFPS(cpuCounter, cpuFrequencySeconds, &ms, &fps);
    //         win32::FormattedPrint("ms %f\n", ms);
    //     }
    // 
    void GetCpuCounterAndFrequencySeconds(unsigned long long* cpuCounter, unsigned long long* cpuFrequencySeconds);

    // Given the previous cpu counter to compare with, and the cpu frequency (Use GetCpuCounterAndFrequencySeconds)
    // Calculate timeDifferenceMs and fps. Returns the current value of cpuCounter.
    // returns a newly calculated cpu counter.
    unsigned long long GetTimeDifferenceMsAndFPS(unsigned long long cpuPreviousCounter, unsigned long long cpuFrequencySeconds, double* timeDifferenceMs, unsigned long long* fps);


    // 
    // ** `printf`-like methods using msvc stuff **
    // 
    
    // Prints a string to stdout
    void Print(const char* str);

    // printf but wrong lol
    // Max output is 1024 bytes long!
    void FormattedPrint(const char* format, ...);

    // Given a char buffer, and a format str, puts the resulting str in the buffer
    void FormatBuffer(char* buffer, const char* format, ...);
}