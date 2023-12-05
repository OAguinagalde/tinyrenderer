const std = @import("std");
const core = @import("core.zig");
const math = @import("math.zig");
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vector4f = math.Vector4f;


pub const PhysicsConfig = struct {
    tile_size: i32,
    /// A granularity of 1 means that a physical tile represents a tile_size x tile_size tile.
    /// A granularity of 2 means that a physical tile represents a tile_size/2 x tile_size/2 tile.
    /// The more granularity, the slower the calculation, but more precise the collision detection
    /// This should probably always be 1, 2 or 4... Never 0
    granularity: i32,
    /// The pad values are used when dealing with collisions.
    /// For example, if moving right and collided, the physical position will be capped at `pad_right` rather than all the way at 0.99999999
    /// Consider using these values (top 0,3, bottom 0.9, left 0.3, right 0.3) as a good option for a 2d platformer
    ///     
    ///    (0,0),______________,
    ///         |    _0.3__    |
    ///         |   |      |   |
    ///         |  0.3    0.7  |
    ///         |   |_0.9__|   |
    ///         '--------------'(1,1)
    ///                      
    pad_left: f32,
    pad_right: f32,
    pad_bottom: f32,
    pad_top: f32,
    /// This is additive, so 0 for no gravity
    gravity: f32,
    /// This is multiplicative, so 1 for NO friction
    friction_floor: f32,
    /// This is multiplicative, so 1 for NO friction
    friction_air: f32,
};

