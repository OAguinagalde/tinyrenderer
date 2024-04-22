const std = @import("std");
const builtin = @import("builtin");

const math = @import("math.zig");
const Vector2i = math.Vector2i;

/// The actual `windows.h` API
const win32 = @import("win32.zig");
// const win32 = @import("win32").everything;
// const win32 = @import("../dep/zigwin32/win32/everything.zig");

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
            
            var allocator_master = std.heap.GeneralPurposeAllocator(.{}) {};
            // total memory to be used: 64 mib
            var main_allocator = FixedBufferAllocatorWrapper("Main", true).init(try allocator_master.allocator().alloc(u8, 1024*1024*64));
            var app_long_allocator = FixedBufferAllocatorWrapper("AppLong", true).init(main_allocator.allocator().alloc(u8, 1024 * 1024 * 32) catch {
                @panic("Failed to allocate memory for the application's long term reserved memory");
            });
            var app_short_allocator = FixedBufferAllocatorWrapper("AppShort", false).init(main_allocator.allocator().alloc(u8, 1024 * 1024 * 32) catch {
                @panic("Failed to allocate memory for the application's update memory");
            });
            
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

            state.pixel_buffer = Buffer2D(BGRA).from(try app_long_allocator.allocator().alloc(BGRA, app.desired_width * app.desired_height), app.desired_width);

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

                var mouse: Vector2i = blk: {
                    var mouse_win32: win32.POINT = undefined;
                    // windows gives the position of the mouse relative to the top left corner.
                    _ = win32.GetCursorPos(&mouse_win32);
                    std.debug.assert(win32.ScreenToClient(window_handle, &mouse_win32) == @intFromEnum(win32.True));
                    break :blk Vector2i {
                        // NOTE we want the mouse position to take into account the dimension scale of the application, hence the division here
                        .x = @divFloor(mouse_win32.x, app.dimension_scale),
                        // NOTE we want it relative to the bottom left corner, so inverse it
                        .y = @divFloor(state.h - mouse_win32.y, app.dimension_scale)
                    };
                };

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

                try app.init(app_long_allocator.allocator());

                var running: bool = true;
                while (running) {

                    var ms: f32 = undefined;
                    var time_since_start: f64 = undefined;
                    const do_artificial_wait = false;
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
                    time_since_start = @as(f64, @floatFromInt(cpu_counter_since_first)) / @as(f64, @floatFromInt(cpu_frequency_seconds));

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
                    var mouse_win32: win32.POINT = undefined;
                    // windows gives the position of the mouse relative to the top left corner.
                    _ = win32.GetCursorPos(&mouse_win32);
                    std.debug.assert(win32.ScreenToClient(window_handle, &mouse_win32) == @intFromEnum(win32.True));
                    // NOTE we want the mouse position to take into account the dimension scale of the application, hence the division here
                    mouse.x = @divFloor(mouse_win32.x, app.dimension_scale);
                    // NOTE we want it relative to the bottom left corner, so inverse it
                    mouse.y = @divFloor(state.h - mouse_win32.y, app.dimension_scale);
                    const mouse_dx = mouse.x - mouse_previous.x;
                    const mouse_dy = mouse.y - mouse_previous.y;

                    const mouse_left_clicked = state.mouse_left_clicked;
                    state.mouse_left_clicked = false;

                    const mwheel = state.mwheel;
                    state.mwheel = 0;

                    var platform = UpdateData {
                        .frame = frame,
                        .tick = cpu_counter_since_first,
                        .time_since_start = time_since_start,
                        .ms = ms,
                        .mouse_d = Vector2i { .x = mouse_dx, .y = mouse_dy },
                        .mouse = mouse,
                        .pixel_buffer = state.pixel_buffer,
                        .keys_old = state.keys_old,
                        .keys = state.keys,
                        .allocator = app_short_allocator.allocator(),
                        .w =  state.w,
                        .h =  state.h,
                        .mouse_left_down = state.mouse_left_down,
                        .mouse_left_clicked = mouse_left_clicked,
                        .mwheel = mwheel,
                    };
                    
                    // _ = platform;
                    const keep_running = try app.update(&platform);
                    app_short_allocator.fba.reset();
                    
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
        
        pub fn read_file_sync(allocator: std.mem.Allocator, file_name: []const u8) ![]const u8 {
            const file = try std.fs.cwd().openFile(file_name, .{});
            defer file.close();
            const file_stats = try file.stat();
            const bytes = try file.reader().readAllAlloc(allocator, file_stats.size);
            return bytes;
        }

        pub const sound = struct {
            pub const initialize = waveout.waveout_setup;
        };
    };
}

