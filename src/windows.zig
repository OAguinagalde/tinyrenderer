const std = @import("std");

const math = @import("math.zig");
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vector4f = math.Vector4f;
const M44 = math.M44;
const Plane = math.Plane;
const Frustum = math.Frustum;
const win32 = @import("win32.zig");
const OBJ = @import("obj.zig");
const TGA = @import("tga.zig");
const imgui = @import("imgui.zig");
const Buffer2D = @import("buffer.zig").Buffer2D;

const Camera = struct {
    position: Vector3f,
    direction: Vector3f,
    looking_at: Vector3f,
    up: Vector3f,
};

pub const RGBA = extern struct {
    r: u8 align(1),
    g: u8 align(1),
    b: u8 align(1),
    a: u8 align(1),
    comptime { std.debug.assert(@sizeOf(@This()) == 4); }
    pub fn scale(self: RGBA, factor: f32) RGBA {
        return RGBA {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
            .a = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.a)) * factor))),
        };
    }
    pub fn add(c1: RGBA, c2: RGBA) RGBA {
        const result = RGBA {
            .r = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.r))/255 + @as(f32, @floatFromInt(c2.r))/255)*255))),
            .g = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.g))/255 + @as(f32, @floatFromInt(c2.g))/255)*255))),
            .b = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.b))/255 + @as(f32, @floatFromInt(c2.b))/255)*255))),
            .a = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.a))/255 + @as(f32, @floatFromInt(c2.a))/255)*255))),
        };
        return result;
    }
    pub fn scale_raw(self: RGBA, factor: f32) RGBA {
        return RGBA {
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * factor),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * factor),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * factor),
            .a = @intFromFloat(@as(f32, @floatFromInt(self.a)) * factor),
        };
    }
    /// This assumes that the sum of any channel is inside the range of u8, there is no checks!
    pub fn add_raw(c1: RGBA, c2: RGBA) RGBA {
        const result = RGBA {
            .r = c1.r + c2.r,
            .g = c1.g + c2.g,
            .b = c1.b + c2.b,
            .a = c1.a + c2.a,
        };
        return result;
    }
    /// where `c2` is the background color
    /// https://learnopengl.com/Advanced-OpenGL/Blending
    pub fn blend(c1: RGBA, c2: RGBA) RGBA {
        const a1: f32 = @as(f32, @floatFromInt(c1.a)) / 255;
        const result = RGBA {
            .r = @intFromFloat((@as(f32, @floatFromInt(c1.r))/255*a1 + @as(f32, @floatFromInt(c2.r))/255*(1-a1))*255),
            .g = @intFromFloat((@as(f32, @floatFromInt(c1.g))/255*a1 + @as(f32, @floatFromInt(c2.g))/255*(1-a1))*255),
            .b = @intFromFloat((@as(f32, @floatFromInt(c1.b))/255*a1 + @as(f32, @floatFromInt(c2.b))/255*(1-a1))*255),
            .a = @intFromFloat((@as(f32, @floatFromInt(c1.a))/255*a1 + @as(f32, @floatFromInt(c2.a))/255*(1-a1))*255),
        };
        return result;
    }
    pub fn multiply(c1: RGBA, c2: RGBA) RGBA {
        const result = RGBA {
            .r = @intFromFloat( @as(f32, @floatFromInt(c1.r)) * (@as(f32, @floatFromInt(c2.r)) / 255)),
            .g = @intFromFloat( @as(f32, @floatFromInt(c1.g)) * (@as(f32, @floatFromInt(c2.g)) / 255)),
            .b = @intFromFloat( @as(f32, @floatFromInt(c1.b)) * (@as(f32, @floatFromInt(c2.b)) / 255)),
            .a = @intFromFloat( @as(f32, @floatFromInt(c1.a)) * (@as(f32, @floatFromInt(c2.a)) / 255)),
        };
        return result;
    }
    pub fn mean(c1: RGBA, c2: RGBA, c3: RGBA, c4: RGBA) RGBA {
        return RGBA {
            .r = @as(u8, @intCast((@as(u16, @intCast(c1.r)) + @as(u16, @intCast(c2.r)) + @as(u16, @intCast(c3.r)) + @as(u16, @intCast(c4.r))) / 4)),
            .g = @as(u8, @intCast((@as(u16, @intCast(c1.g)) + @as(u16, @intCast(c2.g)) + @as(u16, @intCast(c3.g)) + @as(u16, @intCast(c4.g))) / 4)),
            .b = @as(u8, @intCast((@as(u16, @intCast(c1.b)) + @as(u16, @intCast(c2.b)) + @as(u16, @intCast(c3.b)) + @as(u16, @intCast(c4.b))) / 4)),
            .a = @as(u8, @intCast((@as(u16, @intCast(c1.a)) + @as(u16, @intCast(c2.a)) + @as(u16, @intCast(c3.a)) + @as(u16, @intCast(c4.a))) / 4)),
        };
    }
};

pub const RGB = extern struct {
    r: u8 align(1),
    g: u8 align(1),
    b: u8 align(1),
    comptime { std.debug.assert(@sizeOf(@This()) == 3); }
    pub fn scale(self: RGB, factor: f32) RGB {
        return RGB {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
        };
    }
    pub fn scale_raw(self: RGB, factor: f32) RGB {
        return RGB {
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * factor),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * factor),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * factor),
        };
    }
    /// This assumes that the sum of any channel is inside the range of u8, there is no checks!
    pub fn add_raw(c1: RGB, c2: RGB) RGB {
        const result = RGB {
            .r = c1.r + c2.r,
            .g = c1.g + c2.g,
            .b = c1.b + c2.b,
        };
        return result;
    }
};

const imgui_win32_impl = struct {

    const Context = struct {
        hWnd: win32.c.HWND,
        Time: i64,
        TicksPerSecond: i64,
    };
    
    fn init(context: *Context, window_handle: win32.c.HWND, out_font_texture: *Buffer2D(RGBA)) void {
        const io = imgui.c.igGetIO();        
        io.*.BackendPlatformUserData = context;
        context.hWnd = window_handle;
        var counter: win32.c.LARGE_INTEGER = undefined;
        var performance_frequency: win32.c.LARGE_INTEGER = undefined;
        _ = win32.c.QueryPerformanceCounter(&counter);
        _ = win32.c.QueryPerformanceFrequency(&performance_frequency);
        context.TicksPerSecond = performance_frequency.QuadPart;
        context.Time = counter.QuadPart;

        const main_viewport = imgui.c.igGetMainViewport();
        main_viewport.*.PlatformHandle = window_handle;
        main_viewport.*.PlatformHandleRaw = window_handle;

        var out_width: i32 = undefined;
        var out_height: i32 = undefined;
        var out_bytes_per_pixel: i32 = undefined;
        var out_pixels: [*c]u8 = undefined;
        imgui.c.ImFontAtlas_GetTexDataAsRGBA32(io.*.Fonts, &out_pixels, &out_width, &out_height, &out_bytes_per_pixel);

        const total_size: usize = @intCast(out_width * out_height);
        out_font_texture.* = Buffer2D(RGBA).from(std.mem.bytesAsSlice(RGBA, @as([]u8, @ptrCast(out_pixels[0..total_size]))), @intCast(out_width));
        imgui.c.ImFontAtlas_SetTexID(io.*.Fonts, out_font_texture);
    }

    fn render_draw_data(pixel_buffer: Buffer2D(win32.RGBA)) void {
        const draw_data = imgui.c.igGetDrawData();
        const clip_offset = draw_data.*.DisplayPos;
        const pos = Vector2f { .x = draw_data.*.DisplayPos.x, .y = draw_data.*.DisplayPos.y };
        const dimensions = Vector2f { .x = draw_data.*.DisplaySize.x, .y = draw_data.*.DisplaySize.y };
        // In DearImgui 0, 0 is the top left corner but on this renderer is bottom left, so I make the projection matrix with "top" and "bottom"
        // inverted so that they every point trasformed by it has its y coordinate inverted
        const projection_matrix = M44.orthographic_projection(pos.x, pos.x + dimensions.x, pos.y, pos.y + dimensions.y, 0, 10);
        const viewport_matrix = M44.viewport_2(pos.x, pos.y, dimensions.x, dimensions.y, 255);
        if (draw_data.*.CmdLists.Data == null) return;
        const command_lists = imgui.im_vector_from(draw_data.*.CmdLists);
        const command_lists_count: usize = @intCast(draw_data.*.CmdListsCount);
        for (command_lists.data[0..command_lists_count]) |command_list| {
            const command_buffer = imgui.im_vector_from(command_list.*.CmdBuffer);
            const vertex_buffer = imgui.im_vector_from(command_list.*.VtxBuffer);
            const index_buffer = imgui.im_vector_from(command_list.*.IdxBuffer);
            for (command_buffer.used_slice()) |command| {
                const clip_min = Vector2f { .x = command.ClipRect.x - clip_offset.x, .y = command.ClipRect.y - clip_offset.y };
                const clip_max = Vector2f { .x = command.ClipRect.z - clip_offset.x, .y = command.ClipRect.w - clip_offset.y };
                const clip = Vector4f { .x = clip_min.x, .y = clip_max.y, .z = clip_max.x, .w = clip_min.y };
                if (clip_max.x <= clip_min.x or clip_max.y <= clip_min.y) continue;
                const texture: *Buffer2D(RGBA) = @as(*Buffer2D(RGBA), @alignCast(@ptrCast(command.TextureId.?)));
                std.debug.assert(texture == &state.imgui_font_texture);
                const vertex_data: []const imgui_renderer.Vertex = std.mem.bytesAsSlice(imgui_renderer.Vertex, std.mem.sliceAsBytes(vertex_buffer.used_slice()))[command.VtxOffset..];
                const render_context = imgui_renderer.Context {
                    .texture = texture.*,
                    .texture_width = texture.width,
                    .texture_height = texture.height,
                    .projection_matrix = projection_matrix,
                };
                const render_requirements = imgui_renderer.pipeline_configuration.Requirements() {
                    .viewport_matrix = viewport_matrix,
                    .index_buffer = index_buffer.used_slice()[command.IdxOffset..],
                    .scissor_rect = clip,
                };
                imgui_renderer.Pipeline.render(pixel_buffer, render_context, vertex_data, command.ElemCount / 3, render_requirements);
            }
        }
    }

    fn setup_new_frame(context: *Context) void {
        const io = imgui.c.igGetIO();

        var mouse_current: win32.c.POINT = undefined;
        _ = win32.c.GetCursorPos(&mouse_current);

        imgui.c.ImGuiIO_AddMousePosEvent(io,
            @as(f32, @floatFromInt(mouse_current.x)),
            @as(f32, @floatFromInt(mouse_current.y))
        );
        
        var rect: win32.c.RECT = undefined;
        _ = win32.c.GetClientRect(context.hWnd, &rect);
        const client_width = rect.right - rect.left;
        const client_height = rect.bottom - rect.top;

        io.*.DisplaySize = imgui.c.ImVec2 { .x = @floatFromInt(client_width), .y = @floatFromInt(client_height) };

        var current_time: win32.c.LARGE_INTEGER = undefined;
        _ = win32.c.QueryPerformanceCounter(&current_time);
        io.*.DeltaTime = @as(f32, @floatFromInt(current_time.QuadPart - context.Time)) / @as(f32, @floatFromInt(context.TicksPerSecond));
        context.Time = current_time.QuadPart;
    }

};

