const std = @import("std");
const builtin = @import("builtin");
const math = @import("math.zig");
const graphics = @import("graphics.zig");
const font = @import("text.zig").font;
const core = @import("core.zig");

const BoundingBox = math.BoundingBox;
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vec2 = math.Vec2;
const M44 = math.M44;
const M33 = math.M33;
const Buffer2D = @import("buffer.zig").Buffer2D;
const RGB = @import("pixels.zig").RGB;
const RGBA = @import("pixels.zig").RGBA;
const BGR = @import("pixels.zig").BGR;

const windows = @import("windows.zig");
const wasm = @import("wasm.zig");
const platform = if (builtin.os.tag == .windows) windows else wasm;

const Application = platform.Application(.{
    .init = init,
    .update = update,
    .dimension_scale = 2,
    .desired_width = 240*3,
    .desired_height = 136*3,
});

// TODO: currently the wasm target only works if the exported functions are explicitly referenced.
// The reason for this is that zig compiles lazily. By referencing Platform.run, the comptime code
// in that funciton is executed, which in turn references the exported functions, making it so
// that those are "found" by zig and properly exported.
comptime {
    if (@This() == @import("root")) {
        _ = Application.run;
    }
}

pub fn main() !void {
    try Application.run();
}

const text_scale = 1;
const State = struct {
    renderer: Renderer(platform.OutPixelType),
    resources: Resources,
    resource_file_name: []const u8,
};

var state: State = undefined;

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    state.renderer = try Renderer(platform.OutPixelType).init(allocator);
    state.resource_file_name = "res/resources.bin";
    state.resources = Resources.init(allocator);
    if (builtin.os.tag == .windows) {
        const file = try std.fs.cwd().openFile(state.resource_file_name, .{});
        defer file.close();
        // try state.resources.load_from_bytes(file.reader());
        var fbs = std.io.fixedBufferStream(try file.reader().readAllAlloc(allocator, 999999));
        const reader = fbs.reader(); 
        // for (0..10) |i| {
        //     const b = try reader.readByte();
        //     std.log.debug("b[{}]: {}", .{i, b});
        // }
        try state.resources.load_from_bytes(reader);
        finished = true;
    }
    else {

        const resources_loading_stuff = struct {

            const Context = struct {
                allocator: std.mem.Allocator,
                resources: *Resources,
            };

            fn finish_loading_resource_file(bytes: []const u8, context: []const u8) !void {
                var ctx: Context = undefined;
                core.value(&ctx, context);
                // for (bytes, 0..) |b, i| {
                //     if (i < 10) Application.flog("b[{}]: {}", .{i, b});
                // }
                defer ctx.allocator.free(bytes);
                var fbs = std.io.fixedBufferStream(bytes);
                const reader = fbs.reader(); 
                try ctx.resources.*.load_from_bytes(reader);
                finished = true;
            }

        };

        try Application.read_file(state.resource_file_name, resources_loading_stuff.finish_loading_resource_file, resources_loading_stuff.Context { .allocator = allocator, .resources = &state.resources });
    }
}

var finished = false;

