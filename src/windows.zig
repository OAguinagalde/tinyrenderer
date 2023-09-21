const std = @import("std");
const imgui = struct {
    
    const c = @cImport({
        @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", {});
        @cInclude("cimgui.h");
    });
    
    pub fn ImVector(comptime T: type) type {
        // Original ImVectors look like this
        // 
        //     pub const struct_ImVector_ImDrawIdx = extern struct {
        //         Size: c_int,
        //         Capacity: c_int,
        //         Data: [*c]ImDrawIdx,
        //     };
        // 
        return struct {
            const Self = @This();
            
            used: usize,
            data: []T,
            
            pub fn used_slice(self: Self) []T {
                return self.data[0..self.used];
            }

            pub fn from(im_vector: anytype) Self {
                const size: usize = @intCast(@field(im_vector, "Size"));
                const capacity: usize = @intCast(@field(im_vector, "Capacity"));
                const data = @field(im_vector, "Data");
                const slice: []T = @ptrCast(data[0..capacity]);
                return Self {
                    .used = size,
                    .data = slice
                };
            }
        };
    }

    fn im_vector_guess_type(comptime im_vector_type: type) type {
        const info: std.builtin.Type = @typeInfo(im_vector_type);
        for (info.Struct.fields) |field| {
            if (std.mem.eql(u8, field.name, "Data")) {
                const data_type: std.builtin.Type = @typeInfo(field.type);
                return data_type.Pointer.child;
            }
        }
        @panic("Provided type isn't an ImVector");
    }

    pub fn im_vector_from(im_vector: anytype) ImVector(im_vector_guess_type(@TypeOf(im_vector))) {
        return ImVector(im_vector_guess_type(@TypeOf(im_vector))).from(im_vector);
    }
};

inline fn float(comptime t: type, v: anytype) t { return @as(t, @floatFromInt(v)); }
inline fn int(comptime t: type, v: anytype) t { return @as(t, @intFromFloat(v)); }

const win32 = struct {
    usingnamespace @import("win32").everything;
    const falsei32: i32 = 0;
    const call_convention = std.os.windows.WINAPI;
    
    comptime { std.debug.assert(@sizeOf(win32.RGBA) == @sizeOf(u32)); }

    /// In windows pixels are stored as BGRA
    const RGBA = extern struct {
        b: u8,
        g: u8,
        r: u8,
        /// 255 for solid and 0 for transparent
        a: u8,
        fn scale(self: win32.RGBA, factor: f32) win32.RGBA {
            return win32.RGBA {
                .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
                .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
                .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
                .a = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.a)) * factor))),
            };
        }

        fn blend(c1: win32.RGBA, c2: win32.RGBA) win32.RGBA {
        const a1: f32 = @as(f32, @floatFromInt(c1.a)) / 255;
        const result = win32.RGBA {
            .r = @intFromFloat((@as(f32, @floatFromInt(c1.r))/255*a1 + @as(f32, @floatFromInt(c2.r))/255*(1-a1))*255),
            .g = @intFromFloat((@as(f32, @floatFromInt(c1.g))/255*a1 + @as(f32, @floatFromInt(c2.g))/255*(1-a1))*255),
            .b = @intFromFloat((@as(f32, @floatFromInt(c1.b))/255*a1 + @as(f32, @floatFromInt(c2.b))/255*(1-a1))*255),
            .a = @intFromFloat((@as(f32, @floatFromInt(c1.a))/255*a1 + @as(f32, @floatFromInt(c2.a))/255*(1-a1))*255),
        };
        return result;
    }
    };

    fn rgb(r: u8, g: u8, b: u8) win32.RGBA {
        return rgba(r,g,b,255);
    }

    fn rgba(r: u8, g: u8, b: u8, a: u8) win32.RGBA {
        return win32.RGBA {
            .a = a, .r = r, .g = g, .b = b
        };
    }

};

const Vector2i = struct {
    x: i32,
    y: i32,

    pub fn add(self: Vector2i, other: Vector2i) Vector2i {
        return Vector2i { .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn substract(self: Vector2i, other: Vector2i) Vector2i {
        return Vector2i { .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: Vector2i, factor: i32) Vector2i {
        return Vector2i { .x = self.x * factor, .y = self.y * factor };
    }

    pub fn dot(self: Vector2i, other: Vector2i) i32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn cross_product(self: Vector2i, other: Vector2i) Vector3f {
        return Vector3f {
            .x = 0.0,
            .y = 0.0,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn to_vec2f(self: Vector2i) Vector2f {
        return Vector2f { .x = @intCast(self.x), .y = @intCast(self.y) };
    }
};

const Vector2f = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vector2f, other: Vector2f) Vector2f {
        return Vector2f { .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn substract(self: Vector2f, other: Vector2f) Vector2f {
        return Vector2f { .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: Vector2f, factor: f32) Vector2f {
        return Vector2f { .x = self.x * factor, .y = self.y * factor };
    }

    /// dot product (represented by a dot ·) of 2 vectors A and B is a scalar N, sometimes called scalar product
    pub fn dot(self: Vector2f, other: Vector2f) f32 {
        return self.x * other.x + self.y * other.y;
    }

    /// also known as length, magnitude or norm, represented like ||v||
    pub fn magnitude(self: Vector2f) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y);
    }
    
    pub fn normalized(self: Vector2f) Vector2f {
        const mag = self.magnitude();
        return Vector2f { .x = self.x / mag, .y = self.y / mag };
    }

    pub fn cross_product(self: Vector2f, other: Vector2f) Vector3f {
        return Vector3f {
            .x = 0.0,
            .y = 0.0,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    /// The cross product or vector product (represented by an x) of 2 vectors A and B is another vector C.
    /// C is exactly perpendicular (90 degrees) to the plane AB, meaning that there has to be a 3rd dimension for the cross product for this to make sense.
    /// The length of C will be the same as the area of the parallelogram formed by AB.
    /// This implementation assumes z = 0, meaning that the result will always be of type Vec3 (0, 0, x*v.y-y*v.x).
    /// For that same reason, the magnitude of the resulting Vec3 will be just the value of the component z
    pub fn cross_product_magnitude(self: Vector2f, other: Vector2f) f32 {
        return self.cross_product(other).z;
    }
};

const Vector3f = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn add(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f { .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }

    pub fn substract(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f { .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }

    pub fn dot(self: Vector3f, other: Vector3f) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn magnitude(self: Vector3f) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z);
    }

    pub fn normalized(self: Vector3f) Vector3f {
        const mag = self.magnitude();
        return Vector3f { .x = self.x / mag, .y = self.y / mag, .z = self.z / mag };
    }

    pub fn normalize(self: *Vector3f) void {
        const mag = self.magnitude();
        self.x = self.x / mag;
        self.y = self.y / mag;
        self.z = self.z / mag;
    }

    pub fn cross_product(self: Vector3f, other: Vector3f) Vector3f {
        return Vector3f {
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn scale(self: Vector3f, factor: f32) Vector3f {
        return Vector3f { .x = self.x * factor, .y = self.y * factor, .z = self.z * factor };
    }
};

const Vector4f = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn add(self: Vector4f, other: Vector4f) Vector4f {
        return Vector4f { .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z, .w = self.w + other.w };
    }

    pub fn scale(self: Vector4f, factor: f32) Vector4f {
        return Vector4f { .x = self.x * factor, .y = self.y * factor, .z = self.z * factor, .w = self.w * factor };
    }

    pub fn discard_w(self: Vector4f) Vector3f {
        return Vector3f {
            .x = self.x,
            .y = self.y,
            .z = self.z,
        };
    }

    pub fn perspective_division(self: Vector4f) Vector3f {
        return Vector3f {
            .x = self.x / self.w,
            .y = self.y / self.w,
            .z = self.z / self.w,
        };
    }
};

/// column major 4x4 matrix
const M44 = struct {
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
        const point4d = Vector4f { .x = point.x, .y = point.y, .z = point.z, .w = 1 };
        var point_transformed: Vector4f = undefined;
        point_transformed.x = self.data[0] * point4d.x + self.data[4] * point4d.y + self.data[8] * point4d.z + self.data[12] * point4d.w;
        point_transformed.y = self.data[1] * point4d.x + self.data[5] * point4d.y + self.data[9] * point4d.z + self.data[13] * point4d.w;
        point_transformed.z = self.data[2] * point4d.x + self.data[6] * point4d.y + self.data[10] * point4d.z + self.data[14] * point4d.w;
        point_transformed.w = self.data[3] * point4d.x + self.data[7] * point4d.y + self.data[11] * point4d.z + self.data[15] * point4d.w;
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

    pub fn scale(factor: f32) M44 {
        var result = M44.identity();
        result.data[0] = factor;
        result.data[5] = factor;
        result.data[10] = factor;
        return result;
    }
    
    /// The camera is looking towards -Z.
    /// The right direction is in the +X direction.
    /// The up direction is in the +Y direction.
    pub fn lookat_right_handed(camera_location: Vector3f, point_looked_at: Vector3f, up: Vector3f) M44 {
        
        { // Some notes and articles, this things can be confusing lol

            // https://stackoverflow.com/questions/349050/calculating-a-lookat-matrix
            // > # Note the example given is a left-handed, row major matrix.
            // > 
            // > So the operation is: Translate to the origin first (move by -eye),
            // > then rotate so that the vector from eye to At lines up with +z:
            // > 
            // > Basically you get the same result if you pre-multiply the rotation matrix by a translation -eye:
            // > 
            // >     [      1       0       0   0 ]   [ xaxis.x  yaxis.x  zaxis.x 0 ]
            // >     [      0       1       0   0 ] * [ xaxis.y  yaxis.y  zaxis.y 0 ]
            // >     [      0       0       1   0 ]   [ xaxis.z  yaxis.z  zaxis.z 0 ]
            // >     [ -eye.x  -eye.y  -eye.z   1 ]   [       0        0        0 1 ]
            // >     
            // >       [         xaxis.x          yaxis.x          zaxis.x  0 ]
            // >     = [         xaxis.y          yaxis.y          zaxis.y  0 ]
            // >       [         xaxis.z          yaxis.z          zaxis.z  0 ]
            // >       [ dot(xaxis,-eye)  dot(yaxis,-eye)  dot(zaxis,-eye)  1 ]
            // > 
            // > ## Additional notes:
            // > 
            // > Note that a viewing transformation is (intentionally) inverted: you multiply every vertex by
            // > this matrix to "move the world" so that the portion you want to see ends up in the canonical view volume.
            // > 
            // > Also note that the rotation matrix (call it R) component of the LookAt
            // > matrix is an inverted change of basis matrix where the rows of R are the new basis vectors in
            // > terms of the old basis vectors (hence the variable names xaxis.x, .. xaxis is the new x axis
            // > after the change of basis occurs). Because of the inversion, however, the rows and columns are transposed.
            // > 
            // > This would imply that the LookAt matrix is an orthonormal basis (they are all unit vectors and orthogonal to each other)
            // > otherwise the transpose would not be equal to it's inverse

            // http://davidlively.com/programming/graphics/opengl-matrices/row-major-vs-column-major/
            // > # Row Major VS. Column Major
            // > 
            // > ## Column-Major
            // > 
            // > - Standard widely used for OpenGL.
            // > - Values are stored in column-first order (see below)
            // > - Transpose of row-major.
            // > - The matrix must be to the LEFT of the multiply operator
            // > - The vertex or vector must to the RIGHT of the operator
            // > 
            // > Given a matrix:
            // > 
            // >     a00 a01 a02 a03
            // >     a10 a11 a12 a13
            // >     a20 a21 a22 a23
            // >     a30 a31 a32 a33
            // > 
            // > The values would be stored in memory in the order
            // > 
            // >     a00, a10, a20, a30, a01, a11, a21, a31, a02, a12, a22, a32, a03, a13, a23, a33
            // > 
            // > Translation matrix:
            // > 
            // >     | 1 0 0 tx |   | x |     | x+w*tx |
            // >     | 0 1 0 ty |   | y |  =  | y+w*ty |
            // >     | 0 0 1 tz |   | z |     | z+w*tz |
            // >     | 0 0 0 tw |   | 1 |     |   tw   |
            // > 
            // > 
            // > ## Row-Major
            // > 
            // > - Used in DirectX and HLSL
            // > - Values are stored in row-first order
            // > - Transpose of column-major
            // > - The matrix must be to the RIGHT of the multiply operator
            // > - The vertex or vector must to the LEFT of the operator
            // > - When using the row-major convention, the matrix:
            // > 
            // > Given a matrix:
            // > 
            // >     a00 a01 a02 a03
            // >     a10 a11 a12 a13
            // >     a20 a21 a22 a23
            // >     a30 a31 a32 a33
            // > 
            // > The values would be stored in memory in the order
            // > 
            // >     a00, a01, a02, a03, a10, a11, a12, a13, a20, a21, a22, a23, a30, a31, a32, a33
            // >  
            // > Translation matrix:
            // >  
            // >                     | 0  0  0  0  |
            // >     | x, y, z, 1 |  | 0  0  0  0  |  =  | x+w∗tx, y+w∗ty, z+w∗tz, tw |
            // >                     | 0  0  0  0  | 
            // >                     | tx ty tz tw |
            // > 
            // > https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dxmatrixlookatlh
            // > https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dxmatrixlookatrh
            // > 
            // > From D3D9, Left Handed Look At
            // > 
            // >     zaxis = normal(At - Eye)
            // >     xaxis = normal(cross(Up, zaxis))
            // >     yaxis = cross(zaxis, xaxis)
            // >     
            // >      xaxis.x           yaxis.x           zaxis.x          0
            // >      xaxis.y           yaxis.y           zaxis.y          0
            // >      xaxis.z           yaxis.z           zaxis.z          0
            // >     -dot(xaxis, eye)  -dot(yaxis, eye)  -dot(zaxis, eye)  1
            // > 
            // > From D3D9, Right Handed Look At
            // > 
            // >     zaxis = normal(Eye - At)
            // >     xaxis = normal(cross(Up, zaxis))
            // >     yaxis = cross(zaxis, xaxis)
            // >     
            // >      xaxis.x            yaxis.x            zaxis.x           0
            // >      xaxis.y            yaxis.y            zaxis.y           0
            // >      xaxis.z            yaxis.z            zaxis.z           0
            // >      -dot(xaxis, eye)   -dot(yaxis, eye)   -dot(zaxis, eye)  1
            // > 
        }

        // just in case, normalize the up direction
        const normalized_up = up.normalized();
        
        // the camera looks towards the negative z axes
        // the z axes got the direction `point looked at ------> camera location`
        // 
        //     The camera is looking towards -Z.
        //     The right direction is in the +X direction.
        //     The up direction is in the +Y direction.
        // 
        const new_forward: Vector3f = camera_location.substract(point_looked_at).normalized();
        const new_right: Vector3f = normalized_up.cross_product(new_forward).normalized();
        const new_up: Vector3f = new_forward.cross_product(new_right).normalized();

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

    // the resulting matrix will map a point to NDC based on the input parameters
    pub fn orthographic_projection(left: f32, right: f32, top: f32, bottom: f32, near: f32, far: f32) M44 {
        var result = M44.identity();
        // Scale factor for X
        result.data[0] = 2 / (right - left);
        // Scale factor for Y
        result.data[5] = 2 / (top - bottom);
        // Scale factor for Z
        result.data[10] = 2 / (far - near);
        // Translate X
        result.data[12] = -(right + left) / (right - left);
        // Translate Y
        result.data[13] = -(top + bottom) / (top - bottom);
        // Translate Z
        result.data[14] = -(far + near) / (far - near);
        // Homogeneous Coordinate
        result.data[15] = 1;
        return result;
    }
    pub fn perspective_projection(fovY: f32, aspectRatio: f32, near: f32, far: f32) M44 {
        var result = M44.identity();
        // Calculate the tangent of half the vertical field of view angle (fovY)
        const tanHalfFovY: f32 = std.math.tan(fovY/2);
        // Calculate the scaling factors for X and Y axes
        result.data[0] = 1 / (aspectRatio * tanHalfFovY);
        result.data[5] = 1 / tanHalfFovY;
        // Calculate the depth-related components
        result.data[10] = (far + near) / (far - near);     // Depth scaling and translation
        result.data[11] = -1;                              // Depth scaling
        result.data[14] = (2 * far * near) / (far - near); // Depth translation
        return result;
    }


    /// This should probably go something like...
    /// 
    ///     float c = -1 / (camera.looking_at - camera.position).norm();
    ///     projection(c);
    /// 
    pub fn projection(coefficient: f32) M44 {
        var projection_matrix = M44.identity();
        projection_matrix.data[11] = coefficient;
        return projection_matrix;
    }
    
    /// Builds a "viewport" (as its called in opengl) matrix, a matrix that
    /// will map a point in the 3-dimensional cube [-1, 1]*[-1, 1]*[-1, 1]
    /// onto the screen cube [x, x+w]*[y, y+h]*[0, d],
    /// where d is the depth/resolution of the z-buffer
    pub fn viewport_i32(x: i32, y: i32, w: i32, h: i32, depth: i32) M44 {
        const xf: f32 = @floatFromInt(x);
        const yf: f32 = @floatFromInt(y);
        const wf: f32 = @floatFromInt(w);
        const hf: f32 = @floatFromInt(h);
        const depthf: f32 = @floatFromInt(depth);
        return viewport(xf, yf, wf, hf, depthf);
    }
    
    pub fn viewport(x: f32, y: f32, w: f32, h: f32, depth: f32) M44 {
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

const Camera = struct {
    position: Vector3f,
    direction: Vector3f,
    looking_at: Vector3f,
    up: Vector3f,
};

const RGBA = extern struct {
    r: u8 align(1),
    g: u8 align(1),
    b: u8 align(1),
    a: u8 align(1),
    fn scale(self: RGBA, factor: f32) RGBA {
        return RGBA {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
            .a = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.a)) * factor))),
        };
    }
    fn add(c1: RGBA, c2: RGBA) RGBA {
        const result = RGBA {
            .r = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.r))/255 + @as(f32, @floatFromInt(c2.r))/255)*255))),
            .g = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.g))/255 + @as(f32, @floatFromInt(c2.g))/255)*255))),
            .b = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.b))/255 + @as(f32, @floatFromInt(c2.b))/255)*255))),
            .a = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.a))/255 + @as(f32, @floatFromInt(c2.a))/255)*255))),
        };
        return result;
    }
    fn scale_raw(self: RGBA, factor: f32) RGBA {
        return RGBA {
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * factor),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * factor),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * factor),
            .a = @intFromFloat(@as(f32, @floatFromInt(self.a)) * factor),
        };
    }
    /// This assumes that the sum of any channel is inside the range of u8, there is no checks!
    fn add_raw(c1: RGBA, c2: RGBA) RGBA {
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
    fn blend(c1: RGBA, c2: RGBA) RGBA {
        const a1: f32 = @as(f32, @floatFromInt(c1.a)) / 255;
        const result = RGBA {
            .r = @intFromFloat((@as(f32, @floatFromInt(c1.r))/255*a1 + @as(f32, @floatFromInt(c2.r))/255*(1-a1))*255),
            .g = @intFromFloat((@as(f32, @floatFromInt(c1.g))/255*a1 + @as(f32, @floatFromInt(c2.g))/255*(1-a1))*255),
            .b = @intFromFloat((@as(f32, @floatFromInt(c1.b))/255*a1 + @as(f32, @floatFromInt(c2.b))/255*(1-a1))*255),
            .a = @intFromFloat((@as(f32, @floatFromInt(c1.a))/255*a1 + @as(f32, @floatFromInt(c2.a))/255*(1-a1))*255),
        };
        return result;
    }
    fn multiply(c1: RGBA, c2: RGBA) RGBA {
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
    comptime { std.debug.assert(@sizeOf(RGBA) == 4); }
};

const RGB = extern struct {
    r: u8 align(1),
    g: u8 align(1),
    b: u8 align(1),
    fn scale(self: RGB, factor: f32) RGB {
        return RGB {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
        };
    }
    fn scale_raw(self: RGB, factor: f32) RGB {
        return RGB {
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * factor),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * factor),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * factor),
        };
    }
    /// This assumes that the sum of any channel is inside the range of u8, there is no checks!
    fn add_raw(c1: RGB, c2: RGB) RGB {
        const result = RGB {
            .r = c1.r + c2.r,
            .g = c1.g + c2.g,
            .b = c1.b + c2.b,
        };
        return result;
    }
    comptime { std.debug.assert(@sizeOf(RGB) == 3); }
};

