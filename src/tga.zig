/// This is a TGA file reader
// http://www.paulbourke.net/dataformats/tga/
// https://www.gamers.org/dEngine/quake3/TGA.txt

const std = @import("std");
const core = @import("core.zig");
const Buffer2D = @import("buffer.zig").Buffer2D;

const BitsPerPixel = enum(u8) {
    RGB = 24,
    RGBA = 32
};

const DataTypeCode = enum(u8) {
    UncompressedRgb = 2,
    RunLengthEncodedRgb = 10,
};

const ColorMapSpecification = extern struct {
    /// index of first color map entry
    origin: i16 align(1),
    /// count of color map entries
    length: i16 align(1),
    /// Number of bits in color map entry - same as `bits_per_pixel`
    entry_size: u8 align(1),
};

const ImageDescriptorByte = extern struct {
    
    the_byte: u8 align(1),
    
    const Self = @This();

    /// number of attribute bits associated with each
    /// pixel.  For the Targa 16, this would be 0 or
    /// 1.  For the Targa 24, it should be 0.  For
    /// Targa 32, it should be 8.
    fn get_attribute_bits_per_pixel(self: Self) u4 {
        return @intCast(self.the_byte >> 4);
    }

    /// must be 0
    fn get_reserved(self: Self) u1 {
        return @intCast((self.the_byte | 0b00001000) >> 3);
    }

    /// 0 = Origin in lower left-hand corner
    /// 1 = Origin in upper left-hand corner
    fn get_screen_origin_bit(self: Self) u1 {
        return @intCast((self.the_byte | 0b00000100) >> 2);
    }

    /// 00 = non-interleaved.                        
    /// 01 = two-way (even/odd) interleaving.        
    /// 10 = four way interleaving.                  
    /// 11 = reserved.                               
    fn get_interleaving(self: Self) u2 {
        return @intCast(self.the_byte << 6);
    }

};

const ImageSpecification = extern struct {
    /// X coordinate of the lower left corner
    x_origin: i16 align(1),
    /// Y coordinate of the lower left corner
    y_origin: i16 align(1),
    /// width of the image in pixels
    width: i16 align(1),
    /// height of the image in pixels
    height: i16 align(1),
    /// number of bits in a pixel
    bits_per_pixel: BitsPerPixel align(1),
    image_descriptor: ImageDescriptorByte align(1),
};

/// Example of a TGA header, the first 18 bytes and it after being parsed
/// 
/// 00000000   00 00 0A 00 00 00 00 00 00 00 00 00 00 04 00 04  ................
/// 00000010   18 00 3F 37 45 58 3F 39 47 5A 3F 38 46 59 3F 37  ..?7EX?9GZ?8FY?7
/// 00000020   45 58 3F 37 44 5A 00 36 44 57 3F 37 45 58 3F 38  EX?7DZ.6DW?7EX?8
/// 00000030   46 59 00 36 42 5A 3F 35 41 59 00 36 42 5A 3F 37  FY.6BZ?5AY.6BZ?7
/// 00000040   43 5B 3F 37 45 58 3F 36 44 57 07 35 41 59 36 43  C[?7EX?6DW.5AY6C
/// 00000050   59 37 44 5A 38 45 5B 38 46 59 37 45 58 36 44 56  Y7DZ8E[8FY7EX6DV
/// 00000060   35 43 55 3F 37 45 58 3F 34 42 55 00 33 41 54 3F  5CU?7EX?4BU.3AT?
/// 00000070   32 40 53 00 33 41 54 3F 31 3F 52 3F 32 40 53 3F  2@S.3AT?1?R?2@S?
/// 
/// std.debug.print("{?}", .{header.*});
/// 
///     Header {
///         .id_length = 0,
///         .color_map_type = 0,
///         .data_type = DataTypeCode.RunLengthEncodedRgb,
///         .color_map_spec = ColorMapSpecification {
///             .origin = 0,
///             .length = 0,
///             .entry_size = 0
///         },
///         .image_spec = ImageSpecification {
///             .x_origin = 0,
///             .y_origin = 0,
///             .width = 1024,
///             .height = 1024,
///             .bits_per_pixel = BitsPerPixel.RGB,
///             .image_descriptor = ImageDescriptorByte { .the_byte = 0 }
///         }
///     };
///
const Header = extern struct {
    id_length: u8 align(1),
    color_map_type: u8 align(1),
    data_type: DataTypeCode align(1),
    color_map_spec: ColorMapSpecification align(1),
    image_spec: ImageSpecification align(1),
};

comptime { std.debug.assert(@sizeOf(BitsPerPixel) == 1); }
comptime { std.debug.assert(@sizeOf(DataTypeCode) == 1); }
comptime { std.debug.assert(@sizeOf(ColorMapSpecification) == 5); }
comptime { std.debug.assert(@sizeOf(ImageSpecification) == 10); }
comptime { std.debug.assert(@sizeOf(Header) == 18); }

