const std = @import("std");

const win32 = struct {
    usingnamespace @import("win32").everything;
    const falsei32: i32 = 0;
    const call_convention = std.os.windows.WINAPI;
};

const Vector2i = struct {
    x: i32,
    y: i32,

    pub fn add(self: Vector2i, other: Vector2i) Vector2i {
        return Vector2i { .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn substract(self: Vector2i, other: Vector2i) Vector2i {
        return Vector2i { .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: Vector2i, factor: i32) Vector2i {
        return Vector2i { .x = self.x * factor, .y = self.y * factor };
    }

    pub fn dot(self: Vector2i, other: Vector2i) i32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn cross_product(self: Vector2i, other: Vector2i) Vector3f {
        return Vector3f {
            .x = 0.0,
            .y = 0.0,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn to_vec2f(self: Vector2i) Vector2f {
        return Vector2f { .x = @intCast(f32, self.x), .y = @intCast(f32, self.y) };
    }
};

const Vector2f = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vector2f, other: Vector2f) Vector2f {
        return Vector2f { .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn substract(self: Vector2f, other: Vector2f) Vector2f {
        return Vector2f { .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: Vector2f, factor: f32) Vector2f {
        return Vector2f { .x = self.x * factor, .y = self.y * factor };
    }

    /// dot product (represented by a dot ·) of 2 vectors A and B is a scalar N, sometimes called scalar product
    pub fn dot(self: Vector2f, other: Vector2f) f32 {
        return self.x * other.x + self.y * other.y;
    }

    /// also known as length, magnitude or norm, represented like ||v||
    pub fn magnitude(self: Vector2f) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y);
    }
    
    pub fn normalized(self: Vector2f) Vector2f {
        const mag = self.magnitude();
        return Vector2f { .x = self.x / mag, .y = self.y / mag };
    }

    pub fn cross_product(self: Vector2f, other: Vector2f) Vector3f {
        return Vector3f {
            .x = 0.0,
            .y = 0.0,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    /// The cross product or vector product (represented by an x) of 2 vectors A and B is another vector C.
    /// C is exactly perpendicular (90 degrees) to the plane AB, meaning that there has to be a 3rd dimension for the cross product for this to make sense.
    /// The length of C will be the same as the area of the parallelogram formed by AB.
    /// This implementation assumes z = 0, meaning that the result will always be of type Vec3 (0, 0, x*v.y-y*v.x).
    /// For that same reason, the magnitude of the resulting Vec3 will be just the value of the component z
    pub fn cross_product_magnitude(self: Vector2f, other: Vector2f) f32 {
        return self.cross_product(other).z;
    }
};

const Vector3f = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn add(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f { .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }

    pub fn subtract(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f { .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }

    pub fn dot(self: Vector3f, other: Vector3f) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn magnitude(self: Vector3f) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub fn normalized(self: Vector3f) Vector3f {
        const mag = self.magnitude();
        return Vector3f { .x = self.x / mag, .y = self.y / mag, .z = self.z / mag };
    }

    pub fn normalize(self: *Vector3f) void {
        const mag = self.magnitude();
        self.x = self.x / mag;
        self.y = self.y / mag;
        self.z = self.z / mag;
    }

    pub fn cross_product(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f {
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn scale(self: Vector3f, factor: f32) Vector3f {
        return Vector3f { .x = self.x * factor, .y = self.y * factor, .z = self.z * factor };
    }
};

const Vector4f = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn add(self: Vector4f, other: Vector4f) Vector4f {
        return Vector4f { .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z, .w = self.w + other.w };
    }

    pub fn scale(self: Vector4f, factor: f32) Vector4f {
        return Vector4f { .x = self.x * factor, .y = self.y * factor, .z = self.z * factor, .w = self.w * factor };
    }
};

/// column major 4x4 matrix
const M44 = struct {
    data: [16]f32,

    pub fn multiply(self: M44, other: M44) M44 {
        var result: M44 = undefined;
        for (0..4) |row| {
            for (0..4) |col| {
                result.data[(row*4)+col] = 0;
                for (0..4) |element| {
                    result.data[(row*4)+col] += self.data[(element*4)+col] * other.data[(row*4)+element];
                }
            }
        }
        return result;
    }

    pub fn transposed(self: M44) M44 {
        var result: M44 = undefined;
        for (0..4) |row| {
            for (0..4) |col| {
                result.data[(row*4)+col] = self.data[(col*4)+row];
            }
        }
        return result;
    }

    pub fn identity() M44 {
        var result: M44 = undefined;
        result.data[0] = 1;
        result.data[1] = 0;
        result.data[2] = 0;
        result.data[3] = 0;
        result.data[4] = 0;
        result.data[5] = 1;
        result.data[6] = 0;
        result.data[7] = 0;
        result.data[8] = 0;
        result.data[9] = 0;
        result.data[10] = 1;
        result.data[11] = 0;
        result.data[12] = 0;
        result.data[13] = 0;
        result.data[14] = 0;
        result.data[15] = 1;
        return result;
    }

    pub fn translation(t: Vector3f) M44 {
        var result = M44.identity();
        result.data[12] = t.x;
        result.data[13] = t.y;
        result.data[14] = t.z;
        return result;
    }
    
};

const Pixel = u32;

fn rgb(r: u8, g: u8, b: u8) Pixel {
    return rgba(r,g,b,255);
}

fn rgba(r: u8, g: u8, b: u8, a: u8) Pixel {
    // In windows pixels are stored as BGRA
    const Win32PixelStructure = extern struct {
        b: u8,
        g: u8,
        r: u8,
        /// 255 for solid and 0 for transparent
        a: u8,
    };
    return @bitCast(u32 , Win32PixelStructure {
        .a = a, .r = r, .g = g, .b = b
    });
}

fn line(buffer: []Pixel, buffer_width: i32, a: Vector2i, b: Vector2i, color: Pixel) void {
    const delta = a.substract(b);
    const delta_x_abs = std.math.absInt(delta.x) catch unreachable;
    const delta_y_abs = std.math.absInt(delta.y) catch unreachable;

    if (delta_x_abs > delta_y_abs) {
        // draw horizontally
        
        var left = &a;
        var right = &b;

        if (delta.x > 0) {
            left = &b;
            right = &a;
        }

        const increment = 1 / @intToFloat(f32, delta_x_abs);
        var percentage_of_line_done: f32 = 0;
        
        var x = left.x;
        while (x <= right.x) : (x += 1) {
            // linear interpolation to figure out `y`
            const y = left.y + @floatToInt(i32, @intToFloat(f32, right.y - left.y) * percentage_of_line_done);
            buffer[@intCast(usize, buffer_width*y + x)] = color;
            percentage_of_line_done += increment;
        }
    }
    else {
        // draw vertically

        var top = &a;
        var bottom = &b;

        if (delta.y > 0) {
            top = &b;
            bottom = &a;
        }

        const increment = 1 / @intToFloat(f32, delta_y_abs);
        var percentage_of_line_done: f32 = 0;

        var y = top.y;
        while (y <= bottom.y) : (y += 1) {
            const x = top.x + @floatToInt(i32, @intToFloat(f32, bottom.x - top.x) * percentage_of_line_done);
            buffer[@intCast(usize, buffer_width * y + x)] = color;
            percentage_of_line_done += increment;
        }

    }

    buffer[@intCast(usize, a.x + a.y*buffer_width)] = rgb(0, 255, 0);
    buffer[@intCast(usize, b.x + b.y*buffer_width)] = rgb(255, 0, 0);
}

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
                
                // TODO The actual application code
                
                // for (state.pixel_buffer, 0..) |*pixel, i| {
                //     pixel.* = @intCast(Pixel, i + @intCast(usize, counted_since_start));
                // }

                _ = counted_since_start;
                // Clear the screen blue
                for (state.pixel_buffer) |*pixel| { pixel.* = rgb(0, 0, 0); }

                const white = rgb(255, 255, 255);
                const red = rgb(255, 0, 0);
                const green = rgb(0, 255, 0);
                const blue = rgb(0, 0, 255);
                line(state.pixel_buffer, state.w, Vector2i { .x = 1, .y = 1 }, Vector2i { .x = 100, .y = 1 }, red); 
                line(state.pixel_buffer, state.w, Vector2i { .x = 1, .y = 1 }, Vector2i { .x = 100, .y = 50 }, green);
                line(state.pixel_buffer, state.w, Vector2i { .x = 1, .y = 1 }, Vector2i { .x = 50, .y = 100 }, blue);
                line(state.pixel_buffer, state.w, Vector2i { .x = 1, .y = 1 }, Vector2i { .x = 1, .y = 100 }, white);

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