const ElementType = enum {
    rgb,
    rgba,
    win32_rgba,
    f32,
};

const AnyElement = union(ElementType) {
    rgb: RGB,
    rgba: RGBA,
    win32_rgba: win32.RGBA,
    f32: f32,
};

const AnyBuffer2D = union(ElementType) {
    rgb: Buffer2D(RGB),
    rgba: Buffer2D(RGBA),
    win32_rgba: Buffer2D(win32.RGBA),
    f32: Buffer2D(f32),
};

fn Buffer2D(comptime T: type) type {
    return struct {
        
        const Self = @This();
        
        data: []T,
        width: usize,
        
        fn init(data: []T, width: usize) Self {
            return .{
                .data = data,
                .width = width
            };
        }

        fn height(self: Self) usize {
            return @divExact(self.data.len, self.width);
        }

        fn set(self: Self, x: usize, y: usize, item: T) void {
            self.data[x + self.width * y] = item;
        }
        
        fn get(self: Self, x: usize, y: usize) T {
            return self.data[x + self.width*y];
        }
        
        fn at(self: Self, x: usize, y: usize) *T {
            return &self.data[x + self.width*y];
        }

    };
}

fn texture_point_sample(comptime texture_pixel_type: type, comptime uv_is_01: bool, texture_data: []texture_pixel_type, texture_width: usize, texture_height: usize, uv: Vector2f) texture_pixel_type {
    // if (uv.x < 0.02 or uv.x > 0.98 or uv.y < 0.02 or uv.y > 0.98) return texture_pixel_type { .r = 0, .g = 0, .b = 0, .a = 255 };
    const tx = if (uv_is_01) uv.x * @as(f32, @floatFromInt(texture_width)) else uv.x;
    const ty = if (uv_is_01) uv.y * @as(f32, @floatFromInt(texture_height)) else uv.y;
    // if (tx - @floor(tx) < 0.03 or tx - @floor(tx) > 0.97 or ty - @floor(ty) < 0.03 or ty - @floor(ty) > 0.97) return texture_pixel_type { .r = 90, .g = 90, .b = 90, .a = 255 };
    // if (tx - @floor(tx) > 0.45 and tx - @floor(tx) < 0.55 and ty - @floor(ty) > 0.45 and ty - @floor(ty) < 0.55) return texture_pixel_type { .r = 0, .g = 0, .b = 0, .a = 255 };
    const texel_x = @as(usize, @intFromFloat(@floor(tx)));
    const texel_y = @as(usize, @intFromFloat(@floor(ty)));
    const x = std.math.clamp(texel_x, 0, texture_width-1);
    const y = std.math.clamp(texel_y, 0, texture_height-1);
    return texture_data[x + texture_width*y];
}

fn texture_bilinear_sample(comptime texture_pixel_type: type, comptime uv_is_01: bool, texture_data: []texture_pixel_type, texture_width: usize, texture_height: usize, uv: Vector2f) texture_pixel_type {
    // if (uv.x < 0.02 or uv.x > 0.98 or uv.y < 0.02 or uv.y > 0.98) return texture_pixel_type { .r = 0, .g = 0, .b = 0, .a = 255 };
    const tx = if (uv_is_01) uv.x * @as(f32, @floatFromInt(texture_width)) else uv.x;
    const ty = if (uv_is_01) uv.y * @as(f32, @floatFromInt(texture_height)) else uv.y;
    // if (tx - @floor(tx) < 0.03 or tx - @floor(tx) > 0.97 or ty - @floor(ty) < 0.03 or ty - @floor(ty) > 0.97) return texture_pixel_type { .r = 90, .g = 90, .b = 90, .a = 255 };
    // if (tx - @floor(tx) > 0.45 and tx - @floor(tx) < 0.55 and ty - @floor(ty) > 0.45 and ty - @floor(ty) < 0.55) return texture_pixel_type { .r = 0, .g = 0, .b = 0, .a = 255 };
    
    const x_min = int(usize, @max(@floor(tx-0.5), 0));
    const x_max = @min(int(usize, @floor(tx+0.5)), texture_width-1);
    const y_min = int(usize, @max(@floor(ty-0.5), 0));
    const y_max = @min(int(usize, @floor(ty+0.5)), texture_height-1);

    if (x_min == x_max) {
        if (y_min == y_max) {
            // a corner of the texture
            const sampled_color = texture_data[y_min*texture_width+x_min];
            return sampled_color;
        }
        else {
            // left or right border of texture
            const color_bottom = texture_data[y_min*texture_width+x_min];
            const color_top = texture_data[y_max*texture_width+x_min];
            
            const weight_y: f32 = ty - (@floor(ty-0.5) + 0.5);
            
            const interpolated_color = color_bottom.scale_raw(1 - weight_y).add_raw(color_top.scale_raw(weight_y));
            return interpolated_color;
        }
    }
    else if (y_min == y_max) {
        // top or bottom border of texture
        const color_left = texture_data[y_min*texture_width+x_min];
        const color_right = texture_data[y_min*texture_width+x_max];
        
        const weight_x: f32 = tx - (@floor(tx-0.5) + 0.5);
        
        const interpolated_color = color_left.scale_raw(1 - weight_x).add_raw(color_right.scale_raw(weight_x));
        return interpolated_color;
    }
    else {
        const color_bottom_left = texture_data[y_min*texture_width+x_min];
        const color_bottom_right = texture_data[y_min*texture_width+x_max];
        const color_top_left = texture_data[y_max*texture_width+x_min];
        const color_top_right = texture_data[y_max*texture_width+x_max];
        
        const weight_x: f32 = tx - (@floor(tx-0.5) + 0.5);
        const weight_y: f32 = ty - (@floor(ty-0.5) + 0.5);
        
        const interpolated_color_1 = color_bottom_left.scale_raw(1 - weight_x).add_raw(color_bottom_right.scale_raw(weight_x));
        const interpolated_color_2 = color_top_left.scale_raw(1 - weight_x).add_raw(color_top_right.scale_raw(weight_x));
        const interpolated_color_3 = interpolated_color_1.scale_raw(1 - weight_y).add_raw(interpolated_color_2.scale_raw(weight_y));

        return interpolated_color_3;
    }
}

