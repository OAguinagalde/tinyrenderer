const std = @import("std");
const builtin = @import("builtin");
const math = @import("math.zig");
const graphics = @import("graphics.zig");
const physics = @import("physics.zig");
const font = @import("text.zig").font;
const core = @import("core.zig");
const wav = @import("wav.zig");

const BoundingBox = math.BoundingBox;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const M33 = math.M33;
const Buffer2D = @import("buffer.zig").Buffer2D;
const RGB = @import("pixels.zig").RGB;
const RGBA = @import("pixels.zig").RGBA;
const BGR = @import("pixels.zig").BGR;
const Ecs = @import("ecs.zig").Ecs;
const Entity = @import("ecs.zig").Entity;
const Sound = wav.Sound;
const TextRenderer = @import("text.zig").TextRenderer(platform.OutPixelType, 1024, 1);
const Renderer = @import("app_003.zig").Renderer;
const Resources = @import("app_003.zig").Resources;

const windows = @import("windows.zig");
const wasm = @import("wasm.zig");
const platform = if (builtin.os.tag == .windows) windows else wasm;

const SCALE = 4;
const Application = platform.Application(.{
    .init = init,
    .update = update,
    .dimension_scale = 1,
    .desired_width = 240*SCALE,
    .desired_height = 136*SCALE,
});

comptime {
    if (@This() == @import("root")) {
        _ = Application.run;
    }
}

pub fn main() !void {
    try Application.run();
}

const State = struct {
    entities: game.ECS,
    game_render_target: Buffer2D(platform.OutPixelType),
    camera: Camera,
    debug: bool,
    rng: core.Random,
    ui: ImmediateModeGui,
    resources: Resources,
    scrolling_log: ScrollingLog(1024*3),
};

var state: State = undefined;

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    state.game_render_target = Buffer2D(platform.OutPixelType).from(try allocator.alloc(platform.OutPixelType, 240*136), 240);
    state.camera = Camera.init(Vector3f { .x = 0, .y = 0, .z = 0 });
    state.debug = true;
    state.rng = core.Random.init(@bitCast(platform.timestamp()));
    state.scrolling_log.init();
    state.entities = try game.ECS.init_capacity(allocator, 32);
    ImmediateModeGui.init(&state.ui);
    state.resources = try Resources.init(allocator);
    const bytes = try Application.read_file_sync(allocator, "res/resources.bin");
    defer allocator.free(bytes);
    try state.resources.load_from_bytes(bytes);

    game.slime_spawn(Vec2(f32).from(5*8, 8*2), 0);
    game.slime_spawn(Vec2(f32).from(7*8, 8*2), 0);
    game.player_spawn(0, Vec2(f32).from(4*8, 8*2), 0);
    game.player_spawn(1, Vec2(f32).from(4*8 + 6*8, 8*3), 0);

    for (&game.skill_registry.all_skills) |cs| log("skill > {?}", .{cs});
}