const State = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    render_target: win32.c.BITMAPINFO,
    pixel_buffer: Buffer2D(win32.RGBA),
    running: bool,
    mouse: Vector2i,
    keys: [256]bool,
    
    depth_buffer: Buffer2D(f32),
    texture: Buffer2D(RGB),
    vertex_buffer: []f32,
    camera: Camera,
    view_matrix: M44,
    viewport_matrix: M44,
    projection_matrix: M44,
    time: f64,
    
    imgui_platform_context: imgui_win32_impl.Context,
    imgui_font_texture: Buffer2D(RGBA),
};

var state = State {
    .x = 10,
    .y = 10,
    // .w = 1000,
    .w = 600,
    // .h = 1000,
    .h = 500,
    .render_target = undefined,
    .pixel_buffer = undefined,
    .running = true,
    .mouse = undefined,
    .keys = [1]bool{false} ** 256,
    
    .depth_buffer = undefined,
    .texture = undefined,
    .vertex_buffer = undefined,
    .camera = undefined,
    .view_matrix = undefined,
    .viewport_matrix = undefined,
    .projection_matrix = undefined,
    .time = undefined,
    
    .imgui_font_texture = undefined,
    .imgui_platform_context = undefined,
};

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

    state.pixel_buffer.data = try allocator.alloc(win32.RGBA, @intCast(state.w * state.h));
    state.pixel_buffer.width = @intCast(state.w);
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

        // Initialize the application state
        {
            // Create the z-buffer
            state.depth_buffer = Buffer2D(f32).from(try allocator.alloc(f32, @intCast(state.w * state.h)), @intCast(state.w));
            
            // Initialize the imgui stuff
            const imgui_context = imgui.c.igCreateContext(null);
            _ = imgui_context;
            imgui_win32_impl.init(&state.imgui_platform_context, window_handle, &state.imgui_font_texture);

            // Load the diffuse texture data
            state.texture = TGA.from_file(RGB, allocator, "res/african_head_diffuse.tga")
                catch |err| { std.debug.print("error reading `res/african_head_diffuse.tga` {?}", .{err}); return; };
            
            state.vertex_buffer = OBJ.from_file(allocator, "res/african_head.obj")
                catch |err| { std.debug.print("error reading `res/african_head.obj` {?}", .{err}); return; };

            state.camera.position = Vector3f { .x = 0, .y = 0, .z = 0 };
            state.camera.up = Vector3f { .x = 0, .y = 1, .z = 0 };
            state.camera.direction = Vector3f { .x = 0, .y = 0, .z = 1 };

            state.time = 0;
        }

        // Deinitialize the application state
        defer {
            allocator.free(state.depth_buffer.data);
            allocator.free(state.texture.data);
            allocator.free(state.vertex_buffer);
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

        { // Set the initial mouse state to wherever the mouse is when the app is initialized
            var mouse_current: win32.c.POINT = undefined;
            _ = win32.c.GetCursorPos(&mouse_current);
            state.mouse.x = mouse_current.x;
            state.mouse.y = mouse_current.y;
        }

        // var open: bool = true;
        while (state.running) {

            // imgui_win32_impl.setup_new_frame(&state.imgui_platform_context);
            // imgui.c.igNewFrame();

            var fps: i64 = undefined;
            var ms: f64 = undefined;
            { // calculate fps and ms
                var new_counter: win32.c.LARGE_INTEGER = undefined;
                _ = win32.c.QueryPerformanceCounter(&new_counter);
                var counter_difference = new_counter.QuadPart - cpu_counter;
                // TODO sometimes it comes out as 0????? not sure why but its not important right now
                if (counter_difference == 0) counter_difference = 1;
                ms = 1000.0 * @as(f64, @floatFromInt(counter_difference)) / @as(f64, @floatFromInt(cpu_frequency_seconds));
                fps = @divFloor(cpu_frequency_seconds, counter_difference);
                cpu_counter = new_counter.QuadPart;
            }
            const counted_since_start = cpu_counter - cpu_counter_first;
            _ = counted_since_start;

            { // windows message loop
                var message: win32.c.MSG = undefined;
                while (win32.c.PeekMessageW(&message, null,  0, 0, .REMOVE) != @intFromEnum(win32.c.False)) {
                    _ = win32.c.TranslateMessage(&message);
                    _ = win32.c.DispatchMessageW(&message);

                    // TODO Any windows messages that the application needs to read should happen here
                    switch (message.message) {
                        win32.c.WM_QUIT => state.running = false,
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

            const mouse_previous = state.mouse;
            var mouse_current: win32.c.POINT = undefined;
            _ = win32.c.GetCursorPos(&mouse_current);
            const factor: f32 = 0.02;
            const mouse_dx: f32 = @as(f32, @floatFromInt(mouse_current.x - mouse_previous.x)) * factor;
            const mouse_dy: f32 = @as(f32, @floatFromInt(mouse_current.y - mouse_previous.y)) * factor;
            state.mouse.x = mouse_current.x;
            state.mouse.y = mouse_current.y;

            var app_close_requested = false;
            { // tick / update
                
                // const white = win32.rgb(255, 255, 255);
                const red = win32.rgb(255, 0, 0);
                // const green = win32.rgb(0, 255, 0);
                const blue = win32.rgb(0, 0, 255);
                // const turquoise = win32.rgb(0, 255, 255);
                
                // Clear the screen and the zbuffer
                state.pixel_buffer.clear(win32.rgb(100, 149, 237));
                state.depth_buffer.clear(999999);

                if (state.keys['T']) state.time += ms;

                // camera movement with mouse
                const mouse_sensitivity = 0.60;
                const up = Vector3f {.x = 0, .y = 1, .z = 0 };
                const real_right = state.camera.direction.cross_product(up).normalized();
                const real_up = state.camera.direction.cross_product(real_right).scale(-1).normalized();
                if (mouse_dx != 0 or mouse_dy != 0) {
                    state.camera.direction = state.camera.direction.add(real_right.scale(mouse_dx*mouse_sensitivity));
                    if (state.camera.direction.y < 0.95 and state.camera.direction.y > -0.95) {
                        state.camera.direction = state.camera.direction.add(real_up.scale(-mouse_dy*mouse_sensitivity));
                    }
                    state.camera.direction.normalize();
                }
                
                // camera position with AWSD and QE
                if (state.keys['W']) state.camera.position = state.camera.position.add(state.camera.direction.scale(0.02));
                if (state.keys['S']) state.camera.position = state.camera.position.add(state.camera.direction.scale(-0.02));
                if (state.keys['A']) state.camera.position = state.camera.position.add(real_right.scale(-0.02));
                if (state.keys['D']) state.camera.position = state.camera.position.add(real_right.scale(0.02));
                if (state.keys['Q']) state.camera.position.y += 0.02;
                if (state.keys['E']) state.camera.position.y -= 0.02;

                // calculate view_matrix, projection_matrix and viewport_matrix
                const looking_at: Vector3f = state.camera.position.add(state.camera.direction);                
                state.view_matrix = M44.lookat_right_handed(state.camera.position, looking_at, Vector3f.from(0, 1, 0));
                const aspect_ratio = @as(f32, @floatFromInt(client_width)) / @as(f32, @floatFromInt(client_height));
                state.projection_matrix = M44.perspective_projection(60, aspect_ratio, 0.1, 5);
                state.viewport_matrix = M44.viewport_i32_2(0, 0, client_width, client_height, 255);

                // Example rendering OBJ model with Gouraud Shading
                if (true) {
                    const horizontally_spinning_position = Vector3f { .x = std.math.cos(@as(f32, @floatCast(state.time)) / 2000), .y = 0, .z = std.math.sin(@as(f32, @floatCast(state.time)) / 2000) };
                    const render_context = gouraud_renderer.Context {
                        .light_position_camera_space = state.view_matrix.apply_to_vec3(horizontally_spinning_position).discard_w(),
                        .projection_matrix = state.projection_matrix,
                        .texture = state.texture,
                        .texture_height = state.texture.height,
                        .texture_width = state.texture.width,
                        .view_model_matrix = state.view_matrix.multiply(
                            M44.translation(Vector3f { .x = 0, .y = 0, .z = 4 }).multiply(M44.scaling_matrix(Vector3f.from(0.5, 0.5, -0.5)))
                        ),
                    };
                    var i: usize = 0;
                    var vertex_buffer = std.ArrayList(gouraud_renderer.Vertex).initCapacity(allocator, @divExact(state.vertex_buffer.len, 8)) catch unreachable;
                    while (i < state.vertex_buffer.len) : (i = i + 8) {
                        const pos: Vector3f = .{ .x=state.vertex_buffer[i+0], .y=state.vertex_buffer[i+1], .z=state.vertex_buffer[i+2] };
                        const uv: Vector2f = .{ .x=state.vertex_buffer[i+3], .y=state.vertex_buffer[i+4] };
                        const normal: Vector3f = .{ .x=state.vertex_buffer[i+5], .y=state.vertex_buffer[i+6], .z=state.vertex_buffer[i+7] };
                        vertex_buffer.appendAssumeCapacity(.{ .pos = pos, .uv = uv, .normal = normal });
                    }
                    const render_requirements: gouraud_renderer.pipeline_configuration.Requirements() = .{
                        .depth_buffer = state.depth_buffer,
                        .viewport_matrix = state.viewport_matrix,
                    };
                    gouraud_renderer.Pipeline.render(state.pixel_buffer, render_context, vertex_buffer.items, @divExact(vertex_buffer.items.len, 3), render_requirements);
                }

                // render the model texture as a quad
                if (true) {
                    // const texture_data = state.texture.rgba.data;
                    const w: f32 = @floatFromInt(state.texture.width);
                    const h: f32 = @floatFromInt(state.texture.height);
                    var quad_context = quad_renderer(RGB, false).Context {
                        .texture = state.texture,
                        .texture_width = state.texture.width,
                        .texture_height = state.texture.height,
                        .projection_matrix =
                            state.projection_matrix.multiply(
                                state.view_matrix.multiply(
                                    M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1.5 }).multiply(M44.scale(1/w))
                                )
                            ),
                    };
                    const vertex_buffer = [_]quad_renderer(RGB, false).Vertex{
                        .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
                        .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=0} },
                        .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=1} },
                        .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=1} },
                    };
                    const index_buffer = [_]u16{0,1,2,0,2,3};
                    const requirements = quad_renderer(RGB, false).pipeline_configuration.Requirements() {
                        .depth_buffer = state.depth_buffer,
                        .viewport_matrix = state.viewport_matrix,
                        .index_buffer = &index_buffer,
                    };
                    quad_renderer(RGB, false).Pipeline.render(state.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
                }
                
                // render the font texture as a quad
                if (true) {
                    const texture = @import("font_embedded.zig");
                    const texture_data = texture.data;
                    const w: f32 = @floatFromInt(texture.width);
                    const h: f32 = @floatFromInt(texture.height);
                    var quad_context = quad_renderer(RGBA, false).Context {
                        .texture = Buffer2D(RGBA).from(@constCast(@ptrCast(&texture_data)), texture.width),
                        .texture_width = texture.width,
                        .texture_height = texture.height,
                        .projection_matrix =
                            state.projection_matrix.multiply(
                                state.view_matrix.multiply(
                                    M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1 }).multiply(M44.scale(1/@as(f32, @floatFromInt(texture.width))))
                                )
                            ),
                    };
                    const vertex_buffer = [_]quad_renderer(RGBA, false).Vertex{
                        .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
                        .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=0} },
                        .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=1} },
                        .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=1} },
                    };
                    const index_buffer = [_]u16{0,1,2,0,2,3};
                    const requirements = quad_renderer(RGBA, false).pipeline_configuration.Requirements() {
                        .depth_buffer = state.depth_buffer,
                        .viewport_matrix = state.viewport_matrix,
                        .index_buffer = &index_buffer,
                    };
                    quad_renderer(RGBA, false).Pipeline.render(state.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
                }

                // some debug information and stuff
                state.pixel_buffer.line(Vector2i { .x = 150, .y = 150 }, Vector2i { .x = 150 + @as(i32, @intFromFloat(50 * state.camera.direction.x)), .y = 150 + @as(i32, @intFromFloat(50 * state.camera.direction.y)) }, red);
                state.pixel_buffer.line(Vector2i { .x = 150, .y = 150 }, Vector2i { .x = 150 + @as(i32, @intFromFloat(50 * state.camera.direction.z)), .y = 150 }, blue);
                render_text(allocator, state.pixel_buffer, Vector2i { .x = 10, .y = client_height-10 }, "ms {d: <9.2}", .{ms});
                render_text(allocator, state.pixel_buffer, Vector2i { .x = 10, .y = client_height-22 }, "camera {d:.8}, {d:.8}, {d:.8}", .{state.camera.position.x, state.camera.position.y, state.camera.position.z});
                render_text(allocator, state.pixel_buffer, Vector2i { .x = 10, .y = client_height-10 - (12*2) }, "{d:.3}, {d:.3}, {d:.3}", .{real_right.x, real_right.y, real_right.z});
                render_text(allocator, state.pixel_buffer, Vector2i { .x = 10, .y = client_height-10 - (12*3) }, "d mouse {d:.8}, {d:.8}", .{mouse_dx, mouse_dy});
                render_text(allocator, state.pixel_buffer, Vector2i { .x = 10, .y = client_height-10 - (12*4) }, "direction {d:.8}, {d:.8}, {d:.8}", .{state.camera.direction.x, state.camera.direction.y, state.camera.direction.z});
                
                // imgui.c.igShowDemoWindow(&open);
                // _ = open;
                // imgui.c.igText("Hello, world");  
                // imgui.c.igEndFrame();
                // imgui.c.igRender();
                // imgui_win32_impl.render_draw_data(state.pixel_buffer);
            }

            state.running = state.running and !app_close_requested;
            if (state.running == false) continue;

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