const OBJ = struct {
    
    /// This OBJ reader is very barebones and will crash if the OBJ doesn't meet a number of things I expect it to
    /// lines must have shape of `v f32 f32 f32`, `vt f32 f32`, `vn f32 f32 f32` or `f u32/u32/u32 u32/u32/u32 u32/u32/u32`.
    /// even tho technically OBJ allows for some variance there.
    /// Returns a []f32 buffer that must be freed by the caller.
    /// The layout of the buffer returned is as follows:
    /// [ location_x, location_y, location_z, texture_u, texture_v, normal_x, normal_y, normal_z ] x 3 x number of triangles
    /// `const number_of_triangles = @divExacty(buffer.len, 8*3)`
    fn from_file(allocator: std.mem.Allocator, file_path: [] const u8) ![]f32 {
        
        const Face = struct {
            vertex_indices: [3]u32 = undefined,
            uv_indices: [3]u32 = undefined,
            normal_indices: [3]u32 = undefined,
        };

        var vertices = std.ArrayList(Vector3f).init(allocator);
        defer vertices.deinit();
        var normals = std.ArrayList(Vector3f).init(allocator);
        defer normals.deinit();
        var uvs = std.ArrayList(Vector2f).init(allocator);
        defer uvs.deinit();
        var faces = std.ArrayList(Face).init(allocator);
        defer faces.deinit();

        var file = std.fs.cwd().openFile(file_path, .{}) catch return error.CantOpenFile;
        defer file.close();
        var buf_reader = std.io.bufferedReader(file.reader());
        
        // line by line read the obj file and parse its content
        var current_line_buffer: [1024]u8 = undefined;
        while (try buf_reader.reader().readUntilDelimiterOrEof(&current_line_buffer, '\n')) |the_line| {
            // If the file has windows style line endings ignore the \r at the end of each line
            const line_content = if (the_line[the_line.len-1] == '\r') the_line[0..the_line.len-1] else the_line;
            // skip empty lines
            if (line_content.len == 0) continue;
            // skip comments
            if (line_content[0] == '#') continue;
            
            if (std.mem.eql(u8, line_content[0..2], "v ")) {
                // vertex
                // List of geometric vertices, with (x, y, z, [w]) coordinates, w is optional and defaults to 1.0.
                // example: v 0.123 0.234 0.345 1.0
                var values: [3]f32 = undefined;
                var i: usize = 2;
                var start = i;
                for (0..3) |j| {
                    while (start<line_content.len and line_content[start] == ' ') : ({start += 1; i += 1;}) {} // skip spaces
                    while (i<line_content.len and line_content[i] != ' ') : (i += 1) {}
                    const f32_string = line_content[start..i];
                    const f32_value = try std.fmt.parseFloat(f32, f32_string);
                    values[j] = f32_value;
                    start = i+1;
                    i = start;
                }
                const vertex = Vector3f { .x = values[0], .y = values[1], .z = values[2] };
                // std.debug.print("{s}\n", .{line_content});
                // std.debug.print("{?}\n", .{vertex});
                std.debug.assert(vertex.x>=-1 and vertex.x<=1);
                std.debug.assert(vertex.y>=-1 and vertex.y<=1);
                std.debug.assert(vertex.z>=-1 and vertex.z<=1);
                try vertices.append(vertex);
            }
            else if (std.mem.eql(u8, line_content[0..3], "vt ")) {
                // UVs
                // List of texture coordinates, in (u, [v, w]) coordinates, these will vary between 0 and 1. v, w are optional and default to 0.
                // example: vt 0.500 1 [0]
                var values: [2]f32 = undefined;
                var i: usize = 3;
                var start = i;
                for (0..2) |j| {
                    while (start<line_content.len and line_content[start] == ' ') : ({start += 1; i += 1;}) {} // skip spaces
                    while (i<line_content.len and line_content[i] != ' ') : (i += 1) {}
                    const f32_string = line_content[start..i];
                    const f32_value = try std.fmt.parseFloat(f32, f32_string);
                    values[j] = f32_value;
                    start = i+1;
                    i = start;
                }
                const uv = Vector2f { .x = values[0], .y = values[1] };
                std.debug.assert(uv.x>=0 and uv.x<=1);
                std.debug.assert(uv.y>=0 and uv.y<=1);
                try uvs.append(uv);
            }
            else if (std.mem.eql(u8, line_content[0..3], "vn ")) {
                // normals
                // List of vertex normals in (x,y,z) form; normals might not be unit vectors.
                // example: vn 0.707 0.000 0.707
                var values: [3]f32 = undefined;
                var i: usize = 3;
                var start = i;
                for (0..3) |j| {
                    while (start<line_content.len and line_content[start] == ' ') : ({start += 1; i += 1;}) {} // skip spaces
                    while (i<line_content.len and line_content[i] != ' ') : (i += 1) {}
                    const f32_string = line_content[start..i];
                    const f32_value = try std.fmt.parseFloat(f32, f32_string);
                    values[j] = f32_value;
                    start = i+1;
                    i = start;
                }
                const normal = Vector3f { .x = values[0], .y = values[1], .z = values[2] };
                std.debug.assert(normal.x>=-1 and normal.x<=1);
                std.debug.assert(normal.y>=-1 and normal.y<=1);
                std.debug.assert(normal.z>=-1 and normal.z<=1);
                try normals.append(normal);
            }
            else if (std.mem.eql(u8, line_content[0..2], "f ")) {
                // face
                // Polygonal face element (see below)
                // example: f 6/4/1 3/5/3 7/6/5
                // f loc_idx/text_idx/normal_idx loc_idx/text_idx/normal_idx loc_idx/text_idx/normal_idx
                
                var vertex_indices: [3]u32 = undefined;
                var uv_indices: [3]u32 = undefined;
                var normal_indices: [3]u32 = undefined;
                
                var i: usize = 2;
                var start = i;
                for (0..3) |j| {
                    while (start<line_content.len and line_content[start] == ' ') : ({start += 1; i += 1;}) {} // skip spaces
                    while (i<line_content.len and line_content[i] != ' ') : (i += 1) {}
                    const index_trio_string = line_content[start..i];
                    var i_2: usize = 0;
                    var start_2 = i_2;
                    inline for (0..3) |k| {
                        while (i_2<index_trio_string.len and index_trio_string[i_2] != '/') : (i_2 += 1) {}
                        const index_of_slash = i_2;
                        const u32_string = index_trio_string[start_2..index_of_slash];
                        const u32_value = try std.fmt.parseUnsigned(u32, u32_string, 10);
                        switch (k) {
                            // in wavefront obj all indices start at 1, not zero, so substract 1 from every index
                            0 => vertex_indices[j] = u32_value - 1,
                            1 => uv_indices[j] = u32_value - 1,
                            2 => normal_indices[j] = u32_value - 1,
                            else => @panic("what the hell? k 0..3 is not 0..3")
                        }
                        start_2 = i_2 + 1;
                        i_2 = start_2;
                    }

                    start = i+1;
                    i = start;
                }

                const face = Face { .vertex_indices = vertex_indices, .uv_indices = uv_indices, .normal_indices = normal_indices };
                try faces.append(face);
            }
            
        }

        // std.debug.print("A {?}\n", .{ faces.items[2].uv_indices[0] });
        // std.debug.print("A {?}\n", .{ faces.items[2].uv_indices[1] });
        // std.debug.print("A {?}\n", .{ faces.items[2].uv_indices[2] });
        
        // std.debug.print("B {?}\n", .{ uvs.items[faces.items[2].uv_indices[0]] });
        // std.debug.print("B {?}\n", .{ uvs.items[faces.items[2].uv_indices[1]] });
        // std.debug.print("B {?}\n", .{ uvs.items[faces.items[2].uv_indices[2]] });

        // const VertexLayout = struct {
        //     location_x: f32,
        //     location_y: f32,
        //     location_z: f32,
        //     texture_u: f32,
        //     texture_v: f32,
        //     normal_x: f32,
        //     normal_y: f32,
        //     normal_z: f32,
        // };

        var vertex_buffer = try allocator.alloc(f32, faces.items.len * 3 * 8);
        for (faces.items, 0..) |face, face_index| {

            vertex_buffer[face_index*3*8 + 8*0 + 0] = vertices.items[face.vertex_indices[0]].x;
            vertex_buffer[face_index*3*8 + 8*0 + 1] = vertices.items[face.vertex_indices[0]].y;
            vertex_buffer[face_index*3*8 + 8*0 + 2] = vertices.items[face.vertex_indices[0]].z;
            vertex_buffer[face_index*3*8 + 8*0 + 3] = uvs.items[face.uv_indices[0]].x;
            vertex_buffer[face_index*3*8 + 8*0 + 4] = uvs.items[face.uv_indices[0]].y;
            vertex_buffer[face_index*3*8 + 8*0 + 5] = normals.items[face.normal_indices[0]].x;
            vertex_buffer[face_index*3*8 + 8*0 + 6] = normals.items[face.normal_indices[0]].y;
            vertex_buffer[face_index*3*8 + 8*0 + 7] = normals.items[face.normal_indices[0]].z;
                
            vertex_buffer[face_index*3*8 + 8*1 + 0] = vertices.items[face.vertex_indices[1]].x;
            vertex_buffer[face_index*3*8 + 8*1 + 1] = vertices.items[face.vertex_indices[1]].y;
            vertex_buffer[face_index*3*8 + 8*1 + 2] = vertices.items[face.vertex_indices[1]].z;
            vertex_buffer[face_index*3*8 + 8*1 + 3] = uvs.items[face.uv_indices[1]].x;
            vertex_buffer[face_index*3*8 + 8*1 + 4] = uvs.items[face.uv_indices[1]].y;
            vertex_buffer[face_index*3*8 + 8*1 + 5] = normals.items[face.normal_indices[1]].x;
            vertex_buffer[face_index*3*8 + 8*1 + 6] = normals.items[face.normal_indices[1]].y;
            vertex_buffer[face_index*3*8 + 8*1 + 7] = normals.items[face.normal_indices[1]].z;

            vertex_buffer[face_index*3*8 + 8*2 + 0] = vertices.items[face.vertex_indices[2]].x;
            vertex_buffer[face_index*3*8 + 8*2 + 1] = vertices.items[face.vertex_indices[2]].y;
            vertex_buffer[face_index*3*8 + 8*2 + 2] = vertices.items[face.vertex_indices[2]].z;
            vertex_buffer[face_index*3*8 + 8*2 + 3] = uvs.items[face.uv_indices[2]].x;
            vertex_buffer[face_index*3*8 + 8*2 + 4] = uvs.items[face.uv_indices[2]].y;
            vertex_buffer[face_index*3*8 + 8*2 + 5] = normals.items[face.normal_indices[2]].x;
            vertex_buffer[face_index*3*8 + 8*2 + 6] = normals.items[face.normal_indices[2]].y;
            vertex_buffer[face_index*3*8 + 8*2 + 7] = normals.items[face.normal_indices[2]].z;

        }
        return vertex_buffer;
    }
};

