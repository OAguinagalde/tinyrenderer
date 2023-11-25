const std = @import("std");

const core = @import("core.zig");
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
const RGBA = @import("pixels.zig").RGBA;
const RGB = @import("pixels.zig").RGB;
const BGRA = @import("pixels.zig").BGRA;
const GraphicsPipelineConfiguration = @import("graphics.zig").GraphicsPipelineConfiguration;
const GraphicsPipeline = @import("graphics.zig").GraphicsPipeline;
const tic80 = @import("tic80.zig");

const GouraudShader = @import("shaders/gouraud.zig").Shader(BGRA, RGB);
const QuadShaderRgb = @import("shaders/quad.zig").Shader(BGRA, RGB, false, false);
const QuadShaderRgba = @import("shaders/quad.zig").Shader(BGRA, RGBA, false, false);
const TextRenderer = @import("text.zig").TextRenderer(BGRA, 1024, 1024);

const Camera = struct {
    position: Vector3f,
    direction: Vector3f,
    looking_at: Vector3f,
    up: Vector3f,
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

    fn render_draw_data(pixel_buffer: Buffer2D(win32.BGRA)) void {
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
    pixel_buffer: Buffer2D(BGRA),
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
    text_renderer: TextRenderer,
    
    // imgui_platform_context: imgui_win32_impl.Context,
    imgui_font_texture: Buffer2D(RGBA),
    renderer: tic80.Renderer(BGRA),
};

var state = State {
    .x = 10,
    .y = 10,
    // .w = 1000,
    .w = 240*4,
    // .h = 1000,
    .h = 136*4,
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
    .text_renderer = undefined,
    
    .imgui_font_texture = undefined,
    .renderer = undefined,
    // .imgui_platform_context = undefined,
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

    state.pixel_buffer.data = try allocator.alloc(BGRA, @intCast(state.w * state.h));
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
            // const imgui_context = imgui.c.igCreateContext(null);
            // _ = imgui_context;
            // imgui_win32_impl.init(&state.imgui_platform_context, window_handle, &state.imgui_font_texture);

            // Load the diffuse texture data
            state.texture = TGA.from_file(RGB, allocator, "res/african_head_diffuse.tga")
                catch |err| { std.debug.print("error reading `res/african_head_diffuse.tga` {?}", .{err}); return; };
            
            state.vertex_buffer = OBJ.from_file(allocator, "res/african_head.obj")
                catch |err| { std.debug.print("error reading `res/african_head.obj` {?}", .{err}); return; };

            state.text_renderer = try TextRenderer.init(allocator, state.pixel_buffer);
            
            state.camera.position = Vector3f { .x = 0, .y = 0, .z = 0 };
            state.camera.up = Vector3f { .x = 0, .y = 1, .z = 0 };
            state.camera.direction = Vector3f { .x = 0, .y = 0, .z = 1 };

            state.time = 0;

            state.renderer = try tic80.Renderer(BGRA).init(allocator, tic80.penguknight_original_assets.palette, tic80.penguknight_original_assets.tiles);
        }

        // Deinitialize the application state
        defer {
            allocator.free(state.depth_buffer.data);
            allocator.free(state.texture.data);
            allocator.free(state.vertex_buffer);
            state.text_renderer.deinit();
            state.renderer.deinit();
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

                // Clear the screen and the zbuffer
                state.pixel_buffer.clear(BGRA.make(100, 149, 237,255));
                state.depth_buffer.clear(999999);

                if (state.keys['T']) state.time += ms;

                // camera movement with mouse
                const mouse_sensitivity = 0.60;
                const up = Vector3f {.x = 0, .y = 1, .z = 0 };
                // TODO so, I'm doing something wrong either in the cross product or I just dont know math, because both my looakat_right_handed and this real_right here are not what
                // they are supposed to be
                const real_right = state.camera.direction.cross_product(up).normalized();
                const real_up = state.camera.direction.cross_product(real_right).scale(-1).normalized();
                if (false) if (mouse_dx != 0 or mouse_dy != 0) {
                    state.camera.direction = state.camera.direction.add(real_right.scale(mouse_dx*mouse_sensitivity));
                    if (state.camera.direction.y < 0.95 and state.camera.direction.y > -0.95) {
                        state.camera.direction = state.camera.direction.add(real_up.scale(-mouse_dy*mouse_sensitivity));
                    }
                    state.camera.direction.normalize();
                };
                
                // camera position with AWSD and QE
                const unit: f32 = @floatCast(5/ms);
                // if (state.keys['W']) state.camera.position = state.camera.position.add(state.camera.direction.scale(unit));
                // if (state.keys['S']) state.camera.position = state.camera.position.add(state.camera.direction.scale(-unit));
                if (state.keys['A']) state.camera.position = state.camera.position.add(real_right.scale(-unit));
                if (state.keys['D']) state.camera.position = state.camera.position.add(real_right.scale(unit));
                // if (state.keys['Q']) state.camera.position.y += unit;
                // if (state.keys['E']) state.camera.position.y -= unit;
                if (state.keys['W']) state.camera.position.y += unit;
                if (state.keys['S']) state.camera.position.y -= unit;

                // calculate view_matrix, projection_matrix and viewport_matrix
                const looking_at: Vector3f = state.camera.position.add(state.camera.direction);
                state.view_matrix = M44.lookat_right_handed(state.camera.position, looking_at, Vector3f.from(0, 1, 0));
                // const aspect_ratio = @as(f32, @floatFromInt(client_width)) / @as(f32, @floatFromInt(client_height));
                // state.projection_matrix = M44.perspective_projection(60, aspect_ratio, 0.1, 255);
                state.projection_matrix = M44.orthographic_projection(0, @floatFromInt(@divExact(client_width,4)), @floatFromInt(@divExact(client_height,4)), 0, 0, 10);
                state.viewport_matrix = M44.viewport_i32_2(0, 0, client_width, client_height, 255);

                // Example rendering OBJ model with Gouraud Shading
                if (false) {
                    const horizontally_spinning_position = Vector3f { .x = std.math.cos(@as(f32, @floatCast(state.time)) / 2000), .y = 0, .z = std.math.sin(@as(f32, @floatCast(state.time)) / 2000) };
                    const render_context = GouraudShader.Context {
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
                    var vertex_buffer = std.ArrayList(GouraudShader.Vertex).initCapacity(allocator, @divExact(state.vertex_buffer.len, 8)) catch unreachable;
                    while (i < state.vertex_buffer.len) : (i = i + 8) {
                        const pos: Vector3f = .{ .x=state.vertex_buffer[i+0], .y=state.vertex_buffer[i+1], .z=state.vertex_buffer[i+2] };
                        const uv: Vector2f = .{ .x=state.vertex_buffer[i+3], .y=state.vertex_buffer[i+4] };
                        const normal: Vector3f = .{ .x=state.vertex_buffer[i+5], .y=state.vertex_buffer[i+6], .z=state.vertex_buffer[i+7] };
                        vertex_buffer.appendAssumeCapacity(.{ .pos = pos, .uv = uv, .normal = normal });
                    }
                    const render_requirements: GouraudShader.pipeline_configuration.Requirements() = .{
                        .depth_buffer = state.depth_buffer,
                        .viewport_matrix = state.viewport_matrix,
                    };
                    GouraudShader.Pipeline.render(state.pixel_buffer, render_context, vertex_buffer.items, @divExact(vertex_buffer.items.len, 3), render_requirements);
                }

                // render the model texture as a quad
                if (false) {
                    // const texture_data = state.texture.rgba.data;
                    const w: f32 = @floatFromInt(state.texture.width);
                    const h: f32 = @floatFromInt(state.texture.height);
                    var quad_context = QuadShaderRgb.Context {
                        .texture = state.texture,
                        .projection_matrix =
                            state.projection_matrix.multiply(
                                state.view_matrix.multiply(
                                    M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1.5 }).multiply(M44.scale(1/w))
                                )
                            ),
                    };
                    const vertex_buffer = [_]QuadShaderRgb.Vertex{
                        .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
                        .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=0} },
                        .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=1} },
                        .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=1} },
                    };
                    const index_buffer = [_]u16{0,1,2,0,2,3};
                    const requirements = QuadShaderRgb.pipeline_configuration.Requirements() {
                        .depth_buffer = state.depth_buffer,
                        .viewport_matrix = state.viewport_matrix,
                        .index_buffer = &index_buffer,
                    };
                    QuadShaderRgb.Pipeline.render(state.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
                }
                
                // render the font texture as a quad
                if (false) {
                    const texture = @import("text.zig").font.texture;
                    const w: f32 = @floatFromInt(texture.width);
                    const h: f32 = @floatFromInt(texture.height);
                    var quad_context = QuadShaderRgba.Context {
                        .texture = texture,
                        .projection_matrix =
                            state.projection_matrix.multiply(
                                state.view_matrix.multiply(
                                    M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 1 }).multiply(M44.scale(1/@as(f32, @floatFromInt(texture.width))))
                                )
                            ),
                    };
                    const vertex_buffer = [_]QuadShaderRgba.Vertex{
                        .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
                        .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=0} },
                        .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=1} },
                        .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=1} },
                    };
                    const index_buffer = [_]u16{0,1,2,0,2,3};
                    const requirements = QuadShaderRgba.pipeline_configuration.Requirements() {
                        .depth_buffer = state.depth_buffer,
                        .viewport_matrix = state.viewport_matrix,
                        .index_buffer = &index_buffer,
                    };
                    QuadShaderRgba.Pipeline.render(state.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
                }

                
                const w = 8;
                const h = 8;
                try state.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.weird_block, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*0, h*0));
                try state.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.slime1, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*2, h*2));
                try state.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.slime2, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*3, h*3));
                try state.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.pengu1, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*4, h*4));
                try state.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.pengu2, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*5, h*5));
                try state.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.id0, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*0, h*0));
                try state.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.id255, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*15, h*15));
                try state.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.id15, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*15, h*0));
                try state.renderer.add_sprite(tic80.penguknight_original_assets.SpriteEnum.id240, tic80.penguknight_original_assets.SpriteMap, Vector2f.from(w*0, h*15));
                state.renderer.render(
                    state.pixel_buffer,
                    state.projection_matrix.multiply(
                        state.view_matrix.multiply(
                            M44.translation(Vector3f.from(0, 0, 1)).multiply(M44.scale(1))
                        )
                    ),
                    state.viewport_matrix
                );

                // some debug information and stuff
                if (true) {
                    const red = BGRA.make(255, 0, 0, 255);
                    const blue = BGRA.make(0, 0, 255, 255);
                    if (false) state.pixel_buffer.line(Vector2i { .x = 150, .y = 150 }, Vector2i { .x = 150 + @as(i32, @intFromFloat(50 * state.camera.direction.x)), .y = 150 + @as(i32, @intFromFloat(50 * state.camera.direction.y)) }, red);
                    if (false) state.pixel_buffer.line(Vector2i { .x = 150, .y = 150 }, Vector2i { .x = 150 + @as(i32, @intFromFloat(50 * state.camera.direction.z)), .y = 150 }, blue);
                    try state.text_renderer.print(Vector2i { .x = 0, .y = 0 }, "hello from (0, 0), the lowest possible text!!!", .{});
                    try state.text_renderer.print(Vector2i { .x = 5, .y = client_height-10 }, "ms {d: <9.2}", .{ms});
                    try state.text_renderer.print(Vector2i { .x = 5, .y = client_height-22 }, "camera {d:.8}, {d:.8}, {d:.8}", .{state.camera.position.x, state.camera.position.y, state.camera.position.z});
                    try state.text_renderer.print(Vector2i { .x = 5, .y = client_height-10 - (12*2) }, "{d:.3}, {d:.3}, {d:.3}", .{real_right.x, real_right.y, real_right.z});
                    try state.text_renderer.print(Vector2i { .x = 5, .y = client_height-10 - (12*3) }, "d mouse {d:.8}, {d:.8}", .{mouse_dx, mouse_dy});
                    try state.text_renderer.print(Vector2i { .x = 5, .y = client_height-10 - (12*4) }, "direction {d:.8}, {d:.8}, {d:.8}", .{state.camera.direction.x, state.camera.direction.y, state.camera.direction.z});
                    state.text_renderer.render_all(
                        M44.orthographic_projection(0, @floatFromInt(state.w), @floatFromInt(state.h), 0, 0, 10),
                        state.viewport_matrix
                    );
                }
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
        BGRA,
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
            fn fragment_shader(context: Context, invariants: Invariant) BGRA {
                const sample = context.texture.point_sample(true, invariants.texture_uv);
                const rgba = invariants.color.multiply(sample);
                return BGRA { .r = rgba.r, .g = rgba.g, .b = rgba.b, .a = rgba.a };
            }
        }.fragment_shader,
    );
};
