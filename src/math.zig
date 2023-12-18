const std = @import("std");

pub const Vector2f = Vec2(f32);
pub const Vector2i = Vec2(i32);
pub const Vector3f = Vec3(f32);
pub const Vector4f = Vec4(f32);

pub fn Vec2(comptime T: type) type {
    return struct {

        const Self = @This();

        x: T,
        y: T,
        
        pub inline fn from(x: T, y: T) Self {
            return Self { .x = x, .y = y };
        }

        pub inline fn to(self: Self, comptime OtherType: type) Vec2(OtherType) {
            return switch (@typeInfo(T)) {
                .Float => switch (@typeInfo(OtherType)) {
                    .Float => |_| Vec2(OtherType).from(@floatCast(self.x), @floatCast(self.y)),
                    .Int => |_| Vec2(OtherType).from(@intFromFloat(self.x), @intFromFloat(self.y)),
                    else => @panic("type not supported")
                },
                .Int => switch (@typeInfo(OtherType)) {
                    .Int => |_| Vec2(OtherType).from(@intCast(self.x), @intCast(self.y)),
                    .Float => |_| Vec2(OtherType).from(@floatFromInt(self.x), @floatFromInt(self.y)),
                    else => @panic("type not supported")
                },
                else => @panic("type not supported")
            };
        }

        pub fn add(self: Self, other: Self) Self {
            return Self.from(self.x + other.x, self.y + other.y);
        }

        pub inline fn equal(self: Self, other: Self) bool {
            return self.x == other.x and self.y == other.y;
        }

        pub fn substract(self: Self, other: Self) Self {
            return Self.from(self.x - other.x, self.y - other.y);
        }

        pub fn scale(self: Self, factor: T) Self {
            return Self.from(self.x * factor, self.y * factor);
        }

        pub fn scale_vec(self: Self, other: Self) Self {
            return Self.from(self.x * other.x, self.y * other.y);
        }

        pub fn dot(self: Self, other: Self) T {
            return self.x * other.x + self.y * other.y;
        }

        pub fn magnitude(self: Self) T {
            return std.math.sqrt(self.x * self.x + self.y * self.y);
        }
        
        pub fn normalized(self: Self) Self {
            switch (@typeInfo(T)) {
                .Float => {
                    const mag = self.magnitude();
                    return Self.from(self.x / mag, self.y / mag);
                },
                else => @compileError("type " ++ @typeName(T) ++ " is not a floating point number")
            }
        }

        pub fn perpendicular(self: Self) Self {
            return Self.from(self.y, -self.x);
        }
    };
}

pub fn Vec3(comptime T: type) type {
    return struct {

        const Self = @This();

        x: T,
        y: T,
        z: T,
        
        pub inline fn from(x: T, y: T, z: T) Self {
            return Self { .x = x, .y = y, .z = z };
        }

        pub inline fn to(self: Self, comptime OtherType: type) Vec3(OtherType) {
            const self_is_float = comptime std.meta.trait.isFloat(T);
            const other_is_float = comptime std.meta.trait.isFloat(OtherType);
            if (self_is_float) {
                if (other_is_float) return Vec3(OtherType).from(@floatCast(self.x), @floatCast(self.y), @floatCast(self.z))
                else return Vec3(OtherType).from(@intFromFloat(self.x), @intFromFloat(self.y), @intFromFloat(self.z));
            }
            else {
                if (other_is_float) return Vec3(OtherType).from(@floatFromInt(self.x), @floatFromInt(self.y), @floatFromInt(self.z))
                else return Vec3(OtherType).from(@intCast(self.x), @intCast(self.y), @intCast(self.z));
            }
        }

        pub fn add(self: Self, other: Self) Self {
            return Self.from(self.x + other.x, self.y + other.y, self.z + other.z );
        }

        pub fn substract(self: Self, other: Self) Self {
            return Self.from(self.x - other.x, self.y - other.y, self.z - other.z );
        }

        pub fn scale(self: Self, factor: T) Self {
            return Self.from(self.x * factor, self.y * factor, self.z * factor);
        }

        pub fn scale_vec(self: Self, other: Self) Self {
            return Self.from(self.x * other.x, self.y * other.y, self.z * other.z);
        }

        pub fn dot(self: Self, other: Self) T {
            return self.x * other.x + self.y * other.y + self.z * other.z;
        }

        pub fn cross_product(self: Self, other: Self) Self {
            return Self.from(
                self.y * other.z - self.z * other.y,
                self.z * other.x - self.x * other.z,
                self.x * other.y - self.y * other.x,
            );
        }

        pub fn magnitude(self: Self) T {
            return std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
        }
        
        pub fn normalized(self: Self) Self {
            if (comptime std.meta.trait.isFloat(T)) {
                const mag = self.magnitude();
                return Self.from(self.x / mag, self.y / mag, self.z / mag);
            }
            else @compileError("type " ++ @typeName(T) ++ " is not a floating point number");
        }

        pub fn perspective_division(self: Self) Vec2(T) {
            return Vec2(T).from(self.x / self.z, self.y / self.z);
        }
    };
}

