const std = @import("std");
const builtin = @import("builtin");
const math = @import("math.zig");
const Buffer2D = @import("buffer.zig").Buffer2D;
const Vector2f = math.Vector2f;
const M33 = math.M33;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const BoundingBox = math.BoundingBox;
const core = @import("core.zig");
const Random = core.Random;
const RGBA = @import("pixels.zig").RGBA;
const RGB = @import("pixels.zig").RGB;
const graphics = @import("graphics.zig");
const TextRenderer = @import("text.zig").TextRenderer(platform.OutPixelType, 1024, 1);
const wav = @import("wav.zig");
const windows = @import("windows.zig");
const wasm = @import("wasm.zig");
const platform = if (builtin.os.tag == .windows) windows else wasm;
const Application = platform.Application(.{
    .init = init,
    .update = update,
    .dimension_scale = 3,
    .desired_width = 256,
    .desired_height = 100,
});

comptime {
    if (@This() == @import("root")) {
        _ = Application.run;
    }
}

inline fn v2(a: i32, b: i32) Vec2(i32) {
    return Vec2(i32).from(a, b);
}

inline fn bb(top: i32, bottom: i32, left: i32, right: i32) BoundingBox(i32) {
    return BoundingBox(i32).from(top, bottom, left, right);
}

const color = struct {
    const white = RGBA.from_hex(0xffffffff);
    const black = RGBA.from_hex(0x000000ff);
    const cornflowerblue = RGBA.from_hex(0x6495edff);

    const palette_0 = RGBA.from_hex(0x780000ff);
    const palette_1 = RGBA.from_hex(0xc1121fff);
    const palette_2 = RGBA.from_hex(0xfdf0d5ff);
    const palette_3 = RGBA.from_hex(0x003049ff);
    const palette_4 = RGBA.from_hex(0x669bbcff);
};

const UI = ImmediateUi(.{
    .draw_call_text_max_count = 16,
    .draw_call_shape_max_count = 16,
    .text_buffer_size = 1024*2,
    .layout = .{
        .char_height = 5,
        .char_width = 4,
        .widget_margin  = 1,
        .widget_padding = 1,
        .container_padding = 1,
    },
    .containers = enum {
        window,
        debug,
    },
});

var state: struct {
    ui: UI,
    temp_fba: std.heap.FixedBufferAllocator,
    rng: Random,
    
    count: usize = 0,
} = undefined;

pub fn main() !void {
    try Application.run();
}

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    state.ui = UI.init_pre_allocate();
    state.rng = Random.init(@intCast(platform.timestamp()));
    state.temp_fba = std.heap.FixedBufferAllocator.init(try allocator.alloc(u8, 1024*1024*10));
    defer state.temp_fba.reset();
}

pub fn update(ud: *platform.UpdateData) anyerror!bool {
    ud.pixel_buffer.clear(platform.OutPixelType.from(RGBA, color.palette_4));

    const hi: i32 = @intCast(ud.pixel_buffer.height);
    const wi: i32 = @intCast(ud.pixel_buffer.width);

    const hf: f32 = @floatFromInt(ud.pixel_buffer.height);
    const wf: f32 = @floatFromInt(ud.pixel_buffer.width);
    
    const ui = &state.ui;
    {
        ui.prepare_frame(.{
            .mouse_pos = ud.mouse,
            .mouse_down = ud.mouse_left_down,
        });
        defer ui.end_frame();

        const window = ui.begin_container(.window, bb(hi-50, hi-90, 10, 100)); {
            defer window.end();
            window.header("This is a window", .{});
            window.label("button:", .{});
            if (window.button("count: {d}", .{state.count})) state.count += 1;
            window.label("the end!", .{});
        }

        const debug = ui.begin_container(.debug, bb(hi, 0, 0, wi)); {
            defer debug.end();
            debug.label("some debug message", .{});
            debug.header("This is a window", .{});
            if (debug.button("count: {d}", .{state.count})) state.count += 1;
        }
    }
    
    var shape_vertex_buffer = std.ArrayList(ShapeRenderer(platform.OutPixelType).shader.Vertex).init(ud.allocator);
    var text_renderer = try TextRenderer.init(ud.allocator);
    for (&ui.containers.buffer) |*c| {
        for (c.draw_calls.shape.slice()) |draw_call_shape| {
            try ShapeRenderer(platform.OutPixelType).add_quad_from_bb(&shape_vertex_buffer, draw_call_shape.bounding_box, switch (draw_call_shape.style) {
                .base => color.palette_4,
                .accent => color.palette_3,
                .highlight => color.palette_2,
                .special => color.palette_1,
            });
        }
        for (c.draw_calls.text.slice()) |draw_call_text| {
            try text_renderer.print(draw_call_text.pos, "{s}", .{draw_call_text.text}, switch (draw_call_text.style) {
                .base => color.palette_0,
                .accent => color.palette_1,
                .highlight => color.palette_2,
                .special => color.palette_3,
            });
        }
    }
    ShapeRenderer(platform.OutPixelType).render_vertex_buffer(
        &shape_vertex_buffer,
        ud.pixel_buffer,
        M33.orthographic_projection(0, wf, hf, 0),
        M33.viewport(0, 0, wf, hf)
    );
    text_renderer.render_all(
        ud.pixel_buffer,
        M33.orthographic_projection(0, wf, hf, 0),
        M33.viewport(0, 0, wf, hf)
    );

    return true;
}

