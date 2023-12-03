const std = @import("std");

pub const RGBA = extern struct {
    r: u8 align(1),
    g: u8 align(1),
    b: u8 align(1),
    a: u8 align(1),
    comptime { std.debug.assert(@sizeOf(@This()) == 4); }
    pub inline fn make(r: u8, g: u8, b: u8, a: u8) RGBA {
        return RGBA { .r = r, .g = g, .b = b, .a = a };
    }
    pub fn scale(self: RGBA, factor: f32) RGBA {
        return RGBA {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
            .a = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.a)) * factor))),
        };
    }
    pub fn add(c1: RGBA, c2: RGBA) RGBA {
        const result = RGBA {
            .r = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.r))/255 + @as(f32, @floatFromInt(c2.r))/255)*255))),
            .g = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.g))/255 + @as(f32, @floatFromInt(c2.g))/255)*255))),
            .b = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.b))/255 + @as(f32, @floatFromInt(c2.b))/255)*255))),
            .a = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.a))/255 + @as(f32, @floatFromInt(c2.a))/255)*255))),
        };
        return result;
    }
    pub fn scale_raw(self: RGBA, factor: f32) RGBA {
        return RGBA {
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * factor),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * factor),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * factor),
            .a = @intFromFloat(@as(f32, @floatFromInt(self.a)) * factor),
        };
    }
    /// This assumes that the sum of any channel is inside the range of u8, there is no checks!
    pub fn add_raw(c1: RGBA, c2: RGBA) RGBA {
        const result = RGBA {
            .r = c1.r + c2.r,
            .g = c1.g + c2.g,
            .b = c1.b + c2.b,
            .a = c1.a + c2.a,
        };
        return result;
    }
    /// where `c2` is the background color
    /// https://learnopengl.com/Advanced-OpenGL/Blending
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
    pub fn multiply(c1: RGBA, c2: RGBA) RGBA {
        const result = RGBA {
            .r = @intFromFloat( @as(f32, @floatFromInt(c1.r)) * (@as(f32, @floatFromInt(c2.r)) / 255)),
            .g = @intFromFloat( @as(f32, @floatFromInt(c1.g)) * (@as(f32, @floatFromInt(c2.g)) / 255)),
            .b = @intFromFloat( @as(f32, @floatFromInt(c1.b)) * (@as(f32, @floatFromInt(c2.b)) / 255)),
            .a = @intFromFloat( @as(f32, @floatFromInt(c1.a)) * (@as(f32, @floatFromInt(c2.a)) / 255)),
        };
        return result;
    }
    pub fn mean(c1: RGBA, c2: RGBA, c3: RGBA, c4: RGBA) RGBA {
        return RGBA {
            .r = @as(u8, @intCast((@as(u16, @intCast(c1.r)) + @as(u16, @intCast(c2.r)) + @as(u16, @intCast(c3.r)) + @as(u16, @intCast(c4.r))) / 4)),
            .g = @as(u8, @intCast((@as(u16, @intCast(c1.g)) + @as(u16, @intCast(c2.g)) + @as(u16, @intCast(c3.g)) + @as(u16, @intCast(c4.g))) / 4)),
            .b = @as(u8, @intCast((@as(u16, @intCast(c1.b)) + @as(u16, @intCast(c2.b)) + @as(u16, @intCast(c3.b)) + @as(u16, @intCast(c4.b))) / 4)),
            .a = @as(u8, @intCast((@as(u16, @intCast(c1.a)) + @as(u16, @intCast(c2.a)) + @as(u16, @intCast(c3.a)) + @as(u16, @intCast(c4.a))) / 4)),
        };
    }
    pub fn from(comptime T: type, color: T) RGBA {
        return switch (T) {
            BGRA => RGBA { .r = color.r, .g = color.g, .b = color.b, .a = color.a },
            RGB => RGBA { .r = color.r, .g = color.g, .b = color.b, .a = 255 },
            RGBA => color,
            else => @compileError("Conversion from " ++ T ++ " -> " ++ RGBA ++ " not implemented!"),
        };
    }
};