pub fn update(ud: *platform.UpdateData) anyerror!bool {
    if (!finished) return true;
    const clear_color: BGR = @bitCast(assets.palette[0]);
    ud.pixel_buffer.clear(platform.OutPixelType.from(BGR, clear_color));
    
    const h: f32 = @floatFromInt(ud.pixel_buffer.height);
    const w: f32 = @floatFromInt(ud.pixel_buffer.width);

    const viewport_matrix = M33.viewport(0, 0, w, h);
    const projection_matrix_screen = M33.orthographic_projection(0, w, h, 0);

    // already takes into account native scaling if in use
    const mouse_window: Vector2f = blk: {
        const mx = @divFloor(ud.mouse.x, Application.dimension_scale);
        // inverse y since mouse is given relative to top left corner
        const my = @divFloor((Application.height*Application.dimension_scale) - ud.mouse.y, Application.dimension_scale);
        break :blk Vector2i.from(mx, my).to(f32);
    };
    
    if (ud.key_pressed('L')) {
            if (builtin.os.tag == .windows) {
                const file = try std.fs.cwd().openFile(state.resource_file_name, .{});
                defer file.close();
                try state.resources.load_from_bytes(file.reader());
            } else {

            }
    }
    if (ud.key_pressed('M')) {
        if (builtin.os.tag == .windows) {
            try state.resources.save_to_file(ud.allocator, state.resource_file_name);
        } else {

        }
    }
    
    const junctions_menu_data = struct {
        var option_selected: ?usize = null;
        var option_hovered: ?usize = null;
        const options: []const []const u8 = blk: {
            var opts: []const []const u8 = &[_][]const u8 {};
            opts = opts ++ &[_][]const u8{"add junction"};
            opts = opts ++ &[_][]const u8{"delete junction"};
            break :blk opts;
        };
    };

    const entity_spawner_menu_data = struct {
        var option_selected: ?usize = null;
        var option_hovered: ?usize = null;
        const options: []const []const u8 = blk: {
            var opts: []const []const u8 = &[_][]const u8 {};
            opts = opts ++ &[_][]const u8{};
            for (@typeInfo(assets.EntityType).Enum.fields) |field| {
                opts = opts ++ &[_][]const u8{field.name};
            }
            opts = opts ++ &[_][]const u8{"delete spawner"};
            break :blk opts;
        };
    };
    
    const particle_emitter_menu_data = struct {
        var option_selected: ?usize = null;
        var option_hovered: ?usize = null;
        const options: []const []const u8 = blk: {
            var opts: []const []const u8 = &[_][]const u8 {};
            opts = opts ++ &[_][]const u8{};
            for (@typeInfo(assets.ParticleEmitterType).Enum.fields) |field| {
                opts = opts ++ &[_][]const u8{field.name};
            }
            opts = opts ++ &[_][]const u8{"delete emitter"};
            break :blk opts;
        };
    };
    
    const sprite_selector_window_data = struct {
        var sprite_selected: ?usize = 0;
        var sprite_hovered: ?usize = null;
        var quick_select_sprite_selected: ?usize = 0;
        var quick_select_sprite_hovered: ?usize = null;
        var quick_select_indices: [8]?usize = [_]?usize {null} ** 8;
    };
   
    const MapEditActionType = enum {
        /// the default state, do nothing
        none,
        /// "paint" the map with tiles from the sprite atlas
        modify_map,
        /// add or remove entity spawners based on the wahtever is selected on the respective menu
        modify_entity_spawners,
        /// add or remove particle emitters based on the wahtever is selected on the respective menu
        modify_particle_emitters,
        /// drag things around. Move spawners, particle emitters, junctions....
        modify_position_of_selected_item,
        /// change the size and position of the level boxes
        /// TODO add or remove level boxes themselves
        modify_level_boxes,
        /// add or remove level junctions
        modify_junctions
    };

    const map_editor_data = struct {
        const size = Vec2(usize).from(60,39);
        var map_tile_selected: ?usize = 0;
        var map_tile_hovered: ?usize = null;
        var map_tile_bb = BoundingBox(usize).from(size.y-1, 0, 0, size.x-1);
        var surface: Buffer2D(platform.OutPixelType) = undefined;
        var initialized = false;
        var edit_action_type: MapEditActionType = .none;
    };

    if (!map_editor_data.initialized) {
        map_editor_data.initialized = true;
        map_editor_data.surface = Buffer2D(platform.OutPixelType).from(try ud.allocator.alloc(platform.OutPixelType, map_editor_data.size.x*8*map_editor_data.size.y*8), map_editor_data.size.x*8);
    }

    const sprite_editor_data = struct {
        var sprite_selected: usize = 0;
        var sprite_editor_cell_selected: ?usize = 0;
        var sprite_editor_cell_hovered: ?usize = null;
        var palette_selected: ?usize = 0;
        var palette_hovered: ?usize = null;
        var surface_sprite: Buffer2D(platform.OutPixelType) = undefined;
        var surface_palette: Buffer2D(platform.OutPixelType) = undefined;
        var initialized = false;
    };

    if (!sprite_editor_data.initialized) {
        sprite_editor_data.initialized = true;
        sprite_editor_data.surface_sprite = Buffer2D(platform.OutPixelType).from(try ud.allocator.alloc(platform.OutPixelType, 8*8*8*8), 8*8);
        sprite_editor_data.surface_palette = Buffer2D(platform.OutPixelType).from(try ud.allocator.alloc(platform.OutPixelType, 16), 8);
        for (assets.palette, 0..) |color, i| sprite_editor_data.surface_palette.data[i] = platform.OutPixelType.from(BGR, @bitCast(color));
    }

    const mouse_state = struct {
        var click_captured = false;
        var down_captured = false;
        var frame_clicked = false;
        var frame_down = false;
        fn setup(_clicked: bool, _down: bool) void {
            frame_clicked = _clicked;
            frame_down = _down;
        }
        fn clicked() bool {
            return !click_captured and frame_clicked;
        }
        fn down() bool {
            return !down_captured and frame_down;
        }
        fn capture_click() void {
            click_captured = true;
        }
        fn capture_down() void {
            down_captured = true;
        }
    };

    mouse_state.setup(ud.mouse_left_clicked, ud.mouse_left_down);
    
    const sprite_editor = Container("sprite_editor");
    if (try sprite_editor.begin(ud.allocator, "sprite editor", Vec2(f32).from(4,h-120), mouse_window, mouse_state.clicked(), mouse_state.down(), ud.pixel_buffer, projection_matrix_screen, viewport_matrix)) {
        
        if (sprite_selector_window_data.sprite_selected) |selected| sprite_editor_data.sprite_selected = selected;

        try sprite_editor.text_line_fmt("Selected: {}", .{sprite_editor_data.sprite_selected});
        
        const palette_grid = sprite_editor.selection_grid(Vec2(usize).from(8,2), Vec2(usize).from(4,4), &sprite_editor_data.palette_selected, &sprite_editor_data.palette_hovered, false);
        try palette_grid.fill_with_texture(sprite_editor_data.surface_palette);
        try palette_grid.highlight_hovered();
        
        const sprite_grid = sprite_editor.selection_grid(Vec2(usize).from(8,8), Vec2(usize).from(8,8), &sprite_editor_data.sprite_editor_cell_selected, &sprite_editor_data.sprite_editor_cell_hovered, false);
        if (sprite_grid.tile_clicking()) |pixel_index| {
            if (sprite_editor_data.palette_selected) |palette_index| {
                const sprite_x = sprite_editor_data.sprite_selected % 16;
                const sprite_y = @divFloor(sprite_editor_data.sprite_selected, 16);
                const x = 8*sprite_x + (pixel_index % 8);
                const y = 8*sprite_y + @divFloor(pixel_index, 8);
                state.resources.sprite_atlas[x + y*(8*16)] = @intCast(palette_index);
            }
        }

        state.renderer.set_context(sprite_editor_data.surface_sprite, M33.orthographic_projection(0, 8, 8, 0), M33.viewport(0, 0, 8*8, 8*8));
        try state.renderer.add_sprite_from_atlas_by_index(Vec2(usize).from(8, 8), Vec2(usize).from(16, 16), @constCast(&assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 8*16), sprite_editor_data.sprite_selected, BoundingBox(f32).from(8,0,0,8), .{});
        try state.renderer.flush_all();

        try sprite_grid.fill_with_texture(sprite_editor_data.surface_sprite);
        try sprite_grid.highlight_hovered();
    }
    try sprite_editor.end();

    const map_editor = Container("map_editor");
    if (try map_editor.begin(ud.allocator, "map editor", Vec2(f32).from(100, h-44), mouse_window, mouse_state.clicked(), mouse_state.down(), ud.pixel_buffer, projection_matrix_screen, viewport_matrix)) {
        
        var is_dragging_enabled = map_editor_data.edit_action_type == .modify_position_of_selected_item;
        if (try map_editor.button("drag things around", &is_dragging_enabled)) {
            map_editor_data.edit_action_type = .modify_position_of_selected_item;
        }

        var is_modifying_level_boxes = map_editor_data.edit_action_type == .modify_level_boxes;
        if (try map_editor.button("modify level boxes", &is_modifying_level_boxes)) {
            map_editor_data.edit_action_type = .modify_level_boxes;
        }

        const junctions_menu = map_editor;
        {
            if (junctions_menu_data.option_selected) |selected| try junctions_menu.text_line_fmt("· junctions: {}", .{selected})
            else try junctions_menu.text_line("· junctions: ");
            const selection_grid = try junctions_menu.selection_grid_from_text_options(junctions_menu_data.options, &junctions_menu_data.option_selected, &junctions_menu_data.option_hovered, false);
            if (selection_grid.tile_clicked()) |_| {
                map_editor_data.edit_action_type = .modify_junctions;
            }
        }
        
        try map_editor.separator(0);
        try map_editor.separator(0);
        
        const entity_spawner_menu = map_editor;
        {
            
            const cosa = struct {
                var my_boolean: bool = false;
            };

            if (try entity_spawner_menu.button("Hola que tal", &cosa.my_boolean)) {
                try entity_spawner_menu.text_line("clicked");
            }
            
            if (entity_spawner_menu_data.option_selected) |selected| try entity_spawner_menu.text_line_fmt("· entities: {}", .{selected})
            else try entity_spawner_menu.text_line("· entities: ");
            const selection_grid = try entity_spawner_menu.selection_grid_from_text_options(entity_spawner_menu_data.options, &entity_spawner_menu_data.option_selected, &entity_spawner_menu_data.option_hovered, false);
            if (selection_grid.tile_clicked()) |_| {
                map_editor_data.edit_action_type = .modify_entity_spawners;
            }
        }
        
        try map_editor.separator(0);
        try map_editor.separator(0);
        
        const particle_emitter_menu = map_editor;
        {
            if (particle_emitter_menu_data.option_selected) |selected| try particle_emitter_menu.text_line_fmt("· particles: {}", .{selected})
            else try particle_emitter_menu.text_line("· particles: ");
            const selection_grid = try particle_emitter_menu.selection_grid_from_text_options(particle_emitter_menu_data.options, &particle_emitter_menu_data.option_selected, &particle_emitter_menu_data.option_hovered, false);
            if (selection_grid.tile_clicked()) |_| {
                map_editor_data.edit_action_type = .modify_particle_emitters;
            }
        }

        try map_editor.separator(0);
        try map_editor.separator(0);

        const sprite_selector_window = map_editor;
        {
            if (sprite_selector_window_data.sprite_selected) |selected| try sprite_selector_window.text_line_fmt("· sprites: {}", .{selected})
            else try sprite_selector_window.text_line("· sprites: ");
            
            const sprite_quick_select_grid = sprite_selector_window.selection_grid(Vec2(usize).from(8,1), Vec2(usize).from(8,8), &sprite_selector_window_data.quick_select_sprite_selected, &sprite_selector_window_data.quick_select_sprite_hovered, false);
            for (0..8) |i| {
                if (ud.key_pressed(49 + i)) {
                    sprite_selector_window_data.quick_select_sprite_selected = i;
                    map_editor_data.edit_action_type = .modify_map;
                }
                if (sprite_selector_window_data.quick_select_indices[i]) |sprite_index| {
                    const sprite_uv_bb = BoundingBox(usize).from_indexed_grid(Vec2(usize).from(16,16), Vec2(usize).from(8,8), sprite_index, false);
                    try sprite_quick_select_grid.fill_index_with_palette_based_textured_quad(i, sprite_uv_bb.to(f32), Buffer2D(u4).from(&state.resources.sprite_atlas, 8*16), @constCast(&assets.palette));
                }
            }
            try sprite_quick_select_grid.highlight_hovered();
            try sprite_quick_select_grid.highlight_selected();

            const sprite_grid = sprite_selector_window.selection_grid(Vec2(usize).from(16,16), Vec2(usize).from(8,8), &sprite_selector_window_data.sprite_selected, &sprite_selector_window_data.sprite_hovered, false);
            try sprite_grid.fill_with_palette_based_texture(Buffer2D(u4).from(&state.resources.sprite_atlas, 8*16), @constCast(&assets.palette));
            try sprite_grid.highlight_hovered();
            
            if (sprite_grid.tile_clicked()) |index| {
                map_editor_data.edit_action_type = .modify_map;
                sprite_selector_window_data.quick_select_indices[sprite_selector_window_data.quick_select_sprite_selected.?] = index;
            }
        }

        map_editor.layout_next_column();

        // TODO make a in-editor log

        if (ud.key_pressing('D') and map_editor_data.map_tile_bb.right < 240-1) map_editor_data.map_tile_bb = map_editor_data.map_tile_bb.offset(Vec2(usize).from(1, 0));
        if (ud.key_pressing('W') and map_editor_data.map_tile_bb.top < 136-1) map_editor_data.map_tile_bb = map_editor_data.map_tile_bb.offset(Vec2(usize).from(0, 1));
        if (ud.key_pressing('S') and map_editor_data.map_tile_bb.bottom > 0) map_editor_data.map_tile_bb = map_editor_data.map_tile_bb.offset_negative(Vec2(usize).from(0, 1));
        if (ud.key_pressing('A') and map_editor_data.map_tile_bb.left > 0) map_editor_data.map_tile_bb = map_editor_data.map_tile_bb.offset_negative(Vec2(usize).from(1, 0));
        
        const map_editor_tile_grid = map_editor.selection_grid(map_editor_data.size, Vec2(usize).from(8,8), &map_editor_data.map_tile_selected, &map_editor_data.map_tile_hovered, false);
        if (map_editor_tile_grid.tile_clicking()) |tile_index| {
            const map_tile_clicked = Vec2(usize).from(
                map_editor_data.map_tile_bb.left + tile_index % map_editor_data.size.x,
                map_editor_data.map_tile_bb.bottom + @divFloor(tile_index, map_editor_data.size.x)
            ).to(u8);
            switch (map_editor_data.edit_action_type) {
                .modify_map => {
                    if (sprite_selector_window_data.quick_select_sprite_selected) |quic_select_index| {
                        if (sprite_selector_window_data.quick_select_indices[quic_select_index]) |sprite_index| {
                            state.resources.map[map_tile_clicked.y][map_tile_clicked.x] = @intCast(sprite_index);
                        }
                    }
                },
                .modify_entity_spawners => {
                    const option_selected = entity_spawner_menu_data.option_selected.?;
                    // NOTE the last option is hardcoded to be "delete" which is the only way of deleting entity spawners currently
                    if (option_selected == entity_spawner_menu_data.options.len-1) {
                        for (state.resources.entity_spawners.items, 0..) |pe, i| {
                            if (pe.pos.equal(map_tile_clicked)) {
                                _ = state.resources.entity_spawners.orderedRemove(i);
                                break;
                            }
                        }
                    }
                    else {
                        try state.resources.entity_spawners.append(.{
                            .pos = map_tile_clicked,
                            .entity_type = @intCast(option_selected)
                        });
                    }
                },
                .modify_particle_emitters => {
                    const option_selected = particle_emitter_menu_data.option_selected.?;
                    // NOTE the last option is hardcoded to be "delete" which is the only way of deleting entity spawners currently
                    if (option_selected == particle_emitter_menu_data.options.len-1) {
                        for (state.resources.environment_particle_emitters.items, 0..) |pe, i| {
                            if (pe.pos.equal(map_tile_clicked)) {
                                _ = state.resources.environment_particle_emitters.orderedRemove(i);
                                break;
                            }
                        }
                    }
                    else {
                        try state.resources.environment_particle_emitters.append(.{
                            .pos = map_tile_clicked,
                            .particle_emitter_type = @intCast(option_selected)
                        });
                    }
                },
                .modify_position_of_selected_item => {
                    
                    const static_data = struct {
                        var dragged_index: ?usize = null;
                        var last_draged_drame: usize = 0;
                        fn stop_dragging() void {
                            dragged_index = null;
                        }
                        fn start_dragging(i: usize) void {
                            dragged_index = i;
                        }
                    };
                    
                    // NOTE if we were not dragging on the previous frame, it means that
                    // at some point we stopped dragging any item so reset the dragging related state
                    if (static_data.last_draged_drame != ud.frame - 1) static_data.stop_dragging();

                    if (static_data.dragged_index == null) {
                        // If we are not dragging anything from previous frames but are trying to drag something, find what it is, and set it as dragging
                        var index_offset: usize = undefined;
                        const map_tile_clicked_u8 = map_tile_clicked.to(u8);

                        index_offset = 0;
                        for (state.resources.junctions.items, 0..) |junction, index| {
                            if (junction.a.equal(map_tile_clicked_u8)) {
                                static_data.start_dragging(index_offset + index*2);
                                break;
                            }
                            else if (junction.b.equal(map_tile_clicked_u8)) {
                                static_data.start_dragging(index_offset + index*2 + 1);
                                break;
                            }
                        }

                        index_offset += state.resources.junctions.items.len*2;
                        if (static_data.dragged_index == null) for (state.resources.entity_spawners.items, 0..) |entity_spawner, index| {
                            if (entity_spawner.pos.equal(map_tile_clicked_u8)) {
                                static_data.start_dragging(index_offset + index);
                                break;
                            }
                        };

                        index_offset += state.resources.entity_spawners.items.len;
                        if (static_data.dragged_index == null) for (state.resources.environment_particle_emitters.items, 0..) |particle_emitter, index| {
                            if (particle_emitter.pos.equal(map_tile_clicked_u8)) {
                                static_data.start_dragging(index_offset + index);
                                break;
                            }
                        };
                    }

                    if (static_data.dragged_index) |dragged_index| {
                        // `dragged_index` is already being dragged from previous frames
                        // we can calculate the exact item we are dragging since 
                        if (dragged_index<state.resources.junctions.items.len*2) {
                            const real_index = @divFloor(dragged_index, 2);
                            const junction = &state.resources.junctions.items[real_index];
                            if (real_index*2 == dragged_index) junction.a = map_tile_clicked.to(u8)
                            else junction.b = map_tile_clicked.to(u8);
                        }
                        else if (dragged_index < state.resources.junctions.items.len*2 + state.resources.entity_spawners.items.len) {
                            const offset_index: usize = state.resources.junctions.items.len*2;
                            const real_index = dragged_index - offset_index;
                            const entity_spawner = &state.resources.entity_spawners.items[real_index];
                            entity_spawner.pos = map_tile_clicked.to(u8);
                            
                        }
                        else if (dragged_index < state.resources.junctions.items.len*2 + state.resources.entity_spawners.items.len + state.resources.environment_particle_emitters.items.len) {
                            const offset_index: usize = state.resources.junctions.items.len*2 + state.resources.entity_spawners.items.len;
                            const real_index = dragged_index - offset_index;
                            const particle_emitter = &state.resources.environment_particle_emitters.items[real_index];
                            particle_emitter.pos = map_tile_clicked.to(u8);
                        }
                        else unreachable;

                        static_data.last_draged_drame = ud.frame;
                    }
                },
                .modify_level_boxes => {

                    const BoxAndSide = struct {
                        index: usize,
                        side: math.BoundingBoxSide,
                    };

                    const static_data = struct {
                        var box_being_modified: ?BoxAndSide = null;
                        var last_frame_modified: usize = 0;
                        fn stop_dragging() void {
                            box_being_modified = null;
                        }
                        fn start_dragging(i: usize, side: math.BoundingBoxSide) void {
                            box_being_modified = .{
                                .index = i,
                                .side = side,
                            };
                        }
                    };

                    // NOTE if we were not dragging on the previous frame, it means that
                    // at some point we stopped dragging any item so reset the dragging related state
                    if (static_data.last_frame_modified != ud.frame - 1) static_data.stop_dragging();

                    // If we are not dragging anything from previous frames but are trying to drag something, find what it is, and set it as dragging
                    if (static_data.box_being_modified == null) {
                                                
                        for (state.resources.levels.items, 0..) |l, i| {
                            
                            const level_bb = blk: {
                                var bb = l.bb;
                                bb.right += 1;
                                bb.top += 1;
                                break :blk bb;
                            };

                            const distance = 1;
                            if (@abs(@as(i32,@intCast(level_bb.left)) - @as(i32,@intCast(map_tile_clicked.x))) < distance and map_tile_clicked.y > level_bb.bottom and map_tile_clicked.y < level_bb.top) {
                                static_data.start_dragging(i, .left);
                                break;
                            }
                            else if (@abs(@as(i32,@intCast(level_bb.right)) - @as(i32,@intCast(map_tile_clicked.x))) < distance and map_tile_clicked.y > level_bb.bottom and map_tile_clicked.y < level_bb.top) {
                                static_data.start_dragging(i, .right);
                                break;
                            }
                            else if (@abs(@as(i32,@intCast(level_bb.top)) - @as(i32,@intCast(map_tile_clicked.y))) < distance and map_tile_clicked.x > level_bb.left and map_tile_clicked.x < level_bb.right) {
                                static_data.start_dragging(i, .top);
                                break;
                            }
                            else if (@abs(@as(i32,@intCast(level_bb.bottom)) - @as(i32,@intCast(map_tile_clicked.y))) < distance and map_tile_clicked.x > level_bb.left and map_tile_clicked.x < level_bb.right) {
                                static_data.start_dragging(i, .bottom);
                                break;
                            }
                        }
                    }

                    if (static_data.box_being_modified) |level_bb_being_modified| {

                        const l = &state.resources.levels.items[level_bb_being_modified.index];
                        const level_bb = l.bb;

                        // the level bounding box is being modified
                        if (!level_bb.contains(map_tile_clicked)) switch (level_bb_being_modified.side) {
                            // Its being made larger
                            .top => if (map_tile_clicked.y > level_bb.top) { l.bb.top = map_tile_clicked.y; },
                            .bottom => if (map_tile_clicked.y < level_bb.bottom) { l.bb.bottom = map_tile_clicked.y; },
                            .left => if (map_tile_clicked.x < level_bb.left) { l.bb.left = map_tile_clicked.x; },
                            .right => if (map_tile_clicked.x > level_bb.right) { l.bb.right = map_tile_clicked.x; },
                        }
                        else switch (level_bb_being_modified.side) {
                            // Its being made smaller
                            .top => if (map_tile_clicked.y < level_bb.top) { l.bb.top = map_tile_clicked.y; },
                            .bottom => if (map_tile_clicked.y > level_bb.bottom) { l.bb.bottom = map_tile_clicked.y; },
                            .left => if (map_tile_clicked.x > level_bb.left) { l.bb.left = map_tile_clicked.x; },
                            .right => if (map_tile_clicked.x < level_bb.right) { l.bb.right = map_tile_clicked.x; },
                        }
                        
                        static_data.last_frame_modified = ud.frame;
                    }
                },
                .modify_junctions => {
                    const option_selected = junctions_menu_data.option_selected.?;
                    // NOTE the last option is hardcoded to be "delete" which is the only way of deleting entity spawners currently
                    if (option_selected == junctions_menu_data.options.len-1) {
                        for (state.resources.junctions.items, 0..) |junction, i| {
                            if (junction.a.equal(map_tile_clicked)) {
                                _ = state.resources.junctions.orderedRemove(i);
                                break;
                            }
                            if (junction.b.equal(map_tile_clicked)) {
                                _ = state.resources.junctions.orderedRemove(i);
                                break;
                            }
                        }
                    }
                    else {
                        try state.resources.junctions.append(.{ .a = map_tile_clicked, .b = map_tile_clicked });
                        map_editor_data.edit_action_type = .modify_position_of_selected_item;
                    }
                },
                .none => {},
            }
        }

        // TODO new container for modifying the tiles, a simple paint windows basically

        // NOTE the map editor is rendered separately to a surface and after the surface is done its paited onto the grid itself
        {
            state.renderer.set_context(map_editor_data.surface, M33.orthographic_projection(0, map_editor_data.size.x*8, map_editor_data.size.y*8, 0), M33.viewport(0, 0, map_editor_data.size.x*8, map_editor_data.size.y*8));

            // render the map
            try state.renderer.add_map(Vec2(usize).from(8,8), Vec2(usize).from(16,16), @constCast(&assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8), &state.resources.map, map_editor_data.map_tile_bb, BoundingBox(f32).from_bl_size(Vector2f.from(0,0),Vector2f.from(map_editor_data.size.x*8, map_editor_data.size.y*8)));

            // render the level junctions
            for (state.resources.junctions.items) |junction| {
                const exit_sprite_id = 127;
                // TODO add line renderer pipeline, which batches lines and renders them all together I guess?
                if (map_editor_data.map_tile_bb.contains(junction.a.to(usize))) {
                    const position = junction.a.to(f32).scale(8).substract(map_editor_data.map_tile_bb.bl().scale(8).to(f32));
                    try state.renderer.add_sprite_from_atlas_by_index(Vec2(usize).from(8,8), Vec2(usize).from(16,16), @constCast(&assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8), exit_sprite_id, BoundingBox(f32).from_bl_size(position, Vec2(f32).from(8,8)), .{});

                }
                if (map_editor_data.map_tile_bb.contains(junction.b.to(usize))) {
                    const position = junction.b.to(f32).scale(8).substract(map_editor_data.map_tile_bb.bl().scale(8).to(f32));
                    try state.renderer.add_sprite_from_atlas_by_index(Vec2(usize).from(8,8), Vec2(usize).from(16,16), @constCast(&assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8), exit_sprite_id, BoundingBox(f32).from_bl_size(position, Vec2(f32).from(8,8)), .{});
                }
            }

            // render the particle emitters
            for (state.resources.environment_particle_emitters.items) |particle_emitter| {
                if (!map_editor_data.map_tile_bb.contains(particle_emitter.pos.to(usize))) continue;
                // for now, the "icon" of a particle emitter is the sprite with index 1 (it looks like a weird portal cube thing)
                const particle_emitter_sprite_id = 241;
                const position = particle_emitter.pos.to(f32).scale(8).substract(map_editor_data.map_tile_bb.bl().scale(8).to(f32));
                try state.renderer.add_sprite_from_atlas_by_index(Vec2(usize).from(8,8), Vec2(usize).from(16,16), @constCast(&assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8), particle_emitter_sprite_id, BoundingBox(f32).from_bl_size(position, Vec2(f32).from(8,8)), .{});
            }

            // render entity spawners
            for (state.resources.entity_spawners.items) |entity_spawner| {
                if (!map_editor_data.map_tile_bb.contains(entity_spawner.pos.to(usize))) continue;
                // use the first sprite of the default animation as the sprite of the spawner
                const spawner_sprite_id = assets.EntityDescriptor.from(@enumFromInt(entity_spawner.entity_type)).default_animation.sprites[0];
                const position = entity_spawner.pos.to(f32).scale(8).substract(map_editor_data.map_tile_bb.bl().scale(8).to(f32));
                try state.renderer.add_sprite_from_atlas_by_index(Vec2(usize).from(8,8), Vec2(usize).from(16,16), @constCast(&assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8), spawner_sprite_id, BoundingBox(f32).from_bl_size(position, Vec2(f32).from(8,8)), .{});
            }

            // render the sub level bounding boxes
            for (state.resources.levels.items) |*l| {
                const level_bb_f32 = l.bb.to(f32);
                var level_bb = level_bb_f32;
                level_bb.right += 1;
                level_bb.top += 1;
                level_bb = level_bb.scale(Vec2(f32).from(8,8)).offset_negative(map_editor_data.map_tile_bb.bl().scale(8).to(f32));
                const color: RGBA = @bitCast(@as(u32,0xffffffff));
                try state.renderer.add_quad_border(level_bb, 1, color);
            }

            try state.renderer.flush_all();
        }

        try map_editor_tile_grid.fill_with_texture(map_editor_data.surface);
        try map_editor_tile_grid.highlight_hovered();

        try map_editor.text_line("Current Action:");
        try map_editor.text_line_fmt("{s}", .{@tagName(map_editor_data.edit_action_type)});

    }
    try map_editor.end();

    const dw = Container("debug_window");
    if (try dw.begin(ud.allocator, "debug", Vec2(f32).from(4, h-4), mouse_window, mouse_state.clicked(), mouse_state.down(), ud.pixel_buffer, projection_matrix_screen, viewport_matrix)) {
        try dw.text_line_fmt("ms {d: <9.2}", .{ud.ms});
        try dw.text_line_fmt("frame {}", .{ud.frame});
        try dw.text_line_fmt("mouse_window {d:.4} {d:.4}", .{mouse_window.x, mouse_window.y});
        try dw.text_line_fmt("buffer dimensions {d:.4} {d:.4}", .{w, h});
        try dw.text_line_fmt("l click {}", .{ud.mouse_left_clicked});
    }
    try dw.end();

    try dw.render();
    try map_editor.render();
    try sprite_editor.render();

    return true;
}