const ImmediateUiLayoutConfig = struct {
    char_height: i32,
    char_width: i32,
    widget_margin: i32,
    widget_padding: i32,
    container_padding: i32,
};

const ImmediateUiConfig = struct {
    draw_call_text_max_count: usize,
    draw_call_shape_max_count: usize,
    text_buffer_size: usize,
    layout: ImmediateUiLayoutConfig,
    containers: type,
};

const ImmediateUiIo = struct {
    mouse_pos: Vec2(i32),
    mouse_down: bool,
};

const Style = enum {
    base,
    accent,
    highlight,
    special,
};

const MouseStateType = enum { free, press, drag, release };
const MouseState = struct {
    st: MouseStateType = .free,
    relevant_id: u64 = 0,
};

const MouseEvent = struct {
    st: MouseStateType = .free,
    relevant_id: u64 = 0,
    pos: Vec2(i32) = v2(0,0)
};

fn ImmediateUi(comptime config: ImmediateUiConfig) type {
    return struct {
    
        const Self = @This();
        const ContainerType = config.containers;
        const ContainerTypeInfo: std.builtin.Type.Enum = @typeInfo(ContainerType).Enum;
        const ContainerTypeCount: comptime_int = ContainerTypeInfo.fields.len;
        const WidgetType = enum {
            header,
            label,
            button,
        };

        initialized: bool,
        string_data: std.BoundedArray(u8, config.text_buffer_size),
        containers: std.BoundedArray(Container, ContainerTypeCount),
        io_previous: ImmediateUiIo,

        ms_relevant_id: ?u64,
        ms_event: ?MouseEvent,

        pub fn init_pre_allocate() Self {
            var self: Self = undefined;
            self.initialized = false;
            self.string_data = .{};
            self.containers = .{};
            self.containers.resize(ContainerTypeCount) catch unreachable;
            for (self.containers.slice()) |*c| {
                c.initialized = false;
                c.stack = .{};
                c.bounding_box = undefined;
                c.bounding_box_no_allocated = undefined;
                c.draw_calls = .{};
                c.parent_ui = undefined;
            }
            self.io_previous = undefined;
            self.ms_relevant_id = null;
            self.ms_event = null;
            return self;
        }

        pub fn prepare_frame(self: *Self, io: ImmediateUiIo) void {
            
            if (!self.initialized) {
                self.initialized = true;
                self.io_previous = io;
            }
            
            self.string_data.resize(0) catch unreachable;

            const mouse_went_down = !self.io_previous.mouse_down and io.mouse_down;
            const mouse_went_up = self.io_previous.mouse_down and !io.mouse_down;
            const mouse_position = io.mouse_pos;
            const mouse_movement = io.mouse_pos.substract(self.io_previous.mouse_pos);

            // self.relevant_mouse_id is the the id pressed, released or dragged when a frame logic ends
            if (mouse_went_down) self.ms_event = .{.st = .press, .relevant_id = 0, .pos = mouse_position}
            else if (mouse_went_up) self.ms_event = .{.st = .release, .relevant_id = if (self.ms_relevant_id) |v| v else 0, .pos = mouse_position}
            else if (io.mouse_down) self.ms_event = .{.st = .drag, .relevant_id = if (self.ms_relevant_id) |v| v else 0, .pos = mouse_movement}
            else self.ms_event = .{.st = .free, .relevant_id = 0, .pos = mouse_position};
            
            self.io_previous = io;
            
            // TODO since we know the positions and sizes of all the containers and their layers in the previous frame, we can calculate which container the mouse is over of right now
        }

        pub fn end_frame(self: *Self) void {
            _ = self;
            // TODO set the order of the containerss to be drwan?
        }
        
        // TODO so if I keept everything stack based, I can modify the sizes of the windows after every internal widget has been calculated
        pub fn begin_container(self: *Self, comptime container: ContainerType, bounding_box: BoundingBox(i32)) *Container {
            
            const tag_name: [:0]const u8 = comptime @tagName(container);
            const container_tag_name_hash = comptime core.djb2(@ptrCast(tag_name[0..tag_name.len]));

            const c: *Container = &self.containers.slice()[@intFromEnum(container)];
            if (!c.initialized) {
                c.initialized = true;
                // TODO maybe make this comptime known and passed on the UI type definition, skipping the whole `initialization` part of the container
                // TODO if growable or resizeable then assign the bounding box as the new size
                c.bounding_box = bounding_box;
            }

            c.stack.resize(0) catch unreachable;
            c.stack.append(container_tag_name_hash) catch unreachable;
            c.draw_calls.shape.resize(0) catch unreachable;
            c.draw_calls.text.resize(0) catch unreachable;
            c.bounding_box_no_allocated = c.bounding_box;
            c.parent_ui = self;
            c.mouse_event = null;
            
            // TODO on container end we need to know if the mouse event was handled or not
            if (self.ms_event) |me| {
                // there is a mouse event not handled by any container yet
                switch (me.st) {
                    .free, .press => {
                        
                        // TODO at the end of each frame, compute the layer order of every container so that on the next frame
                        // we can figure out which container is relevant when the mouse is hovering 2 different containers at the same
                        // time but only one of them is "visible" at the mouse position
                        const mouse_in_0: bool = self.containers.slice()[0].bounding_box.contains(me.pos);
                        const container_directly_under_the_mouse_is_this_one = if (container == .window) mouse_in_0 else !mouse_in_0;
                        
                        const mouse_inside_bb = c.bounding_box.contains(me.pos);
                        
                        if (mouse_inside_bb and container_directly_under_the_mouse_is_this_one) {
                            c.mouse_event = me;
                            // Since we already know that no other container can handle the mouse event, consume it already
                            self.ms_event = null;
                        }
                    },
                    .drag, .release => {
                        // we dont know which container is relevant for this event until the widget hash is compared so just pass it
                        // to the container until one of them handles it
                        c.mouse_event = me;
                    },
                }
            }

            return c;
        }

        pub const ContainerDrawCalls = struct {
            text: std.BoundedArray(DrawCallText, config.draw_call_text_max_count) = .{},
            shape: std.BoundedArray(DrawCallShape, config.draw_call_shape_max_count) = .{},
            pub const DrawCallText = struct {
                text: []const u8,
                style: Style,
                pos: Vec2(f32)
            };
            pub const DrawCallShape = struct {
                bounding_box: BoundingBox(f32),
                style: Style,
            };
        };

        pub const Container = struct {
            initialized: bool,
            /// A stack of hash-es that gets pushed as widgets start and end
            /// so the stack at [0] is the hash of the container itsels
            stack: std.BoundedArray(u64, 8),
            /// The known size of the Container. If growable, it might be different than the originally provided bounding_box
            bounding_box: BoundingBox(i32),
            /// The available empty space in the container
            bounding_box_no_allocated: BoundingBox(i32),
            /// Each container has its own draw call buffer
            draw_calls: ContainerDrawCalls,
            parent_ui: *Self,
            mouse_event: ?MouseEvent,

            pub fn header(self: *Container, comptime fmt: []const u8, args: anytype) void {
                
                // compute the space required
                const available_vetical_space = self.bounding_box_no_allocated.height();
                const required_vetical_space = 
                    config.layout.container_padding +
                    config.layout.widget_margin +
                    config.layout.char_height +
                    config.layout.widget_margin
                ;

                if (available_vetical_space < required_vetical_space) return;

                // compute the everything required to render the header
                const text_position = v2(
                    self.bounding_box_no_allocated.left + config.layout.container_padding,
                    self.bounding_box_no_allocated.top - required_vetical_space + config.layout.widget_margin,
                );
                const out = self.bounding_box_no_allocated.shrink(.top, required_vetical_space);
                const header_bb: BoundingBox(i32) = out.leftover;
                const bounding_box_no_allocated_updated = out.shrinked;

                // make a copy of the string to be printed
                const buffer_unused = self.parent_ui.string_data.unusedCapacitySlice();
                const str = std.fmt.bufPrint(buffer_unused, fmt, args) catch unreachable;
                const len = str.len;
                self.parent_ui.string_data.resize(self.parent_ui.string_data.len + len) catch unreachable;
                
                // handle moving the container by clicking and dragging the header
                var container_offset: ?Vec2(i32) = null;
                if (self.mouse_event) |me| switch (me.st) {
                    .free => if (header_bb.contains(me.pos)) {
                        // TODO hover header
                        self.mouse_event = null;
                    },
                    .press => if (header_bb.contains(me.pos)) {
                        const parent_hash = self.stack.buffer[self.stack.len-1];
                        const header_hash = parent_hash + @as(u64, @intFromEnum(WidgetType.header)) + core.djb2(fmt);
                        self.parent_ui.ms_relevant_id = header_hash;
                        self.mouse_event = null;
                    },
                    .drag => {
                        const parent_hash = self.stack.buffer[self.stack.len-1];
                        const header_hash = parent_hash + @as(u64, @intFromEnum(WidgetType.header)) + core.djb2(fmt);
                        if (me.relevant_id == header_hash) {
                            self.parent_ui.ms_relevant_id = header_hash;
                            container_offset = me.pos;
                            self.mouse_event = null;
                        }
                    },
                    .release => {
                        const parent_hash = self.stack.buffer[self.stack.len-1];
                        const header_hash = parent_hash + @as(u64, @intFromEnum(WidgetType.header)) + core.djb2(fmt);
                        if (me.relevant_id == header_hash) {
                            self.parent_ui.ms_relevant_id = null;
                            self.mouse_event = null;
                            // TODO the mouse might have moved and released so... track movement in release event as well, maybe
                        }
                    },
                };

                // render the header taking into account whether the container was dragged or not
                if (container_offset) |offset| {
                    self.bounding_box_no_allocated = bounding_box_no_allocated_updated.offset(offset);
                    self.bounding_box = self.bounding_box.offset(offset);
                    self.render_square(header_bb.offset(offset), .special);
                    self.render_text(str, text_position.add(offset), .special);
                }
                else {
                    self.bounding_box_no_allocated = bounding_box_no_allocated_updated;
                    self.render_square(header_bb, .special);
                    self.render_text(str, text_position, .special);
                }

            }

            pub fn label(self: *Container, comptime fmt: []const u8, args: anytype) void {
                const available_vetical_space = self.bounding_box_no_allocated.height();
                const required_vetical_space = 
                    config.layout.widget_margin +
                    config.layout.char_height +
                    config.layout.widget_margin
                ;
                
                if (available_vetical_space < required_vetical_space) return;

                const text_position = v2(
                    self.bounding_box_no_allocated.left + config.layout.container_padding,
                    self.bounding_box_no_allocated.top - required_vetical_space + config.layout.widget_margin,
                );
                self.bounding_box_no_allocated = self.bounding_box_no_allocated.shrink(.top, required_vetical_space).shrinked;

                // make a copy of the string to be printed
                const buffer_unused = self.parent_ui.string_data.unusedCapacitySlice();
                const str = std.fmt.bufPrint(buffer_unused, fmt, args) catch unreachable;
                const len = str.len;
                self.parent_ui.string_data.resize(self.parent_ui.string_data.len + len) catch unreachable;

                self.render_text(str, text_position, .special);
            }

            const ButtonState = enum {
                normal,
                hover,
                pressed,
                clicked
            };

            pub fn button(self: *Container, comptime fmt: []const u8, args: anytype) bool {
                
                // compute the space required
                const space_available_vetical = self.bounding_box_no_allocated.height();
                const space_available_horizontal = self.bounding_box_no_allocated.width();
                const space_required_vertical: i32 = 
                    config.layout.widget_margin +
                    config.layout.widget_padding +
                    config.layout.char_height +
                    config.layout.widget_padding +
                    config.layout.widget_margin
                ;

                const len = std.fmt.count(fmt, args);

                const space_required_horizontal: i32 = 
                    config.layout.container_padding +
                    config.layout.widget_margin +
                    config.layout.widget_padding +
                    (config.layout.char_width * @as(i32, @intCast(len))) +
                    config.layout.widget_padding +
                    config.layout.widget_margin +
                    config.layout.container_padding
                ;
                
                if (space_available_vetical < space_required_vertical) return false;
                if (space_available_horizontal < space_required_horizontal) return false;

                // compute the everything required to render the button
                const text_position = v2(
                    self.bounding_box_no_allocated.left + config.layout.container_padding + config.layout.widget_margin + config.layout.widget_padding,
                    self.bounding_box_no_allocated.top - space_required_vertical + config.layout.widget_margin + config.layout.widget_padding,
                );
                const out = self.bounding_box_no_allocated.shrink(.top, space_required_vertical);
                self.bounding_box_no_allocated = out.shrinked;
                const iner_bb: BoundingBox(i32) = out.leftover.get_inner_bb_with_padding(config.layout.widget_margin);
                const button_bb: BoundingBox(i32) = iner_bb.shrink(.right, space_available_horizontal - space_required_horizontal).shrinked;

                // make a copy of the string to be printed
                const buffer_unused = self.parent_ui.string_data.unusedCapacitySlice();
                const str = std.fmt.bufPrint(buffer_unused, fmt, args) catch unreachable;
                self.parent_ui.string_data.resize(self.parent_ui.string_data.len + len) catch unreachable;
                std.debug.assert(str.len == len);

                var button_state: ButtonState = .normal;
                // handle the clicking the button logic
                
                if (self.mouse_event) |me| switch (me.st) {
                    .free => if (button_bb.contains(me.pos)) {
                        button_state = .hover;
                        self.mouse_event = null;
                    },
                    .press => if (button_bb.contains(me.pos)) {
                        button_state = .pressed;
                        const parent_hash = self.stack.buffer[self.stack.len-1];
                        const button_hash = parent_hash + @as(u64, @intFromEnum(WidgetType.button)) + core.djb2(fmt);
                        self.parent_ui.ms_relevant_id = button_hash;
                        self.mouse_event = null;
                    },
                    .drag => {
                        const parent_hash = self.stack.buffer[self.stack.len-1];
                        const button_hash = parent_hash + @as(u64, @intFromEnum(WidgetType.button)) + core.djb2(fmt);
                        if (me.relevant_id == button_hash) {
                            self.parent_ui.ms_relevant_id = button_hash;
                            button_state = .pressed;
                            self.mouse_event = null;
                        }
                    },
                    .release => {
                        const parent_hash = self.stack.buffer[self.stack.len-1];
                        const button_hash = parent_hash + @as(u64, @intFromEnum(WidgetType.button)) + core.djb2(fmt);
                        if (me.relevant_id == button_hash) {
                            self.parent_ui.ms_relevant_id = null;
                            if (button_bb.contains(me.pos)) button_state = .clicked;
                            self.mouse_event = null;
                        }
                    },
                };

                const button_style: Style = switch (button_state) {
                    .normal => .base,
                    .hover => .highlight,
                    .pressed => .accent,
                    .clicked => .special,
                };
                self.render_square(button_bb, button_style);
                self.render_text(str, text_position, .base);

                return button_state == .clicked;
            }

            pub fn end (c: *Container) void {
                _ = c;
                // TODO make sure the bb has been updated by this point
                // TODO draw order has been set somehow?
            }
            
            inline fn render_text(self: *Container, str: []const u8, position: Vec2(i32), style: Style) void {
                self.draw_calls.text.appendAssumeCapacity(.{
                    .text = str, .style = style, .pos = position.to(f32)
                });
            }

            inline fn render_square(self: *Container, bounding_box: BoundingBox(i32), style: Style) void {
                self.draw_calls.shape.appendAssumeCapacity(.{
                    .bounding_box = bounding_box.to(f32), .style = style,
                });
            }
        };

        // fn selection_grid_from_text_options(options: []const []const u8, selected: *?usize, hovered: *?usize, allow_deselect: bool) !GridThingy {
        //     var max_width: usize = 0;
        //     for (options) |option| max_width = @max(max_width, option.len * @as(usize, @intFromFloat(char_width)));
            
        //     const grid_dimensions = Vec2(usize).from(1, options.len);
        //     const grid_cell_dimensions = Vec2(usize).from(max_width, @as(usize, @intFromFloat(text_line_height)));

        //     const grid = selection_grid(grid_dimensions, grid_cell_dimensions, selected, hovered, allow_deselect);
        //     try grid.fill_with_text_options(options);
        //     try grid.highlight_hovered();
        //     try grid.highlight_selected();
        //     return grid;
        // }
        
        // const GridThingy = struct {
            
        //     grid_dimensions: Vec2(usize),
        //     grid_cell_dimensions: Vec2(usize),
        //     element_bb: BoundingBox(f32),
        //     working_bb: BoundingBox(f32),
        //     selected: *?usize,
        //     hovered: *?usize,
        //     just_selected: bool,
        //     click_and_dragging: bool,
            
        //     pub fn fill_with_texture(self: GridThingy, texture: Buffer2D(platform.OutPixelType)) !void {
        //         try renderer.add_blit_texture_to_bb(self.working_bb, texture);
        //     }
            
        //     pub fn fill_with_palette_based_texture(self: GridThingy, palette_based_texture: Buffer2D(u4), palette: *tic80.Palette) !void {
        //         try renderer.add_palette_based_textured_quad(self.working_bb, self.working_bb.offset_negative(self.working_bb.bl()), palette_based_texture, palette);
        //     }

        //     pub fn get_grid_index_bb(self: GridThingy, index: usize) BoundingBox(f32) {
        //         const col = index % self.grid_dimensions.x;
        //         const row = @divFloor(index, self.grid_dimensions.x);
        //         return BoundingBox(f32).from(
        //             self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y + self.grid_cell_dimensions.y)),
        //             self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y)),
        //             self.working_bb.left + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x)),
        //             self.working_bb.left + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x + self.grid_cell_dimensions.x))
        //         );
        //     }
        //     pub fn fill_index_with_palette_based_textured_quad(self: GridThingy, index: usize, texture_quad: BoundingBox(f32), palette_based_texture: Buffer2D(u4), palette: *tic80.Palette) !void {
        //         const col = index % self.grid_dimensions.x;
        //         const row = @divFloor(index, self.grid_dimensions.x);
        //         const dest_bb = BoundingBox(f32).from(
        //             self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y + self.grid_cell_dimensions.y)),
        //             self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y)),
        //             self.working_bb.left + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x)),
        //             self.working_bb.left + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x + self.grid_cell_dimensions.x))
        //         );
        //         try renderer.add_palette_based_textured_quad(dest_bb, texture_quad, palette_based_texture, palette);
        //     }

        //     pub fn fill_with_text_options(self: GridThingy, options: []const []const u8) !void {
        //         for (options, 0..) |option, i| {
        //             const if32: f32 = @floatFromInt(i);
        //             const label_position = Vec2(f32).from(self.working_bb.left, self.working_bb.bottom + (if32+0) * @as(f32, @floatFromInt(self.grid_cell_dimensions.y)));
        //             try renderer.add_text(label_position, "{s}", .{option}, text_color);
        //         }
        //     }

        //     pub fn highlight_hovered(self: GridThingy) !void {
        //         // render the highlight for the hover
        //         if (self.hovered.*) |hover_index| {
        //             const col: usize = hover_index % self.grid_dimensions.x;
        //             const row: usize = @divFloor(hover_index, self.grid_dimensions.x);
        //             const option_bb = BoundingBox(f32).from(
        //                 self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y + self.grid_cell_dimensions.y)),
        //                 self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y)),
        //                 self.working_bb.left   + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x)),
        //                 self.working_bb.left   + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x + self.grid_cell_dimensions.x)),
        //             );
        //             var color = highlight_color_a;
        //             color.a = 50;
        //             try renderer.add_quad_from_bb(option_bb, color);
        //         }
        //     }

        //     pub fn highlight_selected(self: GridThingy) !void {
        //         // render the highlight for the selected
        //         if (self.selected.*) |selected_option| {
        //             const col: usize = selected_option%self.grid_dimensions.x;
        //             const row: usize = @divFloor(selected_option,self.grid_dimensions.x);
        //             const option_bb = BoundingBox(f32).from(
        //                 self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y + self.grid_cell_dimensions.y)),
        //                 self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y)),
        //                 self.working_bb.left   + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x)),
        //                 self.working_bb.left   + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x + self.grid_cell_dimensions.x)),
        //             );
        //             var color = highlight_color_b;
        //             color.a = 50;
        //             try renderer.add_quad_from_bb(option_bb, color);
        //         }
        //     }

        //     pub fn tile_clicked(self: GridThingy) ?usize {
        //         if (self.just_selected) return self.selected.*.?;
        //         return null;
        //     }
        //     pub fn tile_clicking(self: GridThingy) ?usize {
        //         if (self.click_and_dragging) return self.hovered.*.?;
        //         return null;
        //     }

        // };

        // fn selection_grid(grid_dimensions: Vec2(usize), grid_cell_dimensions: Vec2(usize), selected: *?usize, hovered: *?usize, allow_deselect: bool) GridThingy {
        //     const element_bb = increment_column_bb(
        //         @as(f32,@floatFromInt(grid_cell_dimensions.y*grid_dimensions.y)) + padding*2,
        //         @as(f32,@floatFromInt(grid_cell_dimensions.x*grid_dimensions.x)) + padding*2
        //     );
        //     const working_bb = BoundingBox(f32).from(element_bb.top-padding, element_bb.bottom+padding, element_bb.left+padding, element_bb.left+padding + @as(f32,@floatFromInt(grid_cell_dimensions.x*grid_dimensions.x)));

        //     // find out if any option is hovered
        //     if (working_bb.contains_exclusive(mouse_position)) {
        //         const mouse_in_surface = mouse_position.substract(working_bb.bl()).to(usize);
        //         const mouse_tile_in_surface = Vec2(usize).from(mouse_in_surface.x/grid_cell_dimensions.x, mouse_in_surface.y/grid_cell_dimensions.y);
        //         const hovered_tile_index = mouse_tile_in_surface.x + mouse_tile_in_surface.y*grid_dimensions.x;
        //         std.debug.assert(hovered_tile_index >= 0 and hovered_tile_index < grid_dimensions.x*grid_dimensions.y);
        //         hovered.* = hovered_tile_index;
        //     }
        //     else hovered.* = null;

        //     // selecting and selection-clear logic
        //     var click_and_dragging = false;
        //     if (mouse_down) if (hovered.*) |_| {
        //         click_and_dragging = true;
        //     };

        //     var just_selected = false;
        //     if (mouse_click) if (hovered.*) |hovered_index| {
        //         if (selected.*) |selected_index| {
        //             if (allow_deselect and selected_index == hovered_index) selected.* = null
        //             else {
        //                 just_selected = true;
        //                 selected.* = hovered_index;
        //             }
        //         }
        //         else {
        //             just_selected = true;
        //             selected.* = hovered_index;
        //         }
        //     };

        //     return GridThingy {
        //         .element_bb = element_bb,
        //         .working_bb = working_bb,
        //         .grid_cell_dimensions = grid_cell_dimensions,
        //         .grid_dimensions = grid_dimensions,
        //         .hovered = hovered,
        //         .selected = selected,
        //         .just_selected = just_selected,
        //         .click_and_dragging = click_and_dragging,
        //     };
        // }
        
    };

}