pub fn Vec4(comptime T: type) type {
    return struct {

        const Self = @This();

        x: T,
        y: T,
        z: T,
        w: T,
        
        pub inline fn from(x: T, y: T, z: T, w: T) Self {
            return Self { .x = x, .y = y, .z = z, .w = w };
        }

        pub inline fn to(self: Self, comptime OtherType: type) Vec4(OtherType) {
            const self_is_float = comptime std.meta.trait.isFloat(T);
            const other_is_float = comptime std.meta.trait.isFloat(OtherType);
            if (self_is_float) {
                if (other_is_float) return Vec4(OtherType).from(@floatCast(self.x), @floatCast(self.y), @floatCast(self.z), @floatCast(self.w))
                else return Vec4(OtherType).from(@intFromFloat(self.x), @intFromFloat(self.y), @intFromFloat(self.z), @intFromFloat(self.w));
            }
            else {
                if (other_is_float) return Vec4(OtherType).from(@floatFromInt(self.x), @floatFromInt(self.y), @floatFromInt(self.z), @floatFromInt(self.w))
                else return Vec4(OtherType).from(@intCast(self.x), @intCast(self.y), @intCast(self.z), @intCast(self.w));
            }
        }

        pub fn add(self: Self, other: Self) Self {
            return Self.from(self.x + other.x, self.y + other.y, self.z + other.z, self.w + other.w);
        }

        pub fn scale(self: Self, factor: T) Self {
            return Self.from(self.x * factor, self.y * factor, self.z * factor, self.w * factor);
        }

        pub fn scale_vec(self: Self, other: Self) Self {
            return Self.from(self.x * other.x, self.y * other.y, self.z * other.z, self.w * other.w);
        }

        pub fn dot(self: Self, other: Self) T {
            return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w;
        }

        pub fn perspective_division(self: Self) Vec3(T) {
            return Vec3(T).from(self.x / self.w, self.y / self.w, self.z / self.w);
        }
    };
}

/// column major 3x3 matrix
/// meaning its stored like in a contiguous array like this:
///
///     [9]f32 { m11, m21, m31, m12, m22, m32, m13, m23, m33 }
///
/// So to access the matrix
/// 
///     m11, m12, m13
///     m21, m22, m23
///     m31, m32, m33
/// 
/// The index used would be
///
///     0    3    6 
///     1    4    7 
///     2    5    8
/// 
pub const M33 = struct {
    data: [9]f32,

    pub inline fn multiply(self: M33, other: M33) M33 {
        var result: M33 = undefined;
        for (0..3) |row| {
            for (0..3) |col| {
                result.data[(row*3)+col] = 0;
                for (0..3) |element| {
                    result.data[(row*3)+col] += self.data[(element*3)+col] * other.data[(row*3)+element];
                }
            }
        }
        return result;
    }

    pub inline fn apply_to_vec2(self: M33, point: Vector2f) Vector3f {
        var point_transformed: Vector3f = undefined;
        point_transformed.x = self.data[0] * point.x + self.data[3] * point.y + self.data[6] * 1;
        point_transformed.y = self.data[1] * point.x + self.data[4] * point.y + self.data[7] * 1;
        point_transformed.z = self.data[2] * point.x + self.data[5] * point.y + self.data[8] * 1;
        return point_transformed;
    }


    pub inline fn identity() M33 {
        var result: M33 = undefined;
        result.data[0] = 1;
        result.data[1] = 0;
        result.data[2] = 0;
        result.data[3] = 0;
        result.data[4] = 1;
        result.data[5] = 0;
        result.data[6] = 0;
        result.data[7] = 0;
        result.data[8] = 1;
        return result;
    }

    pub inline fn translation(t: Vector2f) M33 {
        var result = M33.identity();
        result.data[6] = t.x;
        result.data[7] = t.y;
        return result;
    }

    pub inline fn scaling_matrix(s: Vector2f) M33 {
        var result = M33.identity();
        result.data[0] = s.x;
        result.data[4] = s.y;
        return result;
    }

    pub inline fn scale(factor: f32) M33 {
        var result = M33.identity();
        result.data[0] = factor;
        result.data[4] = factor;
        return result;
    }

    pub fn viewport(x: f32, y: f32, w: f32, h: f32) M33 {
        const t = M33.translation(.{.x = x+1, .y = y+1});
        const s = M33.scaling_matrix(.{.x = map_range_to_range(0, 2, 0, w), .y = map_range_to_range(0, 2, 0, h)});
        return s.multiply(t);
    }

    /// constructs an orthographic projection matrix, which
    /// maps the square [left..right][bottom..top] to the square [-1..1][-1..1]
    /// and center it so that:
    ///        
    ///                                 !         (1    , 1  )
    ///                 O = origin  ____!____.  < (right, top)
    ///                             |   !    |
    ///                         - - - - O - - - - - 
    ///          (left, bottom)  >  |___!____|
    ///          (-1  , -1    )         !
    ///               
    /// https://www.youtube.com/watch?v=U0_ONQQ5ZNM
    pub fn orthographic_projection(left: f32, right: f32, top: f32, bottom: f32) M33 {
        var scale_matrix = M33.identity();
        if (true) {
            // This is the same as below but with the math unrolled.
            // I keep the part below since it is easier to understand what this is doing
            scale_matrix.data[0] = 2/(right-left);
            scale_matrix.data[4] = 2/(top-bottom);
            scale_matrix.data[6] = -(right+left)/(right-left);
            scale_matrix.data[7] = -(top+bottom)/(top-bottom);
            return scale_matrix;
        }
        scale_matrix.data[0] = map_range_to_range(left, right, -1, 1);
        scale_matrix.data[4] = map_range_to_range(bottom, top, -1, 1);
        // translate the world so that (0, 0) is the center of near plane of the square that captures the orthogonal projection
        const translate_matrix = M33.translation(Vector2f { .x = - ((right+left)/2), .y = - ((top+bottom)/2) });
        return scale_matrix.multiply(translate_matrix);
    }

    /// The right direction is in the +X direction.
    /// The up direction is in the +Y direction.
    pub fn look_at(camera_location: Vector2f, up: Vector2f) M33 {
        
        if (true) {
            // same as the code below but with the math unrolled
            const c = camera_location;
            const y: Vector2f = up.normalized();
            const x: Vector2f = y.perpendicular();
            var matrix: M33 = undefined;
            matrix.data[0] = x.x;
            matrix.data[3] = x.y;
            matrix.data[1] = y.x;
            matrix.data[4] = y.y;
            matrix.data[2] = 0;
            matrix.data[5] = 0;
            matrix.data[8] = 1;
            matrix.data[6] = (x.x * -c.x) + (x.y * -c.y);
            matrix.data[7] = (y.x * -c.x) + (y.y * -c.y);
            return matrix;
        }

        // just in case, normalize the up direction
        const normalized_up = up.normalized();
        
        // The right direction is in the +X direction.
        // The up direction is in the +Y direction.
        const new_right: Vector2f = normalized_up.perpendicular(); // x axis
        const new_up: Vector2f = normalized_up; // y axis

        // Create a change of basis matrix, in which, the camera position,
        // the points its looking at and the up vector form the three axes.
        // > In essence, a change of basis matrix is a transformation that allows us to express the same
        // > vector or set of coordinates in a different coordinate system or basis, providing a new
        // > perspective or representation while preserving the underlying geometric relationships.
        var change_of_basis_matrix = M33.identity();
        change_of_basis_matrix.data[0] = new_right.x;
        change_of_basis_matrix.data[3] = new_right.y;

        change_of_basis_matrix.data[1] = new_up.x;
        change_of_basis_matrix.data[4] = new_up.y;

        // translate the world to the location of the camera and then rotate it
        // The order of this multiplication is relevant!
        // 
        //     rotation_matrix * translation_matrix(-camera_location)
        // 
        return change_of_basis_matrix.multiply(M33.translation(camera_location.scale(-1)));
    }

};


