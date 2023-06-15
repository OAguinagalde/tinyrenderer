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

    pub fn scale(factor: f32) M44 {
        var result = M44.identity();
        result.data[0] = factor;
        result.data[5] = factor;
        result.data[10] = factor;
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

/// top = y = window height, bottom = y = 0
fn line(buffer: []Pixel, buffer_width: i32, a: Vector2i, b: Vector2i, color: Pixel) void {
    
    if (a.x == b.x and a.y == b.y) {
        // a point
        buffer[@intCast(usize, buffer_width * a.y + a.x)] = color;
        return;
    }

    const delta = a.substract(b);

    if (delta.x == 0) {
        // vertical line drawn bottom to top
        var top = &a;
        var bottom = &b;
        if (delta.y < 0) {
            top = &b;
            bottom = &a;
        }

        const x = a.x;
        var y = bottom.y;
        while (y != top.y + 1) : (y += 1) {
            buffer[@intCast(usize, buffer_width * y + x)] = color;
        }
        return;
    }
    else if (delta.y == 0) {
        // horizontal line drawn left to right
        var left = &a;
        var right = &b;
        if (delta.x > 0) {
            left = &b;
            right = &a;
        }

        const y = a.y;
        var x = left.x;
        while (x != right.x + 1) : (x += 1) {
            buffer[@intCast(usize, buffer_width * y + x)] = color;
        }
        return;
    }

    const delta_x_abs = std.math.absInt(delta.x) catch unreachable;
    const delta_y_abs = std.math.absInt(delta.y) catch unreachable;

    if (delta_x_abs == delta_y_abs) {
        // draw diagonal line
        var bottom_left = &a;
        var top_right = &b;
        if (a.x < b.x and a.y < b.y) {} else {
            bottom_left = &b;
            top_right = &a;
        }

        var x = bottom_left.x;
        var y = bottom_left.y;
        while (x != top_right.x) {
            buffer[@intCast(usize, buffer_width * y + x)] = color;
            x += 1;
            y += 1;
        }
        return;
    }
    
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
    else if (delta_x_abs < delta_y_abs) {
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
    else unreachable;
}

/// top = y = window height, bottom = y = 0
fn triangle(buffer: []Pixel, buffer_width: i32, tri: [3]Vector3f, z_buffer: []f32, comptime fragment_shader: fn (u:f32, v:f32, w:f32, x: i32, y: i32, z: f32) ?Pixel) void {
    
    const a = &tri[0];
    const b = &tri[1];
    const c = &tri[2];

    const buffer_height = @divExact(@intCast(i32, buffer.len), buffer_width);

    // calculate the bounding of the triangle's projection on the screen
    const left: i32 = @floatToInt(i32, std.math.min(a.x, std.math.min(b.x, c.x)));
    const top: i32 = @floatToInt(i32, std.math.min(a.y, std.math.min(b.y, c.y)));
    const right: i32 = @floatToInt(i32, std.math.max(a.x, std.math.max(b.x, c.x)));
    const bottom: i32 = @floatToInt(i32, std.math.max(a.y, std.math.max(b.y, c.y)));

    if (false) std.debug.print("left   {?}\n", .{ left });
    if (false) std.debug.print("top    {?}\n", .{ top });
    if (false) std.debug.print("bottom {?}\n", .{ bottom });
    if (false) std.debug.print("right  {?}\n", .{ right });

    // if the triangle is not fully inside the buffer, discard it straight away
    if (left < 0 or top < 0 or right >= buffer_width or bottom >= buffer_height) return;

    if (false) std.debug.print("visible\n", .{ });

    // TODO PERF rather than going pixel by pixel on the bounding box of the triangle, use linear interpolation to figure out the "left" and "right" of each row of pixels
    // that way should be faster, although we still need to calculate the barycentric coords for zbuffer and texture sampling, but it might still be better since we skip many pixels
    // test it just in case

    // bottom to top
    var y: i32 = bottom;
    while (y >= top) : (y -= 1) {
        
        // left to right
        var x: i32 = left;
        while (x <= right) : (x += 1) {
            
            // pixel by pixel check if its inside the triangle
            
            // barycentric coordinates of the current pixel, used to...
            // ... determine if a pixel is in fact part of the triangle,
            // ... calculate the pixel's z value
            // ... for texture sampling
            // TODO make const
            var u: f32 = undefined;
            var v: f32 = undefined;
            var w: f32 = undefined;
            {
                const pixel = Vector3f { .x = @intToFloat(f32, x), .y = @intToFloat(f32, y), .z = 0 };

                const ab = b.subtract(a.*);
                const ac = c.subtract(a.*);
                const ap = pixel.subtract(a.*);
                const bp = pixel.subtract(b.*);
                const ca = a.subtract(c.*);

                // TODO PERF we dont actually need many of the calculations of cross_product here, just the z
                // the magnitude of the cross product can be interpreted as the area of the parallelogram.
                const paralelogram_area_abc: f32 = ab.cross_product(ac).z;
                const paralelogram_area_abp: f32 = ab.cross_product(bp).z;
                const paralelogram_area_cap: f32 = ca.cross_product(ap).z;

                u = paralelogram_area_cap / paralelogram_area_abc;
                v = paralelogram_area_abp / paralelogram_area_abc;
                w = (1 - u - v);
            }

            if (false) std.debug.print("u {} v {} w {}\n", .{ u, v, w });

            // determine if a pixel is in fact part of the triangle
            if (u < 0 or u >= 1) continue;
            if (v < 0 or v >= 1) continue;
            if (w < 0 or w >= 1) continue;

            if (false) std.debug.print("inside\n", .{ });

            // interpolate the z of this pixel to find out its depth
            const z = a.z * w + b.z * u + c.z * v;

            const pixel_index = @intCast(usize, x + y * buffer_width);
            if (z_buffer[pixel_index] < z) {
                if (fragment_shader(u, v, w, x, y, z)) |color| {
                    z_buffer[pixel_index] = z;
                    buffer[pixel_index] = color;
                }
            }

        }
    }

}

const State = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    render_target: win32.BITMAPINFO,
    z_buffer: []f32,
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
    .z_buffer = undefined,
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
    state.z_buffer = try allocator.alloc(f32, @intCast(usize, state.w * state.h));
    defer allocator.free(state.pixel_buffer);
    defer allocator.free(state.z_buffer);

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

            var rect: win32.RECT = undefined;
            _ = win32.GetClientRect(window_handle, &rect);
            const client_width = rect.right - rect.left;
            const client_height = rect.bottom - rect.top;

            var app_close_requested = false;
            { // tick / update
                
                // TODO The actual application code
                
                // for (state.pixel_buffer, 0..) |*pixel, i| {
                //     pixel.* = @intCast(Pixel, i + @intCast(usize, counted_since_start));
                // }

                _ = counted_since_start;
                // Clear the screen blue
                for (state.pixel_buffer) |*pixel| { pixel.* = rgb(0, 0, 0); }
                for (state.z_buffer) |*value| { value.* = 0; }

                const white = rgb(255, 255, 255);
                const red = rgb(255, 0, 0);
                const green = rgb(0, 255, 0);
                const blue = rgb(0, 0, 255);
                const turquoise = rgb(0, 255, 255);
                
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 100, .y = 1 }, red); 
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 100, .y = 50 }, green);
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 50, .y = 100 }, blue);
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 1, .y = 100 }, white);
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 100, .y = 100 }, turquoise);

                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 100, .y = 1 }, red); 
                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 100, .y = 50 }, green);
                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 50, .y = 100 }, blue);
                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 1, .y = 100 }, white);
                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 100, .y = 100 }, turquoise);

                line(state.pixel_buffer, state.w, Vector2i { .x = 70, .y = 10 }, Vector2i { .x = 70, .y = 10 }, white);

                const fragment_shader_a = struct {
                    fn shader(u:f32, v:f32, w:f32, x: i32, y: i32, z: f32) ?Pixel {
                        _ = u; _ = v; _ = w; _ = x; _ = y;
                        return rgb(@floatToInt(u8, z*255), @floatToInt(u8, z*255), @floatToInt(u8, z*255));
                    }
                }.shader;

                triangle(
                    state.pixel_buffer,
                    state.w,
                    [3]Vector3f {
                        Vector3f { .x = 33, .y = 20, .z = 0 },
                        Vector3f { .x = 133, .y = 27, .z = 0.5 },
                        Vector3f { .x = 70, .y = 212, .z = 1 },
                    },
                    state.z_buffer,
                    fragment_shader_a
                );

                triangle(
                    state.pixel_buffer,
                    state.w,
                    [3]Vector3f {
                        Vector3f { .x = 33, .y = 50, .z = 1 },
                        Vector3f { .x = 200, .y = 79, .z = 0 },
                        Vector3f { .x = 130, .y = 180, .z = 0.5 },
                    },
                    state.z_buffer,
                    fragment_shader_a
                );
            }

            state.running = state.running and !app_close_requested;
            if (state.running == false) continue;

            { // render
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