pub const RGB = extern struct {
    r: u8 align(1),
    g: u8 align(1),
    b: u8 align(1),
    
    comptime { std.debug.assert(@sizeOf(@This()) == 3); }
    
    pub inline fn from(r: u8, g: u8, b: u8) RGB {
        return RGB { .r = r, .g = g, .b = b, };
    }
    
    pub fn scale(self: RGB, factor: f32) RGB {
        return RGB {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
        };
    }
    pub fn scale_raw(self: RGB, factor: f32) RGB {
        return RGB {
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * factor),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * factor),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * factor),
        };
    }
    /// This assumes that the sum of any channel is inside the range of u8, there is no checks!
    pub fn add_raw(c1: RGB, c2: RGB) RGB {
        const result = RGB {
            .r = c1.r + c2.r,
            .g = c1.g + c2.g,
            .b = c1.b + c2.b,
        };
        return result;
    }
};

pub const BGR = extern struct {
    b: u8 align(1),
    g: u8 align(1),
    r: u8 align(1),
    comptime { std.debug.assert(@sizeOf(@This()) == 3); }
    pub inline fn make(r: u8, g: u8, b: u8) BGR {
        return BGR { .r = r, .g = g, .b = b };
    }
    pub fn from(comptime T: type, color: T) BGR {
        return switch (T) {
            BGRA, RGBA, RGB => BGR { .r = color.r, .g = color.g, .b = color.b },
            else => @compileError("Conversion from " ++ T ++ " -> " ++ BGR ++ " not implemented!"),
        };
    }
};

/// In windows pixels are stored as BGRA
pub const BGRA = extern struct {
    b: u8 align(1),
    g: u8 align(1),
    r: u8 align(1),
    a: u8 align(1),
    comptime { std.debug.assert(@sizeOf(@This()) == 4); }

    pub inline fn make(r: u8, g: u8, b: u8, a: u8) BGRA {
        return BGRA { .r = r, .g = g, .b = b, .a = a };
    }

    pub fn scale(self: BGRA, factor: f32) BGRA {
        return BGRA {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
            .a = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.a)) * factor))),
        };
    }

    pub fn blend(c1: BGRA, c2: BGRA) BGRA {
        const a1: f32 = @as(f32, @floatFromInt(c1.a)) / 255;
        const result = BGRA {
            .r = @intFromFloat((@as(f32, @floatFromInt(c1.r))/255*a1 + @as(f32, @floatFromInt(c2.r))/255*(1-a1))*255),
            .g = @intFromFloat((@as(f32, @floatFromInt(c1.g))/255*a1 + @as(f32, @floatFromInt(c2.g))/255*(1-a1))*255),
            .b = @intFromFloat((@as(f32, @floatFromInt(c1.b))/255*a1 + @as(f32, @floatFromInt(c2.b))/255*(1-a1))*255),
            .a = @intFromFloat((@as(f32, @floatFromInt(c1.a))/255*a1 + @as(f32, @floatFromInt(c2.a))/255*(1-a1))*255),
        };
        return result;
    }

    pub fn tint(color: BGRA, other: BGRA) BGRA {
        return BGRA.make(
            @intFromFloat((@as(f32, @floatFromInt(color.r)) * @as(f32, @floatFromInt(other.r)))/256),
            @intFromFloat((@as(f32, @floatFromInt(color.g)) * @as(f32, @floatFromInt(other.g)))/256),
            @intFromFloat((@as(f32, @floatFromInt(color.b)) * @as(f32, @floatFromInt(other.b)))/256),
            @intFromFloat((@as(f32, @floatFromInt(color.a)) * @as(f32, @floatFromInt(other.a)))/256),
        );
    }

    pub fn from(comptime T: type, color: T) BGRA {
        return switch (T) {
            RGBA => BGRA { .r = color.r, .g = color.g, .b = color.b, .a = color.a },
            RGB => BGRA { .r = color.r, .g = color.g, .b = color.b, .a = 255 },
            BGR => BGRA { .r = color.r, .g = color.g, .b = color.b, .a = 255 },
            BGRA => color,
            else => @compileError("Conversion from " ++ T ++ " -> " ++ BGRA ++ " not implemented!"),
        };
    }
};
