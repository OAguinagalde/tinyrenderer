const std = @import("std");

const win32 = struct {
    usingnamespace @import("win32").everything;
    const falsei32: i32 = 0;
    const call_convention = std.os.windows.WINAPI;
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
        return Vector2f { .x = @intCast(f32, self.x), .y = @intCast(f32, self.y) };
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
        up.normalize();
        
        // here z is technically -z
        const z: Vector3f = camera_location.substract(point_looked_at).normalized();
        const x: Vector3f = up.cross_product(z).normalized();
        const y: Vector3f = z.cross_product(x).normalized();

        // AKA change of basis matrix
        const rotation_matrix = M44.identity();
        rotation_matrix.data[0] = x.x;
        rotation_matrix.data[4] = x.y;
        rotation_matrix.data[8] = x.z;

        rotation_matrix.data[1] = y.x;
        rotation_matrix.data[5] = y.y;
        rotation_matrix.data[9] = y.z;

        rotation_matrix.data[2] = z.x;
        rotation_matrix.data[6] = z.y;
        rotation_matrix.data[10] = z.z;

        // translate the world to the location of the camera and then rotate it
        // The order of this multiplication is relevant!
        // 
        //     rotation_matrix * translation_matrix(-camera_location)
        // 
        return rotation_matrix.multiply(M44.translation(camera_location.scale(-1)));
    }
    
    /// This should probably go something like...
    /// 
    ///     float c = -1 / (camera.looking_at - camera.position).norm();
    ///     projection(c);
    /// 
    pub fn projection(coefficient: f32) M44 {
        const projection_matrix = M44.identity();
        projection_matrix.data[11] = coefficient;
        return projection_matrix;
    }
    
    /// Builds a "viewport" (as its called in opengl) matrix, a matrix that
    /// will map a point in the 3-dimensional cube [-1, 1]*[-1, 1]*[-1, 1]
    /// onto the screen cube [x, x+w]*[y, y+h]*[0, d],
    /// where d is the depth/resolution of the z-buffer
    pub fn viewport(x: i32, y: i32, w: i32, h: i32, depth: i32) M44 {
        var matrix = M44.identity();

        const xf = @intToFloat(f32, x);
        const yf = @intToFloat(f32, y);
        const wf = @intToFloat(f32, w);
        const hf = @intToFloat(f32, h);
        const depthf = @intToFloat(f32, depth);
        
        // 1 0 0 translation_x
        // 0 1 0 translation_y
        // 0 0 1 translation_z
        // 0 0 0 1

        const translation_x: f32 = xf + (wf / 2);
        const translation_y: f32 = yf + (hf / 2);
        const translation_z: f32 = depthf / 2;

        matrix.data[12] = translation_x;
        matrix.data[13] = translation_y;
        matrix.data[14] = translation_z;

        // scale_x 0       0       0
        // 0       scale_y 0       0
        // 0       0       scale_z 0
        // 0       0       0       1
        
        const scale_x: f32 = wf / 2;
        const scale_y: f32 = hf / 2;
        const scale_z: f32 = depthf / 2;

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

const Pixel = u32;

fn rgb(r: u8, g: u8, b: u8) Pixel {
    return rgba(r,g,b,255);
}

fn rgba(r: u8, g: u8, b: u8, a: u8) Pixel {
    // In windows pixels are stored as BGRA
    const Win32PixelStructure = extern struct {
        b: u8,
        g: u8,
        r: u8,
        /// 255 for solid and 0 for transparent
        a: u8,
    };
    return @bitCast(u32 , Win32PixelStructure {
        .a = a, .r = r, .g = g, .b = b
    });
}

/// top = y = window height, bottom = y = 0
fn line(buffer: []Pixel, buffer_width: i32, a: Vector2i, b: Vector2i, color: Pixel) void {
    
    if (a.x == b.x and a.y == b.y) {
        // a point
        buffer[@intCast(usize, buffer_width * a.y + a.x)] = color;
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
            buffer[@intCast(usize, buffer_width * y + x)] = color;
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
            buffer[@intCast(usize, buffer_width * y + x)] = color;
        }
        return;
    }

    const delta_x_abs = std.math.absInt(delta.x) catch unreachable;
    const delta_y_abs = std.math.absInt(delta.y) catch unreachable;

    if (delta_x_abs == delta_y_abs) {
        // draw diagonal line
        var bottom_left = &a;
        var top_right = &b;
        if (a.x < b.x and a.y < b.y) {} else {
            bottom_left = &b;
            top_right = &a;
        }

        var x = bottom_left.x;
        var y = bottom_left.y;
        while (x != top_right.x) {
            buffer[@intCast(usize, buffer_width * y + x)] = color;
            x += 1;
            y += 1;
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

        const increment = 1 / @intToFloat(f32, delta_x_abs);
        var percentage_of_line_done: f32 = 0;
        
        var x = left.x;
        while (x <= right.x) : (x += 1) {
            // linear interpolation to figure out `y`
            const y = left.y + @floatToInt(i32, @intToFloat(f32, right.y - left.y) * percentage_of_line_done);
            buffer[@intCast(usize, buffer_width*y + x)] = color;
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

        const increment = 1 / @intToFloat(f32, delta_y_abs);
        var percentage_of_line_done: f32 = 0;

        var y = top.y;
        while (y <= bottom.y) : (y += 1) {
            const x = top.x + @floatToInt(i32, @intToFloat(f32, bottom.x - top.x) * percentage_of_line_done);
            buffer[@intCast(usize, buffer_width * y + x)] = color;
            percentage_of_line_done += increment;
        }

    }
    else unreachable;
}

/// top = y = window height, bottom = y = 0
fn triangle(buffer: []Pixel, buffer_width: i32, tri: [3]Vector3f, z_buffer: []f32, comptime fragment_shader: fn (u:f32, v:f32, w:f32, x: i32, y: i32, z: f32) ?Pixel) void {
    
    const a = &tri[0];
    const b = &tri[1];
    const c = &tri[2];

    const buffer_height = @divExact(@intCast(i32, buffer.len), buffer_width);

    // calculate the bounding of the triangle's projection on the screen
    const left: i32 = @floatToInt(i32, std.math.min(a.x, std.math.min(b.x, c.x)));
    const top: i32 = @floatToInt(i32, std.math.min(a.y, std.math.min(b.y, c.y)));
    const right: i32 = @floatToInt(i32, std.math.max(a.x, std.math.max(b.x, c.x)));
    const bottom: i32 = @floatToInt(i32, std.math.max(a.y, std.math.max(b.y, c.y)));

    if (false) std.debug.print("left   {?}\n", .{ left });
    if (false) std.debug.print("top    {?}\n", .{ top });
    if (false) std.debug.print("bottom {?}\n", .{ bottom });
    if (false) std.debug.print("right  {?}\n", .{ right });

    // if the triangle is not fully inside the buffer, discard it straight away
    if (left < 0 or top < 0 or right >= buffer_width or bottom >= buffer_height) return;

    if (false) std.debug.print("visible\n", .{ });

    // TODO PERF rather than going pixel by pixel on the bounding box of the triangle, use linear interpolation to figure out the "left" and "right" of each row of pixels
    // that way should be faster, although we still need to calculate the barycentric coords for zbuffer and texture sampling, but it might still be better since we skip many pixels
    // test it just in case

    // bottom to top
    var y: i32 = bottom;
    while (y >= top) : (y -= 1) {
        
        // left to right
        var x: i32 = left;
        while (x <= right) : (x += 1) {
            
            // pixel by pixel check if its inside the triangle
            
            // barycentric coordinates of the current pixel, used to...
            // ... determine if a pixel is in fact part of the triangle,
            // ... calculate the pixel's z value
            // ... for texture sampling
            // TODO make const
            var u: f32 = undefined;
            var v: f32 = undefined;
            var w: f32 = undefined;
            {
                const pixel = Vector3f { .x = @intToFloat(f32, x), .y = @intToFloat(f32, y), .z = 0 };

                const ab = b.subtract(a.*);
                const ac = c.subtract(a.*);
                const ap = pixel.subtract(a.*);
                const bp = pixel.subtract(b.*);
                const ca = a.subtract(c.*);

                // TODO PERF we dont actually need many of the calculations of cross_product here, just the z
                // the magnitude of the cross product can be interpreted as the area of the parallelogram.
                const paralelogram_area_abc: f32 = ab.cross_product(ac).z;
                const paralelogram_area_abp: f32 = ab.cross_product(bp).z;
                const paralelogram_area_cap: f32 = ca.cross_product(ap).z;

                u = paralelogram_area_cap / paralelogram_area_abc;
                v = paralelogram_area_abp / paralelogram_area_abc;
                w = (1 - u - v);
            }

            if (false) std.debug.print("u {} v {} w {}\n", .{ u, v, w });

            // determine if a pixel is in fact part of the triangle
            if (u < 0 or u >= 1) continue;
            if (v < 0 or v >= 1) continue;
            if (w < 0 or w >= 1) continue;

            if (false) std.debug.print("inside\n", .{ });

            // interpolate the z of this pixel to find out its depth
            const z = a.z * w + b.z * u + c.z * v;

            const pixel_index = @intCast(usize, x + y * buffer_width);
            if (z_buffer[pixel_index] < z) {
                if (fragment_shader(u, v, w, x, y, z)) |color| {
                    z_buffer[pixel_index] = z;
                    buffer[pixel_index] = color;
                }
            }

        }
    }

}

const Camera = struct {
    position: Vector3f,
    direction: Vector3f,
    looking_at: Vector3f,
    up: Vector3f,
};

const BufferRgb = struct {
    buffer: []Pixel,
    width: i32
};

const BufferVertex = struct {
    buffer: []f32,
    faces: i32
};

const State = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    render_target: win32.BITMAPINFO,
    pixel_buffer: []Pixel,
    running: bool,
    mouse: Vector2i,
    
    z_buffer: []f32,
    texture: BufferRgb,
    model: BufferVertex,
    camera: Camera,
    view_matrix: M44,
    viewport_matrix: M44,
    projection_matrix: M44,
    time: f64,
};

var state = State {
    .x = 10,
    .y = 10,
    .w = 500,
    .h = 300,
    .render_target = undefined,
    .pixel_buffer = undefined,
    .running = true,
    .mouse = undefined,
    
    .z_buffer = undefined,
    .texture = undefined,
    .model = undefined,
    .camera = undefined,
    .view_matrix = undefined,
    .viewport_matrix = undefined,
    .projection_matrix = undefined,
    .time = undefined,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const instance_handle = win32.GetModuleHandleW(null);
    const window_class_name = win32.L("doesntmatter");
    const window_class = win32.WNDCLASSW {
        .style = @intToEnum(win32.WNDCLASS_STYLES, 0),
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

    state.pixel_buffer = try allocator.alloc(Pixel, @intCast(usize, state.w * state.h));
    defer allocator.free(state.pixel_buffer);

    _ = win32.RegisterClassW(&window_class);
    defer _ = win32.UnregisterClassW(window_class_name, instance_handle);
    
    const window_handle_maybe = win32.CreateWindowExW(
        @intToEnum(win32.WINDOW_EX_STYLE, 0),
        window_class_name,
        win32.L("win32 zig window"),
        @intToEnum(win32.WINDOW_STYLE, @enumToInt(win32.WS_POPUP) | @enumToInt(win32.WS_OVERLAPPED) | @enumToInt(win32.WS_THICKFRAME) | @enumToInt(win32.WS_CAPTION) | @enumToInt(win32.WS_SYSMENU) | @enumToInt(win32.WS_MINIMIZEBOX) | @enumToInt(win32.WS_MAXIMIZEBOX)),
        state.x, state.y, state.w, state.h,
        null, null, instance_handle, null
    );
    
    if (window_handle_maybe) |window_handle| {
        _ = win32.ShowWindow(window_handle, .SHOW);
        defer _ = win32.DestroyWindow(window_handle);

        { // Initialize the application state
            // Create the z-buffer
            state.z_buffer = try allocator.alloc(f32, @intCast(usize, state.w * state.h));

            // Load the diffuse texture data
            state.texture = TGA.from_file(allocator, "res/african_head_diffuse.tga").to_rgb_buffer();
            state.model = OBJ.from_file(allocator, "res/african_head.obj").to_vertex_buffer();

            // Set the camera
            state.camera.position = Vector3f { .x = 1, .y = 1, .z = 3 };
            state.camera.up = Vector3f { .x = 0, .y = 1, .z = 0 };
            state.camera.direction = Vector3f { .x = 0, .y = 0, .z = 1 };

            state.time = 0;
        }

        defer { // Deinitialize the application state
            allocator.free(state.z_buffer);
            allocator.free(state.texture.buffer);
            allocator.free(state.model.buffer);
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

        state.mouse = Vector2i { .x = 0, .y = 0 };

        while (state.running) {

            var fps: i64 = undefined;
            var ms: f64 = undefined;
            { // calculate fps and ms
                var new_counter: win32.LARGE_INTEGER = undefined;
                _ = win32.QueryPerformanceCounter(&new_counter);
                var counter_difference = new_counter.QuadPart - cpu_counter;
                // TODO sometimes it comes out as 0????? not sure why but its not important right now
                if (counter_difference == 0) counter_difference = 1;
                ms = 1000.0 * @intToFloat(f64, counter_difference) / @intToFloat(f64, cpu_frequency_seconds);
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
            win32.GetCursorPos(&mouse_current);
            const factor: f32 = 0.02f;
            const mouse_dx = @intToFloat(f32, mouse_current.x - mouse_previous.x) * factor;
            const mouse_dy = @intToFloat(f32, mouse_current.y - mouse_previous.y) * factor;
            state.mouse.x = mouse_current.x;
            state.mouse.y = mouse_current.y;

            var app_close_requested = false;
            { // tick / update
                
                const white = rgb(255, 255, 255);
                const red = rgb(255, 0, 0);
                const green = rgb(0, 255, 0);
                const blue = rgb(0, 0, 255);
                const turquoise = rgb(0, 255, 255);
                
                // Clear the screen and the zbuffer
                for (state.pixel_buffer) |*pixel| { pixel.* = rgb(0, 0, 0); }
                for (state.z_buffer) |*value| { value.* = -9999; }

                if (state.keys.T) state.time += ms;

                // move camera direction based on mouse movement
                const up = Vector3f {.x = 0, .y = 1, .z = 0 };
                const real_right = state.camera.direction.cross_product(up).normalized();
                const real_up = state.camera.direction.cross_product(real_right).normalized().scale(-1);
                if (mouse_dx != 0 or mouse_dy != 0) {
                    state.camera.direction = state.camera.direction.add(real_right.scale(mouse_dx));
                    if (state.camera.direction.y < 0.95 and state.camera.direction.y > -0.95) {
                        state.camera.direction = state.camera.direction.add(real_up.scale(mouse_dy));
                    }
                    state.camera.direction.normalize();
                }
                
                // move the camera position based on WASD and QE
                if (state.keys.W) state.camera.position = state.camera.position.add(cam.direction.scale(0.02));
                if (state.keys.S) state.camera.position = state.camera.position.add(cam.direction.scale(0.02)).scale(-1);
                if (state.keys.A) state.camera.position = state.camera.position.add(real_right.scale(0.02)).scale(-1);
                if (state.keys.D) state.camera.position = state.camera.position.add(real_right.scale(0.02));
                if (state.keys.Q) state.camera.position.y += factor1;
                if (state.keys.E) state.camera.position.y -= factor1;

                // calculate camera's look-at
                state.camera.looking_at = state.camera.position.add(state.camera.direction);
                
                state.view_matrix = M44.lookat_right_handed(state.camera.position, state.camera.looking_at, state.camera.up);
                state.viewport_matrix = M44.viewport(0, 0, state.w, state.h, 255);
                state.projection_matrix = M44.projection(-1 / state.camera.position.substract(state.camera.looking_at).magnitude());

                if (state.keys.P) state.projection_matrix = M44.identity();
                if (state.keys.V) state.viewport_matrix = M44.identity();

                const horizontally_spinning_position = Vector3f { .x = std.math.cos(time / 2000), .y = 0, .z = std.math.sin(time / 2000) };
                
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 100, .y = 1 }, red); 
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 100, .y = 50 }, green);
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 50, .y = 100 }, blue);
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 1, .y = 100 }, white);
                line(state.pixel_buffer, state.w, Vector2i { .x = 0, .y = 0 }, Vector2i { .x = 100, .y = 100 }, turquoise);

                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 100, .y = 1 }, red); 
                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 100, .y = 50 }, green);
                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 50, .y = 100 }, blue);
                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 1, .y = 100 }, white);
                line(state.pixel_buffer, state.w, Vector2i { .x = state.w-1, .y = state.h-1 }, Vector2i { .x = 100, .y = 100 }, turquoise);

                line(state.pixel_buffer, state.w, Vector2i { .x = 70, .y = 10 }, Vector2i { .x = 70, .y = 10 }, white);

                const fragment_shader_a = struct {
                    fn shader(u:f32, v:f32, w:f32, x: i32, y: i32, z: f32) ?Pixel {
                        _ = u; _ = v; _ = w; _ = x; _ = y;
                        return rgb(@floatToInt(u8, z*255), @floatToInt(u8, z*255), @floatToInt(u8, z*255));
                    }
                }.shader;

                const gouraud_shader = struct {
                    
                    /// A struct containing all the resources that the Gouraud shader requires in order to work
                    const Resources = struct {
                        view_model_matrix: M44,
                        vertex_buffer: BufferVertex,
                        projection_matrix: M44,
                        viewport_matrix: M44,
                        texture: BufferRgb,
                        light_source: Vector3f,
                    };
                    
                    fn vertex_shader(vertex: Vector3f, resources: Resources) ?Vector3f {
                        
                    }

                    fn fragment(u:f32, v:f32, w:f32, x: i32, y: i32, z: f32) ?Pixel {
                        _ = u; _ = v; _ = w; _ = x; _ = y;
                        return rgb(@floatToInt(u8, z*255), @floatToInt(u8, z*255), @floatToInt(u8, z*255));
                    }

                };

                // TODO I think windows is rendering upside down, (or me, lol) so invert it
                
                const resources = gouraud_shader.Resources {
                    .view_model_matrix = state.view_matrix.multiply(M44.translation(Vector3f { .x = 0, .y = 0, .z = -1 }).multiply(M44.scale(1))),
                    .light_source = state.view_matrix.apply_to_point(horizontally_spinning_position),
                    .vertex_buffer = state.model,
                    .projection_matrix = state.projection_matrix,
                    .viewport_matrix = state.viewport_matrix,
                    .texture = state.texture,
                };

                var face_index = 0;
                while (face_index < state.model.faces) : (face_index += 1) {
                    
                    const triangle: [3]Vector3f = undefined;
                    
                    // pass all 3 vertices of this face through the vertex shader
                    inline for(0..3) |i| {

                        const vertex = Vector3f {
                            .x = state.model.buffer[face_index*3+i*3+0],
                            .y = state.model.buffer[face_index*3+i*3+1],
                            .z = state.model.buffer[face_index*3+i*3+2],
                        };

                        if (gouraud_shader.vertex_shader(vertex, resources)) |resulting_vertex| {
                            triangle[i] = resulting_vertex;
                        }
                        else continue;
                    }

                    // TODO write the vertex shader for gouraud
                    // TODO write the fragment shader for gouraud
                    // TODO implement TGA and OBJ file readers
                    
                    triangle(
                        state.pixel_buffer,
                        state.w,
                        triangle,
                        state.z_buffer,
                        fragment_shader_a
                    );
                }

                triangle(
                    state.pixel_buffer,
                    state.w,
                    [3]Vector3f {
                        Vector3f { .x = 33, .y = 20, .z = 0 },
                        Vector3f { .x = 133, .y = 27, .z = 0.5 },
                        Vector3f { .x = 70, .y = 212, .z = 1 },
                    },
                    state.z_buffer,
                    fragment_shader_a
                );

                triangle(
                    state.pixel_buffer,
                    state.w,
                    [3]Vector3f {
                        Vector3f { .x = 33, .y = 50, .z = 1 },
                        Vector3f { .x = 200, .y = 79, .z = 0 },
                        Vector3f { .x = 130, .y = 180, .z = 0.5 },
                    },
                    state.z_buffer,
                    fragment_shader_a
                );
            }

            state.running = state.running and !app_close_requested;
            if (state.running == false) continue;

            { // render
                const device_context_handle = win32.GetDC(window_handle).?;
                _ = win32.StretchDIBits(
                    device_context_handle,
                    0, 0, client_width, client_height,
                    0, 0, client_width, client_height,
                    state.pixel_buffer.ptr,
                    &state.render_target,
                    win32.DIB_RGB_COLORS,
                    win32.SRCCOPY
                );
                _ = win32.ReleaseDC(window_handle, device_context_handle);
            }
        }
    }

}

fn window_callback(window_handle: win32.HWND , message_type: u32, w_param: win32.WPARAM, l_param: win32.LPARAM) callconv(win32.call_convention) win32.LRESULT {
    
    switch (message_type) {

        win32.WM_DESTROY, win32.WM_CLOSE => {
            win32.PostQuitMessage(0);
            return 0;
        },

        win32.WM_SYSKEYDOWN, win32.WM_KEYDOWN => {
            if (w_param == @enumToInt(win32.VK_ESCAPE)) win32.PostQuitMessage(0);
        },

        win32.WM_SIZE => {
            var rect: win32.RECT = undefined;
            _ = win32.GetClientRect(window_handle, &rect);
            _ = win32.InvalidateRect(window_handle, &rect, @enumToInt(win32.True));
        },

        win32.WM_PAINT =>
        {
            var paint_struct: win32.PAINTSTRUCT = undefined;
            const handle_device_context = win32.BeginPaint(window_handle, &paint_struct);

            _ = win32.StretchDIBits(
                handle_device_context,
                0, 0, state.w, state.h,
                0, 0, state.w, state.h,
                state.pixel_buffer.ptr,
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