fn render_text(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(win32.RGBA), pos: Vector2i, comptime format: []const u8, args: anytype) void {
    // bitmap font embedded in the executable
    const font = @import("font_embedded.zig");

    const texture = Buffer2D(RGBA).from(@constCast(@ptrCast(&font.data)), font.width);
    const context = text_renderer.Context {
        .texture = texture,
        .texture_width = texture.width,
        .texture_height = texture.height,
        .projection_matrix = M44.orthographic_projection(0, @floatFromInt(state.w), @floatFromInt(state.h), 0, 0, 10)
    };
    var text_buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&text_buffer);
    std.fmt.format(fbs.writer(), format, args) catch @panic("failed to format text while rendering it");
    const text = fbs.getWritten();

    var vertex_buffer = allocator.alloc(text_renderer.Vertex, text.len*4) catch unreachable;
    defer allocator.free(vertex_buffer);

    const char_width: i32 = 4;
    const char_height: i32 = 7;
    const size = 2;
    for (text, 0..) |c, i| {
        const x: i32 = pos.x + @as(i32, @intCast(i)) * char_width * size;
        const y: i32 = pos.y;
        
        const u_1: i32 = (c%16) * 8;
        const v_1: i32 = (c/16) * 8;
        const u_2: i32 = u_1 + char_width;
        const v_2: i32 = v_1 + char_height;

        const offset: usize = i*4;

        vertex_buffer[offset + 0] = .{
            .pos = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) },
            .uv = .{ .x = @floatFromInt(u_1), .y = @floatFromInt(v_1) },
        };
        vertex_buffer[offset + 1] = .{
            .pos = .{ .x = @floatFromInt(x + char_width * size), .y = @floatFromInt(y) },
            .uv = .{ .x = @floatFromInt(u_2), .y = @floatFromInt(v_1) },
        };
        vertex_buffer[offset + 2] = .{
            .pos = .{ .x = @floatFromInt(x + char_width * size), .y = @floatFromInt(y - char_height * size) },
            .uv = .{ .x = @floatFromInt(u_2), .y = @floatFromInt(v_2) },
        };
        vertex_buffer[offset + 3] = .{
            .pos = .{ .x = @floatFromInt(x), .y = @floatFromInt(y - char_height * size) },
            .uv = .{ .x = @floatFromInt(u_1), .y = @floatFromInt(v_2) },
        };
    }
    
    if (true) text_renderer.Pipeline.render(pixel_buffer, context, vertex_buffer[0..text.len*4], text.len * 2, .{ .viewport_matrix = state.viewport_matrix, });
}