// TODO implement internal persistent state for arbitrary number of buttons identified by the label
// TODO find a good way to handle errors without needing to try on every call
// TODO stack based API so that I dont rely on comptime generated static lifetime structs
fn Container(comptime id: []const u8) type {
    return struct {
    
        const Self = @This();

        const text_line_height = TextRenderer(platform.OutPixelType, 1024, text_scale).char_height+3;
        const char_width = TextRenderer(platform.OutPixelType, 1024, text_scale).char_width+1;

        const padding = 2;

        var renderer: Renderer(platform.OutPixelType) = undefined;

        var initialized: bool = false;
        var background_color: RGBA = undefined;
        var highlight_color_a: RGBA = undefined;
        var highlight_color_b: RGBA = undefined;
        var text_color: RGBA = undefined;
        
        var total_bb: BoundingBox(f32) = undefined;
        var column_bb: BoundingBox(f32) = undefined;
        var other_columns_bb: BoundingBox(f32) = undefined;

        var draggable_previous_position: ?Vec2(f32) = null;
        var dragged_frames: usize = 0;
        var container_active: bool = true;
        var pos: Vec2(f32) = undefined;
        var mouse_position: Vec2(f32) = undefined;
        var mouse_click: bool = undefined;
        var mouse_down: bool = undefined;

        var allocator: std.mem.Allocator = undefined;

        fn begin(_allocator: std.mem.Allocator, name: []const u8, _pos: Vec2(f32), _mouse_position: Vec2(f32), _mouse_click: bool, _mouse_down: bool, pixel_buffer: Buffer2D(platform.OutPixelType), mvp_matrix: M33, viewport_matrix: M33) !bool {
            _ = id;
            allocator = _allocator;
            if (!initialized) {
                initialized = true;
                renderer = try Renderer(platform.OutPixelType).init(allocator);
                
                text_color = RGBA.from(BGR, @bitCast(assets.palette[1]));
                highlight_color_a = RGBA.from(BGR, @bitCast(assets.palette[2]));
                highlight_color_b = RGBA.from(BGR, @bitCast(assets.palette[3]));
                background_color = RGBA.make(0,0,0,255);

                total_bb = BoundingBox(f32).from(pos.y, pos.y, pos.x, pos.x);
                other_columns_bb = total_bb;
                column_bb = total_bb;

                pos = _pos;
            }
            // reset the data for a new frame
            
            total_bb = BoundingBox(f32).from(pos.y, pos.y, pos.x, @max(pos.x + total_bb.width(), (1+char_width)*@as(f32,@floatFromInt(name.len))));
            column_bb = BoundingBox(f32).from(pos.y, pos.y, pos.x, pos.x);
            other_columns_bb = column_bb;

            mouse_position = _mouse_position;
            mouse_click = _mouse_click and dragged_frames<8;
            mouse_down = _mouse_down;
            renderer.set_context(pixel_buffer, mvp_matrix, viewport_matrix);

            // NOTE this is a hack until I have layers in the renderer. Since I dont know the full size of the container yet
            // once I know it later on the call to `end()` I will then alter these values here for the correct ones.
            // TODO fix this hack
            try renderer.add_quad_from_bb(BoundingBox(f32).from(1,0,0,1), background_color);

            var header_bb = BoundingBox(f32).from(total_bb.top, total_bb.top - text_line_height, total_bb.left, total_bb.right);
            total_bb.bottom = header_bb.bottom;
            column_bb.bottom -= text_line_height;
            
            var name_hover = false;
            if (header_bb.contains(mouse_position)) {
                name_hover = true;
                if (mouse_click)  {
                    container_active = !container_active;
                }
            }
            else name_hover = false;

            if (draggable_previous_position) |previous_position| {
                if (!mouse_down) {
                    draggable_previous_position = null;
                    dragged_frames = 0;
                }
                else {
                    const movement = mouse_position.substract(previous_position);
                    draggable_previous_position = mouse_position;
                    pos = pos.add(movement);
                    total_bb = total_bb.offset(movement);
                    column_bb = column_bb.offset(movement);
                    other_columns_bb = other_columns_bb.offset(movement);
                    header_bb = header_bb.offset(movement);
                    dragged_frames += 1;
                }
            }
            else {
                if (mouse_down and header_bb.contains(mouse_position)) {
                    draggable_previous_position = mouse_position;
                }
            }

            try renderer.add_quad_from_bb(header_bb, if (name_hover) highlight_color_a else highlight_color_b);
            try renderer.add_text(header_bb.bl().add(Vec2(f32).from(1,1)), "{s}", .{name}, text_color);
            
            return container_active;
        }

        fn layout_next_column() void {
            // `other_columns_bb` = `other_columns_bb` + `column_bb`
            other_columns_bb = BoundingBox(f32).from(total_bb.top, total_bb.bottom, total_bb.left, column_bb.right);
            column_bb = BoundingBox(f32).from(total_bb.top - text_line_height, total_bb.top - text_line_height, column_bb.right, column_bb.right);
        }

        fn increment_column_bb(required_height: f32, required_width: f32) BoundingBox(f32) {
            column_bb.bottom = column_bb.bottom - required_height;
            column_bb.right = @max(column_bb.left + required_width, column_bb.right);
            if (column_bb.height() > other_columns_bb.height()) {
                other_columns_bb.bottom = column_bb.bottom;
                total_bb.bottom = column_bb.bottom;
            }
            if (column_bb.right > total_bb.right) {
                total_bb.right = column_bb.right;
            }
            return BoundingBox(f32).from(column_bb.bottom + required_height, column_bb.bottom, column_bb.left, column_bb.right);
        }

        fn button(text: []const u8, pressed: *bool) !bool {
            const element_bb = increment_column_bb(text_line_height + padding*4, @as(f32, @floatFromInt(text.len))*char_width + padding*4);
            const button_bb = element_bb.get_inner_bb_with_padding(padding);

            var hover = false;
            if (button_bb.contains(mouse_position)) {
                hover = true;
                if (mouse_click)  {
                    pressed.* = !pressed.*;
                }
            }
            
            try renderer.add_quad_from_bb(button_bb, if (hover) highlight_color_a else highlight_color_b);
            try renderer.add_text(button_bb.bl().add(Vec2(f32).from(padding, padding)), "{s}", .{text}, text_color);
            
            return pressed.*;
        }
        
        fn text_line(text: []const u8) !void {
            const text_bb = increment_column_bb(text_line_height + padding*2, @as(f32, @floatFromInt(text.len))*char_width + padding*2);
            try renderer.add_text(text_bb.bl().add(Vec2(f32).from(padding, padding)), "{s}", .{text}, text_color);
        }

        fn text_line_fmt(comptime fmt: []const u8, args: anytype) !void {
            const text = try std.fmt.allocPrint(allocator, fmt, args);
            defer allocator.free(text);
            const text_bb = increment_column_bb(text_line_height + padding*2, @as(f32, @floatFromInt(text.len))*char_width + padding*2);           
            try renderer.add_text(text_bb.bl().add(Vec2(f32).from(padding, padding)), "{s}", .{text}, text_color);
        }

        fn selection_grid_from_text_options(options: []const []const u8, selected: *?usize, hovered: *?usize, allow_deselect: bool) !GridThingy {
            var max_width: usize = 0;
            for (options) |option| max_width = @max(max_width, option.len * @as(usize, @intFromFloat(char_width)));
            
            const grid_dimensions = Vec2(usize).from(1, options.len);
            const grid_cell_dimensions = Vec2(usize).from(max_width, @as(usize, @intFromFloat(text_line_height)));

            const grid = selection_grid(grid_dimensions, grid_cell_dimensions, selected, hovered, allow_deselect);
            try grid.fill_with_text_options(options);
            try grid.highlight_hovered();
            try grid.highlight_selected();
            return grid;
        }
        
        const GridThingy = struct {
            
            grid_dimensions: Vec2(usize),
            grid_cell_dimensions: Vec2(usize),
            element_bb: BoundingBox(f32),
            working_bb: BoundingBox(f32),
            selected: *?usize,
            hovered: *?usize,
            just_selected: bool,
            click_and_dragging: bool,
            
            pub fn fill_with_texture(self: GridThingy, texture: Buffer2D(platform.OutPixelType)) !void {
                try renderer.add_blit_texture_to_bb(self.working_bb, texture);
            }
            
            pub fn fill_with_palette_based_texture(self: GridThingy, palette_based_texture: Buffer2D(u4), palette: *tic80.Palette) !void {
                try renderer.add_palette_based_textured_quad(self.working_bb, self.working_bb.offset_negative(self.working_bb.bl()), palette_based_texture, palette);
            }

            pub fn get_grid_index_bb(self: GridThingy, index: usize) BoundingBox(f32) {
                const col = index % self.grid_dimensions.x;
                const row = @divFloor(index, self.grid_dimensions.x);
                return BoundingBox(f32).from(
                    self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y + self.grid_cell_dimensions.y)),
                    self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y)),
                    self.working_bb.left + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x)),
                    self.working_bb.left + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x + self.grid_cell_dimensions.x))
                );
            }
            pub fn fill_index_with_palette_based_textured_quad(self: GridThingy, index: usize, texture_quad: BoundingBox(f32), palette_based_texture: Buffer2D(u4), palette: *tic80.Palette) !void {
                const col = index % self.grid_dimensions.x;
                const row = @divFloor(index, self.grid_dimensions.x);
                const dest_bb = BoundingBox(f32).from(
                    self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y + self.grid_cell_dimensions.y)),
                    self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y)),
                    self.working_bb.left + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x)),
                    self.working_bb.left + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x + self.grid_cell_dimensions.x))
                );
                try renderer.add_palette_based_textured_quad(dest_bb, texture_quad, palette_based_texture, palette);
            }

            pub fn fill_with_text_options(self: GridThingy, options: []const []const u8) !void {
                for (options, 0..) |option, i| {
                    const if32: f32 = @floatFromInt(i);
                    const label_position = Vec2(f32).from(self.working_bb.left, self.working_bb.bottom + (if32+0) * @as(f32, @floatFromInt(self.grid_cell_dimensions.y)));
                    try renderer.add_text(label_position, "{s}", .{option}, text_color);
                }
            }

            pub fn highlight_hovered(self: GridThingy) !void {
                // render the highlight for the hover
                if (self.hovered.*) |hover_index| {
                    const col: usize = hover_index % self.grid_dimensions.x;
                    const row: usize = @divFloor(hover_index, self.grid_dimensions.x);
                    const option_bb = BoundingBox(f32).from(
                        self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y + self.grid_cell_dimensions.y)),
                        self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y)),
                        self.working_bb.left   + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x)),
                        self.working_bb.left   + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x + self.grid_cell_dimensions.x)),
                    );
                    var color = highlight_color_a;
                    color.a = 50;
                    try renderer.add_quad_from_bb(option_bb, color);
                }
            }

            pub fn highlight_selected(self: GridThingy) !void {
                // render the highlight for the selected
                if (self.selected.*) |selected_option| {
                    const col: usize = selected_option%self.grid_dimensions.x;
                    const row: usize = @divFloor(selected_option,self.grid_dimensions.x);
                    const option_bb = BoundingBox(f32).from(
                        self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y + self.grid_cell_dimensions.y)),
                        self.working_bb.bottom + @as(f32, @floatFromInt(row*self.grid_cell_dimensions.y)),
                        self.working_bb.left   + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x)),
                        self.working_bb.left   + @as(f32, @floatFromInt(col*self.grid_cell_dimensions.x + self.grid_cell_dimensions.x)),
                    );
                    var color = highlight_color_b;
                    color.a = 50;
                    try renderer.add_quad_from_bb(option_bb, color);
                }
            }

            pub fn tile_clicked(self: GridThingy) ?usize {
                if (self.just_selected) return self.selected.*.?;
                return null;
            }
            pub fn tile_clicking(self: GridThingy) ?usize {
                if (self.click_and_dragging) return self.hovered.*.?;
                return null;
            }

        };

        fn selection_grid(grid_dimensions: Vec2(usize), grid_cell_dimensions: Vec2(usize), selected: *?usize, hovered: *?usize, allow_deselect: bool) GridThingy {
            const element_bb = increment_column_bb(
                @as(f32,@floatFromInt(grid_cell_dimensions.y*grid_dimensions.y)) + padding*2,
                @as(f32,@floatFromInt(grid_cell_dimensions.x*grid_dimensions.x)) + padding*2
            );
            const working_bb = BoundingBox(f32).from(element_bb.top-padding, element_bb.bottom+padding, element_bb.left+padding, element_bb.left+padding + @as(f32,@floatFromInt(grid_cell_dimensions.x*grid_dimensions.x)));

            // find out if any option is hovered
            if (working_bb.contains_exclusive(mouse_position)) {
                const mouse_in_surface = mouse_position.substract(working_bb.bl()).to(usize);
                const mouse_tile_in_surface = Vec2(usize).from(mouse_in_surface.x/grid_cell_dimensions.x, mouse_in_surface.y/grid_cell_dimensions.y);
                const hovered_tile_index = mouse_tile_in_surface.x + mouse_tile_in_surface.y*grid_dimensions.x;
                std.debug.assert(hovered_tile_index >= 0 and hovered_tile_index < grid_dimensions.x*grid_dimensions.y);
                hovered.* = hovered_tile_index;
            }
            else hovered.* = null;

            // selecting and selection-clear logic
            var click_and_dragging = false;
            if (mouse_down) if (hovered.*) |_| {
                click_and_dragging = true;
            };

            var just_selected = false;
            if (mouse_click) if (hovered.*) |hovered_index| {
                if (selected.*) |selected_index| {
                    if (allow_deselect and selected_index == hovered_index) selected.* = null
                    else {
                        just_selected = true;
                        selected.* = hovered_index;
                    }
                }
                else {
                    just_selected = true;
                    selected.* = hovered_index;
                }
            };

            return GridThingy {
                .element_bb = element_bb,
                .working_bb = working_bb,
                .grid_cell_dimensions = grid_cell_dimensions,
                .grid_dimensions = grid_dimensions,
                .hovered = hovered,
                .selected = selected,
                .just_selected = just_selected,
                .click_and_dragging = click_and_dragging,
            };
        }
        
        fn separator(extra_width: f32) !void {
            const separator_bb = increment_column_bb(extra_width + 2*padding, 0);
            const separator_line_bb = BoundingBox(f32).from(separator_bb.top-padding, separator_bb.bottom+padding, separator_bb.left + padding, separator_bb.right - padding);
            try renderer.add_quad_from_bb(separator_line_bb, highlight_color_a);
        }

        fn end() !void {
            // TODO render in background layer
            // For now this is a huge hack lol dont do this
            try renderer.batches_shapes.items[0].add_quad_from_bb(total_bb, background_color);
            renderer.batches_shapes.items[0].vertex_buffer.items[3] = renderer.batches_shapes.items[0].vertex_buffer.pop();
            renderer.batches_shapes.items[0].vertex_buffer.items[2] = renderer.batches_shapes.items[0].vertex_buffer.pop();
            renderer.batches_shapes.items[0].vertex_buffer.items[1] = renderer.batches_shapes.items[0].vertex_buffer.pop();
            renderer.batches_shapes.items[0].vertex_buffer.items[0] = renderer.batches_shapes.items[0].vertex_buffer.pop();
            
            try renderer.add_quad_border(total_bb, 1, highlight_color_a);
        }

        fn render() !void {
            try renderer.flush_all();
        }

    };

}