const TGA = struct {

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
        pub fn get_attribute_bits_per_pixel(self: Self) u4 {
            return @intCast(self.the_byte >> 4);
        }

        /// must be 0
        pub fn get_reserved(self: Self) u1 {
            return @intCast((self.the_byte | 0b00001000) >> 3);
        }

        /// 0 = Origin in lower left-hand corner
        /// 1 = Origin in upper left-hand corner
        pub fn get_screen_origin_bit(self: Self) u1 {
            return @intCast((self.the_byte | 0b00000100) >> 2);
        }

        /// 00 = non-interleaved.                        
        /// 01 = two-way (even/odd) interleaving.        
        /// 10 = four way interleaving.                  
        /// 11 = reserved.                               
        pub fn get_interleaving(self: Self) u2 {
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

    /// This can only read TGA files of data type 2 (unmapped, uncompressed, rgb(a) images)
    fn from_file(allocator: std.mem.Allocator, file_path: [] const u8) !AnyBuffer2D {

        { // NOTE specification

            // Version 1.0 of TGA Spec
            // http://www.paulbourke.net/dataformats/tga/
            // https://www.gamers.org/dEngine/quake3/TGA.txt
            { // DATA TYPE 2: Unmapped RGB
                //     ________________________________________________________________________________
                //     | Offset | Length |                     Description                            |
                //     |--------|--------|------------------------------------------------------------|
                //     |    0   |     1  |  Number of Characters in Identification Field.             |
                //     |        |        |                                                            |
                //     |        |        |  This field is a one-byte unsigned integer, specifying     |
                //     |        |        |  the length of the Image Identification Field.  Its value  |
                //     |        |        |  is 0 to 255.  A value of 0 means that no Image            |
                //     |        |        |  Identification Field is included.                         |
                //     |--------|--------|------------------------------------------------------------|
                //     |    1   |     1  |  Color Map Type.                                           |
                //     |        |        |                                                            |
                //     |        |        |  This field contains either 0 or 1.  0 means no color map  |
                //     |        |        |  is included.  1 means a color map is included, but since  |
                //     |        |        |  this is an unmapped image it is usually ignored.  TIPS    |
                //     |        |        |  ( a Targa paint system ) will set the border color        |
                //     |        |        |  the first map color if it is present.                     |
                //     |--------|--------|------------------------------------------------------------|
                //     |    2   |     1  |  Image Type Code.                                          |
                //     |        |        |                                                            |
                //     |        |        |  This field will always contain a binary 2.                |
                //     |        |        |  ( That's what makes it Data Type 2 ).                     |
                //     |--------|--------|------------------------------------------------------------|
                //     |    3   |     5  |  Color Map Specification.                                  |
                //     |        |        |                                                            |
                //     |        |        |  Ignored if Color Map Type is 0; otherwise, interpreted    |
                //     |        |        |  as follows:                                               |
                //     |    3   |     2  |  Color Map Origin.                                         |
                //     |        |        |  Integer ( lo-hi ) index of first color map entry.         |
                //     |    5   |     2  |  Color Map Length.                                         |
                //     |        |        |  Integer ( lo-hi ) count of color map entries.             |
                //     |    7   |     1  |  Color Map Entry Size.                                     |
                //     |        |        |  Number of bits in color map entry.  16 for the Targa 16,  |
                //     |        |        |  24 for the Targa 24, 32 for the Targa 32.                 |
                //     |--------|--------|------------------------------------------------------------|
                //     |    8   |    10  |  Image Specification.                                      |
                //     |        |        |                                                            |
                //     |    8   |     2  |  X Origin of Image.                                        |
                //     |        |        |  Integer ( lo-hi ) X coordinate of the lower left corner   |
                //     |        |        |  of the image.                                             |
                //     |   10   |     2  |  Y Origin of Image.                                        |
                //     |        |        |  Integer ( lo-hi ) Y coordinate of the lower left corner   |
                //     |        |        |  of the image.                                             |
                //     |   12   |     2  |  Width of Image.                                           |
                //     |        |        |  Integer ( lo-hi ) width of the image in pixels.           |
                //     |   14   |     2  |  Height of Image.                                          |
                //     |        |        |  Integer ( lo-hi ) height of the image in pixels.          |
                //     |   16   |     1  |  Image Pixel Size.                                         |
                //     |        |        |  Number of bits in a pixel.  This is 16 for Targa 16,      |
                //     |        |        |  24 for Targa 24, and .... well, you get the idea.         |
                //     |   17   |     1  |  Image Descriptor Byte.                                    |
                //     |        |        |  Bits 3-0 - number of attribute bits associated with each  |
                //     |        |        |             pixel.  For the Targa 16, this would be 0 or   |
                //     |        |        |             1.  For the Targa 24, it should be 0.  For     |
                //     |        |        |             Targa 32, it should be 8.                      |
                //     |        |        |  Bit 4    - reserved.  Must be set to 0.                   |
                //     |        |        |  Bit 5    - screen origin bit.                             |
                //     |        |        |             0 = Origin in lower left-hand corner.          |
                //     |        |        |             1 = Origin in upper left-hand corner.          |
                //     |        |        |             Must be 0 for Truevision images.               |
                //     |        |        |  Bits 7-6 - Data storage interleaving flag.                |
                //     |        |        |             00 = non-interleaved.                          |
                //     |        |        |             01 = two-way (even/odd) interleaving.          |
                //     |        |        |             10 = four way interleaving.                    |
                //     |        |        |             11 = reserved.                                 |
                //     |--------|--------|------------------------------------------------------------|
                //     |   18   | varies |  Image Identification Field.                               |
                //     |        |        |                                                            |
                //     |        |        |  Contains a free-form identification field of the length   |
                //     |        |        |  specified in byte 1 of the image record.  It's usually    |
                //     |        |        |  omitted ( length in byte 1 = 0 ), but can be up to 255    |
                //     |        |        |  characters.  If more identification information is        |
                //     |        |        |  required, it can be stored after the image data.          |
                //     |--------|--------|------------------------------------------------------------|
                //     | varies | varies |  Color map data.                                           |
                //     |        |        |                                                            |
                //     |        |        |  If the Color Map Type is 0, this field doesn't exist.     |
                //     |        |        |  Otherwise, just read past it to get to the image.         |
                //     |        |        |  The Color Map Specification describes the size of each    |
                //     |        |        |  entry, and the number of entries you'll have to skip.     |
                //     |        |        |  Each color map entry is 2, 3, or 4 bytes.                 |
                //     |--------|--------|------------------------------------------------------------|
                //     | varies | varies |  Image Data Field.                                         |
                //     |        |        |                                                            |
                //     |        |        |  This field specifies (width) x (height) pixels.  Each     |
                //     |        |        |  pixel specifies an RGB color value, which is stored as    |
                //     |        |        |  an integral number of bytes.                              |
                //     |        |        |  The 2 byte entry is broken down as follows:               |
                //     |        |        |  ARRRRRGG GGGBBBBB, where each letter represents a bit.    |
                //     |        |        |  But, because of the lo-hi storage order, the first byte   |
                //     |        |        |  coming from the file will actually be GGGBBBBB, and the   |
                //     |        |        |  second will be ARRRRRGG. "A" represents an attribute bit. |
                //     |        |        |  The 3 byte entry contains 1 byte each of blue, green,     |
                //     |        |        |  and red.                                                  |
                //     |        |        |  The 4 byte entry contains 1 byte each of blue, green,     |
                //     |        |        |  red, and attribute.  For faster speed (because of the     |
                //     |        |        |  hardware of the Targa board itself), Targa 24 images are  |
                //     |        |        |  sometimes stored as Targa 32 images.                      |
                //     --------------------------------------------------------------------------------
                // 
            }
            { // DATA TYPE 10: Run Length Encoded, RGB images
                // 
                // ________________________________________________________________________________
                // | Offset | Length |                     Description                            |
                // |--------|--------|------------------------------------------------------------|
                // |    0   |     1  |  Number of Characters in Identification Field.             |
                // |        |        |                                                            |
                // |        |        |  This field is a one-byte unsigned integer, specifying     |
                // |        |        |  the length of the Image Identification Field.  Its range  |
                // |        |        |  is 0 to 255.  A value of 0 means that no Image            |
                // |        |        |  Identification Field is included.                         |
                // |--------|--------|------------------------------------------------------------|
                // |    1   |     1  |  Color Map Type.                                           |
                // |        |        |                                                            |
                // |        |        |  This field contains either 0 or 1.  0 means no color map  |
                // |        |        |  is included.  1 means a color map is included, but since  |
                // |        |        |  this is an unmapped image it is usually ignored.  TIPS    |
                // |        |        |  ( a Targa paint system ) will set the border color        |
                // |        |        |  the first map color if it is present.  Wowie zowie.       |
                // |--------|--------|------------------------------------------------------------|
                // |    2   |     1  |  Image Type Code.                                          |
                // |        |        |                                                            |
                // |        |        |  Binary 10 for this type of image.                         |
                // |--------|--------|------------------------------------------------------------|
                // |    3   |     5  |  Color Map Specification.                                  |
                // |        |        |                                                            |
                // |        |        |  Ignored if Color Map Type is 0; otherwise, interpreted    |
                // |        |        |  as follows:                                               |
                // |    3   |     2  |  Color Map Origin.                                         |
                // |        |        |  Integer ( lo-hi ) index of first color map entry.         |
                // |    5   |     2  |  Color Map Length.                                         |
                // |        |        |  Integer ( lo-hi ) count of color map entries.             |
                // |    7   |     1  |  Color Map Entry Size.                                     |
                // |        |        |  Number of bits in color map entry.  This value is 16 for  |
                // |        |        |  the Targa 16, 24 for the Targa 24, 32 for the Targa 32.   |
                // |--------|--------|------------------------------------------------------------|
                // |    8   |    10  |  Image Specification.                                      |
                // |        |        |                                                            |
                // |    8   |     2  |  X Origin of Image.                                        |
                // |        |        |  Integer ( lo-hi ) X coordinate of the lower left corner   |
                // |        |        |  of the image.                                             |
                // |   10   |     2  |  Y Origin of Image.                                        |
                // |        |        |  Integer ( lo-hi ) Y coordinate of the lower left corner   |
                // |        |        |  of the image.                                             |
                // |   12   |     2  |  Width of Image.                                           |
                // |        |        |  Integer ( lo-hi ) width of the image in pixels.           |
                // |   14   |     2  |  Height of Image.                                          |
                // |        |        |  Integer ( lo-hi ) height of the image in pixels.          |
                // |   16   |     1  |  Image Pixel Size.                                         |
                // |        |        |  Number of bits in a pixel.  This is 16 for Targa 16,      |
                // |        |        |  24 for Targa 24, and .... well, you get the idea.         |
                // |   17   |     1  |  Image Descriptor Byte.                                    |
                // |        |        |  Bits 3-0 - number of attribute bits associated with each  |
                // |        |        |             pixel.  For the Targa 16, this would be 0 or   |
                // |        |        |             1.  For the Targa 24, it should be 0.  For the |
                // |        |        |             Targa 32, it should be 8.                      |
                // |        |        |  Bit 4    - reserved.  Must be set to 0.                   |
                // |        |        |  Bit 5    - screen origin bit.                             |
                // |        |        |             0 = Origin in lower left-hand corner.          |
                // |        |        |             1 = Origin in upper left-hand corner.          |
                // |        |        |             Must be 0 for Truevision images.               |
                // |        |        |  Bits 7-6 - Data storage interleaving flag.                |
                // |        |        |             00 = non-interleaved.                          |
                // |        |        |             01 = two-way (even/odd) interleaving.          |
                // |        |        |             10 = four way interleaving.                    |
                // |        |        |             11 = reserved.                                 |
                // |--------|--------|------------------------------------------------------------|
                // |   18   | varies |  Image Identification Field.                               |
                // |        |        |  Contains a free-form identification field of the length   |
                // |        |        |  specified in byte 1 of the image record.  It's usually    |
                // |        |        |  omitted ( length in byte 1 = 0 ), but can be up to 255    |
                // |        |        |  characters.  If more identification information is        |
                // |        |        |  required, it can be stored after the image data.          |
                // |--------|--------|------------------------------------------------------------|
                // | varies | varies |  Color map data.                                           |
                // |        |        |                                                            |
                // |        |        |  If the Color Map Type is 0, this field doesn't exist.     |
                // |        |        |  Otherwise, just read past it to get to the image.         |
                // |        |        |  The Color Map Specification, describes the size of each   |
                // |        |        |  entry, and the number of entries you'll have to skip.     |
                // |        |        |  Each color map entry is 2, 3, or 4 bytes.                 |
                // |--------|--------|------------------------------------------------------------|
                // | varies | varies |  Image Data Field.                                         |
                // |        |        |                                                            |
                // |        |        |  This field specifies (width) x (height) pixels.  The      |
                // |        |        |  RGB color information for the pixels is stored in         |
                // |        |        |  packets.  There are two types of packets:  Run-length     |
                // |        |        |  encoded packets, and raw packets.  Both have a 1-byte     |
                // |        |        |  header, identifying the type of packet and specifying a   |
                // |        |        |  count, followed by a variable-length body.                |
                // |        |        |  The high-order bit of the header is "1" for the           |
                // |        |        |  run length packet, and "0" for the raw packet.            |
                // |        |        |                                                            |
                // |        |        |  For the run-length packet, the header consists of:        |
                // |        |        |      __________________________________________________    |
                // |        |        |      | 1 bit |   7 bit repetition count minus 1.      |    |
                // |        |        |      |   ID  |   Since the maximum value of this      |    |
                // |        |        |      |       |   field is 127, the largest possible   |    |
                // |        |        |      |       |   run size would be 128.               |    |
                // |        |        |      |-------|----------------------------------------|    |
                // |        |        |      |   1   |  C     C     C     C     C     C    C  |    |
                // |        |        |      --------------------------------------------------    |
                // |        |        |                                                            |
                // |        |        |  For the raw packet, the header consists of:               |
                // |        |        |      __________________________________________________    |
                // |        |        |      | 1 bit |   7 bit number of pixels minus 1.      |    |
                // |        |        |      |   ID  |   Since the maximum value of this      |    |
                // |        |        |      |       |   field is 127, there can never be     |    |
                // |        |        |      |       |   more than 128 pixels per packet.     |    |
                // |        |        |      |-------|----------------------------------------|    |
                // |        |        |      |   0   |  N     N     N     N     N     N    N  |    |
                // |        |        |      --------------------------------------------------    |
                // |        |        |                                                            |
                // |        |        |  For the run length packet, the header is followed by      |
                // |        |        |  a single color value, which is assumed to be repeated     |
                // |        |        |  the number of times specified in the header.  The         |
                // |        |        |  packet may cross scan lines ( begin on one line and end   |
                // |        |        |  on the next ).                                            |
                // |        |        |  For the raw packet, the header is followed by             |
                // |        |        |  the number of color values specified in the header.       |
                // |        |        |  The color entries themselves are two bytes, three bytes,  |
                // |        |        |  or four bytes ( for Targa 16, 24, and 32 ), and are       |
                // |        |        |  broken down as follows:                                   |
                // |        |        |  The 2 byte entry -                                        |
                // |        |        |  ARRRRRGG GGGBBBBB, where each letter represents a bit.    |
                // |        |        |  But, because of the lo-hi storage order, the first byte   |
                // |        |        |  coming from the file will actually be GGGBBBBB, and the   |
                // |        |        |  second will be ARRRRRGG. "A" represents an attribute bit. |
                // |        |        |  The 3 byte entry contains 1 byte each of blue, green,     |
                // |        |        |  and red.                                                  |
                // |        |        |  The 4 byte entry contains 1 byte each of blue, green,     |
                // |        |        |  red, and attribute.  For faster speed (because of the     |
                // |        |        |  hardware of the Targa board itself), Targa 24 image are   |
                // |        |        |  sometimes stored as Targa 32 images.                      |
                // --------------------------------------------------------------------------------
            }
        }
        
        var buffer_header = allocator.alloc(u8, @sizeOf(Header)) catch return error.OutOfMemory;
        defer allocator.free(buffer_header);
        
        var file = std.fs.cwd().openFile(file_path, .{}) catch return error.CantOpenFile;
        defer file.close();

        {
            const read_size = file.read(buffer_header) catch return error.ReadHeader;
            if (read_size != @sizeOf(Header)) return error.ReadHeader;
        }
        
        // Parse the header only to figure out the size of the pixel data
        const header: *Header = std.mem.bytesAsValue(Header, buffer_header[0..18]);

        { // NOTE Example of a TGA header, the first 18 bytes and it after being parsed
            // 
            // 00000000   00 00 0A 00 00 00 00 00 00 00 00 00 00 04 00 04  ................
            // 00000010   18 00 3F 37 45 58 3F 39 47 5A 3F 38 46 59 3F 37  ..?7EX?9GZ?8FY?7
            // 00000020   45 58 3F 37 44 5A 00 36 44 57 3F 37 45 58 3F 38  EX?7DZ.6DW?7EX?8
            // 00000030   46 59 00 36 42 5A 3F 35 41 59 00 36 42 5A 3F 37  FY.6BZ?5AY.6BZ?7
            // 00000040   43 5B 3F 37 45 58 3F 36 44 57 07 35 41 59 36 43  C[?7EX?6DW.5AY6C
            // 00000050   59 37 44 5A 38 45 5B 38 46 59 37 45 58 36 44 56  Y7DZ8E[8FY7EX6DV
            // 00000060   35 43 55 3F 37 45 58 3F 34 42 55 00 33 41 54 3F  5CU?7EX?4BU.3AT?
            // 00000070   32 40 53 00 33 41 54 3F 31 3F 52 3F 32 40 53 3F  2@S.3AT?1?R?2@S?
            // 
            // std.debug.print("{?}", .{header.*});
            // 
            //     Header {
            //         .id_length = 0,
            //         .color_map_type = 0,
            //         .data_type = DataTypeCode.RunLengthEncodedRgb,
            //         .color_map_spec = ColorMapSpecification {
            //             .origin = 0,
            //             .length = 0,
            //             .entry_size = 0
            //         },
            //         .image_spec = ImageSpecification {
            //             .x_origin = 0,
            //             .y_origin = 0,
            //             .width = 1024,
            //             .height = 1024,
            //             .bits_per_pixel = BitsPerPixel.RGB,
            //             .image_descriptor = ImageDescriptorByte { .the_byte = 0 }
            //         }
            //     };
            //
        } 
        
        { // validate the file
            // only care about RGB and RGBA images
            switch (@intFromEnum(header.image_spec.bits_per_pixel)) {
                24, 32 => {},
                else => return error.FileNotSupported,
            }
            // only care about non color mapped, non compressed files
            // 2023/06/29 and now also run length encoded rgb images!
            switch (@intFromEnum(header.data_type)) {
                2, 10 => {},
                else => return error.FileNotSupported,
            }
            // if its not color mapped why does it have a color map?
            if (header.color_map_type != 0) {
                // const color_map_size = @intCast(usize, @intCast(i16, header.color_map_spec.entry_size) * header.color_map_spec.length);
                return error.MalformedTgaFile;
            }
            // this shouldn't be a thing, probably...
            if (header.image_spec.width <= 0 or header.image_spec.height <= 0) return error.MalformedTgaFile;
        }
        const width: usize = @intCast(header.image_spec.width);
        const height: usize = @intCast(header.image_spec.height);

        // If there is a comment/id or whatever, skip it
        const id_length: usize = @intCast(header.id_length);
        if (id_length > 0) {
            file.seekTo(@sizeOf(Header) + id_length) catch return error.SeekTo;
        }
    
        // NOTE If there was a color map that would have to be skipped but for now we just assume there is not, but beware of malformed tga files I guess

        switch (header.data_type) {
            DataTypeCode.RunLengthEncodedRgb => {
                { // NOTE some details on how to parse run length encoded
                    // > This field specifies (width) x (height) pixels. The RGB color information for the pixels is stored in packets. There are two types of packets: Run-length
                    // > encoded packets, and raw packets. Both have a 1-byte header, identifying the type of packet and specifying a count, followed by a variable-length body.
                    // > The high-order bit of the header is "1" for the run length packet, and "0" for the raw packet.
                    // > 
                    // > For the run-length packet, the header consists of:
                    // >     __________________________________________________
                    // >     | 1 bit |   7 bit repetition count minus 1.      |
                    // >     |   ID  |   Since the maximum value of this      |
                    // >     |       |   field is 127, the largest possible   |
                    // >     |       |   run size would be 128.               |
                    // >     |-------|----------------------------------------|
                    // >     |   1   |  C     C     C     C     C     C    C  |
                    // >     --------------------------------------------------
                    // >
                    // > For the raw packet, the header consists of:
                    // >     __________________________________________________
                    // >     | 1 bit |   7 bit number of pixels minus 1.      |
                    // >     |   ID  |   Since the maximum value of this      |
                    // >     |       |   field is 127, there can never be     |
                    // >     |       |   more than 128 pixels per packet.     |
                    // >     |-------|----------------------------------------|
                    // >     |   0   |  N     N     N     N     N     N    N  |
                    // >     --------------------------------------------------
                    // >
                    // > For the run length packet, the header is followed by a single color value, which is assumed to be repeated the number of times specified in the header.
                    // > The packet may cross scan lines ( begin on one line and end on the next ).
                    // > For the raw packet, the header is followed by the number of color values specified in the header.
                    // > The color entries themselves are two bytes, three bytes, or four bytes ( for Targa 16, 24, and 32 ), and are broken down as follows:
                    // > The 2 byte entry - ARRRRRGG GGGBBBBB, where each letter represents a bit. But, because of the lo-hi storage order, the first byte coming from the file will actually be GGGBBBBB, and the
                    // > second will be ARRRRRGG. "A" represents an attribute bit. The 3 byte entry contains 1 byte each of blue, green, and red. The 4 byte entry contains 1 byte each of blue, green,
                    // > red, and attribute. For faster speed (because of the hardware of the Targa board itself), Targa 24 image are sometimes stored as Targa 32 images.
                }
                
                // Allocate anough memory to store the pixel data
                const pixel_data_size = width * height * @as(usize, @intCast(@divExact(@intFromEnum(header.image_spec.bits_per_pixel), 8)));
                var buffer_pixel_data: []u8 = allocator.alloc(u8, pixel_data_size) catch return error.OutOfMemory;

                var pixel_packet_header: [1]u8 = undefined;
                var pixel_index: usize = 0;
                while (pixel_index < width * height) {
                    const read_size = file.read(&pixel_packet_header) catch return error.ReadPixelDataHeader;
                    if (read_size != 1) return error.ReadPixelDataHeaderReadSize;
                    const is_run_length_packet = (pixel_packet_header[0] >> 7) == 1;
                    const count: usize = @as(usize, @intCast(pixel_packet_header[0] & 0b01111111)) + 1;
                    std.debug.assert(count <= 128);
                    if (is_run_length_packet) {
                        switch (header.image_spec.bits_per_pixel) {
                            .RGB => {
                                var color: [@sizeOf(RGB)]u8 = undefined;
                                const read_bytes = file.read(&color) catch return error.ReadPixelData;
                                std.debug.assert(read_bytes == @sizeOf(RGB));
                                for (pixel_index .. pixel_index+count) |i| {
                                    std.mem.copyForwards(u8, buffer_pixel_data[i*@sizeOf(RGB)..i*@sizeOf(RGB)+@sizeOf(RGB)], &color);
                                }
                            },
                            .RGBA => {
                                var color: [@sizeOf(RGBA)]u8 = undefined;
                                const read_bytes = file.read(&color) catch return error.ReadPixelData;
                                std.debug.assert(read_bytes == @sizeOf(RGBA));
                                for (pixel_index .. pixel_index+count) |i| {
                                    std.mem.copyForwards(u8, buffer_pixel_data[i*@sizeOf(RGBA)..i*@sizeOf(RGBA)+@sizeOf(RGBA)], &color);
                                }
                            },
                        }
                    }
                    else {
                        switch (header.image_spec.bits_per_pixel) {
                            .RGB => {
                                // there can never be more than [@sizeOf(RGBA)*128]u8 bytes worth of pixel data per packet, but there can be less.
                                var color: [@sizeOf(RGB)*128]u8 = undefined;
                                const read_bytes = file.read(color[0..count*@sizeOf(RGB)]) catch return error.ReadPixelData;
                                std.debug.assert(read_bytes == count*@sizeOf(RGB));
                                std.mem.copyForwards(
                                    u8,
                                    buffer_pixel_data[pixel_index*@sizeOf(RGB) .. pixel_index*@sizeOf(RGB) + count*@sizeOf(RGB)],
                                    color[0 .. count*@sizeOf(RGB)]
                                );
                            },
                            .RGBA => {
                                // there can never be more than [@sizeOf(RGBA)*128]u8 bytes worth of pixel data per packet, but there can be less.
                                var color: [@sizeOf(RGBA)*128]u8 = undefined;
                                const read_bytes = file.read(color[0..count*@sizeOf(RGBA)]) catch return error.ReadPixelData;
                                std.debug.assert(read_bytes == count*@sizeOf(RGBA));
                                std.mem.copyForwards(
                                    u8,
                                    buffer_pixel_data[pixel_index*@sizeOf(RGBA) .. pixel_index*@sizeOf(RGBA) + count*@sizeOf(RGBA)],
                                    color[0 .. count*@sizeOf(RGBA)]
                                );
                            },
                        }
                    }
                    pixel_index += count;
                }
                std.debug.assert(pixel_index == width * height);
                return switch (header.image_spec.bits_per_pixel) {
                    .RGB => AnyBuffer2D { .rgb = Buffer2D(RGB).init(std.mem.bytesAsSlice(RGB, buffer_pixel_data), width) },
                    .RGBA => AnyBuffer2D { .rgba = Buffer2D(RGBA).init(std.mem.bytesAsSlice(RGBA, buffer_pixel_data), width)  },
                };
            },
            DataTypeCode.UncompressedRgb => {
                // Only thing left is to read the pixel data
                const pixel_data_size = width * height * @as(usize, @intCast(@divExact(@intFromEnum(header.image_spec.bits_per_pixel), 8)));
                var buffer_pixel_data: []u8 = allocator.alloc(u8, pixel_data_size) catch return error.OutOfMemory;
                // allocate and let the caller handle its lifetime
                {
                    const read_size = file.read(buffer_pixel_data) catch return error.ReadPixelData;
                    if (read_size != pixel_data_size) return error.ReadPixelData;
                }

                return switch (header.image_spec.bits_per_pixel) {
                    .RGB => AnyBuffer2D { .rgb = Buffer2D(RGB).init(std.mem.bytesAsSlice(RGB, buffer_pixel_data), width) },
                    .RGBA => AnyBuffer2D { .rgba = Buffer2D(RGBA).init(std.mem.bytesAsSlice(RGBA, buffer_pixel_data), width)  },
                };
            }
        }
    }
};

const imgui_win32_impl = struct {

    const Context = struct {
        hWnd: win32.HWND,
        Time: i64,
        TicksPerSecond: i64,
    };
    
    fn init(context: *Context, window_handle: win32.HWND, out_font_texture: *Buffer2D(RGBA)) void {
        const io = imgui.c.igGetIO();        
        io.*.BackendPlatformUserData = context;
        context.hWnd = window_handle;
        var counter: win32.LARGE_INTEGER = undefined;
        var performance_frequency: win32.LARGE_INTEGER = undefined;
        _ = win32.QueryPerformanceCounter(&counter);
        _ = win32.QueryPerformanceFrequency(&performance_frequency);
        context.TicksPerSecond = performance_frequency.QuadPart;
        context.Time = counter.QuadPart;

        const main_viewport = imgui.c.igGetMainViewport();
        main_viewport.*.PlatformHandle = window_handle;
        main_viewport.*.PlatformHandleRaw = window_handle;

        var out_width: i32 = undefined;
        var out_height: i32 = undefined;
        var out_bytes_per_pixel: i32 = undefined;
        var out_pixels: [*c]u8 = undefined;
        imgui.c.ImFontAtlas_GetTexDataAsRGBA32(io.*.Fonts, &out_pixels, &out_width, &out_height, &out_bytes_per_pixel);

        const total_size: usize = @intCast(out_width * out_height);
        // out_font_texture.* = Buffer2D(RGBA).init(@ptrCast(out_pixels[0..total_size]), out_width);
        out_font_texture.* = Buffer2D(RGBA).init(std.mem.bytesAsSlice(RGBA, @as([]u8, @ptrCast(out_pixels[0..total_size]))), @intCast(out_width));
        imgui.c.ImFontAtlas_SetTexID(io.*.Fonts, out_font_texture);
    }

    fn render_draw_data(pixel_buffer: Buffer2D(win32.RGBA)) void {
        const draw_data = imgui.c.igGetDrawData();
        const clip_offset = draw_data.*.DisplayPos;
        const pos = Vector2f { .x = draw_data.*.DisplayPos.x, .y = draw_data.*.DisplayPos.y };
        const dimensions = Vector2f { .x = draw_data.*.DisplaySize.x, .y = draw_data.*.DisplaySize.y };
        // In DearImgui 0, 0 is the top left corner but on this renderer is bottom left, so I make the projection matrix with "top" and "bottom"
        // inverted so that they every point trasformed by it has its y coordinate inverted
        const projection_matrix = M44.orthographic_projection(pos.x, pos.x + dimensions.x, pos.y, pos.y + dimensions.y, 0.1, 1000);
        const viewport_matrix = M44.viewport(pos.x, pos.y, dimensions.x, dimensions.y, 255);
        if (draw_data.*.CmdLists.Data == null) return;
        const command_lists = imgui.im_vector_from(draw_data.*.CmdLists);
        const command_lists_count: usize = @intCast(draw_data.*.CmdListsCount);
        for (command_lists.data[0..command_lists_count]) |command_list| {
            const command_buffer = imgui.im_vector_from(command_list.*.CmdBuffer);
            const vertex_buffer = imgui.im_vector_from(command_list.*.VtxBuffer);
            const index_buffer = imgui.im_vector_from(command_list.*.IdxBuffer);
            for (command_buffer.used_slice()) |command| {
                const clip_min = Vector2f { .x = command.ClipRect.x - clip_offset.x, .y = command.ClipRect.y - clip_offset.y };
                const clip_max = Vector2f { .x = command.ClipRect.z - clip_offset.x, .y = command.ClipRect.w - clip_offset.y };
                const clip = Vector4f { .x = clip_min.x, .y = clip_max.y, .z = clip_max.x, .w = clip_min.y };
                if (clip_max.x <= clip_min.x or clip_max.y <= clip_min.y) continue;
                const texture: *Buffer2D(RGBA) = @as(*Buffer2D(RGBA), @alignCast(@ptrCast(command.TextureId.?)));
                std.debug.assert(texture == &state.imgui_font_texture);
                const vertex_data: []const imgui_renderer.Vertex = std.mem.bytesAsSlice(imgui_renderer.Vertex, std.mem.sliceAsBytes(vertex_buffer.used_slice()))[command.VtxOffset..];
                const render_context = imgui_renderer.Context {
                    .texture = texture.*,
                    .texture_width = texture.width,
                    .texture_height = texture.height(),
                    .projection_matrix = projection_matrix,
                };
                const render_requirements = imgui_renderer.pipeline_configuration.Requirements() {
                    .viewport_matrix = viewport_matrix,
                    .index_buffer = index_buffer.used_slice()[command.IdxOffset..],
                    .scissor_rect = clip,
                };
                imgui_renderer.Pipeline.render(pixel_buffer, render_context, vertex_data, command.ElemCount / 3, render_requirements);
            }
        }
    }

    fn setup_new_frame(context: *Context) void {
        const io = imgui.c.igGetIO();

        var mouse_current: win32.POINT = undefined;
        _ = win32.GetCursorPos(&mouse_current);

        imgui.c.ImGuiIO_AddMousePosEvent(io,
            @as(f32, @floatFromInt(mouse_current.x)),
            @as(f32, @floatFromInt(mouse_current.y))
        );
        
        var rect: win32.RECT = undefined;
        _ = win32.GetClientRect(context.hWnd, &rect);
        const client_width = rect.right - rect.left;
        const client_height = rect.bottom - rect.top;

        io.*.DisplaySize = imgui.c.ImVec2 { .x = @floatFromInt(client_width), .y = @floatFromInt(client_height) };

        var current_time: win32.LARGE_INTEGER = undefined;
        _ = win32.QueryPerformanceCounter(&current_time);
        io.*.DeltaTime = @as(f32, @floatFromInt(current_time.QuadPart - context.Time)) / @as(f32, @floatFromInt(context.TicksPerSecond));
        context.Time = current_time.QuadPart;
    }

};
/// top = y = window height, bottom = y = 0
fn line(comptime pixel_type: type, buffer: *Buffer2D(pixel_type), a: Vector2i, b: Vector2i, color: pixel_type) void {
    
    if (a.x == b.x and a.y == b.y) {
        // a point
        buffer.set(@intCast(a.x), @intCast(a.y), color);
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
            buffer.set(@intCast(x), @intCast(y), color);
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
            buffer.set(@intCast(x), @intCast(y), color);
        }
        return;
    }

    const delta_x_abs = std.math.absInt(delta.x) catch unreachable;
    const delta_y_abs = std.math.absInt(delta.y) catch unreachable;

    if (delta_x_abs == delta_y_abs) {
        if (a.y < b.y) { // draw a to b so that memory is modified in the "correct order"
            const diff: i32 = if (a.x < b.x) 1 else -1;
            var x = a.x;
            var y = a.y;
            while (x != b.x) {
                buffer.set(@intCast(x), @intCast(y), color);
                x += diff;
                y += 1;
            }
        }
        else { // draw b to a so that memory is modified in the "correct order"
            const diff: i32 = if (a.x < b.x) -1 else 1;
            var x = b.x;
            var y = b.y;
            while (x != a.x) {
                buffer.set(@intCast(x), @intCast(y), color);
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
            buffer.set(@intCast(x), @intCast(y), color);
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
            buffer.set(@intCast(x), @intCast(y), color);
            percentage_of_line_done += increment;
        }

    }
    else unreachable;
}

const State = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    render_target: win32.BITMAPINFO,
    pixel_buffer: Buffer2D(win32.RGBA),
    running: bool,
    mouse: Vector2i,
    keys: [256]bool,
    
    depth_buffer: Buffer2D(f32),
    texture: AnyBuffer2D,
    vertex_buffer: []f32,
    camera: Camera,
    view_matrix: M44,
    viewport_matrix: M44,
    projection_matrix: M44,
    time: f64,
    
    imgui_platform_context: imgui_win32_impl.Context,
    imgui_font_texture: Buffer2D(RGBA),
};

