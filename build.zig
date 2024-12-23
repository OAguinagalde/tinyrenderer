const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) !void {

    var target_win32 = b.option([]const u8, "win32", "default compilation for win32");
    const target_wasm = b.option([]const u8, "wasm", "default compilation for wasm");
    const run_step = b.step("run", "Run the application");

    // if nothing defined, default to something on build
    const do_default = target_win32 == null and target_wasm == null;
    if (do_default) {
        target_win32 = "src/app_004.zig";
    }
    
    const check = b.step("check", "Check if foo compiles");

    if (target_win32) |root_file| {

        const tracy = b.option([]const u8, "tracy", "Enable Tracy integration. Supply path to Tracy source");
        const tracy_callstack = b.option(bool, "tracy-callstack", "Include callstack information with Tracy data. Does nothing if -Dtracy is not provided") orelse (tracy != null);
        const tracy_allocation = b.option(bool, "tracy-allocation", "Include allocation information with Tracy data. Does nothing if -Dtracy is not provided") orelse (tracy != null);

        const optimization_options = b.standardOptimizeOption(.{});
        const target = b.resolveTargetQuery(.{ .os_tag = .windows });

        const exe = b.addExecutable(.{
            .name = "windows",
            .root_source_file = .{ .cwd_relative = root_file },
            .target = target,
            .optimize = optimization_options,
        });

        // https://github.com/marlersoft/zigwin32 - e61d5e9 - 21.0.3-preview
        const win32 = b.createModule(.{
            .root_source_file = .{ .cwd_relative = "dep/zigwin32/win32.zig" },
        });
        exe.root_module.addImport("win32", win32);
        
        b.installArtifact(exe);
        var step_run = b.addRunArtifact(exe);
        run_step.dependOn(&step_run.step);

        // To activate on save diagnose on vscode
        // > https://kristoff.it/blog/improving-your-zls-experience/
        // 1. Install Error Lens
        // 2. Set the zls settings on vscode:
        // 
        //     {
        //       "enable_build_on_save": true,
        //       "build_on_save_step": "check"
        //     }
        // 
        // 3. Make sure that `zig build check` builds whatever you are working on.
        // On every save it will (just) check the program and on error show a diagnostick on directly in vscode
        {
            const exe_check = b.addExecutable(.{
                .name = "windows",
                .root_source_file = .{ .cwd_relative = root_file },
                .target = target,
                .optimize = optimization_options,
            });
            exe_check.root_module.addImport("win32", win32);
            check.dependOn(&exe_check.step);
        }

        const exe_options = b.addOptions();
        exe.root_module.addOptions("build_options", exe_options);

        exe_options.addOption(bool, "enable_tracy", tracy != null);
        exe_options.addOption(bool, "enable_tracy_callstack", tracy_callstack);
        exe_options.addOption(bool, "enable_tracy_allocation", tracy_allocation);
        if (tracy) |tracy_path| {
            const client_cpp = std.fs.path.join(
                b.allocator,
                &[_][]const u8{ tracy_path, "public", "TracyClient.cpp" },
            ) catch unreachable;

            // const tracy_c_flags: []const []const u8 = if (target.isWindows() and target.getAbi() == .gnu)
            const tracy_c_flags: []const []const u8 = if (target.result.isMinGW())
                &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined", "-D_WIN32_WINNT=0x601" }
            else
                &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

            
            exe.addIncludePath(.{ .cwd_relative = tracy_path });
            exe.addCSourceFile(.{ .file = .{ .cwd_relative = client_cpp }, .flags = tracy_c_flags });

            // if (!enable_llvm) {
                exe.linkSystemLibrary("c++");
            // }

            exe.linkLibC();

            if (target.result.os.tag == .windows) {
                exe.linkSystemLibrary("dbghelp");
                exe.linkSystemLibrary("ws2_32");
            }
        }
    }
    else if (target_wasm) |root_file| {

        // Number of pages reserved for heap memory.
        // This must match the number of pages used in script.js.
        // 64 kib per page * 1024 pages = 64 mib
        const number_of_pages = 1024;
        const optimization_options = b.standardOptimizeOption(.{});
        
        const target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        });

        const exe = b.addExecutable(.{
            .name = "wasm_app",
            .root_source_file = .{ .cwd_relative = root_file },
            .target = target,
            .optimize = optimization_options,
        });
        
        // Executable with no entry-point since js will manage that
        exe.entry = .disabled;
        // for a wasm library to export symbols one needs to specify the -rdynamic flag
        // meaning that if this is not true, the wasm runtime wont be able to call exported functions
        exe.rdynamic = true;
        // meaning that the runtime that loads our wasm module (js) will provide the
        // memory that our wasm module will work with (the `WebAssembly.Memory` object)
        exe.import_memory = true;
        // the provided memory doesnt change, it is excatly `number_of_pages * page_size`
        // so both `initial_memory` and `max_memory` are the same
        exe.initial_memory = std.wasm.page_size * number_of_pages;
        exe.max_memory = std.wasm.page_size * number_of_pages;
        // Out of that memory, we reserve 16 pages for the stack (1 mib)
        exe.stack_size = std.wasm.page_size * 16;
        // we could reserve an X ammount of memory out of the provided memory, for example for
        // io mapping or something similar. This is the case with tic80 for instance
        // 
        //    exe.global_base = X;
        // 

        // There is 3 things that need to happen to build the project for wasm:
        // 1. compile the zig code to targe wasm
        // 2. copy the index.html which has the canvas
        // 3. copy the js logic which links the canvas and the wasm module
        // 3. copy resources
        var step_compile_wasm_executable = b.addInstallArtifact(exe, .{});
        var step_copy_res = b.addInstallDirectory(.{ .source_dir = .{ .cwd_relative = "res" }, .install_dir = .{ .custom = "./" }, .install_subdir = "./res" });
        var step_copy_html = b.addInstallFile(.{ .cwd_relative = "src/index.html" }, "./index.html");
        var step_copy_js = b.addInstallFile(.{ .cwd_relative = "src/wasm_app_canvas_loader.js" }, "./wasm_app_canvas_loader.js");

        const generated = generate_inline_js_file(b, "src/wasm.zig", "generated.js", &step_copy_js.step);
        var step_inline_js = b.addInstallFile(generated, "./generated.js");
        
        // NOTE InstallStep is just how zig calls the "main build task", by itself it does nothing
        // but by making it depend on other tasks, it will run those first
        b.getInstallStep().dependOn(&step_compile_wasm_executable.step);
        b.getInstallStep().dependOn(&step_copy_res.step);
        b.getInstallStep().dependOn(&step_copy_html.step);
        b.getInstallStep().dependOn(&step_copy_js.step);
        b.getInstallStep().dependOn(&step_inline_js.step);

        // TODO make a ultra simple web server just for serving the wasm project lol
        var step_run = run_coded_as_step(b, struct {
            fn code() void {
                std.log.info("You can test the project at zig-out/index.html", .{});
            }
        }.code);
        step_run.dependOn(b.getInstallStep());
        run_step.dependOn(step_run);
    }
    else {
        return error.NoBuildTargetDefined;
    }
}