pub fn PhysicalWorld(comptime config: PhysicsConfig, comptime is_collision: fn(Vector2i) callconv(.Inline) bool) type {
    return struct {

        const tile_size_f: f32 = @floatFromInt(config.tile_size);
        const granularity_f: f32 = @floatFromInt(config.granularity);
        
        pub const PhysicalObject = struct {
            velocity: Vector2f,
            physical_pos: Vector2f,
            weight: f32,

            pub inline fn from(pos: Vector2f, weight: f32) PhysicalObject {
                const physical_post = calculate_physical_pos(pos);
                return PhysicalObject {
                    .velocity = Vector2f.from(0,0),
                    .physical_pos = physical_post,
                    .weight = weight
                };
            }
        };

        pub const PhysicalPosDecomposed = struct {
            physical_tile: Vector2i,
            in_tile: Vector2f,

            pub inline fn from(physical_pos: Vector2f) PhysicalPosDecomposed {
                const temp_x = @floor(physical_pos.x);
                const temp_y = @floor(physical_pos.y);
                const tile_x: i32 = @intFromFloat(temp_x);
                const tile_y: i32 = @intFromFloat(temp_y);
                const in_tile_x = physical_pos.x - temp_x;
                const in_tile_y = physical_pos.y - temp_y;
                return PhysicalPosDecomposed {
                    .physical_tile = .{ .x = tile_x, .y = tile_y },
                    .in_tile = .{ .x = in_tile_x, .y = in_tile_y }
                };
            }
            
            pub inline fn to_physical_pos(self: PhysicalPosDecomposed) Vector2f {
                return Vector2f.from(
                    @as(f32, @floatFromInt(self.physical_tile.x)) + self.in_tile.x,
                    @as(f32, @floatFromInt(self.physical_tile.y)) + self.in_tile.y
                );
            }
        };


        /// if granularity != 1, then real tiles and tiles in the phyisical world wont match, so use this function to figure it out
        pub inline fn calculate_real_tile(physical_tile: Vector2i) Vector2i {
            return Vector2i.from(
                @divFloor(physical_tile.x, config.granularity),
                @divFloor(physical_tile.y, config.granularity),
            );
        }

        /// given a physical position, calculate the real position taking into account granularity and tile size
        pub inline fn calculate_real_pos(physical_pos: Vector2f) Vector2f {
            return Vector2f.from(
                @round(physical_pos.x * tile_size_f / granularity_f),
                @round(physical_pos.y * tile_size_f / granularity_f),
            );
        }

        /// given a real position, calculate the position in the context of the phyisical world
        pub inline fn calculate_physical_pos(pos: Vector2f) Vector2f {
            return Vector2f.from(
                pos.x / tile_size_f * granularity_f,
                pos.y / tile_size_f * granularity_f,
            );
        }

        const IsFloored = bool;
        
        pub fn apply(o: *PhysicalObject) IsFloored {
            
            // For now we dont keep track of whether it was previously in the floor or not, we just keep track of whether it is or not.
            var floor: bool = false;
            var pos = PhysicalPosDecomposed.from(o.physical_pos);
            var vel: Vector2f = o.velocity;
            
            // Apply gravity
            vel.y -= (config.gravity * o.weight);

            // Horizontal movement
            if (!std.math.approxEqAbs(f32, vel.x, 0, std.math.floatEps(f32))) {

                // The velocity is basically how many tiles this object is going to move in 1 update.
                // A velocity of (-3.2, 0) means that the particle is moving 3.2 tiles to the left.
                var total_movement = vel.x;

                // The reason I do `ceil` is because its always going to be at least 1 check:
                // Consider a cell |::____::| where the `:` is the space between the next cell and the `pad_{left|right}`.
                // If the object moves to the pad area, and the next tile is a collision, it needs to be moved.
                var tiles_to_check: u32 = @intFromFloat(@ceil(@abs(vel.x)));

                // wether the object moved across tiles or not
                var moved_tile: bool = false;

                // Move the object tile by tile until we collide, or until we moved the object all the way to its target position
                while (tiles_to_check > 0) : (tiles_to_check -= 1) {
                    
                    const movement_ammount = std.math.clamp(total_movement, -1.0, 1.0);
                    total_movement -= movement_ammount;

                    // First move...
                    pos.in_tile.x += movement_ammount;
                    
                    // ... and then check whether we collided (and if so, move back!)
                    if (pos.in_tile.x > config.pad_right) {
                        const right_tile = calculate_real_tile(Vector2i.from(pos.physical_tile.x + 1, pos.physical_tile.y));
                        if (is_collision(right_tile)) {
                            // If it collided, remove all its horizontal velocity and put "agains the wall".
                            pos.in_tile.x = config.pad_right;
                            vel.x = 0.0;
                            break;
                        }
                        else if (pos.in_tile.x > 1.0) {
                            pos.in_tile.x -= 1.0;
                            pos.physical_tile.x += 1;
                            moved_tile = true;
                        }
                    }
                    else if (pos.in_tile.x < config.pad_left) {
                        const left_tile = calculate_real_tile(Vector2i.from(pos.physical_tile.x - 1, pos.physical_tile.y));
                        if (is_collision(left_tile)) {
                            pos.in_tile.x = config.pad_left;
                            vel.x = 0.0;
                            break;
                        }
                        else if (pos.in_tile.x < 1.0) {
                            pos.in_tile.x += 1.0;
                            pos.physical_tile.x -= 1;
                            moved_tile = true;                    
                        }
                    }
                    
                }

                // If we moved tiles we need to check that we are not inside the padding vertically, since it may happen that after moving horizontally, suddenly there is a collision
                // on top of the object that wasnt there before (meaning that before moving the padding_top could be ignored but now that there is a collision cant be ignored)
                if (moved_tile) {
                    if (pos.in_tile.y < config.pad_bottom) {
                        const bottom_tile = calculate_real_tile(Vector2i.from(pos.physical_tile.x, pos.physical_tile.y - 1));
                        if (is_collision(bottom_tile)) pos.in_tile.y = config.pad_bottom;
                    }
                    else if (pos.in_tile.y > config.pad_top) {
                        const top_tile = calculate_real_tile(Vector2i.from(pos.physical_tile.x, pos.physical_tile.y + 1));
                        if (is_collision(top_tile)) pos.in_tile.y = config.pad_top;
                    }
                }
            }

            // Vertical movement, same as code above but on the vertical axis
            if (!std.math.approxEqAbs(f32, vel.y, 0, std.math.floatEps(f32))) {

                var total_movement = vel.y;
                var tiles_to_check: u32 = @intFromFloat(@ceil(@abs(vel.y)));
                var moved_tile: bool = false;

                while (tiles_to_check > 0) : (tiles_to_check -= 1) {
                    
                    const movement_ammount = std.math.clamp(total_movement, -1.0, 1.0);
                    total_movement -= movement_ammount;

                    pos.in_tile.y += movement_ammount;

                    if (pos.in_tile.y < config.pad_bottom) {
                        const bottom_tile = calculate_real_tile(Vector2i.from(pos.physical_tile.x, pos.physical_tile.y - 1));
                        if (is_collision(bottom_tile)) {
                            pos.in_tile.y = config.pad_bottom;
                            vel.y = 0.0;
                            // Mark the object as floored
                            floor = true;
                            break;
                        }
                        else if (pos.in_tile.y < 1.0) {
                            pos.in_tile.y += 1.0;
                            pos.physical_tile.y -= 1;
                            moved_tile = true;
                        }
                    }
                    else if (pos.in_tile.y > config.pad_top) {
                        const top_tile = calculate_real_tile(Vector2i.from(pos.physical_tile.x, pos.physical_tile.y + 1));
                        if (is_collision(top_tile)) {
                            pos.in_tile.y = config.pad_top;
                            vel.y = 0.0;
                            break;
                        }
                        else if (pos.in_tile.y > 1.0) {
                            pos.in_tile.y -= 1.0;
                            pos.physical_tile.y += 1;
                            moved_tile = true;
                        }
                    }

                }

                if (moved_tile) {
                    if (pos.in_tile.x > config.pad_right) {
                        const right_tile = calculate_real_tile(Vector2i.from(pos.physical_tile.x + 1, pos.physical_tile.y));
                        if (is_collision(right_tile)) pos.in_tile.x = config.pad_right;
                    }
                    else if (pos.in_tile.x < config.pad_left) {
                        const left_tile = calculate_real_tile(Vector2i.from(pos.physical_tile.x - 1, pos.physical_tile.y));
                        if (is_collision(left_tile)) pos.in_tile.x = config.pad_left;
                    }
                }
            }

            // Apply forces and frictions
            if (floor) {
                vel.x *= config.friction_floor;
            }
            else {
                vel.x *= config.friction_air;
                // vel.y *= config.friction_air;
            }

            if (std.math.approxEqAbs(f32, vel.x, 0, std.math.floatEps(f32))) { vel.x = 0; }
            if (std.math.approxEqAbs(f32, vel.y, 0, std.math.floatEps(f32))) { vel.y = 0; }

            // Update the objects state
            const new_physical_position = pos.to_physical_pos();
            o.physical_pos = new_physical_position;
            o.velocity = vel;
            return floor;
        }
    
    };
}