pub fn from_bytes(comptime expected_pixel_type: type, allocator: std.mem.Allocator, bytes: [] const u8) !Buffer2D(expected_pixel_type) {
    var byte_index: usize = 0;
    var header: Header = undefined;
    core.value(&header, bytes[0..@sizeOf(Header)]);
    byte_index += @sizeOf(Header);
    
    // validate the file
    {
        // only care about RGB and RGBA images
        switch (@intFromEnum(header.image_spec.bits_per_pixel)) {
            24, 32 => {},
            else => return error.FileNotSupportedA,
        }
        // only care about non color mapped, non compressed files
        // 2023/06/29 and now also run length encoded rgb images!
        switch (@intFromEnum(header.data_type)) {
            2, 10 => {},
            else => return error.FileNotSupportedB,
        }
        // if its not color mapped why does it have a color map?
        if (header.color_map_type != 0) {
            // const color_map_size: usize = @intCast(@as(i16, @intCast(header.color_map_spec.entry_size)) * header.color_map_spec.length);
            return error.MalformedTgaFile;
        }
        // this shouldn't be a thing, probably...
        if (header.image_spec.width <= 0 or header.image_spec.height <= 0) return error.MalformedTgaFile;

    }

    const pixel_size = @divExact(@intFromEnum(header.image_spec.bits_per_pixel), 8);
    if (@sizeOf(expected_pixel_type) != pixel_size) return error.InvalidExpectedPixelType;

    const width: usize = @intCast(header.image_spec.width);
    const height: usize = @intCast(header.image_spec.height);

    // TODO If there was a color map that would have to be skipped as well but for now we just assume there is not
    // If there is a comment/id or whatever, skip it
    if (header.id_length > 0) byte_index += @intCast(header.id_length);

    // allocate and let the caller handle its lifetime
    const buffer: []u8 = try allocator.alloc(u8, width * height * @as(usize, @intCast(pixel_size)));
    switch (header.data_type) {
        DataTypeCode.UncompressedRgb => @memcpy(buffer, bytes[byte_index..byte_index+buffer.len]),
        DataTypeCode.RunLengthEncodedRgb => {
            var pixel_packet_header: u8 = undefined;
            var pixel_index: usize = 0;
            while (pixel_index < width * height) {
                pixel_packet_header = bytes[byte_index];
                byte_index += 1;
                const is_run_length_packet = (pixel_packet_header >> 7) == 1;
                const count: usize = @as(usize, @intCast(pixel_packet_header & 0b01111111)) + 1;
                // logger("header {b:0>8}: count {}, run_length {}", .{pixel_packet_header, count, is_run_length_packet});
                if (is_run_length_packet) {
                    const color: []const u8 = bytes[byte_index..byte_index+pixel_size];
                    std.debug.assert(color.len == pixel_size);
                    for (pixel_index .. pixel_index+count) |i| @memcpy(buffer[i*pixel_size..(i*pixel_size)+pixel_size], color[0..pixel_size]);
                    byte_index += pixel_size;
                }
                else {
                    std.debug.assert(bytes[byte_index..byte_index+(count*pixel_size)].len == pixel_size*count);
                    std.debug.assert(buffer[pixel_index*pixel_size .. (pixel_index*pixel_size) + (count*pixel_size)].len == bytes[byte_index..byte_index+(count*pixel_size)].len);
                    @memcpy(buffer[pixel_index*pixel_size .. (pixel_index*pixel_size) + (count*pixel_size)], bytes[byte_index..byte_index+(count*pixel_size)]);
                    byte_index += count*pixel_size;
                }
                pixel_index += count;
            }
            std.debug.assert(pixel_index == width * height);
        }
    }

    return Buffer2D(expected_pixel_type).from(std.mem.bytesAsSlice(expected_pixel_type, buffer), width);
}

// TODO decouple this from the platform layer, just pass the file itself already read to the `from_file` function
/// This can only read TGA files of data type `UncompressedRgb` (2) or `RunLengthEncodedRgb` (10)
pub fn from_file(comptime expected_pixel_type: type, allocator: std.mem.Allocator, file_path: [] const u8) !Buffer2D(expected_pixel_type) {
    var file = std.fs.cwd().openFile(file_path, .{}) catch return error.CantOpenFile;
    defer file.close();
    const stats = try file.stat();
    var buffer = try allocator.alloc(u8, stats.size);
    defer allocator.free(buffer);
    const read = try file.readAll(buffer);
    std.debug.assert(read == stats.size);
    return try from_bytes(expected_pixel_type, allocator, buffer);
}
        