pub fn update(ud: *platform.UpdateData) anyerror!bool {

    const h: f32 = @floatFromInt(state.game_render_target.height);
    const w: f32 = @floatFromInt(state.game_render_target.width);

    const real_h: f32 = @floatFromInt(ud.pixel_buffer.height);
    const real_w: f32 = @floatFromInt(ud.pixel_buffer.width);

    const real_hi: i32 = @intCast(ud.pixel_buffer.height);
    const real_wi: i32 = @intCast(ud.pixel_buffer.width);

    const player_count = 2;
    const KeyType = enum(u8) {select_next_target, move_left, move_right, action_0, action_1, action_2, action_3};
    // const player_1_skills = &[_] struct { number_key: u8, skill: type } {
    //     .{ .number_key = '0', .skill = game.skills.slime_melee },
    //     .{ .number_key = '1', .skill = game.skills.unarmed_melee },
    //     .{ .number_key = '2', .skill = game.skills.kick },
    //     .{ .number_key = '3', .skill = game.skills.fireball },
    // };
    // const player_2_skills = &[_] struct { number_key: u8, skill: type } {
    //     .{ .number_key = '0', .skill = game.skills.slime_melee },
    //     .{ .number_key = '1', .skill = game.skills.unarmed_melee },
    //     .{ .number_key = '2', .skill = game.skills.kick },
    //     .{ .number_key = '3', .skill = game.skills.fireball },
    // };
    // const players_skills: [player_count][]const struct{ number_key: u8, skill: type } = .{&player_1_skills, player_2_skills};
    const players_skills  = [player_count][4]struct { number_key: u8, skill: usize } {
        .{
            .{ .number_key = '0', .skill = game.skills.slime_melee.get_skill_id() },
            .{ .number_key = '1', .skill = game.skills.unarmed_melee.get_skill_id() },
            .{ .number_key = '2', .skill = game.skills.kick.get_skill_id() },
            .{ .number_key = '3', .skill = game.skills.fireball.get_skill_id() },
        },
        .{
            .{ .number_key = '0', .skill = game.skills.slime_melee.get_skill_id() },
            .{ .number_key = '1', .skill = game.skills.unarmed_melee.get_skill_id() },
            .{ .number_key = '2', .skill = game.skills.kick.get_skill_id() },
            .{ .number_key = '3', .skill = game.skills.fireball.get_skill_id() },
        }
    };
    const players_keybinds: [player_count][]const u8 = .{
        "QAD1234",
        "UJL7890"
    };
    comptime for (players_keybinds) |keybinds| std.debug.assert(@typeInfo(KeyType).@"enum".fields.len == keybinds.len);

    const entities = &state.entities;

    const ms_taken_update: f32 = blk: {
        const profile = Application.perf.profile_start();

        if (ud.key_pressed('G')) state.debug = !state.debug;
        
        const player_1: Entity = label: {
            var it = entities.iterator(.{game.GameTags});
            while (it.next()) |e| {
                if (entities.require_component(game.GameTags, e).isSet(@intFromEnum(game.Tag.IsPlayer))) break :label e;
            }
            unreachable;
        };
        const player_2: Entity = label: {
            var it = entities.iterator(.{game.GameTags});
            while (it.next()) |e| {
                if (entities.require_component(game.GameTags, e).isSet(@intFromEnum(game.Tag.IsPlayer)) and e.id != player_1.id) break :label e;
            }
            unreachable;
        };
        const players: [player_count]Entity = .{player_1, player_2};
        
        const players_target: [player_count]*game.Target = .{
            entities.require_component(game.Target, player_1),
            entities.require_component(game.Target, player_2)
        };
        for (players_target) |player_target| {
            if (player_target.entity) |e| {
                if (!entities.valid_entity(e)) {
                    player_target.entity = null;
                }
            }
        }

        for (players_target, 0..) |player_target, player_index| {
            const keybind = players_keybinds[player_index][@intFromEnum(KeyType.select_next_target)];
            if (ud.key_pressed(keybind)) {
                const targets_capacity = 12;
                var targets_len: usize = 0;
                const targets_first_12: [targets_capacity]?Entity = label: {
                    var list: [targets_capacity]?Entity = undefined;
                    for (&list) |*i| i.* = null;
                    var index: usize = 0;
                    var it = entities.iterator(.{game.GameTags});
                    log("Looking for targets...", .{});
                    while (it.next()) |e| {
                        if (entities.require_component(game.GameTags, e).isSet(@intFromEnum(game.Tag.IsTarget))) {
                            list[index] = e;
                            log("- target {?}", .{e});
                            index += 1;
                            if (index == targets_capacity) break;
                        }
                    }
                    targets_len = index;
                    break :label list;
                    // TODO order the target list based on position and select the next one
                };
                if (targets_len > 0) {
                    player_target.entity = targets_first_12[state.rng.u()%targets_len];
                    log("Target changed to {}", .{player_target.entity.?.id});
                }
            }
        }

        for (players, 0..) |player, i| {
            const keybind_right = players_keybinds[i][@intFromEnum(KeyType.move_right)];
            const keybind_left = players_keybinds[i][@intFromEnum(KeyType.move_left)];

            var player_is_walking: bool = false;
            if (ud.key_pressing(keybind_right)) {
                const phys = entities.require_component(game.Phys, player);
                const dir = entities.require_component(game.LookDir, player);
                phys.velocity.x += 0.010;
                dir.* = .Right;
                player_is_walking = true;
            }
            if (ud.key_pressing(keybind_left)) {
                const phys = entities.require_component(game.Phys, player);
                const dir = entities.require_component(game.LookDir, player);
                phys.velocity.x -= 0.010;
                dir.* = .Left;
                player_is_walking = true;
            }
            if (player_is_walking) {
                const casting = entities.require_component(game.CastingInfo, player);
                if (casting.is_casting) {
                    casting.cast_cancel();
                }
                // TODO walk animation for player   
            }
        }

        // fire up actions for each player
        for (players, players_target, players_keybinds, players_skills) |player, player_target, keybinds, skills| {
            if (player_target.entity) |target| {
                for (skills, 0..) |ps, skill_positional_number| {
                    // const skill_positional_number = ps.number_key;
                    const skill_0_index_in_keybinds = @intFromEnum(KeyType.action_0);
                    const skill_keybind = keybinds[skill_0_index_in_keybinds + skill_positional_number];
                    if (ud.key_pressed(skill_keybind)) {
                        const skill = game.get_skill(ps.skill);
                        if (skill.check.?(player, target, ud.frame)) {
                            const action = if (entities.try_component(game.ActionTargeted, player)) |a| a else entities.set_component(game.ActionTargeted, player);
                            action.* = .{
                                .skill = ps.skill,
                                .target = target
                            };
                        }
                    }
                }
            }
        }
        
        // TODO IA
        {
            var it = entities.iterator(.{game.Behaviour});
            while (it.next()) |e| {
                const behaviour = entities.require_component(game.Behaviour, e);
                switch (behaviour.*) {
                    // .slime => game.behaviours.slime(e, player),
                    // .knight => game.behaviours.knight(e, player),
                    else => {}
                }
            }
        }

        // process skills
        {
            var it = entities.iterator(.{game.ActionTargeted});
            while (it.next()) |e| {
                const a = entities.require_component(game.ActionTargeted, e);
                const skill = game.get_skill(a.skill);
                const target = a.target;
                const origin = e;
                log("INFO: [{}] Processing skill {} from {} to {}", .{ud.frame, a.skill, origin, target});
                if (skill.cast_start) |fn_cast_start| std.debug.assert(fn_cast_start(origin, target, ud.frame))
                else if (skill.do) |fn_do| std.debug.assert(fn_do(origin, target, ud.frame))
                else log("ERROR: failed to process skill!", .{});
            }
        }
        
        // check every entity that is currently casting something and if finished, execute the on finish effect of the skill
        var it = entities.iterator(.{game.CastingInfo});
        while (it.next()) |e| {
            const casting = entities.require_component(game.CastingInfo, e);
            if (casting.is_casting) {
                const skill = game.get_skill(casting.skill_id);
                if (skill.get_cast_time) |fn_get_cast_time| if (casting.finished(ud.frame, fn_get_cast_time())) {
                    std.debug.assert(skill.cast_finish.?(e, casting.target, ud.frame));
                };
            }
        }

        game.entities_update_physics();

        break :blk Application.perf.profile_end(profile);
    };

    var renderer: Renderer(platform.OutPixelType) = undefined;

    const ms_taken_render: f32 = blk: {
        const profile = Application.perf.profile_start();
        state.game_render_target.clear(platform.OutPixelType.from_hex(0x000000));
        const view_matrix_m33 = M33.look_at(Vector2f.from(state.camera.pos.x, state.camera.pos.y), Vector2f.from(0, 1));
        const projection_matrix_m33 = M33.orthographic_projection(0, w, h, 0);
        const viewport_matrix_m33 = M33.viewport(0, 0, w, h);
        const mvp_matrix_33 = projection_matrix_m33.multiply(view_matrix_m33.multiply(M33.identity()));

        renderer = try Renderer(platform.OutPixelType).init(ud.allocator);
        
        renderer.set_context(
            state.game_render_target,
            mvp_matrix_33,
            viewport_matrix_m33
        );

        const sprite_atlas = &state.resources.sprite_atlas;

        const player_1: Entity = label: {
            var it = entities.iterator(.{game.GameTags});
            while (it.next()) |e| {
                if (entities.require_component(game.GameTags, e).isSet(@intFromEnum(game.Tag.IsPlayer))) break :label e;
            }
            unreachable;
        };
        const player_2: Entity = label: {
            var it = entities.iterator(.{game.GameTags});
            while (it.next()) |e| {
                if (entities.require_component(game.GameTags, e).isSet(@intFromEnum(game.Tag.IsPlayer)) and e.id != player_1.id) break :label e;
            }
            unreachable;
        };
        const players: [player_count]Entity = .{player_1, player_2};
        
        const players_target: [player_count]*game.Target = .{
            entities.require_component(game.Target, player_1),
            entities.require_component(game.Target, player_2)
        };
        for (players_target) |player_target| {
            if (player_target.entity) |e| {
                if (!entities.valid_entity(e)) {
                    player_target.entity = null;
                }
            }
        }

        // render entities with position and sprite
        {
            var it = entities.iterator(.{game.Pos, game.Sprite});
            while (it.next()) |e| {
                const pos = entities.require_component(game.Pos, e);
                const sprite = entities.require_component(game.Sprite, e);
                const final_position = pos.add(Vec2(f32).from(-4, 0)) ;
                const dir = entities.require_component(game.LookDir, e);
                renderer.add_sprite_from_atlas_by_index(
                    Vec2(usize).from(8,8), Vec2(usize).from(16, 16),
                    @constCast(&game.palette),
                    Buffer2D(u4).from(sprite_atlas, 16*8),
                    @intCast(sprite.*),
                    BoundingBox(f32).from_bl_size(
                        final_position,
                        Vec2(f32).from(8,8)
                    ),
                    .{ .mirror_horizontally = (dir.* == .Left) , .blend = true, }
                ) catch unreachable;
                for (players_target) |player_target| if (player_target.entity) |t| if (e.id == t.id and e.version == t.version) {
                    renderer.add_sprite_from_atlas_by_index(
                        Vec2(usize).from(8,8), Vec2(usize).from(16, 16),
                        @constCast(&game.palette),
                        Buffer2D(u4).from(sprite_atlas, 16*8),
                        @intCast(207),
                        BoundingBox(f32).from_bl_size(
                            final_position.add(Vec2(f32).from(0, 8)),
                            Vec2(f32).from(8,8)
                        ),
                        .{ .mirror_horizontally = false, .blend = true, }
                    ) catch unreachable;
                };
            }
        }

        // render the casting bar of the player
        for (players) |player| { 
            const pos = state.entities.require_component(game.Pos, player);
            const final_position = pos.add(Vec2(f32).from(-4, 0)) ;
            // const cds = state.entities.require_component(game.Cooldowns);
            const casting = state.entities.require_component(game.CastingInfo, player);
            if (casting.is_casting) {
                const skill_id = casting.skill_id;
                const skill_cast_time = game.get_skill(skill_id).get_cast_time.?();
                const cast_start_frame = casting.cast_start_frame;
                var percentage = @as(f32, @floatFromInt(ud.frame - cast_start_frame)) / @as(f32, @floatFromInt(skill_cast_time));
                percentage = if (percentage > 1) 1 else if (percentage < 0) 0 else percentage;
                renderer.add_quad_border(
                    BoundingBox(f32).from_bl_size(
                        final_position.add(Vec2(f32).from(0, 9)),
                        Vec2(f32).from(percentage*8,0)
                    ),
                    1,
                    RGBA.from_hex(0x00ff00ff)
                ) catch unreachable;
            }
        }

        // render the player skill bar
        for (players, players_skills, 0..) |player, player_skills, player_index| {
            const offset_extra = player_index*16;
            var cds = state.entities.require_component(game.Cooldowns, player);
            const offset_y: usize = 8*3 + offset_extra;
            const offset_x: usize = 8*2;
            // TODO make player skills non comptime lol
            for (player_skills, 0..) |ps, index| {
                
                const skill_id = ps.skill;
                const skill_sprite: usize = switch (skill_id) {
                    @intFromEnum(game.skill_type.fireball) => 190,
                    else => 189,
                };
                // render the skill placeholder
                renderer.add_sprite_from_atlas_by_index(
                    Vec2(usize).from(8,8), Vec2(usize).from(16, 16),
                    @constCast(&game.palette),
                    Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8),
                    191,
                    BoundingBox(f32).from_bl_size(
                        Vec2(usize).from(offset_x + (3*index) + (8*index), offset_y).to(f32),
                        Vec2(f32).from(8,8)
                    ),
                    .{ .mirror_horizontally = false, .blend = true, }
                ) catch unreachable;
                // render the skill icon
                renderer.add_sprite_from_atlas_by_index(
                    Vec2(usize).from(8,8), Vec2(usize).from(16, 16),
                    @constCast(&game.palette),
                    Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8),
                    skill_sprite,
                    BoundingBox(f32).from_bl_size(
                        Vec2(usize).from(offset_x + (3*index) + (8*index), offset_y).to(f32),
                        Vec2(f32).from(8,8)
                    ),
                    .{ .mirror_horizontally = false, .blend = true, }
                ) catch unreachable;
                // render cd animation
                if (cds.get_cooldown(skill_id)) |cd| {
                    const skill_cd = game.get_skill(cd.id).get_cd.?();
                    if (cds.in_cooldown(cd.id, ud.frame, skill_cd)) {
                        var percentage = @as(f32, @floatFromInt(ud.frame - cd.used_at)) / @as(f32, @floatFromInt(skill_cd));
                        percentage = if (percentage > 1) 1 else if (percentage < 0) 0 else percentage;
                        renderer.add_quad_border(BoundingBox(f32).from_bl_size(
                            Vec2(usize).from(offset_x + (3*index) + (8*index), offset_y).to(f32),
                            Vec2(f32).from(8*percentage,8)
                        ), 1, RGBA.from_hex(0xff000077)) catch unreachable;
                    }
                }
                // render the key to be pressed
                renderer.add_text(Vec2(usize).from(offset_x-2 + (3*index) + (8*index), offset_y-2).to(f32), "{c}", .{ps.number_key}, RGBA.from_hex(0x00FF00FF)) catch unreachable;
            }
        }

        try renderer.flush_all();

        break :blk Application.perf.profile_end(profile);
    };

    // The game is being rendered to a 1/4 size of the window, so scale the image back up to the real size
    const ms_taken_upscale: f32 = blk: {
        const profile = Application.perf.profile_start();
        scalers.upscale(platform.OutPixelType, state.game_render_target, ud.pixel_buffer, SCALE);
        break :blk Application.perf.profile_end(profile);
    };

    const static = struct {
        var ms_taken_render_ui_previous: f32 = 0;
        var ms_taken_ui_previous: f32 = 0;
    };
    
    var ui_builder: ImmediateModeGui.UiBuilder = undefined;
    ui_builder = state.ui.prepare_frame(ud.allocator, .{
        .mouse_pos = ud.mouse,
        .mouse_down = ud.mouse_left_down,
    });

    var builder: ImmediateModeGui.UiBuilder = undefined;

    if (state.debug) {

        static.ms_taken_ui_previous = blk: {
            const profile = Application.perf.profile_start();
            
            builder = state.ui.prepare_frame(ud.allocator, .{
                .mouse_pos = ud.mouse,
                .mouse_down = ud.mouse_left_down,
            });

            const mouse: Vector2f = mouse_blk: {
                const mx = @divFloor(ud.mouse.x, Application.dimension_scale);
                // inverse y since mouse is given relative to top left corner
                const my = @divFloor((Application.height*Application.dimension_scale) - ud.mouse.y, Application.dimension_scale);
                const offset = Vector2f.from(state.camera.pos.x, state.camera.pos.y);
                const pos = Vector2i.from(mx, my).to(f32).add(offset);
                break :mouse_blk pos;
            };

            const player: Entity = label: {
            var it = state.entities.iterator(.{game.GameTags});
                while (it.next()) |e| {
                    if (state.entities.require_component(game.GameTags, e).isSet(@intFromEnum(game.Tag.IsPlayer))) break :label e;
                }
                unreachable;
            };
            
            var debug = try builder.begin("debug", BoundingBox(i32).from(real_hi, 0, 0, real_wi), false); {
                try debug.label("ms {d: <9.2}", .{ud.ms});
                try debug.label("io {?}", .{builder.io});
                try debug.label("ms {d: <9.2}", .{ud.ms});
                try debug.label("fps {d:0.4}", .{ud.ms / 1000*60});
                try debug.label("frame {}", .{ud.frame});
                try debug.label("camera {d:.8}, {d:.8}, {d:.8}", .{state.camera.pos.x, state.camera.pos.y, state.camera.pos.z});
                try debug.label("mouse {d:.4} {d:.4}", .{mouse.x, mouse.y});
                try debug.label("dimensions {d:.4} {d:.4} | real {d:.4} {d:.4}", .{w, h, real_w, real_h});
                try debug.label("update  took {d:.8}ms", .{ms_taken_update});
                try debug.label("render  took {d:.8}ms", .{ms_taken_render});
                try debug.label("player cooldowns {?}", .{state.entities.require_component(game.Cooldowns, player).*});
                try debug.label("player action td {?}", .{if (state.entities.try_component(game.ActionTargeted, player)) |a| a else null});
                try debug.label("player casting   {?}", .{state.entities.require_component(game.CastingInfo, player).*});

                const stuff = struct {
                    const times_count = 120;
                    var times: [times_count]f32 = undefined;
                    var times_idx: usize = 0;
                    var initialized = false;
                };
                if (!stuff.initialized) {
                    stuff.initialized = true;
                    for (&stuff.times) |*val| val.* = 0;
                }
                stuff.times[stuff.times_idx] = ms_taken_upscale;
                stuff.times_idx = (stuff.times_idx + 1) % stuff.times_count;
                const final_time = calc_time_block: {
                    var ft: f32 = 0;
                    for (&stuff.times) |val| ft += val;
                    break :calc_time_block ft/stuff.times_count;
                };
                try debug.label("upscale took {d:.8}ms", .{final_time});
                try debug.label("ui prev took {d:.8}ms", .{static.ms_taken_ui_previous});
                try debug.label("ui rend took {d:.8}ms", .{static.ms_taken_render_ui_previous});
                
                try debug.label("# Logs", .{});
                // render the last #want logs
                {
                    const want = 16;
                    var skip_left = if (state.scrolling_log.count > want) state.scrolling_log.count - want else 0;
                    var it = state.scrolling_log.iterator();
                    while (it.next()) |message| {
                        if (skip_left>0) {
                            skip_left -= 1;
                            continue;
                        }
                        try debug.label("{s}", .{message});
                    }
                }
                
                // force debug container to be the lowest layer
                for (state.ui.containers_order.slice(), 0..) |container_id, i| if (container_id == debug.persistent.unique_identifier) {
                    const aux = state.ui.containers_order.slice()[0];
                    state.ui.containers_order.slice()[0] = container_id;
                    state.ui.containers_order.slice()[i] = aux;
                };
            }

            break :blk Application.perf.profile_end(profile);
        };

        static.ms_taken_render_ui_previous = blk: {
            const profile = Application.perf.profile_start();

            const draw_call_data = builder.draw_call_data;
            for (state.ui.containers_order.slice()) |container_id| {
                if (draw_call_data.draw_call_list_indices[container_id]) |list_index| {
                    var shape_vertex_buffer = std.ArrayList(ShapeRenderer(platform.OutPixelType).shader.Vertex).init(ud.allocator);
                    var text_renderer = try TextRenderer.init(ud.allocator);
                    const draw_calls = draw_call_data.draw_call_lists.items[list_index];
                    for (draw_calls.items) |dc| switch (dc.draw_call_type) {
                        .shape => {
                            const draw_call_shape = draw_call_data.shape.items[dc.index];
                            try ShapeRenderer(platform.OutPixelType).add_quad_from_bb(&shape_vertex_buffer, draw_call_shape.bounding_box, switch (draw_call_shape.style) {
                                .base => color.palette_4,
                                .accent => color.palette_3,
                                .highlight => color.palette_2,
                                .special => color.palette_1,
                            });
                        },
                        .text => {
                            const draw_call_text = draw_call_data.text.items[dc.index];
                            const text = builder.string_data.items[draw_call_text.text[0]..draw_call_text.text[0] + draw_call_text.text[1]];
                            try text_renderer.print(draw_call_text.pos, "{s}", .{text}, switch (draw_call_text.style) {
                                .base => color.palette_1,
                                .accent => color.palette_2,
                                .highlight => color.palette_3,
                                .special => color.palette_4,
                            });
                        }
                    };
                    ShapeRenderer(platform.OutPixelType).render_vertex_buffer(
                        &shape_vertex_buffer,
                        ud.pixel_buffer,
                        M33.orthographic_projection(0, real_w, real_h, 0),
                        M33.viewport(0, 0, real_w, real_h)
                    );
                    text_renderer.render_all(
                        ud.pixel_buffer,
                        M33.orthographic_projection(0, real_w, real_h, 0),
                        M33.viewport(0, 0, real_w, real_h)
                    );
                }
            }

            break :blk Application.perf.profile_end(profile);
        };

    }

    return true;
}

