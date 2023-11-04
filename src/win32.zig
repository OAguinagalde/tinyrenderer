const std = @import("std");

/// The actual `windows.h` API
pub const c = @import("win32").everything;

pub const falsei32: i32 = 0;
pub const call_convention = std.os.windows.WINAPI;

/// In windows pixels are stored as BGRA
pub const RGBA = extern struct {
    b: u8,
    g: u8,
    r: u8,
    a: u8,
    
    comptime { std.debug.assert(@sizeOf(@This()) == @sizeOf(u32)); }

    pub fn scale(self: RGBA, factor: f32) RGBA {
        return RGBA {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
            .a = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.a)) * factor))),
        };
    }

    pub fn blend(c1: RGBA, c2: RGBA) RGBA {
        const a1: f32 = @as(f32, @floatFromInt(c1.a)) / 255;
        const result = RGBA {
            .r = @intFromFloat((@as(f32, @floatFromInt(c1.r))/255*a1 + @as(f32, @floatFromInt(c2.r))/255*(1-a1))*255),
            .g = @intFromFloat((@as(f32, @floatFromInt(c1.g))/255*a1 + @as(f32, @floatFromInt(c2.g))/255*(1-a1))*255),
            .b = @intFromFloat((@as(f32, @floatFromInt(c1.b))/255*a1 + @as(f32, @floatFromInt(c2.b))/255*(1-a1))*255),
            .a = @intFromFloat((@as(f32, @floatFromInt(c1.a))/255*a1 + @as(f32, @floatFromInt(c2.a))/255*(1-a1))*255),
        };
        return result;
    }
};

pub fn rgb(r: u8, g: u8, b: u8) RGBA {
    return RGBA {
        .a = 255, .r = r, .g = g, .b = b
    };
}

pub fn rgba(r: u8, g: u8, b: u8, a: u8) RGBA {
    return RGBA {
        .a = a, .r = r, .g = g, .b = b
    };
}
