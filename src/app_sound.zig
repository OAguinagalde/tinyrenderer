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
    sound: ?wav.Sound,
    rng: Random,
    keyboard_sound: Sound,
} = undefined;

pub fn main() !void {
    try Application.run();
}

pub fn init(allocator: std.mem.Allocator) anyerror!void {
    state.rng = Random.init(@intCast(platform.timestamp()));
    state.temp_fba = std.heap.FixedBufferAllocator.init(try allocator.alloc(u8, 1024*1024*10));
    state.sound = null;
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

    const selected = if (false) state.rng.u() % wav_files.len else wav_files.len - 1;
    for (wav_files, 0..) |wav_file, i| {
        const bytes = Application.read_file_sync(state.temp_fba.allocator(), wav_file) catch continue;
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

/// every value in seconds
const EnvelopeDescription = struct {
    attack_amplitude: f64,
    attack_time: f64,
    decay_time: f64,
    sustain_amplitude: f64,
    release_time: f64,

    pub fn calculate_amplitude(envelope: EnvelopeDescription, time: f64, envelope_start: ?f64, envelope_end: ?f64) ?f64 {
        
        var amplitude: f64 = 0.0;
        
        if (envelope_start) |start| {
            const time_since_evelope_start = time - start;

            if (envelope_end) |end| {
                const time_since_envelope_end = time - end;

                amplitude = envelope.sustain_amplitude + ((time_since_envelope_end / envelope.release_time) * (-envelope.sustain_amplitude));
                
                // the envelope ended
                if (amplitude <= 0.0001) return null;

            }
            else {
                if (time_since_evelope_start <= envelope.attack_time) {
                    amplitude = (time_since_evelope_start/envelope.attack_time) * envelope.attack_amplitude;
                }
                else if (time_since_evelope_start <= envelope.decay_time) {
                    const time_in_decay_zone = time_since_evelope_start - envelope.attack_time;
                    const amplitude_difference = envelope.sustain_amplitude - envelope.attack_amplitude;
                    amplitude = envelope.attack_amplitude - ((time_in_decay_zone / envelope.decay_time * amplitude_difference));
                }
                else {
                    amplitude = envelope.sustain_amplitude;
                }
            }
        }

        return amplitude;
    }
};

const Sound = struct {
    envelope: EnvelopeDescription,
    start: ?f64,
    end: ?f64,
    index: usize,
};

pub fn update(ud: *platform.UpdateData) anyerror!bool {
    const h: f32 = @floatFromInt(ud.pixel_buffer.height);
    const w: f32 = @floatFromInt(ud.pixel_buffer.width);
    ud.pixel_buffer.clear(platform.OutPixelType.from(RGBA, color.black));
    state.time += ud.ms;

    state.keyboard_sound.envelope = EnvelopeDescription {
        .attack_amplitude = 0.98,
        .sustain_amplitude = 0.7,
        .attack_time = 1,
        .decay_time = 0.5,
        .release_time = 1,
    };

    state.keyboard_sound.envelope = EnvelopeDescription {
        .attack_amplitude = 1.0,
        .sustain_amplitude = 1.0,
        .attack_time = 0.01,
        .decay_time = 0.0,
        .release_time = 0.15,
    };

    const keys: []const u8 = "ZSXCFVGBNJMK,L./";
    for (keys, 0..) |key, i| {
        if (ud.key_pressed(key)) {
            state.keyboard_sound.index = i;
            state.keyboard_sound.start = ud.time_since_start;
            state.keyboard_sound.end = null;
        }
        else if (ud.key_pressing(key)) {
            // nothing to do
        }
        else if (ud.key_released(key)) {
            state.keyboard_sound.end = ud.time_since_start;
        }
    }
    
    if (state.keyboard_sound.start != null) {
        const key_f64: f64 = @floatFromInt(state.keyboard_sound.index);
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
            \\        |   |   |   | |   |   |   |   | |   | |   |         
            \\      S |   |   | F | | G |   |   | J | | K | | L |   |     
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
    text_renderer.render_all(
        ud.pixel_buffer,
        M33.orthographic_projection(0, w, h, 0),
        M33.viewport(0, 0, w, h)
    );

    return true;
}

/// converts ferequency Hz to angular velocity
pub inline fn convert(hertz: f64) f64 {
    return hertz * 2.0 * std.math.pi; 
}

const WaveType = enum {
    Sine,
    Square,
    Triangle,
    SawSlow,
    SawFast,
    Noise
};

pub inline fn wave(comptime wave_type: WaveType, time: f64, freq_hertz: f64) f64 {
    return switch (wave_type) {
        .Sine => std.math.sin(time * convert(freq_hertz)),
        .Square => if (std.math.sin(time * convert(freq_hertz)) > 0.0) 1.0 else 0.0,
        .Triangle => std.math.asin(std.math.sin(time * convert(freq_hertz))) * (2.0 / std.math.pi),
        .SawSlow => blk: {
            var result: f64 = 0;
            var n: f64 = 1;
            while (n < 40.0) : (n+=1) result += (std.math.sin(n * time * convert(freq_hertz))) / n;
            break :blk result * (2.0 / std.math.pi);
        },
        .SawFast => (2.0 / std.math.pi) * (freq_hertz * std.math.pi * (std.math.mod(f64, time, 1.0 / freq_hertz) catch unreachable) - (std.math.pi / 2.0)),
        .Noise => (state.rng.f() * 2.0) - 1.0,
    };
}

pub fn produce_sound(time: f64) f64 {
    
    const sample_keyboard = blk: {
        const volume: f64 = 0.5;
        if (state.keyboard_sound.envelope.calculate_amplitude(time, state.keyboard_sound.start, state.keyboard_sound.end)) |envelope| {
            const osc0 = wave(.SawSlow, time, state.frequency_output * 0.5);
            const osc1 = wave(.Sine, time, state.frequency_output * 1.0);
            break :blk envelope * (osc0 + osc1) * volume;
        }
        else break :blk 0;
    };

    if (state.sound) |sound| {
        const sample_audio: f64 = switch (sound.channel_count) {
            1 => blk: {
                // sample0: i16, sample1: i16, ...
                const samples: []const i16 = @as([*]const i16, @alignCast(@ptrCast(sound.raw.ptr)))[0..@divExact(sound.raw.len, 2)];
                const sound_duration_seconds: f64 = @floatFromInt(@divFloor(samples.len, sound.sample_rate));
                // NOTE @mod so that it loops back
                const actual_time = @mod(time, sound_duration_seconds);
                const samples_per_second_f: f64 = @floatFromInt(sound.sample_rate);
                const next_sample_index: usize = @intFromFloat(samples_per_second_f * actual_time);
                
                const sample = samples[next_sample_index];
                const sample_f: f64 = @floatFromInt(sample);
                const max_i16_f: f64 = @floatFromInt(std.math.maxInt(i16));
                const sample_final: f64 = sample_f/max_i16_f;
                break :blk sample_final;
            },
            2 => blk: {
                // sample0 {channel0: i16, channel1: i16}, sample1 {channel0: i16, channel1: i16}, ...
                const samples: []const i16 = @as([*]const i16, @alignCast(@ptrCast(sound.raw.ptr)))[0..@divExact(sound.raw.len, 2)];
                const sound_duration_seconds: f64 = @floatFromInt(@divFloor(samples.len, sound.sample_rate));
                // NOTE @mod so that it loops back
                const actual_time = @mod(time, sound_duration_seconds);
                const samples_per_second_f: f64 = @floatFromInt(sound.sample_rate);
                const next_sample_index: usize = @intFromFloat(samples_per_second_f * actual_time);
                
                // for now only care about channel 0
                const sample = samples[@mod(next_sample_index*2, samples.len)];
                const sample_f: f64 = @floatFromInt(sample);
                const max_i16_f: f64 = @floatFromInt(std.math.maxInt(i16));
                const sample_final: f64 = sample_f/max_i16_f;
                break :blk sample_final;
            },
            else => @panic("AAAAAAAAAAAH no more channeeeellss!!! AAAAAAHHH"),
        };

        const sample_all_mixed = sample_audio + sample_keyboard;

        return sample_all_mixed;
    }
    else return sample_keyboard;
}