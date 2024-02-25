const std = @import("std");
const builtin = @import("builtin");

const math = @import("math.zig");
const Vector2i = math.Vector2i;
/// The actual `windows.h` API
const win32 = @import("win32").everything;
const Buffer2D = @import("buffer.zig").Buffer2D;
const BGRA = @import("pixels.zig").BGRA;

pub fn Application(comptime app: ApplicationDescription) type {
    return struct {
        
        pub const width = app.desired_width;
        pub const height = app.desired_height;
        pub const dimension_scale = app.dimension_scale;

        const State = struct {
            x: i32 = 10,
            y: i32 = 10,
            w: i32 = app.desired_width*app.dimension_scale,
            h: i32 = app.desired_height*app.dimension_scale,
            render_target: win32.BITMAPINFO = undefined,
            keys_old: [256]bool = [1]bool{false} ** 256,
            keys: [256]bool = [1]bool{false} ** 256,
            pixel_buffer: Buffer2D(BGRA) = undefined,
            mouse_left_clicked: bool = false,
            mouse_left_down: bool = false,
            mwheel: i32 = 0,
        };

        var state: State = .{};

        pub fn run() !void {
            
            const AllocatorType = std.heap.GeneralPurposeAllocator(.{});
            var allocator_master = AllocatorType {};
            defer _ = allocator_master.detectLeaks();
            const allocator = allocator_master.allocator();
            const instance_handle = win32.GetModuleHandleW(null);
            if (instance_handle == null) {
                std.log.debug("win32.GetModuleHandleW == NULL. Last error: {any}", .{win32.GetLastError()});
                unreachable;
            }
            const window_class_name = win32.L("doesntmatter");
            const window_class = win32.WNDCLASSW {
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
            state.render_target.bmiHeader.biWidth = app.desired_width;
            // NOTE from the ms docs
            // > StretchDIBits creates a top-down image if the sign of the biHeight member of the BITMAPINFOHEADER structure for the DIB is negative
            // > The origin of a bottom-up DIB is the lower-left corner; the origin of a top-down DIB is the upper-left corner.
            state.render_target.bmiHeader.biHeight = app.desired_height;
            state.render_target.bmiHeader.biPlanes = 1;
            state.render_target.bmiHeader.biBitCount = 32;
            state.render_target.bmiHeader.biCompression = win32.BI_RGB;

            state.pixel_buffer = Buffer2D(BGRA).from(try allocator.alloc(BGRA, app.desired_width * app.desired_height), app.desired_width);
            defer allocator.free(state.pixel_buffer.data);

            const register_class_error = win32.RegisterClassW(&window_class);
            if (register_class_error == 0) {
                std.log.debug("win32.RegisterClassW == 0. Last error: {any}", .{win32.GetLastError()});
                unreachable;
            }
            defer _ = win32.UnregisterClassW(window_class_name, instance_handle);
            
            const window_handle_maybe = win32.CreateWindowExW(
                @enumFromInt(0),
                window_class_name,
                win32.L("win32 zig window"),
                @enumFromInt(@intFromEnum(win32.WS_POPUP) | @intFromEnum(win32.WS_OVERLAPPED) | @intFromEnum(win32.WS_THICKFRAME) | @intFromEnum(win32.WS_CAPTION) | @intFromEnum(win32.WS_SYSMENU) | @intFromEnum(win32.WS_MINIMIZEBOX) | @intFromEnum(win32.WS_MAXIMIZEBOX)),
                state.x, state.y, state.w, state.h,
                null, null, instance_handle, null
            );
            if (window_handle_maybe == null) {
                std.log.debug("win32.CreateWindowExW == NULL. Last error: {any}", .{win32.GetLastError()});
                unreachable;
            }   
            
            if (window_handle_maybe) |window_handle| {
                _ = win32.ShowWindow(window_handle, .SHOW);
                defer _ = win32.DestroyWindow(window_handle);

                // Make sure that client area and state.width/height match
                {
                    var rect: win32.RECT = undefined;
                    _ = win32.GetClientRect(window_handle, &rect);
                    const client_width: i32 = rect.right - rect.left;
                    const client_height: i32 = rect.bottom - rect.top;

                    const dw: i32 = state.w - client_width;
                    const dh: i32 = state.h - client_height;

                    var window_placement: win32.WINDOWPLACEMENT = undefined;
                    _ = win32.GetWindowPlacement(window_handle, &window_placement);
                    _ = win32.MoveWindow(window_handle, 1920/2/2, 1080/2/2, state.w+dw, state.h+dh, @intFromEnum(win32.False));
                }

                var mouse: Vector2i = undefined;
                // get mouse data from win32
                {
                    var mouse_current: win32.POINT = undefined;
                    _ = win32.GetCursorPos(&mouse_current);
                    mouse.x = mouse_current.x;
                    mouse.y = mouse_current.y;
                }
                // by default, the mouse positions will be relative to the top left corner of the left-most screen
                // convert it so that its a relative position to the top left of the window client area, and take into account
                // the dimension_scaling there might be
                mouse.x = @divFloor(mouse.x - state.x, app.dimension_scale);
                mouse.y = @divFloor(mouse.y - state.y, app.dimension_scale);

                var frame: usize = 0;    
                var cpu_counter_now: i64 = blk: {
                    var counter: win32.LARGE_INTEGER = undefined;
                    _ = win32.QueryPerformanceCounter(&counter);
                    break :blk counter.QuadPart;
                };
                const cpu_counter_first: i64 = cpu_counter_now;
                var cpu_counter_since_first: usize = @intCast(cpu_counter_now - cpu_counter_first);
                const cpu_frequency_seconds: i64 = blk: {
                    var performance_frequency: win32.LARGE_INTEGER = undefined;
                    _ = win32.QueryPerformanceFrequency(&performance_frequency);
                    break :blk performance_frequency.QuadPart;
                };

                try app.init(allocator);

                var running: bool = true;
                while (running) {

                    var ms: f32 = undefined;
                    const do_artificial_wait = true;
                    while (true) {
                        var current_cpu_counter: win32.LARGE_INTEGER = undefined;
                        _ = win32.QueryPerformanceCounter(&current_cpu_counter);
                        var cpu_counter_delta = current_cpu_counter.QuadPart - cpu_counter_now;
                        // TODO sometimes it comes out as 0????? not sure why but its not important right now
                        if (cpu_counter_delta == 0) cpu_counter_delta = 1;
                        ms = 1000.0 * @as(f32, @floatFromInt(cpu_counter_delta)) / @as(f32, @floatFromInt(cpu_frequency_seconds));
                        // TODO figure out a proper timing mechanism lol
                        // https://gafferongames.com/post/fix_your_timestep/
                        if ((do_artificial_wait and ms >= 1000/60) or !do_artificial_wait) {
                            cpu_counter_now = current_cpu_counter.QuadPart;
                            cpu_counter_since_first = @intCast(cpu_counter_now - cpu_counter_first);
                            break;
                        }
                    }

                    // windows message loop
                    {
                        var message: win32.MSG = undefined;
                        while (win32.PeekMessageW(&message, null,  0, 0, .REMOVE) != @intFromEnum(win32.False)) {
                            _ = win32.TranslateMessage(&message);
                            _ = win32.DispatchMessageW(&message);

                            switch (message.message) {
                                win32.WM_QUIT => running = false,
                                else => {},
                            }
                        }
                    }

                    {
                        // make sure sizes are correct
                        var rect: win32.RECT = undefined;
                        _ = win32.GetClientRect(window_handle, &rect);
                        const client_width = rect.right - rect.left;
                        const client_height = rect.bottom - rect.top;
                        std.debug.assert(client_height == state.h);
                        std.debug.assert(client_width == state.w);
                    }

                    const mouse_previous = mouse;
                    // relative to the top left corner of the window client area
                    const mouse_current: win32.POINT = blk: {
                        var point: win32.POINT = undefined;
                        if (win32.GetCursorPos(&point) == 0) {
                            std.log.debug("win32.GetCursorPos == 0. Last error: {any}", .{win32.GetLastError()});
                            unreachable;
                        }
                        if (win32.ScreenToClient(window_handle, &point) == 0) {
                            std.log.debug("win32.ScreenToClient == 0. Last error: {any}", .{win32.GetLastError()});
                            unreachable;
                        }
                        break :blk point;
                    };
                    const mouse_dx = mouse_current.x - mouse_previous.x;
                    const mouse_dy = mouse_current.y - mouse_previous.y;
                    mouse.x = mouse_current.x;
                    mouse.y = mouse_current.y;

                    const mouse_left_clicked = state.mouse_left_clicked;
                    state.mouse_left_clicked = false;

                    const mwheel = state.mwheel;
                    state.mwheel = 0;

                    var platform = UpdateData {
                        .frame = frame,
                        .ms = ms,
                        .mouse_d = Vector2i { .x = mouse_dx, .y = mouse_dy },
                        .mouse = mouse,
                        .pixel_buffer = state.pixel_buffer,
                        .keys_old = state.keys_old,
                        .keys = state.keys,
                        .allocator = allocator,
                        .w =  state.w,
                        .h =  state.h,
                        .mouse_left_down = state.mouse_left_down,
                        .mouse_left_clicked = mouse_left_clicked,
                        .mwheel = mwheel,
                    };
                    
                    // _ = platform;
                    const keep_running = try app.update(&platform);
                    // state.pixel_buffer.clear(BGRA.make(100,100,100,100));
                    
                    state.keys_old = state.keys;
                    frame += 1;
                    running = running and keep_running;

                    if (running == false) continue;

                    // render
                    const device_context_handle = win32.GetDC(window_handle);
                    if (device_context_handle == null) {
                        std.log.debug("win32.GetDC == 0. Last error: {any}", .{win32.GetLastError()});
                        unreachable;
                    }
                    // std.log.debug("StretchDIBits {}x{} from {}x{}", .{state.w, state.h, @as(i32,@intCast(state.pixel_buffer.width)), @as(i32,@intCast(state.pixel_buffer.height))});
                    const stretch_di_bits_error = win32.StretchDIBits(
                        device_context_handle.?,
                        // NOTE so stretchdibits is a fucking mess. These 2 coordinates are the top left in the window itself...
                        0, 0,
                        // then how many pixels we want to draw starting from that corner...
                        @divExact(state.w,1), @divExact(state.h,1),
                        // These two, are the bottom left corner of OUR pixel buffer. If we want this to also be the top left, then biHeight in the header must be a negative number...
                        0, 0,
                        // ... finally, starting from that bottom left corner, how many pixels we want to draw in the previously defined rectangle of the window itself
                        @intCast(@divExact(state.pixel_buffer.width,1)), @intCast(@divExact(state.pixel_buffer.height,1)),
                        // A pointer to the data and a structure with information about the DIB
                        state.pixel_buffer.data.ptr, &state.render_target,
                        // This is used to tell windows whether the colors are just RGB or whether we are using a color palette (in which case, it would be defined in the DIB structure)
                        win32.DIB_USAGE.RGB_COLORS,
                        // Finally, what operation to use when rastering. We just want to copy it.
                        win32.SRCCOPY
                    );
                    if (stretch_di_bits_error == 0) {
                        std.log.debug("win32.StretchDIBits == 0. Last error: {any}", .{win32.GetLastError()});
                        // unreachable;
                    }
                    _ = win32.ReleaseDC(window_handle, device_context_handle.?);
                }
            }

        }

        fn window_callback(window_handle: win32.HWND , message_type: u32, w_param: win32.WPARAM, l_param: win32.LPARAM) callconv(std.os.windows.WINAPI) win32.LRESULT {
            
            switch (message_type) {

                win32.WM_DESTROY,
                win32.WM_CLOSE => {
                    win32.PostQuitMessage(0);
                    return 0;
                },

                win32.WM_MOUSEWHEEL => {
                    // 
                    //     const delta = win32.GET_WHEEL_DELTA_WPARAM(w_param);
                    // 
                    // The delta value indicates the distance the wheel was rotated.
                    // A positive value means the wheel was scrolled forward (away from the user),
                    // and a negative value means the wheel was scrolled backward (toward the user).
                    // 
                    //     if (delta > 0) {
                    //     } else if (delta < 0) {
                    //     }
                    // 
                    state.mwheel = @intCast(@as(i16, @bitCast(@as(u16, @truncate(w_param >> 16)) & @as(u16, 0xFFFF))));
                },
                
                win32.WM_LBUTTONDOWN => {
                    state.mouse_left_down = true;
                },

                win32.WM_LBUTTONUP => {
                    state.mouse_left_down = false;
                    state.mouse_left_clicked = true;
                },

                win32.WM_SYSKEYDOWN,
                win32.WM_KEYDOWN => {
                    if (w_param == @intFromEnum(win32.VK_ESCAPE)) win32.PostQuitMessage(0)
                    else if (w_param < 256 and w_param >= 0) {
                        const key: u8 = @intCast(w_param);
                        state.keys[key] = true;
                        // std.debug.print("down {c}\n", .{key});
                    }
                },

                win32.WM_KEYUP => {
                    if (w_param < 256 and w_param >= 0) {
                        const key: u8 = @intCast(w_param);
                        state.keys[key] = false;
                    }
                },

                win32.WM_SIZE => {
                    var rect: win32.RECT = undefined;
                    _ = win32.GetClientRect(window_handle, &rect);
                    _ = win32.InvalidateRect(window_handle, &rect, @intFromEnum(win32.True));
                },

                win32.WM_PAINT => {
                    var paint_struct: win32.PAINTSTRUCT = undefined;
                    const handle_device_context = win32.BeginPaint(window_handle, &paint_struct);

                    const result = win32.StretchDIBits(
                        handle_device_context,
                        0, 0, @divExact(state.w,1), @divExact(state.h,1),
                        0, 0, @intCast(@divExact(state.pixel_buffer.width,1)), @intCast(@divExact(state.pixel_buffer.height,1)),
                        
                        // 0, 0, state.w, state.h,
                        // 0, 0, @intCast(state.pixel_buffer.width), @intCast(state.pixel_buffer.height),
                        state.pixel_buffer.data.ptr,
                        &state.render_target,
                        win32.DIB_RGB_COLORS,
                        win32.SRCCOPY
                    );

                    if (result == 0) {
                        std.log.debug("win32.StretchDIBits == 0. Last error: {any}", .{win32.GetLastError()});
                        // unreachable;
                    }
                    _ = win32.EndPaint(window_handle, &paint_struct);
                    return 0;
                },

                else => {},
            }

            return win32.DefWindowProcW(window_handle, message_type, w_param, l_param);
        }

    };
}

pub const UpdateData = struct {
    allocator: std.mem.Allocator,
    w: i32,
    h: i32,
    mouse: Vector2i,
    mouse_d: Vector2i,
    keys_old: [256]bool,
    keys: [256]bool,
    pixel_buffer: Buffer2D(BGRA),
    ms: f32,
    frame: usize,
    mouse_left_down: bool,
    mouse_left_clicked: bool,
    mwheel: i32,

    pub fn key_pressing(ud: *const UpdateData, key: usize) bool {
        return ud.keys[key];
    }
    
    pub fn key_pressed(ud: *const UpdateData, key: usize) bool {
        return ud.keys[key] and !ud.keys_old[key];
    }

};

pub const InitFn = fn (allocator: std.mem.Allocator) anyerror!void;
pub const UpdateFn = fn (update_data: *UpdateData) anyerror!bool;
pub const ApplicationDescription = struct {
    init: InitFn,
    update: UpdateFn,
    dimension_scale: comptime_int,
    desired_width: comptime_int,
    desired_height: comptime_int,
};

pub const timestamp: fn () i64 = std.time.timestamp;
pub const OutPixelType = BGRA;