var state = State {
    .x = 10,
    .y = 10,
    .w = 1000,
    // .w = 500,
    .h = 1000,
    // .h = 300,
    .render_target = undefined,
    .pixel_buffer = undefined,
    .running = true,
    .mouse = undefined,
    .keys = [1]bool{false} ** 256,
    
    .depth_buffer = undefined,
    .texture = undefined,
    .vertex_buffer = undefined,
    .camera = undefined,
    .view_matrix = undefined,
    .viewport_matrix = undefined,
    .projection_matrix = undefined,
    .time = undefined,
    
    .imgui_font_texture = undefined,
    .imgui_platform_context = undefined,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const instance_handle = win32.GetModuleHandleW(null);
    const window_class_name = win32.L("doesntmatter");
    const window_class = win32.WNDCLASSW {
        .style = @enumFromInt(0),
        .lpfnWndProc = window_callback,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance_handle,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = window_class_name,
    };
    
    state.render_target.bmiHeader.biSize = @sizeOf(@TypeOf(state.render_target.bmiHeader));
    state.render_target.bmiHeader.biWidth = state.w;
    state.render_target.bmiHeader.biHeight = state.h;
    //  _______________________________
    // |                               |
    // |   `biPlanes` must be one      |
    // |                    -Microsoft |
    // '_______________________________'
    state.render_target.bmiHeader.biPlanes = 1;
    state.render_target.bmiHeader.biBitCount = 32;
    state.render_target.bmiHeader.biCompression = win32.BI_RGB;

    state.pixel_buffer.data = try allocator.alloc(win32.RGBA, @intCast(state.w * state.h));
    state.pixel_buffer.width = @intCast(state.w);
    defer allocator.free(state.pixel_buffer.data);

    _ = win32.RegisterClassW(&window_class);
    defer _ = win32.UnregisterClassW(window_class_name, instance_handle);
    
    const window_handle_maybe = win32.CreateWindowExW(
        @enumFromInt(0),
        window_class_name,
        win32.L("win32 zig window"),
        @enumFromInt(@intFromEnum(win32.WS_POPUP) | @intFromEnum(win32.WS_OVERLAPPED) | @intFromEnum(win32.WS_THICKFRAME) | @intFromEnum(win32.WS_CAPTION) | @intFromEnum(win32.WS_SYSMENU) | @intFromEnum(win32.WS_MINIMIZEBOX) | @intFromEnum(win32.WS_MAXIMIZEBOX)),
        state.x, state.y, state.w, state.h,
        null, null, instance_handle, null
    );
    
    if (window_handle_maybe) |window_handle| {
        _ = win32.ShowWindow(window_handle, .SHOW);
        defer _ = win32.DestroyWindow(window_handle);

        { // Initialize the application state
            // Create the z-buffer
            state.depth_buffer = Buffer2D(f32) { .data = try allocator.alloc(f32, @intCast(state.w * state.h)), .width = @intCast(state.w) };
            
            // Initialize the imgui stuff
            const imgui_context = imgui.c.igCreateContext(null);
            _ = imgui_context;
            imgui_win32_impl.init(&state.imgui_platform_context, window_handle, &state.imgui_font_texture);

            // Load the diffuse texture data
            state.texture = TGA.from_file(allocator, "res/african_head_diffuse.tga")
                catch |err| { std.debug.print("error reading `res/african_head_diffuse.tga` {?}", .{err}); return; };
            
            state.vertex_buffer = OBJ.from_file(allocator, "res/african_head.obj")
                catch |err| { std.debug.print("error reading `res/african_head.obj` {?}", .{err}); return; };

            // Set the camera
            // Since I have decided that the camera will look towards -z (this happens in the lookat matrix generation)
            // meaning that the camera starts at 0, 0, 1, Looking backwards (direction is 0, 0, -1), and up is up
            state.camera.position = Vector3f { .x = 0, .y = 0, .z = 1 };
            state.camera.up = Vector3f { .x = 0, .y = 1, .z = 0 };
            state.camera.direction = Vector3f { .x = 0, .y = 0, .z = -1 };

            state.time = 0;
        }

        defer { // Deinitialize the application state
            allocator.free(state.depth_buffer.data);
            switch(state.texture) { inline else => |buffer| allocator.free(buffer.data) }
            allocator.free(state.vertex_buffer);
        }
        
        var cpu_counter: i64 = blk: {
            var counter: win32.LARGE_INTEGER = undefined;
            _ = win32.QueryPerformanceCounter(&counter);
            break :blk counter.QuadPart;
        };
        const cpu_counter_first: i64 = cpu_counter;
        const cpu_frequency_seconds: i64 = blk: {
            var performance_frequency: win32.LARGE_INTEGER = undefined;
            _ = win32.QueryPerformanceFrequency(&performance_frequency);
            break :blk performance_frequency.QuadPart;
        };

        { // Set the initial mouse state to wherever the mouse is when the app is initialized
            var mouse_current: win32.POINT = undefined;
            _ = win32.GetCursorPos(&mouse_current);
            state.mouse.x = mouse_current.x;
            state.mouse.y = mouse_current.y;
        }

        var open: bool = true;
        while (state.running) {

            imgui_win32_impl.setup_new_frame(&state.imgui_platform_context);
            imgui.c.igNewFrame();

            var fps: i64 = undefined;
            var ms: f64 = undefined;
            { // calculate fps and ms
                var new_counter: win32.LARGE_INTEGER = undefined;
                _ = win32.QueryPerformanceCounter(&new_counter);
                var counter_difference = new_counter.QuadPart - cpu_counter;
                // TODO sometimes it comes out as 0????? not sure why but its not important right now
                if (counter_difference == 0) counter_difference = 1;
                ms = 1000.0 * @as(f64, @floatFromInt(counter_difference)) / @as(f64, @floatFromInt(cpu_frequency_seconds));
                fps = @divFloor(cpu_frequency_seconds, counter_difference);
                cpu_counter = new_counter.QuadPart;
            }
            const counted_since_start = cpu_counter - cpu_counter_first;

            { // windows message loop
                var message: win32.MSG = undefined;
                while (win32.PeekMessageW(&message, null,  0, 0, .REMOVE) != win32.falsei32) {
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessageW(&message);

                    // TODO Any windows messages that the application needs to read should happen here
                    switch (message.message) {
                        win32.WM_QUIT => state.running = false,
                        else => {},
                    }
                }
            }

            var rect: win32.RECT = undefined;
            _ = win32.GetClientRect(window_handle, &rect);
            const client_width = rect.right - rect.left;
            const client_height = rect.bottom - rect.top;

            const mouse_previous = state.mouse;
            var mouse_current: win32.POINT = undefined;
            _ = win32.GetCursorPos(&mouse_current);
            const factor: f32 = 0.02;
            const mouse_dx: f32 = @as(f32, @floatFromInt(mouse_current.x - mouse_previous.x)) * factor;
            const mouse_dy: f32 = @as(f32, @floatFromInt(mouse_current.y - mouse_previous.y)) * factor;
            state.mouse.x = mouse_current.x;
            state.mouse.y = mouse_current.y;

            var app_close_requested = false;
            { // tick / update
                
                const white = win32.rgb(255, 255, 255);
                const red = win32.rgb(255, 0, 0);
                const green = win32.rgb(0, 255, 0);
                const blue = win32.rgb(0, 0, 255);
                const turquoise = win32.rgb(0, 255, 255);
                
                // Clear the screen and the zbuffer
                for (state.pixel_buffer.data) |*pixel| { pixel.* = win32.rgb(100, 149, 237); }
                for (state.depth_buffer.data) |*value| { value.* = -999999; }

                if (state.keys['T']) state.time += ms;

                // move camera direction based on mouse movement
                const mouse_sensitivity = 0.60;
                const up = Vector3f {.x = 0, .y = 1, .z = 0 };
                const real_right = state.camera.direction.cross_product(up).normalized();
                const real_up = state.camera.direction.cross_product(real_right).normalized().scale(-1);
                if (mouse_dx != 0 or mouse_dy != 0) {
                    state.camera.direction = state.camera.direction.add(real_right.scale(mouse_dx*mouse_sensitivity));
                    if (state.camera.direction.y < 0.95 and state.camera.direction.y > -0.95) {
                        state.camera.direction = state.camera.direction.add(real_up.scale(-mouse_dy*mouse_sensitivity));
                    }
                    state.camera.direction.normalize();
                }
                
                // move the camera position based on WASD and QE
                if (state.keys['W']) state.camera.position = state.camera.position.add(state.camera.direction.scale(0.02));
                if (state.keys['S']) state.camera.position = state.camera.position.add(state.camera.direction.scale(-0.02));
                if (state.keys['A']) state.camera.position = state.camera.position.add(real_right.scale(-0.02));
                if (state.keys['D']) state.camera.position = state.camera.position.add(real_right.scale(0.02));
                if (state.keys['Q']) state.camera.position.y += 0.02;
                if (state.keys['E']) state.camera.position.y -= 0.02;

                // calculate camera's look-at
                state.camera.looking_at = state.camera.position.add(state.camera.direction);                
                state.view_matrix = M44.lookat_right_handed(state.camera.position, state.camera.looking_at, state.camera.up);
                state.projection_matrix = M44.perspective_projection(60*(@as(f32,std.math.pi)/180), 16/9, 0.01, 10);
                state.viewport_matrix = M44.viewport_i32(0, 0, state.w, state.h, 255);

                // if (state.keys['V']) state.viewport_matrix = M44.identity();
                if (state.keys['P']) bilinear = !bilinear;

                _ = counted_since_start;
                
                if (false) {
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 100, .y = 1 }, red);
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 100, .y = 50 }, green);
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 50, .y = 100 }, blue);
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 1, .y = 100 }, white);
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 100, .y = 100 }, turquoise);
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 100, .y = 1 }, red); 
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 100, .y = 50 }, green);
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 50, .y = 100 }, blue);
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 1, .y = 100 }, white);
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 100, .y = 100 }, turquoise);
                    line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = 70, .y = 10 }, Vector2i { .x = 70, .y = 10 }, white);
                }

                // TODO I think windows is rendering upside down, (or me, lol) so invert it
                // TODO the light intensity varies as the camera moves which shouldnt happen since its static, fix that
                // TODO Im pretty sure the pixel data is being read in a weird way on the TGA reader, the color is a bit off
                if (true) {
                    const horizontally_spinning_position = Vector3f { .x = std.math.cos(@as(f32, @floatCast(state.time)) / 2000), .y = 0, .z = std.math.sin(@as(f32, @floatCast(state.time)) / 2000) };
                    const render_context = gouraud_renderer.Context {
                        .light_position_camera_space = state.view_matrix.apply_to_vec3(horizontally_spinning_position).discard_w(),
                        .projection_matrix = state.projection_matrix,
                        .texture = state.texture.rgb,
                        .texture_height = state.texture.rgb.height(),
                        .texture_width = state.texture.rgb.width,
                        .view_model_matrix = state.view_matrix.multiply(
                            M44.translation(Vector3f { .x = 0, .y = 0, .z = -2 }).multiply(M44.scale(0.8))
                        ),
                    };
                    var i: usize = 0;
                    var vertex_buffer = std.ArrayList(gouraud_renderer.Vertex).initCapacity(allocator, @divExact(state.vertex_buffer.len, 8)) catch unreachable;
                    while (i < state.vertex_buffer.len) : (i = i + 8) {
                        const pos: Vector3f = .{ .x=state.vertex_buffer[i+0], .y=state.vertex_buffer[i+1], .z=state.vertex_buffer[i+2] };
                        const uv: Vector2f = .{ .x=state.vertex_buffer[i+3], .y=state.vertex_buffer[i+4] };
                        const normal: Vector3f = .{ .x=state.vertex_buffer[i+5], .y=state.vertex_buffer[i+6], .z=state.vertex_buffer[i+7] };
                        vertex_buffer.appendAssumeCapacity(.{ .pos = pos, .uv = uv, .normal = normal });
                    }
                    const render_requirements: gouraud_renderer.pipeline_configuration.Requirements() = .{
                        .depth_buffer = state.depth_buffer,
                        .viewport_matrix = state.viewport_matrix,
                    };
                    gouraud_renderer.Pipeline.render(state.pixel_buffer, render_context, vertex_buffer.items, @divExact(vertex_buffer.items.len, 3), render_requirements);
                }

                line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = 200, .y = 200 }, Vector2i { .x = 200 + @as(i32, @intFromFloat(50 * state.camera.direction.x)), .y = 200 + @as(i32, @intFromFloat(50 * state.camera.direction.y)) }, red);
                line(win32.RGBA, &state.pixel_buffer, Vector2i { .x = 150, .y = 150 }, Vector2i { .x = 150 + @as(i32, @intFromFloat(50 * state.camera.direction.z)), .y = 150 }, blue);
                // TODO there is part of the pixel buffer being rendered below the status bar from windows
                if (true) render_text(allocator, state.pixel_buffer, Vector2i { .x = 10, .y = @intCast(state.pixel_buffer.height() - 300) }, "ms {d: <9.2}", .{ms});

                if (true) {
                    const texture = @import("font_embedded.zig");
                    // const c_red = RGBA { .r = 255, .g = 0, .b = 0, .a = 255 };
                    // const c_green = RGBA { .r = 0, .g = 255, .b = 0, .a = 255 };
                    // const c_blue = RGBA { .r = 0, .g = 0, .b = 255, .a = 255 };
                    // const c_white = RGBA { .r = 255, .g = 255, .b = 255, .a = 255 };
                    // const c_transparent = RGBA { .r = 255, .g = 255, .b = 255, .a = 0 };
                    // const texture = struct {
                    //     const data = [_]RGBA {
                    //         c_transparent, c_transparent, c_transparent, c_transparent,
                    //         c_transparent, c_red, c_green, c_transparent,
                    //         c_transparent, c_blue, c_white, c_transparent,
                    //         c_transparent, c_transparent, c_transparent, c_transparent,
                    //     };
                    //     const width: usize = 4;
                    //     const height: usize = 4;
                    // };
                    const texture_data = texture.data;
                    const w: f32 = @floatFromInt(texture.width);
                    const h: f32 = @floatFromInt(texture.height);
                    const quad_context = quad_renderer.Context {
                        .texture = Buffer2D(RGBA).init(@constCast(@ptrCast(&texture_data)), texture.width),
                        .texture_width = texture.width,
                        .texture_height = texture.height,
                        .projection_matrix =
                            state.projection_matrix.multiply(
                                state.view_matrix.multiply(
                                    M44.translation(Vector3f { .x = -0.5, .y = -0.5, .z = 0 }).multiply(M44.scale(1/@as(f32, @floatFromInt(texture.width))))
                                )
                            ),
                    };
                    const vertex_buffer = [_]quad_renderer.Vertex{
                        .{ .pos = .{.x=0,.y=0}, .uv = .{.x=0,.y=0} },
                        .{ .pos = .{.x=w,.y=0}, .uv = .{.x=1,.y=0} },
                        .{ .pos = .{.x=w,.y=h}, .uv = .{.x=1,.y=1} },
                        .{ .pos = .{.x=0,.y=h}, .uv = .{.x=0,.y=1} },
                    };
                    const index_buffer = [_]u16{0,1,2,0,2,3};
                    const requirements = quad_renderer.pipeline_configuration.Requirements() {
                        .depth_buffer = state.depth_buffer,
                        .viewport_matrix = state.viewport_matrix,
                        .index_buffer = &index_buffer,
                    };
                    quad_renderer.Pipeline.render(state.pixel_buffer, quad_context, &vertex_buffer, index_buffer.len/3, requirements);
                }

                // imgui.c.igShowDemoWindow(&open);
                _ = open;
                imgui.c.igText("Hello, world");  
                imgui.c.igEndFrame();
                imgui.c.igRender();
                imgui_win32_impl.render_draw_data(state.pixel_buffer);
            }

            state.running = state.running and !app_close_requested;
            if (state.running == false) continue;

            { // render
                const device_context_handle = win32.GetDC(window_handle).?;
                _ = win32.StretchDIBits(
                    device_context_handle,
                    0, 0, client_width, client_height,
                    0, 0, client_width, client_height,
                    state.pixel_buffer.data.ptr,
                    &state.render_target,
                    win32.DIB_USAGE.RGB_COLORS,
                    win32.SRCCOPY
                );
                _ = win32.ReleaseDC(window_handle, device_context_handle);
            }
        }
    }

}

