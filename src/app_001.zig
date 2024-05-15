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
const Resources = @import("app_003.zig").Resources;
const Renderer = @import("app_003.zig").Renderer;
const Sound = wav.Sound;
const text_size_multiplier = 1;
const TextRenderer = @import("text.zig").TextRenderer(platform.OutPixelType, 1024, text_size_multiplier);

const windows = @import("windows.zig");
const wasm = @import("wasm.zig");
const platform = if (builtin.os.tag == .windows) windows else wasm;

const Application = platform.Application(.{
    .init = init,
    .update = update,
    .dimension_scale = 1,
    .desired_width = 240*4,
    .desired_height = 136*4,
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

// TODO damage numbers
// TODO exclamation mark when slimes start attacking
// TODO transparent overlay on poison pool
// TODO trigger areas
// TODO tools

const State = struct {
    game_render_target: Buffer2D(platform.OutPixelType),
    entities: EntitySystem,
    level_background: BoundingBox(usize),
    player: Player,
    camera: Camera,
    animations_in_place: AnimationSystem,
    particles: Particles,
    rng_engine: std.rand.DefaultPrng,
    random: std.rand.Random,
    doors: std.ArrayList(Door),
    particle_emitters: std.ArrayList(ParticleEmitter),
    texts: []const *const Assets.StaticTextDescriptor,
    entities_damage_dealers: HitboxSystem,
    player_damage_dealers: HitboxSystem,
    debug: bool,
    resources: Resources,
    resource_file_name: []const u8,
    audio_tracks: [16] ?AudioTrack,
    sound_library: [@typeInfo(sounds).Enum.fields.len]wav.Sound,
    play_background_music: bool,
    ui: ImmediateModeGui,
};

var state: State = undefined;

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    state.entities = try EntitySystem.init_capacity(allocator, 16);
    state.player = Player.init(0);
    state.camera = Camera.init(Vector3f { .x = 0, .y = 0, .z = 0 });
    state.animations_in_place = try AnimationSystem.init_capacity(allocator, 1024);
    state.particles = try Particles.init_capacity(allocator, 1024);
    state.rng_engine = std.rand.DefaultPrng.init(@bitCast(platform.timestamp()));
    state.random = state.rng_engine.random();
    state.entities_damage_dealers = try HitboxSystem.init_capacity(allocator, 64);
    state.player_damage_dealers = try HitboxSystem.init_capacity(allocator, 64);
    state.doors = try std.ArrayList(Door).initCapacity(allocator, 32); // doors are set on load_level
    state.particle_emitters = try std.ArrayList(ParticleEmitter).initCapacity(allocator, 64); // doors are set on load_level
    state.texts = undefined; // texts are set on load_level
    state.debug = true;
    state.resource_file_name = "res/resources.bin";
    state.resources = try Resources.init(allocator);
    state.game_render_target = Buffer2D(platform.OutPixelType).from(try allocator.alloc(platform.OutPixelType, 240*136), 240);
    state.play_background_music = true;
    ImmediateModeGui.init(&state.ui);
    
    // audio stuff
    {
        for (&state.audio_tracks) |*at| at.* = null;
        for (wav_files, 0..) |wav_file, i| {
            // TODO make an scratch allocator for things like this since these are not necessary to be kept
            const bytes = Application.read_file_sync(allocator, wav_file) catch continue;
            const sound = try wav.from_bytes(allocator, bytes);
            // TODO some of my audio resources have a range without any sound at all at the start.
            // Preprocess them to discard any samples of value 0 (or values under a threshold or something)
            state.sound_library[i] = sound;
        }

        try Application.sound.initialize(allocator, .{
            .user_callback = produce_sound,
            .block_count = 8,
            .block_sample_count = 256,
            .channels = 1,
            .device_index = 0,
            .samples_per_second = 44100,
        });
    }

    // load the resources
    const bytes = try Application.read_file_sync(allocator, state.resource_file_name);
    defer allocator.free(bytes);
    try state.resources.load_from_bytes(bytes);
    // load the level
    try load_level(Vec2(u8).from(5, 1), 0);
}

pub fn update(ud: *platform.UpdateData) anyerror!bool {

    const h: f32 = @floatFromInt(state.game_render_target.height);
    const w: f32 = @floatFromInt(state.game_render_target.width);

    const hi: i32 = @intCast(state.game_render_target.height);
    const wi: i32 = @intCast(state.game_render_target.width);

    _ = hi;
    _ = wi;
    
    const real_h: f32 = @floatFromInt(ud.pixel_buffer.height);
    const real_w: f32 = @floatFromInt(ud.pixel_buffer.width);

    const real_hi: i32 = @intCast(ud.pixel_buffer.height);
    const real_wi: i32 = @intCast(ud.pixel_buffer.width);

    const clear_color: BGR = @bitCast(Assets.palette[0]);
    state.game_render_target.clear(platform.OutPixelType.from(BGR, clear_color));

    const ms_taken_update: f32 = blk: {
        const profile = Application.perf.profile_start();

        if (state.play_background_music and state.audio_tracks[0] == null) {
            play(.music_penguknight);
        }

        if (ud.key_pressed('R')) try load_level(Vec2(u8).from(5, 1), ud.frame);

        if (ud.key_pressed('L')) {
            const bytes = try Application.read_file_sync(ud.allocator, state.resource_file_name);
            defer ud.allocator.free(bytes);
            try state.resources.load_from_bytes(bytes);
        }
        if (ud.key_pressed('G')) state.debug = !state.debug;
        if (ud.key_pressed('M')) {
            if (state.play_background_music and state.audio_tracks[0] != null) {
                state.play_background_music = false;
                // NOTE make it look like the song started longer before than it really did so that it naturally stops
                state.audio_tracks[0].?.time_offset -= state.audio_tracks[0].?.duration_seconds;
            }
            else if (!state.play_background_music) state.play_background_music = true;
        }
        
        if (state.player.attack_start_frame > 0 and ud.frame - state.player.attack_start_frame >= Assets.config.player.attack.cooldown) {
            state.player.attack_start_frame = 0;
        }

        var player_is_walking: bool = false;
        if (ud.keys['A'] and state.player.attack_start_frame == 0) {
            state.player.physical_component.velocity.x -= 0.010;
            state.player.look_direction = .Left;
            player_is_walking = true;
        }
        if (ud.keys['D'] and state.player.attack_start_frame == 0) {
            state.player.physical_component.velocity.x += 0.010;
            state.player.look_direction = .Right;
            player_is_walking = true;
        }
        const player_direction_offset: f32 = switch (state.player.look_direction) { .Right => 1, .Left => -1 };
        if (!ud.keys_old['W'] and ud.keys['W'] and state.player.jumps > 0) {
            state.player.physical_component.velocity.y = 0.17;
            state.player.jumps -= 1;
            play(.jump);
            for (0..5) |_| try particle_create(&state.particles, particles_generators.other(
                state.player.pos.add(Vector2f.from(0, 1.5)),
                2 + state.random.float(f32) * 2,
                Vector2f.from(((state.random.float(f32) * 2) - 1)*0.2, -0.05),
                100,
            ));
        }
        if (!ud.keys_old['F'] and ud.keys['F'] and state.player.attack_start_frame == 0) {
            _ = try render_animation_in_place(&state.animations_in_place, RuntimeAnimation.from(Assets.config.player.attack.animation, ud.frame), state.player.pos.add(Vector2f.from(player_direction_offset*8,0)), switch (state.player.look_direction) { .Right => false, .Left => true }, ud.frame);
            state.player.attack_start_frame = ud.frame;
            state.player.physical_component.velocity.x += 0.06 * player_direction_offset;
            play(.attack);
            for (0..3) |_| try particle_create(&state.particles, particles_generators.other(
                state.player.pos.add(Vector2f.from(player_direction_offset*5, 1)),
                2,
                Vector2f.from((0.5 + (state.random.float(f32) * 0.3)) * player_direction_offset, (state.random.float(f32) * 0.6) - 0.2).scale(0.74),
                60,
            ));
            const damage = Assets.config.player.attack.damage;
            const hitbox = Assets.config.player.attack.hitbox_relative_to_position.scale(Vector2f.from(player_direction_offset, 1)).offset(state.player.pos);
            const behaviour: Assets.HitboxType = .once_per_target;
            const duration = Assets.config.player.attack.animation.duration;
            const knockback = Vector2f.from(Assets.config.player.attack.knockback_strength * player_direction_offset, 0);
            try state.entities_damage_dealers.add(hitbox, damage, knockback, behaviour, duration, ud.frame);
        }

        if (state.random.float(f32)>0.8) {
            const height = 21;
            const from: f32 = 304;
            const to: f32 = 367;
            try particle_create(&state.particles, particles_generators.poison(Vector2f.from(state.random.float(f32)*(to-from)+from, height)));
        }

        const player_floored = Physics.apply(&state.player.physical_component);
        state.player.pos = Physics.calculate_real_pos(state.player.physical_component.physical_pos);
        state.player.hurtbox = Assets.entity_knight_1.hurtbox.offset(state.player.pos);

        if (player_floored) {
            state.player.jumps = 2;
            if (player_is_walking and (state.random.float(f32) > 0.8)) {
                try particle_create(&state.particles, particles_generators.walk(state.player.pos.add(Vector2f.from(0, 1))));
            }
        }

        // check for doors to change level
        const player_tile = state.player.get_current_tile();
        for (state.doors.items) |door| {
            if (player_tile.x == door.pos.x and player_tile.y == door.pos.y and ud.key_pressed('E')) {
                const junction = state.resources.junctions.items[door.index];
                if (junction.a.x == door.pos.x and junction.a.y == door.pos.y) try load_level(junction.b, ud.frame) else try load_level(junction.a, ud.frame);
                return true;
            }
        }
        
        for (state.particle_emitters.items) |particle_emitter| {
            if (state.random.boolean()) try particle_create(&state.particles, particles_generators.fire(particle_emitter.pos.to(f32).scale(8).add(Vec2(f32).from(4,4))));
        }

        try state.entities.entities_update(state.player.pos, ud.frame);
        
        for (state.player_damage_dealers.hitboxes.slice(), 0..) |hitbox, i| {
            const frames_up = ud.frame - hitbox.frame;
            var do_remove = false;
            // the entity is being hit by `hitbox`
            if (hitbox.bb.overlaps(state.player.hurtbox)) {
                switch (hitbox.behaviour) {
                    // TODO implement different hitbox behaviours
                    .once_per_frame, .once_per_target => {
                        state.player.hp -= hitbox.dmg;
                        state.player.physical_component.velocity = state.player.physical_component.velocity.add(hitbox.knockback);
                        for (0..5) |_| try particle_create(&state.particles, particles_generators.bleed(state.player.pos));
                        do_remove = true;
                        play(.damage_received_unused);
                    },
                }
            }
            if (do_remove or (frames_up >= hitbox.duration)) state.player_damage_dealers.hitboxes.release_by_index(i);
        }

        state.camera.move_to(state.player.pos, w, h);

        try update_animations_in_place(&state.animations_in_place, ud.frame);
        try particles_update(&state.particles);
        break :blk Application.perf.profile_end(profile);
    };
    
    var renderer: Renderer(platform.OutPixelType) = undefined;
    
    const ms_taken_render: f32 = blk: {
        const profile = Application.perf.profile_start();
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

        // render map
        const map_bb_f = state.level_background.scale(Vec2(usize).from(8,8)).to(f32);
        try renderer.add_map(
            Vec2(usize).from(8,8), Vec2(usize).from(16, 16),
            @constCast(&Assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8), &state.resources.map,
            state.level_background,
            map_bb_f
            // BoundingBox(f32).from_bl_size(
            //     Vector2f.from(map_bb_f.left, map_bb_f.bottom),
            //     Vector2f.from(state.level_background.width()*8, state.level_background.height()*8)
            // )
        );

        // TODO render static texts
        // 
        //     const static_texts_color = RGBA.from(BGR, @bitCast(Assets.palette[5]));
        //     for (state.texts) |text| {
        //         const text_tile = Vector2i.from(text.pos.x, correct_y(text.pos.y));
        //         try state.text_renderer.print(text_tile.scale(8).to(f32), "{s}", .{text.text}, static_texts_color);
        //     }
        //     state.text_renderer.render_all(
        //         state.game_render_target,
        //         mvp_matrix_33,
        //         viewport_matrix_m33
        //     );
        // 
        
        // render entities
        {
            var it = EntitySystem.EntityStorage.view(.{EntitySystem.EntityPosition, RuntimeAnimation}).iterator();
            while (it.next(&state.entities.entities)) |e| {
                const anim_component = (try state.entities.entities.getComponent(RuntimeAnimation, e)).?;
                const pos_component = (try state.entities.entities.getComponent(EntitySystem.EntityPosition, e)).?;
                const dir_component = (try state.entities.entities.getComponent(Direction, e)).?;
                const sprite = anim_component.calculate_frame(ud.frame);
                const pos = pos_component.add(Vector2f.from(-4, 0)) ;
                try renderer.add_sprite_from_atlas_by_index(
                    Vec2(usize).from(8,8), Vec2(usize).from(16, 16),
                    @constCast(&Assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8),
                    @intCast(sprite),
                    BoundingBox(f32).from_bl_size(
                        pos,
                        Vec2(f32).from(8,8)
                    ),
                    .{
                        .mirror_horizontally = switch (dir_component.*) { .Left => true, .Right => false },
                        .blend = true,
                    }
                );
            }
        }
        
        // render player
        {
            const sprite = state.player.animation.calculate_frame(ud.frame);
            const pos = state.player.pos.add(Vector2f.from(-4, 0));
            try renderer.add_sprite_from_atlas_by_index(
                Vec2(usize).from(8,8), Vec2(usize).from(16, 16),
                @constCast(&Assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8),
                @intCast(sprite),
                BoundingBox(f32).from_bl_size(
                    pos,
                    Vec2(f32).from(8,8)
                ),
                .{
                    .mirror_horizontally = state.player.look_direction == .Left,
                    .blend = true,
                }
            );
        }
        
        // render in-place animation
        {
            var it = AnimationSystem.view(.{ Visual }).iterator();
            while (it.next(&state.animations_in_place)) |entity| {
                const visual = (try state.animations_in_place.getComponent(Visual, entity)).?;
                const sprite = visual.sprite;
                const pos = visual.position.add(Vector2f.from(-4,0));
                try renderer.add_sprite_from_atlas_by_index(
                    Vec2(usize).from(8,8), Vec2(usize).from(16, 16),
                    @constCast(&Assets.palette), Buffer2D(u4).from(&state.resources.sprite_atlas, 16*8),
                    @intCast(sprite),
                    BoundingBox(f32).from_bl_size(
                        pos,
                        Vec2(f32).from(8,8)
                    ),
                    .{
                        .mirror_horizontally = visual.flipped,
                        .blend = true,
                    }
                );
            }
        }
        
        // render particles
        {
            var it = Particles.view(.{ Vector2f, ParticleRenderData }).iterator();
            while (it.next(&state.particles)) |e| {
                const render_component = (try state.particles.getComponent(ParticleRenderData, e)).?;
                const position_component = (try state.particles.getComponent(Vector2f, e)).?;
                const radius = render_component.radius;
                try renderer.add_quad_from_bb(BoundingBox(f32).from_bl_size(position_component.*, Vec2(f32).from(radius, radius)), render_component.color);
            }
        }
        
        // render debug hit boxes
        if (state.debug) {
            for (state.player_damage_dealers.hitboxes.slice()) |hb| {
                try renderer.add_quad_from_bb(hb.bb, RGBA.make(255,0,0,100));
            }
            for (state.entities_damage_dealers.hitboxes.slice()) |hb| {
                try renderer.add_quad_from_bb(hb.bb, RGBA.make(0,255,0,100));
            }
            const hb = state.player.hurtbox;
            try renderer.add_quad_from_bb(hb, RGBA.make(0,0,255,100));
        }

        try renderer.flush_all();
        break :blk Application.perf.profile_end(profile);
    };

    // scale to 4 times bigger render target
    // The game is being rendered to a 1/4 size of the window, so scale the image back up to the real size
    const ms_taken_upscale: f32 = blk: {
        const profile = Application.perf.profile_start();
        var y: usize = 0;
        var x: usize = 0;
        var pixel_out_index: usize = 0;
        var rows: usize = 0;
        const game_w = state.game_render_target.width;
        const limit = ud.pixel_buffer.data.len - 4;
        while (pixel_out_index<=limit) {
            const pixel = state.game_render_target.data[y*game_w + x];
            ud.pixel_buffer.data[pixel_out_index+0] = pixel;
            ud.pixel_buffer.data[pixel_out_index+1] = pixel;
            ud.pixel_buffer.data[pixel_out_index+2] = pixel;
            ud.pixel_buffer.data[pixel_out_index+3] = pixel;
            x += 1;
            if (x == game_w) {
                rows += 1;
                x = 0;
                if (rows == 4) {
                    y += 1;
                    rows = 0;
                }
            }
            pixel_out_index += 4;
        }
        break :blk Application.perf.profile_end(profile);
    };

    // blit to bottom left
    // 
    //     for (state.game_render_target.data, 0..) |pixel_in, pixel_in_index| {
    //         const pixel_in_x = pixel_in_index % state.game_render_target.width;
    //         const pixel_in_y = @divFloor(pixel_in_index, state.game_render_target.width);
    //         ud.pixel_buffer.data[pixel_in_y*ud.pixel_buffer.width + pixel_in_x] = pixel_in;
    //     }
    // 
    
    const static = struct {
        var ms_taken_render_ui_previous: f32 = 0;
        var ms_taken_ui_previous: f32 = 0;
    };
    
    var builder: ImmediateModeGui.UiBuilder = undefined;

    static.ms_taken_ui_previous = blk: {
        const profile = Application.perf.profile_start();
        
        builder = state.ui.prepare_frame(ud.allocator, .{
            .mouse_pos = ud.mouse,
            .mouse_down = ud.mouse_left_down,
        });

        const physical_pos_decomposed = Physics.PhysicalPosDecomposed.from(state.player.physical_component.physical_pos);
        const real_tile = Physics.calculate_real_tile(physical_pos_decomposed.physical_tile);
        const mouse: Vector2f = mouse_blk: {
            const mx = @divFloor(ud.mouse.x, Application.dimension_scale);
            // inverse y since mouse is given relative to top left corner
            const my = @divFloor((Application.height*Application.dimension_scale) - ud.mouse.y, Application.dimension_scale);
            const offset = Vector2f.from(state.camera.pos.x, state.camera.pos.y);
            const pos = Vector2i.from(mx, my).to(f32).add(offset);
            break :mouse_blk pos;
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
            try debug.label("physical pos {d:.4} {d:.4}", .{state.player.physical_component.physical_pos.x, state.player.physical_component.physical_pos.y});
            try debug.label("physical tile {} {}", .{physical_pos_decomposed.physical_tile.x, physical_pos_decomposed.physical_tile.y});
            try debug.label("to real tile {} {}", .{real_tile.x, real_tile.y});
            try debug.label("vel {d:.5} {d:.5}", .{state.player.physical_component.velocity.x, state.player.physical_component.velocity.y});
            try debug.label("update  took {d:.8}ms", .{ms_taken_update});
            try debug.label("render  took {d:.8}ms", .{ms_taken_render});
            try debug.label("upscale took {d:.8}ms", .{ms_taken_upscale});
            try debug.label("ui prev took {d:.8}ms", .{static.ms_taken_ui_previous});
            try debug.label("ui rend took {d:.8}ms", .{static.ms_taken_render_ui_previous});
            // force debug container to be the lowest layer
            for (state.ui.containers_order.slice(), 0..) |container_id, i| if (container_id == debug.persistent.unique_identifier) {
                const aux = state.ui.containers_order.slice()[0];
                state.ui.containers_order.slice()[0] = container_id;
                state.ui.containers_order.slice()[i] = aux;
            };
        }

        break :blk Application.perf.profile_end(profile);
    };

    if (state.debug) {

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

// *****************************************************************

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

const ImmediateModeGui = imgui.ImmediateModeGui(.{
    .layout = .{
        .char_height = 5*text_size_multiplier,
        .char_width = 4*text_size_multiplier,
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

const Door = struct {
    pos: Vec2(u8),
    index: usize
};

const ParticleEmitter = struct {
    pos: Vec2(u8),
    emitter_type: Assets.ParticleEmitterType
};

pub fn load_level(spawn: Vec2(u8), frame: usize) !void {
    state.entities.clear();
    state.particles.deleteAll();
    state.player.reset_soft(frame);
    state.doors.clearRetainingCapacity();
    state.particle_emitters.clearRetainingCapacity();
    state.animations_in_place.deleteAll();
    // TODO reset the HitboxSystems

    var found = false;
    for (state.resources.levels.items) |level| {
        if (level.bb.contains(spawn)) {
            
            // found the level
            found = true;
            
            state.level_background = level.bb.to(usize);
            
            var bb = state.level_background;
            bb.top += 1;
            bb.right += 1;
            state.camera.set_bounds(bb.scale(Vec2(usize).from(8, 8)).to(f32));

            for (state.resources.environment_particle_emitters.items) |particle_emitter| {
                if (level.bb.contains(particle_emitter.pos)) state.particle_emitters.appendAssumeCapacity(.{.pos = particle_emitter.pos, .emitter_type = @enumFromInt(particle_emitter.particle_emitter_type)});
            }

            for (state.resources.entity_spawners.items) |entity_spawn| {
                if (level.bb.contains(entity_spawn.pos)) {
                    try state.entities.spawn(@enumFromInt(entity_spawn.entity_type), tile_to_grounded_position(entity_spawn.pos.to(i32)), frame);
                }
            }

            for (state.resources.junctions.items, 0..) |junction, i| {
                if (level.bb.contains(junction.a)) state.doors.appendAssumeCapacity(.{.pos=junction.a, .index=i});
                if (level.bb.contains(junction.b)) state.doors.appendAssumeCapacity(.{.pos=junction.b, .index=i});
            }

            break;
        }
    }

    if (!found) return error.LevelContainingSpawnNotFound;
    
    // TODO
    // state.texts = level.static_texts;
    
    state.player.spawn(spawn.to(i32));
}

fn tile_to_grounded_position(tile: Vector2i) Vector2f {
    return Vector2f.from(@floatFromInt(tile.x*8+4), (@floatFromInt(tile.y*8)));
}

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

inline fn collision_checker(tile: Vector2i) bool {
    if (tile.x < 0 or tile.y < 0) return true;
    const tileu = tile.to(usize);
    if (!state.level_background.contains(tileu)) return true;
    const tile_index = state.resources.map[tileu.y][tileu.x];
    const col = tile_index%16;
    const row = @divFloor(tile_index, 16);
    return Assets.map_flags[col + row*16] == 0x01;
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

const Direction = enum {Left, Right};

const Player = struct {
    animation: RuntimeAnimation,
    pos: Vector2f,
    physical_component: Physics.PhysicalObject,
    look_direction: Direction,
    jumps: i32,
    /// The frame in which the attack started. 0 when not attacking
    attack_start_frame: usize,
    hurtbox: BoundingBox(f32),
    hp: i32,
    
    pub fn init(frame: usize) Player {
        var player: Player = undefined;
        player.reset_soft(frame);
        player.physical_component = Physics.PhysicalObject.from(Vector2f.from(0,0), 3);
        player.pos = Vector2f.from(0,0);
        // TODO set other config stuff
        // player.hp = Assets.config.player.hp;
        player.hp = 100;
        return player;
    }

    pub fn reset_soft(self: *Player, frame: usize) void {
        self.animation = RuntimeAnimation {
            .animation = Assets.animation_player_idle,
            .frame_start = frame,
        };
        self.attack_start_frame = 0;
        self.jumps = 1;
        self.look_direction = .Right;
    }

    pub fn spawn(self: *Player, pos: Vector2i) void {
        self.pos = pos.to(f32).scale(8);
        self.physical_component = Physics.PhysicalObject.from(self.pos, 3);
        self.hurtbox = Assets.entity_knight_1.hurtbox.offset(self.pos);
    }

    pub fn get_current_tile(self: *const Player) Vector2i {
        return Vector2i.from(@intFromFloat(@divFloor(self.pos.x, 8)), @intFromFloat(@divFloor(self.pos.y, 8)));
    }
};

const RuntimeAnimation = struct {
    animation: Assets.AnimationDescriptor,
    frame_start: usize,
    pub fn calculate_frame(self: RuntimeAnimation, frame: usize) u8 {
        const total_frames: usize = frame - self.frame_start;
        const normalized: usize = total_frames % self.animation.duration;
        const time_between_animation_frames: usize = @divFloor(self.animation.duration, self.animation.sprites.len);
        const animation_index: usize = @divFloor(normalized, time_between_animation_frames);
        // TODO there is bug in which `animation_index` == `animation.sprites.len`
        return self.animation.sprites[animation_index];
    }
    pub fn from(animation: Assets.AnimationDescriptor, frame: usize) RuntimeAnimation {
        return RuntimeAnimation {
            .animation = animation,
            .frame_start = frame
        };
    }
};

const EntitySystem = struct {

    const EntityPosition = Vector2f;
    const EntityStorage = Ecs( .{ i32, Assets.EntityType, Physics.PhysicalObject, EntityPosition, RuntimeAnimation, Direction, Assets.EntitySlimeRuntime, Assets.EntityKnight1Runtime, Assets.EntityKnight2Runtime, Assets.EntitySlimeKingRuntime, BoundingBox(f32) });
    
    entities: EntityStorage,
    
    pub fn init_capacity(allocator: std.mem.Allocator, capacity: usize) !EntitySystem {
        return EntitySystem {
            .entities = try EntityStorage.init_capacity(allocator, capacity)
        };
    }
    
    pub fn clear(self: *EntitySystem) void {
        self.entities.deleteAll();
    }

    pub fn spawn(self: *EntitySystem, entity_type: Assets.EntityType, pos: Vector2f, frame_number: usize) !void {
        const entity_desc = Assets.EntityDescriptor.from(entity_type);
        const e = try self.entities.newEntity();
        const phys_component = try self.entities.setComponent(Physics.PhysicalObject, e);
        const pos_component = try self.entities.setComponent(EntityPosition, e);
        const dir_component = try self.entities.setComponent(Direction, e);
        const anim_component = try self.entities.setComponent(RuntimeAnimation, e);
        const type_component = try self.entities.setComponent(Assets.EntityType, e);
        const hurtbox_component = try self.entities.setComponent(BoundingBox(f32), e);
        const hp_component = try self.entities.setComponent(i32, e);
        switch (entity_type) {
            .slime => {
                const runtime_component = try self.entities.setComponent(Assets.EntitySlimeRuntime, e);
                runtime_component.* = Assets.EntitySlimeRuntime.init();
            },
            .knight_1 => {
                const runtime_component = try self.entities.setComponent(Assets.EntityKnight1Runtime, e);
                runtime_component.* = Assets.EntityKnight1Runtime.init();
            },
            .knight_2 => {
                const runtime_component = try self.entities.setComponent(Assets.EntityKnight2Runtime, e);
                runtime_component.* = Assets.EntityKnight2Runtime.init();
            },
            .archer => {
                const runtime_component = try self.entities.setComponent(Assets.EntityArcherRuntime, e);
                runtime_component.* = Assets.EntityArcherRuntime.init();
            },
            .slime_king => {
                const runtime_component = try self.entities.setComponent(Assets.EntitySlimeKingRuntime, e);
                runtime_component.* = Assets.EntitySlimeKingRuntime.init();
            },
        }
        type_component.* = entity_type;
        phys_component.* = Physics.PhysicalObject.from(pos, entity_desc.weight);
        anim_component.* = RuntimeAnimation {
            .animation = entity_desc.default_animation.*,
            .frame_start = frame_number,
        };
        pos_component.* = pos;
        dir_component.* = .Right;
        hurtbox_component.* = entity_desc.hurtbox.offset(pos_component.*);
        hp_component.* = entity_desc.hp;
    }

    pub fn entities_update(self: *EntitySystem, player_pos: Vector2f, frame: usize) !void {
        
        var it = EntityStorage.view(.{i32, Physics.PhysicalObject, EntityPosition, Direction, Assets.EntityType, BoundingBox(f32)}).iterator();
        while (it.next(&self.entities)) |e| {
            const phys_component = (try self.entities.getComponent(Physics.PhysicalObject, e)).?;
            const pos_component = (try self.entities.getComponent(EntityPosition, e)).?;
            const dir_component = (try self.entities.getComponent(Direction, e)).?;
            const type_component = (try self.entities.getComponent(Assets.EntityType, e)).?;
            const hb_component = (try self.entities.getComponent(BoundingBox(f32), e)).?;
            const hp_component = (try self.entities.getComponent(i32, e)).?;
            const entity_desc = Assets.EntityDescriptor.from(type_component.*);

            // find whether the entity is being damaged
            for (state.entities_damage_dealers.hitboxes.slice(), 0..) |hitbox, i| {
                // the entity is being hit by `hitbox`
                if (hitbox.bb.overlaps(hb_component.*)) {
                    switch (hitbox.behaviour) {
                        // TODO implement different hitbox behaviours
                        .once_per_frame, .once_per_target => {
                            hp_component.* -= hitbox.dmg;
                            phys_component.velocity = phys_component.velocity.add(hitbox.knockback);
                            _ = state.entities_damage_dealers.hitboxes.release_by_index(i);
                            switch (type_component.*) {
                                .slime, .slime_king  => for (0..5) |_| try particle_create(&state.particles, particles_generators.slime_damaged(pos_component.*)),
                                else => for (0..5) |_| try particle_create(&state.particles, particles_generators.bleed(pos_component.*))
                            }
                            // TODO sfx
                        },
                    }
                }

            }

            if (hp_component.* <= 0) {
                try self.entities.deleteEntity(e);
                continue;
            }
            
            const entity_to_player = player_pos.substract(pos_component.*);
            const dist_to_player = entity_to_player.magnitude();
            const is_right = entity_to_player.x>0;
            const dir_f32: f32 = if (is_right) 1 else -1;
            const in_attack_range = dist_to_player <= entity_desc.attack_range;
            const in_chase_range = dist_to_player <= entity_desc.chase_range;

            switch (type_component.*) {
                .slime => {
                    const slime_component = (try self.entities.getComponent(Assets.EntitySlimeRuntime, e)).?;
                    const charge_duration = 60;
                    const launch_speed = 0.6;
                    var set_slime_body_as_hitbox = false;
                    const is_attacking = slime_component.attack_start_frame != 0;
                    if (!is_attacking) {
                        if (in_attack_range) {
                            // the slime will be "charging" the launch from frame until frame+charge_duration
                            slime_component.attack_start_frame = frame;
                            slime_component.attack_direction = if (is_right) .Right else .Left;
                            dir_component.* = if (is_right) .Right else .Left;
                            // TODO animation "charging"
                            play(.slime_attack_a);
                        }
                        else if (in_chase_range) {
                            phys_component.velocity.x = (entity_desc.speed * dir_f32);
                            dir_component.* = if (is_right) .Right else .Left;
                            // TODO climb wall
                        }
                        else {
                            // TODO animation "iddle"
                        }
                    }
                    else {
                        const frames_since_attack_start = frame - slime_component.attack_start_frame;

                        // either charging, attacking (when its launching agains player), recovering
                        if (frames_since_attack_start < charge_duration) {
                            // do nothing, keep charging
                        }
                        else if (frames_since_attack_start == charge_duration) {
                            // launch towards the player
                            phys_component.velocity.x = (launch_speed * switch(slime_component.attack_direction){.Right=>@as(f32, 1.0),.Left=>-1.0});
                            phys_component.velocity.y = 0.07;
                            
                            set_slime_body_as_hitbox = true;
                            
                            // TODO animation "damaging hitbox"
                            play(.slime_attack_b);
                        }
                        else if (@abs(phys_component.velocity.x) <= 0.1 and @abs(phys_component.velocity.y) <= 0.1) {
                            // back to normal
                            slime_component.attack_start_frame = 0;
                            // TODO animation "normal"
                        }
                        else {
                            // TODO set hitbox
                            set_slime_body_as_hitbox = true;
                        }
                    }

                    const is_floored = Physics.apply(phys_component);
                    pos_component.* = Physics.calculate_real_pos(phys_component.physical_pos);
                    hb_component.* = entity_desc.hurtbox.offset(pos_component.*);
                    _ = is_floored;

                    if (set_slime_body_as_hitbox) {
                        const damage: i32 = @intFromFloat(@as(f32, @floatFromInt(entity_desc.attack_dmg)) * std.math.clamp(@abs(phys_component.velocity.x)/launch_speed, 0, 1));
                        const hitbox = BoundingBox(f32).from(4, 0, -3, 3).offset(pos_component.*);
                        const behaviour: Assets.HitboxType = .once_per_frame;
                        const duration = 1;
                        const knockback = phys_component.velocity;
                        try state.player_damage_dealers.add(hitbox, damage, knockback, behaviour, duration, frame);
                    }
                },
                .knight_1 => {
                    const knight_component = (try self.entities.getComponent(Assets.EntityKnight1Runtime, e)).?;
                    
                    const charge_duration = 35;
                    const chain_charge_duration = 35;
                    const cooldown_duration_1 = 60;
                    const cooldown_duration_2 = 150;

                    if (knight_component.current_state == .idle) {
                        if (in_attack_range) {
                            // start attack
                            knight_component.current_state = .charging;
                            knight_component.state_change_frame = frame;
                            knight_component.attack_direction = if (is_right) .Right else .Left;
                            dir_component.* = if (is_right) .Right else .Left;
                            const attack_dir_f32 = switch(knight_component.attack_direction){.Right=>@as(f32, 1.0),.Left=>-1.0};
                            _ = try render_animation_in_place(&state.animations_in_place, RuntimeAnimation.from(Assets.animation_preparing_attack, frame), pos_component.add(Vector2f.from(attack_dir_f32*3,0)), false, frame);
                            // TODO knight animation "charging"?
                            play(.knight_prepare);
                        }
                        else if (in_chase_range) {
                            phys_component.velocity.x = (entity_desc.speed * dir_f32);
                            dir_component.* = if (is_right) .Right else .Left;
                            // TODO jump or if cant, then taunt
                        }
                        else {
                            // TODO animation "idle"
                        }
                    }

                    const attack_dir_f32 = switch(knight_component.attack_direction){.Right=>@as(f32, 1.0),.Left=>-1.0};
                    
                    if (knight_component.current_state == .charging) {
                        const frames_since_charge_start = frame - knight_component.state_change_frame;
                        if (frames_since_charge_start == charge_duration) {
                            // charge complete, so swing blade in front
                            
                            const damage: i32 = entity_desc.attack_dmg;
                            const hitbox = BoundingBox(f32).from(6, 1, 3, 8).scale(Vector2f.from(attack_dir_f32, 1)).offset(pos_component.*);
                            const behaviour: Assets.HitboxType = .once_per_frame;
                            const duration = Assets.animation_attack_1.duration;
                            const knockback = Vector2f.from(attack_dir_f32, 0).scale(0.25);
                            try state.player_damage_dealers.add(hitbox, damage, knockback, behaviour, duration, frame);

                            const mirror_animation = switch(knight_component.attack_direction){.Right=> false, .Left=> true};
                            _ = try render_animation_in_place(&state.animations_in_place, RuntimeAnimation.from(Assets.animation_attack_1, frame), pos_component.add(Vector2f.from(attack_dir_f32*7,0)), mirror_animation, frame);
                            play(.knight_attack);
                            phys_component.velocity.x = (entity_desc.speed * switch(knight_component.attack_direction){.Right=>@as(f32, 1.0),.Left=>-1.0});
                            knight_component.current_state = .attack_1_cooldown;
                            knight_component.state_change_frame = frame;
                        }
                    }

                    if (knight_component.current_state == .attack_1_cooldown) {
                        const frames_since_attack = frame - knight_component.state_change_frame;
                        if (frames_since_attack < cooldown_duration_1) {
                            if (in_attack_range and (is_right == (knight_component.attack_direction == .Right))) {
                                // if player still in front, chain attack
                                play(.knight_prepare);
                                _ = try render_animation_in_place(&state.animations_in_place, RuntimeAnimation.from(Assets.animation_preparing_attack, frame), pos_component.add(Vector2f.from(attack_dir_f32*3,0)), false, frame);
                                knight_component.current_state = .chaining;
                                knight_component.state_change_frame = frame;
                            }
                        }
                        else if (frames_since_attack == cooldown_duration_1) {
                            // cooled down from first attack
                            knight_component.current_state = .idle;
                            knight_component.state_change_frame = 0;
                        }
                    }

                    if (knight_component.current_state == .chaining) {
                        const frames_since_chaining_started = frame - knight_component.state_change_frame;
                        if (frames_since_chaining_started == chain_charge_duration) {
                            play(.knight_attack);
                            
                            const damage: i32 = entity_desc.attack_dmg*2;
                            const hitbox = BoundingBox(f32).from(7, 1, 3, 10).scale(Vector2f.from(attack_dir_f32, 1)).offset(pos_component.*);
                            const behaviour: Assets.HitboxType = .once_per_frame;
                            const duration = Assets.animation_attack_1.duration;
                            const knockback = Vector2f.from(attack_dir_f32*1.20, 0).scale(0.25);
                            try state.player_damage_dealers.add(hitbox, damage, knockback, behaviour, duration, frame);

                            const mirror_animation = switch(knight_component.attack_direction){.Right=> false, .Left=> true};
                            _ = try render_animation_in_place(&state.animations_in_place, RuntimeAnimation.from(Assets.animation_attack_1, frame), pos_component.add(Vector2f.from(attack_dir_f32*7,0)), mirror_animation, frame);
                            phys_component.velocity.x = (entity_desc.speed * switch(knight_component.attack_direction){.Right=>@as(f32, 1.0),.Left=>-1.0});
                            knight_component.current_state = .attack_2_cooldown;
                            knight_component.state_change_frame = frame;
                        }
                    }

                    if (knight_component.current_state == .attack_2_cooldown) {
                        const frames_since_attack = frame - knight_component.state_change_frame;
                        if (frames_since_attack == cooldown_duration_2) {
                            // cooled down from attack 2, back to idle
                            knight_component.current_state = .idle;
                            knight_component.state_change_frame = 0;
                        }
                    }

                    const is_floored = Physics.apply(phys_component);
                    pos_component.* = Physics.calculate_real_pos(phys_component.physical_pos);
                    hb_component.* = entity_desc.hurtbox.offset(pos_component.*);
                    _ = is_floored;
                },
                .knight_2 => {
                    const knight_component = (try self.entities.getComponent(Assets.EntityKnight2Runtime, e)).?;
                    _ = knight_component;
                    if (in_chase_range) {
                        phys_component.velocity.x = (entity_desc.speed * dir_f32);
                    }
                    const is_floored = Physics.apply(phys_component);
                    pos_component.* = Physics.calculate_real_pos(phys_component.physical_pos);
                    _ = is_floored;
                },
                .slime_king => {
                    const knight_component = (try self.entities.getComponent(Assets.EntitySlimeKingRuntime, e)).?;
                    _ = knight_component;
                    if (in_chase_range) {
                        phys_component.velocity.x = (entity_desc.speed * dir_f32);
                    }
                    const is_floored = Physics.apply(phys_component);
                    pos_component.* = Physics.calculate_real_pos(phys_component.physical_pos);
                    _ = is_floored;
                },
                else => unreachable
            }
        }
    
        for (state.entities_damage_dealers.hitboxes.slice(), 0..) |hitbox, i| {
            const frames_up = frame - hitbox.frame;
            if (frames_up >= hitbox.duration) _ = state.entities_damage_dealers.hitboxes.release_by_index(i);
        }
    }

};

pub fn Pool(comptime T: type) type {
    return struct {

        const Self = @This();
        
        marked_deleted: std.ArrayList(usize),
        data: std.ArrayList(T),
        index: usize,
        total: usize,

        pub fn init_capacity(allocator: std.mem.Allocator, num: usize) std.mem.Allocator.Error!Self {
            const self = Self {
                .marked_deleted = try std.ArrayList(usize).initCapacity(allocator, num),
                .data = try std.ArrayList(T).initCapacity(allocator, num),
                .index = 0,
                .total = num
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.marked_deleted.deinit();
            self.data.deinit();
        }

        pub fn acquire(self: *Self) ?*T {
            if (self.index >= self.total) {
                if (self.marked_deleted.items.len == 0) return null
                else {
                    // if the pool is full try to return a resource that has been marked as deleted
                    // this is slow but its also not really supposed to happen I guess
                    const index_to_reuse = self.marked_deleted.pop();
                    return &self.data.items[index_to_reuse];
                }
            }
            const i = self.index;
            self.index += 1;
            if (i == self.data.items.len) return self.data.addOneAssumeCapacity()
            else return &self.data.items[i];
        }

        pub fn release_by_index(self: *Self, i: usize) void {
            std.debug.assert(i <= self.index);
            self.marked_deleted.appendAssumeCapacity(i);
        }

        fn maintenance(self: *Self) void {
            if (self.marked_deleted.items.len == 0) return;
            self.index -= self.marked_deleted.items.len;
            while (self.marked_deleted.popOrNull()) |deleted_index| {
                _ = self.data.swapRemove(deleted_index);
            }
            self.marked_deleted.clearRetainingCapacity();
        }

        pub fn slice(self: *Self) []T {
            self.maintenance();
            return self.data.items[0..self.index];
        }

    };
}

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

const AnimationSystem = Ecs(.{ Visual, KillAtFrame, RuntimeAnimation });

const KillAtFrame = usize;

const Visual = struct {
    sprite: u8,
    flipped: bool,
    position: Vector2f,
};

fn render_animation_in_place(pool: *AnimationSystem, anim: RuntimeAnimation, pos: Vector2f, flipped: bool, frame: usize) !Entity {
    const e = try pool.newEntity();
    const animation = try pool.setComponent(RuntimeAnimation, e);
    const kill_frame = try pool.setComponent(KillAtFrame, e);
    const visual = try pool.setComponent(Visual, e);
    animation.* = anim;
    kill_frame.* = frame + anim.animation.duration - 1;
    visual.* = .{
        .sprite = anim.animation.sprites[0],
        .flipped = flipped,
        .position = pos
    };
    return e;
}

fn update_animations_in_place(pool: *AnimationSystem, frame: usize) !void {
    var it = AnimationSystem.view(.{ Visual, KillAtFrame, RuntimeAnimation }).iterator();
    while (it.next(pool)) |entity| {
        const visual = (try pool.getComponent(Visual, entity)).?;
        const kill_frame = (try pool.getComponent(KillAtFrame, entity)).?;
        const anim = (try pool.getComponent(RuntimeAnimation, entity)).?;
        if (frame > kill_frame.*) try pool.deleteEntity(entity)
        else visual.*.sprite = anim.calculate_frame(frame);
    }
}

pub const Particles = Ecs(.{ Physics.PhysicalObject, ParticleLife, Vector2f, ParticleRenderData });

const ParticleLife = i32;

pub const ParticleRenderData = struct {
    radius: f32,
    color: RGBA,
};

pub const ParticleDescriptor = struct {
    position: Vector2f,
    color: RGB,
    weight: f32,
    speed: Vector2f,
    radius: f32,
    /// How many frames the particle will live for
    life: ParticleLife,
    alpha: u8,
};

pub fn particle_create(particles: *Particles, descriptor: ParticleDescriptor) !void {
    const particle = try particles.newEntity();
    var physical = try particles.setComponent(Physics.PhysicalObject, particle);
    const life = try particles.setComponent(ParticleLife, particle);
    const pos = try particles.setComponent(Vector2f, particle);
    const render_data = try particles.setComponent(ParticleRenderData, particle);
    physical.* = Physics.PhysicalObject.from(descriptor.position, descriptor.weight);
    physical.velocity = descriptor.speed;
    life.* = descriptor.life;
    pos.* = descriptor.position;
    render_data.*.color = RGBA.from(RGB, descriptor.color);
    render_data.*.color.a = descriptor.alpha;
    render_data.*.radius = descriptor.radius;
}

pub fn particles_update(particles: *Particles) !void {

    // update particles life
    {
        var iterator = Particles.view(.{ ParticleLife }).iterator();
        while (iterator.next(particles)) |e| {
            const life_component = (try particles.getComponent(ParticleLife, e)).?;
            life_component.* -= 1;
            if (life_component.* < 0) try particles.deleteEntity(e);
        }
    }

    // update particles positions and velocities
    {
        var iterator = Particles.view(.{ Physics.PhysicalObject, Vector2f }).iterator();
        while (iterator.next(particles)) |e| {
            const physics_component = (try particles.getComponent(Physics.PhysicalObject, e)).?;
            const position_component = (try particles.getComponent(Vector2f, e)).?;
            _ = Physics.apply(physics_component);
            position_component.* = Physics.calculate_real_pos(physics_component.physical_pos);
        }
    }

}

pub const particles_generators = struct {
    pub fn bleed(pos: Vector2f) ParticleDescriptor {
        return ParticleDescriptor {
            .color = RGB.from_other(BGR, @bitCast(Assets.palette[2])),
            .life = 1000,
            .position = pos,
            .radius = 1 + state.random.float(f32),
            .speed = Vector2f.from((state.random.float(f32) * 2) - 1, (state.random.float(f32) * 2) - 1).scale(0.5),
            .weight = 5,
            .alpha = 160,
        };
    }
    pub fn slime_damaged(pos: Vector2f) ParticleDescriptor {
        return ParticleDescriptor {
            .color = RGB.from_other(BGR, @bitCast(Assets.palette[6])),
            .life = 1000,
            .position = pos,
            .radius = 1 + state.random.float(f32)*3,
            .speed = Vector2f.from((state.random.float(f32) * 2) - 1, (state.random.float(f32) * 2) - 1).scale(0.4),
            .weight = 6,
            .alpha = 160,
        };
    }
    pub fn walk(pos: Vector2f) ParticleDescriptor {
        return ParticleDescriptor {
            .color = RGB.from_other(BGR, @bitCast(Assets.palette[15])),
            .life = 30,
            .position = pos,
            .radius = 1 + state.random.float(f32) * 3,
            .speed = Vector2f.from((state.random.float(f32) * 2) - 1, (state.random.float(f32) * 2) - 1).scale(0.05),
            .weight = 0.2,
            .alpha = 120,
        };
    }
    pub fn fire(pos: Vector2f) ParticleDescriptor {
        return ParticleDescriptor {
            .color = RGB.from_other(BGR, @bitCast(Assets.palette[if (state.random.boolean()) 3 else 4])),
            .life = 40,
            .position = pos,
            .radius = 1 + state.random.float(f32) * 2,
            .speed = Vector2f.from((state.random.float(f32) * 2) - 1, state.random.float(f32) - 0.5).scale(0.05),
            .weight = -0.2,
            .alpha = 120,
        };
    }
    pub fn poison(pos: Vector2f) ParticleDescriptor {
        return ParticleDescriptor {
            .color = RGB.from_other(BGR, @bitCast(Assets.palette[if (state.random.boolean()) 6 else 7])),
            .life = 100,
            .position = pos,
            .radius = 2 + state.random.float(f32) * 3,
            .speed = Vector2f.from((state.random.float(f32) * 2) - 1, 0).scale(0.02),
            .weight = -0.13,
            .alpha = 120,
        };
    }
    pub fn other(pos: Vector2f, radious: f32, speed: Vector2f, alpha: u8) ParticleDescriptor {
        return ParticleDescriptor {
            .color = RGB.from_other(BGR, @bitCast(Assets.palette[15])),
            .life = 30,
            .position = pos,
            .radius = radious,
            .speed = speed,
            .weight = 0.2,
            .alpha = alpha,
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

const HitboxSystem = struct {
    
    pub const HitboxData = struct {
        bb: BoundingBox(f32),
        dmg: i32,
        knockback: Vector2f,
        behaviour: Assets.HitboxType,
        duration: usize,
        frame: usize,
        
        pub inline fn from(bb: BoundingBox(f32), dmg: i32, knockback: Vector2f, behaviour: Assets.HitboxType, duration: usize, frame: usize) HitboxData {
            return HitboxData {
                .bb = bb,
                .dmg = dmg,
                .knockback = knockback,
                .behaviour = behaviour,
                .duration = duration,
                .frame = frame,
            };
        }
    };
    
    hitboxes: Pool(HitboxData),
    
    pub fn init_capacity(allocator: std.mem.Allocator, capacity: usize) !HitboxSystem {
        return .{
            .hitboxes = try Pool(HitboxData).init_capacity(allocator, capacity),
        };
    }

    pub fn add(self: *HitboxSystem, bb: BoundingBox(f32), dmg: i32, knockback: Vector2f, behaviour: Assets.HitboxType, duration: usize, frame: usize) !void {
        if (self.hitboxes.acquire()) |hb| hb.* = (HitboxData.from(bb, dmg, knockback, behaviour, duration, frame))
        else return error.NotEnoughCapacity;
    }
};

/// in tic's maps, the Y points downwards. This functions "corrects" any y coordinate when referencing a tile in a map
inline fn correct_y(thing: anytype) @TypeOf(thing) {
    return  135 - thing;
}

pub const Assets = struct {
    
    pub const ParticleEmitterType = enum {
        fire
    };

    // TODO add static texts to the resource manager
    // 
    pub const StaticTextDescriptor = struct {
        /// indexes into a `tic80.Map` 
        pos: Vector2i,
        /// size in terms of map cells
        size: Vector2i,
        text: []const u8,
        pub inline fn from(pos: Vector2i, size: Vector2i, text: []const u8) StaticTextDescriptor {
            return StaticTextDescriptor  { .pos = pos, .size = size, .text = text };
        }
    };
    
    pub const static_text_tutorial_0 = StaticTextDescriptor.from(Vector2i.from(3, correct_y(3)), Vector2i.from(25, 1), "[g] to toggle debug");
    pub const static_text_tutorial_1 = StaticTextDescriptor.from(Vector2i.from(3, correct_y(2)), Vector2i.from(25, 1), "[r] to restart");
    pub const static_text_tutorial_2 = StaticTextDescriptor.from(Vector2i.from(35, correct_y(8)), Vector2i.from(19, 1), "[f] to attack");


    pub const EntitySpawnDescriptor = struct {
        /// indexes into a `tic80.Map` 
        pos: Vector2i,
        entity: EntityType,
        pub inline fn from(pos: Vector2i, entity: EntityType) EntitySpawnDescriptor {
            return EntitySpawnDescriptor  { .pos = pos, .entity = entity };
        }
    };
    
    pub const entity_spawn_enemy_slime_king_0 = EntitySpawnDescriptor.from(Vector2i.from(131, 131), .slime_king);
    pub const entity_spawn_enemy_knight_0 = EntitySpawnDescriptor.from(Vector2i.from(71, 116), .knight_1);
    pub const entity_spawn_enemy_knight_1 = EntitySpawnDescriptor.from(Vector2i.from(77, 116), .knight_2);
    pub const entity_spawn_enemy_slime_0 = EntitySpawnDescriptor.from(Vector2i.from(68, 132), .slime);
    pub const entity_spawn_enemy_slime_1 = EntitySpawnDescriptor.from(Vector2i.from(72, 132), .slime);
    pub const entity_spawn_enemy_slime_2 = EntitySpawnDescriptor.from(Vector2i.from(81, 129), .slime);
    pub const entity_spawn_enemy_slime_3 = EntitySpawnDescriptor.from(Vector2i.from(36, 132), .slime);
    pub const entity_spawn_enemy_slime_4 = EntitySpawnDescriptor.from(Vector2i.from(48, 132), .slime);
    pub const entity_spawn_enemy_knight_2 = EntitySpawnDescriptor.from(Vector2i.from(7, 25), .knight_1);
    pub const entity_spawn_enemy_knight_3 = EntitySpawnDescriptor.from(Vector2i.from(13, 23), .knight_2);
    pub const entity_spawn_enemy_knight_4 = EntitySpawnDescriptor.from(Vector2i.from(15, 20), .knight_1);
    pub const entity_spawn_enemy_knight_5 = EntitySpawnDescriptor.from(Vector2i.from(21, 25), .knight_2);

    const EntityType = enum {
        slime,
        knight_1,
        knight_2,
        archer,
        slime_king,
    };

    const EntitySlimeRuntime = struct {
        attack_start_frame: usize,
        attack_direction: Direction,
        pub fn init() EntitySlimeRuntime {
            return .{
                .attack_start_frame = 0,
                .attack_direction = .Right,
            };
        }
    };

    const EntityArcherRuntime = struct {
        pub fn init() EntityArcherRuntime { return .{}; }
    };

    const EntitySlimeKingRuntime = struct {
        pub fn init() EntitySlimeKingRuntime { return .{}; }
    };
    
    const EntityKnight1Runtime = struct {
        
        state_change_frame: usize,
        current_state: EntityState,
        attack_direction: Direction,

        const EntityState = enum {
            idle, charging, attack_1_cooldown, chaining, attack_2_cooldown 
        };

        pub fn init() EntityKnight1Runtime {
            return .{
                .state_change_frame = 0,
                .current_state = .idle,
                .attack_direction = .Right,
            };
        }
    };

    const EntityKnight2Runtime = struct {
        pub fn init() EntityKnight2Runtime { return .{}; }
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
    
    pub const config = struct {
        pub const player = struct {
            pub const attack = struct {
                pub const cooldown = 10;
                pub const damage = 10;
                pub const animation = animation_attack_1;
                pub const range = 2;
                pub const hitbox_relative_to_position = BoundingBox(f32).from(6, 1, 5, 11);
                pub const knockback_strength = 0.22;
            };
        };
    };

    const HitboxType = enum {
        /// once the hitbox hits an enemy, it cannot hit the same enemy again for the duration of the hitbox
        once_per_target,
        /// once hit per frame, as many times as it hits
        once_per_frame,
    };
    
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

    // NOTE(Oscar) for some reason the flags are inversed in the save format of tic80, so I reversed them here manually
    const map_flags = tic80.Flags {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x02, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00,
    };

    // TODO in place effects such as: attack slash animation 1, attack slash animation 2 and kinght attack flash animation
    // consists of: animation, location, and creation frame

};