const String = struct {
    index: usize,
    length: usize
};

const Camera = struct {
    pos: Vector3f,
    pub fn init(pos: Vector3f) Camera {
        return Camera {
            .pos = pos,
        };
    }
};

pub fn ShapeRenderer(comptime output_pixel_type: type, comptime color: RGB) type {
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
                    inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector3f {
                        out_invariant.tint = vertex.tint;
                        return context.mvp_matrix.apply_to_vec2(vertex.pos);
                    }
                }.vertex_shader,
                struct {
                    inline fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                        _ = context;
                        const out_color = comptime output_pixel_type.from(RGB, color);
                        const tint = output_pixel_type.from(RGBA, invariants.tint);
                        return out_color.tint(tint);
                    }
                }.fragment_shader,
            );
        };
        
        const Self = @This();

        allocator: std.mem.Allocator,
        vertex_buffer: std.ArrayList(shader.Vertex),

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
            return self;
        }

        pub fn add_quad_from_bb(self: *Self, bb: BoundingBox(f32), tint: RGBA) !void {
            const pos = Vector2f.from(bb.left, bb.bottom);
            const size = Vector2f.from(bb.right - bb.left, bb.top - bb.bottom);
            const vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
            };
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub fn add_quad_border(self: *Self, bb: BoundingBox(f32), thickness: f32, tint: RGBA) !void {
            const line_left = BoundingBox(f32).from(bb.top+thickness, bb.bottom-thickness, bb.left-thickness, bb.left);
            const line_bottom = BoundingBox(f32).from(bb.bottom, bb.bottom-thickness, bb.left-thickness, bb.right+thickness);
            const line_right = BoundingBox(f32).from(bb.top+thickness, bb.bottom-thickness, bb.right, bb.right+thickness);
            const line_top = BoundingBox(f32).from(bb.top+thickness, bb.top, bb.left-thickness, bb.right+thickness);
            try self.add_quad_from_bb(line_left, tint);
            try self.add_quad_from_bb(line_bottom, tint);
            try self.add_quad_from_bb(line_right, tint);
            try self.add_quad_from_bb(line_top, tint);
        }
        
        pub fn add_quad(self: *Self, pos: Vector2f, size: Vector2f, tint: RGBA) !void {
            const vertices = [4] shader.Vertex {
                .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
            };
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub fn render(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            const context = shader.Context {
                .mvp_matrix = mvp_matrix,
            };
            shader.Pipeline.render(pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = viewport_matrix, });
            self.vertex_buffer.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            self.vertex_buffer.clearAndFree();
        }

        const Batch = struct {
            vertex_buffer: std.ArrayList(shader.Vertex),
            pixel_buffer: Buffer2D(output_pixel_type),
            mvp_matrix: M33,
            viewport_matrix: M33,

            fn init(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) Batch {
                return .{
                    .vertex_buffer = std.ArrayList(shader.Vertex).init(allocator),
                    .pixel_buffer = pixel_buffer,
                    .mvp_matrix = mvp_matrix,
                    .viewport_matrix = viewport_matrix,
                };
            }

            pub fn add_quad_from_bb(self: *Batch, bb: BoundingBox(f32), tint: RGBA) !void {
                const size = Vector2f.from(bb.right - bb.left, bb.top - bb.bottom);
                if (size.x == 0 or size.y == 0) return;
                const pos = Vector2f.from(bb.left, bb.bottom);
                const vertices = [4] shader.Vertex {
                    .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                    .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                    .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                    .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
                };
                try self.vertex_buffer.appendSlice(&vertices);
            }

            pub fn add_quad_border(self: *Batch, bb: BoundingBox(f32), thickness: f32, tint: RGBA) !void {
                const line_left = BoundingBox(f32).from(bb.top+thickness, bb.bottom-thickness, bb.left-thickness, bb.left);
                const line_bottom = BoundingBox(f32).from(bb.bottom, bb.bottom-thickness, bb.left-thickness, bb.right+thickness);
                const line_right = BoundingBox(f32).from(bb.top+thickness, bb.bottom-thickness, bb.right, bb.right+thickness);
                const line_top = BoundingBox(f32).from(bb.top+thickness, bb.top, bb.left-thickness, bb.right+thickness);
                try self.add_quad_from_bb(line_left, tint);
                try self.add_quad_from_bb(line_bottom, tint);
                try self.add_quad_from_bb(line_right, tint);
                try self.add_quad_from_bb(line_top, tint);
            }
            
            pub fn add_quad(self: *Batch, pos: Vector2f, size: Vector2f, tint: RGBA) !void {
                const vertices = [4] shader.Vertex {
                    .{ .pos = .{ .x = pos.x,          .y = pos.y          }, .tint = tint },
                    .{ .pos = .{ .x = pos.x + size.x, .y = pos.y          }, .tint = tint },
                    .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .tint = tint },
                    .{ .pos = .{ .x = pos.x,          .y = pos.y + size.y }, .tint = tint },
                };
                try self.vertex_buffer.appendSlice(&vertices);
            }

            pub fn flush(self: *Batch) void {
                const context = shader.Context {
                    .mvp_matrix = self.mvp_matrix,
                };
                shader.Pipeline.render(self.pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = self.viewport_matrix, });
                self.vertex_buffer.clearAndFree();
            }
        };
    
    };
}