fn log(comptime fmt: []const u8, args: anytype) void {
    var buffer: [1024*16] u8 = undefined;
    const message: []const u8 = std.fmt.bufPrint(&buffer, fmt, args) catch @panic("Failed to log!");
    state.scrolling_log.append(message);
    std.log.debug("{s}", .{message});
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
    const red_hp_bar = RGBA.from_hex(0xff3333ff);
};

const AudioTrack = struct {
    wav: wav.Sound,
    // reinterpret the raw bytes of the audio track as an []i16
    samples: []const i16,
    samples_per_second_f: f64,
    duration_seconds: f64,
    time_offset: f64,
};

pub fn play(sound: sounds) void {
    audio_play(&state.audio_tracks, state.sound_library[@intFromEnum(sound)]);
}

pub fn audio_play(audio_tracks: []?AudioTrack, sound: wav.Sound) void {
    for (audio_tracks) |*maybe_audio_track| {
        if (maybe_audio_track.* == null) {
            // found an unused audio track, set it with the new audio track
            const samples = @as([*]const i16, @alignCast(@ptrCast(sound.raw.ptr)))[0..@divExact(sound.raw.len, 2)];
            var duration: f64 = @floatFromInt(@divFloor(samples.len, sound.sample_rate));
            if (sound.channel_count == 2) duration /= 2;
            maybe_audio_track.* = .{
                .time_offset = 0,
                .wav = sound,
                .samples = samples,
                .samples_per_second_f = @floatFromInt(sound.sample_rate),
                .duration_seconds = duration,
            };
            return;
        }
    }
    // if we get here it means couldn't find an unused track
}

const sounds = enum {
    attack,
    jump,
    knight_prepare,
    knight_attack,
    slime_attack_a,
    slime_attack_b,
    damage_received_unused,
    die_received_unused,
    music_unused,
    music_penguknight,
};

const wav_files = &[_][]const u8 {
    "res/sfx62_attack.wav",
    "res/sfx0_jump.wav",
    "res/sfx5_knight_prepare.wav",
    "res/sfx8_knight_attack.wav",
    "res/sfx32_slime_attack.wav",
    "res/sfx33_slime_attack.wav",
    "res/sfx57_damage_received_unused.wav",
    "res/sfx59_die_unused.wav",
    "res/m0_unused.wav",
    "res/m1_penguknight.wav",
};

pub fn produce_sound(time: f64) f64 {

    const max_i16_f: f64 = @floatFromInt(std.math.maxInt(i16));

    // TODO It's probably better to somehow pre-calculate the samples being generated for a sound and just caching them
    // and passing them directly as an array of pre-calculated samples, rather than make them one by one like now.
    // But doing that means changing the way the whole thing works, so later...
    var resulting_sample: f64 = 0;
    for (&state.audio_tracks) |*audio_track_maybe| {
        if (audio_track_maybe.*) |*audio_track| {
            if (audio_track.time_offset == 0) {
                // TODO for now I'm not sure how to properly synchronize the timer in the audio thread and the one in the
                // main thread so whenever time_offset is 0 it means it just started so just set the time offset
                // to the time here since this is the relevant audio thread timer
                audio_track.time_offset = time;
            }
            // we are done playing the audio track so free it so that other audio tracks can be played
            if (time >= audio_track.time_offset+audio_track.duration_seconds) {
                audio_track_maybe.* = null;
                continue;
            }
            const track = audio_track.wav;
            const samples: []const i16 = audio_track.samples;
            // @mod so that it loops back
            const actual_time = @mod(time-audio_track.time_offset, audio_track.duration_seconds);
            const next_sample_index: usize = @intFromFloat(audio_track.samples_per_second_f * actual_time);
            const sample: i16 = switch (track.channel_count) {
                // This is how I expect the samples to be stored in memory when there is a single channel:
                // sample0: i16, sample1: i16, ...
                1 => samples[next_sample_index],
                // This is how I expect the samples to be stored in memory when there is 2 channels:
                // sample0 {channel0: i16, channel1: i16}, sample1 {channel0: i16, channel1: i16}, ...
                // TODO for now only care about channel 0, implement proper stereo sound
                2 => samples[@mod(next_sample_index*2, samples.len)],
                else => @panic("AAAAAAAAAAAH no more channeeeellss!!! AAAAAAHHH"),
            };
            const sample_f: f64 = @floatFromInt(sample);
            const sample_final: f64 = sample_f/max_i16_f;
            resulting_sample += sample_final;
        }
    }
    return resulting_sample;
}