/// column major 4x4 matrix
/// meaning its stored like in a contiguous array like this:
///
///     [16]f32 { m11, m21, m31, m41, m12, m22, m32, m42, m13, m23, m33, m43, m14, m24, m34, m44 }
///
/// So to access the matrix
/// 
///     m11, m12, m13, m14
///     m21, m22, m23, m24
///     m31, m32, m33, m34
///     m41, m42, m43, m44
/// 
/// The index used would be
///
///     0    4    8    12
///     1    5    9    13
///     2    6    10   14
///     3    7    11   15
/// 
pub const M44 = struct {
    data: [16]f32,

    pub fn multiply(self: M44, other: M44) M44 {
        var result: M44 = undefined;
        for (0..4) |row| {
            for (0..4) |col| {
                result.data[(row*4)+col] = 0;
                for (0..4) |element| {
                    result.data[(row*4)+col] += self.data[(element*4)+col] * other.data[(row*4)+element];
                }
            }
        }
        return result;
    }

    pub fn apply_to_vec3(self: M44, point: Vector3f) Vector4f {
        var point_transformed: Vector4f = undefined;
        point_transformed.x = self.data[0] * point.x + self.data[4] * point.y + self.data[8] * point.z + self.data[12] * 1;
        point_transformed.y = self.data[1] * point.x + self.data[5] * point.y + self.data[9] * point.z + self.data[13] * 1;
        point_transformed.z = self.data[2] * point.x + self.data[6] * point.y + self.data[10] * point.z + self.data[14] * 1;
        point_transformed.w = self.data[3] * point.x + self.data[7] * point.y + self.data[11] * point.z + self.data[15] * 1;
        return point_transformed;
    }

    pub fn apply_to_vec4(self: M44, point4d: Vector4f) Vector4f {
        var point_transformed: Vector4f = undefined;
        point_transformed.x = self.data[0] * point4d.x + self.data[4] * point4d.y + self.data[8] * point4d.z + self.data[12] * point4d.w;
        point_transformed.y = self.data[1] * point4d.x + self.data[5] * point4d.y + self.data[9] * point4d.z + self.data[13] * point4d.w;
        point_transformed.z = self.data[2] * point4d.x + self.data[6] * point4d.y + self.data[10] * point4d.z + self.data[14] * point4d.w;
        point_transformed.w = self.data[3] * point4d.x + self.data[7] * point4d.y + self.data[11] * point4d.z + self.data[15] * point4d.w;
        return point_transformed;
    }
    
    pub fn apply_to_point(self: M44, point: Vector3f) Vector3f {
        // Embed the `point` into "4D" by augmenting it with 1, so that we can work with it.
        // 
        //     | x |    | x |
        //     | y | => | y |
        //     | z |    | z |
        //              | 1 |
        //     
        // Essentially creating a Matrix41 where its "new" 4th element is 1.0f
        const point4d = Vector4f { .x = point.x, .y = point.y, .z = point.z, .w = 1 };

        // Then do a standard Matrix multiplication M44 * M41 => M41 (AKA Vector4f)
        // 
        //     point_transformed = self * point4d
        // 
        var point_transformed: Vector4f = undefined;
        point_transformed.x = self.data[0] * point4d.x + self.data[4] * point4d.y + self.data[8] * point4d.z + self.data[12] * point4d.w;
        point_transformed.y = self.data[1] * point4d.x + self.data[5] * point4d.y + self.data[9] * point4d.z + self.data[13] * point4d.w;
        point_transformed.z = self.data[2] * point4d.x + self.data[6] * point4d.y + self.data[10] * point4d.z + self.data[14] * point4d.w;
        point_transformed.w = self.data[3] * point4d.x + self.data[7] * point4d.y + self.data[11] * point4d.z + self.data[15] * point4d.w;

        // Finally we project (retro-project*) the resulting point back in a 3D space
        //     
        //     | x |    | x/w |
        //     | y | => | y/w |
        //     | z |    | z/w |
        //     | w |         
        //
        return Vector3f {
            .x = point_transformed.x / point_transformed.w,
            .y = point_transformed.y / point_transformed.w,
            .z = point_transformed.z / point_transformed.w,
        };
    }

    pub fn transposed(self: M44) M44 {
        var result: M44 = undefined;
        for (0..4) |row| {
            for (0..4) |col| {
                result.data[(row*4)+col] = self.data[(col*4)+row];
            }
        }
        return result;
    }

    pub fn identity() M44 {
        var result: M44 = undefined;
        result.data[0] = 1;
        result.data[1] = 0;
        result.data[2] = 0;
        result.data[3] = 0;
        result.data[4] = 0;
        result.data[5] = 1;
        result.data[6] = 0;
        result.data[7] = 0;
        result.data[8] = 0;
        result.data[9] = 0;
        result.data[10] = 1;
        result.data[11] = 0;
        result.data[12] = 0;
        result.data[13] = 0;
        result.data[14] = 0;
        result.data[15] = 1;
        return result;
    }

    pub fn translation(t: Vector3f) M44 {
        var result = M44.identity();
        result.data[12] = t.x;
        result.data[13] = t.y;
        result.data[14] = t.z;
        return result;
    }

    pub fn scaling_matrix(s: Vector3f) M44 {
        var result = M44.identity();
        result.data[0] = s.x;
        result.data[5] = s.y;
        result.data[10] = s.z;
        return result;
    }

    pub fn scale(factor: f32) M44 {
        var result = M44.identity();
        result.data[0] = factor;
        result.data[5] = factor;
        result.data[10] = factor;
        return result;
    }

    /// The camera is looking towards +Z.
    /// The right direction is in the +X direction.
    /// The up direction is in the +Y direction.
    pub fn lookat_left_handed(camera_location: Vector3f, point_looked_at: Vector3f, up: Vector3f) M44 {
        
        if (true) return lookat_left_handed_unrolled(camera_location, point_looked_at, up);

        // just in case, normalize the up direction
        const normalized_up = up.normalized();
        
        // the camera looks towards the positive z axes
        // the z axes got the direction `point looked at <------ camera location`
        // 
        //     The camera is looking towards +Z.
        //     The right direction is in the +X direction.
        //     The up direction is in the +Y direction.
        // 
        const new_forward: Vector3f = point_looked_at.substract(camera_location).normalized(); // z axis
        const new_right: Vector3f = normalized_up.cross_product(new_forward).scale(-1).normalized(); // x axis
        const new_up: Vector3f = new_forward.cross_product(new_right).scale(-1).normalized(); // y axis

        // Create a change of basis matrix, in which, the camera position,
        // the points its looking at and the up vector form the three axes.
        // > In essence, a change of basis matrix is a transformation that allows us to express the same
        // > vector or set of coordinates in a different coordinate system or basis, providing a new
        // > perspective or representation while preserving the underlying geometric relationships.
        var change_of_basis_matrix = M44.identity();
        change_of_basis_matrix.data[0] = new_right.x;
        change_of_basis_matrix.data[4] = new_right.y;
        change_of_basis_matrix.data[8] = new_right.z;

        change_of_basis_matrix.data[1] = new_up.x;
        change_of_basis_matrix.data[5] = new_up.y;
        change_of_basis_matrix.data[9] = new_up.z;

        change_of_basis_matrix.data[2] = new_forward.x;
        change_of_basis_matrix.data[6] = new_forward.y;
        change_of_basis_matrix.data[10] = new_forward.z;

        // translate the world to the location of the camera and then rotate it
        // The order of this multiplication is relevant!
        // 
        //     rotation_matrix * translation_matrix(-camera_location)
        // 
        return change_of_basis_matrix.multiply(M44.translation(camera_location.scale(-1)));
    }

    /// same as `lookat_left_handed` but with the math unrolled
    fn lookat_left_handed_unrolled(c: Vector3f, point_looked_at: Vector3f, up: Vector3f) M44 {

        // NOTE So, for a while I thought that I decided whether I wanted my reference system to be left handed or right handed,
        // and based on that, I would figure out the rest. But aparently thats not the case. As this gamedev.stackexchange answer
        // says:
        // 
        // > https://gamedev.stackexchange.com/questions/146930/help-to-understand-positive-rotation-direction-on-left-right-handed-cord-spaces
        // > You got it backwards, the rotation direction defines the handedness.
        // 
        // So, rather than choose left or right handed, you decide how your camera works (in my case, front is +z, right is +x and up is + y).
        // 
        // > https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/coordinate-systems.html#:~:text=With%20the%20x%2Daxis%20pointing,a%20right%2Dhand%20coordinate%20system.
        // > With the x-axis pointing to the right and the y-axis pointing up, if the z-axis points away from you,
        // > it's a left-hand coordinate system. If it points in your direction, it is a right-hand coordinate system.
        // 

        const normalized_up = up.normalized();
        const z: Vector3f = point_looked_at.substract(c).normalized(); // z axis
        const x: Vector3f = normalized_up.cross_product(z).normalized(); // x axis
        const y: Vector3f = z.cross_product(x).normalized(); // y axis
        var matrix: M44 = undefined;
        matrix.data[0] = x.x;
        matrix.data[4] = x.y;
        matrix.data[8] = x.z;
        matrix.data[1] = y.x;
        matrix.data[5] = y.y;
        matrix.data[9] = y.z;
        matrix.data[2] = z.x;
        matrix.data[6] = z.y;
        matrix.data[10] = z.z;
        matrix.data[3] = 0;
        matrix.data[7] = 0;
        matrix.data[11] = 0;
        matrix.data[15] = 1;
        matrix.data[12] = (x.x * -c.x) + (x.y * -c.y) + (x.z * -c.z);
        matrix.data[13] = (y.x * -c.x) + (y.y * -c.y) + (y.z * -c.z);
        matrix.data[14] = (z.x * -c.x) + (z.y * -c.y) + (z.z * -c.z);
        return matrix;
    }
    
    /// constructs an orthographic projection matrix, which
    /// maps the cube [left..right][bottom..top][near..far] to the cube [-1..1][-1..1][0..1] cube
    /// and center it so that:
    ///        
    ///                                 !           (1    , 1  , 1  )
    ///                   O = origin  __!______.  < (right, top, far)
    ///                              /  !     /|
    ///                             /___!____/ |
    ///                             |   !    | |
    ///                         - - - - O - - -/- - - 
    ///    (left, bottom, near)  >  |___!____|/
    ///    (-1  , -1    , 0   )         !
    ///               
    /// https://www.youtube.com/watch?v=U0_ONQQ5ZNM
    pub fn orthographic_projection(left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) M44 {
        if (true) return orthographic_projection_unrolled(left, right, top, bottom, near, far);
        var scale_matrix = M44.identity();
        scale_matrix.data[0] = map_range_to_range(left, right, -1, 1);
        scale_matrix.data[5] = map_range_to_range(bottom, top, -1, 1);
        // NOTE I'm not sure whether this is actually correct... check test below
        scale_matrix.data[10] = map_range_to_range(near, far, 0, 1);
        // translate the world so that (0, 0, 0) is the center of near plane of the cube that captures the orthogonal projection
        const translate_matrix = M44.translation(Vector3f { .x = - ((right+left)/2), .y = - ((top+bottom)/2), .z = - near });
        return scale_matrix.multiply(translate_matrix);
    }
    
    /// same as `orthographic_projection` but with the math unrolled
    pub fn orthographic_projection_unrolled(l: f32, r: f32, t: f32, b: f32, n: f32, f: f32) M44 {
        var matrix = M44.identity();
        matrix.data[0] = 2/(r-l);
        matrix.data[5] = 2/(t-b);
        matrix.data[10] = 1/(f-n);
        matrix.data[12] = -(r+l)/(r-l);
        matrix.data[13] = -(t+b)/(t-b);
        matrix.data[14] = -n/(f-n);
        return matrix;
    }

    test "scaling of z is not what I expect..." {
        try std.testing.expect(map_range_to_range(0, 100, 0, 1) * 0 == 0);
        try std.testing.expect(map_range_to_range(0, 100, 0, 1) * 100 == 1);
        try std.testing.expect(map_range_to_range(0, 100, 0, 1) * 50 == 0.5);
        // From what I see online, the consensus is to do `1/(f-n)` for scaling the z values on the orthographic projection matrix.
        // However, for example, if `far = 1000` and `near = 0.1` then `1/(1000-0.1) * 0.1` should be 0, but it is not!
        try std.testing.expect((map_range_to_range(0.1, 100, 0, 1) * 0.1 == 0) == false);
        // It seems to have to do with normalization but I'm not sure how to apply that in the orthographic matrix situation
        try std.testing.expect((map_range_to_range_normalized(0.1, 0.1, 100, 0, 1) == 0));
    }

    /// https://www.youtube.com/watch?v=U0_ONQQ5ZNM
    pub fn perspective_projection(fov_degrees: f32, aspect_ratio: f32, near: f32, far: f32) M44 {
        if (true) return perspective_projection_unrolled(fov_degrees, aspect_ratio, near, far);
        const fov_radians = (@as(f32,std.math.pi)/180) * fov_degrees;
        const top = near * std.math.tan(fov_radians / 2.0);
        const right = near * aspect_ratio * std.math.tan(fov_radians / 2.0); 
        const left = -right;
        const bottom = -top;
        
        var perspective = M44.identity();
        perspective.data[0] = near;
        perspective.data[5] = near;
        perspective.data[10] = far+near;
        perspective.data[14] = -(far*near);
        perspective.data[11] = 1;
        perspective.data[15] = 0;

        const ortho_projection = orthographic_projection(left, right, top, bottom, near, far);
        return ortho_projection.multiply(perspective);
    }

    /// same as `perspective_projection_2` but with the math unrolled
    pub fn perspective_projection_unrolled(fov_degrees: f32, aspect_ratio: f32, n: f32, f: f32) M44 {
        const fov_radians = (@as(f32,std.math.pi)/180) * fov_degrees;
        const t = n * std.math.tan(fov_radians / 2.0);
        const r = n * aspect_ratio * std.math.tan(fov_radians / 2.0); 
        var matrix = M44.identity();
        matrix.data[0] = n/r;
        matrix.data[5] = n/t;
        matrix.data[10] = f/(f-n);
        matrix.data[11] = 1;
        matrix.data[14] = -(f*n)/(f-n);
        matrix.data[15] = 0;
        return matrix;
    }
    
    /// Builds a "viewport" (as its called in opengl) matrix, a matrix that
    /// will map a point in the 3-dimensional cube [-1, 1]*[-1, 1]*[-1, 1]
    /// onto the screen cube [x, x+w]*[y, y+h]*[0, d],
    /// where d is the depth/resolution of the z-buffer
    pub fn viewport_i32_old(x: i32, y: i32, w: i32, h: i32, depth: i32) M44 {
        const xf: f32 = @floatFromInt(x);
        const yf: f32 = @floatFromInt(y);
        const wf: f32 = @floatFromInt(w);
        const hf: f32 = @floatFromInt(h);
        const depthf: f32 = @floatFromInt(depth);
        return viewport_old(xf, yf, wf, hf, depthf);
    }
    
    pub fn viewport_i32(x: i32, y: i32, w: i32, h: i32, depth: i32) M44 {
        const xf: f32 = @floatFromInt(x);
        const yf: f32 = @floatFromInt(y);
        const wf: f32 = @floatFromInt(w);
        const hf: f32 = @floatFromInt(h);
        const depthf: f32 = @floatFromInt(depth);
        return viewport(xf, yf, wf, hf, depthf);
    }

    pub fn viewport(x: f32, y: f32, w: f32, h: f32, depth: f32) M44 {
        const t = M44.translation(.{.x = x+1, .y = y+1, .z = 0});
        const s = M44.scaling_matrix(.{.x = map_range_to_range(0, 2, 0, w), .y = map_range_to_range(0, 2, 0, h), .z = map_range_to_range(0, 1, 0, depth)});
        return s.multiply(t);
    }

    /// returns a matrix which maps the cube [-1,1]*[-1,1]*[0,1] onto the screen cube [x,x+w]*[y,y+h]*[0,d]
    pub fn viewport_old(x: f32, y: f32, w: f32, h: f32, depth: f32) M44 {
        var matrix = M44.identity();
        
        // 1 0 0 translation_x
        // 0 1 0 translation_y
        // 0 0 1 translation_z
        // 0 0 0 1

        const translation_x: f32 = x + (w / 2);
        const translation_y: f32 = y + (h / 2);
        const translation_z: f32 = depth / 2;

        matrix.data[12] = translation_x;
        matrix.data[13] = translation_y;
        matrix.data[14] = translation_z;

        // scale_x 0       0       0
        // 0       scale_y 0       0
        // 0       0       scale_z 0
        // 0       0       0       1
        
        const scale_x: f32 = w / 2;
        // This coulb be negated so that the top left corner is 0,0
        // If so, when mapping from normalized device coordinates (NDC) to screen space, thing will be inverted so that top left is 0,0
        // 
        //     const scale_y: f32 = -hf / 2;
        const scale_y: f32 = h / 2;
        const scale_z: f32 = depth / 2;

        matrix.data[0] = scale_x;
        matrix.data[5] = scale_y;
        matrix.data[10] = scale_z;

        // resulting in matrix...
        // w/2     0       0       x+(w/2)
        // 0       h/2     0       y+(h/w)
        // 0       0       d/2     d/2
        // 0       0       0       1

        // https://github.com/ssloy/tinyrenderer/wiki/Lesson-5:-Moving-the-camera#viewport
        // > In this function, we are basically mapping a cube [-1,1]*[-1,1]*[-1,1] onto the screen cube [x,x+w]*[y,y+h]*[0,d]
        // > Its a cube (and not a rectangle) since there is a `d`epth variable to it, which acts as the resolution of the z-buffer.

        return matrix;
    }
};

