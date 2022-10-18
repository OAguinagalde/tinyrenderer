#include <strsafe.h>
#include "win32.h"

namespace win32 {

    // Get the handles to this console with GetStdHandle(STD_INPUT_HANDLE/STD_OUTPUT_HANDLE/STD_ERROR_HANDLE)
    ConsoleAttachResult ConsoleAttach() {
        if (AttachConsole(ATTACH_PARENT_PROCESS)) {
            Print("Console hijacked!\n");
            return ConsoleAttachResult::SUCCESS;
        }
        DWORD error = GetLastError();
        switch (error) {

            case ERROR_ACCESS_DENIED: {
                // If the calling process is already attached to a console, the error code returned is ERROR_ACCESS_DENIED.
                return ConsoleAttachResult::ALREADY_ATTACHED;
            } break;
            
            case ERROR_INVALID_HANDLE: {
                // If the specified process does not have a console, the error code returned is ERROR_INVALID_HANDLE.
                return ConsoleAttachResult::NO_CONSOLE_TO_ATTACH;
            } break;
            
            case ERROR_INVALID_PARAMETER: {
                // If the specified process does not exist, the error code returned is ERROR_INVALID_PARAMETER. 
            } break;
        }
        DWORD break_this = error / 0;
        // Unreachable
        return ConsoleAttachResult::NO_CONSOLE_TO_ATTACH;
    }
    
    // Get the handles to this console with GetStdHandle(STD_INPUT_HANDLE/STD_OUTPUT_HANDLE/STD_ERROR_HANDLE)
    ConsoleCreateResult ConsoleCreate() {
        if (AllocConsole()) {
            return ConsoleCreateResult::SUCCESS;
        }
        else {
            return ConsoleCreateResult::ALREADY_ATTACHED;
        }
    }

    // clears the console associated with the stdout
    void ConsoleClear() {
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
        WriteConsoleA(consoleStdOut, clearConsoleSequence, sizeof(clearConsoleSequence)/sizeof((clearConsoleSequence)[0]), NULL, NULL);
        // Restore original mode
        SetConsoleMode(consoleStdOut, originalMode);
    }