const Physics = blk: {
    const granularity = 1;
    const config = physics.PhysicsConfig {
        // barely no air friction, but enough for it to be there
        .friction_air = 0.85,
        // strong friction on the floor to make movement less floaty
        .friction_floor = 0.85,
        .granularity = granularity,
        // strong gravity to prevent the player from jumping too much
        .gravity = 0.004 * granularity,
        .pad_bottom = 0.01,
        .pad_top = 0.6,
        .pad_left = 0.2,
        .pad_right = 0.8,
        .tile_size = 8
    };
    break :blk physics.PhysicalWorld(config, collision_checker);
};

inline fn collision_checker(tile: Vec2(i32)) bool {
    return (tile.x < 0 or tile.y < 0);
}

const Camera = struct {
    pos: Vector3f,
    bounds: BoundingBox(f32),
    
    pub fn init(pos: Vector3f) Camera {
        return Camera {
            .pos = pos,
            .bounds = undefined,
        };
    }

    pub fn move_to(self: *Camera, pos: Vector2f, real_width: f32, real_height: f32) void {
        const bound_width = self.bounds.width();
        const bound_height = self.bounds.height();

        // center the camera on the level bound
        self.pos.x = self.bounds.left - (real_width/2) + (bound_width/2);
        if (bound_width > real_width) {
            // if the level is bigger than the screen, pan it without showing the outside of the level
            const half_diff = (bound_width - real_width)/2;
            const c = self.pos.x;
            self.pos.x = std.math.clamp(pos.x-(real_width/2), c-half_diff, c+half_diff);
        }
        
        self.pos.y = self.bounds.bottom - (real_height/2) + (bound_height/2);
        if (bound_height > real_height) {
            const half_diff = (bound_height - real_height)/2;
            const c = self.pos.y;
            self.pos.y = std.math.clamp(pos.y-(real_height/2), c-half_diff, c+half_diff);
        }

    }

    pub fn set_bounds(self: *Camera, bounds: BoundingBox(f32)) void {
        self.bounds = bounds;
    }
};

/// returns a random f32 [0,1]
const f = struct {
    pub inline fn random_float() f32 {
        return @floatCast(state.random.f());
    }
}.random_float;

// Given a type T, returns a unique identifier for that type T
pub fn identify_type(comptime T: type) usize {
    const magic = struct {
        // NOTE capture T so that the identity of `magic` is different for each input T
        // and so the address of `dummy` is different as well
        const CaptureType = T;
        var dummy: u8 = undefined;
    };
    const ptr = &magic.dummy;
    return @intFromPtr(ptr);
}

test "identify_type" {
    const SomeType = struct {thing:u32};
    const OtherType = struct {thing:u32};
    try std.testing.expect(identify_type(SomeType) == identify_type(SomeType));
    try std.testing.expect(identify_type(OtherType) == identify_type(OtherType));
    try std.testing.expect(identify_type(SomeType) != identify_type(OtherType));
}

/// use zig magic to make an equal type to T, but not the same.
/// alternative_always(SomeType, opaque{}) != alternative_always(SomeType, opaque{})
pub fn alternative_always(comptime T: type, comptime pass_opaque_here_thanks: type) type {
    var ti = @typeInfo(T);
    switch(ti) {
        .Struct => |*s| {
            s.fields = s.fields ++ .{
                .{
                    .name = std.fmt.comptimePrint("{s}", .{@typeName(T)}),
                    .type = type,
                    .default_value = &pass_opaque_here_thanks,
                    .is_comptime = true,
                    .alignment = 0,
                },
            };
            s.decls = &.{};
        },
        .Enum => |*e| {
            e.fields = e.fields ++ .{
                .{
                    .name = std.fmt.comptimePrint("{s}", .{@typeName(T)}),
                    // .type = type,
                    // .default_value = &pass_opaque_here_thanks,
                    // .is_comptime = true,
                    // .alignment = 0,
                    .value = e.fields[e.fields.len-1].value
                },
            };
            e.decls = &.{};
        },
        else => @compileError("Can only make alternative types out of Struct or Unions")
    }
    
    return @Type(ti);
}

/// use zig magic to make an equal type to T, but not the same.
/// alternative(SomeType) == alternative(SomeType)
pub fn alternative(comptime T: type) type {
    var ti = @typeInfo(T);
    ti.Struct.fields = ti.Struct.fields ++ .{
       .{
           .name = std.fmt.comptimePrint("{s}", .{@typeName(T)}),
           .type = type,
           .default_value = &T,
           .is_comptime = true,
           .alignment = 0,
       },
    };
    ti.Struct.decls = &.{};
    return @Type(ti);
}

test "alternative" {
    const SomeType = struct {thing:u32};
    const OtherType = struct {thing:u32};
    const Aaa = OtherType;
    try std.testing.expect(Aaa == OtherType);
    try std.testing.expect(SomeType != OtherType);
    try std.testing.expect(SomeType == SomeType);
    try std.testing.expect(OtherType == OtherType);
    try std.testing.expect(SomeType != OtherType);
    const AlmostSomeType = alternative(SomeType);
    try std.testing.expect(AlmostSomeType != SomeType);
    try std.testing.expect(AlmostSomeType == AlmostSomeType);
    try std.testing.expect(AlmostSomeType == alternative(SomeType));
    try std.testing.expect(alternative(SomeType) == alternative(SomeType));
    try std.testing.expect(alternative(SomeType) != alternative(alternative(SomeType)));
    try std.testing.expect(alternative(alternative(alternative(SomeType))) != alternative(alternative(SomeType)));
    const AlternativeVersion = alternative_always(SomeType,opaque{});
    try std.testing.expect(AlternativeVersion == AlternativeVersion);
    try std.testing.expect(alternative_always(SomeType,opaque{}) != alternative_always(SomeType,opaque{}));
    try std.testing.expect(alternative_always(SomeType,opaque{}) != alternative_always(SomeType,opaque{}));
}

