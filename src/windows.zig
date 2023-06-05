const std = @import("std");
const win32 = struct {
    usingnamespace @import("win32").everything;
    const falsei32: i32 = 0;
    const call_convention = std.os.windows.WINAPI;
};

const Pixel = u32;
const State = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    render_target: win32.BITMAPINFO,
    pixel_buffer: []Pixel,
    running: bool,
};

var state = State {
    .x = 10,
    .y = 10,
    .w = 500,
    .h = 300,
    .render_target = undefined,
    .pixel_buffer = undefined,
    .running = true,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const instance_handle = win32.GetModuleHandleW(null);
    const window_class_name = win32.L("doesntmatter");
    const window_class = win32.WNDCLASSW {
        .style = @intToEnum(win32.WNDCLASS_STYLES, 0),
        .lpfnWndProc = window_callback,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance_handle,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = window_class_name,
    };
    
    state.render_target.bmiHeader.biSize = @sizeOf(@TypeOf(state.render_target.bmiHeader));
    state.render_target.bmiHeader.biWidth = state.w;
    state.render_target.bmiHeader.biHeight = state.h;
    //  _______________________________
    // |                               |
    // |   `biPlanes` must be one      |
    // |                    -Microsoft |
    // '_______________________________'
    state.render_target.bmiHeader.biPlanes = 1;
    state.render_target.bmiHeader.biBitCount = 32;
    state.render_target.bmiHeader.biCompression = win32.BI_RGB;

    state.pixel_buffer = try allocator.alloc(Pixel, @intCast(usize, state.w * state.h));
    defer allocator.free(state.pixel_buffer);

    _ = win32.RegisterClassW(&window_class);
    defer _ = win32.UnregisterClassW(window_class_name, instance_handle);
    
    const window_handle_maybe = win32.CreateWindowExW(
        @intToEnum(win32.WINDOW_EX_STYLE, 0),
        window_class_name,
        win32.L("win32 zig window"),
        @intToEnum(win32.WINDOW_STYLE, @enumToInt(win32.WS_POPUP) | @enumToInt(win32.WS_OVERLAPPED) | @enumToInt(win32.WS_THICKFRAME) | @enumToInt(win32.WS_CAPTION) | @enumToInt(win32.WS_SYSMENU) | @enumToInt(win32.WS_MINIMIZEBOX) | @enumToInt(win32.WS_MAXIMIZEBOX)),
        state.x, state.y, state.w, state.h,
        null, null, instance_handle, null
    );
    
    if (window_handle_maybe) |window_handle| {
        defer _ = win32.DestroyWindow(window_handle);
        _ = win32.ShowWindow(window_handle, .SHOW);

        var cpu_counter: i64 = blk: {
            var counter: win32.LARGE_INTEGER = undefined;
            _ = win32.QueryPerformanceCounter(&counter);
            break :blk counter.QuadPart;
        };
        const cpu_counter_first: i64 = cpu_counter;
        const cpu_frequency_seconds: i64 = blk: {
            var performance_frequency: win32.LARGE_INTEGER = undefined;
            _ = win32.QueryPerformanceFrequency(&performance_frequency);
            break :blk performance_frequency.QuadPart;
        };

        while (state.running) {

            var fps: i64 = undefined;
            var ms: f64 = undefined;
            { // calculate fps and ms
                var new_counter: win32.LARGE_INTEGER = undefined;
                _ = win32.QueryPerformanceCounter(&new_counter);
                var counter_difference = new_counter.QuadPart - cpu_counter;
                // TODO sometimes it comes out as 0????? not sure why but its not important right now
                if (counter_difference == 0) counter_difference = 1;
                ms = 1000.0 * @intToFloat(f64, counter_difference) / @intToFloat(f64, cpu_frequency_seconds);
                fps = @divFloor(cpu_frequency_seconds, counter_difference);
                cpu_counter = new_counter.QuadPart;
            }
            const counted_since_start = cpu_counter - cpu_counter_first;

            { // windows message loop
                var message: win32.MSG = undefined;
                while (win32.PeekMessageW(&message, null,  0, 0, .REMOVE) != win32.falsei32) {
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageW(&message);

                    // TODO Any windows messages that the application needs to read should happen here
                    switch (message.message) {
                        win32.WM_QUIT => state.running = false,
                        else => {},
                    }
                }
            }

            var app_close_requested = false;
            { // tick / update
                // TODO The actual applicatio code
                for (state.pixel_buffer, 0..) |*pixel, i| {
                    pixel.* = @intCast(Pixel, i + @intCast(usize, counted_since_start));
                }
            }

            state.running = state.running and !app_close_requested;
            if (state.running == false) continue;

            { // render
                var rect: win32.RECT = undefined;
                _ = win32.GetClientRect(window_handle, &rect);
                const client_width = rect.right - rect.left;
                const client_height = rect.bottom - rect.top;
                const device_context_handle = win32.GetDC(window_handle).?;
                _ = win32.StretchDIBits(
                    device_context_handle,
                    0, 0, client_width, client_height,
                    0, 0, client_width, client_height,
                    state.pixel_buffer.ptr,
                    &state.render_target,
                    win32.DIB_RGB_COLORS,
                    win32.SRCCOPY
                );
                _ = win32.ReleaseDC(window_handle, device_context_handle);
            }
        }
    }

}

fn window_callback(window_handle: win32.HWND , message_type: u32, w_param: win32.WPARAM, l_param: win32.LPARAM) callconv(win32.call_convention) win32.LRESULT {
    
    switch (message_type) {

        win32.WM_DESTROY, win32.WM_CLOSE => {
            win32.PostQuitMessage(0);
            return 0;
        },

        win32.WM_SYSKEYDOWN, win32.WM_KEYDOWN => {
            if (w_param == @enumToInt(win32.VK_ESCAPE)) win32.PostQuitMessage(0);
        },

        win32.WM_SIZE => {
            var rect: win32.RECT = undefined;
            _ = win32.GetClientRect(window_handle, &rect);
            _ = win32.InvalidateRect(window_handle, &rect, @enumToInt(win32.True));
        },

        win32.WM_PAINT =>
        {
            var paint_struct: win32.PAINTSTRUCT = undefined;
            const handle_device_context = win32.BeginPaint(window_handle, &paint_struct);

            _ = win32.StretchDIBits(
                handle_device_context,
                0, 0, state.w, state.h,
                0, 0, state.w, state.h,
                state.pixel_buffer.ptr,
                &state.render_target,
                win32.DIB_RGB_COLORS,
                win32.SRCCOPY
            );

            _ = win32.EndPaint(window_handle, &paint_struct);
            return 0;
        },
        else => {},
    }

    return win32.DefWindowProcW(window_handle, message_type, w_param, l_param);
}
