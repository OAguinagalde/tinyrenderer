// Mostly based of this video:
// 
//     "Code-It-Yourself! Sound Synthesizer #1 - Basic Noises"
//     https://www.youtube.com/watch?v=tgamhuQnOkM
// 
// TODO implement sound API for wasm

const std = @import("std");
const builtin = @import("builtin");
const math = @import("math.zig");
const Vector2f = math.Vector2f;
const M33 = math.M33;
const RGBA = @import("pixels.zig").RGBA;
const TextRenderer = @import("text.zig").TextRenderer(platform.OutPixelType, 1024, 1);
const wav = @import("wav.zig");
const windows = @import("windows.zig");
const wasm = @import("wasm.zig");
const Random = @import("core.zig").Random;
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

var state: struct {
    temp_fba: std.heap.FixedBufferAllocator,
    time: f32 = 0,
    frequency_output: f64,
    sound: wav.Sound,
    rng: Random,
} = undefined;

pub fn main() !void {
    try Application.run();
}

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    state.rng = Random.init(@intCast(platform.timestamp()));
    state.temp_fba = std.heap.FixedBufferAllocator.init(try allocator.alloc(u8, 1024*1024*10));
    defer state.temp_fba.reset();

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

    const selected = state.rng.u() % wav_files.len;
    for (wav_files, 0..) |wav_file, i| {
        const bytes = try Application.read_file_sync(state.temp_fba.allocator(), wav_file);
        defer state.temp_fba.reset();
        const sound = try wav.from_bytes(allocator, bytes);
        if (i == selected) state.sound = sound;
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

const color = struct {
    const white = RGBA.from(RGBA, @bitCast(@as(u32, 0xffffffff)));
    const black = RGBA.from(RGBA, @bitCast(@as(u32, 0x00000000)));
    const cornflowerblue = RGBA.from(RGBA, @bitCast(@as(u32, 0x6495ed)));
};

pub fn update(ud: *platform.UpdateData) anyerror!bool {
    const h: f32 = @floatFromInt(ud.pixel_buffer.height);
    const w: f32 = @floatFromInt(ud.pixel_buffer.width);
    ud.pixel_buffer.clear(platform.OutPixelType.from(RGBA, color.black));
    state.time += ud.ms;

    for (ud.pixel_buffer.data) |*p| {
        p.* = if (state.rng.f()>0.5) platform.OutPixelType.from(RGBA, @bitCast(@as(u32, 0x44444444))) else platform.OutPixelType.from(RGBA, @bitCast(@as(u32, 0xaaaaaaaa)));
    }

    var a: u64 = 0;
    var b: u64 = 0;
    for (0..10000) |_| { if (state.rng.f()>0.5) a += 1 else b += 1; }

    var pressed_key: ?usize = null;
    const keys: []const u8 = "ZSXCFVGBNJMK,L./";
    for (keys, 0..) |key, i| {
        if (ud.key_pressing(key)) pressed_key = i;
    }

    if (pressed_key) |key| {
        const key_f64: f64 = @floatFromInt(key);
        const octave_base_frequency: f64 = 110; // A2
        const _12th_root_of_2: f64 = std.math.pow(f64, 2.0, 1.0/12.0);
        state.frequency_output = std.math.pow(f64, _12th_root_of_2, key_f64) * octave_base_frequency;
    }
    else state.frequency_output = 0;

    var text_renderer = try TextRenderer.init(ud.allocator);
    const text_height = text_renderer.height() + 1;
    
    // Render the keyboard on screen
    {
        const ui: []const u8 =
            \\        |   |   |   | |   |   |   |   | |   | |   |   |   | 
            \\      S |   |   | F | | G |   |   | J | | K | | L |   |   | 
            \\|   |___|   |   |___| |___|   |   |___| |___| |___|   |   |_
            \\|     |     |     |     |     |     |     |     |     |     
            \\|  Z  |  X  |  C  |  V  |  B  |  N  |  M  |  ,  |  .  |  /  
            \\|_____|_____|_____|_____|_____|_____|_____|_____|_____|_____
        ;
        var token_iterator = std.mem.tokenizeAny(u8, ui, "\n\r");
        var height: f32 = h - (text_height*6);
        while (token_iterator.next()) |token| {
            const length_of_line = @as(f32, @floatFromInt(token.len))*(text_renderer.width()+1.0);
            try text_renderer.print(Vector2f.from((w/2.0) - (length_of_line/2.0), height), "{s}", .{token}, color.white);
            height -= text_height;
        }
    }
    
    try text_renderer.print(Vector2f.from(1, h - (text_height*1)), "ms {d: <9.2}", .{ud.ms}, color.white);
    try text_renderer.print(Vector2f.from(1, h - (text_height*2)), "frame {}", .{ud.frame}, color.white);
    try text_renderer.print(Vector2f.from(1, h - (text_height*3)), "rng f64 {d: <9.5}", .{state.rng.f()}, color.white);
    try text_renderer.print(Vector2f.from(1, h - (text_height*4)), "rng u64 {}", .{state.rng.u()}, color.white);
    try text_renderer.print(Vector2f.from(1, h - (text_height*5)), "a {}", .{a}, color.white);
    try text_renderer.print(Vector2f.from(1, h - (text_height*6)), "b {}", .{b}, color.white);
    text_renderer.render_all(
        ud.pixel_buffer,
        M33.orthographic_projection(0, w, h, 0),
        M33.viewport(0, 0, w, h)
    );

    return true;
}

pub fn produce_sound(time: f64) f64 {
    // const bits_per_sample = state.sound.bits_per_sample;
    // const samples_per_second = state.sound.sample_rate;
    // return std.math.sin(time * 2 * 3.14159 * state.frequency_output) * 0.5;

    // play the song
    const samples: []const i16 = @as([*]const i16, @alignCast(@ptrCast(state.sound.raw.ptr)))[0..@divExact(state.sound.raw.len, 2)];
    const samples_per_second_f: f64 = @floatFromInt(state.sound.sample_rate);
    const max_i16_f: f64 = @floatFromInt(std.math.maxInt(i16));
    const sound_duration_seconds: f64 = @floatFromInt(@divFloor(samples.len, state.sound.sample_rate));
    const actual_time = @mod(time, sound_duration_seconds);
    const next_sample_index: usize = @intFromFloat(samples_per_second_f * actual_time);
    const sample = samples[@mod(next_sample_index*2, samples.len)];
    const sample_f: f64 = @floatFromInt(sample);
    return sample_f/max_i16_f;
}