fn window_callback(window_handle: win32.HWND , message_type: u32, w_param: win32.WPARAM, l_param: win32.LPARAM) callconv(win32.call_convention) win32.LRESULT {
    
    switch (message_type) {

        win32.WM_DESTROY,
        win32.WM_CLOSE => {
            win32.PostQuitMessage(0);
            return 0;
        },

        win32.WM_SYSKEYDOWN,
        win32.WM_KEYDOWN => {
            if (w_param == @intFromEnum(win32.VK_ESCAPE)) win32.PostQuitMessage(0)
            else if (w_param < 256 and w_param >= 0) {
                const key: u8 = @intCast(w_param);
                state.keys[key] = true;
                std.debug.print("down {c}\n", .{key});
            }
        },

        win32.WM_KEYUP => {
            if (w_param < 256 and w_param >= 0) {
                const key: u8 = @intCast(w_param);
                state.keys[key] = false;
                std.debug.print("up   {c}\n", .{key});
            }
        },

        win32.WM_SIZE => {
            var rect: win32.RECT = undefined;
            _ = win32.GetClientRect(window_handle, &rect);
            _ = win32.InvalidateRect(window_handle, &rect, @intFromEnum(win32.True));
        },

        win32.WM_PAINT => {
            var paint_struct: win32.PAINTSTRUCT = undefined;
            const handle_device_context = win32.BeginPaint(window_handle, &paint_struct);

            _ = win32.StretchDIBits(
                handle_device_context,
                0, 0, state.w, state.h,
                0, 0, state.w, state.h,
                state.pixel_buffer.data.ptr,
                &state.render_target,
                win32.DIB_RGB_COLORS,
                win32.SRCCOPY
            );

            _ = win32.EndPaint(window_handle, &paint_struct);
            return 0;
        },

        else => {},
    }

    return win32.DefWindowProcW(window_handle, message_type, w_param, l_param);
}

