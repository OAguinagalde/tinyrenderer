const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) !void {

    const target_win32 = b.option(bool, "win32", "default compilation for win32") orelse false;
    const target_wasm = b.option(bool, "wasm", "default compilation for wasm") orelse false;
    if (!(target_win32 or target_wasm)) {
        std.log.err("choose a target, ex: `zig build -Dwin32`", .{});
        return error.NoTarget;
    }
    
    const run_step = b.step("run", "Run the application");

    if (target_win32) {
        // const target = b.standardTargetOptions(.{});
        const optimization_options = b.standardOptimizeOption(.{});
        const exe = b.addExecutable(.{
            .name = "windows",
            .root_source_file = .{ .path = "src/windows.zig" },
            .target = .{ .os_tag = .windows },
            .optimize = optimization_options,
        });

        // https://github.com/marlersoft/zigwin32 - e61d5e9 - 21.0.3-preview
        const win32 = b.createModule(.{
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
        exe.addCSourceFile(.{ .file = .{ .path = "dep/cimgui/cimgui.cpp" }, .flags = &[_] []const u8 {""} });
        exe.addIncludePath(.{ .path = "dep/cimgui" });

        b.installArtifact(exe);
        // TODO make a ultra simple web server just for serving the wasm project lol
        var step_run = b.addRunArtifact(exe);
        run_step.dependOn(&step_run.step);
    }
    
    if (target_wasm) {

        // Number of pages reserved for heap memory.
        // This must match the number of pages used in script.js.
        // 64 kb per page
        const number_of_pages = 100;
        const optimization_options = b.standardOptimizeOption(.{});
        const lib = b.addSharedLibrary(.{
            .name = "wasm_app",
            .root_source_file = .{ .path = "src/wasm_app.zig" },
            .target = .{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            },
            .optimize = optimization_options,
        });
        
        // for a wasm library to export symbols one needs to specify the -rdynamic flag
        // meaning that if this is not true, the wasm runtime wont be able to call exported functions
        lib.rdynamic = true;
        
        // meaning that the runtime that loads our wasm module (js) will provide the
        // memory that our wasm module will work with (the `WebAssembly.Memory` object)
        lib.import_memory = true;
        // the provided memory doesnt change, it is excatly `number_of_pages * page_size`
        // so both `initial_memory` and `max_memory` are the same
        lib.initial_memory = std.wasm.page_size * number_of_pages;
        lib.max_memory = std.wasm.page_size * number_of_pages;
        // Out of that memory, we reserve 1 page for the shadow stack
        lib.stack_size = std.wasm.page_size;
        // we could reserve an X ammount of memory out of the provided memory, for example for
        // io mapping or something similar. This is the case with tic80 for instance
        // 
        //    lib.global_base = X;
        // 

        // generate a compile time file with the settings used for building the wasm module,
        // which will in turn be embedded into the module itself, so that the module knows
        // these parameters
        // const str = b.fmt(
        //     \\pub const initial_memory: usize = {d};
        //     \\pub const max_memory: usize = {d};
        //     \\pub const stack_size: usize = {d};
        //     \\pub const global_base: usize = {d};
        //     , .{
        //         lib.initial_memory orelse @as(u64, 0),
        //         lib.max_memory orelse @as(u64, 0),
        //         lib.stack_size orelse @as(u64, 0),
        //         lib.global_base orelse @as(u64, 0)
        //     }
        // );
        // std.log.info("{s}",.{str});

        // const step_tool_runner = b.addRunArtifact(b.addExecutable(.{
        //     .name = "write_wasm_module_memory_info",
        //     .root_source_file = .{ .path = "src/stdin_to_file.zig" },
        // }));
        // step_tool_runner.setStdIn(.{ .bytes = str });
        // Its a weird default but this basically adds the file name as the first argument...
        // const output = step_tool_runner.addOutputFileArg("memory_info.zig");
        
        // allow @import to "see" the generated file `memory_info.zon`
        // lib.addAnonymousModule("comptime_memory_info", .{ .source_file = output });

        // There is 3 things that need to happen to build the project for wasm:
        // 1. compile the zig code to targe wasm
        // 2. copy the index.html which has the canvas
        // 3. copy the js logic which links the canvas and the wasm module
        var step_compile_wasm_library = b.addInstallArtifact(lib, .{});
        // step_compile_wasm_library.step.dependOn(&step_write_memory_info.step);
        var step_copy_html = b.addInstallFile(.{.path="src/index.html"}, "./index.html");
        var step_copy_js = b.addInstallFile(.{.path="src/wasm_app_canvas_loader.js"}, "./wasm_app_canvas_loader.js");
        // All three steps need to be happen in order to consider the build successfull
        // NOTE InstallStep is just how zig calls the "main build task", by itself it does nothing
        // but by making it depend on other tasks, it will run those first
        b.getInstallStep().dependOn(&step_compile_wasm_library.step);
        b.getInstallStep().dependOn(&step_copy_html.step);
        b.getInstallStep().dependOn(&step_copy_js.step);

        // TODO make a ultra simple web server just for serving the wasm project lol
        var step_run = addRunCodeStep(b, struct {
            fn code() void {
                std.log.info("You can test the project at zig-out/index.html", .{});
            }
        }.code);
        step_run.dependOn(b.getInstallStep());
        run_step.dependOn(step_run);
    }

}

fn addRunCodeStep(builder: *std.Build, comptime code: fn()void) *std.Build.Step {
    const step = builder.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "Running some code",
        .owner = builder,
        .makeFn = struct {
            fn code_runner(s: *std.Build.Step, n: *std.Progress.Node) !void {
                _ = s;
                _ = n;
                code();
            }
        }.code_runner,
    });
    return step;
}