pub fn StandardQuadRenderer(comptime output_pixel_type: type, comptime texture_pixel_type: type) type {
    return struct {

        const shader = struct {

            pub const Context = struct {
                texture: Buffer2D(texture_pixel_type),
                mvp_matrix: M33,
            };

            pub const Invariant = struct {
                uv: Vector2f,
            };

            pub const Vertex = struct {
                pos: Vector2f,
                uv: Vector2f,
            };

            pub const pipeline_configuration = graphics.GraphicsPipelineQuads2DConfiguration {
                .blend_with_background = false,
                .do_quad_clipping = true,
                .do_scissoring = false,
                .trace = false,
            };

            pub const Pipeline = graphics.GraphicsPipelineQuads2D(
                output_pixel_type,
                Context,
                Invariant,
                Vertex,
                pipeline_configuration,
                struct {
                    inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector3f {
                        out_invariant.uv = vertex.uv;
                        return context.mvp_matrix.apply_to_vec2(vertex.pos);
                    }
                }.vertex_shader,
                struct {
                    inline fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                        const sample = context.texture.point_sample(true, invariants.uv);
                        return output_pixel_type.from(texture_pixel_type, sample);
                    }
                }.fragment_shader,
            );
        };
        
        const Self = @This();

        allocator: std.mem.Allocator,
        vertex_buffer: std.ArrayList(shader.Vertex),
        texture: Buffer2D(texture_pixel_type),

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
            self.texture = undefined;
            return self;
        }

        pub fn add_blit_texture_to_bb(self: *Self, bb: BoundingBox(f32), texture: Buffer2D(texture_pixel_type)) !void {
            self.texture = texture;
            const vertex_buffer = [4] shader.Vertex {
                .{ .pos = bb.bl(), .uv = Vec2(f32).from(0, 0) }, // 0 - bottom left
                .{ .pos = bb.br(), .uv = Vec2(f32).from(1, 0) }, // 1 - bottom right
                .{ .pos = bb.tr(), .uv = Vec2(f32).from(1, 1) }, // 2 - top right
                .{ .pos = bb.tl(), .uv = Vec2(f32).from(0, 1) }, // 3 - top left
            };
            try self.vertex_buffer.appendSlice(&vertex_buffer);
        }

        pub fn render(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            const context = shader.Context {
                .texture = self.texture,
                .mvp_matrix = mvp_matrix,
            };
            shader.Pipeline.render(pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = viewport_matrix, });
            self.vertex_buffer.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            self.vertex_buffer.clearAndFree();
        }

        const Batch = struct {
            vertex_buffer: std.ArrayList(shader.Vertex),
            texture: Buffer2D(texture_pixel_type),
            pixel_buffer: Buffer2D(output_pixel_type),
            mvp_matrix: M33,
            viewport_matrix: M33,

            fn init(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33, texture: Buffer2D(texture_pixel_type)) Batch {
                return .{
                    .vertex_buffer = std.ArrayList(shader.Vertex).init(allocator),
                    .texture = texture,
                    .pixel_buffer = pixel_buffer,
                    .mvp_matrix = mvp_matrix,
                    .viewport_matrix = viewport_matrix,
                };
            }

            pub fn add_blit_texture_to_bb(self: *Batch, bb: BoundingBox(f32)) !void {
                const vertex_buffer = [4] shader.Vertex {
                    .{ .pos = bb.bl(), .uv = Vec2(f32).from(0, 0) }, // 0 - bottom left
                    .{ .pos = bb.br(), .uv = Vec2(f32).from(1, 0) }, // 1 - bottom right
                    .{ .pos = bb.tr(), .uv = Vec2(f32).from(1, 1) }, // 2 - top right
                    .{ .pos = bb.tl(), .uv = Vec2(f32).from(0, 1) }, // 3 - top left
                };
                try self.vertex_buffer.appendSlice(&vertex_buffer);
            }

            pub fn flush(self: *Batch) void {
                const context = shader.Context {
                    .texture = self.texture,
                    .mvp_matrix = self.mvp_matrix,
                };
                shader.Pipeline.render(self.pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = self.viewport_matrix, });
                self.vertex_buffer.clearAndFree();
            }
        };
    };
}

pub fn TextRenderer(comptime out_pixel_type: type, comptime max_size_per_print: usize, comptime size: comptime_float) type {
    return struct {

        const texture = font.texture;
        const char_width: f32 = (base_width - pad_left - pad_right) * size;
        const char_height: f32 = (base_height - pad_top - pad_bottom) * size;
        // NOTE the font has quite a lot of padding so rather than rendering the whole 8x8 quad, only render the relevant part of the quad
        // the rest is just transparent anyway
        const base_width: f32 = 8;
        const base_height: f32 = 8;
        const pad_top: f32 = 0;
        const pad_bottom: f32 = 3;
        const pad_left: f32 = 0;
        const pad_right: f32 = 5;
        const space_between_characters: f32 = 1;
        
        const Shader = struct {

            pub const Context = struct {
                mvp_matrix: M33,
            };

            pub const Invariant = struct {
                tint: RGBA,
                uv: Vector2f,
            };

            pub const Vertex = struct {
                pos: Vector2f,
                uv: Vector2f,
                tint: RGBA,
            };

            pub const pipeline_configuration = graphics.GraphicsPipelineQuads2DConfiguration {
                .blend_with_background = true,
                .do_quad_clipping = true,
                .do_scissoring = false,
                .trace = false
            };

            pub const Pipeline = graphics.GraphicsPipelineQuads2D(
                out_pixel_type,
                Context,
                Invariant,
                Vertex,
                pipeline_configuration,
                struct {
                    inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector3f {
                        out_invariant.tint = vertex.tint;
                        out_invariant.uv = vertex.uv;
                        return context.mvp_matrix.apply_to_vec2(vertex.pos);
                    }
                }.vertex_shader,
                struct {
                    inline fn fragment_shader(context: Context, invariants: Invariant) out_pixel_type {
                        _ = context;
                        const sample = texture.point_sample(false, invariants.uv);
                        const sample_adapted = out_pixel_type.from(RGBA, sample); 
                        const tint = out_pixel_type.from(RGBA, invariants.tint);
                        return sample_adapted.tint(tint);
                    }
                }.fragment_shader,
            );
        };

        vertex_buffer: std.ArrayList(Shader.Vertex),
        
        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .vertex_buffer = std.ArrayList(Shader.Vertex).init(allocator)
            };
        }

        pub fn deinit(self: *Self) void {
            self.vertex_buffer.clearAndFree();
        }

        pub fn print(self: *Self, pos: Vector2f, comptime fmt: []const u8, args: anytype, tint: RGBA) !void {
            var buff: [max_size_per_print]u8 = undefined;
            const str = try std.fmt.bufPrint(&buff, fmt, args);
            for (str, 0..) |_c, i| {
                    
                const c = switch (_c) {
                    // NOTE for whatever reason the font I'm using has uppercase and lowercase reversed?
                    // so make everything lower case (which will show up as an upper case and looks better)
                    // 'A'..'Z' -> 'a'..'z'
                    65...90 => _c+32,
                    else => _c
                };
                
                // x and y are the bottom left of the quad
                const x: f32 = pos.x + @as(f32, @floatFromInt(i)) * char_width + @as(f32, @floatFromInt(i));
                const y: f32 = pos.y;
                
                const cy: f32 = @floatFromInt(15 - @divFloor(c,16));
                const cx: f32 = @floatFromInt(c % 16);
                
                // texture left and right
                const u_1: f32 = cx * base_width + pad_left;
                const u_2: f32 = (cx+1) * base_width - pad_right;
                
                // texture top and bottom. Note that the texture is invertex so the mat here is also inverted
                const v_1: f32 = cy * base_height + pad_bottom;
                const v_2: f32 = (cy+1) * base_height - pad_top;

                // NOTE the texture is reversed hence the weird uv coordinates
                const vertices = [4] Shader.Vertex {
                    .{ .pos = .{ .x = x,              .y = y               }, .uv = .{ .x = u_1, .y = v_1 }, .tint = tint },
                    .{ .pos = .{ .x = x + char_width, .y = y               }, .uv = .{ .x = u_2, .y = v_1 }, .tint = tint },
                    .{ .pos = .{ .x = x + char_width, .y = y + char_height }, .uv = .{ .x = u_2, .y = v_2 }, .tint = tint },
                    .{ .pos = .{ .x = x,              .y = y + char_height }, .uv = .{ .x = u_1, .y = v_2 }, .tint = tint }
                };
                
                try self.vertex_buffer.appendSlice(&vertices);                
            }
        }

        pub fn width(self: *Self) f32 {
            _ = self;
            return char_width;
        }
        
        pub fn height(self: *Self) f32 {
            _ = self;
            return char_height;
        }

        pub fn render_all(self: *Self, pixel_buffer: Buffer2D(out_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            Shader.Pipeline.render(
                pixel_buffer,
                .{ .mvp_matrix = mvp_matrix, },
                self.vertex_buffer.items,
                self.vertex_buffer.items.len/4,
                .{ .viewport_matrix = viewport_matrix, }
            );
            self.vertex_buffer.clearRetainingCapacity();
        }
    
        const Batch = struct {
            vertex_buffer: std.ArrayList(Shader.Vertex),
            pixel_buffer: Buffer2D(out_pixel_type),
            mvp_matrix: M33,
            viewport_matrix: M33,

            fn init(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(out_pixel_type), mvp_matrix: M33, viewport_matrix: M33) Batch {
                return .{
                    .vertex_buffer = std.ArrayList(Shader.Vertex).init(allocator),
                    .pixel_buffer = pixel_buffer,
                    .mvp_matrix = mvp_matrix,
                    .viewport_matrix = viewport_matrix,
                };
            }

            pub fn add_text(self: *Batch, pos: Vector2f, comptime fmt: []const u8, args: anytype, tint: RGBA) !void {
                var buff: [max_size_per_print]u8 = undefined;
                const str = try std.fmt.bufPrint(&buff, fmt, args);
                for (str, 0..) |_c, i| {
                    
                    const c = switch (_c) {
                        // NOTE for whatever reason the font I'm using has uppercase and lowercase reversed?
                        // so make everything lower case (which will show up as an upper case and looks better)
                        // 'A'..'Z' -> 'a'..'z'
                        65...90 => _c+32,
                        else => _c
                    };
                    
                    // x and y are the bottom left of the quad
                    const x: f32 = pos.x + @as(f32, @floatFromInt(i)) * char_width + @as(f32, @floatFromInt(i));
                    const y: f32 = pos.y;
                    
                    const cy: f32 = @floatFromInt(15 - @divFloor(c,16));
                    const cx: f32 = @floatFromInt(c % 16);
                    
                    // texture left and right
                    const u_1: f32 = cx * base_width + pad_left;
                    const u_2: f32 = (cx+1) * base_width - pad_right;
                    
                    // texture top and bottom. Note that the texture is invertex so the mat here is also inverted
                    const v_1: f32 = cy * base_height + pad_bottom;
                    const v_2: f32 = (cy+1) * base_height - pad_top;

                    // NOTE the texture is reversed hence the weird uv coordinates
                    const vertices = [4] Shader.Vertex {
                        .{ .pos = .{ .x = x,              .y = y               }, .uv = .{ .x = u_1, .y = v_1 }, .tint = tint },
                        .{ .pos = .{ .x = x + char_width, .y = y               }, .uv = .{ .x = u_2, .y = v_1 }, .tint = tint },
                        .{ .pos = .{ .x = x + char_width, .y = y + char_height }, .uv = .{ .x = u_2, .y = v_2 }, .tint = tint },
                        .{ .pos = .{ .x = x,              .y = y + char_height }, .uv = .{ .x = u_1, .y = v_2 }, .tint = tint }
                    };
                    
                    try self.vertex_buffer.appendSlice(&vertices);                
                }
            }

            pub fn flush(self: *Batch) void {
                Shader.Pipeline.render(
                    self.pixel_buffer,
                    .{ .mvp_matrix = self.mvp_matrix, },
                    self.vertex_buffer.items,
                    self.vertex_buffer.items.len/4,
                    .{ .viewport_matrix = self.viewport_matrix, }
                );
                self.vertex_buffer.clearAndFree();
            }
        };
    
    };
}