const GraphicsPipelineConfiguration = struct {
    blend_with_background: bool = false,
    use_index_buffer_auto: bool = false,
    use_index_buffer: bool = false,
    do_triangle_clipping: bool = false,
    do_depth_testing: bool = false,
    do_perspective_correct_interpolation: bool = false,
    do_scissoring: bool = false,
    use_triangle_2: bool = false,
    /// for debugging purposes
    trace: bool = false,

    
    /// returns a comptime tpye (an struct, basically) which needs to be filled, and passed as a value to the render pipeline when calling `render`
    pub fn Requirements(comptime self: GraphicsPipelineConfiguration) type {
        var fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField {
            std.builtin.Type.StructField {
                .default_value = null,
                .is_comptime = false,
                .name = "viewport_matrix",
                .type = M44,
                .alignment = @alignOf(M44)
            },
        };
        if (self.use_index_buffer) {
            if (self.use_index_buffer_auto) @compileError("Only one option can be active: `use_index_buffer_auto`, or `use_index_buffer`");
            fields = fields ++ [_]std.builtin.Type.StructField {
                std.builtin.Type.StructField {
                    .default_value = null,
                    .is_comptime = false,
                    .name = "index_buffer",
                    .type = []const u16,
                    .alignment = @alignOf([]const u16)
                }
            };
        }
        if (self.do_depth_testing) fields = fields ++ [_]std.builtin.Type.StructField {
                std.builtin.Type.StructField {
                .default_value = null,
                .is_comptime = false,
                .name = "depth_buffer",
                .type = Buffer2D(f32),
                .alignment = @alignOf([]f32)
            }
        };
        if (self.do_scissoring) fields = fields ++ [_]std.builtin.Type.StructField {
                std.builtin.Type.StructField {
                .default_value = null,
                .is_comptime = false,
                .name = "scissor_rect",
                .type = Vector4f,
                .alignment = @alignOf(Vector4f)
            }
        };
        // TODO what exactly should I do with declarations?
        // according to the compiler, when I put any declaration whatsoever I ger `error: reified structs must have no decls`
        // not sure what that means
        var declarations: []const std.builtin.Type.Declaration = &[_]std.builtin.Type.Declaration {
            // .{ .name = "" },
        };
        const requirements = std.builtin.Type {
            .Struct = .{
                .is_tuple = false,
                .fields = fields,
                .layout = .Auto,
                .decls = declarations,
            }
        };
        return @Type(requirements);
    }
};

