/// This is an OBJ file reader

const std = @import("std");
const Vector3f = @import("math.zig").Vector3f;
const Vector2f = @import("math.zig").Vector2f;

pub fn from_bytes(allocator: std.mem.Allocator, bytes: [] const u8) ![]f32 {
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

    // line by line read the obj file and parse its content
    // var current_line_buffer: [1024]u8 = undefined;
    var tokens = std.mem.tokenize(u8, bytes, "\n");
    while (tokens.next()) |the_line| {
    // while (try buf_reader.reader().readUntilDelimiterOrEof(&current_line_buffer, '\n')) |the_line| {
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

/// - This OBJ reader is very barebones and will crash if the OBJ doesn't meet a number of things I expect it to
/// lines must have shape of `v f32 f32 f32`, `vt f32 f32`, `vn f32 f32 f32` or `f u32/u32/u32 u32/u32/u32 u32/u32/u32`
/// even tho technically OBJ allows for some variance there.
/// - The layout of the buffer returned is as follows:
/// [ location_x, location_y, location_z, texture_u, texture_v, normal_x, normal_y, normal_z ] x 3 x number of triangles
/// where `const number_of_triangles = @divExacty(buffer.len, 8*3)`
/// - Returns a []f32 buffer that must be freed by the caller.
pub fn from_file(allocator: std.mem.Allocator, file_path: [] const u8) ![]f32 {
    
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