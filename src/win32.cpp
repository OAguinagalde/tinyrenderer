#include <strsafe.h>
#include "win32.h"

namespace win32 {

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

    WNDCLASSA MakeWindowClass(const char* windowClassName, WNDPROC pfnWindowProc, HINSTANCE hInstance) {
        WNDCLASSA windowClass = {};
        windowClass.lpfnWndProc = pfnWindowProc;
        windowClass.hInstance = hInstance;
        windowClass.lpszClassName = LPCSTR(windowClassName);
        windowClass.hCursor = LoadCursor(NULL, IDC_ARROW);
        RegisterClassA(&windowClass);
        return windowClass;
    }

    // hInstance may be null if you dont know or care what it is
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
        int difference_w = clientWidth - desiredClientWidth;
        if (difference_w < 0) difference_w *= -1;
        int difference_h = clientHeight - desiredClientHeight;
        if (difference_h < 0) difference_h *= -1;
        // Set the initially desired position and size now
        MoveWindow(windowHandle, windowPositionX, windowPositionY, windowWidth + difference_w, windowHeight + difference_h, 0);
        // It should have the right size about now
        Print("Window adjusted\n");
        GetWindowSizeAndPosition(windowHandle, &windowWidth, &windowHeight, &windowPositionX, &windowPositionY);
        GetClientSize(windowHandle, &clientWidth, &clientHeight);
        ShowWindow(windowHandle, nCmdShow);
        return windowHandle;
    }

    // return true if you handle a message, else return false and the internal code will handle it
    typedef bool windowsCallback(HWND window, UINT messageType, WPARAM param1, LPARAM param2);
    typedef bool windowsCallback(HWND window, UINT messageType, WPARAM param1, LPARAM param2);
    
    static BITMAPINFO render_target;
    static void* pixel_buffer = NULL;
    static windowsCallback* user_callback = NULL;
    static LRESULT CALLBACK DefaultWindowCallback(HWND window, UINT messageType, WPARAM param1, LPARAM param2) {

        if (user_callback != NULL && user_callback(window, messageType, param1, param2)) {
            return 0;
        }
        
        switch (messageType) {

            case WM_DESTROY: { /* fallthrough */ }
            case WM_CLOSE: {
                PostQuitMessage(0);
                return 0;
            } break;

            case WM_SYSKEYDOWN: { /* fallthrough */ }
            case WM_KEYDOWN: {
                if (param1 == VK_ESCAPE) {
                    PostQuitMessage(0);
                }
                return 0;
            } break;

            case WM_PAINT: {
                
                if (pixel_buffer != NULL) {
                    int w, h;
                    win32::GetClientSize(window, &w, &h);

                    PAINTSTRUCT paint;
                    HDC dc = BeginPaint(window, &paint);
                    StretchDIBits(
                        dc,
                        0, 0, w, h,
                        0, 0, w, h,
                        pixel_buffer,
                        &render_target,
                        DIB_RGB_COLORS,
                        SRCCOPY
                    );
                    EndPaint(window, &paint);
                }

            } break;

            case WM_SIZE: {
                RECT rect;
                GetClientRect(window, &rect);
                InvalidateRect(window, &rect, true);
            } break;
        }
        
        return DefWindowProc(window, messageType, param1, param2);
    }

    // Warning: Probably its a bad idea to call this more than once lol
    // Warning: Uses GetModuleHandleA(NULL) as the hInstance, so might not work if used as a DLL
    HWND NewWindow(const char* identifier, const char* windowTitle, int x, int y, int w, int h, windowsCallback* callback) {
        user_callback = callback;
        HINSTANCE hinstance = GetModuleHandleA(NULL);
        WNDCLASSA windowClass = {};
        windowClass.lpfnWndProc = DefaultWindowCallback;
        windowClass.hInstance = hinstance;
        windowClass.lpszClassName = LPCSTR(identifier);
        windowClass.hCursor = LoadCursor(NULL, IDC_ARROW);
        RegisterClassA(&windowClass);
        HWND windowHandle = CreateWindowExA(0, LPCSTR(identifier), LPCSTR(windowTitle), WS_POPUP | WS_OVERLAPPED | WS_THICKFRAME | WS_CAPTION | WS_SYSMENU  | WS_MINIMIZEBOX | WS_MAXIMIZEBOX,
            x, y, w, h,
            NULL, NULL, hinstance, NULL
        );
        ShowWindow(windowHandle, SW_SHOW);
        return windowHandle;
    }

    // Sets the client size (not the window size!)
    void SetWindowClientSize(HWND window, int width, int height) {
        int w, h, cw, ch, x, y;
        GetWindowSizeAndPosition(window, &w, &h, &x, &y);
        MoveWindow(window, x, y, width, height, 0);
        GetWindowSizeAndPosition(window, &w, &h, &x, &y);
        GetClientSize(window, &cw, &ch);

        int dw = cw - width;
        if (dw < 0) dw *= -1;
        int dh = ch - height;
        if (dh < 0) dh *= -1;

        MoveWindow(window, x, y, width + dw, height + dh, 0);
        RedrawWindow(window, NULL, NULL, RDW_INVALIDATE);
    }

    void SetWindowPosition(HWND window, int x, int y) {
        int w, h, ignore;
        GetWindowSizeAndPosition(window, &w, &h, &ignore, &ignore);
        
        // Moving the console doesn't redraw it, so parts of the window that were originally hidden won't be rendered.
        MoveWindow(window, x, y, w, h, 0);

        // https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-redrawwindow
        // "If both the hrgnUpdate and lprcUpdate parameters are NULL, the entire client area is added to the update region."
        RedrawWindow(window, NULL, NULL, RDW_INVALIDATE);
    }

    // Everytime this is called it resets the render target
    // 0,0 is top left and w,h is bottom right
    uint32_t* NewWindowRenderTarget(int w, int h) {
        // setup the bitmap that will be rendered to the screen
        render_target.bmiHeader.biSize = sizeof(render_target.bmiHeader);
        render_target.bmiHeader.biWidth = w;
        render_target.bmiHeader.biHeight = -h; // This is negative so that 0,0 is top left and w,h is bottom right

        // "Must be one" -Microsoft
        // Thanks Ms.
        render_target.bmiHeader.biPlanes = 1;

        render_target.bmiHeader.biBitCount = 32;
        render_target.bmiHeader.biCompression = BI_RGB;

        if (pixel_buffer != NULL) {
            VirtualFree(pixel_buffer, 0, MEM_RELEASE);
        }

        int pixel_size = 4; // 4 bytes
        int total_size = pixel_size * (w * h);
        pixel_buffer = VirtualAlloc(0, total_size, MEM_COMMIT, PAGE_READWRITE);
        return (uint32_t*) pixel_buffer;
    }

    // if returns false, loop will end
    typedef bool OnUpdate(uint32_t* pixels, double dt_ms);

    // enters a blocking loop in which keeps on reading and dispatching the windows messages, until the running flag is set to false
    void NewWindowLoopStart(HWND window, OnUpdate* onUpdate) {
        
        char windowTitle[100];
        unsigned long long cpuFrequencySeconds;
        unsigned long long cpuCounter;
        unsigned long long fps;
        double ms;
        win32::GetCpuCounterAndFrequencySeconds(&cpuCounter, &cpuFrequencySeconds);

        bool running = true;
        while (running) {

            cpuCounter = win32::GetTimeDifferenceMsAndFPS(cpuCounter, cpuFrequencySeconds, &ms, &fps);
            
            { // Message loop
                MSG msg;
                while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {

                    TranslateMessage(&msg);
                    DispatchMessage(&msg);

                    if (user_callback != NULL && user_callback(msg.hwnd, msg.message, msg.wParam, msg.lParam)) {
                        continue;
                    }
                    else {
                        switch (msg.message) {
                            case WM_QUIT: {
                                running = false;
                            } break;
                        }
                    }
                }
            }

            running = running && onUpdate((uint32_t*)pixel_buffer, ms);
            if (!running) continue;
            
            // render
            if (pixel_buffer != NULL) {
                int cw, ch;
                win32::GetClientSize(window, &cw, &ch);
                HDC dc = GetDC(window);
                StretchDIBits(
                    dc,
                    0, 0, cw, ch,
                    0, 0, cw, ch,
                    pixel_buffer,
                    &render_target,
                    DIB_RGB_COLORS,
                    SRCCOPY
                );
                ReleaseDC(window, dc);
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
    // returns a newly calculated cpu counter
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

}