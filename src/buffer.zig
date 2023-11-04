const std = @import("std");
const Vector2f = @import("math.zig").Vector2f;
const Vector2i = @import("math.zig").Vector2i;

pub fn Buffer2D(comptime T: type) type {
    return struct {
        
        const Self = @This();
        
        data: []T,
        width: usize,
        height: usize,
        
        pub fn from(data: []T, width: usize) Self {
            return .{
                .data = data,
                .width = width,
                .height = @divExact(data.len, width)
            };
        }

        pub fn set(self: Self, x: usize, y: usize, item: T) void {
            self.data[x + self.width * y] = item;
        }
        
        pub fn get(self: Self, x: usize, y: usize) T {
            return self.data[x + self.width*y];
        }
        
        pub fn at(self: Self, x: usize, y: usize) *T {
            return &self.data[x + self.width*y];
        }

        /// set `point_is_normalized` to true if the `point` is normalized to the range [0..1]
        pub fn point_sample(self: Self, comptime point_is_normalized: bool, point: Vector2f) T {
            const tx = if (point_is_normalized) point.x * @as(f32, @floatFromInt(self.width)) else point.x;
            const ty = if (point_is_normalized) point.y * @as(f32, @floatFromInt(self.height)) else point.y;
            const x = std.math.clamp(@as(usize, @intFromFloat(tx)), 0, self.width-1);
            const y = std.math.clamp(@as(usize, @intFromFloat(ty)), 0, self.height-1);
            return self.data[x + self.width*y];
        }

        /// uses `scale_raw` and `add_raw` from T
        /// set `point_is_normalized` to true if the `point` is normalized to the range [0..1]
        pub fn bilinear_sample(self: Self, comptime point_is_normalized: bool, point: Vector2f) T {
            const tx = if (point_is_normalized) point.x * @as(f32, @floatFromInt(self.width)) else point.x;
            const ty = if (point_is_normalized) point.y * @as(f32, @floatFromInt(self.height)) else point.y;
            
            const x_min: usize = @max(@as(usize, @intFromFloat(@floor(tx-0.5))), 0);
            const x_max: usize = @min(@as(usize, @intFromFloat(@floor(tx+0.5))), self.width-1);
            const y_min: usize = @max(@as(usize, @intFromFloat(@floor(ty-0.5))), 0);
            const y_max: usize = @min(@as(usize, @intFromFloat(@floor(ty+0.5))), self.height-1);

            if (x_min == x_max) {
                if (y_min == y_max) {
                    // a corner of the texture
                    const sampled_color = self.data[y_min*self.width+x_min];
                    return sampled_color;
                }
                else {
                    // left or right border of texture
                    const color_bottom = self.data[y_min*self.width+x_min];
                    const color_top = self.data[y_max*self.width+x_min];
                    
                    const weight_y: f32 = ty - (@floor(ty-0.5) + 0.5);
                    
                    const interpolated_color = color_bottom.scale_raw(1 - weight_y).add_raw(color_top.scale_raw(weight_y));
                    return interpolated_color;
                }
            }
            else if (y_min == y_max) {
                // top or bottom border of texture
                const color_left = self.data[y_min*self.width+x_min];
                const color_right = self.data[y_min*self.width+x_max];
                
                const weight_x: f32 = tx - (@floor(tx-0.5) + 0.5);
                
                const interpolated_color = color_left.scale_raw(1 - weight_x).add_raw(color_right.scale_raw(weight_x));
                return interpolated_color;
            }
            else {
                const color_bottom_left = self.data[y_min*self.width+x_min];
                const color_bottom_right = self.data[y_min*self.width+x_max];
                const color_top_left = self.data[y_max*self.width+x_min];
                const color_top_right = self.data[y_max*self.width+x_max];
                
                const weight_x: f32 = tx - (@floor(tx-0.5) + 0.5);
                const weight_y: f32 = ty - (@floor(ty-0.5) + 0.5);
                
                const interpolated_color_1 = color_bottom_left.scale_raw(1 - weight_x).add_raw(color_bottom_right.scale_raw(weight_x));
                const interpolated_color_2 = color_top_left.scale_raw(1 - weight_x).add_raw(color_top_right.scale_raw(weight_x));
                const interpolated_color_3 = interpolated_color_1.scale_raw(1 - weight_y).add_raw(interpolated_color_2.scale_raw(weight_y));

                return interpolated_color_3;
            }
        }

        pub fn clear(self: *Self, value: T) void {
            for (self.data) |*v| { v.* = value; }
        }
        
        pub fn line(self: *Self, a: Vector2i, b: Vector2i, color: T) void {
    
            if (a.x == b.x and a.y == b.y) {
                // a point
                self.set(@intCast(a.x), @intCast(a.y), color);
                return;
            }

            const delta = a.substract(b);

            if (delta.x == 0) {
                // vertical line drawn bottom to top
                var top = &a;
                var bottom = &b;
                if (delta.y < 0) {
                    top = &b;
                    bottom = &a;
                }

                const x = a.x;
                var y = bottom.y;
                while (y != top.y + 1) : (y += 1) {
                    self.set(@intCast(x), @intCast(y), color);
                }
                return;
            }
            else if (delta.y == 0) {
                // horizontal line drawn left to right
                var left = &a;
                var right = &b;
                if (delta.x > 0) {
                    left = &b;
                    right = &a;
                }

                const y = a.y;
                var x = left.x;
                while (x != right.x + 1) : (x += 1) {
                    self.set(@intCast(x), @intCast(y), color);
                }
                return;
            }

            const delta_x_abs = @abs(delta.x);
            const delta_y_abs = @abs(delta.y);

            if (delta_x_abs == delta_y_abs) {
                if (a.y < b.y) { // draw a to b so that memory is modified in the "correct order"
                    const diff: i32 = if (a.x < b.x) 1 else -1;
                    var x = a.x;
                    var y = a.y;
                    while (x != b.x) {
                        self.set(@intCast(x), @intCast(y), color);
                        x += diff;
                        y += 1;
                    }
                }
                else { // draw b to a so that memory is modified in the "correct order"
                    const diff: i32 = if (a.x < b.x) -1 else 1;
                    var x = b.x;
                    var y = b.y;
                    while (x != a.x) {
                        self.set(@intCast(x), @intCast(y), color);
                        x += diff;
                        y += 1;
                    }
                }
                return;
            }
            
            if (delta_x_abs > delta_y_abs) {
                // draw horizontally
                
                var left = &a;
                var right = &b;

                if (delta.x > 0) {
                    left = &b;
                    right = &a;
                }

                const increment = 1 / @as(f32, @floatFromInt(delta_x_abs));
                var percentage_of_line_done: f32 = 0;
                
                var x = left.x;
                while (x <= right.x) : (x += 1) {
                    // linear interpolation to figure out `y`
                    const y = left.y + @as(i32, @intFromFloat(@as(f32, @floatFromInt(right.y - left.y)) * percentage_of_line_done));
                    self.set(@intCast(x), @intCast(y), color);
                    percentage_of_line_done += increment;
                }
            }
            else if (delta_x_abs < delta_y_abs) {
                // draw vertically

                var top = &a;
                var bottom = &b;

                if (delta.y > 0) {
                    top = &b;
                    bottom = &a;
                }

                const increment = 1 / @as(f32, @floatFromInt(delta_y_abs));
                var percentage_of_line_done: f32 = 0;

                var y = top.y;
                while (y <= bottom.y) : (y += 1) {
                    const x = top.x + @as(i32, @intFromFloat(@as(f32, @floatFromInt(bottom.x - top.x)) * percentage_of_line_done));
                    self.set(@intCast(x), @intCast(y), color);
                    percentage_of_line_done += increment;
                }

            }
            else unreachable;
        }
    };
}