pub const UpdateData = struct {
    allocator: std.mem.Allocator,
    time_since_start: f64,
    w: i32,
    h: i32,
    mouse: Vector2i,
    mouse_d: Vector2i,
    keys_old: [256]bool,
    keys: [256]bool,
    pixel_buffer: Buffer2D(BGRA),
    ms: f32,
    frame: usize,
    tick: usize,
    mouse_left_down: bool,
    mouse_left_clicked: bool,
    mwheel: i32,

    pub fn key_pressing(ud: *const UpdateData, key: usize) bool {
        return ud.keys[key];
    }
    
    pub fn key_pressed(ud: *const UpdateData, key: usize) bool {
        return ud.keys[key] and !ud.keys_old[key];
    }

    pub fn key_released(ud: *const UpdateData, key: usize) bool {
        return !ud.keys[key] and ud.keys_old[key];
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

fn FixedBufferAllocatorWrapper(comptime name: []const u8, comptime log: bool) type {
    return struct {

        const Self = @This();

        fba: std.heap.FixedBufferAllocator,
        one_percent_aprox: usize,

        pub fn init(buffer: []u8) Self {
            return .{
                .fba = std.heap.FixedBufferAllocator.init(buffer),
                .one_percent_aprox = @intFromFloat(@as(f32, @floatFromInt(buffer.len))/100.0),
            };
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .free = free,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            var self = ptrCast(Self, ctx);
            const res = self.fba.allocator().rawAlloc(len, ptr_align, ret_addr);
            if (log) std.log.debug("Allocator " ++ name ++ " alloc {} ({}%) at {any}", .{len, @divFloor(len, self.one_percent_aprox), res});
            return res;
        }

        fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            var self = ptrCast(Self, ctx);
            const res = self.fba.allocator().rawResize(buf, buf_align, new_len, ret_addr);
            if (log) std.log.debug("Allocator " ++ name ++ " resize from {} ({}%) at {any} to {} ({}%): {s}", .{buf.len, @divFloor(buf.len, self.one_percent_aprox), buf.ptr, new_len, @divFloor(new_len, self.one_percent_aprox), if (res) "success" else "fail"});
            return res;
        }

        fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            var self = ptrCast(Self, ctx);
            const is_last_allocation = self.fba.isLastAllocation(buf);
            if (log) if (is_last_allocation) {
                std.log.debug("Allocator " ++ name ++ " free {} ({}%) bytes at {any}", .{buf.len, @divFloor(buf.len, self.one_percent_aprox), buf.ptr});
            }
            else {
                std.log.debug("Allocator " ++ name ++ " free {} ({}%) bytes at {any} (will not free!)", .{buf.len, @divFloor(buf.len, self.one_percent_aprox), buf.ptr});
            };
            self.fba.allocator().rawFree(buf, buf_align, ret_addr);
        }

        fn ptrCast(comptime T: type, ptr: *anyopaque) *T {
            if (@alignOf(T) == 0) @compileError(@typeName(T));
            return @ptrCast(@alignCast(ptr));
        }
    };

}

