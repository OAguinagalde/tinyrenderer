const std = @import("std");

// functions provided by the wasm module caller (in js, the `env` object passed to `instantiateStreaming`)
pub extern fn console_log(str: [*]const u8, len: usize) void;
pub extern fn milli_since_epoch() usize;
pub extern fn fetch(str: [*]const u8, len: usize) void;

pub fn flog(comptime fmt: []const u8, args: anytype) void {
    var buffer: [1024*2]u8 = undefined;
    var str = std.fmt.bufPrint(&buffer, fmt, args) catch "flog failed"[0..];
    console_log(str.ptr, str.len);
}

const WasmLoggingAllocator = struct {

    child_allocator: std.mem.Allocator,

    pub fn init(child_allocator: std.mem.Allocator) WasmLoggingAllocator {
        return .{
            .child_allocator = child_allocator,
        };
    }

    pub fn allocator(self: *WasmLoggingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        var self = ptrCast(WasmLoggingAllocator, ctx);
        // const res = self.child_allocator.alloc(ctx, len, ptr_align, ret_addr);
        const res = self.child_allocator.rawAlloc(len, ptr_align, ret_addr);
        flog("Allocator alloc {} at {any}", .{len, res});
        return res;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        var self = ptrCast(WasmLoggingAllocator, ctx);
        const res = self.child_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        flog("Allocator resize from {} at {any} to {} -> {}", .{buf.len, buf.ptr, new_len, res});
        return res;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        var self = ptrCast(WasmLoggingAllocator, ctx);
        flog("Allocator free {} bytes at {any}", .{buf.len, buf.ptr});
        self.child_allocator.rawFree(buf, buf_align, ret_addr);
    }

    fn ptrCast(comptime T: type, ptr: *anyopaque) *T {
        if (@alignOf(T) == 0) @compileError(@typeName(T));
        return @ptrCast(@alignCast(ptr));
    }

};

pub const Runtime = struct {

    fba: std.heap.FixedBufferAllocator,
    wla: WasmLoggingAllocator,
    allocator: std.mem.Allocator,
    random: std.rand.Random,
    random_internal_implementation: std.rand.Xoshiro256,
    
    __memory_base: [*]u8,
    __table_base: [*]u8,
    __stack_pointer: [*]u8,
    __data_end: [*]u8,
    __heap_base: [*]u8,
    __heap_end: [*]u8,


    pub fn init(out_runtime: *Runtime, random_seed: u64) void {

        out_runtime.random_internal_implementation = std.rand.DefaultPrng.init(random_seed);
        out_runtime.random = out_runtime.random_internal_implementation.random();

        // https://github.com/WebAssembly/tool-conventions/blob/main/DynamicLinking.md
        out_runtime.__memory_base = @extern(?[*]u8, .{.name = "__memory_base"}).?; flog("__memory_base {any} {}", .{out_runtime.__memory_base, @as(usize, @intFromPtr(out_runtime.__memory_base))});
        out_runtime.__table_base = @extern(?[*]u8, .{.name = "__table_base"}).?; flog("__table_base {any} {}", .{out_runtime.__table_base, @as(usize, @intFromPtr(out_runtime.__table_base))});
        out_runtime.__stack_pointer = @extern(?[*]u8, .{.name = "__stack_pointer"}).?; flog("__stack_pointer {any} {}", .{out_runtime.__stack_pointer, @as(usize, @intFromPtr(out_runtime.__stack_pointer))});
        out_runtime.__data_end = @extern(?[*]u8, .{.name = "__data_end"}).?; flog("__data_end {any} {}", .{out_runtime.__data_end, @as(usize, @intFromPtr(out_runtime.__data_end))});
        out_runtime.__heap_base = @extern(?[*]u8, .{.name = "__heap_base"}).?; flog("__heap_base {any} {}", .{out_runtime.__heap_base, @as(usize, @intFromPtr(out_runtime.__heap_base))});
        out_runtime.__heap_end = @extern(?[*]u8, .{.name = "__heap_end"}).?; flog("__heap_end {any} {}", .{out_runtime.__heap_end, @as(usize, @intFromPtr(out_runtime.__heap_end))});
        
        var zero: [*]allowzero u8 = @ptrFromInt(0);
        var heap: []u8 = @ptrCast(zero[@intFromPtr(out_runtime.__heap_base)..@intFromPtr(out_runtime.__heap_end)]);
        flog("heap length {}", .{heap.len});
        out_runtime.fba = std.heap.FixedBufferAllocator.init(heap);
        out_runtime.wla = WasmLoggingAllocator { .child_allocator = out_runtime.fba.allocator() };
        out_runtime.allocator = out_runtime.wla.allocator();
    }

};

pub export fn wasm_get_static_buffer() [*]u8 {
    const buffer = callbacks.get_static_buffer();
    return @ptrCast(buffer.ptr);
}

pub export fn wasm_get_canvas_pixels() [*]u8 {
    return @ptrCast(callbacks.get_canvas_pixels());
}

pub export fn wasm_get_canvas_size(out_w: *u32, out_h: *u32) void {
    const wh = callbacks.get_canvas_size();
    out_w.* = wh.w;
    out_h.* = wh.h;
}

pub export fn wasm_send_event(len: usize, a: usize, b: usize) void {
    const event: []const u8 = callbacks.get_static_buffer()[0..len];
    callbacks.send_event(event, a, b);
}

pub export fn wasm_request_buffer(len: usize) [*]u8 {
    const buffer = callbacks.request_buffer(len);
    return @ptrCast(buffer.ptr);
}

pub export fn wasm_init() void {
    callbacks.init();
}
pub export fn wasm_tick() void {
    callbacks.tick();
}

/// These are the callbacks that javascript will use to interact with the wasm module.
/// As such, the application code should implement this inside a `const callbacks = struct { ... }` struct
/// and the exported functions in this file will automatically call them like this: `@import("root").callbacks.get_static_buffer;`
///
/// This line is necessary in the root zig file, so that the exported functions located in this file are referenced and zig actually compiles it
/// 
///     comptime { _ = @import("wasm.zig"); }
/// 
pub const Callbacks = struct {
    /// Should return a static buffer which the runtime should be
    /// able to access at any time for its own purposes
    get_static_buffer: fn () []u8,
    /// Should return a pointer to the actual pixel buffer to be rendered
    get_canvas_pixels: fn () *void,
    /// Should return the width and height of the pixel buffer to be rendered
    get_canvas_size: fn () Dimensions,
    /// Should handle events sent by the runtime
    send_event: fn (event: []const u8, a: usize, b: usize) void,
    /// Should return a buffer big enough, used when fetching files from the module
    request_buffer: fn (len: usize) []u8,
    /// Should initialize the status of the application
    init: fn () void,
    /// Should update the state of the application and make sure that `get_canvas_pixels`
    /// and `get_canvas_size` are properly set
    tick: fn () void,
    
    pub const Dimensions = struct { w: usize, h: usize };
};

const callbacks: Callbacks = blk: {
    var cbs: Callbacks = undefined;
    cbs.get_static_buffer = @import("root").callbacks.get_static_buffer;
    cbs.get_canvas_pixels = @import("root").callbacks.get_canvas_pixels;
    cbs.get_canvas_size = @import("root").callbacks.get_canvas_size;
    cbs.send_event = @import("root").callbacks.send_event;
    cbs.request_buffer = @import("root").callbacks.request_buffer;
    cbs.init = @import("root").callbacks.init;
    cbs.tick = @import("root").callbacks.tick;
    break :blk cbs;
};
