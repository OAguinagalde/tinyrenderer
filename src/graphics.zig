const std = @import("std");

const math = @import("math.zig");
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vector4f = math.Vector4f;
const M44 = math.M44;
const M33 = math.M33;
const Plane = math.Plane;
const Frustum = math.Frustum;
const Buffer2D = @import("buffer.zig").Buffer2D;

pub const GraphicsPipelineConfiguration = struct {
    blend_with_background: bool = false,
    use_index_buffer_auto: bool = false,
    use_index_buffer: bool = false,
    do_triangle_clipping: bool = false,
    do_depth_testing: bool = false,
    do_perspective_correct_interpolation: bool = false,
    do_scissoring: bool = false,
    use_triangle_2: bool = false,
    /// for debugging purposes
    trace: bool = false,
    
    /// returns a comptime tpye (an struct, basically) which needs to be filled, and passed as a value to the render pipeline when calling `render`
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
        const declarations: []const std.builtin.Type.Declaration = &[_]std.builtin.Type.Declaration {
            // .{ .name = "" },
        };
        const requirements = std.builtin.Type {
            .@"struct" = .{
                .is_tuple = false,
                .fields = fields,
                .layout = .Auto,
                .decls = declarations,
            }
        };
        return @Type(requirements);
    }
};

pub fn GraphicsPipeline(
    // The output pixel type
    comptime final_color_type: type,
    comptime context_type: type,
    comptime invariant_type: type,
    comptime vertex_type: type,
    comptime pipeline_configuration: GraphicsPipelineConfiguration,
    comptime vertex_shader: fn(context: context_type, vertex_buffer: vertex_type, out_invariant: *invariant_type) Vector4f,
    comptime fragment_shader: fn(context: context_type, invariants: invariant_type) final_color_type,
) type {
    return struct {

        pub fn render(pixel_buffer: Buffer2D(final_color_type), context: context_type, vertex_buffer: []const vertex_type, face_count: usize, requirements: pipeline_configuration.Requirements()) void {
            
            var face_index: usize = 0;
            label_outer: while (face_index < face_count) : (face_index += 1) {
                
                // 0, 1 and 2 will be the original triangle vertices.
                // if there is clipping however
                var invariants: [3]invariant_type = undefined;
                var clip_space_positions: [3]Vector4f = undefined;
                var ndcs: [3]Vector3f = undefined;
                var screen_space_position: [3]Vector3f = undefined;
                var w_used_for_perspective_correction: [3]f32 = undefined;
                var depth: [3]f32 = undefined;
                var clipped_count: usize = 0;

                // pass all 3 vertices of this face through the vertex shader
                inline for(0..3) |i| {
                    
                    const vertex_index = index: {
                        if (pipeline_configuration.use_index_buffer) break :index requirements.index_buffer[face_index * 3 + i]
                        else if (pipeline_configuration.use_index_buffer_auto) break :index
                            // Generates the sequence 0 1 2 0 2 3 4 5 6 4 6 7 8 9 10 8 10 11 ...
                            if (face_index%2==0) face_index * 2 + i else if (i==0) (face_index-1) * 2 else ((face_index-1) * 2) + i + 1
                        else break :index face_index * 3 + i;
                    };

                    const vertex_data: vertex_type = vertex_buffer[vertex_index];

                    // As far as I understand, in your standard opengl vertex shader, the returned position is usually in
                    // clip space, which is a homogeneous coordinate system. The `w` will be used for perspective correction.
                    clip_space_positions[i] = vertex_shader(context, vertex_data, &invariants[i]);
                    
                    // NOTE This is quivalent to checking whether a point is inside the NDC cube after perspective division
                    // 
                    //     if (ndc.x > 1 or ndc.x < -1 or ndc.y > 1 or ndc.y < -1 or ndc.z > 1 or ndc.z < 0) {
                    // 
                    // if (clip_space_positions.x > clip_space_positions.w or clip_space_positions.x < -clip_space_positions.w or
                    //     clip_space_positions.y > clip_space_positions.w or clip_space_positions.y < -clip_space_positions.w or
                    //     clip_space_positions.z > clip_space_positions.w or clip_space_positions.z < 0) {
                    // 
                    // }

                    const ndc = clip_space_positions[i].perspective_division();
                    ndcs[i] = ndc;
                    if (ndc.x > 1 or ndc.x < -1 or ndc.y > 1 or ndc.y < -1 or ndc.z > 1 or ndc.z < 0) {
                        if (pipeline_configuration.do_triangle_clipping) {
                            clipped_count += 1;
                            if (clipped_count == 3) continue :label_outer;
                        }
                        else continue :label_outer;
                    }
                    if (pipeline_configuration.do_depth_testing) depth[i] = ndc.z;
                    if (pipeline_configuration.do_perspective_correct_interpolation) w_used_for_perspective_correction[i] = clip_space_positions[i].w;
                    screen_space_position[i] = requirements.viewport_matrix.apply_to_vec3(ndc).perspective_division();
                }

                if (pipeline_configuration.do_triangle_clipping) {
                    if (clipped_count == 0) {
                        rasterizer(pixel_buffer, context, requirements, screen_space_position[0..3].*, depth[0..3].*, w_used_for_perspective_correction[0..3].*, invariants[0..3].*);
                        
                        // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(tri[0].x), .y = @intFromFloat(tri[0].y) }, Vector2i { .x = @intFromFloat(tri[1].x), .y = @intFromFloat(tri[1].y) }, .{.r = 255, .g = 0, .b = 0, .a = 255 });
                        // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(tri[1].x), .y = @intFromFloat(tri[1].y) }, Vector2i { .x = @intFromFloat(tri[2].x), .y = @intFromFloat(tri[2].y) }, .{.r = 255, .g = 0, .b = 0, .a = 255 });
                        // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(tri[2].x), .y = @intFromFloat(tri[2].y) }, Vector2i { .x = @intFromFloat(tri[0].x), .y = @intFromFloat(tri[0].y) }, .{.r = 255, .g = 0, .b = 0, .a = 255 });
                    }
                    else {
                        
                        trace("clipping", .{});
                        trace("clip space", .{});
                        trace_triangle_4(clip_space_positions[0..3].*);
                        trace("ndc", .{});
                        trace_triangle(ndcs[0..3].*);
                        trace_mat4(context.projection_matrix);

                        const left_bottom_near = comptime Vector3f.from(-1,-1,0);
                        const right_top_far = comptime Vector3f.from(1,1,1);
                        const frustum = comptime Frustum {
                            .left = Plane.from(left_bottom_near, Vector3f.from(1,0,0)),
                            .right = Plane.from(right_top_far, Vector3f.from(-1,0,0)),
                            .bottom = Plane.from(left_bottom_near, Vector3f.from(0,1,0)),
                            .top = Plane.from(right_top_far, Vector3f.from(0,-1,0)),
                            .near = Plane.from(left_bottom_near, Vector3f.from(0,0,1)),
                            .far = Plane.from(right_top_far, Vector3f.from(0,0,-1) ),
                        };

                        const VertexList = struct {
                            const VertexLinkedList = std.DoublyLinkedList(Vector3f);
                            data: std.ArrayList(VertexLinkedList.Node),
                            list: VertexLinkedList,
                            fn init(allocator: std.mem.Allocator) @This() {
                                return .{
                                    .data = std.ArrayList(VertexLinkedList.Node).initCapacity(allocator, 15) catch unreachable,
                                    .list = VertexLinkedList {}
                                };
                            }
                            fn add(self: *@This(), vertex: Vector3f) void {
                                const ptr = self.data.addOneAssumeCapacity();
                                ptr.* = .{ .data = vertex };
                                self.list.append(ptr);
                            }
                            fn clear(self: *@This()) void {
                                self.list = VertexLinkedList {};
                                self.data.clearRetainingCapacity();
                            }
                            fn free(self: *@This()) void {
                                self.data.clearAndFree();
                            }
                            fn first(self: @This()) ?*VertexLinkedList.Node {
                                return self.list.first;
                            }
                            fn last(self: @This()) ?*VertexLinkedList.Node {
                                return self.list.last;
                            }
                            fn pop_first(self: *@This()) Vector3f {
                                return self.list.popFirst().?.data;
                            }
                            fn next(self: *@This()) ?Vector3f {
                                return if (self.list.popFirst()) |n| n.data else null;
                            }
                            fn move_to_other(self: *@This(), other: *@This()) void {
                                while (self.list.popFirst()) |item| {
                                    other.add(item.data);
                                }
                                self.clear();
                            }
                        };

                        var buffer: [1024*4]u8 = undefined;
                        var fba = std.heap.FixedBufferAllocator.init(&buffer);
                        var vertex_list = VertexList.init(fba.allocator());
                        vertex_list.add(ndcs[0]);
                        vertex_list.add(ndcs[1]);
                        vertex_list.add(ndcs[2]);
                        var temp_vertex_list = VertexList.init(fba.allocator());

                        // for each plane `p`
                        inline for (@typeInfo(Frustum).@"struct".fields) |field| {
                            const p: Plane = @field(frustum, field.name);

                            // for each pair of vertices v1, v2
                            var v1 = vertex_list.last().?;
                            var v2 = vertex_list.first().?;
                            
                            // this is basically a `do {} while {}`
                            while (true) {
                                const v1_inside: bool = (p.classify_point(v1.data) != .negative);
                                const v2_inside: bool = (p.classify_point(v2.data) != .negative);
                                if (v2_inside != v1_inside) {
                                    temp_vertex_list.add(p.intersection(v1.data, v2.data));
                                }
                                if (v2_inside) {
                                    temp_vertex_list.add(v2.data);
                                }

                                if (v2 == vertex_list.last().?) break // break condition
                                else { // continue
                                    v1 = v2;
                                    v2 = v2.next.?;
                                }
                            }

                            vertex_list.clear();
                            temp_vertex_list.move_to_other(&vertex_list);
                        }

                        if (pipeline_configuration.trace) {
                            var count: usize = 0;
                            var n = vertex_list.first();
                            while (n) |node| {
                                count += 1 ;
                                n = node.next;
                            }
                            trace("clipped to {} vertices ({} triangles)", .{count, count-2});
                        }

                        const to_interpolate = struct {
                            depth: f32,
                            w_used_for_perspective_correction: f32,
                        };
                        const orig_triangle_data = [3]to_interpolate {
                            .{
                                .depth = depth[0],
                                .w_used_for_perspective_correction = w_used_for_perspective_correction[0],
                            },
                            .{
                                .depth = depth[1],
                                .w_used_for_perspective_correction = w_used_for_perspective_correction[1],
                            },
                            .{
                                .depth = depth[2],
                                .w_used_for_perspective_correction = w_used_for_perspective_correction[2],
                            },
                        };

                        const vertex_1: Vector3f = vertex_list.pop_first();
                        const screen_space_1 = requirements.viewport_matrix.apply_to_vec3(vertex_1).perspective_division();
                        
                        var vertex_2: Vector3f = vertex_list.pop_first();
                        var vertex_3: Vector3f = vertex_list.pop_first();

                        while (true) { // This is basically a `do {} while {}`
                            
                            trace_triangle([3]Vector3f{vertex_1, vertex_2, vertex_3});
                            
                            const screen_space_2 = requirements.viewport_matrix.apply_to_vec3(vertex_2).perspective_division();
                            const screen_space_3 = requirements.viewport_matrix.apply_to_vec3(vertex_3).perspective_division();

                            var a = screen_space_1;
                            a.z = 0;
                            var b = screen_space_2;
                            b.z = 0;
                            var c = screen_space_3;
                            c.z = 0;
                            const bar_a = barycentric(screen_space_position[0..3].*, a);
                            const bar_b = barycentric(screen_space_position[0..3].*, b);
                            const bar_c = barycentric(screen_space_position[0..3].*, c);

                            const interpolated_a: to_interpolate = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(to_interpolate, orig_triangle_data, w_used_for_perspective_correction[0..3].*, bar_a.x, bar_a.y, bar_a.z)
                                else interpolate(to_interpolate, orig_triangle_data, bar_a.x, bar_a.y, bar_a.z);
                            const interpolated_b: to_interpolate = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(to_interpolate, orig_triangle_data, w_used_for_perspective_correction[0..3].*, bar_b.x, bar_b.y, bar_b.z)
                                else interpolate(to_interpolate, orig_triangle_data, bar_b.x, bar_b.y, bar_b.z);
                            const interpolated_c: to_interpolate = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(to_interpolate, orig_triangle_data, w_used_for_perspective_correction[0..3].*, bar_c.x, bar_c.y, bar_c.z)
                                else interpolate(to_interpolate, orig_triangle_data, bar_c.x, bar_c.y, bar_c.z);
                            
                            const invariants_a = if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants[0..3].*, w_used_for_perspective_correction[0..3].*, bar_a.x, bar_a.y, bar_a.z)
                                else interpolate(invariant_type, invariants[0..3].*, bar_a.x, bar_a.y, bar_a.z);
                            const invariants_b = if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants[0..3].*, w_used_for_perspective_correction[0..3].*, bar_b.x, bar_b.y, bar_b.z)
                                else interpolate(invariant_type, invariants[0..3].*, bar_b.x, bar_b.y, bar_b.z);
                            const invariants_c = if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants[0..3].*, w_used_for_perspective_correction[0..3].*, bar_c.x, bar_c.y, bar_c.z)
                                else interpolate(invariant_type, invariants[0..3].*, bar_c.x, bar_c.y, bar_c.z);

                            // TODO I got two bugs!
                            // 1. Sometimes I get negative uvs not sure why, it only happens when I do perspective correction tho! (Actually I might be wrong about that and I might be getting it without the correction as well)
                            // 2. sometimes the NDC coordinates suddenly go from, say, 23, to -134. Usually when I am close to the clipped triangle and rotate the camera until I'm getting more paralel
                            // meaning that the resulting clipped triangle looks completely out of place. I'm not sure how to go about that

                            rasterizer(pixel_buffer, context, requirements, .{ screen_space_1, screen_space_2, screen_space_3 }, .{ interpolated_a.depth, interpolated_b.depth, interpolated_c.depth }, .{ interpolated_a.w_used_for_perspective_correction, interpolated_b.w_used_for_perspective_correction, interpolated_c.w_used_for_perspective_correction }, .{ invariants_a, invariants_b, invariants_c });

                            // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(screen_space_1.x), .y = @intFromFloat(screen_space_1.y) }, Vector2i { .x = @intFromFloat(screen_space_2.x), .y = @intFromFloat(screen_space_2.y) }, .{.r = 0, .g = 255, .b = 0, .a = 255 });
                            // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(screen_space_2.x), .y = @intFromFloat(screen_space_2.y) }, Vector2i { .x = @intFromFloat(screen_space_3.x), .y = @intFromFloat(screen_space_3.y) }, .{.r = 0, .g = 255, .b = 0, .a = 255 });
                            // line(win32.RGBA, pixel_buffer, Vector2i { .x = @intFromFloat(screen_space_3.x), .y = @intFromFloat(screen_space_3.y) }, Vector2i { .x = @intFromFloat(screen_space_1.x), .y = @intFromFloat(screen_space_1.y) }, .{.r = 0, .g = 255, .b = 0, .a = 255 });

                            // raster the next triangle? or break if we have already drawn them all
                            if (vertex_list.next()) |next_vertex| {
                                vertex_2 = vertex_3;
                                vertex_3 = next_vertex;
                            }
                            else break;
                        }
                    }
                }
                else rasterizer(pixel_buffer, context, requirements, screen_space_position[0..3].*, depth[0..3].*, w_used_for_perspective_correction[0..3].*, invariants[0..3].*);
            }
        }
    
        // NOTE currently rasterize_2 has some issues with filling conventions, gotta fix those. It performs much better however.
        // eventually if multithreading is added, I expect rasterize_1 to be much more multithreading friendly tho...
        const rasterizer = if (pipeline_configuration.use_triangle_2) rasterizers.rasterize_2 else  rasterizers.rasterize_1;
        const rasterizers = struct {
            fn rasterize_2(pixel_buffer: Buffer2D(final_color_type), context: context_type, requirements: pipeline_configuration.Requirements(), tri: [3]Vector3f, depth: [3]f32, w_used_for_perspective_correction: [3]f32, invariants: [3]invariant_type) void {
                
                const a = &tri[0];
                const b = &tri[1];
                const c = &tri[2];

                var top: *const Vector3f = &tri[0];
                var mid: *const Vector3f = &tri[1];
                var bot: *const Vector3f = &tri[2];

                // order the vertices based on their y axis
                if (bot.y > mid.y) {
                    const aux: *const Vector3f = mid;
                    mid = bot;
                    bot = aux;
                }
                if (bot.y > top.y) {
                    const aux: *const Vector3f = top;
                    top = bot;
                    bot = aux;
                }
                if (mid.y > top.y) {
                    const aux: *const Vector3f = top;
                    top = mid;
                    mid = aux;
                }
                std.debug.assert(top.y >= mid.y and mid.y >= bot.y);

                // calculate dy between them
                const dyTopMid: f32 = top.y - mid.y;
                const dyMidBot: f32 = mid.y - bot.y;
                const dyTopBot: f32 = top.y - bot.y;

                const dxTopMid: f32 = top.x - mid.x;
                const dxTopBot: f32 = top.x - bot.x;
                const dxMidBot: f32 = mid.x - bot.x;

                // At this point we know that line(T-B) is going to be longer than line(T-M) or (M-B)
                // So we can split the triangle in 2 triangles, divided by the horizontal line(y == mid.y)
                const exists_top_half = dyTopMid >= 0.5;
                const exists_bot_half = dyMidBot >= 0.5;

                var side1: f32 = top.x;
                var side2: f32 = top.x;
                if (exists_top_half) {
                    // Calculate the increments (steepness) of the segments of the triangle as we progress with its filling
                    const incrementLongLine: f32 = dxTopBot / dyTopBot;
                    const incrementShortLine: f32 = dxTopMid / dyTopMid;

                    // draw top half
                    var y: usize = @intFromFloat(top.y);
                    while (y > @as(usize, @intFromFloat(mid.y))) : (y -= 1) {
                        
                        // TODO I can probably skip doing this on every line and just do it once
                        var left: usize = @intFromFloat(side1);
                        var right: usize = @intFromFloat(side2);
                        if (left > right) {
                            const aux = left;
                            left = right;
                            right = aux;
                        }
                        
                        var x: usize = left;
                        // draw a horizontal line from left to right
                        while (x < right) : (x += 1) {
                            
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
                                if (requirements.depth_buffer.get(x, y) < z) continue;
                                requirements.depth_buffer.set(x, y, z);
                            }

                            const interpolated_invariants: invariant_type = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants, w_used_for_perspective_correction, u, v, w)
                                else interpolate(invariant_type, invariants, u, v, w);

                            const final_color = fragment_shader(context, interpolated_invariants);
                            
                            if (pipeline_configuration.blend_with_background) {
                                const old_color = pixel_buffer.get(x, y);
                                pixel_buffer.set(x, y, final_color.blend(old_color));
                            }
                            else pixel_buffer.set(x, y, final_color);
                        }

                        side1 -= incrementLongLine;
                        side2 -= incrementShortLine;
                    }

                }

                if (exists_bot_half) {
                    // Calculate the increments (steepness) of the segments of the triangle as we progress with its filling
                    const incrementLongLine: f32 = dxTopBot / dyTopBot;
                    const incrementShortLine: f32 = dxMidBot / dyMidBot;
                    side2 = mid.x;

                    // draw bottom half
                    var y: usize = @intFromFloat(mid.y);
                    while (y > @as(usize, @intFromFloat(bot.y))) : (y -= 1) {
                        
                        // TODO I can probably skip doing this on every line and just do it once
                        var left: usize = @intFromFloat(side1);
                        var right: usize = @intFromFloat(side2);
                        if (left > right) {
                            const aux = left;
                            left = right;
                            right = aux;
                        }
                        
                        var x: usize = left;
                        // draw a horizontal line from left to right
                        while (x < right) : (x += 1) {
                            
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
                                if (requirements.depth_buffer.get(x, y) < z) continue;
                                requirements.depth_buffer.set(x, y, z);
                            }

                            const interpolated_invariants: invariant_type = 
                                if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants, w_used_for_perspective_correction, u, v, w)
                                else interpolate(invariant_type, invariants, u, v, w);

                            const final_color = fragment_shader(context, interpolated_invariants);
                            
                            if (pipeline_configuration.blend_with_background) {
                                const old_color = pixel_buffer.get(x, y);
                                pixel_buffer.set(x, y, final_color.blend(old_color));
                            }
                            else pixel_buffer.set(x, y, final_color);
                        }

                        side1 -= incrementLongLine;
                        side2 -= incrementShortLine;
                    }
                }

                if (!exists_top_half and !exists_bot_half and dyTopBot >= 0.5) {
                    // If neither half is big enough by itself to be drawn, but together they are big enough, then draw it
                    // even though it will be just a line of pixels
                    // TODO draw a line from left to right. figure out which side is mor to the left and which one is more to the right
                }
            }
            fn rasterize_1(pixel_buffer: Buffer2D(final_color_type), context: context_type, requirements: pipeline_configuration.Requirements(), tri: [3]Vector3f, depth: [3]f32, w_used_for_perspective_correction: [3]f32, invariants: [3]invariant_type) void {
                
                trace("rasterize_1", .{});
                trace_triangle(tri);

                // alias each triangle vertex to a, b and c just for readability
                const a = &tri[0];
                const b = &tri[1];
                const c = &tri[2];

                // these are used later when calculating barycenter
                const ab = b.substract(a.*);
                const ac = c.substract(a.*);
                const ca = a.substract(c.*);
                const paralelogram_area_abc: f32 = ab.cross_product(ac).z;
                if (paralelogram_area_abc < std.math.floatEps(f32)) return;

                // calculate the bounds in pixels of the triangle on the screen
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

                trace_bb(left, right, top, bottom);

                // bottom to top
                var y: usize = bottom;
                while (y <= top) : (y += 1) {
                    
                    // left to right
                    var x: usize = left;
                    while (x <= right) : (x += 1) {
                        
                        // calculate barycentric coordinates of the current pixel
                        // NOTE we are checking that THE MIDDLE point of the pixel itself is inside the triangle, hence the +0.5
                        const pixel = Vector3f { .x = @as(f32, @floatFromInt(x)) + 0.5, .y = @as(f32, @floatFromInt(y)) + 0.5, .z = 0 };

                        const ap = pixel.substract(a.*);
                        const bp = pixel.substract(b.*);

                        // NOTE the magnitude of the cross product can be interpreted as the area of the parallelogram.
                        const paralelogram_area_abp: f32 = ab.cross_product(bp).z;
                        const paralelogram_area_cap: f32 = ca.cross_product(ap).z;

                        // The inverse of the barycentric would be `P=wA+uB+vC`
                        const u: f32 = paralelogram_area_cap / paralelogram_area_abc;
                        const v: f32 = paralelogram_area_abp / paralelogram_area_abc;
                        const w: f32 = (1 - u - v);

                        // determine if a pixel is in fact part of the triangle
                        if (u < 0 or u >= 1) continue;
                        if (v < 0 or v >= 1) continue;
                        if (w < 0 or w >= 1) continue;

                        if (pipeline_configuration.do_depth_testing) {
                            // TODO do perspective correct interpolation
                            // if (pipeline_configuration.do_perspective_correct_interpolation) {}
                            // else {}
                            const z = depth[0] * w + depth[1] * u + depth[2] * v;
                            if (requirements.depth_buffer.get(x, y) < z) continue;
                            requirements.depth_buffer.set(x, y, z);
                        }

                        const interpolated_invariants: invariant_type = 
                            if (pipeline_configuration.do_perspective_correct_interpolation) interpolate_with_correction(invariant_type, invariants, w_used_for_perspective_correction, u, v, w)
                            else interpolate(invariant_type, invariants, u, v, w);

                        const final_color = fragment_shader(context, interpolated_invariants);
                        
                        if (pipeline_configuration.blend_with_background) {
                            const old_color = pixel_buffer.get(x, y);
                            pixel_buffer.set(x, y, final_color.blend(old_color));
                        }
                        else pixel_buffer.set(x, y, final_color);

                    }
                }
            }
        };

        /// Here, `t` could be any struct that consists of either floats, ints, or structs.
        /// Structs MUST in turn be composed of all floats or all ints
        /// ex: struct { a: f32, b: Vector2f, c: RGBA }
        /// NOTE I'm assuming that the order of fields inside a struct is kept... which is probably not true in some situations???? but it works for now
        fn interpolate(comptime t: type, data: [3]t, u: f32, v: f32, w: f32) t {
            
            var interpolated_data: t = undefined;

            inline for (@typeInfo(t).@"struct".fields) |field| {
                @field(interpolated_data, field.name) = blk: {
                    
                    const a: *const field.type = &@field(data[0], field.name);
                    const b: *const field.type = &@field(data[1], field.name);
                    const c: *const field.type = &@field(data[2], field.name);
                    const interpolated_result: field.type = switch (@typeInfo(field.type)) {
                        .float => a.* * w + b.* * u + c.* * v,
                        .int => @intFromFloat( @as(f32,@floatFromInt(a.*)) * w + @as(f32,@floatFromInt(b.*)) * u + @as(f32,@floatFromInt(c.*)) * v ),
                        .@"struct" => |s| interpolate_struct: {
                            
                            var interpolated_struct_result: field.type = undefined;
                            inline for (s.fields) |sub_field| {
                                @field(interpolated_struct_result, sub_field.name) = interpolate_struct_field: {
                                    const sub_a: *const sub_field.type = &@field(a, sub_field.name);
                                    const sub_b: *const sub_field.type = &@field(b, sub_field.name);
                                    const sub_c: *const sub_field.type = &@field(c, sub_field.name);
                                    break :interpolate_struct_field switch (@typeInfo(sub_field.type)) {
                                        .float => sub_a.* * w + sub_b.* * u + sub_c.* * v,
                                        .int => @intFromFloat( @as(f32,@floatFromInt(sub_a.*)) * w + @as(f32,@floatFromInt(sub_b.*)) * u + @as(f32,@floatFromInt(sub_c.*)) * v ),
                                        else => @panic("inner struct type " ++ @tagName(sub_field.type) ++ " is neither a Float, Int so it cant be interpolated!")
                                    };
                                };
                            }
                            break :interpolate_struct interpolated_struct_result;

                        },
                        else => @panic("type " ++ @tagName(field.type) ++ " is neither a Float, Int or Struct, so it cant be interpolated!")
                    };

                    break :blk interpolated_result;
                };
            }

            return interpolated_data;
        }

        /// Same as `interpolate` but applies perspective correction using the provided correction_values
        /// Here, `t` could be any struct that consists of either floats, ints, or structs.
        /// Structs MUST in turn be composed of all floats or all ints
        /// ex: struct { a: f32, b: Vector2f, c: RGBA }
        /// NOTE I'm assuming that the order of fields inside a struct is kept... which is probably not true in some situations???? but it works for now
        fn interpolate_with_correction(comptime t: type, data: [3]t, correction_values: [3]f32, u: f32, v: f32, w: f32) t {
            
            var interpolated_data: t = undefined;

            const correction = 1/correction_values[0] * w + 1/correction_values[1] * u + 1/correction_values[2] * v;

            inline for (@typeInfo(t).@"struct".fields) |field| {
                @field(interpolated_data, field.name) = interpolate_field: {
                    
                    const a: *const field.type = &@field(data[0], field.name);
                    const b: *const field.type = &@field(data[1], field.name);
                    const c: *const field.type = &@field(data[2], field.name);
                    const interpolated_result: field.type = switch (@typeInfo(field.type)) {
                        .float => blk: {
                            const fa: f32 = a.* / correction_values[0];
                            const fb: f32 = b.* / correction_values[1];
                            const fc: f32 = c.* / correction_values[2];
                            break :blk (fa * w + fb * u + fc * v) / correction;
                        },
                        .int => blk: {
                            const fa: f32 = @as(f32, @floatFromInt(a.*)) / correction_values[0];
                            const fb: f32 = @as(f32, @floatFromInt(b.*)) / correction_values[1];
                            const fc: f32 = @as(f32, @floatFromInt(c.*)) / correction_values[2];
                            const result = (fa * w + fb * u + fc * v) / correction;
                            break :blk @intFromFloat(result);
                        },
                        .@"struct" => |s| interpolate_struct: {
                            
                            var interpolated_struct_result: field.type = undefined;
                            inline for (s.fields) |sub_field| {
                                @field(interpolated_struct_result, sub_field.name) = interpolate_struct_field: {
                                    
                                    const sub_a: *const sub_field.type = &@field(a, sub_field.name);
                                    const sub_b: *const sub_field.type = &@field(b, sub_field.name);
                                    const sub_c: *const sub_field.type = &@field(c, sub_field.name);
                                    break :interpolate_struct_field switch (@typeInfo(sub_field.type)) {
                                        .float => blk: {
                                            const fa: f32 = sub_a.* / correction_values[0];
                                            const fb: f32 = sub_b.* / correction_values[1];
                                            const fc: f32 = sub_c.* / correction_values[2];
                                            break :blk (fa * w + fb * u + fc * v) / correction;
                                        },
                                        .int => blk: {
                                            const fa: f32 = @as(f32, @floatFromInt(sub_a.*)) / correction_values[0];
                                            const fb: f32 = @as(f32, @floatFromInt(sub_b.*)) / correction_values[1];
                                            const fc: f32 = @as(f32, @floatFromInt(sub_c.*)) / correction_values[2];
                                            const result = (fa * w + fb * u + fc * v) / correction;
                                            break :blk @intFromFloat(result);
                                        },
                                        else => @panic("inner struct type " ++ @tagName(sub_field.type) ++ " is neither a Float, Int so it cant be interpolated!")
                                    };
                                };
                            }
                            break :interpolate_struct interpolated_struct_result;

                        },
                        else => @panic("type " ++ @tagName(field.type) ++ " is neither a Float, Int or Struct, so it cant be interpolated!")
                    };

                    break :interpolate_field interpolated_result;
                };
            }

            return interpolated_data;
        }

        fn barycentric(triangle: [3]Vector3f, point: Vector3f) Vector3f {
            // barycentric coordinates of the current pixel
            const ab = triangle[1].substract(triangle[0]);
            const ac = triangle[2].substract(triangle[0]);
            const ap = point.substract(triangle[0]);
            const bp = point.substract(triangle[1]);
            const ca = triangle[0].substract(triangle[2]);

            // TODO PERF we dont actually need many of the calculations of cross_product here, just the z
            // the magnitude of the cross product can be interpreted as the area of the parallelogram.
            const paralelogram_area_abc: f32 = ab.cross_product(ac).z;
            const paralelogram_area_abp: f32 = ab.cross_product(bp).z;
            const paralelogram_area_cap: f32 = ca.cross_product(ap).z;

            const u: f32 = paralelogram_area_cap / paralelogram_area_abc;
            const v: f32 = paralelogram_area_abp / paralelogram_area_abc;
            const w: f32 = (1 - u - v);

            return .{.x = u, .y = v, .z = w};
        }

        fn trace_bb(left: usize, right: usize, top: usize, bottom: usize) void {
            trace("T.BB: left {}, right {}, top {}, bottom {}", .{left, right, top, bottom});
        }

        fn trace_triangle_4(t: [3]Vector4f) void {
            trace("T.A: {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{t[0].x,t[0].y,t[0].z,t[0].w});
            trace("T.B: {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{t[1].x,t[1].y,t[1].z,t[1].w});
            trace("T.C: {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{t[2].x,t[2].y,t[2].z,t[2].w});
        }

        fn trace_triangle(t: [3]Vector3f) void {
            trace("T.A: {d:.8}, {d:.8}, {d:.8}", .{t[0].x,t[0].y,t[0].z});
            trace("T.B: {d:.8}, {d:.8}, {d:.8}", .{t[1].x,t[1].y,t[1].z});
            trace("T.C: {d:.8}, {d:.8}, {d:.8}", .{t[2].x,t[2].y,t[2].z});
        }

        fn trace_mat4(m: M44) void {
            trace("M {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{m.data[0], m.data[4], m.data[8], m.data[12]});
            trace("M {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{m.data[1], m.data[5], m.data[9], m.data[13]});
            trace("M {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{m.data[2], m.data[6], m.data[10], m.data[14]});
            trace("M {d:.8}, {d:.8}, {d:.8}, {d:.8}", .{m.data[3], m.data[7], m.data[11], m.data[15]});
        }

        fn trace(comptime fmt: []const u8, args: anytype) void {
            if (!pipeline_configuration.trace) return;
            std.log.debug(fmt, args);
        }

    };
}

pub const GraphicsPipelineQuads2DConfiguration = struct {
    blend_with_background: bool = false,
    do_quad_clipping: bool = false,
    do_scissoring: bool = false,
    trace: bool = false,
    
    /// returns a comptime tpye (an struct, basically) which needs to be filled, and passed as a value to the render pipeline when calling `render`
    pub fn Requirements(comptime self: GraphicsPipelineQuads2DConfiguration) type {
        var fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField {
            std.builtin.Type.StructField {
                .default_value = null,
                .is_comptime = false,
                .name = "viewport_matrix",
                .type = M33,
                .alignment = @alignOf(M33)
            },
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
        const declarations: []const std.builtin.Type.Declaration = &[_]std.builtin.Type.Declaration {};
        const requirements = std.builtin.Type {
            .@"struct" = .{
                .is_tuple = false,
                .fields = fields,
                .layout = .auto,
                .decls = declarations,
            }
        };
        return @Type(requirements);
    }
};

pub fn GraphicsPipelineQuads2D(
    comptime final_color_type: type,
    comptime context_type: type,
    comptime invariant_type: type,
    comptime vertex_type: type,
    comptime pipeline_configuration: GraphicsPipelineQuads2DConfiguration,
    comptime vertex_shader: fn(context: context_type, vertex_buffer: vertex_type, out_invariant: *invariant_type) callconv(.Inline) Vector3f,
    comptime fragment_shader: fn(context: context_type, invariants: invariant_type) callconv(.Inline) final_color_type,
) type {
    return struct {

        pub fn render(pixel_buffer: Buffer2D(final_color_type), context: context_type, vertex_buffer: []const vertex_type, face_count: usize, requirements: pipeline_configuration.Requirements()) void {
            var face_index: usize = 0;
            label_outer: while (face_index < face_count) : (face_index += 1) {
                
                var invariants: [4]invariant_type = undefined;
                var normalized: [4]Vector2f = undefined;
                var screen_space_position: [4]Vector2f = undefined;
                var not_inside: usize = 0;

                inline for(0..4) |i| {
                    const vertex_data: vertex_type = vertex_buffer[face_index * 4 + i];
                    normalized[i] = vertex_shader(context, vertex_data, &invariants[i]).perspective_division();
                    if (normalized[i].x > 1 or normalized[i].x < -1 or normalized[i].y > 1 or normalized[i].y < -1) {
                        if (pipeline_configuration.do_quad_clipping) not_inside += 1
                        else continue :label_outer;
                    }
                    screen_space_position[i] = requirements.viewport_matrix.apply_to_vec2(normalized[i]).perspective_division();
                }

                if (pipeline_configuration.do_quad_clipping) {
                    if (not_inside == 0) rasterizer(pixel_buffer, context, requirements, screen_space_position[0..4].*, invariants[0..4].*)
                    else {
                        const left = normalized[0].x;
                        const right = normalized[1].x;
                        if ((left < -1 and right < -1) or (left > 1 and right > 1)) continue :label_outer;
                        const bottom = normalized[0].y;
                        const top = normalized[2].y;
                        if ((bottom < -1 and top < -1) or (bottom > 1 and top > 1)) continue :label_outer;

                        // else, there is pixels to draw, so calculate the clipped quad
                        const height_f: f32 = top - bottom;
                        const width_f: f32 = right - left;
                        
                        const new_left = @max(left, -1);
                        const new_right = @min(right, 1);
                        const new_bottom = @max(bottom, -1);
                        const new_top = @min(top, 1);

                        var new_normalized: [4]Vector2f = undefined;
                        new_normalized[0] = Vector2f.from(new_left, new_bottom);
                        new_normalized[1] = Vector2f.from(new_right, new_bottom);
                        new_normalized[2] = Vector2f.from(new_right, new_top);
                        new_normalized[3] = Vector2f.from(new_left, new_top);

                        var new_invariants: [4]invariant_type = undefined;
                        new_invariants[0] = interpolate(invariant_type, invariants, (new_normalized[0].x-left) / width_f, (new_normalized[0].y-bottom) / height_f);
                        new_invariants[1] = interpolate(invariant_type, invariants, (new_normalized[1].x-left) / width_f, (new_normalized[1].y-bottom) / height_f);
                        new_invariants[2] = interpolate(invariant_type, invariants, (new_normalized[2].x-left) / width_f, (new_normalized[2].y-bottom) / height_f);
                        new_invariants[3] = interpolate(invariant_type, invariants, (new_normalized[3].x-left) / width_f, (new_normalized[3].y-bottom) / height_f);

                        var new_screen_space_position: [4]Vector2f = undefined;
                        new_screen_space_position[0] = requirements.viewport_matrix.apply_to_vec2(new_normalized[0]).perspective_division();
                        new_screen_space_position[1] = requirements.viewport_matrix.apply_to_vec2(new_normalized[1]).perspective_division();
                        new_screen_space_position[2] = requirements.viewport_matrix.apply_to_vec2(new_normalized[2]).perspective_division();
                        new_screen_space_position[3] = requirements.viewport_matrix.apply_to_vec2(new_normalized[3]).perspective_division();

                        rasterizer(pixel_buffer, context, requirements, new_screen_space_position[0..4].*, new_invariants[0..4].*);
                    }
                }
                else rasterizer(pixel_buffer, context, requirements, screen_space_position[0..4].*, invariants[0..4].*);
            }
        }

        // TODO rasterize quad that are not given in order bl, br, tr, tl
        /// assumes that the quad and the invariants are given in the order: bl, br, tr, tl
        fn rasterizer(pixel_buffer: Buffer2D(final_color_type), context: context_type, requirements: pipeline_configuration.Requirements(), quad: [4]Vector2f, invariants: [4]invariant_type) void {
            
            trace("rasterize quad:", .{});
            trace_quad(quad);

            const height_f: f32 = quad[2].y - quad[0].y;
            const width_f: f32 = quad[1].x - quad[3].x;
            trace("height: {d:.4} width: {d:.4}", .{height_f, width_f});

            const bb: BoundingBox = blk: {
                var bottom: usize = @intFromFloat(@floor(quad[0].y+0.5));
                var right: usize = @intFromFloat(@ceil(quad[1].x-0.5));
                var top: usize = @intFromFloat(@ceil(quad[2].y-0.5));
                var left: usize = @intFromFloat(@floor(quad[3].x+0.5));
                if (pipeline_configuration.do_scissoring) {
                    // TODO this can be factored out and used as constant through a single render pass of the pipeline
                    const scissor_bottom: usize = @intFromFloat(@floor(requirements.scissor_rect.y+0.5));
                    const scissor_right: usize = @intFromFloat(@ceil(requirements.scissor_rect.z-0.5));
                    const scissor_top: usize = @intFromFloat(@ceil(requirements.scissor_rect.w-0.5));
                    const scissor_left: usize = @intFromFloat(@floor(requirements.scissor_rect.x+0.5));
                    
                    bottom = @max(bottom, scissor_bottom);
                    right = @min(right, scissor_right);
                    top = @min(top, scissor_top);
                    left = @max(left, scissor_left);
                }
                break :blk BoundingBox { .bottom = bottom, .top = top, .left = left, .right = right };
            };
            trace_bb(bb.left, bb.right, bb.top, bb.bottom);

            if (bb.top == 0) return;
            if (bb.right == 0) return;

            var y = bb.bottom;
            while (y < bb.top) : (y += 1) {
                const percentage_y: f32 = (@as(f32, @floatFromInt(y))-quad[0].y+0.5) / height_f;
                std.debug.assert(percentage_y <= 1 and percentage_y >= 0);

                var x = bb.left;
                while (x < bb.right) : (x += 1) {
                    const percentage_x: f32 = (@as(f32, @floatFromInt(x))-quad[0].x+0.5) / width_f;
                    std.debug.assert(percentage_x <= 1 and percentage_x >= 0);

                    const interpolated_invariants: invariant_type = interpolate(invariant_type, invariants, percentage_x, percentage_y);
                    const final_color = fragment_shader(context, interpolated_invariants);

                    if (pipeline_configuration.blend_with_background) {
                        const old_color = pixel_buffer.get(x, y);
                        pixel_buffer.set(x, y, final_color.blend(old_color));
                    }
                    else pixel_buffer.set(x, y, final_color);

                }
            }
        }

        const BoundingBox = struct {
            bottom: usize,
            right: usize,
            top: usize,
            left: usize,
        };

        /// `percentage_x` left to right
        /// `percentage_y` bottom to top
        inline fn bilinear_interpolation(bl: f32, br: f32, tr: f32, tl: f32, percentage_x: f32, percentage_y: f32) f32 {
            const horizontal_bottom = (bl * (1 - percentage_x)) + (br * percentage_x);
            const horizontal_top = (tl * (1 - percentage_x)) + (tr * percentage_x);
            return (horizontal_bottom * (1 - percentage_y)) + (horizontal_top * percentage_y);
        }
        
        inline fn interpolate(comptime t: type, data: [4]t, x: f32, y: f32) t {
            
            var interpolated_data: t = undefined;

            inline for (@typeInfo(t).@"struct".fields) |field| {
                @field(interpolated_data, field.name) = blk: {
                    
                    const bl: *const field.type = &@field(data[0], field.name);
                    const br: *const field.type = &@field(data[1], field.name);
                    const tr: *const field.type = &@field(data[2], field.name);
                    const tl: *const field.type = &@field(data[3], field.name);

                    const interpolated_result: field.type = switch (@typeInfo(field.type)) {
                        .float => bilinear_interpolation(bl.*, br.*, tr.*, tl.*, x, y),
                        .int => @intFromFloat(bilinear_interpolation(@floatFromInt(bl.*), @floatFromInt(br.*), @floatFromInt(tr.*), @floatFromInt(tl.*), x, y)),
                        .@"struct" => |s| interpolate_struct: {
                            
                            var interpolated_struct_result: field.type = undefined;
                            inline for (s.fields) |sub_field| {
                                @field(interpolated_struct_result, sub_field.name) = interpolate_struct_field: {
                                    const sub_bl: *const sub_field.type = &@field(bl, sub_field.name);
                                    const sub_br: *const sub_field.type = &@field(br, sub_field.name);
                                    const sub_tr: *const sub_field.type = &@field(tr, sub_field.name);
                                    const sub_tl: *const sub_field.type = &@field(tl, sub_field.name);
                                    break :interpolate_struct_field switch (@typeInfo(sub_field.type)) {
                                        .float => bilinear_interpolation(sub_bl.*, sub_br.*, sub_tr.*, sub_tl.*, x, y),
                                        .int => @intFromFloat(bilinear_interpolation(@floatFromInt(sub_bl.*), @floatFromInt(sub_br.*), @floatFromInt(sub_tr.*), @floatFromInt(sub_tl.*), x, y)),
                                        else => @panic("inner struct type " ++ @tagName(sub_field.type) ++ " is neither a Float, Int so it cant be interpolated!")
                                    };
                                };
                            }
                            break :interpolate_struct interpolated_struct_result;

                        },
                        else => @panic("type " ++ @tagName(field.type) ++ " is neither a Float, Int or Struct, so it cant be interpolated!")
                    };

                    break :blk interpolated_result;
                };
            }

            return interpolated_data;
        }
    
        inline fn trace_bb(left: usize, right: usize, top: usize, bottom: usize) void {
            if (!pipeline_configuration.trace) return;
            trace("bounding box: left {}, right {}, top {}, bottom {}", .{left, right, top, bottom});
        }

        inline fn trace_quad(quad: [4]Vector2f) void {
            if (!pipeline_configuration.trace) return;
            trace("quad[0]: {d:.4}, {d:.4}, ", .{quad[0].x,quad[0].y});
            trace("quad[1]: {d:.4}, {d:.4}, ", .{quad[1].x,quad[1].y});
            trace("quad[2]: {d:.4}, {d:.4}, ", .{quad[2].x,quad[2].y});
            trace("quad[3]: {d:.4}, {d:.4}, ", .{quad[3].x,quad[3].y});
        }

        inline fn trace_mat4(m: M33) void {
            if (!pipeline_configuration.trace) return;
            trace("M33: | {d:.8} {d:.8} {d:.8} |", .{m.data[0], m.data[3], m.data[6],});
            trace("     | {d:.8} {d:.8} {d:.8} |", .{m.data[1], m.data[4], m.data[7],});
            trace("     | {d:.8} {d:.8} {d:.8} |", .{m.data[2], m.data[5], m.data[8],});
        }

        inline fn trace(comptime fmt: []const u8, args: anytype) void {
            if (!pipeline_configuration.trace) return;
            std.log.debug(fmt, args);
        }
    };
}
