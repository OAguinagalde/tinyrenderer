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
    .layout = .{
        .char_height = 5,
        .char_width = 4,
        .widget_margin  = 1,
        .widget_padding = 1,
        .container_padding = 1,
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
    state.ui.init();
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
    
    var builder = state.ui.prepare_frame(ud.allocator, .{
        .mouse_pos = ud.mouse,
        .mouse_down = ud.mouse_left_down,
    });

    const static = struct {
        var toggle = false;
    };
    var window = builder.begin("window", bb(hi-50, hi-90, 10, 100));{
        try window.header("This is a window", .{});
        try window.label("button:", .{});
        if (try window.button("debug", .{})) static.toggle = !static.toggle;
        try window.label("the end!", .{});
    }

    if (static.toggle) {
        var debug = builder.begin("debug", bb(hi, 0, 0, wi)); {
            try debug.label("some debug message", .{});
            try debug.header("This is a window", .{});
            if (try debug.button("count: {d}", .{state.count})) state.count += 1;
        }
    }
    
    var shape_vertex_buffer = std.ArrayList(ShapeRenderer(platform.OutPixelType).shader.Vertex).init(ud.allocator);
    var text_renderer = try TextRenderer.init(ud.allocator);
    for (builder.draw_calls.shape.items) |draw_call_shape| {
        try ShapeRenderer(platform.OutPixelType).add_quad_from_bb(&shape_vertex_buffer, draw_call_shape.bounding_box, switch (draw_call_shape.style) {
            .base => color.palette_4,
            .accent => color.palette_3,
            .highlight => color.palette_2,
            .special => color.palette_1,
        });
    }
    for (builder.draw_calls.text.items) |draw_call_text| {
        try text_renderer.print(draw_call_text.pos, "{s}", .{draw_call_text.text}, switch (draw_call_text.style) {
            .base => color.palette_0,
            .accent => color.palette_1,
            .highlight => color.palette_2,
            .special => color.palette_3,
        });
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
    layout: ImmediateUiLayoutConfig,
};

const ImmediateUiIo = struct {
    mouse_pos: Vec2(i32) = v2(0, 0),
    mouse_down: bool = false,
};

const Style = enum {
    base,
    accent,
    highlight,
    special,
};

const MouseStateType = enum { free, press, drag, release };

const MouseEvent = struct {
    st: MouseStateType = .free,
    relevant_id: ?u64 = 0,
    pos: Vec2(i32) = v2(0,0)
};

fn ImmediateUi(comptime config: ImmediateUiConfig) type {
    return struct {
    
        const Self = @This();

        const WidgetType = enum {
            header,
            label,
            button,
        };

        const ContainerPersistent = struct {
            valid: bool = false,
            parent_hash: u64 = undefined,
            unique_identifier: u64 = undefined,
            id: []const u8 = undefined,
            bounding_box: BoundingBox(i32) = undefined,
        };

        const Container = struct {
            builder: *UiBuilder,
            persistent: *ContainerPersistent,
            bounding_box_free: BoundingBox(i32) = undefined,
            mouse_event: ?MouseEvent,

            pub fn header(self: *Container, comptime fmt: []const u8, args: anytype) !void {
                
                // compute the space required
                const available_vetical_space = self.bounding_box_free.height();
                const required_vetical_space = 
                    config.layout.container_padding +
                    config.layout.widget_margin +
                    config.layout.char_height +
                    config.layout.widget_margin
                ;

                if (available_vetical_space < required_vetical_space) return;

                // compute the everything required to render the header
                const text_position = v2(
                    self.bounding_box_free.left + config.layout.container_padding,
                    self.bounding_box_free.top - required_vetical_space + config.layout.widget_margin,
                );
                const out = self.bounding_box_free.shrink(.top, required_vetical_space);
                const header_bb: BoundingBox(i32) = out.leftover;
                const bounding_box_free_updated = out.shrinked;

                // make a copy of the string to be printed
                
                const len = std.fmt.count(fmt, args);
                const slice = try self.builder.string_data.addManyAsSlice(len);
                const str = std.fmt.bufPrint(slice, fmt, args) catch unreachable;
                
                // handle moving the container by clicking and dragging the header
                var is_hovering = false;
                var container_offset: ?Vec2(i32) = null;
                if (self.mouse_event) |me| switch (me.st) {
                    .free => if (header_bb.contains(me.pos)) {
                        is_hovering = true;
                        self.mouse_event = null;
                    },
                    .press => if (header_bb.contains(me.pos)) {
                        const parent_hash = self.persistent.parent_hash;
                        const header_hash = @addWithOverflow(parent_hash, @addWithOverflow(@as(u64, @intFromEnum(WidgetType.header)), core.djb2(fmt))[0])[0];
                        self.builder.parent_ui.id_active = header_hash;
                        self.builder.mouse_event = null;
                        self.mouse_event = null;
                    },
                    .drag => {
                        const parent_hash = self.persistent.parent_hash;
                        const header_hash = @addWithOverflow(parent_hash, @addWithOverflow(@as(u64, @intFromEnum(WidgetType.header)), core.djb2(fmt))[0])[0];
                        if (me.relevant_id!=null and me.relevant_id.? == header_hash) {
                            self.builder.parent_ui.id_active = header_hash;
                            container_offset = me.pos;
                            self.builder.mouse_event = null;
                            self.mouse_event = null;
                        }
                    },
                    .release => {
                        const parent_hash = self.persistent.parent_hash;
                        const header_hash = @addWithOverflow(parent_hash, @addWithOverflow(@as(u64, @intFromEnum(WidgetType.header)), core.djb2(fmt))[0])[0];
                        if (me.relevant_id!=null and me.relevant_id.? == header_hash) {
                            self.builder.parent_ui.id_active = null;
                            self.builder.mouse_event = null;
                            self.mouse_event = null;
                            // TODO the mouse might have moved and released so... track movement in release event as well, maybe
                        }
                    },
                };

                // render the header taking into account whether the container was dragged or not
                if (container_offset) |offset| {
                    self.bounding_box_free = bounding_box_free_updated.offset(offset);
                    self.persistent.bounding_box = self.persistent.bounding_box.offset(offset);
                    try self.builder.render_square(header_bb.offset(offset), if (is_hovering) .highlight else .special);
                    try self.builder.render_text(str, text_position.add(offset), .special);
                }
                else {
                    self.bounding_box_free = bounding_box_free_updated;
                    try self.builder.render_square(header_bb, if (is_hovering) .highlight else .special);
                    try self.builder.render_text(str, text_position, .special);
                }

            }

            pub fn label(self: *Container, comptime fmt: []const u8, args: anytype) !void {
                const available_vetical_space = self.bounding_box_free.height();
                const required_vetical_space = 
                    config.layout.widget_margin +
                    config.layout.char_height +
                    config.layout.widget_margin
                ;
                
                if (available_vetical_space < required_vetical_space) return;

                const text_position = v2(
                    self.bounding_box_free.left + config.layout.container_padding,
                    self.bounding_box_free.top - required_vetical_space + config.layout.widget_margin,
                );
                self.bounding_box_free = self.bounding_box_free.shrink(.top, required_vetical_space).shrinked;

                // make a copy of the string to be printed
                const len = std.fmt.count(fmt, args);
                const slice = try self.builder.string_data.addManyAsSlice(len);
                const str = std.fmt.bufPrint(slice, fmt, args) catch unreachable;

                try self.builder.render_text(str, text_position, .special);
            }

            const ButtonState = enum {
                normal,
                hover,
                pressed,
                clicked
            };

            pub fn button(self: *Container, comptime fmt: []const u8, args: anytype) !bool {
                
                // compute the space required
                const space_available_vetical = self.bounding_box_free.height();
                const space_available_horizontal = self.bounding_box_free.width();
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
                    self.bounding_box_free.left + config.layout.container_padding + config.layout.widget_margin + config.layout.widget_padding,
                    self.bounding_box_free.top - space_required_vertical + config.layout.widget_margin + config.layout.widget_padding,
                );
                const out = self.bounding_box_free.shrink(.top, space_required_vertical);
                self.bounding_box_free = out.shrinked;
                const iner_bb: BoundingBox(i32) = out.leftover.get_inner_bb_with_padding(config.layout.widget_margin);
                const button_bb: BoundingBox(i32) = iner_bb.shrink(.right, space_available_horizontal - space_required_horizontal).shrinked;

                // make a copy of the string to be printed
                const slice = try self.builder.string_data.addManyAsSlice(len);
                const str = std.fmt.bufPrint(slice, fmt, args) catch unreachable;

                var button_state: ButtonState = .normal;
                
                // handle the clicking the button logic
                if (self.mouse_event) |me| switch (me.st) {
                    .free => if (button_bb.contains(me.pos)) {
                        button_state = .hover;
                        self.mouse_event = null;
                        self.builder.mouse_event = null;
                    },
                    .press => if (button_bb.contains(me.pos)) {
                        const parent_hash = self.persistent.parent_hash;
                        const button_hash = @addWithOverflow(parent_hash, @addWithOverflow(@as(u64, @intFromEnum(WidgetType.button)), core.djb2(fmt))[0])[0];
                        self.builder.parent_ui.id_active = button_hash;
                        button_state = .pressed;
                        self.builder.mouse_event = null;
                        self.mouse_event = null;
                    },
                    .drag => {
                        const parent_hash = self.persistent.parent_hash;
                        const button_hash = @addWithOverflow(parent_hash, @addWithOverflow(@as(u64, @intFromEnum(WidgetType.button)), core.djb2(fmt))[0])[0];
                        if (me.relevant_id!=null and me.relevant_id.? == button_hash) {
                            self.builder.parent_ui.id_active = button_hash;
                            button_state = .pressed;
                            self.mouse_event = null;
                            self.builder.mouse_event = null;
                        }
                    },
                    .release => {
                        const parent_hash = self.persistent.parent_hash;
                        const button_hash = @addWithOverflow(parent_hash, @addWithOverflow(@as(u64, @intFromEnum(WidgetType.button)), core.djb2(fmt))[0])[0];
                        if (me.relevant_id!=null and me.relevant_id.? == button_hash) {
                            self.builder.parent_ui.id_active = null;
                            if (button_bb.contains(me.pos)) button_state = .clicked;
                            self.mouse_event = null;
                            self.builder.mouse_event = null;
                        }
                    },
                };

                const button_style: Style = switch (button_state) {
                    .normal => .base,
                    .hover => .highlight,
                    .pressed => .accent,
                    .clicked => .special,
                };
                try self.builder.render_square(button_bb, button_style);
                try self.builder.render_text(str, text_position, .base);

                return button_state == .clicked;
            }

        };

        const UiBuilder = struct {
            parent_ui: *Self,
            /// reset on prepare_frame
            string_data: std.ArrayList(u8),
            /// set on prepare_frame
            mouse_event: ?MouseEvent,
            io_previous: ImmediateUiIo,
            io: ImmediateUiIo,
            container_stack: std.BoundedArray(u64, ContainerCountMax),
            /// Each container has its own draw call buffer
            draw_calls: ContainerDrawCalls,

            inline fn render_text(self: *UiBuilder, str: []const u8, position: Vec2(i32), style: Style) !void {
                try self.draw_calls.text.append(.{
                    .text = str, .style = style, .pos = position.to(f32)
                });
            }

            inline fn render_square(self: *UiBuilder, bounding_box: BoundingBox(i32), style: Style) !void {
                try self.draw_calls.shape.append(.{
                    .bounding_box = bounding_box.to(f32), .style = style,
                });
            }


            pub fn begin(self: *UiBuilder, id: []const u8, bounding_box: BoundingBox(i32)) Container {
                const ui = self.parent_ui;
                const parent_hash = if (self.container_stack.len > 0) self.container_stack.get(self.container_stack.len-1) else 0;
                const container_persistent = ui.get_container(id, parent_hash);
                if (!container_persistent.valid) { // this happens only on the first time that a container is retrieved
                    container_persistent.valid = true;
                    container_persistent.bounding_box = bounding_box;
                    // new containers by default are put on top
                    ui.containers_order.append(container_persistent.unique_identifier) catch unreachable;
                }
                // TODO on end remove from stack
                self.container_stack.append(container_persistent.unique_identifier) catch unreachable;
                
                var mouse_event_to_pass: ?MouseEvent = null;
                if (self.mouse_event) |me| switch (me.st) {
                    .free, .press => {
                        if (container_persistent.bounding_box.contains(me.pos)) {
                            // TODO this is NOT my best work lol
                            const container_directly_under_the_mouse_is_this_one: bool = blk: {
                                var topmost_relevant_container: ?u64 = null;
                                for (ui.containers_order.slice()) |container_identifier| {
                                    const container_bounding_box = ui.get_container_by_unique_id(container_identifier).bounding_box;
                                    if (container_bounding_box.contains(me.pos)) topmost_relevant_container = container_identifier;
                                }

                                if (topmost_relevant_container) |container_id| {
                                    const relevant_container = ui.get_container_by_unique_id(container_id);
                                    break :blk relevant_container.unique_identifier == container_persistent.unique_identifier;
                                }
                                break :blk false;
                            };
                            if (container_directly_under_the_mouse_is_this_one) {
                                mouse_event_to_pass = me;
                                // Since we already know that no other container can handle the mouse event, consume it already
                                self.mouse_event = null;
                            }
                        }
                    },
                    .drag, .release => {
                        // we dont know which container is relevant for this event until the widget hash is compared so just pass it
                        // to the container until one of them handles it
                        mouse_event_to_pass = me;
                    },
                };
                return Container {
                    .builder = self,
                    .persistent = container_persistent,
                    .bounding_box_free = container_persistent.bounding_box,
                    .mouse_event = mouse_event_to_pass,
                };
            }
        };
        
        // we can have up to 16 containers
        const ContainerCountMax: usize = 16;

        /// persistent data regarding containers
        containers: [ContainerCountMax]ContainerPersistent,
        /// TODO keep track of the order of the windows in a list or something
        containers_order: std.BoundedArray(u64, ContainerCountMax),
        /// the widget id being interacted with
        id_active: ?u64,
        io_previous: ImmediateUiIo,
        
        pub fn init(self: *Self) void {
            for (&self.containers) |*c| c.* = .{};
            self.containers_order = .{};
            self.id_active = null;
            self.io_previous = .{};
        }

        pub fn prepare_frame(self: *Self, allocator: std.mem.Allocator, io: ImmediateUiIo) UiBuilder {
            const io_previous = self.io_previous;
            const mouse_went_down = !io_previous.mouse_down and io.mouse_down;
            const mouse_went_up = io_previous.mouse_down and !io.mouse_down;
            const mouse_position = io.mouse_pos;
            const mouse_movement = io.mouse_pos.substract(io_previous.mouse_pos);
            self.io_previous = io;

            const mouse_event: MouseEvent = if (mouse_went_down) .{.st = .press, .relevant_id = null, .pos = mouse_position}
                else if (mouse_went_up) .{.st = .release, .relevant_id = self.id_active, .pos = mouse_position }
                else if (io.mouse_down) .{.st = .drag, .relevant_id = self.id_active, .pos = mouse_movement }
                else .{.st = .free, .relevant_id = null, .pos = mouse_position};

            return .{
                .parent_ui = self,
                .string_data = std.ArrayList(u8).init(allocator),
                .mouse_event = mouse_event,
                .io = io,
                .io_previous = io_previous,
                .container_stack = .{},
                .draw_calls = .{
                    .text = std.ArrayList(ContainerDrawCalls.DrawCallText).init(allocator),
                    .shape = std.ArrayList(ContainerDrawCalls.DrawCallShape).init(allocator),
                }
            };
            
            // TODO since we know the positions and sizes of all the containers and their layers in the previous frame, we can calculate which container the mouse is over of right now
        }
        
        /// returns error.ContainerLimitReached when all container slots haven been taken
        fn get_container_by_unique_id(self: *Self, unique_identifier: u64) *ContainerPersistent {
            const container = &self.containers[unique_identifier];
            std.debug.assert(container.valid);
            return container;
        }

        fn get_container(self: *Self, id: []const u8, parent_hash: u64) *ContainerPersistent {
            // when a container is requested, its id is used to generate a hash that must be unique
            const hash = @addWithOverflow(core.djb2(id), parent_hash)[0];
            const index_initial = hash % ContainerCountMax;
            // the hash is used to index into the containers array and retrieve it in following frames
            for (0..ContainerCountMax) |containers_checked| {
                const index = index_initial+containers_checked % ContainerCountMax;
                const container: *ContainerPersistent = &self.containers[index];
                if (container.valid) {
                    const same_container = std.mem.eql(u8, id, container.id) and parent_hash == container.parent_hash;
                    // container already existed, just return it
                    if (same_container) return container
                    // there is a collision, check the next one
                    else continue;
                }
                // container didn't exist yet, set it and return it
                else {
                    container.id = id;
                    container.parent_hash = parent_hash;
                    container.unique_identifier = index;
                    return container;
                }
            }
            @panic("Not enough containers!");
        }

        pub const ContainerDrawCalls = struct {
            text: std.ArrayList(DrawCallText),
            shape: std.ArrayList(DrawCallShape),
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