var bilinear: bool = false;

fn render_line(pixel_buffer: *Buffer2D(win32.RGBA), a: Vector2i, b: Vector2i, color: win32.RGBA) void {
    line(win32.RGBA, pixel_buffer, a, b, color);
}

fn render_text(allocator: std.mem.Allocator, pixel_buffer: Buffer2D(win32.RGBA), pos: Vector2i, comptime format: []const u8, args: anytype) void {
    // bitmap font embedded in the executable
    const font = @import("font_embedded.zig");

    const texture = Buffer2D(RGBA).init(@constCast(@ptrCast(&font.data)), font.width);
    const context = text_renderer.Context {
        .texture = texture,
        .texture_width = texture.width,
        .texture_height = texture.height(),
        .projection_matrix = M44.orthographic_projection(0, @floatFromInt(state.w), @floatFromInt(state.h), 0, 0.1, 1000)
    };
    var text_buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&text_buffer);
    std.fmt.format(fbs.writer(), format, args) catch @panic("failed to format text while rendering it");
    const text = fbs.getWritten();

    var vertex_buffer = allocator.alloc(text_renderer.Vertex, text.len*4) catch unreachable;
    defer allocator.free(vertex_buffer);

    const char_width: i32 = 4;
    const char_height: i32 = 7;
    const size = 8;
    for (text, 0..) |c, i| {
        const x: i32 = pos.x + @as(i32, @intCast(i)) * char_width * size;
        const y: i32 = pos.y;
        
        const u_1: i32 = (c%16) * 8;
        const v_1: i32 = (c/16) * 8;
        const u_2: i32 = u_1 + char_width;
        const v_2: i32 = v_1 + char_height;

        const offset: usize = i*4;

        vertex_buffer[offset + 0] = .{
            .pos = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) },
            .uv = .{ .x = @floatFromInt(u_1), .y = @floatFromInt(v_1) },
        };
        vertex_buffer[offset + 1] = .{
            .pos = .{ .x = @floatFromInt(x + char_width * size), .y = @floatFromInt(y) },
            .uv = .{ .x = @floatFromInt(u_2), .y = @floatFromInt(v_1) },
        };
        vertex_buffer[offset + 2] = .{
            .pos = .{ .x = @floatFromInt(x + char_width * size), .y = @floatFromInt(y - char_height * size) },
            .uv = .{ .x = @floatFromInt(u_2), .y = @floatFromInt(v_2) },
        };
        vertex_buffer[offset + 3] = .{
            .pos = .{ .x = @floatFromInt(x), .y = @floatFromInt(y - char_height * size) },
            .uv = .{ .x = @floatFromInt(u_1), .y = @floatFromInt(v_2) },
        };
    }
    
    text_renderer.Pipeline.render(pixel_buffer, context, vertex_buffer[0..text.len*4], text.len * 2, .{ .viewport_matrix = state.viewport_matrix, });
}

// TODO finish this...
// triangle clipping on at least one plane
// 
// if 1 or 2 (but not 3) points of a given triangle are outside the plane, then calculate the 1 or 2 clipped triangles that need to be rendered
// continue implementing this ...