pub const Frustum = struct {
    left: Plane,
    right: Plane,
    top: Plane,
    bottom: Plane,
    near: Plane,
    far: Plane,
};

/// Check Appendix A for more info:
/// https://www.gamedevs.org/uploads/fast-extraction-viewing-frustum-planes-from-world-view-projection-matrix.pdf
pub const Plane = struct {
    
    a: f32,
    b: f32,
    c: f32,
    d: f32,

    pub fn from(point: Vector3f, normal: Vector3f) Plane {
        const d = - ((normal.x*point.x)+(normal.y*point.y)+(normal.z*point.z));
        return Plane { .a = normal.x, .b = normal.y, .c = normal.z, .d = d };
    }

    /// https://www.gamedevs.org/uploads/fast-extraction-viewing-frustum-planes-from-world-view-projection-matrix.pdf
    pub fn extract_frustum_from_projection(projection_matrix: M44) Frustum {
        var frustum: Frustum = undefined;
        // Left clipping plane
        frustum.left.a = projection_matrix.data[3] + projection_matrix.data[0];
        frustum.left.b = projection_matrix.data[7] + projection_matrix.data[4];
        frustum.left.c = projection_matrix.data[11] + projection_matrix.data[8];
        frustum.left.d = projection_matrix.data[15] + projection_matrix.data[12];
        // Right clipping plane
        frustum.right.a = projection_matrix.data[3] - projection_matrix.data[0];
        frustum.right.b = projection_matrix.data[7] - projection_matrix.data[4];
        frustum.right.c = projection_matrix.data[11] - projection_matrix.data[8];
        frustum.right.d = projection_matrix.data[15] - projection_matrix.data[12];
        // Top clipping plane
        frustum.top.a = projection_matrix.data[3] - projection_matrix.data[1];
        frustum.top.b = projection_matrix.data[7] - projection_matrix.data[5];
        frustum.top.c = projection_matrix.data[11] - projection_matrix.data[9];
        frustum.top.d = projection_matrix.data[15] - projection_matrix.data[13];
        // Bottom clipping plane
        frustum.bottom.a = projection_matrix.data[3] + projection_matrix.data[1];
        frustum.bottom.b = projection_matrix.data[7] + projection_matrix.data[5];
        frustum.bottom.c = projection_matrix.data[11] + projection_matrix.data[9];
        frustum.bottom.d = projection_matrix.data[15] + projection_matrix.data[13];
        // Near clipping plane
        frustum.near.a = projection_matrix.data[3] + projection_matrix.data[2];
        frustum.near.b = projection_matrix.data[7] + projection_matrix.data[6];
        frustum.near.c = projection_matrix.data[11] + projection_matrix.data[10];
        frustum.near.d = projection_matrix.data[15] + projection_matrix.data[14];
        // Far clipping plane
        frustum.far.a = projection_matrix.data[3] - projection_matrix.data[2];
        frustum.far.b = projection_matrix.data[7] - projection_matrix.data[6];
        frustum.far.c = projection_matrix.data[11] - projection_matrix.data[10];
        frustum.far.d = projection_matrix.data[15] - projection_matrix.data[14];

        frustum.left.normalize();
        frustum.right.normalize();
        frustum.top.normalize();
        frustum.bottom.normalize();
        frustum.near.normalize();
        frustum.far.normalize();

        return frustum;
    }

    /// > A plane cuts three-dimensional space into two separate parts. These parts are called `halfspaces`. The halfspace the
    /// > plane's normals vector points into is called the positive halfspace, and the other halfspace is called the negative halfspace.
    pub const Halfspace = enum(i32) {
        negative = -1,
        on_plane = 0,
        positive = 1,
    };

    /// > This distance is not necessarily a 'true' distance.
    /// > Instead it is the signed distance in units of the magnitude of the plane’s normal vector.
    /// > To obtain a 'true' distance, you need to normalize the plane equation first.
    /// >
    /// > If the plane equation is not normalized, then we can still get some valuable information from the 'non-true' distance:
    /// > 1. If dist < 0 , then the point p lies in the negative halfspace.
    /// > 2. If dist = 0 , then the point p lies in the plane.
    /// > 3. If dist > 0 , then the point p lies in the positive halfspace
    pub fn signed_distance_to_point(plane: Plane, point: Vector3f) f32 {
        return plane.a * point.x +
            plane.b * point.y +
            plane.c * point.z +
            plane.d;
    }

    pub fn classify_point(plane: Plane, point: Vector3f) Halfspace {
        const distance: f32 = signed_distance_to_point(plane, point);
        return if (distance < -std.math.floatEps(f32)) Halfspace.negative else if (distance > std.math.floatEps(f32)) Halfspace.positive else Halfspace.on_plane;
    }

    pub fn intersection(plane: Plane, p1: Vector3f, p2: Vector3f) Vector3f {
        const t: f32 =
            -(plane.a * p1.x + plane.b * p1.y + plane.c * p1.z + plane.d) /
            (plane.a * (p2.x - p1.x) + plane.b * (p2.y - p1.y) + plane.c * (p2.z - p1.z));

        const intersection_point = Vector3f {
            .x = p1.x + t * (p2.x - p1.x),
            .y = p1.y + t * (p2.y - p1.y),
            .z = p1.z + t * (p2.z - p1.z),
        };

        return intersection_point;
    }

    /// > means to change the plane equation, such that the normal becomes a unit vector.
    pub fn normalize(self: *Plane) void {
        const magnitude: f32 = std.math.sqrt(self.a * self.a + self.b * self.b + self.c * self.c);
        self.a /= magnitude;
        self.b /= magnitude;
        self.c /= magnitude;
        self.d /= magnitude;
    }

};