pub fn ShapeRenderer(comptime output_pixel_type: type) type {
    return struct {

        const shader = struct {

            pub const Context = struct {
                mvp_matrix: M33,
            };

            pub const Invariant = struct {
                tint: RGBA,
            };

            pub const Vertex = struct {
                pos: Vector2f,
                tint: RGBA,
            };

            pub const pipeline_configuration = graphics.GraphicsPipelineQuads2DConfiguration {
                .blend_with_background = true,
                .do_quad_clipping = true,
                .do_scissoring = false,
                .trace = false
            };

            pub const Pipeline = graphics.GraphicsPipelineQuads2D(
                output_pixel_type,
                Context,
                Invariant,
                Vertex,
                pipeline_configuration,
                struct {
                    inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vec3(f32) {
                        out_invariant.tint = vertex.tint;
                        return context.mvp_matrix.apply_to_vec2(vertex.pos);
                    }
                }.vertex_shader,
                struct {
                    inline fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                        _ = context;
                        const out_color = comptime output_pixel_type.from(RGBA, color.white);
                        const tint = output_pixel_type.from(RGBA, invariants.tint);
                        return out_color.tint(tint);
                    }
                }.fragment_shader,
            );
        };

        pub fn add_quad_from_bb(vertex_buffer: *std.ArrayList(shader.Vertex), bounding_box: BoundingBox(f32), tint: RGBA) !void {
            const size = Vector2f.from(bounding_box.right - bounding_box.left, bounding_box.top - bounding_box.bottom);
            if (size.x == 0 or size.y == 0) return;
            const pos = Vector2f.from(bounding_box.left, bounding_box.bottom);
            const vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
            };
            try vertex_buffer.appendSlice(&vertices);
        }

        pub fn add_quad_border(vertex_buffer: *std.ArrayList(shader.Vertex), bounding_box: BoundingBox(f32), thickness: f32, tint: RGBA) !void {
            const line_left = BoundingBox(f32).from(bounding_box.top+thickness, bounding_box.bottom-thickness, bounding_box.left-thickness, bounding_box.left);
            const line_bottom = BoundingBox(f32).from(bounding_box.bottom, bounding_box.bottom-thickness, bounding_box.left-thickness, bounding_box.right+thickness);
            const line_right = BoundingBox(f32).from(bounding_box.top+thickness, bounding_box.bottom-thickness, bounding_box.right, bounding_box.right+thickness);
            const line_top = BoundingBox(f32).from(bounding_box.top+thickness, bounding_box.top, bounding_box.left-thickness, bounding_box.right+thickness);
            try add_quad_from_bb(vertex_buffer, line_left, tint);
            try add_quad_from_bb(vertex_buffer, line_bottom, tint);
            try add_quad_from_bb(vertex_buffer, line_right, tint);
            try add_quad_from_bb(vertex_buffer, line_top, tint);
        }
        
        pub fn add_quad(vertex_buffer: *std.ArrayList(shader.Vertex), pos: Vector2f, size: Vector2f, tint: RGBA) !void {
            const vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
            };
            try vertex_buffer.appendSlice(&vertices);
        }

        pub fn render_vertex_buffer(vertex_buffer: *std.ArrayList(shader.Vertex), pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            const context = shader.Context {
                .mvp_matrix = mvp_matrix,
            };
            shader.Pipeline.render(pixel_buffer, context, vertex_buffer.items, @divExact(vertex_buffer.items.len, 4), .{ .viewport_matrix = viewport_matrix, });
        }
    
    };
}