const game = struct {

    const Phys = Physics.PhysicalObject;
    const Direction = enum { Left, Right };
    const LookDir = Direction;
    const Pos = Vec2(f32);
    const Hp = i32;
    const GameTags = std.bit_set.IntegerBitSet(32);
    const PlayerId = u8;
    const Tag = enum { IsPlayer, IsTarget };
    const Sprite = usize;
    const Target = struct { entity: ?Entity };
    const CastingInfo = struct {
        is_casting: bool,
        cast_start_frame: usize,
        skill_id: usize,
        target: Entity,

        pub fn finished(self: *const CastingInfo, frame: usize, cast_time: usize) bool {
            std.debug.assert(self.is_casting);
            return frame - self.cast_start_frame >= cast_time;
        }
        
        pub fn cast_cancel(self: *CastingInfo) void {
            self.is_casting = false;
        }

        pub fn cast_start(self: *CastingInfo, frame: usize, skill_id: usize, target: Entity) void {
            self.is_casting = true;
            self.cast_start_frame = frame;
            self.skill_id = skill_id;
            self.target = target;
        }

        pub fn cast_finish(self: *CastingInfo) void {
            self.is_casting = false;
        }

    };
    const Cooldowns = struct {
        
        const Self = @This();
        
        const Cooldown = struct {
            id: usize,
            used_at: usize,
        };
        
        times: [16]Cooldown,

        pub fn init() Cooldowns {
            var cds = Cooldowns {
                .times = undefined
            };
            for (&cds.times) |*cd| cd.id = 0;
            return cds;
        }

        pub fn in_cooldown(self: *Cooldowns, id: usize, frame: usize, cooldown: usize) bool {
            for (&self.times) |cd| if (cd.id == id) return frame - cd.used_at < cooldown;
            return false;
        }

        pub fn get_cooldown(self: *Cooldowns, id: usize) ?*Cooldown {
            for (&self.times) |*cd| if (cd.id == id) return cd;
            return null;
        }

        pub fn start_cooldown(self: *Cooldowns, id: usize, frame: usize) void {
            for (&self.times) |*cd| if (cd.id == id) { cd.used_at = frame; return; };
            for (&self.times) |*cd| if (cd.id == 0) { cd.id = id; cd.used_at = frame; return; };
            unreachable;
        }
    };
    const EntityStatus = enum { idle, combat, reset };
    const Behaviour = enum { slime, knight };
    const ActionTargeted = struct {
        skill: usize,
        target: Entity,
    };
    const ECS = Ecs(.{
        Pos, Hp, LookDir, GameTags, Cooldowns, CastingInfo, Phys, Sprite, EntityStatus, Behaviour, CastingInfo, Target, ActionTargeted, PlayerId
    });

    const Weapon = struct {
        damage: i32,
        speed: i32,
        range: i32,
    };

    const Spell = struct {
        cooldown: i32,
        range: i32,
        damage: i32,
        cast_time: i32,
    };

    const weapons = struct {
        const slime_melee = Weapon {
            .damage = 1,
            .speed = 60,
            .range = 3,
        };
        const unarmed_melee = Weapon {
            .damage = 2,
            .speed = 75,
            .range = 8,
        };
    };

    pub fn ranged_cast(comptime spell: Spell, comptime id: usize) type {
        return struct {
            const self = @This();
            pub fn get_skill_id() usize { return id; }
            pub fn get_cast_time() usize { return spell.cast_time; }
            pub fn get_cd() usize { return spell.cooldown; }
            pub fn get_dispatcher() SkillDispatcher {
                return .{
                    .cast_start = cast_start,
                    .cast_finish = cast_finish,
                    .check = check,
                    .get_cast_time = get_cast_time,
                    .get_cd = get_cd,
                };
            }
            pub fn check(origin: Entity, target: Entity, frame: usize) bool {
                const self_id = get_skill_id();
                var entities = &state.entities;
                var origin_cooldowns = entities.require_component(Cooldowns, origin);
                if (origin_cooldowns.in_cooldown(self_id, frame, spell.cooldown)) {
                    log("cast skill check failed: ability is in cooldown!", .{});
                    return false;
                }
                const origin_casting_info = entities.require_component(CastingInfo, origin);
                if (origin_casting_info.is_casting) {
                    log("cast skill check failed: already casting!", .{});
                    return false;
                }

                const target_pos = entities.require_component(Pos, target);
                const origin_pos = entities.require_component(Pos, origin);
                const origin_look_dir = entities.require_component(LookDir, origin);
                const origin_to_target = target_pos.x - origin_pos.x;
                const origin_to_target_direction = if (origin_to_target >= 0) Direction.Right else Direction.Left;
                const origin_to_target_magnitude = if (origin_to_target >= 0) origin_to_target else -origin_to_target;
                if (origin_to_target_magnitude > spell.range) {
                    log("cast skill check failed: out of range!", .{});
                    return false;
                }
                if (origin_look_dir.* != origin_to_target_direction) {
                    log("cast skill check failed: looking away!", .{});
                    return false;
                }
                log("cast skill check success!", .{});
                return true;
            }
            pub fn cast_start(origin: Entity, target: Entity, frame: usize) bool {
                const self_id = get_skill_id();
                var entities = &state.entities;
                if (entities.try_component(game.ActionTargeted, origin)) |_| {
                    entities.remove_component(ActionTargeted, origin);
                }
                var origin_cooldowns = entities.require_component(Cooldowns, origin);
                std.debug.assert(!origin_cooldowns.in_cooldown(self_id, frame, spell.cooldown));
                var origin_casting_info = entities.require_component(CastingInfo, origin);
                std.debug.assert(!origin_casting_info.is_casting);
                const target_pos = entities.require_component(Pos, target);
                const origin_pos = entities.require_component(Pos, origin);
                const origin_look_dir = entities.require_component(LookDir, origin);

                const origin_to_target = target_pos.x - origin_pos.x;
                const origin_to_target_direction = if (origin_to_target >= 0) Direction.Right else Direction.Left;
                const origin_to_target_magnitude = if (origin_to_target >= 0) origin_to_target else -origin_to_target;

                std.debug.assert(!(origin_to_target_magnitude > spell.range or origin_look_dir.* != origin_to_target_direction));
                origin_casting_info.cast_start(frame, self_id, target);
                log("cast skill started!", .{});
                return true;
            }
            pub fn cast_finish(origin: Entity, target: Entity, frame: usize) bool {
                log("finishing cast", .{});
                const self_id = get_skill_id();
                var entities = &state.entities;
                var origin_cooldowns = entities.require_component(Cooldowns, origin);
                var origin_casting_info = entities.require_component(CastingInfo, origin);
                std.debug.assert(origin_casting_info.is_casting);
                const target_pos = entities.require_component(Pos, target);
                const target_hp = entities.require_component(Hp, target);
                const origin_pos = entities.require_component(Pos, origin);
                const origin_look_dir = entities.require_component(LookDir, origin);
                const origin_tags = entities.require_component(GameTags, origin);
                const is_player = origin_tags.isSet(@intFromEnum(Tag.IsPlayer));

                const origin_to_target = target_pos.x - origin_pos.x;
                const origin_to_target_magnitude = if (origin_to_target >= 0) origin_to_target else -origin_to_target;
                if (origin_to_target_magnitude > spell.range) {
                    log("cast finish failed: out of range!", .{});
                    return false;
                }

                const origin_to_target_direction = if (origin_to_target >= 0) Direction.Right else Direction.Left;
                if (origin_look_dir.* != origin_to_target_direction) {
                    log("cast finish failed: looking away!", .{});
                    return false;
                }

                origin_cooldowns.start_cooldown(self_id, frame);
                target_hp.* -= spell.damage;
                if (target_hp.* <= 0) {
                    entities.delete(target);
                    if (is_player) {
                        // TODO exp, etc
                    }
                }
                origin_casting_info.cast_finish();
                log("cast skill finished! (damage: {})", .{spell.damage});
                return true;
            }
        };
    }

    pub fn melee(comptime weapon: Weapon, comptime id: usize) type {
        return struct {
            pub fn get_skill_id() usize { return id; }
            pub fn get_cd() usize { return weapon.speed; }
            pub fn get_dispatcher() SkillDispatcher {
                return .{
                    .do = do,
                    .check = check,
                    .get_cd = get_cd,
                };
            }
            pub fn check(origin: Entity, target: Entity, frame: usize) bool {
                const self_id = get_skill_id();
                var entities = &state.entities;
                var origin_cooldowns = entities.require_component(Cooldowns, origin);
                if (origin_cooldowns.in_cooldown(self_id, frame, weapon.speed)) {
                    log("melee skill check failed: ability is in cooldown!", .{});
                    return false;
                }
                const target_pos = entities.require_component(Pos, target);
                const origin_pos = entities.require_component(Pos, origin);
                const origin_look_dir = entities.require_component(LookDir, origin);
                const origin_to_target = target_pos.x - origin_pos.x;
                const origin_to_target_direction = if (origin_to_target >= 0) Direction.Right else Direction.Left;
                const origin_to_target_magnitude = if (origin_to_target >= 0) origin_to_target else -origin_to_target;
                const is_in_range = origin_to_target_magnitude <= weapon.range;
                if (!is_in_range) {
                    log("melee skill check failed: not in range! {d:0>4}", .{origin_to_target_magnitude});
                    return false;
                }
                const is_in_front = origin_look_dir.* == origin_to_target_direction;
                if (!is_in_front) {
                    log("melee skill check failed: enemy is behind!", .{});
                    return false;
                }
                log("melee skill check success!",.{});
                return true;
            }
            pub fn do(origin: Entity, target: Entity, frame: usize) bool {
                const self_id = get_skill_id();
                const entities = &state.entities;
                const target_hp = entities.require_component(Hp, target);
                const target_pos = entities.require_component(Pos, target);
                const origin_pos = entities.require_component(Pos, origin);
                const origin_look_dir = entities.require_component(LookDir, origin);
                var origin_casting_info = entities.require_component(CastingInfo, origin);
                var origin_cooldowns = entities.require_component(Cooldowns, origin);
                var origin_tags = entities.require_component(GameTags, origin);
                if (entities.try_component(game.ActionTargeted, origin)) |_| entities.remove_component(ActionTargeted, origin);
                const is_player = origin_tags.isSet(@intFromEnum(Tag.IsPlayer));
                std.debug.assert(!origin_cooldowns.in_cooldown(self_id, frame, weapon.speed));
                const origin_to_target = target_pos.x - origin_pos.x;
                const origin_to_target_direction = if (origin_to_target >= 0) Direction.Right else Direction.Left;
                const origin_to_target_magnitude = if (origin_to_target >= 0) origin_to_target else -origin_to_target;
                std.debug.assert(!(origin_to_target_magnitude > weapon.range and origin_look_dir.* != origin_to_target_direction));
                // TODO system_damage_number(weapon.damage, target_pos);
                if (origin_casting_info.is_casting) {
                    log("melee skill cancelled casting {}", .{origin_casting_info.skill_id});
                    origin_casting_info.cast_cancel();
                }
                origin_cooldowns.start_cooldown(self_id, frame);
                target_hp.* -= weapon.damage;
                if (target_hp.* <= 0) {
                    entities.delete(target);
                    if (is_player) {
                        // TODO exp, etc
                    }
                }
                log("melee skill done! (damage: {})", .{weapon.damage});
                return true;
            }
        };
    }

    // TODO spawn entities whose AI is to walk to each other till skills.melee(weapons.slime_melee).check(), and then do the skill as soon as possible
    // TODO if HP is below 20 then make the slimes walk away
    // TODO make any "casted" skill that sets the CastingInfo and can then be cancelled by kick
    // TODO make "global cooldown" for player

    const SkillDispatcher = struct {
        check: ?*const fn (origin: Entity, target: Entity, frame: usize) bool = null,
        cast_start: ?*const fn (origin: Entity, target: Entity, frame: usize) bool = null,
        do: ?*const fn (origin: Entity, target: Entity, frame: usize) bool = null,
        cast_finish: ?*const fn (origin: Entity, target: Entity, frame: usize) bool = null,
        get_cast_time: ?*const fn () usize = null,
        get_cd: ?*const fn () usize = null,
    };

    fn register_entry(comptime skill: type) registry_entry {
        return .{
            .skill_id = skill.get_skill_id() ,
            .dispatcher = skill.get_dispatcher(),
        };
    }

    const registry_entry = struct { skill_id: usize, dispatcher: SkillDispatcher };
    const skill_registry = struct {
        var all_skills = [_] registry_entry {
            register_entry(skills.unarmed_melee),
            register_entry(skills.kick),
            register_entry(skills.slime_melee),
            register_entry(skills.fireball),
        };
    };

    pub fn get_skill(skill_id: usize) SkillDispatcher {
        for (&skill_registry.all_skills) |o| if (o.skill_id == skill_id) return o.dispatcher;
        unreachable;
    }
    
    const skill_type = enum (usize) {
        kick = 1,
        unarmed_melee,
        slime_melee,
        fireball
    };
    
    const skills = struct {
        const kick = struct {
            const cooldown = 60*10;
            const range = 5;
            const self = @This();
            pub fn get_skill_id() usize { return @intFromEnum(skill_type.kick); }
            pub fn get_cd() usize { return cooldown; }
            pub fn get_dispatcher() SkillDispatcher {
                return .{
                    .do = do,
                    .check = check,
                    .get_cd = get_cd,
                };
            }
            pub fn check(origin: Entity, target: Entity, frame: usize) bool {
                const self_id = get_skill_id();
                const entities = &state.entities;
                var origin_cooldowns = entities.require_component(Cooldowns, origin);
                if (origin_cooldowns.in_cooldown(self_id, frame, cooldown)) return false;
                const target_pos = entities.require_component(Pos, target);
                const origin_pos = entities.require_component(Pos, origin);
                const origin_look_dir = entities.require_component(LookDir, origin);
                const origin_to_target = target_pos.x - origin_pos.x;
                const origin_to_target_direction = if (origin_to_target >= 0) Direction.Right else Direction.Left;
                const origin_to_target_magnitude = if (origin_to_target >= 0) origin_to_target else -origin_to_target;
                return (origin_to_target_magnitude <= range and origin_look_dir.* == origin_to_target_direction) ;
            }
            pub fn do(origin: Entity, target: Entity, frame: usize) bool {
                const self_id = get_skill_id();
                const entities = &state.entities;
                const target_pos = entities.require_component(Pos, target);
                const target_casting_info = entities.require_component(CastingInfo, target);
                const origin_pos = entities.require_component(Pos, origin);
                const origin_look_dir = entities.require_component(LookDir, origin);
                entities.remove_component(ActionTargeted, origin);
                var origin_cooldowns = entities.require_component(Cooldowns, origin);
                std.debug.assert(!origin_cooldowns.in_cooldown(self_id, frame, cooldown));
                const origin_to_target = target_pos.x - origin_pos.x;
                const origin_to_target_direction = if (origin_to_target >= 0) Direction.Right else Direction.Left;
                const origin_to_target_magnitude = if (origin_to_target >= 0) origin_to_target else -origin_to_target;
                if (origin_to_target_magnitude <= range and origin_look_dir.* == origin_to_target_direction) {
                    origin_cooldowns.start_cooldown(self_id, frame);
                    target_casting_info.cast_cancel();
                }
                log("kicked!", .{});
                return true;
            }
        };
        const fireball = ranged_cast(.{
            .cooldown = 60*7,
            .range = 5*8,
            .damage = 12,
            .cast_time = 60 + 30
        }, @intFromEnum(skill_type.fireball));
        const slime_melee = melee(weapons.slime_melee, @intFromEnum(skill_type.slime_melee));
        const unarmed_melee = melee(weapons.unarmed_melee, @intFromEnum(skill_type.unarmed_melee));
    };

    pub fn entities_update_physics() void {
        const entities = &state.entities;

        var it = entities.iterator(.{Pos,Phys});
        while (it.next()) |e| {
            const pos = entities.require_component(Pos, e);
            const phys = entities.require_component(Phys, e);
            _ = Physics.apply(phys);
            pos.* = Physics.calculate_real_pos(phys.physical_pos);
        }
    }

    pub const palette = [16]u24 {
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

    pub fn slime_spawn(position: Vec2(f32), frame: usize) void {
        const entities = &state.entities;
        const e = entities.new_entity();
        
        const pos = entities.set_component(Pos, e);
        const hp = entities.set_component(Hp, e);
        const look_dir = entities.set_component(LookDir, e);
        const tags = entities.set_component(GameTags, e);
        const cooldowns = entities.set_component(Cooldowns, e);
        const sprite = entities.set_component(Sprite, e);
        const casting = entities.set_component(CastingInfo, e);
        const phys = entities.set_component(Phys, e);
        
        pos.* = position;
        phys.* = Phys.from(position, 0.3);
        look_dir.* = .Right;
        hp.* = 35;
        tags.mask = 0;
        tags.set(@intFromEnum(Tag.IsTarget));
        sprite.* = 66;
        for (&cooldowns.times) |*cd| cd.* = .{.id = 0, .used_at = 0};
        casting.is_casting = false;

        _ = frame;
    }

    pub fn player_spawn(player_id: u8, position: Vec2(f32), frame: usize) void {
        const entities = &state.entities;
        const e = entities.new_entity();
        
        const pos = entities.set_component(Pos, e);
        const hp = entities.set_component(Hp, e);
        const look_dir = entities.set_component(LookDir, e);
        const tags = entities.set_component(GameTags, e);
        const cooldowns = entities.set_component(Cooldowns, e);
        const casting = entities.set_component(CastingInfo, e);
        const sprite = entities.set_component(Sprite, e);
        const phys = entities.set_component(Phys, e);
        const target = entities.set_component(Target, e);
        const id = entities.set_component(PlayerId, e);
        
        pos.* = position;
        phys.* = Phys.from(position, 0.7);
        look_dir.* = .Right;
        hp.* = 100;
        tags.mask = 0;
        tags.set(@intFromEnum(Tag.IsPlayer));
        sprite.* = 64;
        target.entity = null;
        for (&cooldowns.times) |*cd| cd.* = .{.id = 0, .used_at = 0};
        casting.is_casting = false;
        id.* = player_id;

        _ = frame;
    }

    // pub fn slime(e: Entity, p: Entity) void {
    //     const e_status = entities.require_component(EntityStatus, e);
    //     switch (e_status) {
    //         .idle => {

    //         },
    //         .combat => {

    //         },
    //     }
    //     const p_pos = entities.require_component(Pos, p);
    //     const e_pos = entities.require_component(Pos, e);

    // }


};

pub fn ScrollingLog(comptime memory_len: usize) type {
    return struct {
        const Self = @This();
        
        count: usize,
        first: *align(1) usize,
        previous: *align(1) usize,
        memory: [memory_len]u8,

        pub fn init(self: *Self) void {
            self.memory = undefined;
            for (&self.memory) |*b| b.* = 0;
            self.previous = @ptrCast(&self.memory);
            self.first = @ptrCast(&self.memory);
            self.count = 0;
        }
        
        fn ptr(pointer: anytype) usize {
            return @intFromPtr(pointer);
        }
        
        pub fn _log_debug_visualization(self: *Self) void {
            var b: [memory_len*2]u8 = [1]u8{'#'} ** (memory_len*2);
            
            var it = self.iterator();
            while (it.next()) |item| {
                const index = item.ptr - 8 - &self.memory;
                _ = std.fmt.bufPrint(b[index..], "{d:0>8}", .{item.len}) catch @panic("");
                _ = std.fmt.bufPrint(b[index+8..], "{s}", .{item}) catch @panic("");
            }
            
            for (&self.memory, 0..) |*c, i| {
                b[memory_len+i] = ' ';
                if (ptr(c) == ptr(self.first)) b[memory_len+i] = 'f';
                if (ptr(c) == ptr(self.previous)) b[memory_len+i] = 'p';
            }
            std.log.debug("1|{s}", .{b[0..memory_len]});
            std.log.debug("2|{s}", .{b[memory_len..]});
        }

        pub fn append(self: *Self, message: []const u8) void {
            
            if (message.len == 0) return;
            if (message.len + @sizeOf(usize) > memory_len) @panic("message is too big!");

            const memory_end = ptr(&self.memory) + self.memory.len;

            const prev_ptr = self.previous;
            const prev_len = prev_ptr.*;
            const prev_str_ptr = ptr(prev_ptr) + @sizeOf(usize);
            
            if (prev_len == 0) {
                // This only ever happens on the first `append` call
                const message_len_storage: *align(1) usize = @ptrCast(&self.memory);
                message_len_storage.* = message.len;
                self.count = 1;
                const owned_message = self.memory[@sizeOf(usize) .. @sizeOf(usize) + message.len];
                for (owned_message, 0..) |*c, i| c.* = message[i];
                return;
            }

            var curr_ptr = prev_str_ptr + prev_len;
            var curr_len = message.len;
            var curr_str_ptr = curr_ptr + @sizeOf(usize);
            
            // if there isn't enough space for this message without divinding it
            // then just clear everything to the right of the buffer and start again from 0
            if (curr_str_ptr + curr_len > memory_end) {
                
                var it = self.iterator();
                while (it.next()) |item| if (ptr(item.ptr) >= curr_ptr) {
                    self.count -= 1;
                };

                // but there is enough space for a length value, then make it zero to make it clear we wrapped
                if (curr_ptr + @sizeOf(usize) <= memory_end) {
                    const message_len_storage: *align(1) usize = @ptrFromInt(curr_ptr);
                    message_len_storage.* = 0;
                }

                self.first = @ptrCast(&self.memory);
                curr_ptr = @intFromPtr(&self.memory);
                curr_len = message.len;
                curr_str_ptr = curr_ptr + @sizeOf(usize);

            }
            
            // remove as many messages as we need to in order to make space for the new message
            // (this `while` is basically moving self.first to the right in the buffer until there is no need to move it any more)
            while (curr_ptr <= ptr(self.first) and curr_str_ptr + curr_len > ptr(self.first)) {

                // while overriding messages, we reached the last message we appended (aka `previous`) meaning we overrided EVERY message
                if (self.first == self.previous) {
                    self.first = @ptrCast(&self.memory);
                    self.count = 0;
                    break;
                }

                // on every iteration of this `while`, `first` will point to the next message which is about to be overriden
                const first_ptr = self.first;
                const first_len = first_ptr.*;
                const first_str_ptr = ptr(first_ptr) + @sizeOf(usize);

                // space left after we override this message
                const space_left = memory_end - ptr(first_ptr);

                // If there is at least 1 more message (after the one about to be overriden)...
                if (space_left >= @sizeOf(usize) and first_len != 0) {
                    
                    const space_left_again = memory_end - (first_str_ptr + first_len);
                    // there is not enough for 2...
                    if (space_left_again <= @sizeOf(usize)) {
                        self.count -= 1;
                        self.first = @ptrCast(&self.memory);
                        break;
                    }
                    // there is potentially even more messages...
                    else {
                        self.count -= 1;
                        self.first = @ptrFromInt(first_str_ptr + first_len);
                        if (self.first.* == 0 or self.count == 0) {
                            self.first = @ptrCast(&self.memory);
                            break;
                        }
                    }

                }
                else {
                    // This means that either there wasnt space for a message here at all,
                    // or that the space was just unused because on a previous append the space wasn't big enough
                    self.first = @ptrCast(&self.memory);
                    break;
                }

            }

            const message_len_storage: *align(1) usize = @ptrFromInt(curr_ptr);
            message_len_storage.* = message.len;
            const index_message_start = curr_str_ptr - ptr(&self.memory);
            self.count += 1;
            const owned_message = self.memory[index_message_start .. index_message_start + message.len];
            for (owned_message, 0..) |*c, i| c.* = message[i];
            std.debug.assert(owned_message.len == message.len);
            std.debug.assert(std.mem.eql(u8, owned_message, message));

            self.previous = @ptrFromInt(curr_ptr);
        }
        
        const Iterator = struct {
            
            self: *Self,
            current: *align(1) usize,
            done: bool,
            
            pub fn next(self: *Iterator) ?[]u8 {
                if (self.done) return null;
                // get string
                const curr_ptr = self.current;
                const curr_len = curr_ptr.*;
                const curr_str_ptr = ptr(curr_ptr) + @sizeOf(usize);
                const str_start_index = curr_str_ptr - ptr(&self.self.memory);
                const str = self.self.memory[str_start_index .. str_start_index + curr_len];
                if (self.current == self.self.previous) {
                    self.done = true;
                    return str;
                }
                // calc next
                const memory_end = ptr(&self.self.memory) + self.self.memory.len;
                const space_left = memory_end - (curr_str_ptr + curr_len);
                if (space_left <= @sizeOf(usize)) {
                    self.current = @ptrCast(&self.self.memory);
                }
                else {
                    self.current = @ptrFromInt(curr_str_ptr + curr_len);
                    if (self.current.* == 0) self.current = @ptrCast(&self.self.memory);
                }
                return str;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return .{
                .self = self,
                .current = self.first,
                .done = false,
            };
        }

    };
}
const ImmediateModeGui = imgui.ImmediateModeGui(.{
    .layout = .{
        .char_height = 5*1,
        .char_width = 4*1,
        .widget_margin  = 1,
        .widget_padding = 1,
        .container_padding = 1,
    },
});

const imgui = struct {

    const LayoutConfig = struct {
        char_height: i32,
        char_width: i32,
        widget_margin: i32,
        widget_padding: i32,
        container_padding: i32,
    };

    const Config = struct {
        layout: LayoutConfig,
    };

    const Io = struct {
        mouse_pos: Vec2(i32) = Vec2(i32).from(0, 0),
        mouse_down: bool = false,
    };

    const Style = enum {
        base,
        accent,
        highlight,
        special,
    };

    const MouseStateType = enum {
        free,
        press,
        drag,
        release
    };

    const MouseEvent = struct {
        st: MouseStateType = .free,
        relevant_id: ?u64 = 0,
        pos: Vec2(i32) = Vec2(i32).from(0,0)
    };

    fn ImmediateModeGui(comptime config: Config) type {
        return struct {
        
            const Self = @This();

            const DrawCallType = enum {
                shape,
                text
            };

            const DrawCall = struct {
                draw_call_type: DrawCallType,
                index: usize,
            };

            pub const DrawCallText = struct {
                text: struct {usize, usize},
                pos: Vec2(f32),
                style: Style,
            };

            pub const DrawCallShape = struct {
                bounding_box: BoundingBox(f32),
                style: Style,
            };
            
            const DrawCallBigBuffer = struct {
                allocator: std.mem.Allocator,
                text: std.ArrayList(DrawCallText),
                shape: std.ArrayList(DrawCallShape),
                draw_call_lists: std.ArrayList(std.ArrayList(DrawCall)),
                draw_call_list_indices: [ContainerCountMax]?usize,

                fn init(allocator: std.mem.Allocator) DrawCallBigBuffer {
                    var res = DrawCallBigBuffer {
                        .allocator = allocator,
                        .text = std.ArrayList(DrawCallText).init(allocator),
                        .shape = std.ArrayList(DrawCallShape).init(allocator),
                        .draw_call_lists = std.ArrayList(std.ArrayList(DrawCall)).init(allocator),
                        .draw_call_list_indices = undefined,
                    };
                    for (&res.draw_call_list_indices) |*value| value.* = null;
                    return res;
                }

                pub fn render_text(self: *DrawCallBigBuffer, container_id: u64, str: struct {usize, usize}, position: Vec2(i32), style: Style) !void {
                    if (self.draw_call_list_indices[container_id] == null) {
                        const list_index = self.draw_call_lists.items.len;
                        self.draw_call_list_indices[container_id] = list_index;
                        const draw_call_list = std.ArrayList(DrawCall).init(self.allocator);
                        try self.draw_call_lists.append(draw_call_list);
                    }
                    const list_index = self.draw_call_list_indices[container_id].?;
                    var draw_call_list = &self.draw_call_lists.items[list_index];
                    const call_index = self.text.items.len;
                    try draw_call_list.append(.{
                        .draw_call_type = .text,
                        .index = call_index,
                    });
                    try self.text.append(.{
                        .text = str, .style = style, .pos = position.to(f32)
                    });
                }

                pub fn render_shape(self: *DrawCallBigBuffer, container_id: u64, bounding_box: BoundingBox(i32), style: Style) !void {
                    if (self.draw_call_list_indices[container_id] == null) {
                        const list_index = self.draw_call_lists.items.len;
                        self.draw_call_list_indices[container_id] = list_index;
                        const draw_call_list = std.ArrayList(DrawCall).init(self.allocator);
                        try self.draw_call_lists.append(draw_call_list);
                    }
                    const list_index = self.draw_call_list_indices[container_id].?;
                    var draw_call_list = &self.draw_call_lists.items[list_index];
                    const call_index = self.shape.items.len;
                    try draw_call_list.append(.{
                        .draw_call_type = .shape,
                        .index = call_index,
                    });
                    try self.shape.append(.{
                        .bounding_box = bounding_box.to(f32), .style = style,
                    });
                }

            };

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
                    const text_position = Vec2(i32).from(
                        self.bounding_box_free.left + config.layout.container_padding,
                        self.bounding_box_free.top - required_vetical_space + config.layout.widget_margin,
                    );
                    const out = self.bounding_box_free.shrink(.top, required_vetical_space);
                    const header_bb: BoundingBox(i32) = out.leftover;
                    const bounding_box_free_updated = out.shrinked;

                    // make a copy of the string to be printed
                    
                    const len = std.fmt.count(fmt, args);
                    const index_into_string_data = self.builder.string_data.items.len;
                    const slice = try self.builder.string_data.addManyAsSlice(len);
                    _ = std.fmt.bufPrint(slice, fmt, args) catch unreachable;
                    
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
                    const id = self.persistent.unique_identifier;
                    if (container_offset) |offset| {
                        self.bounding_box_free = bounding_box_free_updated.offset(offset);
                        self.persistent.bounding_box = self.persistent.bounding_box.offset(offset);
                        try self.builder.draw_call_data.render_shape(id, header_bb.offset(offset), .accent);
                        try self.builder.draw_call_data.render_text(id, .{index_into_string_data, len}, text_position.add(offset), .special);
                    }
                    else {
                        self.bounding_box_free = bounding_box_free_updated;
                        try self.builder.draw_call_data.render_shape(id, header_bb, if (is_hovering) .highlight else .special);
                        try self.builder.draw_call_data.render_text(id, .{index_into_string_data, len}, text_position, .special);
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

                    const text_position = Vec2(i32).from(
                        self.bounding_box_free.left + config.layout.container_padding,
                        self.bounding_box_free.top - required_vetical_space + config.layout.widget_margin,
                    );
                    self.bounding_box_free = self.bounding_box_free.shrink(.top, required_vetical_space).shrinked;

                    // make a copy of the string to be printed
                    const len = std.fmt.count(fmt, args);
                    const index_into_string_data = self.builder.string_data.items.len;
                    const slice = try self.builder.string_data.addManyAsSlice(len);
                    _ = std.fmt.bufPrint(slice, fmt, args) catch unreachable;

                    const id = self.persistent.unique_identifier;
                    try self.builder.draw_call_data.render_text(id, .{index_into_string_data, len}, text_position, .special);
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
                    const text_position = Vec2(i32).from(
                        self.bounding_box_free.left + config.layout.container_padding + config.layout.widget_margin + config.layout.widget_padding,
                        self.bounding_box_free.top - space_required_vertical + config.layout.widget_margin + config.layout.widget_padding,
                    );
                    const out = self.bounding_box_free.shrink(.top, space_required_vertical);
                    self.bounding_box_free = out.shrinked;
                    const iner_bb: BoundingBox(i32) = out.leftover.get_inner_bb_with_padding(config.layout.widget_margin);
                    const button_bb: BoundingBox(i32) = iner_bb.shrink(.right, space_available_horizontal - space_required_horizontal).shrinked;

                    // make a copy of the string to be printed
                    const index_into_string_data = self.builder.string_data.items.len;
                    const slice = try self.builder.string_data.addManyAsSlice(len);
                    _ = std.fmt.bufPrint(slice, fmt, args) catch unreachable;

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
                    const id = self.persistent.unique_identifier;
                    try self.builder.draw_call_data.render_shape(id, button_bb, button_style);
                    try self.builder.draw_call_data.render_text(id, .{index_into_string_data, len}, text_position, .base);

                    return button_state == .clicked;
                }

            };

            const UiBuilder = struct {
                parent_ui: *Self,
                /// reset on prepare_frame
                string_data: std.ArrayList(u8),
                /// set on prepare_frame
                mouse_event: ?MouseEvent,
                io_previous: Io,
                io: Io,
                container_stack: std.BoundedArray(u64, ContainerCountMax),
                /// Each container has its own draw call buffer
                draw_call_data: DrawCallBigBuffer,

                pub fn begin(self: *UiBuilder, id: []const u8, bounding_box: BoundingBox(i32), comptime is_window: bool) !Container {
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

                                    // put the container at the top most layer if it is clicked
                                    if (is_window and me.st == .press) for (ui.containers_order.slice(), 0..) |unique_id, position| {
                                        if (unique_id == container_persistent.unique_identifier) {
                                            const top_most_index = ui.containers_order.len - 1;
                                            const current_index = position;
                                            const previous_top_most_container = ui.containers_order.buffer[top_most_index];
                                            ui.containers_order.buffer[top_most_index] = container_persistent.unique_identifier;
                                            ui.containers_order.buffer[current_index] = previous_top_most_container;
                                            break;
                                        }
                                    };

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
                    const container = Container {
                        .builder = self,
                        .persistent = container_persistent,
                        .bounding_box_free = container_persistent.bounding_box,
                        .mouse_event = mouse_event_to_pass,
                    };
                    const style: Style = if (ui.containers_order.slice()[ui.containers_order.len-1] == container.persistent.unique_identifier) .highlight else .base;
                    if (is_window) try container.builder.draw_call_data.render_shape(container.persistent.unique_identifier, container.persistent.bounding_box, style);
                    return container;
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
            io_previous: Io,
            
            pub fn init(self: *Self) void {
                for (&self.containers) |*c| c.* = .{};
                self.containers_order = .{};
                self.id_active = null;
                self.io_previous = .{};
            }

            pub fn prepare_frame(self: *Self, allocator: std.mem.Allocator, io: Io) UiBuilder {
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
                    .draw_call_data = DrawCallBigBuffer.init(allocator)
                };
                
                // TODO since we know the positions and sizes of all the containers and their layers in the previous frame, we can calculate which container the mouse is over of right now
            }
            
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

        };

    }

};

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

const scalers = struct {
    pub fn _upscale_u32_known_scale_asm(src_data: *u32, dst_data: *u32, src_width: u32, src_height: u32, comptime scaling_factor: u32) void {
        // ; input
        // rd32| = src_width
        // ra32| = src_height
        // rc64| = src_data
        // rb64| = dst_data
        // 
        // ; assembly
        // ; NOTE this might not be 100% accurate with the actual code below, but it mostly is an accurate
        // ; representation of the assembly below...
        // r832|src_width = rd32|src_width
        // r332|size_of_src_row_in_bytes = r832|src_width * 4
        // r432|square_of_scaling_factor = comptime scaling_factor*scaling_factor
        // r432|size_of_dst_row_in_bytes *= r332|size_of_src_row_in_bytes
        // r064|src_row_end = rc64|src_data
        // r964|dst_row_end = rb64|dst_data
        // ra32|src_data_len *=  rd32|src_width
        // rd64|src_data_end = rc64|src_data + (ra32|src_data_len * 4)
        // while (rc64|src_data != rd64|src_data_end) {
        //     ; Calculate the address of the first pixel of the next row in src_data
        //     r064|src_row_end += r332|size_of_src_row_in_bytes
        //     ; Calculate the address of the first pixel of the next row in dst_data
        //     r964|dst_row_end += r432|size_of_dst_row_in_bytes
        //     while (rb64|dst_data != r964|dst_row_end) {
        //         push rc64|src_data
        //         while (rc64|src_data != r064|src_row_end) {
        //             r132|pixel = *rc64|src_data
        //             ; TODO look into SIMD to replace this whole loop
        //             comptime inline for(0..scaling_factor) |_| {
        //                 *(rb64|dst_data) = r132|pixel
        //                 rb64|dst_data += 4
        //             }
        //             rc64|src_data += 4
        //         }
        //         pop rc64|src_data
        //     }
        //     rc64|src_data = r064|src_row_end
        // }
        
        const comptime_generated_asm_2 = comptime blk: {
            var comptime_string: []const u8 = "";
            for  (0..scaling_factor) |_| {
                // Tried also this but didnt make any difference as far as I can tell
                // |mov %%r11d, 4(%%rbx)
                // |mov %%r11d, 8(%%rbx)
                // |mov %%r11d, 12(%%rbx)
                // |mov %%r11d, 14(%%rbx)
                // |addq $16, %%rbx
                comptime_string = comptime_string ++
                    \\    mov %%r11d, (%%rbx)
                    \\    addq $4, %%rbx
                    \\
                ;
            }
            break :blk comptime_string;
        };

        const comptime_generated_asm_1 = std.fmt.comptimePrint(
            \\    mov ${}, %%r14d
            \\
            , .{scaling_factor*scaling_factor}
        );
        
        // This is the code that copies a pixel from scale_factor x pixels of dst
        const loop_core = if (scaling_factor == 4)
            // SIMD version when scaling factor is 4
            // TODO should probably implement the same for scaling factor 2 and 8
            // TODO additionally I could copy more than 1 pixel: Load p and p+1, fill ymm 256 bit register and write it to memory
            // although it would need some extra checks probably? Not really needing the extra speed now anyway lol
            \\    vbroadcastss (%%rcx), %%xmm0
            \\    movaps %%xmm0, (%%rbx)
            \\    addq $16, %%rbx
            \\
            else
            \\    mov (%%rcx), %%r11d
            \\
            ++ comptime_generated_asm_2 ++
            \\
        ;

        // TODO I probably should reset flags and stuff that I'm not checking? I actually dont know...
        asm volatile (
            \\    mov %%edx, %%r8d
            \\    imul $4, %%r8d, %%r13d
            \\
            ++ comptime_generated_asm_1 ++
            \\    imul %%r13d, %%r14d
            \\    mov %%rcx, %%r10
            \\    mov %%rbx, %%r9
            \\    mul %%edx
            \\    lea (%%rcx,%%rax,4), %%rdx
            \\._outer:
            \\    cmp %%rcx, %%rdx
            \\    je ._outer_end
            \\    add %%r13, %r10
            \\    add %%r14, %r9
            \\._outer_2:
            \\    cmp %%rbx, %%r9
            \\    je ._outer_2_end
            \\    push %%rcx
            \\._inner:
            \\    cmp %%rcx, %%r10
            \\    je ._inner_end
            \\
            ++ loop_core ++
            \\    addq $4, %%rcx
            \\    jmp ._inner
            \\._inner_end:
            \\    pop %%rcx
            \\    jmp ._outer_2
            \\._outer_2_end:
            \\    mov %%r10, %%rcx
            \\    jmp ._outer
            \\._outer_end:
            \\
            :: [dst_data]"{rbx}"(dst_data),
            [src_data]"{rcx}"(src_data),
            [src_width]"{edx}"(src_width),
            [src_height]"{eax}"(src_height),
            : "memory"
        );
    }
    pub fn _upscale_u32_known_scale(_src_data: [*]u32, _dst_data: [*]u32, src_width: u32, src_height: u32, comptime scaling_factor: u32) void {
        const square_of_scaling_factor: u32 = comptime scaling_factor*scaling_factor;
        // by default input parameters of functions are const
        var dst_data = _dst_data;
        var src_data = _src_data;

        const size_of_dst_row: u32 = square_of_scaling_factor * src_width;
        const src_data_end = src_data + src_width * src_height;
        var src_row_end = src_data;
        var dst_row_end = dst_data;
        while (src_data != src_data_end) {
            src_row_end += src_width;
            dst_row_end += size_of_dst_row;
            while (dst_data != dst_row_end) {
                const saved_src_data = src_data;
                while (src_data != src_row_end) {
                    const pixel = src_data[0];
                    inline for(0..scaling_factor) |i| {
                        dst_data[i] = pixel;
                    }
                    dst_data += scaling_factor;
                    src_data += 1;
                }
                src_data = saved_src_data;
            }
            src_data = src_row_end;
        }
    }
    pub fn upscale_u32_known_scale_asm(comptime pixel_type: type, src: Buffer2D(pixel_type), dst: Buffer2D(pixel_type), comptime scale: u32) void {
        std.debug.assert(@sizeOf(pixel_type) == @sizeOf(u32));
        _upscale_u32_known_scale_asm(@ptrCast(@alignCast(src.data)), @ptrCast(@alignCast(dst.data)), @intCast(src.width), @intCast(src.height), scale);
    }
    pub fn upscale_u32_known_scale(comptime pixel_type: type, src: Buffer2D(pixel_type), dst: Buffer2D(pixel_type), comptime scale: u32) void {
        std.debug.assert(@sizeOf(pixel_type) == @sizeOf(u32));
        _upscale_u32_known_scale(@ptrCast(@alignCast(src.data)), @ptrCast(@alignCast(dst.data)), @intCast(src.width), @intCast(src.height), scale);
    }
    pub fn upscale(comptime pixel_type: type, src: Buffer2D(pixel_type), dst: Buffer2D(pixel_type), comptime scale: u32) void {
        if (builtin.os.tag == .windows and builtin.mode == .Debug) upscale_u32_known_scale_asm(platform.OutPixelType, src, dst, scale)
        else upscale_u32_known_scale(platform.OutPixelType, src, dst, scale);
    }
};