fn map_range_to_range(from: f32, to: f32, map_from: f32, map_to: f32) f32 {
    return (map_to - map_from) / (to - from);
}

fn map_range_to_range_normalized(n: f32, from: f32, to: f32, map_from: f32, map_to: f32) f32 {
    const factor = ((map_to - map_from) / (to - from));
    // put n in normalized space, then multiply by the factor, then map back to original space
    // this is aking to how, when rotating things with a matrix, you first move it to the origin, rotate it, and then move it back
    return ((n - from) * factor) + map_from;
}

pub const BoundingBoxSide = enum {
    top, bottom, left, right
};

pub fn BoundingBox(comptime T: type) type {
    return struct {

        const Self = @This();
        const Pair = struct {
            x: T, y: T,
            pub inline fn from(x: T, y: T) Pair {
                return .{ .x = x, .y = y };
            }
        };

        top: T,
        bottom: T,
        left: T,
        right: T,

        pub inline fn from(top: T, bottom: T, left: T, right: T) Self {
            std.debug.assert(top >= bottom);
            std.debug.assert(right >= left);
            return .{
                .top = top,
                .bottom = bottom,
                .left = left,
                .right = right,
            };
        }

        pub inline fn to(self: Self, comptime OtherType: type) BoundingBox(OtherType) {
            return switch (@typeInfo(T)) {
                .Float => switch (@typeInfo(OtherType)) {
                    .Float => |_| BoundingBox(OtherType).from(@floatCast(self.top), @floatCast(self.bottom), @floatCast(self.left), @floatCast(self.right)),
                    .Int => |_| BoundingBox(OtherType).from(@intFromFloat(self.top), @intFromFloat(self.bottom), @intFromFloat(self.left), @intFromFloat(self.right)),
                    else => @panic("type not supported")
                },
                .Int => switch (@typeInfo(OtherType)) {
                    .Int => |_| BoundingBox(OtherType).from(@intCast(self.top), @intCast(self.bottom), @intCast(self.left), @intCast(self.right)),
                    .Float => |_| BoundingBox(OtherType).from(@floatFromInt(self.top), @floatFromInt(self.bottom), @floatFromInt(self.left), @floatFromInt(self.right)),
                    else => @panic("type not supported")
                },
                else => @panic("type not supported")
            };
        }

        pub inline fn side(self: Self, s: BoundingBoxSide) T {
            return switch (s) {
                .top => self.top,
                .botom => self.botom,
                .left => self.left,
                .right => self.right,
            };
        }

        pub inline fn width(self: Self) T {
            return self.right - self.left;
        }

        pub inline fn height(self: Self) T {
            return self.top - self.bottom;
        }

        pub inline fn bl(self: Self) Vec2(T) {
            return Vec2(T).from(self.left, self.bottom);
        }

        pub inline fn br(self: Self) Vec2(T) {
            return Vec2(T).from(self.right, self.bottom);
        }

        pub inline fn tl(self: Self) Vec2(T) {
            return Vec2(T).from(self.left, self.top);
        }

        pub inline fn tr(self: Self) Vec2(T) {
            return Vec2(T).from(self.right, self.top);
        }

        pub inline fn from_tl_br(_tl: anytype, _br: anytype) Self {
            return from(_tl.y, _br.y, _tl.x, _br.x);
        }

        pub inline fn from_br_size(_br: anytype, size: anytype) Self {
            return from(_br.y+size.y, _br.y, _br.x, _br.x+size.x);
        }

        pub inline fn from_indexed_grid(grid_dimensions: Vec2(T), grid_cell_dimensions: Vec2(T), index: T, inverse_y: bool) Self {
            const col = index % grid_dimensions.x;
            const row = if (inverse_y) (grid_dimensions.y-1) - @divFloor(index, grid_dimensions.x) else @divFloor(index, grid_dimensions.x);
            return BoundingBox(T).from(row*grid_cell_dimensions.y + grid_cell_dimensions.y, row*grid_cell_dimensions.y, col*grid_cell_dimensions.x, col*grid_cell_dimensions.x + grid_cell_dimensions.x);
        }

        /// `point` can be anything that has fields `x: T` and `y: T`
        pub inline fn contains(self: Self, point: anytype) bool {
            return point.x >= self.left and point.x <= self.right and point.y >= self.bottom and point.y <= self.top;
        }

        pub inline fn contains_exclusive(self: Self, point: anytype) bool {
            return point.x >= self.left and point.x < self.right and point.y >= self.bottom and point.y < self.top;
        }

        pub inline fn overlaps(self: Self, other: Self) bool {
            return self.contains(Pair.from(other.left, other.top))
                or self.contains(Pair.from(other.right, other.top))
                or self.contains(Pair.from(other.left, other.bottom))
                or self.contains(Pair.from(other.right, other.bottom));
        }

        /// `factor` can be anything that has fields `x: T` and `y: T`
        /// scales `top` and `bottom` by `factor.y` and `left` and `right` by `factor.x`
        pub fn scale(self: Self, factor: anytype) Self {
            var new: Self = .{
                .top = self.top * factor.y,
                .bottom = self.bottom * factor.y,
                .left = self.left * factor.x,
                .right = self.right * factor.x,
            };
            // make sure left is still left and top is still top
            if (factor.x < 0) std.mem.swap(T, &new.left, &new.right);
            if (factor.y < 0) std.mem.swap(T, &new.top, &new.bottom);
            return new;
        }

        /// `os` can be anything that has fields `x: T` and `y: T`
        pub fn offset(self: Self, os: anytype) Self {
            return Self.from(
                self.top + os.y,
                self.bottom + os.y,
                self.left + os.x,
                self.right + os.x,
            );
        }

        /// generally `offset` should be enough but when working with unsigned types this is handy
        pub fn offset_negative(self: Self, os: anytype) Self {
            return Self.from(
                self.top - os.y,
                self.bottom - os.y,
                self.left - os.x,
                self.right - os.x,
            );
        }
        
    };
}