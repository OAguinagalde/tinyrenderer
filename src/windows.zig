const std = @import("std");

const math = @import("math.zig");
const Vector2i = math.Vector2i;
const win32 = @import("win32.zig");
const Buffer2D = @import("buffer.zig").Buffer2D;
const BGRA = @import("pixels.zig").BGRA;

const State = struct {
    x: i32 = 10,
    y: i32 = 10,
    w: i32 = 240*4,
    h: i32 = 136*4,
    render_target: win32.c.BITMAPINFO = undefined,
    keys: [256]bool = [1]bool{false} ** 256,
    pixel_buffer: Buffer2D(BGRA) = undefined,
};

var state: State = .{};

fn window_callback(window_handle: win32.c.HWND , message_type: u32, w_param: win32.c.WPARAM, l_param: win32.c.LPARAM) callconv(win32.call_convention) win32.c.LRESULT {
    
    switch (message_type) {

        win32.c.WM_DESTROY,
        win32.c.WM_CLOSE => {
            win32.c.PostQuitMessage(0);
            return 0;
        },

        win32.c.WM_SYSKEYDOWN,
        win32.c.WM_KEYDOWN => {
            if (w_param == @intFromEnum(win32.c.VK_ESCAPE)) win32.c.PostQuitMessage(0)
            else if (w_param < 256 and w_param >= 0) {
                const key: u8 = @intCast(w_param);
                state.keys[key] = true;
                // std.debug.print("down {c}\n", .{key});
            }
        },

        win32.c.WM_KEYUP => {
            if (w_param < 256 and w_param >= 0) {
                const key: u8 = @intCast(w_param);
                state.keys[key] = false;
            }
        },

        win32.c.WM_SIZE => {
            var rect: win32.c.RECT = undefined;
            _ = win32.c.GetClientRect(window_handle, &rect);
            _ = win32.c.InvalidateRect(window_handle, &rect, @intFromEnum(win32.c.True));
        },

        win32.c.WM_PAINT => {
            var paint_struct: win32.c.PAINTSTRUCT = undefined;
            const handle_device_context = win32.c.BeginPaint(window_handle, &paint_struct);

            _ = win32.c.StretchDIBits(
                handle_device_context,
                0, 0, state.w, state.h,
                0, 0, state.w, state.h,
                state.pixel_buffer.data.ptr,
                &state.render_target,
                win32.c.DIB_RGB_COLORS,
                win32.c.SRCCOPY
            );

            _ = win32.c.EndPaint(window_handle, &paint_struct);
            return 0;
        },

        else => {},
    }

    return win32.c.DefWindowProcW(window_handle, message_type, w_param, l_param);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const instance_handle = win32.c.GetModuleHandleW(null);
    const window_class_name = win32.c.L("doesntmatter");
    const window_class = win32.c.WNDCLASSW {
        .style = @enumFromInt(0),
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
    // NOTE from the ms docs
    // > StretchDIBits creates a top-down image if the sign of the biHeight member of the BITMAPINFOHEADER structure for the DIB is negative
    // > The origin of a bottom-up DIB is the lower-left corner; the origin of a top-down DIB is the upper-left corner.
    state.render_target.bmiHeader.biHeight = state.h;
    state.render_target.bmiHeader.biPlanes = 1;
    state.render_target.bmiHeader.biBitCount = 32;
    state.render_target.bmiHeader.biCompression = win32.c.BI_RGB;

    state.pixel_buffer = Buffer2D(BGRA).from(try allocator.alloc(BGRA, @intCast(state.w * state.h)), @intCast(state.w));
    defer allocator.free(state.pixel_buffer.data);

    _ = win32.c.RegisterClassW(&window_class);
    defer _ = win32.c.UnregisterClassW(window_class_name, instance_handle);
    
    const window_handle_maybe = win32.c.CreateWindowExW(
        @enumFromInt(0),
        window_class_name,
        win32.c.L("win32 zig window"),
        @enumFromInt(@intFromEnum(win32.c.WS_POPUP) | @intFromEnum(win32.c.WS_OVERLAPPED) | @intFromEnum(win32.c.WS_THICKFRAME) | @intFromEnum(win32.c.WS_CAPTION) | @intFromEnum(win32.c.WS_SYSMENU) | @intFromEnum(win32.c.WS_MINIMIZEBOX) | @intFromEnum(win32.c.WS_MAXIMIZEBOX)),
        state.x, state.y, state.w, state.h,
        null, null, instance_handle, null
    );
    
    if (window_handle_maybe) |window_handle| {
        _ = win32.c.ShowWindow(window_handle, .SHOW);
        defer _ = win32.c.DestroyWindow(window_handle);

        // Make sure that client area and state.width/height match
        {
            var rect: win32.c.RECT = undefined;
            _ = win32.c.GetClientRect(window_handle, &rect);
            const client_width: i32 = rect.right - rect.left;
            const client_height: i32 = rect.bottom - rect.top;

            const dw: i32 = state.w - client_width;
            const dh: i32 = state.h - client_height;

            var window_placement: win32.c.WINDOWPLACEMENT = undefined;
            _ = win32.c.GetWindowPlacement(window_handle, &window_placement);
            _ = win32.c.MoveWindow(window_handle, 1920/2/2, 1080/2/2, state.w+dw, state.h+dh, @intFromEnum(win32.c.False));
        }

        var mouse: Vector2i = undefined;
        {
            var mouse_current: win32.c.POINT = undefined;
            _ = win32.c.GetCursorPos(&mouse_current);
            mouse.x = mouse_current.x;
            mouse.y = mouse_current.y;
        }
            
        var cpu_counter: i64 = blk: {
            var counter: win32.c.LARGE_INTEGER = undefined;
            _ = win32.c.QueryPerformanceCounter(&counter);
            break :blk counter.QuadPart;
        };
        const cpu_counter_first: i64 = cpu_counter;
        const cpu_frequency_seconds: i64 = blk: {
            var performance_frequency: win32.c.LARGE_INTEGER = undefined;
            _ = win32.c.QueryPerformanceFrequency(&performance_frequency);
            break :blk performance_frequency.QuadPart;
        };
        std.debug.assert(cpu_frequency_seconds >= 0);
        std.debug.assert(cpu_counter_first >= 0);
        std.debug.assert(cpu_counter >= 0);

        try init(allocator, state.pixel_buffer);

        var running: bool = true;
        while (running) {

            var fps: usize = undefined;
            var ms: f32 = undefined;
            {
                var new_counter: win32.c.LARGE_INTEGER = undefined;
                _ = win32.c.QueryPerformanceCounter(&new_counter);

                var counter_difference = new_counter.QuadPart - cpu_counter;
                
                // TODO sometimes it comes out as 0????? not sure why but its not important right now
                {
                    if (counter_difference == 0) counter_difference = 1;
                }

                ms = 1000.0 * @as(f32, @floatFromInt(counter_difference)) / @as(f32, @floatFromInt(cpu_frequency_seconds));
                fps = @intCast(@divFloor(cpu_frequency_seconds, counter_difference));
                cpu_counter = new_counter.QuadPart;
            }
            
            const counted_since_start: usize = @intCast(cpu_counter - cpu_counter_first);

            // windows message loop
            {
                var message: win32.c.MSG = undefined;
                while (win32.c.PeekMessageW(&message, null,  0, 0, .REMOVE) != @intFromEnum(win32.c.False)) {
                    _ = win32.c.TranslateMessage(&message);
                    _ = win32.c.DispatchMessageW(&message);

                    switch (message.message) {
                        win32.c.WM_QUIT => running = false,
                        else => {},
                    }
                }
            }

            var rect: win32.c.RECT = undefined;
            _ = win32.c.GetClientRect(window_handle, &rect);
            const client_width = rect.right - rect.left;
            const client_height = rect.bottom - rect.top;
            std.debug.assert(client_height == state.h);
            std.debug.assert(client_width == state.w);

            const mouse_previous = mouse;
            var mouse_current: win32.c.POINT = undefined;
            _ = win32.c.GetCursorPos(&mouse_current);
            const mouse_dx = mouse_current.x - mouse_previous.x;
            const mouse_dy = mouse_current.y - mouse_previous.y;
            mouse.x = mouse_current.x;
            mouse.y = mouse_current.y;

            var platform = Platform {
                .frame = counted_since_start,
                .fps = fps,
                .ms = ms,
                .mouse_d = Vector2i { .x = mouse_dx, .y = mouse_dy },
                .mouse = mouse,
                .pixel_buffer = state.pixel_buffer,
                .keys = state.keys,
                .allocator = allocator,
                .w =  state.w,
                .h =  state.h,
            };
            
            const keep_running = try update(&platform);

            running = running and keep_running;
            if (running == false) continue;

            { // render
                const device_context_handle = win32.c.GetDC(window_handle).?;
                _ = win32.c.StretchDIBits(
                    device_context_handle,
                    // The destination x, y (upper left) and width height (in logical units)
                    0, 0, client_width, client_height,
                    // The source x, y (upper left) and width height (in pixels)
                    0, 0, client_width, client_height,
                    // A pointer to the data and a structure with information about the DIB
                    state.pixel_buffer.data.ptr, &state.render_target,
                    // This is used to tell windows whether the colors are just RGB or whether we are using a color palette (in which case, it would be defined in the DIB structure)
                    win32.c.DIB_USAGE.RGB_COLORS,
                    // Finally, what operation to use when rastering. We just want to copy it.
                    win32.c.SRCCOPY
                );
                _ = win32.c.ReleaseDC(window_handle, device_context_handle);
            }
        }
    }

}

pub const Platform = struct {
    allocator: std.mem.Allocator,
    w: i32 = 240*4,
    h: i32 = 136*4,
    mouse: Vector2i,
    mouse_d: Vector2i,
    keys: [256]bool,
    pixel_buffer: Buffer2D(BGRA),
    fps: usize,
    ms: f32,
    frame: usize,
};

const app = @import("windows_001.zig");
const init = app.init;
const update = app.update;