// pub inline fn physicalPosToTilePos(comptime config: PhysicsConfig, physical_pos: PhysicalPos) common.TilePos {
//     const decomposed = physicalPosDecompose(physical_pos);
//     return physicalTileToTilePos(config, decomposed.physical_tile);
// }

// pub const TilePositionToPhysicalPositionMode = enum {
//     grounded,
//     centered,
// };

// pub inline fn tilePosToPhysicalPos(comptime config: PhysicsConfig, comptime mode: TilePositionToPhysicalPositionMode, tile_pos: common.TilePos) PhysicalPos {
//     const granularity_float = @intToFloat(f32, config.granularity);
//     return switch (mode) {
//         .grounded => common.fpair(
//             @intToFloat(f32, tile_pos.x * config.granularity) + (0.5 * granularity_float),
//             @intToFloat(f32, (tile_pos.y + 1) * config.granularity) - (1 - config.pad_bottom),
//         ),
//         .centered => common.fpair(
//             @intToFloat(f32, tile_pos.x * config.granularity) + (0.5 * granularity_float),
//             @intToFloat(f32, tile_pos.y * config.granularity) + (0.5 * granularity_float),
//         ),
//     };
// }

// pub const TilePosToPixelPosMode = enum {
//     top_left,
//     bottom_right,
// };

// pub inline fn tilePosToPixelPos(comptime config: PhysicsConfig, comptime mode: TilePosToPixelPosMode, tile_pos: common.TilePos) common.PixelPos {
//     return switch (mode) {
//         .top_left => common.pp(
//             tile_pos.x * config.tile_size,
//             tile_pos.y * config.tile_size
//         ),
//         .bottom_right => common.pp(
//             (tile_pos.x + 1) * config.tile_size,
//             (tile_pos.y + 1) * config.tile_size
//         )
//     };
// }

// pub inline fn pixelPostToTilePos(comptime config: PhysicsConfig, pixel_pos: common.PixelPos) common.TilePos {
//     return common.tile(
//         @divFloor(pixel_pos.x, config.tile_size),
//         @divFloor(pixel_pos.y, config.tile_size),
//     );
// }

// pub inline fn pixelPosToPhysicalPos(comptime config: PhysicsConfig, pixel_pos: common.PixelPos) PhysicalPos {
//     const tile_size_f = @intToFloat(f32, config.tile_size);
//     const granularity_f = @intToFloat(f32, config.granularity);
//     return common.fpair(
//         @intToFloat(f32, pixel_pos.x) / tile_size_f * granularity_f,
//         @intToFloat(f32, pixel_pos.y) / tile_size_f * granularity_f
//     );
// }
