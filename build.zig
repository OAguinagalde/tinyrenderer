const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const optimization_options = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "windows",
        .root_source_file = .{ .path = "src/windows.zig" },
        .target = target,
        .optimize = optimization_options,
    });
    // exe.single_threaded = true;
    // exe.subsystem = .Windows;
    b.installArtifact(exe);

    const win32 = b.createModule(.{
        // https://github.com/marlersoft/zigwin32 - e61d5e9 - 21.0.3-preview
        .source_file = .{ .path = "../zigwin32/win32.zig" },
    });
    exe.addModule("win32", win32);
}