fn GraphicsPipeline(
    comptime final_color_type: type,
    comptime context_type: type,
    comptime invariant_type: type,
    comptime vertex_type: type,
    comptime pipeline_configuration: GraphicsPipelineConfiguration,
    comptime vertex_shader: fn(context: context_type, vertex_buffer: vertex_type, out_invariant: *invariant_type) Vector4f,
    comptime fragment_shader: fn(context: context_type, invariants: invariant_type) final_color_type,
) type {
    return struct {
        const Self = @This();
        fn render(pixel_buffer: Buffer2D(final_color_type), context: context_type, vertex_buffer: []const vertex_type, face_count: usize, requirements: pipeline_configuration.Requirements()) void {
            
            var face_index: usize = 0;
            label_outer: while (face_index < face_count) : (face_index += 1) {
                
                const vertex_count = if (pipeline_configuration.do_triangle_clipping) 4 else 3;

                // 0, 1 and 2 will be the original triangle vertices.
                // if there is clipping however
                var invariants: [vertex_count]invariant_type = undefined;
                var clip_space_positions: [vertex_count]Vector4f = undefined;
                var ndcs: [vertex_count]Vector3f = undefined;
                var tri: [vertex_count]Vector3f = undefined;
                var w_used_for_perspective_correction: [vertex_count]f32 = undefined;
                var depth: [vertex_count]f32 = undefined;
                var clipped_count: usize = 0;

                // pass all 3 vertices of this face through the vertex shader
                inline for(0..3) |i| {
                    const vertex_index = index: {
                        if (pipeline_configuration.use_index_buffer) break :index requirements.index_buffer[face_index * 3 + i]
                        else if (pipeline_configuration.use_index_buffer_auto) break :index
                            // Generates the sequence 0 1 2 0 2 3 4 5 6 4 6 7 8 9 10 8 10 11 ...
                            if (face_index%2==0) face_index * 2 + i else if (i==0) (face_index-1) * 2 else ((face_index-1) * 2) + i + 1
                        else break :index face_index * 3 + i;
                    };
                    const vertex_data: vertex_type = vertex_buffer[vertex_index];
                    // As far as I know, in your standard opengl vertex shader, the returned position is usually in
                    // clip space, which is a homogeneous coordinate system. The `w` will be used for perspective correction.
                    clip_space_positions[i] = vertex_shader(context, vertex_data, &invariants[i]);
                    // NOTE This is quivalent to checking whether a point is inside the NDC cube after perspective division
                    // 
                    //     if (ndc.x > 1 or ndc.x < -1 or ndc.y > 1 or ndc.y < -1 or ndc.z > 1 or ndc.z < 0) {
                    // 
                    // if (clip_space_positions.x > clip_space_positions.w or clip_space_positions.x < -clip_space_positions.w or
                    //     clip_space_positions.y > clip_space_positions.w or clip_space_positions.y < -clip_space_positions.w or
                    //     clip_space_positions.z > clip_space_positions.w or clip_space_positions.z < 0) {
                    // 
                    // }

                    const ndc = clip_space_positions[i].perspective_division();
                    ndcs[i] = ndc;
                    if (ndc.x > 1 or ndc.x < -1 or ndc.y > 1 or ndc.y < -1 or ndc.z > 1 or ndc.z < 0) {
                        if (pipeline_configuration.do_triangle_clipping) {
                            clipped_count += 1;
                            if (clipped_count == 3) continue :label_outer;
                        }
                        else continue :label_outer;
                    }
                    if (pipeline_configuration.do_depth_testing) depth[i] = ndc.z;
                    if (pipeline_configuration.do_perspective_correct_interpolation) w_used_for_perspective_correction[i] = clip_space_positions[i].w;
                    const screen_space_position = requirements.viewport_matrix.apply_to_vec3(ndc).perspective_division();
                    tri[i] = screen_space_position;
                }

                if (pipeline_configuration.do_triangle_clipping) {
                    if (clipped_count == 0) {
                        if (pipeline_configuration.use_triangle_2) rasterizers.rasterize_2(pixel_buffer, context, requirements, tri[0..3].*, depth[0..3].*, w_used_for_perspective_correction[0..3].*, invariants[0..3].*)
                        else rasterizers.rasterize_1(pixel_buffer, context, requirements, tri[0..3].*, depth[0..3].*, w_used_for_perspective_correction[0..3].*, invariants[0..3].*);
                        
                        // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(tri[0].x), .y = @intFromFloat(tri[0].y) }, Vector2i { .x = @intFromFloat(tri[1].x), .y = @intFromFloat(tri[1].y) }, .{.r = 255, .g = 0, .b = 0, .a = 255 });
                        // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(tri[1].x), .y = @intFromFloat(tri[1].y) }, Vector2i { .x = @intFromFloat(tri[2].x), .y = @intFromFloat(tri[2].y) }, .{.r = 255, .g = 0, .b = 0, .a = 255 });
                        // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(tri[2].x), .y = @intFromFloat(tri[2].y) }, Vector2i { .x = @intFromFloat(tri[0].x), .y = @intFromFloat(tri[0].y) }, .{.r = 255, .g = 0, .b = 0, .a = 255 });
                    }
                    else {
                        
                        trace("clipping", .{});
                        trace("clip space", .{});
                        trace_triangle_4(clip_space_positions[0..3].*);
                        trace("ndc", .{});
                        trace_triangle(ndcs[0..3].*);
                        trace_mat4(context.projection_matrix);

                        const left_bottom_near = comptime Vector3f.from(-1,-1,0);
                        const right_top_far = comptime Vector3f.from(1,1,1);
                        const frustum = comptime Frustum {
                            .left = Plane.from(left_bottom_near, Vector3f.from(1,0,0)),
                            .right = Plane.from(right_top_far, Vector3f.from(-1,0,0)),
                            .bottom = Plane.from(left_bottom_near, Vector3f.from(0,1,0)),
                            .top = Plane.from(right_top_far, Vector3f.from(0,-1,0)),
                            .near = Plane.from(left_bottom_near, Vector3f.from(0,0,1)),
                            .far = Plane.from(right_top_far, Vector3f.from(0,0,-1) ),
                        };

                        const VertexList = struct {
                            const VertexLinkedList = std.DoublyLinkedList(Vector3f);
                            data: std.ArrayList(VertexLinkedList.Node),
                            list: VertexLinkedList,
                            fn init(allocator: std.mem.Allocator) @This() {
                                return .{
                                    .data = std.ArrayList(VertexLinkedList.Node).initCapacity(allocator, 15) catch unreachable,
                                    .list = VertexLinkedList {}
                                };
                            }
                            fn add(self: *@This(), vertex: Vector3f) void {
                                const ptr = self.data.addOneAssumeCapacity();
                                ptr.* = .{ .data = vertex };
                                self.list.append(ptr);
                            }
                            fn clear(self: *@This()) void {
                                self.list = VertexLinkedList {};
                                self.data.clearRetainingCapacity();
                            }
                            fn free(self: *@This()) void {
                                self.data.clearAndFree();
                            }
                            fn first(self: @This()) ?*VertexLinkedList.Node {
                                return self.list.first;
                            }
                            fn last(self: @This()) ?*VertexLinkedList.Node {
                                return self.list.last;
                            }
                            fn pop_first(self: *@This()) Vector3f {
                                return self.list.popFirst().?.data;
                            }
                            fn next(self: *@This()) ?Vector3f {
                                return if (self.list.popFirst()) |n| n.data else null;
                            }
                            fn move_to_other(self: *@This(), other: *@This()) void {
                                while (self.list.popFirst()) |item| {
                                    other.add(item.data);
                                }
                                self.clear();
                            }
                        };

                        var vertex_list = VertexList.init(std.heap.c_allocator);
                        vertex_list.add(ndcs[0]);
                        vertex_list.add(ndcs[1]);
                        vertex_list.add(ndcs[2]);
                        defer vertex_list.free();
                        var temp_vertex_list = VertexList.init(std.heap.c_allocator);
                        defer temp_vertex_list.free();

                        // for each plane `p`
                        inline for (@typeInfo(Frustum).Struct.fields) |field| {
                            const p: Plane = @field(frustum, field.name);

                            // for each pair of vertices v1, v2
                            var v1 = vertex_list.last().?;
                            var v2 = vertex_list.first().?;
                            
                            // this is basically a `do {} while {}`
                            while (true) {
                                const v1_inside: bool = (p.classify_point(v1.data) != .negative);
                                const v2_inside: bool = (p.classify_point(v2.data) != .negative);
                                if (v2_inside != v1_inside) {
                                    temp_vertex_list.add(p.intersection(v1.data, v2.data));
                                }
                                if (v2_inside) {
                                    temp_vertex_list.add(v2.data);
                                }

                                if (v2 == vertex_list.last().?) break // break condition
                                else { // continue
                                    v1 = v2;
                                    v2 = v2.next.?;
                                }
                            }

                            vertex_list.clear();
                            temp_vertex_list.move_to_other(&vertex_list);
                        }

                        if (pipeline_configuration.trace) {
                            var count: usize = 0;
                            var n = vertex_list.first();
                            while (n) |node| {
                                count += 1 ;
                                n = node.next;
                            }
                            trace("clipped to {} vertices ({} triangles)", .{count, count-2});
                        }

                        const to_interpolate = struct {
                            depth: f32,
                            w_used_for_perspective_correction: f32,
                        };
                        const orig_triangle_data = [3]to_interpolate {
                            .{
                                .depth = depth[0],
                                .w_used_for_perspective_correction = w_used_for_perspective_correction[0],
                            },
                            .{
                                .depth = depth[1],
                                .w_used_for_perspective_correction = w_used_for_perspective_correction[1],
                            },
                            .{
                                .depth = depth[2],
                                .w_used_for_perspective_correction = w_used_for_perspective_correction[2],
                            },
                        };

                        const vertex_1: Vector3f = vertex_list.pop_first();
                        const screen_space_1 = requirements.viewport_matrix.apply_to_vec3(vertex_1).perspective_division();
                        
                        var vertex_2: Vector3f = vertex_list.pop_first();
                        var vertex_3: Vector3f = vertex_list.pop_first();

                        while (true) { // This is basically a `do {} while {}`
                            
                            trace_triangle([3]Vector3f{vertex_1, vertex_2, vertex_3});
                            
                            const screen_space_2 = requirements.viewport_matrix.apply_to_vec3(vertex_2).perspective_division();
                            const screen_space_3 = requirements.viewport_matrix.apply_to_vec3(vertex_3).perspective_division();

                            var a = screen_space_1;
                            a.z = 0;
                            var b = screen_space_2;
                            b.z = 0;
                            var c = screen_space_3;
                            c.z = 0;
                            const bar_a = barycentric(tri[0..3].*, a);
                            const bar_b = barycentric(tri[0..3].*, b);
                            const bar_c = barycentric(tri[0..3].*, c);

                            const interpolated_a: to_interpolate = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(to_interpolate, orig_triangle_data, w_used_for_perspective_correction[0..3].*, bar_a.x, bar_a.y, bar_a.z)
                                else interpolate(to_interpolate, orig_triangle_data, bar_a.x, bar_a.y, bar_a.z);
                            const interpolated_b: to_interpolate = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(to_interpolate, orig_triangle_data, w_used_for_perspective_correction[0..3].*, bar_b.x, bar_b.y, bar_b.z)
                                else interpolate(to_interpolate, orig_triangle_data, bar_b.x, bar_b.y, bar_b.z);
                            const interpolated_c: to_interpolate = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(to_interpolate, orig_triangle_data, w_used_for_perspective_correction[0..3].*, bar_c.x, bar_c.y, bar_c.z)
                                else interpolate(to_interpolate, orig_triangle_data, bar_c.x, bar_c.y, bar_c.z);
                            
                            const invariants_a = if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants[0..3].*, w_used_for_perspective_correction[0..3].*, bar_a.x, bar_a.y, bar_a.z)
                                else interpolate(invariant_type, invariants[0..3].*, bar_a.x, bar_a.y, bar_a.z);
                            const invariants_b = if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants[0..3].*, w_used_for_perspective_correction[0..3].*, bar_b.x, bar_b.y, bar_b.z)
                                else interpolate(invariant_type, invariants[0..3].*, bar_b.x, bar_b.y, bar_b.z);
                            const invariants_c = if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants[0..3].*, w_used_for_perspective_correction[0..3].*, bar_c.x, bar_c.y, bar_c.z)
                                else interpolate(invariant_type, invariants[0..3].*, bar_c.x, bar_c.y, bar_c.z);

                            // TODO I got two bugs!
                            // 1. Sometimes I get negative uvs not sure why, it only happens when I do perspective correction tho! (Actually I might be wrong about that and I might be getting it without the correction as well)
                            // 2. sometimes the NDC coordinates suddenly go from, say, 23, to -134. Usually when I am close to the clipped triangle and rotate the camera until I'm getting more paralel
                            // meaning that the resulting clipped triangle looks completely out of place. I'm not sure how to go about that

                            if (pipeline_configuration.use_triangle_2) rasterizers.rasterize_2(pixel_buffer, context, requirements, .{ screen_space_1, screen_space_2, screen_space_3 }, .{ interpolated_a.depth, interpolated_b.depth, interpolated_c.depth }, .{ interpolated_a.w_used_for_perspective_correction, interpolated_b.w_used_for_perspective_correction, interpolated_c.w_used_for_perspective_correction }, .{ invariants_a, invariants_b, invariants_c })
                            else rasterizers.rasterize_1(pixel_buffer, context, requirements, .{ screen_space_1, screen_space_2, screen_space_3 }, .{ interpolated_a.depth, interpolated_b.depth, interpolated_c.depth }, .{ interpolated_a.w_used_for_perspective_correction, interpolated_b.w_used_for_perspective_correction, interpolated_c.w_used_for_perspective_correction }, .{ invariants_a, invariants_b, invariants_c });

                            // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(screen_space_1.x), .y = @intFromFloat(screen_space_1.y) }, Vector2i { .x = @intFromFloat(screen_space_2.x), .y = @intFromFloat(screen_space_2.y) }, .{.r = 0, .g = 255, .b = 0, .a = 255 });
                            // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(screen_space_2.x), .y = @intFromFloat(screen_space_2.y) }, Vector2i { .x = @intFromFloat(screen_space_3.x), .y = @intFromFloat(screen_space_3.y) }, .{.r = 0, .g = 255, .b = 0, .a = 255 });
                            // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(screen_space_3.x), .y = @intFromFloat(screen_space_3.y) }, Vector2i { .x = @intFromFloat(screen_space_1.x), .y = @intFromFloat(screen_space_1.y) }, .{.r = 0, .g = 255, .b = 0, .a = 255 });

                            // raster the next triangle? or break if we have already drawn them all
                            if (vertex_list.next()) |next_vertex| {
                                vertex_2 = vertex_3;
                                vertex_3 = next_vertex;
                            }
                            else break;
                        }
                    }
                }
                else if (pipeline_configuration.use_triangle_2) rasterizers.rasterize_2(pixel_buffer, context, requirements, tri[0..3].*, depth[0..3].*, w_used_for_perspective_correction[0..3].*, invariants[0..3].*)
                else rasterizers.rasterize_1(pixel_buffer, context, requirements, tri[0..3].*, depth[0..3].*, w_used_for_perspective_correction[0..3].*, invariants[0..3].*);
            }
        }
    
        const rasterizers = struct {
            fn rasterize_2(pixel_buffer: Buffer2D(final_color_type), context: context_type, requirements: pipeline_configuration.Requirements(), tri: [3]Vector3f, depth: [3]f32, w_used_for_perspective_correction: [3]f32, invariants: [3]invariant_type) void {
                
                const a = &tri[0];
                const b = &tri[1];
                const c = &tri[2];

                var top: *const Vector3f = &tri[0];
                var mid: *const Vector3f = &tri[1];
                var bot: *const Vector3f = &tri[2];

                // order the vertices based on their y axis
                if (bot.y > mid.y) {
                    const aux: *const Vector3f = mid;
                    mid = bot;
                    bot = aux;
                }
                if (bot.y > top.y) {
                    const aux: *const Vector3f = top;
                    top = bot;
                    bot = aux;
                }
                if (mid.y > top.y) {
                    const aux: *const Vector3f = top;
                    top = mid;
                    mid = aux;
                }
                std.debug.assert(top.y >= mid.y and mid.y >= bot.y);

                // calculate dy between them
                const dyTopMid: f32 = top.y - mid.y;
                const dyMidBot: f32 = mid.y - bot.y;
                const dyTopBot: f32 = top.y - bot.y;

                const dxTopMid: f32 = top.x - mid.x;
                const dxTopBot: f32 = top.x - bot.x;
                const dxMidBot: f32 = mid.x - bot.x;

                // At this point we know that line(T-B) is going to be longer than line(T-M) or (M-B)
                // So we can split the triangle in 2 triangles, divided by the horizontal line(y == mid.y)
                const exists_top_half = dyTopMid >= 0.5;
                const exists_bot_half = dyMidBot >= 0.5;

                var side1: f32 = top.x;
                var side2: f32 = top.x;
                if (exists_top_half) {
                    // Calculate the increments (steepness) of the segments of the triangle as we progress with its filling
                    const incrementLongLine: f32 = dxTopBot / dyTopBot;
                    const incrementShortLine: f32 = dxTopMid / dyTopMid;

                    // draw top half
                    var y: usize = @intFromFloat(top.y);
                    while (y > @as(usize, @intFromFloat(mid.y))) : (y -= 1) {
                        
                        // TODO I can probably skip doing this on every line and just do it once
                        var left: usize = @intFromFloat(side1);
                        var right: usize = @intFromFloat(side2);
                        if (left > right) {
                            const aux = left;
                            left = right;
                            right = aux;
                        }
                        
                        var x: usize = left;
                        // draw a horizontal line from left to right
                        while (x < right) : (x += 1) {
                            
                            // barycentric coordinates of the current pixel
                            const pixel = Vector3f { .x = @floatFromInt(x), .y = @floatFromInt(y), .z = 0 };

                            const ab = b.substract(a.*);
                            const ac = c.substract(a.*);
                            const ap = pixel.substract(a.*);
                            const bp = pixel.substract(b.*);
                            const ca = a.substract(c.*);

                            // TODO PERF we dont actually need many of the calculations of cross_product here, just the z
                            // the magnitude of the cross product can be interpreted as the area of the parallelogram.
                            const paralelogram_area_abc: f32 = ab.cross_product(ac).z;
                            const paralelogram_area_abp: f32 = ab.cross_product(bp).z;
                            const paralelogram_area_cap: f32 = ca.cross_product(ap).z;

                            const u: f32 = paralelogram_area_cap / paralelogram_area_abc;
                            const v: f32 = paralelogram_area_abp / paralelogram_area_abc;
                            const w: f32 = (1 - u - v);

                            // The inverse of the barycentric would be `P=wA+uB+vC`

                            // determine if a pixel is in fact part of the triangle
                            if (u < 0 or u >= 1) continue;
                            if (v < 0 or v >= 1) continue;
                            if (w < 0 or w >= 1) continue;

                            if (pipeline_configuration.do_depth_testing) {
                                const z = depth[0] * w + depth[1] * u + depth[2] * v;
                                if (requirements.depth_buffer.get(x, y) < z) continue;
                                requirements.depth_buffer.set(x, y, z);
                            }

                            const interpolated_invariants: invariant_type = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants, w_used_for_perspective_correction, u, v, w)
                                else interpolate(invariant_type, invariants, u, v, w);

                            const final_color = fragment_shader(context, interpolated_invariants);
                            
                            if (pipeline_configuration.blend_with_background) {
                                const old_color = pixel_buffer.get(x, y);
                                pixel_buffer.set(x, y, final_color.blend(old_color));
                            }
                            else pixel_buffer.set(x, y, final_color);
                        }

                        side1 -= incrementLongLine;
                        side2 -= incrementShortLine;
                    }

                }

                if (exists_bot_half) {
                    // Calculate the increments (steepness) of the segments of the triangle as we progress with its filling
                    const incrementLongLine: f32 = dxTopBot / dyTopBot;
                    const incrementShortLine: f32 = dxMidBot / dyMidBot;
                    side2 = mid.x;

                    // draw bottom half
                    var y: usize = @intFromFloat(mid.y);
                    while (y > @as(usize, @intFromFloat(bot.y))) : (y -= 1) {
                        
                        // TODO I can probably skip doing this on every line and just do it once
                        var left: usize = @intFromFloat(side1);
                        var right: usize = @intFromFloat(side2);
                        if (left > right) {
                            const aux = left;
                            left = right;
                            right = aux;
                        }
                        
                        var x: usize = left;
                        // draw a horizontal line from left to right
                        while (x < right) : (x += 1) {
                            
                            // barycentric coordinates of the current pixel
                            const pixel = Vector3f { .x = @floatFromInt(x), .y = @floatFromInt(y), .z = 0 };

                            const ab = b.substract(a.*);
                            const ac = c.substract(a.*);
                            const ap = pixel.substract(a.*);
                            const bp = pixel.substract(b.*);
                            const ca = a.substract(c.*);

                            // TODO PERF we dont actually need many of the calculations of cross_product here, just the z
                            // the magnitude of the cross product can be interpreted as the area of the parallelogram.
                            const paralelogram_area_abc: f32 = ab.cross_product(ac).z;
                            const paralelogram_area_abp: f32 = ab.cross_product(bp).z;
                            const paralelogram_area_cap: f32 = ca.cross_product(ap).z;

                            const u: f32 = paralelogram_area_cap / paralelogram_area_abc;
                            const v: f32 = paralelogram_area_abp / paralelogram_area_abc;
                            const w: f32 = (1 - u - v);

                            // The inverse of the barycentric would be `P=wA+uB+vC`

                            // determine if a pixel is in fact part of the triangle
                            if (u < 0 or u >= 1) continue;
                            if (v < 0 or v >= 1) continue;
                            if (w < 0 or w >= 1) continue;

                            if (pipeline_configuration.do_depth_testing) {
                                const z = depth[0] * w + depth[1] * u + depth[2] * v;
                                if (requirements.depth_buffer.get(x, y) < z) continue;
                                requirements.depth_buffer.set(x, y, z);
                            }

                            const interpolated_invariants: invariant_type = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants, w_used_for_perspective_correction, u, v, w)
                                else interpolate(invariant_type, invariants, u, v, w);

                            const final_color = fragment_shader(context, interpolated_invariants);
                            
                            if (pipeline_configuration.blend_with_background) {
                                const old_color = pixel_buffer.get(x, y);
                                pixel_buffer.set(x, y, final_color.blend(old_color));
                            }
                            else pixel_buffer.set(x, y, final_color);
                        }

                        side1 -= incrementLongLine;
                        side2 -= incrementShortLine;
                    }
                }

                if (!exists_top_half and !exists_bot_half and dyTopBot >= 0.5) {
                    // If neither half is big enough by itself to be drawn, but together they are big enough, then draw it
                    // even though it will be just a line of pixels
                    // TODO draw a line from left to right. figure out which side is mor to the left and which one is more to the right
                }
            }
            fn rasterize_1(pixel_buffer: Buffer2D(final_color_type), context: context_type, requirements: pipeline_configuration.Requirements(), tri: [3]Vector3f, depth: [3]f32, w_used_for_perspective_correction: [3]f32, invariants: [3]invariant_type) void {
                
                trace("rasterize_1", .{});
                trace_triangle(tri);

                // alias each triangle vertex to a, b and c just for readability
                const a = &tri[0];
                const b = &tri[1];
                const c = &tri[2];

                // these are used later when calculating barycenter
                const ab = b.substract(a.*);
                const ac = c.substract(a.*);
                const ca = a.substract(c.*);
                const paralelogram_area_abc: f32 = ab.cross_product(ac).z;

                // calculate the bounds in pixels of the triangle on the screen
                var left: usize = @intFromFloat(@min(a.x, @min(b.x, c.x)));
                var bottom: usize = @intFromFloat(@min(a.y, @min(b.y, c.y)));
                var right: usize = @intFromFloat(@max(a.x, @max(b.x, c.x)));
                var top: usize = @intFromFloat(@max(a.y, @max(b.y, c.y)));

                if (pipeline_configuration.do_scissoring) {
                    left = @min(left, @as(usize, @intFromFloat(requirements.scissor_rect.x)));
                    bottom = @min(bottom, @as(usize, @intFromFloat(requirements.scissor_rect.y)));
                    right = @max(right, @as(usize, @intFromFloat(requirements.scissor_rect.z)));
                    top = @max(top, @as(usize, @intFromFloat(requirements.scissor_rect.w)));
                }

                trace_bb(left, right, top, bottom);

                // bottom to top
                var y: usize = bottom;
                while (y <= top) : (y += 1) {
                    
                    // left to right
                    var x: usize = left;
                    while (x <= right) : (x += 1) {
                        
                        // calculate barycentric coordinates of the current pixel
                        // NOTE we are checking that THE MIDDLE point of the pixel itself is inside the triangle, hence the +0.5
                        const pixel = Vector3f { .x = @as(f32, @floatFromInt(x)) + 0.5, .y = @as(f32, @floatFromInt(y)) + 0.5, .z = 0 };

                        const ap = pixel.substract(a.*);
                        const bp = pixel.substract(b.*);

                        // NOTE the magnitude of the cross product can be interpreted as the area of the parallelogram.
                        const paralelogram_area_abp: f32 = ab.cross_product(bp).z;
                        const paralelogram_area_cap: f32 = ca.cross_product(ap).z;

                        // The inverse of the barycentric would be `P=wA+uB+vC`
                        const u: f32 = paralelogram_area_cap / paralelogram_area_abc;
                        const v: f32 = paralelogram_area_abp / paralelogram_area_abc;
                        const w: f32 = (1 - u - v);

                        // determine if a pixel is in fact part of the triangle
                        if (u < 0 or u >= 1) continue;
                        if (v < 0 or v >= 1) continue;
                        if (w < 0 or w >= 1) continue;

                        if (pipeline_configuration.do_depth_testing) {
                            // TODO do perspective correct interpolation
                            // if (pipeline_configuration.do_perspective_correct_interpolation) {}
                            // else {}
                            const z = depth[0] * w + depth[1] * u + depth[2] * v;
                            if (requirements.depth_buffer.get(x, y) < z) continue;
                            requirements.depth_buffer.set(x, y, z);
                        }

                        const interpolated_invariants: invariant_type = 
                            if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants, w_used_for_perspective_correction, u, v, w)
                            else interpolate(invariant_type, invariants, u, v, w);

                        const final_color = fragment_shader(context, interpolated_invariants);
                        
                        if (pipeline_configuration.blend_with_background) {
                            const old_color = pixel_buffer.get(x, y);
                            pixel_buffer.set(x, y, final_color.blend(old_color));
                        }
                        else pixel_buffer.set(x, y, final_color);

                    }
                }
            }
        };

        /// Here, `t` could be any struct that consists of either floats, ints, or structs.
        /// Structs MUST in turn be composed of all floats or all ints
        /// ex: struct { a: f32, b: Vector2f, c: RGBA }
        /// NOTE I'm assuming that the order of fields inside a struct is kept... which is probably not true in some situations???? but it works for now
        fn interpolate(comptime t: type, data: [3]t, u: f32, v: f32, w: f32) t {
            
            var interpolated_data: t = undefined;

            inline for (@typeInfo(t).Struct.fields) |field| {
                @field(interpolated_data, field.name) = blk: {
                    
                    const a: *const field.type = &@field(data[0], field.name);
                    const b: *const field.type = &@field(data[1], field.name);
                    const c: *const field.type = &@field(data[2], field.name);
                    var interpolated_result: field.type = switch (@typeInfo(field.type)) {
                        .Float => a.* * w + b.* * u + c.* * v,
                        .Int => @intFromFloat( @as(f32,@floatFromInt(a.*)) * w + @as(f32,@floatFromInt(b.*)) * u + @as(f32,@floatFromInt(c.*)) * v ),
                        .Struct => |s| interpolate_struct: {
                            
                            var interpolated_struct_result: field.type = undefined;
                            inline for (s.fields) |sub_field| {
                                @field(interpolated_struct_result, sub_field.name) = interpolate_struct_field: {
                                    const sub_a: *const sub_field.type = &@field(a, sub_field.name);
                                    const sub_b: *const sub_field.type = &@field(b, sub_field.name);
                                    const sub_c: *const sub_field.type = &@field(c, sub_field.name);
                                    break :interpolate_struct_field switch (@typeInfo(sub_field.type)) {
                                        .Float => sub_a.* * w + sub_b.* * u + sub_c.* * v,
                                        .Int => @intFromFloat( @as(f32,@floatFromInt(sub_a.*)) * w + @as(f32,@floatFromInt(sub_b.*)) * u + @as(f32,@floatFromInt(sub_c.*)) * v ),
                                        else => @panic("inner struct type " ++ @tagName(sub_field.type) ++ " is neither a Float, Int so it cant be interpolated!")
                                    };
                                };
                            }
                            break :interpolate_struct interpolated_struct_result;

                        },
                        else => @panic("type " ++ @tagName(field.type) ++ " is neither a Float, Int or Struct, so it cant be interpolated!")
                    };

                    break :blk interpolated_result;
                };
            }

            return interpolated_data;
        }

        /// Same as `interpolate` but applies perspective correction using the provided correction_values
        /// Here, `t` could be any struct that consists of either floats, ints, or structs.
        /// Structs MUST in turn be composed of all floats or all ints
        /// ex: struct { a: f32, b: Vector2f, c: RGBA }
        /// NOTE I'm assuming that the order of fields inside a struct is kept... which is probably not true in some situations???? but it works for now
        fn interpolate_with_correction(comptime t: type, data: [3]t, correction_values: [3]f32, u: f32, v: f32, w: f32) t {
            
            var interpolated_data: t = undefined;

            const correction = 1/correction_values[0] * w + 1/correction_values[1] * u + 1/correction_values[2] * v;

            inline for (@typeInfo(t).Struct.fields) |field| {
                @field(interpolated_data, field.name) = interpolate_field: {
                    
                    const a: *const field.type = &@field(data[0], field.name);
                    const b: *const field.type = &@field(data[1], field.name);
                    const c: *const field.type = &@field(data[2], field.name);
                    var interpolated_result: field.type = switch (@typeInfo(field.type)) {
                        .Float => blk: {
                            const fa: f32 = a.* / correction_values[0];
                            const fb: f32 = b.* / correction_values[1];
                            const fc: f32 = c.* / correction_values[2];
                            break :blk (fa * w + fb * u + fc * v) / correction;
                        },
                        .Int => blk: {
                            const fa: f32 = @as(f32, @floatFromInt(a.*)) / correction_values[0];
                            const fb: f32 = @as(f32, @floatFromInt(b.*)) / correction_values[1];
                            const fc: f32 = @as(f32, @floatFromInt(c.*)) / correction_values[2];
                            const result = (fa * w + fb * u + fc * v) / correction;
                            break :blk @intFromFloat(result);
                        },
                        .Struct => |s| interpolate_struct: {
                            
                            var interpolated_struct_result: field.type = undefined;
                            inline for (s.fields) |sub_field| {
                                @field(interpolated_struct_result, sub_field.name) = interpolate_struct_field: {
                                    
                                    const sub_a: *const sub_field.type = &@field(a, sub_field.name);
                                    const sub_b: *const sub_field.type = &@field(b, sub_field.name);
                                    const sub_c: *const sub_field.type = &@field(c, sub_field.name);
                                    break :interpolate_struct_field switch (@typeInfo(sub_field.type)) {
                                        .Float => blk: {
                                            const fa: f32 = sub_a.* / correction_values[0];
                                            const fb: f32 = sub_b.* / correction_values[1];
                                            const fc: f32 = sub_c.* / correction_values[2];
                                            break :blk (fa * w + fb * u + fc * v) / correction;
                                        },
                                        .Int => blk: {
                                            const fa: f32 = @as(f32, @floatFromInt(sub_a.*)) / correction_values[0];
                                            const fb: f32 = @as(f32, @floatFromInt(sub_b.*)) / correction_values[1];
                                            const fc: f32 = @as(f32, @floatFromInt(sub_c.*)) / correction_values[2];
                                            const result = (fa * w + fb * u + fc * v) / correction;
                                            break :blk @intFromFloat(result);
                                        },
                                        else => @panic("inner struct type " ++ @tagName(sub_field.type) ++ " is neither a Float, Int so it cant be interpolated!")
                                    };
                                };
                            }
                            break :interpolate_struct interpolated_struct_result;

                        },
                        else => @panic("type " ++ @tagName(field.type) ++ " is neither a Float, Int or Struct, so it cant be interpolated!")
                    };

                    break :interpolate_field interpolated_result;
                };
            }

            return interpolated_data;
        }

        fn barycentric(triangle: [3]Vector3f, point: Vector3f) Vector3f {
            // barycentric coordinates of the current pixel
            const ab = triangle[1].substract(triangle[0]);
            const ac = triangle[2].substract(triangle[0]);
            const ap = point.substract(triangle[0]);
            const bp = point.substract(triangle[1]);
            const ca = triangle[0].substract(triangle[2]);

            // TODO PERF we dont actually need many of the calculations of cross_product here, just the z
            // the magnitude of the cross product can be interpreted as the area of the parallelogram.
            const paralelogram_area_abc: f32 = ab.cross_product(ac).z;
            const paralelogram_area_abp: f32 = ab.cross_product(bp).z;
            const paralelogram_area_cap: f32 = ca.cross_product(ap).z;

            const u: f32 = paralelogram_area_cap / paralelogram_area_abc;
            const v: f32 = paralelogram_area_abp / paralelogram_area_abc;
            const w: f32 = (1 - u - v);

            return .{.x = u, .y = v, .z = w};
        }

        fn trace_bb(left: usize, right: usize, top: usize, bottom: usize) void {
            trace("T.BB: left {}, right {}, top {}, bottom {}", .{left, right, top, bottom});
        }

        fn trace_triangle_4(t: [3]Vector4f) void {
            trace("T.A: {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{t[0].x,t[0].y,t[0].z,t[0].w});
            trace("T.B: {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{t[1].x,t[1].y,t[1].z,t[1].w});
            trace("T.C: {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{t[2].x,t[2].y,t[2].z,t[2].w});
        }

        fn trace_triangle(t: [3]Vector3f) void {
            trace("T.A: {d:.8}, {d:.8}, {d:.8}", .{t[0].x,t[0].y,t[0].z});
            trace("T.B: {d:.8}, {d:.8}, {d:.8}", .{t[1].x,t[1].y,t[1].z});
            trace("T.C: {d:.8}, {d:.8}, {d:.8}", .{t[2].x,t[2].y,t[2].z});
        }

        fn trace_mat4(m: M44) void {
            trace("M {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{m.data[0], m.data[4], m.data[8], m.data[12]});
            trace("M {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{m.data[1], m.data[5], m.data[9], m.data[13]});
            trace("M {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{m.data[2], m.data[6], m.data[10], m.data[14]});
            trace("M {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{m.data[3], m.data[7], m.data[11], m.data[15]});
        }

        fn trace(comptime fmt: []const u8, args: anytype) void {
            if (!pipeline_configuration.trace) return;
            std.log.debug(fmt, args);
        }

    };
}

const imgui_renderer = struct {
    
    const Context = struct {
        texture: Buffer2D(RGBA),
        texture_width: usize,
        texture_height: usize,
        projection_matrix: M44,
    };
    
    const Invariant = struct {
        texture_uv: Vector2f,
        color: RGBA,
    };
    
    const Vertex = struct {
        pos: Vector2f,
        uv: Vector2f,
        color: RGBA,
    };

    const pipeline_configuration = GraphicsPipelineConfiguration {
        .blend_with_background = true,
        .use_index_buffer = true,
        .do_triangle_clipping = false,
        .do_depth_testing = false,
        .do_perspective_correct_interpolation = false,
        .do_scissoring = true,
        .use_triangle_2 = false,
    };

    const Pipeline = GraphicsPipeline(
        win32.RGBA,
        Context,
        Invariant,
        Vertex,
        pipeline_configuration,
        struct {
            fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                out_invariant.color = vertex.color;
                out_invariant.texture_uv = vertex.uv;
                return context.projection_matrix.apply_to_vec3(Vector3f { .x = vertex.pos.x, .y = vertex.pos.y, .z = 1 });
            }
        }.vertex_shader,
        struct {
            fn fragment_shader(context: Context, invariants: Invariant) win32.RGBA {
                const sample = context.texture.point_sample(true, invariants.texture_uv);
                const rgba = invariants.color.multiply(sample);
                return win32.rgba(rgba.r, rgba.g, rgba.b, rgba.a);
            }
        }.fragment_shader,
    );
};

fn quad_renderer(comptime texture_type: type, comptime use_bilinear: bool) type {
    return struct {

        const Self = @This();

        const Context = struct {
            texture: Buffer2D(texture_type),
            texture_width: usize,
            texture_height: usize,
            projection_matrix: M44,
        };

        const Invariant = struct {
            texture_uv: Vector2f,
        };

        const Vertex = struct {
            pos: Vector2f,
            uv: Vector2f,
        };

        const pipeline_configuration = GraphicsPipelineConfiguration {
            .blend_with_background = true,
            .use_index_buffer = true,
            .do_triangle_clipping = true,
            .do_depth_testing = true,
            .do_perspective_correct_interpolation = true,
            .do_scissoring = false,
            .use_triangle_2 = false,
            .trace = false,
        };

        const Pipeline = GraphicsPipeline(
            win32.RGBA,
            Context,
            Invariant,
            Vertex,
            pipeline_configuration,
            struct {
                fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                    out_invariant.texture_uv = vertex.uv;
                    return context.projection_matrix.apply_to_vec3(Vector3f { .x = vertex.pos.x, .y = vertex.pos.y, .z = 0 });
                }
            }.vertex_shader,
            struct {
                fn fragment_shader(context: Context, invariants: Invariant) win32.RGBA {
                    const rgba = if (use_bilinear) context.texture.bilinear_sample(true, invariants.texture_uv) else context.texture.point_sample(true, invariants.texture_uv);
                    if (texture_type == RGBA) return win32.rgba(rgba.r, rgba.g, rgba.b, rgba.a)
                    else return win32.rgba(rgba.r, rgba.g, rgba.b, 255);
                }
            }.fragment_shader,
        );
    };
}

const text_renderer = struct {
    
    const Context = struct {
        texture: Buffer2D(RGBA),
        texture_width: usize,
        texture_height: usize,
        projection_matrix: M44,
    };

    const Invariant = struct {
        texture_uv: Vector2f,
    };

    const Vertex = struct {
        pos: Vector2f,
        uv: Vector2f,
    };

    const Pipeline = GraphicsPipeline(
        win32.RGBA,
        Context,
        Invariant,
        Vertex,
        GraphicsPipelineConfiguration {
            .blend_with_background = true,
            .use_index_buffer_auto = true,
            .use_index_buffer = false,
            .do_triangle_clipping = false,
            .do_depth_testing = false,
            .do_perspective_correct_interpolation = false,
            .do_scissoring = false,
            .use_triangle_2 = false,
        },
        struct {
            fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                out_invariant.texture_uv = vertex.uv;
                return context.projection_matrix.apply_to_vec3(Vector3f { .x = vertex.pos.x, .y = vertex.pos.y, .z = 1 });
            }
        }.vertex_shader,
        struct {
            fn fragment_shader(context: Context, invariants: Invariant) win32.RGBA {
                const rgba = context.texture.point_sample(false, invariants.texture_uv);
                return win32.rgba(rgba.r, rgba.g, rgba.b, rgba.a);
            }
        }.fragment_shader,
    );

};

const gouraud_renderer = struct {
    
    const Context = struct {
        texture: Buffer2D(RGB),
        texture_width: usize,
        texture_height: usize,
        view_model_matrix: M44,
        projection_matrix: M44,
        light_position_camera_space: Vector3f,
    };
    
    const Invariant = struct {
        texture_uv: Vector2f,
        light_intensity: f32,
    };
    
    const Vertex = struct {
        pos: Vector3f,
        uv: Vector2f,
        normal: Vector3f,
    };
    
    const pipeline_configuration = GraphicsPipelineConfiguration {
        .blend_with_background = false,
        .use_index_buffer = false,
        .do_triangle_clipping = true,
        .do_depth_testing = true,
        .do_perspective_correct_interpolation = true,
        .do_scissoring = false,
        .use_triangle_2 = false,
    };

    const Pipeline = GraphicsPipeline(
        win32.RGBA, Context, Invariant, Vertex, pipeline_configuration,
        struct {
            fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                const position_camera_space = context.view_model_matrix.apply_to_vec3(vertex.pos);
                const light_direction = context.light_position_camera_space.substract(position_camera_space.discard_w()).normalized();
                out_invariant.light_intensity = std.math.clamp(vertex.normal.normalized().dot(light_direction), 0, 1);
                out_invariant.texture_uv = vertex.uv;
                return context.projection_matrix.apply_to_vec4(position_camera_space);
            }
        }.vertex_shader,
        struct {
            fn fragment_shader(context: Context, invariants: Invariant) win32.RGBA {
                const sample = context.texture.point_sample(true, invariants.texture_uv);
                const rgba = sample.scale(invariants.light_intensity);
                return win32.rgba(rgba.r, rgba.g, rgba.b, 255);
            }
        }.fragment_shader,
    );

};