const waveout = struct {

    const Strings = struct {
        data: std.ArrayList(u8),
        strings: std.ArrayList([]u8),
        pub fn deinit(self: *Strings) void {
            self.strings.deinit();
            self.data.deinit();
        }
    };
    
    pub fn enumerate_sound_devices(allocator: std.mem.Allocator) !Strings {

        // https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutgetnumdevs
        const device_count = win32.waveOutGetNumDevs();
        if (device_count == 0) return error.NoSoundDevicesOrErrorHappened;

        // https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutgetdevcaps
        var string_data = try std.ArrayList(u8).initCapacity(allocator, 32*16);
        var strings = try std.ArrayList([]u8).initCapacity(allocator, 16);
        var i: u32 = 0;
        while (i < device_count) : (i += 1) {
            var capabilities: win32.WAVEOUTCAPSA = undefined;
            switch(win32.waveOutGetDevCapsA(i, &capabilities, @sizeOf(win32.WAVEOUTCAPSA))) {
                win32.MMSYSERR_NOERROR => {},
                win32.MMSYSERR_BADDEVICEID => {std.log.err("waveOutGetDevCapsA on sound device {}: Specified device identifier is out of range.", .{i});},
                win32.MMSYSERR_NODRIVER => {std.log.err("waveOutGetDevCapsA on sound device {}: No device driver is present.", .{i});},
                win32.MMSYSERR_NOMEM => {std.log.err("waveOutGetDevCapsA on sound device {}: Unable to allocate or lock memory.", .{i});},
                else => unreachable
            }
            const lenght = blk: {
                for (&capabilities.szPname, 0..) |b, l| if (b == 0) break :blk l;
                break :blk 32;
            };
            const str = try string_data.addManyAsSlice(lenght);
            @memcpy(str, capabilities.szPname[0..lenght]);
            try strings.append(str);
        }

        return .{
            .data = string_data,
            .strings = strings
        };
        
    }

    const SampleType = i16;

    const Context = struct {
        waveout_handle: win32.HWAVEOUT,
        waveout_config: Config,
        sample_buffer: []SampleType,
        sample_block_current_index: usize,
        sample_block_descriptors: []win32.WAVEHDR,
        // TODO if I ever allow ready to be false then I might need to make this atomic??
        ready: bool,
        
        sample_block_free_count: usize,
        sample_block_free_count_mutex: std.Thread.Mutex,
        sample_block_free_count_condition: std.Thread.Condition,
        
        thread: std.Thread,
    };
    
    var context: Context = undefined;

    var number: SampleType = 0;
    
    /// returns -1 to +1
    fn default(time: f64) f64 {
        switch (3) {
            0 => {
                const max: f64 = std.math.maxInt(SampleType)/2;
                const sin: f64 = std.math.sin(time)+1;
                const val: SampleType = @intFromFloat(sin*max);
                return val;
            },
            1 => {
                return 0;
            },
            2 => {
                number, _ = @addWithOverflow(number, 1);
                return number;
            },
            3 => {
                
                // |   |   |   |   |   | |   |   |   |   | |   | |   |   |   |
                // |   | S |   |   | F | | G |   |   | J | | K | | L |   |   |
                // |   |___|   |   |___| |___|   |   |___| |___| |___|   |   |__
                // |     |     |     |     |     |     |     |     |     |     |
                // |  Z  |  X  |  C  |  V  |  B  |  N  |  M  |  ,  |  .  |  /  |
                // |_____|_____|_____|_____|_____|_____|_____|_____|_____|_____|
                //    Z  S  X     C  F  V  G  B     N  J  M  K  ,  L  .     /
                //    0  1  2     3  4  5  6  7     8  9  10 11 12 13 14    15
                const key = 15;
                const octave_base_frequency: f64 = 110; // A2
                const _12th_root_of_2: f64 = std.math.pow(f64, 2, 1/12);
                const frequency_output: f64 = std.math.pow(f64, _12th_root_of_2, key) * octave_base_frequency;
                return std.math.sin(time * 2 * 3.14159 * frequency_output * 0.5);
            },
            4 => {
                return 0;
            },
            else => unreachable
        }
    }
    
    pub const Config = struct {
        // TODO WAVE_MAPPER points to default syste, sound device or something like that, look into that
        device_index: u32 = 0,
        samples_per_second: usize = 44100,
        channels: usize = 1,
        block_count: usize = 8,
        block_sample_count: usize = 256,
        user_callback: *const fn (time: f64) f64 = &default,
    };

    fn waveOutProc(hwo: win32.HWAVEOUT, uMsg: u32, dwInstance: *u32, dwParam1: *u32, dwParam2: *u32) void {
        _ = hwo;
        _ = dwInstance;
        _ = dwParam1;
        _ = dwParam2;

        // NOTE we get many kind of events but for now we just care about `WOM_DONE`, which is the
        // event that lets us know that a block of samples has been processed.
        if (uMsg != win32.MM_WOM_DONE) return;
        
        context.sample_block_free_count_mutex.lock();
        context.sample_block_free_count += 1;
        context.sample_block_free_count_condition.signal();
        context.sample_block_free_count_mutex.unlock();
    }
    
    pub fn waveout_setup(allocator: std.mem.Allocator, config: Config) !void {

        var waveout_desired_format: win32.WAVEFORMATEX = undefined;
        waveout_desired_format.wFormatTag = win32.WAVE_FORMAT_PCM;
        waveout_desired_format.nSamplesPerSec = @intCast(config.samples_per_second);
        waveout_desired_format.wBitsPerSample = @sizeOf(SampleType) * 8;
        // TODO implement channels
        // waveout_desired_format.nChannels = config.channels;
        waveout_desired_format.nChannels = 1;
        waveout_desired_format.nBlockAlign = @divExact(waveout_desired_format.wBitsPerSample, 8) * waveout_desired_format.nChannels;
        waveout_desired_format.nAvgBytesPerSec = waveout_desired_format.nSamplesPerSec * waveout_desired_format.nBlockAlign;
        waveout_desired_format.cbSize = 0;
        
        var waveout_handle: ?win32.HWAVEOUT = undefined;
        switch (win32.waveOutOpen(&waveout_handle, config.device_index, &waveout_desired_format, @intFromPtr(&waveOutProc), 0, win32.CALLBACK_FUNCTION)) {
            win32.MMSYSERR_NOERROR => {},
            win32.MMSYSERR_ALLOCATED => {std.log.err("Specified resource is already allocated.", .{});},
            win32.MMSYSERR_BADDEVICEID => {std.log.err("Specified device identifier is out of range.", .{});},
            win32.MMSYSERR_NODRIVER => {std.log.err("No device driver is present.", .{});},
            win32.MMSYSERR_NOMEM => {std.log.err("Unable to allocate or lock memory.", .{});},
            win32.WAVERR_BADFORMAT => {std.log.err("Attempted to open with an unsupported waveform-audio format.", .{});},
            win32.WAVERR_SYNC => {std.log.err("The device is synchronous but waveOutOpen was called without using the WAVE_ALLOWSYNC flag.", .{});},
            else => unreachable
        }

        const waveout_sample_buffer = try allocator.alloc(SampleType, config.block_count * config.block_sample_count);
        @memset(waveout_sample_buffer, 0);
        const waveout_block_descriptors = try allocator.alloc(win32.WAVEHDR, config.block_count);
        @memset(waveout_block_descriptors, std.mem.zeroes(win32.WAVEHDR));
        for (waveout_block_descriptors, 0..) |*descriptor, i| {
            descriptor.dwBufferLength = @intCast(config.block_sample_count * @sizeOf(SampleType));
            descriptor.lpData = @ptrCast(&waveout_sample_buffer[i*config.block_sample_count]);
        }

        context.sample_buffer = waveout_sample_buffer;
        context.sample_block_descriptors = waveout_block_descriptors;
        context.sample_block_free_count = config.block_count;
        context.waveout_config = config;
        context.ready = true;
        context.waveout_handle = waveout_handle.?;
        context.sample_block_current_index = 0;
        context.sample_block_free_count_mutex = .{};
        context.sample_block_free_count_condition = .{};
        // TODO use win32 API for threading rather than relying on zig
        context.thread = try std.Thread.spawn(
            std.Thread.SpawnConfig {
                .allocator = allocator,
                .stack_size = 16*1024*1024
            },
            sound_thread,
            .{}
        );
    }

    fn sound_thread() void {
        const seconds_per_sample: f64 = 1/@as(f64, @floatFromInt(context.waveout_config.samples_per_second));
        var time: f64 = 0;
        while (context.ready) {

            context.sample_block_free_count_mutex.lock();
            if (context.sample_block_free_count == 0) {
                context.sample_block_free_count_condition.wait(&context.sample_block_free_count_mutex);
            }
            context.sample_block_free_count -= 1;
            context.sample_block_free_count_mutex.unlock();

            if (context.sample_block_descriptors[context.sample_block_current_index].dwFlags & win32.WHDR_PREPARED != 0) {
                switch (win32.waveOutUnprepareHeader(context.waveout_handle, &context.sample_block_descriptors[context.sample_block_current_index], @sizeOf(win32.WAVEHDR))) {
                    win32.MMSYSERR_NOERROR => {},
                    win32.MMSYSERR_INVALHANDLE => {std.log.err("Specified device handle is invalid.", .{});},
                    win32.MMSYSERR_NODRIVER => {std.log.err("No device driver is present.", .{});},
                    win32.MMSYSERR_NOMEM => {std.log.err("Unable to allocate or lock memory.", .{});},
                    win32.WAVERR_STILLPLAYING => {std.log.err("The data block pointed to by the pwh parameter is still in the queue.", .{});},
                    else => unreachable
                }
            }

            // TODO factor in that there might be more than 1 channel
            const index_of_first_sample = context.sample_block_current_index * context.waveout_config.block_sample_count;
            const sample_block: []SampleType = context.sample_buffer[index_of_first_sample .. index_of_first_sample + context.waveout_config.block_sample_count];
            for (sample_block) |*sample| {
                const max_sample_as_f64 = @as(f64, @floatFromInt(std.math.maxInt(SampleType)));
                const new_sample = std.math.clamp(context.waveout_config.user_callback(time), -1, 1);
                sample.* = @intFromFloat(new_sample * max_sample_as_f64);
                time += seconds_per_sample;
            }

            switch (win32.waveOutPrepareHeader(context.waveout_handle, &context.sample_block_descriptors[context.sample_block_current_index], @sizeOf(win32.WAVEHDR))) {
                win32.MMSYSERR_NOERROR => {},
                win32.MMSYSERR_INVALHANDLE => {std.log.err("Specified device handle is invalid.", .{});},
                win32.MMSYSERR_NODRIVER => {std.log.err("No device driver is present.", .{});},
                win32.MMSYSERR_NOMEM => {std.log.err("Unable to allocate or lock memory.", .{});},
                else => unreachable
            }

            switch (win32.waveOutWrite(context.waveout_handle, &context.sample_block_descriptors[context.sample_block_current_index], @sizeOf(win32.WAVEHDR))) {
                win32.MMSYSERR_NOERROR => {},
                win32.MMSYSERR_INVALHANDLE => {std.log.err("Specified device handle is invalid.", .{});},
                win32.MMSYSERR_NODRIVER => {std.log.err("No device driver is present.", .{});},
                win32.MMSYSERR_NOMEM => {std.log.err("Unable to allocate or lock memory.", .{});},
                win32.WAVERR_UNPREPARED => {std.log.err("The data block pointed to by the pwh parameter hasn't been prepared.", .{});},
                else => unreachable
            }

            context.sample_block_current_index = @mod(context.sample_block_current_index+1, context.waveout_config.block_count);
        }
    }
};