pub fn PaletteBasedTexturedQuadRenderer(comptime output_pixel_type: type, comptime key_color: ?u4) type {
    return struct {
        
        const Self = @This();

        const shader = struct {

            pub const Context = struct {
                palette_based_texture: Buffer2D(u4),
                palette: *tic80.Palette,
                mvp_matrix: M33,
            };

            pub const Invariant = struct {
                uv: Vector2f,
            };

            pub const Vertex = struct {
                pos: Vector2f,
                uv: Vector2f,
            };

            pub const pipeline_configuration = graphics.GraphicsPipelineQuads2DConfiguration {
                .blend_with_background = key_color != null,
                .do_quad_clipping = true,
                .do_scissoring = false,
                .trace = false
            };

            inline fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector3f {
                out_invariant.uv = vertex.uv;
                return context.mvp_matrix.apply_to_vec2(vertex.pos);
            }

            inline fn fragment_shader(context: Context, invariants: Invariant) output_pixel_type {
                const palette_index = context.palette_based_texture.point_sample(false, invariants.uv);
                const key_color_enabled = comptime key_color != null;
                if (key_color_enabled) {
                    if (palette_index == key_color.?) return output_pixel_type.from(RGBA, RGBA.make(0,0,0,0));
                }
                return output_pixel_type.from(BGR, @bitCast(context.palette[palette_index]));
            }
            
            pub const Pipeline = graphics.GraphicsPipelineQuads2D(
                output_pixel_type,
                Context,
                Invariant,
                Vertex,
                pipeline_configuration,
                vertex_shader,
                fragment_shader
            );
            
        };

        allocator: std.mem.Allocator,
        palette_based_texture: Buffer2D(u4),
        palette: *tic80.Palette,
        vertex_buffer: std.ArrayList(shader.Vertex),

        pub fn init(allocator: std.mem.Allocator, palette: *tic80.Palette, palette_based_texture: Buffer2D(u4)) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.palette_based_texture = palette_based_texture;
            self.palette = palette;
            self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
            return self;
        }

        pub const ExtraParameters = struct {
            mirror_horizontally: bool = false
        };

        pub fn add_sprite_from_atlas_by_index(self: *Self, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), sprite_index: usize, dest_bb: BoundingBox(f32), parameters: ExtraParameters) !void {
            const colf: f32 = @floatFromInt(sprite_index % grid_dimensions.x);
            const rowf: f32 = @floatFromInt(@divFloor(sprite_index, grid_dimensions.x));
            var vertices = [4] shader.Vertex {
                .{ .pos = dest_bb.bl(), .uv = Vec2(f32).from(colf*grid_cell_dimensions.x + 0                      , rowf*grid_cell_dimensions.y + 0) }, // 0 - bottom left
                .{ .pos = dest_bb.br(), .uv = Vec2(f32).from(colf*grid_cell_dimensions.x + grid_cell_dimensions.x , rowf*grid_cell_dimensions.y + 0) }, // 1 - bottom right
                .{ .pos = dest_bb.tr(), .uv = Vec2(f32).from(colf*grid_cell_dimensions.x + grid_cell_dimensions.x , rowf*grid_cell_dimensions.y + grid_cell_dimensions.y ) }, // 2 - top right
                .{ .pos = dest_bb.tl(), .uv = Vec2(f32).from(colf*grid_cell_dimensions.x + 0                      , rowf*grid_cell_dimensions.y + grid_cell_dimensions.y ) }, // 3 - top left
            };
            if (parameters.mirror_horizontally) {
                vertices[0].uv.x = colf*grid_cell_dimensions.x + grid_cell_dimensions.x;
                vertices[1].uv.x = colf*grid_cell_dimensions.x + 0;
                vertices[2].uv.x = colf*grid_cell_dimensions.x + 0;
                vertices[3].uv.x = colf*grid_cell_dimensions.x + grid_cell_dimensions.x;
            }
            try self.vertex_buffer.appendSlice(&vertices);
        }

        pub fn add_map(self: *Self, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), map: *[136][240]u8, map_bb: BoundingBox(usize), dest_bb: BoundingBox(f32)) !void {
            for (map[map_bb.bottom..map_bb.top+1], 0..) |map_row, i| {
                for (map_row[map_bb.left..map_bb.right+1], 0..) |sprite_index, j| {
                    const offset = Vector2f.from(@floatFromInt(j*8), @floatFromInt(i*8));
                    const map_tile_dest_bb = BoundingBox(f32).from(
                        dest_bb.bottom + offset.y + grid_cell_dimensions.y,
                        dest_bb.bottom + offset.y,
                        dest_bb.left + offset.x,
                        dest_bb.left + offset.x + grid_cell_dimensions.x
                    );
                    try self.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, map_tile_dest_bb, .{});
                }
            }
        }

        pub fn render(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            const context = shader.Context {
                .texture = self.palette_based_texture,
                .palette = self.palette,
                .mvp_matrix = mvp_matrix,
            };
            shader.Pipeline.render(pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = viewport_matrix });
            self.vertex_buffer.clearRetainingCapacity();
        }

        pub fn deinit(self: *Self) void {
            self.vertex_buffer.clearAndFree();
        }

        const Batch = struct {
            
            palette_based_texture: Buffer2D(u4),
            palette: *tic80.Palette,
            vertex_buffer: std.ArrayList(shader.Vertex),
            pixel_buffer: Buffer2D(output_pixel_type),
            mvp_matrix: M33,
            viewport_matrix: M33,

            pub fn init(allocator: std.mem.Allocator, palette: *tic80.Palette, palette_based_texture: Buffer2D(u4), pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) !Batch {
                var self: Batch = undefined;
                self.palette_based_texture = palette_based_texture;
                self.palette = palette;
                self.vertex_buffer = std.ArrayList(shader.Vertex).init(allocator);
                self.pixel_buffer = pixel_buffer;
                self.mvp_matrix = mvp_matrix;
                self.viewport_matrix = viewport_matrix;
                return self;
            }

            pub fn add_palette_based_textured_quad(self: *Batch, dest_bb: BoundingBox(f32), src_bb: BoundingBox(f32)) !void {
                var vertices = [4] shader.Vertex {
                    .{ .pos = dest_bb.bl(), .uv = src_bb.bl() }, // 0 - bottom left
                    .{ .pos = dest_bb.br(), .uv = src_bb.br() }, // 1 - bottom right
                    .{ .pos = dest_bb.tr(), .uv = src_bb.tr() }, // 2 - top right
                    .{ .pos = dest_bb.tl(), .uv = src_bb.tl() }, // 3 - top left
                };
                try self.vertex_buffer.appendSlice(&vertices);
            }

            pub fn add_sprite_from_atlas_by_index(self: *Batch, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), sprite_index: usize, dest_bb: BoundingBox(f32), parameters: ExtraParameters) !void {
                const colf: f32 = @floatFromInt(sprite_index % grid_dimensions.x);
                const rowf: f32 = @floatFromInt(@divFloor(sprite_index, grid_dimensions.x));
                var vertices = [4] shader.Vertex {
                    .{ .pos = dest_bb.bl(), .uv = Vec2(f32).from((colf+0)*grid_cell_dimensions.x, (rowf+0)*grid_cell_dimensions.y) }, // 0 - bottom left
                    .{ .pos = dest_bb.br(), .uv = Vec2(f32).from((colf+1)*grid_cell_dimensions.x, (rowf+0)*grid_cell_dimensions.y) }, // 1 - bottom right
                    .{ .pos = dest_bb.tr(), .uv = Vec2(f32).from((colf+1)*grid_cell_dimensions.x, (rowf+1)*grid_cell_dimensions.y) }, // 2 - top right
                    .{ .pos = dest_bb.tl(), .uv = Vec2(f32).from((colf+0)*grid_cell_dimensions.x, (rowf+1)*grid_cell_dimensions.y) }, // 3 - top left
                };
                if (parameters.mirror_horizontally) {
                    vertices[0].uv.x = colf*grid_cell_dimensions.x + grid_cell_dimensions.x;
                    vertices[1].uv.x = colf*grid_cell_dimensions.x + 0;
                    vertices[2].uv.x = colf*grid_cell_dimensions.x + 0;
                    vertices[3].uv.x = colf*grid_cell_dimensions.x + grid_cell_dimensions.x;
                }
                try self.vertex_buffer.appendSlice(&vertices);
            }

            pub fn add_map(self: *Batch, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), map: *[136][240]u8, map_bb: BoundingBox(usize), dest_bb: BoundingBox(f32)) !void {
                for (map[map_bb.bottom..map_bb.top+1], 0..) |map_row, i| {
                    for (map_row[map_bb.left..map_bb.right+1], 0..) |sprite_index, j| {
                        const offset = Vector2f.from(@floatFromInt(j*8), @floatFromInt(i*8));
                        const map_tile_dest_bb = BoundingBox(f32).from(
                            dest_bb.bottom + offset.y + grid_cell_dimensions.y,
                            dest_bb.bottom + offset.y,
                            dest_bb.left + offset.x,
                            dest_bb.left + offset.x + grid_cell_dimensions.x
                        );
                        try self.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, map_tile_dest_bb, .{});
                    }
                }
            }

            pub fn flush(self: *Batch) void {
                const context = shader.Context {
                    .palette_based_texture = self.palette_based_texture,
                    .palette = self.palette,
                    .mvp_matrix = self.mvp_matrix,
                };
                shader.Pipeline.render(self.pixel_buffer, context, self.vertex_buffer.items, @divExact(self.vertex_buffer.items.len, 4), .{ .viewport_matrix = self.viewport_matrix });
                self.vertex_buffer.clearAndFree();
            }
            
        };
        
    };
}