const Plane = struct {
    
    a: f32,
    b: f32,
    c: f32,
    d: f32,

    pub fn from(point: Vector3f, normal: Vector3f) Plane {
        const d = - ((normal.x*point.x)+(normal.y*point.y)+(normal.z*point.z));
        return Plane { .a = normal.a, .b = normal.b, .c = normal.c, .d = d };
    }

    pub fn signed_distance_to_point(plane: Plane, point: Vector3f) f32 {
        return plane.a * point.x +
            plane.b * point.y +
            plane.c * point.z +
            plane.d;
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
};

const GraphicsPipelineConfiguration = struct {
    blend_with_background: bool = false,
    use_index_buffer_auto: bool = false,
    use_index_buffer: bool = false,
    do_triangle_clipping: bool = false,
    do_depth_testing: bool = false,
    do_perspective_correct_interpolation: bool = false,
    do_scissoring: bool = false,
    pub fn Requirements(comptime self: GraphicsPipelineConfiguration) type {
        var fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField {
            std.builtin.Type.StructField {
                .default_value = null,
                .is_comptime = false,
                .name = "viewport_matrix",
                .type = M44,
                .alignment = @alignOf(M44)
            },
        };
        if (self.use_index_buffer) {
            if (self.use_index_buffer_auto) @compileError("Only one option can be active: `use_index_buffer_auto`, or `use_index_buffer`");
            fields = fields ++ [_]std.builtin.Type.StructField {
                std.builtin.Type.StructField {
                    .default_value = null,
                    .is_comptime = false,
                    .name = "index_buffer",
                    .type = []const u16,
                    .alignment = @alignOf([]const u16)
                }
            };
        }
        if (self.do_depth_testing) fields = fields ++ [_]std.builtin.Type.StructField {
                std.builtin.Type.StructField {
                .default_value = null,
                .is_comptime = false,
                .name = "depth_buffer",
                .type = Buffer2D(f32),
                .alignment = @alignOf([]f32)
            }
        };
        if (self.do_scissoring) fields = fields ++ [_]std.builtin.Type.StructField {
                std.builtin.Type.StructField {
                .default_value = null,
                .is_comptime = false,
                .name = "scissor_rect",
                .type = Vector4f,
                .alignment = @alignOf(Vector4f)
            }
        };
        // TODO what exactly should I do with declarations?
        // according to the compiler, when I put any declaration whatsoever I ger `error: reified structs must have no decls`
        // not sure what that means
        var declarations: []const std.builtin.Type.Declaration = &[_]std.builtin.Type.Declaration {
            // .{ .name = "" },
        };
        const requirements = std.builtin.Type {
            .Struct = .{
                .is_tuple = false,
                .fields = fields,
                .layout = .Auto,
                .decls = declarations,
            }
        };
        return @Type(requirements);
    }
};

fn GraphicsPipeline(
    comptime final_color_type: type,
    comptime context_type: type,
    comptime invariant_type: type,
    comptime vertex_type: type,
    comptime pipeline_configuration: GraphicsPipelineConfiguration,
    comptime vertex_shader: fn(context: context_type, vertex_buffer: vertex_type, out_invariant: *invariant_type) Vector4f,
    comptime fragment_shader: fn(context: context_type, invariants: invariant_type) final_color_type,
) type {
    return struct {
        const Self = @This();
        fn render(pixel_buffer: Buffer2D(final_color_type), context: context_type, vertex_buffer: []const vertex_type, face_count: usize, requirements: pipeline_configuration.Requirements()) void {
            
            var face_index: usize = 0;
            label_outer: while (face_index < face_count) : (face_index += 1) {
                
                var invariants: [3]invariant_type = undefined;
                var tri: [3]Vector3f = undefined;
                var w_used_for_perspective_correction: [3]f32 = undefined;
                var depth: [3]f32 = undefined;

                // pass all 3 vertices of this face through the vertex shader
                var clipped: usize = 0;
                inline for(0..3) |i| {
                    const vertex_index = index: {
                        if (pipeline_configuration.use_index_buffer) break :index requirements.index_buffer[face_index * 3 + i]
                        else if (pipeline_configuration.use_index_buffer_auto) break :index
                            // Generates the sequence 0 1 2 0 2 3 4 5 6 4 6 7 8 9 10 8 10 11 ...
                            if (face_index%2==0) face_index * 2 + i else if (i==0) (face_index-1) * 2 else ((face_index-1) * 2) + i + 1
                        else break :index face_index * 3 + i;
                    };
                    const vertex_data: vertex_type = vertex_buffer[vertex_index];
                    // As far as I know, in your standard opengl vertex shader, the returned position is usually in
                    // clip space, which is a homogeneous coordinate system. The `w` will be used for perspective correction.
                    const clip_space_position = vertex_shader(context, vertex_data, &invariants[i]);
                    const ndc = clip_space_position.perspective_division();
                    if (ndc.x >= 1 or ndc.x <= -1 or ndc.y >= 1 or ndc.y <= -1 or ndc.z >= 1 or ndc.z <= -1) {
                        if (pipeline_configuration.do_triangle_clipping) {
                            clipped += 1;
                            @panic("triangle clipping not yet implemented");
                            // TODO how can I get a point and the normal of the frustrum? Maybe I can take those directly from the projection matrix?
                            // Once I have the plane I can check for intersection points and form new triangles (that form the clipped triangle)
                            // Plane.from(point, normal)
                        }
                        else continue :label_outer;
                    }
                    if (pipeline_configuration.do_depth_testing) depth[i] = ndc.z;
                    if (pipeline_configuration.do_perspective_correct_interpolation) w_used_for_perspective_correction[i] = clip_space_position.w;
                    const screen_space_position = requirements.viewport_matrix.apply_to_vec3(ndc).perspective_division();
                    tri[i] = screen_space_position;
                }

                // top = y = window height, bottom = y = 0
                const a = &tri[0];
                const b = &tri[1];
                const c = &tri[2];

                // calculate the bounding of the triangle's projection on the screen
                var left: usize = @intFromFloat(@min(a.x, @min(b.x, c.x)));
                var bottom: usize = @intFromFloat(@min(a.y, @min(b.y, c.y)));
                var right: usize = @intFromFloat(@max(a.x, @max(b.x, c.x)));
                var top: usize = @intFromFloat(@max(a.y, @max(b.y, c.y)));
                if (pipeline_configuration.do_scissoring) {
                    left = @min(left, @as(usize, @intFromFloat(requirements.scissor_rect.x)));
                    bottom = @min(bottom, @as(usize, @intFromFloat(requirements.scissor_rect.y)));
                    right = @max(right, @as(usize, @intFromFloat(requirements.scissor_rect.z)));
                    top = @max(top, @as(usize, @intFromFloat(requirements.scissor_rect.w)));
                }

                // TODO PERF rather than going pixel by pixel on the bounding box of the triangle, use linear interpolation to figure out the "left" and "right" of each row of pixels
                // that way should be faster, although we still need to calculate the barycentric coords for zbuffer and texture sampling, but it might still be better since we skip many pixels
                // test it just in case

                // top to bottom
                var y: usize = top;
                while (y >= bottom) : (y -= 1) {
                    
                    // left to right
                    var x: usize = left;
                    while (x <= right) : (x += 1) {
                        
                        // barycentric coordinates of the current pixel
                        const pixel = Vector3f { .x = @floatFromInt(x), .y = @floatFromInt(y), .z = 0 };

                        const ab = b.substract(a.*);
                        const ac = c.substract(a.*);
                        const ap = pixel.substract(a.*);
                        const bp = pixel.substract(b.*);
                        const ca = a.substract(c.*);

                        // TODO PERF we dont actually need many of the calculations of cross_product here, just the z
                        // the magnitude of the cross product can be interpreted as the area of the parallelogram.
                        const paralelogram_area_abc: f32 = ab.cross_product(ac).z;
                        const paralelogram_area_abp: f32 = ab.cross_product(bp).z;
                        const paralelogram_area_cap: f32 = ca.cross_product(ap).z;

                        const u: f32 = paralelogram_area_cap / paralelogram_area_abc;
                        const v: f32 = paralelogram_area_abp / paralelogram_area_abc;
                        const w: f32 = (1 - u - v);

                        // The inverse of the barycentric would be `P=wA+uB+vC`

                        // determine if a pixel is in fact part of the triangle
                        if (u < 0 or u >= 1) continue;
                        if (v < 0 or v >= 1) continue;
                        if (w < 0 or w >= 1) continue;

                        if (pipeline_configuration.do_depth_testing) {
                            const z = depth[0] * w + depth[1] * u + depth[2] * v;
                            if (requirements.depth_buffer.get(x, y) >= z) continue;
                            requirements.depth_buffer.set(x, y, z);
                        }

                        var interpolated_invariants: invariant_type = undefined;

                        // Get every invariant given out by the vertex shader and interpolate the values which will be passed to the fragment shader 
                        if (pipeline_configuration.do_perspective_correct_interpolation) {
                            const perspective_correction = 1/w_used_for_perspective_correction[0] * w + 1/w_used_for_perspective_correction[1] * u + 1/w_used_for_perspective_correction[2] * v;
                            inline for (@typeInfo(invariant_type).Struct.fields) |invariant| {
                                @field(interpolated_invariants, invariant.name) =
                                    switch (invariant.type) {
                                        Vector2f => Vector2f {
                                            .x = (@field(invariants[0], invariant.name).x/w_used_for_perspective_correction[0] * w + @field(invariants[1], invariant.name).x/w_used_for_perspective_correction[1] * u + @field(invariants[2], invariant.name).x/w_used_for_perspective_correction[2] * v) / perspective_correction,
                                            .y = (@field(invariants[0], invariant.name).y/w_used_for_perspective_correction[0] * w + @field(invariants[1], invariant.name).y/w_used_for_perspective_correction[1] * u + @field(invariants[2], invariant.name).y/w_used_for_perspective_correction[2] * v) / perspective_correction,
                                        },
                                        RGBA => RGBA {
                                            .r = @intFromFloat((@as(f32, @floatFromInt(@field(invariants[0], invariant.name).r))/w_used_for_perspective_correction[0] * w + @as(f32, @floatFromInt(@field(invariants[1], invariant.name).color.r))/w_used_for_perspective_correction[1] * u + @as(f32, @floatFromInt(@field(invariants[2], invariant.name).color.r))/w_used_for_perspective_correction[2] * v) / perspective_correction),
                                            .g = @intFromFloat((@as(f32, @floatFromInt(@field(invariants[0], invariant.name).g))/w_used_for_perspective_correction[0] * w + @as(f32, @floatFromInt(@field(invariants[1], invariant.name).color.g))/w_used_for_perspective_correction[1] * u + @as(f32, @floatFromInt(@field(invariants[2], invariant.name).color.g))/w_used_for_perspective_correction[2] * v) / perspective_correction),
                                            .b = @intFromFloat((@as(f32, @floatFromInt(@field(invariants[0], invariant.name).b))/w_used_for_perspective_correction[0] * w + @as(f32, @floatFromInt(@field(invariants[1], invariant.name).color.b))/w_used_for_perspective_correction[1] * u + @as(f32, @floatFromInt(@field(invariants[2], invariant.name).color.b))/w_used_for_perspective_correction[2] * v) / perspective_correction),
                                            .a = @intFromFloat((@as(f32, @floatFromInt(@field(invariants[0], invariant.name).a))/w_used_for_perspective_correction[0] * w + @as(f32, @floatFromInt(@field(invariants[1], invariant.name).color.a))/w_used_for_perspective_correction[1] * u + @as(f32, @floatFromInt(@field(invariants[2], invariant.name).color.a))/w_used_for_perspective_correction[2] * v) / perspective_correction),
                                        },
                                        f32 => (@field(invariants[0], invariant.name)/w_used_for_perspective_correction[0] * w + @field(invariants[1], invariant.name)/w_used_for_perspective_correction[1] * u + @field(invariants[2], invariant.name)/w_used_for_perspective_correction[2] * v) / perspective_correction,
                                        else => @panic("type " ++ @tagName(invariant.type) ++ " has no implementation of interpolation")
                                    };
                            }
                        }
                        else {
                            inline for (@typeInfo(invariant_type).Struct.fields) |invariant| {
                                @field(interpolated_invariants, invariant.name) =
                                    switch (invariant.type) {
                                        Vector2f => Vector2f {
                                            .x = @field(invariants[0], invariant.name).x * w + @field(invariants[1], invariant.name).x * u + @field(invariants[2], invariant.name).x * v,
                                            .y = @field(invariants[0], invariant.name).y * w + @field(invariants[1], invariant.name).y * u + @field(invariants[2], invariant.name).y * v,
                                        },
                                        RGBA => RGBA {
                                            .r = @intFromFloat(@as(f32, @floatFromInt(@field(invariants[0], invariant.name).r)) * w + @as(f32, @floatFromInt(@field(invariants[1], invariant.name).r)) * u + @as(f32, @floatFromInt(@field(invariants[2], invariant.name).r)) * v),
                                            .g = @intFromFloat(@as(f32, @floatFromInt(@field(invariants[0], invariant.name).g)) * w + @as(f32, @floatFromInt(@field(invariants[1], invariant.name).g)) * u + @as(f32, @floatFromInt(@field(invariants[2], invariant.name).g)) * v),
                                            .b = @intFromFloat(@as(f32, @floatFromInt(@field(invariants[0], invariant.name).b)) * w + @as(f32, @floatFromInt(@field(invariants[1], invariant.name).b)) * u + @as(f32, @floatFromInt(@field(invariants[2], invariant.name).b)) * v),
                                            .a = @intFromFloat(@as(f32, @floatFromInt(@field(invariants[0], invariant.name).a)) * w + @as(f32, @floatFromInt(@field(invariants[1], invariant.name).a)) * u + @as(f32, @floatFromInt(@field(invariants[2], invariant.name).a)) * v),
                                        },
                                        f32 => @field(invariants[0], invariant.name) * w + @field(invariants[1], invariant.name) * u + @field(invariants[2], invariant.name) * v,
                                        else => @panic("type " ++ @tagName(invariant.type) ++ " has no implementation of interpolation")
                                    };
                            }
                        }

                        const final_color = fragment_shader(context, interpolated_invariants);
                        
                        if (pipeline_configuration.blend_with_background) {
                            const old_color = pixel_buffer.get(x, y);
                            pixel_buffer.set(x, y, final_color.blend(old_color));
                        }
                        else pixel_buffer.set(x, y, final_color);

                    }
                }
            }
        }
    };
}

const imgui_renderer = struct {
    
    const Context = struct {
        texture: Buffer2D(RGBA),
        texture_width: usize,
        texture_height: usize,
        projection_matrix: M44,
    };
    
    const Invariant = struct {
        texture_uv: Vector2f,
        color: RGBA,
    };
    
    const Vertex = struct {
        pos: Vector2f,
        uv: Vector2f,
        color: RGBA,
    };

    const pipeline_configuration = GraphicsPipelineConfiguration {
        .blend_with_background = true,
        .use_index_buffer = true,
        .do_triangle_clipping = false,
        .do_depth_testing = false,
        .do_perspective_correct_interpolation = false,
        .do_scissoring = true,
    };

    const Pipeline = GraphicsPipeline(
        win32.RGBA,
        Context,
        Invariant,
        Vertex,
        pipeline_configuration,
        struct {
            fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                out_invariant.color = vertex.color;
                out_invariant.texture_uv = vertex.uv;
                return context.projection_matrix.apply_to_vec3(Vector3f { .x = vertex.pos.x, .y = vertex.pos.y, .z = 1 });
            }
        }.vertex_shader,
        struct {
            fn fragment_shader(context: Context, invariants: Invariant) win32.RGBA {
                const sample =
                    if (bilinear) texture_bilinear_sample(RGBA, true, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv)
                    else texture_point_sample(RGBA, true, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv);
                const rgba = invariants.color.multiply(sample);
                return win32.rgba(rgba.r, rgba.g, rgba.b, rgba.a);
            }
        }.fragment_shader,
    );
};

const quad_renderer = struct {
    
    const Context = struct {
        texture: Buffer2D(RGBA),
        texture_width: usize,
        texture_height: usize,
        projection_matrix: M44
    };

    const Invariant = struct {
        texture_uv: Vector2f,
    };

    const Vertex = struct {
        pos: Vector2f,
        uv: Vector2f,
    };

    const pipeline_configuration = GraphicsPipelineConfiguration {
        .blend_with_background = true,
        .use_index_buffer = true,
        .do_triangle_clipping = false,
        .do_depth_testing = true,
        .do_perspective_correct_interpolation = true,
        .do_scissoring = false,
    };

    const Pipeline = GraphicsPipeline(
        win32.RGBA,
        Context,
        Invariant,
        Vertex,
        pipeline_configuration,
        struct {
            fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                out_invariant.texture_uv = vertex.uv;
                return context.projection_matrix.apply_to_vec3(Vector3f { .x = vertex.pos.x, .y = vertex.pos.y, .z = 0 });
            }
        }.vertex_shader,
        struct {
            fn fragment_shader(context: Context, invariants: Invariant) win32.RGBA {
                const rgba =
                    if (bilinear) texture_bilinear_sample(RGBA, true, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv)
                    else texture_point_sample(RGBA, true, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv);
                return win32.rgba(rgba.r, rgba.g, rgba.b, rgba.a);
            }
        }.fragment_shader,
    );

};

const text_renderer = struct {
    
    const Context = struct {
        texture: Buffer2D(RGBA),
        texture_width: usize,
        texture_height: usize,
        projection_matrix: M44,
    };

    const Invariant = struct {
        texture_uv: Vector2f,
    };

    const Vertex = struct {
        pos: Vector2f,
        uv: Vector2f,
    };

    const Pipeline = GraphicsPipeline(
        win32.RGBA,
        Context,
        Invariant,
        Vertex,
        GraphicsPipelineConfiguration {
            .blend_with_background = true,
            .use_index_buffer_auto = true,
            .use_index_buffer = false,
            .do_triangle_clipping = false,
            .do_depth_testing = false,
            .do_perspective_correct_interpolation = false,
            .do_scissoring = false,
        },
        struct {
            fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                out_invariant.texture_uv = vertex.uv;
                return context.projection_matrix.apply_to_vec3(Vector3f { .x = vertex.pos.x, .y = vertex.pos.y, .z = 1 });
            }
        }.vertex_shader,
        struct {
            fn fragment_shader(context: Context, invariants: Invariant) win32.RGBA {
                const rgba =
                    if (bilinear) texture_bilinear_sample(RGBA, false, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv)
                    else texture_point_sample(RGBA, false, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv);
                return win32.rgba(rgba.r, rgba.g, rgba.b, rgba.a);
            }
        }.fragment_shader,
    );

};

const gouraud_renderer = struct {
    
    const Context = struct {
        texture: Buffer2D(RGB),
        texture_width: usize,
        texture_height: usize,
        view_model_matrix: M44,
        projection_matrix: M44,
        light_position_camera_space: Vector3f,
    };
    
    const Invariant = struct {
        texture_uv: Vector2f,
        light_intensity: f32,
    };
    
    const Vertex = struct {
        pos: Vector3f,
        uv: Vector2f,
        normal: Vector3f,
    };
    
    const pipeline_configuration = GraphicsPipelineConfiguration {
        .blend_with_background = false,
        .use_index_buffer = false,
        .do_triangle_clipping = false,
        .do_depth_testing = true,
        .do_perspective_correct_interpolation = true,
        .do_scissoring = false,
    };

    const Pipeline = GraphicsPipeline(
        win32.RGBA, Context, Invariant, Vertex, pipeline_configuration,
        struct {
            fn vertex_shader(context: Context, vertex: Vertex, out_invariant: *Invariant) Vector4f {
                const position_camera_space = context.view_model_matrix.apply_to_vec3(vertex.pos);
                const light_direction = context.light_position_camera_space.substract(position_camera_space.discard_w()).normalized();
                out_invariant.light_intensity = std.math.clamp(vertex.normal.normalized().dot(light_direction), 0, 1);
                out_invariant.texture_uv = vertex.uv;
                return context.projection_matrix.apply_to_vec4(position_camera_space);
            }
        }.vertex_shader,
        struct {
            fn fragment_shader(context: Context, invariants: Invariant) win32.RGBA {
                const sample =
                    if (bilinear) texture_bilinear_sample(RGB, true, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv)
                    else texture_point_sample(RGB, true, context.texture.data, context.texture_width, context.texture_height, invariants.texture_uv);
                const rgba = sample.scale(invariants.light_intensity);
                return win32.rgba(rgba.r, rgba.g, rgba.b, 255);
            }
        }.fragment_shader,
    );

};
