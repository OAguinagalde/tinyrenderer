const std = @import("std");

pub fn main() !void {
    
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);
    if (args.len != 3) {
        std.debug.print("\n", .{});
        for(args, 0..) |arg, i| std.debug.print("{}: {s}\n", .{i, arg});
        err("wrong number of arguments", .{});
    }
    
    const input_file_path = args[1];
    const zig_source = try std.fs.cwd().readFileAlloc(arena, input_file_path, std.math.maxInt(usize));
    const zig_source_z = try std.fmt.allocPrintZ(arena, "{s}", .{zig_source});
    
    const output_file_path = args[2];
    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |e| {
        err("unable to open '{s}': {s}", .{ output_file_path, @errorName(e) });
    };
    defer output_file.close();

    const ast = try std.zig.Ast.parse(arena, zig_source_z, .zig);
    for (ast.nodes.items(.tag), 0..) |t, i| {
        const index: u32 = @intCast(i);
        const node = ast.nodes.get(@intCast(i));
        if (t == std.zig.Ast.Node.Tag.call) {
            const node_src = ast.getNodeSource(node.data.lhs);
            if (std.mem.eql(u8, node_src, "js")) {
                const call = ast.callFull(index);
                const node_id = call.ast.params[0];
                const node_id_src = ast.getNodeSource(node_id);
                const node_multiline_string = call.ast.params[1];
                const node_multiline_string_src = ast.getNodeSource(node_multiline_string);
                var string_literal = std.ArrayList(u8).init(arena);            
                var tokenizer = std.mem.tokenize(u8, node_multiline_string_src, "\n");
                while (tokenizer.next()) |line| {
                    const string_literal_line: []const u8 = blk: {
                        var found_first_backslash = false;
                        var string_literal_real_start: usize = undefined;
                        for (line, 0..) |c, char_index| switch (c) {
                            ' ' => {
                                if (found_first_backslash) err("malformed multiline string? {s}", .{line});
                            },
                            '\\' => {
                                if (found_first_backslash) {
                                    string_literal_real_start = char_index+1;
                                    break;
                                }
                                else found_first_backslash = true;
                            },
                            else => {
                                err("malformed multiline string? {s}", .{line});
                            }
                        };
                        break :blk line[string_literal_real_start..line.len-1];
                    };
                    try string_literal.appendSlice("    ");
                    try string_literal.appendSlice(string_literal_line);
                    try string_literal.append('\n');
                }
                const js_code = string_literal.items;
                const js_code_full = try std.fmt.allocPrint(arena,
                    \\window.inlined_functions[{s}] = () => {{
                    \\{s}
                    \\}};
                    \\
                    ,
                    .{
                        node_id_src,
                        js_code
                    }
                );
                output_file.writer().writeAll(js_code_full) catch err("error writing", .{});
            }
        }
    }
    
}

fn err(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}