// TODO allow to continue batches if not explicitly asked to use a different batch, or if the continuation is just imposible (for example, when textures used are different)
// TODO add layers!
pub fn Renderer(comptime output_pixel_type: type) type {
    return struct {

        const Self = @This();

        const TextRendererImpl = TextRenderer(output_pixel_type, 1024, text_scale);
        const ShapeRendererImpl = ShapeRenderer(output_pixel_type, RGB.from(255,255,255));
        const SurfaceRendererImpl = StandardQuadRenderer(output_pixel_type, output_pixel_type);
        const PaletteBasedTexturedQuadRendererImpl = PaletteBasedTexturedQuadRenderer(output_pixel_type, null);
        const PaletteBasedTexturedQuadRendererBlendedImpl = PaletteBasedTexturedQuadRenderer(output_pixel_type, 0);

        pub const ExtraParameters = struct {
            mirror_horizontally: bool = false,
            blend: bool = false,
        };

        allocator: std.mem.Allocator,

        batches: std.ArrayList(BatchDescriptor),
        current_batch: BatchDescriptor,

        batches_text: std.ArrayList(TextRendererImpl.Batch),
        batches_shapes: std.ArrayList(ShapeRendererImpl.Batch),
        batches_palette_based_textured_quads: std.ArrayList(PaletteBasedTexturedQuadRendererImpl.Batch),
        batches_palette_based_textured_quads_blended: std.ArrayList(PaletteBasedTexturedQuadRendererBlendedImpl.Batch),
        batches_surfaces: std.ArrayList(SurfaceRendererImpl.Batch),

        pixel_buffer: Buffer2D(output_pixel_type),
        mvp_matrix: M33,
        viewport_matrix: M33,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
                        
            self.batches_text = std.ArrayList(TextRendererImpl.Batch).init(allocator);
            self.batches_shapes = std.ArrayList(ShapeRendererImpl.Batch).init(allocator);
            self.batches_surfaces = std.ArrayList(SurfaceRendererImpl.Batch).init(allocator);
            self.batches_palette_based_textured_quads = std.ArrayList(PaletteBasedTexturedQuadRendererImpl.Batch).init(allocator);
            self.batches_palette_based_textured_quads_blended = std.ArrayList(PaletteBasedTexturedQuadRendererBlendedImpl.Batch).init(allocator);

            self.batches = std.ArrayList(BatchDescriptor).init(allocator);

            self.current_batch = .{
                .index = 0,
                .renderer_type = .none
            };
            
            return self;
        }

        pub fn set_context(self: *Self, pixel_buffer: Buffer2D(output_pixel_type), mvp_matrix: M33, viewport_matrix: M33) void {
            self.pixel_buffer = pixel_buffer;
            self.mvp_matrix = mvp_matrix;
            self.viewport_matrix = viewport_matrix;
        }

        pub fn add_quad_from_bb(self: *Self, bb: BoundingBox(f32), tint: RGBA) !void {
            const correct_renderer = RendererType.shape;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_shapes.items[self.batches_shapes.items.len-1];
                try batch.add_quad_from_bb(bb, tint);
                return;
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);
            // set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_shapes.items.len
            };
            const new_batch = try self.batches_shapes.addOne();
            new_batch.* = ShapeRendererImpl.Batch.init(self.allocator, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_quad_from_bb(bb, tint);
        }
        
        pub fn add_quad_border(self: *Self, bb: BoundingBox(f32), thickness: f32, tint: RGBA) !void {
            const correct_renderer = RendererType.shape;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_shapes.items[self.current_batch.index];
                try batch.add_quad_border(bb, thickness, tint);
                return;
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);
            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_shapes.items.len
            };
            const new_batch = try self.batches_shapes.addOne();
            new_batch.* = ShapeRendererImpl.Batch.init(self.allocator, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_quad_border(bb, thickness, tint);
        }
        
        pub fn add_palette_based_textured_quad(self: *Self, dest_bb: BoundingBox(f32), src_bb: BoundingBox(f32), palette_based_texture: Buffer2D(u4), palette: *tic80.Palette) !void {
            const correct_renderer = RendererType.palette_based_textured_quad_renderer;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_palette_based_textured_quads.items[self.current_batch.index];
                // if the batch is using same palette and texture, keep using it
                if (batch.palette_based_texture.data.ptr == palette_based_texture.data.ptr and batch.palette == palette) {
                    try batch.add_palette_based_textured_quad(dest_bb, src_bb);
                    return;
                }
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);

            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_palette_based_textured_quads.items.len
            };
            const new_batch = try self.batches_palette_based_textured_quads.addOne();
            new_batch.* = try PaletteBasedTexturedQuadRendererImpl.Batch.init(self.allocator, palette, palette_based_texture, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_palette_based_textured_quad(dest_bb, src_bb);
        }

        pub fn add_blit_texture_to_bb(self: *Self, bb: BoundingBox(f32), texture: Buffer2D(output_pixel_type)) !void {
            const correct_renderer = RendererType.surface;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_surfaces.items[self.current_batch.index];
                if (batch.texture.data.ptr == texture.data.ptr) {
                    try batch.add_blit_texture_to_bb(bb);
                    return;
                }
            }
            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);
            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_surfaces.items.len
            };
            const new_batch = try self.batches_surfaces.addOne();
            new_batch.* = SurfaceRendererImpl.Batch.init(self.allocator, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix, texture);
            try new_batch.add_blit_texture_to_bb(bb);
        }
        
        pub fn add_text(self: *Self, pos: Vector2f, comptime fmt: []const u8, args: anytype, tint: RGBA) !void {
            const correct_renderer = RendererType.text;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_text.items[self.current_batch.index];
                try batch.add_text(pos, fmt, args, tint);
                return;
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);
            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_text.items.len
            };
            const new_batch = try self.batches_text.addOne();
            new_batch.* = TextRendererImpl.Batch.init(self.allocator, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_text(pos, fmt, args, tint);
        }
        
        pub fn add_sprite_from_atlas_by_index(self: *Self, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), palette: *tic80.Palette, palette_based_texture: Buffer2D(u4), sprite_index: usize, dest_bb: BoundingBox(f32), parameters: ExtraParameters) !void {
            if (parameters.blend) {
                const correct_renderer = RendererType.palette_based_textured_quad_blended_renderer;
                if (self.current_batch.renderer_type == correct_renderer) {
                    const batch = &self.batches_palette_based_textured_quads_blended.items[self.current_batch.index];
                    // if the batch is using same palette and texture, keep using it
                    if (batch.palette_based_texture.data.ptr == palette_based_texture.data.ptr and batch.palette == palette) {
                        try batch.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, dest_bb, .{ .mirror_horizontally = parameters.mirror_horizontally });
                        return;
                    }
                }

                // save previous batch
                if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);

                // initialize and set new batch
                self.current_batch = .{
                    .renderer_type = correct_renderer,
                    .index = self.batches_palette_based_textured_quads_blended.items.len
                };
                const new_batch = try self.batches_palette_based_textured_quads_blended.addOne();
                new_batch.* = try PaletteBasedTexturedQuadRendererBlendedImpl.Batch.init(self.allocator, palette, palette_based_texture, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
                try new_batch.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, dest_bb, .{ .mirror_horizontally = parameters.mirror_horizontally });
            }
            else {
                const correct_renderer = RendererType.palette_based_textured_quad_renderer;
                if (self.current_batch.renderer_type == correct_renderer) {
                    const batch = &self.batches_palette_based_textured_quads.items[self.current_batch.index];
                    // if the batch is using same palette and texture, keep using it
                    if (batch.palette_based_texture.data.ptr == palette_based_texture.data.ptr and batch.palette == palette) {
                        try batch.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, dest_bb, .{ .mirror_horizontally = parameters.mirror_horizontally });
                        return;
                    }
                }

                // save previous batch
                if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);

                // initialize and set new batch
                self.current_batch = .{
                    .renderer_type = correct_renderer,
                    .index = self.batches_palette_based_textured_quads.items.len
                };
                const new_batch = try self.batches_palette_based_textured_quads.addOne();
                new_batch.* = try PaletteBasedTexturedQuadRendererImpl.Batch.init(self.allocator, palette, palette_based_texture, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
                try new_batch.add_sprite_from_atlas_by_index(grid_cell_dimensions, grid_dimensions, sprite_index, dest_bb, .{ .mirror_horizontally = parameters.mirror_horizontally });
            }
        }

        pub fn add_map(self: *Self, comptime grid_cell_dimensions: Vec2(usize), comptime grid_dimensions: Vec2(usize), palette: *tic80.Palette, palette_based_texture: Buffer2D(u4), map: *[136][240]u8, map_bb: BoundingBox(usize), dest_bb: BoundingBox(f32)) !void {
            const correct_renderer = RendererType.palette_based_textured_quad_renderer;
            if (self.current_batch.renderer_type == correct_renderer) {
                const batch = &self.batches_palette_based_textured_quads.items[self.current_batch.index];
                // if the batch is using same palette and texture, keep using it
                if (batch.palette_based_texture.data.ptr == palette_based_texture.data.ptr and batch.palette == palette) {
                    try batch.add_map(grid_cell_dimensions, grid_dimensions, map, map_bb, dest_bb);
                    return;
                }
            }

            // save previous batch
            if (self.current_batch.renderer_type != .none) try self.batches.append(self.current_batch);

            // initialize and set new batch
            self.current_batch = .{
                .renderer_type = correct_renderer,
                .index = self.batches_palette_based_textured_quads.items.len
            };
            const new_batch = try self.batches_palette_based_textured_quads.addOne();
            new_batch.* = try PaletteBasedTexturedQuadRendererImpl.Batch.init(self.allocator, palette, palette_based_texture, self.pixel_buffer, self.mvp_matrix, self.viewport_matrix);
            try new_batch.add_map(grid_cell_dimensions, grid_dimensions, map, map_bb, dest_bb);
        }

        pub fn flush_all(self: *Self) !void {
            if (self.current_batch.renderer_type == .none) return;
            try self.batches.append(self.current_batch);

            var total: usize = 0;
            for (self.batches.items) |batch| {
                const index = batch.index;
                switch (batch.renderer_type) {
                    .shape => {
                        const batch_to_render = &self.batches_shapes.items[index];
                        batch_to_render.flush();
                    },
                    .text => {
                        const batch_to_render = &self.batches_text.items[index];
                        batch_to_render.flush();
                    },
                    .surface => {
                        const batch_to_render = &self.batches_surfaces.items[index];
                        batch_to_render.flush();
                    },
                    .palette_based_textured_quad_renderer => {
                        const batch_to_render = &self.batches_palette_based_textured_quads.items[index];
                        batch_to_render.flush();
                    },
                    .palette_based_textured_quad_blended_renderer => {
                        const batch_to_render = &self.batches_palette_based_textured_quads_blended.items[index];
                        batch_to_render.flush();
                    },
                    .none => unreachable
                }
                total += 1;
            }

            self.batches.clearRetainingCapacity();
            self.batches_shapes.clearRetainingCapacity();
            self.batches_surfaces.clearRetainingCapacity();
            self.batches_text.clearRetainingCapacity();
            self.batches_palette_based_textured_quads.clearRetainingCapacity();
            self.batches_palette_based_textured_quads_blended.clearRetainingCapacity();
            self.current_batch = .{
                .index = 0,
                .renderer_type = .none
            };
        }

        const RendererType = enum {
            none, text, shape, surface, palette_based_textured_quad_renderer, palette_based_textured_quad_blended_renderer
        };

        const BatchDescriptor = struct {
            renderer_type: RendererType,
            index: usize,
        };
    };
}

/// in tic's maps, the Y points downwards. This functions "corrects" any y coordinate when referencing a tile in a map
inline fn correct_y(thing: anytype) @TypeOf(thing) {
    return  135 - thing;
}

const Direction = enum {Left, Right};