    bool ConsoleGetCursorPosition(short *x, short *y) {
        CONSOLE_SCREEN_BUFFER_INFO cbsi;
        if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &cbsi)) {
            *x = cbsi.dwCursorPosition.X;
            *y = cbsi.dwCursorPosition.Y;
            return true;
        }
        else {
            return false;
        }
    }

    // The handle must have the GENERIC_READ access right
    bool ConsoleSetCursorPosition(short x, short y) {
        COORD position;
        position.X = x;
        position.Y = y;
        return SetConsoleCursorPosition(GetStdHandle(STD_OUTPUT_HANDLE), position);
    }

    HWND ConsoleGetWindow() {
        return GetConsoleWindow();
    }

    bool ConsoleFree() {
        return FreeConsole();
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

    // return true if you handle a message, else return false and the internal code will handle it
    typedef bool windowsCallback(HWND window, UINT messageType, WPARAM param1, LPARAM param2);
    
    WindowContext::WindowContext() {
        win32_user_callback = NULL;
        pixels = NULL;
        memset(&win32_render_target, 0, sizeof(BITMAPINFO));
        memset(&window_handle, 0, sizeof(HWND));
        width = 0;
        height = 0;
    }
    bool WindowContext::IsActive() { return pixels != NULL; }

    static WindowContext window_context;
    WindowContext* GetWindowContext() { return &window_context; }

    static LRESULT CALLBACK DefaultWindowCallback(HWND window, UINT messageType, WPARAM param1, LPARAM param2) {

        if (window_context.win32_user_callback != NULL && window_context.win32_user_callback(window, messageType, param1, param2)) {
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
                
                if (window_context.pixels != NULL) {
                    int w, h;
                    win32::GetClientSize(window, &w, &h);

                    PAINTSTRUCT paint;
                    HDC dc = BeginPaint(window, &paint);
                    StretchDIBits(
                        dc,
                        0, 0, w, h,
                        0, 0, w, h,
                        window_context.pixels,
                        &window_context.win32_render_target,
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
        window_context.win32_user_callback = callback;
        HINSTANCE hinstance = GetModuleHandleA(NULL);
        WNDCLASSA windowClass = {};
        windowClass.lpfnWndProc = DefaultWindowCallback;
        windowClass.hInstance = hinstance;
        windowClass.lpszClassName = LPCSTR(identifier);
        windowClass.hCursor = LoadCursor(NULL, IDC_ARROW);
        ATOM registeredClass = RegisterClassA(&windowClass);
        // clean up with: UnregisterClassA(LPCSTR(identifier), hinstance);
        HWND windowHandle = CreateWindowExA(0, LPCSTR(identifier), LPCSTR(windowTitle), WS_POPUP | WS_OVERLAPPED | WS_THICKFRAME | WS_CAPTION | WS_SYSMENU  | WS_MINIMIZEBOX | WS_MAXIMIZEBOX,
            x, y, w, h,
            NULL, NULL, hinstance, NULL
        );
        // clean up with: DestroyWindow(windowHandle);
        ShowWindow(windowHandle, SW_SHOW);
        window_context.window_handle = windowHandle;
        return windowHandle;
    }

    // Use the same identifier used on NewWindow
    bool CleanWindow(const char* identifier, HWND window) {
        HINSTANCE hinstance = GetModuleHandleA(NULL);
        bool windowDestroyed = DestroyWindow(window);
        bool classUnregistered = UnregisterClassA(LPCSTR(identifier), hinstance);
        memset(&window_context.window_handle, 0, sizeof(HWND));
        return windowDestroyed && classUnregistered;
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
    void NewWindowRenderTarget(int w, int h) {
        // setup the bitmap that will be rendered to the screen
        window_context.win32_render_target.bmiHeader.biSize = sizeof(window_context.win32_render_target.bmiHeader);
        window_context.win32_render_target.bmiHeader.biWidth = w;
        window_context.win32_render_target.bmiHeader.biHeight = h; // make this negative so that 0,0 is top left and w,h is bottom right

        // "Must be one" -Microsoft
        // Thanks Ms.
        window_context.win32_render_target.bmiHeader.biPlanes = 1;

        window_context.win32_render_target.bmiHeader.biBitCount = 32;
        window_context.win32_render_target.bmiHeader.biCompression = BI_RGB;

        if (window_context.pixels != NULL) {
            VirtualFree(window_context.pixels, 0, MEM_RELEASE);
        }

        int pixel_size = 4; // 4 bytes
        int total_size = pixel_size * (w * h);
        window_context.pixels = (uint32_t*) VirtualAlloc(0, total_size, MEM_COMMIT, PAGE_READWRITE);
        window_context.width = w;
        window_context.height = h;
    }

    void CleanWindowRenderTarget() {
        if (window_context.pixels != NULL) {
            VirtualFree(window_context.pixels, 0, MEM_RELEASE);
        }
    }

    // if returns false, loop will end
    typedef bool OnUpdate(double dt_ms, unsigned long long fps);

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

                    if (window_context.win32_user_callback != NULL && window_context.win32_user_callback(msg.hwnd, msg.message, msg.wParam, msg.lParam)) {
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

            running = running && onUpdate(ms, fps);
            if (!running) continue;
            
            // render
            if (window_context.pixels != NULL) {
                int cw, ch;
                win32::GetClientSize(window, &cw, &ch);
                HDC dc = GetDC(window);
                StretchDIBits(
                    dc,
                    0, 0, cw, ch,
                    0, 0, cw, ch,
                    window_context.pixels,
                    &window_context.win32_render_target,
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
        // TODO Not sure why but this is sometimes 0???? for now just idk return with anything, this is not important
        if (counterDifference == 0) counterDifference++;
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