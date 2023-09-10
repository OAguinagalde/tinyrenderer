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
        .source_file = .{ .path = "dep/zigwin32/win32.zig" },
    });
    exe.addModule("win32", win32);
    
    // imgui
    exe.linkLibCpp();
    exe.addCSourceFile(.{ .file = .{ .path = "dep/cimgui/imgui/imgui.cpp" }, .flags = &[_] []const u8 {""} });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/cimgui/imgui/imgui_draw.cpp" }, .flags = &[_] []const u8 {""} });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/cimgui/imgui/imgui_demo.cpp" }, .flags = &[_] []const u8 {""} });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/cimgui/imgui/imgui_tables.cpp" }, .flags = &[_] []const u8 {""} });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/cimgui/imgui/imgui_widgets.cpp" }, .flags = &[_] []const u8 {""} });
    // exe.addCSourceFile(.{ .file = .{ .path = "dep/cimgui/imgui/backends/imgui_impl_win32.cpp" }, .flags = &[_] []const u8 {"-Idep/cimgui/imgui/", "-Idep/cimgui/imgui/backends/"} }); {
    //     exe.linkSystemLibrary("dwmapi");
    // }
    // exe.addCSourceFile(.{ .file = .{ .path = "dep/cimgui/imgui/backends/imgui_impl_opengl3.cpp" }, .flags = &[_] []const u8 {"-Idep/cimgui/imgui/",} });
    exe.addCSourceFile(.{ .file = .{ .path = "dep/cimgui/cimgui.cpp" }, .flags = &[_] []const u8 {""} });
    exe.addIncludePath(.{ .path = "dep/cimgui" });
    // exe.addIncludePath(.{ .path = "dep/cimgui/imgui/backends" });
}