/// Allows you to `@import(name)` any data into a compilation unit:
/// 
///     embed_str_as_module(b, "pub const SomeConstant: usize = 1337;", "constants.zig", lib);
/// 
/// Then somewhere in the lib's code:
/// 
///     const constants = @import("constants.zig");
///     std.log.debug("{}", .{constants.SomeConstant});
/// 
/// which will print "1337"
fn embed_str_as_module(b: *std.Build, comptime str: []const u8, comptime name: []const u8, compilation: *std.Build.Step.Compile) void {
    const step_tool_runner = b.addRunArtifact(b.addExecutable(.{
        .name = "Embed data as anonymous module",
        .root_source_file = .{ .cwd_relative = "src/stdin_to_file.zig" },
    }));
    step_tool_runner.setStdIn(.{ .bytes = str });
    // Its a weird default but this basically adds the file name as the first argument...
    const output = step_tool_runner.addOutputFileArg(name);
    // allow @import to "see" the generated file `memory_info.zon`
    compilation.addAnonymousModule(name, .{ .source_file = output });
    compilation.step.dependOn(&step_tool_runner.step);
}

fn generate_inline_js_file(b: *std.Build, comptime in_zig_file: []const u8, comptime out_generated_js_file: []const u8, step: *std.Build.Step) std.Build.LazyPath {
    // b.standardTargetOptions(.{});
    // const target = b.resolveTargetQuery(.{
    //     .cpu_arch = .wasm32,
    //     .os_tag = .freestanding,
    // });
    const step_tool_runner = b.addRunArtifact(b.addExecutable(.{
        .name = "generate inline js source file",
        .target = b.standardTargetOptions(.{}),
        .root_source_file = .{ .cwd_relative = "src/generate_inline_js.zig" },
    }));
    step_tool_runner.addFileArg(.{ .cwd_relative = in_zig_file });
    const output = step_tool_runner.addOutputFileArg(out_generated_js_file);
    step.dependOn(&step_tool_runner.step);
    return output;
}

fn run_coded_as_step(builder: *std.Build, comptime code: fn () void) *std.Build.Step {
    const step = builder.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "Running some code",
        .owner = builder,
        .makeFn = struct {
            fn code_runner(s: *std.Build.Step, n: std.Progress.Node) anyerror!void {
                _ = s;
                _ = n;
                code();
            }
        }.code_runner,
    });
    return step;
}

fn compile_and_link_imgui(exe: *std.Build.Step.Compile) void {
    exe.linkLibCpp();
    exe.addCSourceFile(.{ .file = .{ .cwd_relative = "dep/cimgui/imgui/imgui.cpp" }, .flags = &[_][]const u8{""} });
    exe.addCSourceFile(.{ .file = .{ .cwd_relative = "dep/cimgui/imgui/imgui_draw.cpp" }, .flags = &[_][]const u8{""} });
    exe.addCSourceFile(.{ .file = .{ .cwd_relative = "dep/cimgui/imgui/imgui_demo.cpp" }, .flags = &[_][]const u8{""} });
    exe.addCSourceFile(.{ .file = .{ .cwd_relative = "dep/cimgui/imgui/imgui_tables.cpp" }, .flags = &[_][]const u8{""} });
    exe.addCSourceFile(.{ .file = .{ .cwd_relative = "dep/cimgui/imgui/imgui_widgets.cpp" }, .flags = &[_][]const u8{""} });
    exe.addCSourceFile(.{ .file = .{ .cwd_relative = "dep/cimgui/cimgui.cpp" }, .flags = &[_][]const u8{""} });
    exe.addIncludePath(.{ .cwd_relative = "dep/cimgui" });
}
