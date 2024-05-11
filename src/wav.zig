/// This is a WAV file reader

const std = @import("std");
const core = @import("core.zig");

/// NOTE Every number is little endian
const RiffChunk = extern struct {
    /// Every RIFF file starts with the "RIFF" ascii string
    id: [4]u8,
    /// The size of the RIFF chunk (minus this RiffChunk itself)
    size: u32,
    /// for .wav files, this should always be "WAVE"
    format: [4]u8,
};

comptime { if (@sizeOf(RiffChunk) != 12) @compileError("wrong size!"); }

/// NOTE Every number is little endian
const RiffSubChunk = extern struct {
    /// Identifies the following bytes. It could be "data", "fmt ", "LIST"...
    id: [4]u8,
    /// The size of the data following this RiffSubChunk
    /// For example, the "fmt " sub chunk is 16 bytes, so this should be 16.
    /// Note that those 16 DO NOT include the 8 bytes of the RiffSubChunk itself
    size: u32,
};

comptime { if (@sizeOf(RiffSubChunk) != 8) @compileError("wrong size!"); }

/// NOTE Every number is little endian
const RiffSubChunkFmt = extern struct {
    /// format type. 1-PCM, 3- IEEE float, 6 - 8bit A law, 7 - 8bit mu law
    type: u16,
    channel_count: u16,
    /// blocks per second
    sample_rate: u32,
    /// SampleRate * NumChannels * BitsPerSample/8
    byte_rate: u32,
    /// NumChannels * BitsPerSample/8
    block_align: u16,
    bits_per_sample: u16,
};

comptime { if (@sizeOf(RiffSubChunkFmt) != 16) @compileError("wrong size!"); }

pub fn from_bytes(allocator: std.mem.Allocator, bytes: [] const u8) !Sound {
    
    var file_byte_index: usize = 0;

    // `.wav` files use the RIFF format (Resource Interchange File Format).
    // RIFF files start with the RiffChunk.
    // RIFF files of type WAVE always havea at least 2 parts (called sub-chunks): The "fmt " and the "data" sub chunks
    // The "fmt " sub-chunk describes the format of the sound information in the "data" sub-chunk 
    // The "data " sub-chunk contains the raw sound data
    // There might be other sub chunks in there but we ignore those
    // Every sub chunk starts with a header RiffSubChunk of 8 bytes followed by the data pertaining the sub chunk itself

    // Every RIFF file starts with the RIFF chunk
    var riff_header: RiffChunk = undefined;
    core.value(&riff_header, bytes[file_byte_index..@sizeOf(RiffChunk)]);
    file_byte_index += @sizeOf(RiffChunk);
    riff_header.size = std.mem.littleToNative(u32, riff_header.size);
    std.log.debug("riff chunk: [{}]u8 \"{s}\"", .{riff_header.size, riff_header.format});
    // Every RIFF file must start with the RIFF ascii string
    if (!std.mem.eql(u8, &riff_header.id, "RIFF")) return error.NotARiffFile;
    // Every RIFF WAVE file is of format WAVE
    if (!std.mem.eql(u8, &riff_header.format, "WAVE")) return error.NotAWaveFile;
    
    // Loop through the subchunks of the RIFF file until we have found the
    // subchunks we care about: the "fmt " and the "data" chunks
    var wave_fmt: ?RiffSubChunkFmt = null;
    var data_bytes: ?[]const u8 = null;
    while ((wave_fmt == null or data_bytes == null) and file_byte_index < bytes.len) {

        var subchunk: RiffSubChunk = undefined;
        core.value(&subchunk, bytes[file_byte_index..file_byte_index+@sizeOf(RiffSubChunk)]);
        subchunk.size = std.mem.littleToNative(u32, subchunk.size);

        std.log.debug("riff subchunk: [{}]u8 \"{s}\"", .{subchunk.size, subchunk.id});
        file_byte_index += @sizeOf(RiffSubChunk);

        if (std.mem.eql(u8, &subchunk.id, "fmt ")) {

            if (subchunk.size != 16) return error.invalidFmtSubChunkSize;

            var fmt: RiffSubChunkFmt = undefined;
            core.value(&fmt, bytes[file_byte_index..file_byte_index+@sizeOf(RiffSubChunkFmt)]);
            fmt.bits_per_sample = std.mem.littleToNative(u16, fmt.bits_per_sample);
            fmt.block_align = std.mem.littleToNative(u16, fmt.block_align);
            fmt.channel_count = std.mem.littleToNative(u16, fmt.channel_count);
            fmt.byte_rate = std.mem.littleToNative(u32, fmt.byte_rate);
            fmt.sample_rate = std.mem.littleToNative(u32, fmt.sample_rate);
            wave_fmt = fmt;

        }
        else if (std.mem.eql(u8, &subchunk.id, "data")) {

            data_bytes = bytes[file_byte_index..file_byte_index+@as(usize, @intCast(subchunk.size))];

        }
        else {} // ignore the sub chunk

        file_byte_index += @intCast(subchunk.size);
    }

    if (wave_fmt == null or data_bytes == null) return error.invalidWaveFile;

    const sound_data = try allocator.alloc(u8, data_bytes.?.len);
    @memcpy(sound_data, data_bytes.?);
    std.log.debug(".wav read: [{}]u8 {?}", .{data_bytes.?.len, wave_fmt.?});

    return .{
        .channel_count = @intCast(wave_fmt.?.channel_count),
        .sample_rate = @intCast(wave_fmt.?.sample_rate),
        .byte_rate = @intCast(wave_fmt.?.byte_rate),
        .block_align = @intCast(wave_fmt.?.block_align),
        .bits_per_sample = @intCast(wave_fmt.?.bits_per_sample),
        .raw = sound_data,
    };
}

pub const Sound = struct {
    channel_count: usize,
    sample_rate: usize,
    byte_rate: usize,
    block_align: usize,
    bits_per_sample: usize,
    /// a slice of bytes that contains the raw data of the audio track
    raw: []const u8,
};