// TODO add header with version of resource file and throw error if wrong version
pub const Resources = struct {
    
    allocator: std.mem.Allocator,
    strings: std.ArrayList(u8),
    map: [136][240]u8,
    sprite_atlas: [8*8 * 16*16]u4,
    levels: std.ArrayList(LevelDescriptor),
    junctions: std.ArrayList(LevelJunctionDescriptor),
    entity_spawners: std.ArrayList(EntitySpawner),
    environment_particle_emitters: std.ArrayList(EnvironmentParticleEmitter),

    pub fn init(allocator: std.mem.Allocator) Resources {
        return .{
            .allocator = allocator,
            .strings = std.ArrayList(u8).init(allocator),
            .map = undefined,
            .sprite_atlas = undefined,
            .levels = std.ArrayList(LevelDescriptor).init(allocator),
            .junctions = std.ArrayList(LevelJunctionDescriptor).init(allocator),
            .entity_spawners = std.ArrayList(EntitySpawner).init(allocator),
            .environment_particle_emitters = std.ArrayList(EnvironmentParticleEmitter).init(allocator),
        };
    }

    pub fn deinit(self: *Resources) void {
        self.strings.deinit();
        self.levels.deinit();
        self.junctions.deinit();
        self.entity_spawners.deinit();
        self.environment_particle_emitters.deinit();
    }

    pub fn save_to_file(self: *const Resources, allocator: std.mem.Allocator, file_name: []const u8) !void {
        var serialized_data = std.ArrayList(u8).init(allocator);
        for (self.map) |byte_row| {
            // write the map
            _ = try serialized_data.writer().write(byte_row[0..]);
        }
        if (true) {
            var i: usize = 0;
            while (i < self.sprite_atlas.len) : (i+=2) {
                const a: u8 = @intCast(self.sprite_atlas[i]);
                const b: u8 = @intCast(self.sprite_atlas[i+1]);
                const the_byte: u8 = (a<<4 | b);
                _ = try serialized_data.writer().writeByte(the_byte);
            }
            // std.log.debug("wrote {}/2 bytes", .{i});
        }
        // write the level count
        // NOTE just int cast to u8, force level count to be less than 256
        _ = try serialized_data.writer().writeByte(@intCast(self.levels.items.len));
        for (self.levels.items) |level| {
            // write the level's name length
            // NOTE just int cast to u8, level name should be smaller than 256 bytes
            _ = try serialized_data.writer().writeByte(@intCast(level.name.length));
            // write the level's name
            for (self.get_string(level.name)) |char| try serialized_data.writer().writeByte(char);
            // write the level's map bounding box
            _ = try serialized_data.writer().writeByte(level.bb.top);
            _ = try serialized_data.writer().writeByte(level.bb.bottom);
            _ = try serialized_data.writer().writeByte(level.bb.left);
            _ = try serialized_data.writer().writeByte(level.bb.right);
        }
        // junctions
        _ = try serialized_data.writer().writeByte(@intCast(self.junctions.items.len));
        for (self.junctions.items) |junction| {
            _ = try serialized_data.writer().writeByte(junction.a.x);
            _ = try serialized_data.writer().writeByte(junction.a.y);
            _ = try serialized_data.writer().writeByte(junction.b.x);
            _ = try serialized_data.writer().writeByte(junction.b.y);
        }
        // enemy entity spawners
        _ = try serialized_data.writer().writeByte(@intCast(self.entity_spawners.items.len));
        for (self.entity_spawners.items) |spawner| {
            _ = try serialized_data.writer().writeByte(spawner.pos.x);
            _ = try serialized_data.writer().writeByte(spawner.pos.y);
            _ = try serialized_data.writer().writeByte(spawner.entity_type);
        }
        // environment particle emitters
        _ = try serialized_data.writer().writeByte(@intCast(self.environment_particle_emitters.items.len));
        for (self.environment_particle_emitters.items) |emitter| {
            _ = try serialized_data.writer().writeByte(emitter.pos.x);
            _ = try serialized_data.writer().writeByte(emitter.pos.y);
            _ = try serialized_data.writer().writeByte(emitter.particle_emitter_type);
        }

        const file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();
        try file.writeAll(serialized_data.items);
    }

    pub fn load_from_bytes(self: *Resources, reader: anytype) !void {

        // TODO this line breaks the wasm target??????? why???? ._.
        // 
        //     var new_resources = Resources.init(self.allocator);
        // 
        
        self.strings.clearAndFree();
        self.levels.clearAndFree();
        self.junctions.clearAndFree();
        self.entity_spawners.clearAndFree();
        self.environment_particle_emitters.clearAndFree();
        self.map = undefined;
        self.sprite_atlas = undefined;

        var new_resources = self;
        // if (builtin.os.tag != .windows) Application.flog("a {}", .{reader.context.pos});
        const map_data_start: [*]u8 = @ptrCast(&new_resources.map);
        // if (builtin.os.tag != .windows) Application.flog("a {}", .{reader.context.pos});
        const map_underlying_bytes: []u8 = @ptrCast(map_data_start[0..240*136]);
        // if (builtin.os.tag != .windows) Application.flog("a {}", .{reader.context.pos});
        // read the map
        if (true) {
            _ = try reader.read(map_underlying_bytes);
            for (map_underlying_bytes, 0..) |*data, i| {
                const index = data.*;
                // const prev_x = index % 16;
                // const prev_y = @divFloor(index,16);
                if (true) continue;
                if (i%240 == 0) std.log.debug("map[{},{}] = {}", .{i%240, @divFloor(i,240), index});
                // data.* = 16*(15-prev_y) + prev_x;
            }
        }
        else {
            // @memcpy(map_underlying_bytes, @constCast(&assets.map));
            new_resources.map = assets.map;
            try reader.skipBytes(new_resources.map.len, .{});
        }
        if (true) {
            var _bytes: [(8*8*16*16)/2]u8 = undefined;
            _ = try reader.read(&_bytes);
            for (_bytes, 0..) |the_byte, i| {
                const a: u8 = the_byte>>4;
                const b: u8 = (the_byte<<4)>>4;
                new_resources.sprite_atlas[2*i] = @intCast(a);
                new_resources.sprite_atlas[2*i+1] = @intCast(b);
                if (true) continue;
                const pixel1 = 2*i;
                const pixel_col = pixel1%(8*16);
                const pixel_row = @divFloor(pixel1, 8*16);
                const sprite_index_col = 15;
                const sprite_index_row = 15;
                if (pixel_col >= 8*sprite_index_col and pixel_col < 8*(sprite_index_col+1) and pixel_row >= 8*sprite_index_row and pixel_row < 8*(sprite_index_row+1)) {
                    std.log.debug("sprite[{},{}] @({},{}) = {}", .{sprite_index_col, sprite_index_row, pixel_col, pixel_row, @as(u4, @intCast(a))});
                    std.log.debug("sprite[{},{}] @({},{}) = {}", .{sprite_index_col, sprite_index_row, pixel_col+1, pixel_row, @as(u4, @intCast(b))});
                }
            }
        }
        else {
            // @memcpy(&new_resources.sprite_atlas, &assets.atlas_tiles_normalized);
            new_resources.sprite_atlas = assets.atlas_tiles_normalized;
            // try reader.skipBytes(new_resources.sprite_atlas.len*2, .{});
        }
        // read the level count
        const level_count: usize = @intCast(try reader.readByte());
        if (false) std.log.debug("level_count {}", .{level_count});
        var name_starting_index: usize = 0;
        for (0..level_count) |_| {
            const name_length: usize = @intCast(try reader.readByte());
            const slice = try new_resources.strings.addManyAsSlice(name_length);
            _ = try reader.read(slice);
            const top = try reader.readByte();
            const bottom = try reader.readByte();
            const left = try reader.readByte();
            const right = try reader.readByte();
            try new_resources.levels.append(.{
                .name = .{.index = name_starting_index, .length = name_length},
                .bb = BoundingBox(u8).from(top, bottom, left, right)
            });
            name_starting_index += name_length;
        }
        // read the level junction count
        const level_junction_count: usize = @intCast(try reader.readByte());
        if (false) std.log.debug("level_junction_count {}", .{level_junction_count});
        for (0..level_junction_count) |_| {
            const ax = try reader.readByte();
            const ay = try reader.readByte();
            const bx = try reader.readByte();
            const by = try reader.readByte();
            try new_resources.junctions.append(.{.a = Vec2(u8).from(ax, ay), .b = Vec2(u8).from(bx, by)});
        }
        const entity_spawner_count: usize = @intCast(try reader.readByte());
        if (false) std.log.debug("entity_spawner_count {}", .{entity_spawner_count});
        for (0..entity_spawner_count) |_| {
            const px = try reader.readByte();
            const py = try reader.readByte();
            const entity_type = try reader.readByte();
            try new_resources.entity_spawners.append(.{.pos = Vec2(u8).from(px, py), .entity_type = entity_type});
        }
        const environment_particle_emitters_count: usize = @intCast(try reader.readByte());
        if (false) std.log.debug("environment_particle_emitters_count {}", .{environment_particle_emitters_count});
        for (0..environment_particle_emitters_count) |_| {
            const px = try reader.readByte();
            const py = try reader.readByte();
            const emitter_type = try reader.readByte();
            try new_resources.environment_particle_emitters.append(.{.pos = Vec2(u8).from(px, py), .particle_emitter_type = emitter_type});
        }
    }

    pub fn get_string(self: *const Resources, string: String) []const u8 {
        return self.strings.items[string.index..string.index+string.length];
    }

    // const String = struct {
    //     index: usize,
    //     length: usize
    // };

    const LevelIndex = u8;

    const LevelDescriptor = struct {
        name: String,
        bb: BoundingBox(u8),
    };

    pub const LevelJunctionDescriptor = struct {
        a: Vec2(u8),
        b: Vec2(u8),
    };

    pub const EntitySpawner = struct {
        pos: Vec2(u8),
        entity_type: u8
    };

    pub const EnvironmentParticleEmitter = struct {
        pos: Vec2(u8),
        particle_emitter_type: u8
    };

};

const tic80 = struct {
    pub const Palette = [16]u24;
    // each `u4` is an index into a `Palette`
    pub const Sprite = [8*8]u4;
    // a sprite atlas is a collection of 256 sprites
    pub const Atlas = [256]Sprite;
    // each `u8` is an index into an `Atlas`
    pub const MapRow = [240]u8;
    pub const Map = [136]MapRow;
    pub const Flags = [256]u8;
};

pub const assets = struct {
    
    pub const ParticleEmitterType = enum(u8) {
        fire,
    };

    pub const EntityType = enum(u8) {
        slime,
        knight_1,
        knight_2,
        archer,
        slime_king,
    };

    pub const EntityDescriptor = struct {
        default_animation: *const AnimationDescriptor,
        weight: f32,
        hp: i32,
        speed: f32,
        chase_range: f32,
        attack_dmg: i32,
        attack_cooldown: usize,
        attack_range: f32,
        hurtbox: BoundingBox(f32),
        
        pub fn from(t: EntityType) EntityDescriptor {
            return switch (t) {
                .slime => entity_slime,
                .knight_1 => entity_knight_1,
                .knight_2 => entity_knight_2,
                .archer => entity_archer,
                .slime_king => entity_slime_king,
            };
        }
    };
    
    pub const entity_slime = EntityDescriptor {
        .default_animation = &animation_slime,
        .weight = 2,
        .hp = 30,
        .speed = 0.02,
        .chase_range = 6*8,
        .attack_dmg = 15,
        .attack_cooldown = 60,
        .attack_range = 3*8,
        .hurtbox = BoundingBox(f32).from(4, 0, -3, 3),
    };
    pub const entity_knight_1 = EntityDescriptor {
        .default_animation = &animation_knight_1,
        .weight = 5,
        .hp = 70,
        .speed = 0.03,
        .chase_range = 7*8,
        .attack_dmg = 30,
        .attack_cooldown = 60*2,
        .attack_range = 2*8,
        .hurtbox = BoundingBox(f32).from(6, 0, -3, 3),
    };
    pub const entity_knight_2 = EntityDescriptor {
        .default_animation = &animation_knight_2,
        .weight = 5,
        .hp = 70,
        .speed = 0.03,
        .chase_range = 7*8,
        .attack_dmg = 30,
        .attack_cooldown = 60*2,
        .attack_range = 2*8,
        .hurtbox = BoundingBox(f32).from(6, 1, 3, 9),
    };
    pub const entity_archer = EntityDescriptor {
        .default_animation = &animation_archer,
        .weight = 3,
        .hp = 60,
        .speed = 0.1,
        .chase_range = 10*8,
        .attack_dmg = 30,
        .attack_cooldown = 60*2,
        .attack_range = 7*8,
        .hurtbox = BoundingBox(f32).from(5, 3, -3, 3),
    };
    pub const entity_slime_king = EntityDescriptor {
        .default_animation = &animation_slime,
        .weight = 10,
        .hp = 200,
        .speed = 0.015,
        .chase_range = 30*8,
        .attack_dmg = 40,
        .attack_cooldown = 60*3,
        .attack_range = 3*8,
        .hurtbox = BoundingBox(f32).from(4*2, 0*2, -3*2, 3*2),
    };

    pub const AnimationDescriptor = struct {
        sprites: []const u8,
        duration: usize,
        pub inline fn from(sprites: []const u8, duration: usize) AnimationDescriptor {
            return AnimationDescriptor { .sprites = sprites, .duration = duration };
        }
    };

    pub const animation_attack_1 = AnimationDescriptor.from( &[_]u8 { 213, 214, 215, 216, 217 }, 10);
    pub const animation_wings = AnimationDescriptor.from( &[_]u8 { 129, 130 }, 30);
    pub const animation_slime = AnimationDescriptor.from( &[_]u8 { 66, 67 }, 60);
    pub const animation_knight_1 = AnimationDescriptor.from( &[_]u8 { 64, 65 }, 60);
    pub const animation_knight_2 = AnimationDescriptor.from( &[_]u8 { 68, 69 }, 60);
    pub const animation_penguin = AnimationDescriptor.from( &[_]u8 { 48, 49 }, 60);
    pub const animation_archer = AnimationDescriptor.from( &[_]u8 { 80, 81 }, 120);
    pub const animation_player_idle = AnimationDescriptor.from( &[_]u8 { 211, 195 }, 60);
    pub const animation_player_walk = AnimationDescriptor.from( &[_]u8 { 211, 212 }, 10);
    pub const animation_preparing_attack = AnimationDescriptor.from( &[_]u8 { 145, 146, 0, 0, 147, 148 }, 18);
    
    pub const palette = tic80.Palette {
        0x1a1c2c,
        0x5d275d,
        0xb13e53,
        0xef7d57,
        0xffcd75,
        0xa7f070,
        0x38b764,
        0x257179,
        0x29366f,
        0x3b5dc9,
        0x41a6f6,
        0x73eff7,
        0xf4f4f4,
        0x94b0c2,
        0x566c86,
        0x333c57
    };

};
