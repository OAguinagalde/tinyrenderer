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
    
    const real_h: f32 = @floatFromInt(ud.pixel_buffer.height);
    const real_w: f32 = @floatFromInt(ud.pixel_buffer.width);

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
        for (state.game_render_target.data, 0..) |pixel_in, pixel_in_index| {
            const pixel_in_x = pixel_in_index % state.game_render_target.width;
            const pixel_in_y = @divFloor(pixel_in_index, state.game_render_target.width);
            const pixel_out_x = pixel_in_x * 4;
            const pixel_out_y = pixel_in_y * 4;
            // TODO not cache frienly at all, it works for now tho
            for (0..4) |i| { for (0..4) |j| ud.pixel_buffer.data[((pixel_out_y+i)*ud.pixel_buffer.width) + (pixel_out_x+j)] = pixel_in; }
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
    
    if (state.debug) {

        const static = struct {
            var ms_taken_debug_previous: f32 = 0;
        };

        static.ms_taken_debug_previous = blk: {
            const profile = Application.perf.profile_start();

            renderer.set_context(
                ud.pixel_buffer,
                M33.orthographic_projection(0, real_w, real_h, 0),
                M33.viewport(0, 0, real_w, real_h)
            );

            const debug_text_color: BGR = @bitCast(Assets.palette[3]);
            const color = RGBA.from(BGR, debug_text_color);
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
            const text_height = 6 + 1;
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*1 )), "ms {d: <9.2}", .{ud.ms}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*2 )), "fps {d:0.4}", .{ud.ms / 1000*60}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*3 )), "frame {}", .{ud.frame}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*4 )), "camera {d:.8}, {d:.8}, {d:.8}", .{state.camera.pos.x, state.camera.pos.y, state.camera.pos.z}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*5 )), "mouse {d:.4} {d:.4}", .{mouse.x, mouse.y}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*6 )), "dimensions {d:.4} {d:.4} | real {d:.4} {d:.4}", .{w, h, real_w, real_h}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*7 )), "physical pos {d:.4} {d:.4}", .{state.player.physical_component.physical_pos.x, state.player.physical_component.physical_pos.y}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*8 )), "physical tile {} {}", .{physical_pos_decomposed.physical_tile.x, physical_pos_decomposed.physical_tile.y}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*9 )), "to real tile {} {}", .{real_tile.x, real_tile.y}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*10)), "vel {d:.5} {d:.5}", .{state.player.physical_component.velocity.x, state.player.physical_component.velocity.y}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*11)), "update  took {d:.8}ms", .{ms_taken_update}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*12)), "render  took {d:.8}ms", .{ms_taken_render}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*13)), "upscale took {d:.8}ms", .{ms_taken_upscale}, color);
            try renderer.add_text(Vector2f.from(5, real_h - (text_height*14)), "debug   took {d:.8}ms", .{static.ms_taken_debug_previous}, color);

            try renderer.flush_all();
        
            break :blk Application.perf.profile_end(profile);
        };

    }

    return true;
}

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
            for (str, 0..) |c, i| {

                // x and y are the bottom left of the quad
                const x: f32 = pos.x + @as(f32, @floatFromInt(i)) * char_width + @as(f32, @floatFromInt(i));
                const y: f32 = pos.y;
                
                // texture left and right
                const u_1: f32 = @as(f32, @floatFromInt(c%16)) * base_width + pad_left;
                const u_2: f32 = u_1 + base_width - pad_left - pad_right;
                // texture top and bottom. Note that the texture is invertex so the mat here is also inverted
                const v_1: f32 = (@as(f32, @floatFromInt(c/16)) + 1) * base_height - pad_bottom;
                const v_2: f32 = @as(f32, @floatFromInt(c/16)) * base_height + pad_top;

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
