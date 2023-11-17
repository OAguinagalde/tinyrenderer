const std = @import("std");

// functions provided by the wasm module caller (in js, the `env` object passed to `instantiateStreaming`)
const external = struct {
    pub extern fn console_log(str: [*]const u8, len: usize) void;
    pub extern fn milli_since_epoch() usize;

    const util = struct {
        pub fn log(str: []const u8) void { console_log(str.ptr, str.len); }
    };
};

/// This buffer is used as a communications buffer between js and wasm
var wasm_interface_buffer: [256]u8 = undefined;
pub export fn wasm_get_interface_buffer() [*]u8 {
    return @ptrCast(&wasm_interface_buffer);
}

/// NOTE the pointer provided is basically an offset in the wasm module memory
/// provided byt the wasm runtime
pub export fn wasm_get_pixel_buffer_ptr() [*]u8 {
    return @ptrCast(&state.pixel_buffer.data);
}

pub export fn wasm_get_canvas_size(out_w: *u32, out_h: *u32) void {
    out_w.* = state.pixel_buffer.width;
    out_h.* = state.pixel_buffer.height;
}

pub export fn wasm_init() void {
    init();
}
pub export fn wasm_tick() void {
    update();
}

pub const Platform = struct {
    /// memory_info is a compile time generated file that has information on how the module
    /// was generated, such as stack size, max memory, etc...
    const memory_info = @import("comptime_memory_info");
    
    memory: std.heap.FixedBufferAllocator,
    random: std.rand.Random,
    random_internal_implementation: std.rand.Xoshiro256,
    
    pub fn init(random_seed: u64) Platform {
        var aux = std.rand.DefaultPrng.init(random_seed);
        return Platform {
            .memory = std.heap.FixedBufferAllocator.init(module_memory()),
            .random = aux.random(),
            .random_internal_implementation = aux,
        };
    }

    fn module_memory() []u8 {
        if (memory_info.initial_memory.? != memory_info.max_memory.?) @panic("memory_info.initial_memory != memory_info.max_memory");
        // > __heap_base is where the statically allocated memory ends,and __heap_end is the value of the initial memory
        // > (either passed by --initial-memory or __heap_base), aligned to page size.
        // > `heap_base` is a special symbol provided by the linker during linking phase.
        // - Luuk
        const heap_base = @extern(?[*]u8, .{.name = "__heap_base"}).?;
        const heap_base_int = @intFromPtr(heap_base);
        // TODO This might not be necessary since the heap_base might be aligned by default?
        const heap_base_int_aligned_16 = std.mem.alignForward(usize, heap_base_int, 16);
        const size_of_total_free_memory = memory_info.max_memory.? - heap_base_int_aligned_16;
        const memory = @as([*]u8, @ptrFromInt(heap_base_int_aligned_16))[0..size_of_total_free_memory];
        // const size_of_static_data_section = heap_base_int - memory_info.global_base;
        // const padding = heap_base_int_aligned_16 - heap_base_int;
        return memory;
    }
};

// APP

const math = @import("math.zig");
const Vector2i = math.Vector2i;
const Vector2f = math.Vector2f;
const Vector3f = math.Vector3f;
const Vector4f = math.Vector4f;
const M44 = math.M44;
const Plane = math.Plane;
const Frustum = math.Frustum;
const Buffer2D = @import("buffer.zig").Buffer2D;

const Camera = struct {
    position: Vector3f,
    direction: Vector3f,
    looking_at: Vector3f,
    up: Vector3f,
};

pub const RGBA = extern struct {
    r: u8 align(1),
    g: u8 align(1),
    b: u8 align(1),
    a: u8 align(1),
    comptime { std.debug.assert(@sizeOf(@This()) == 4); }
    pub fn scale(self: RGBA, factor: f32) RGBA {
        return RGBA {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
            .a = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.a)) * factor))),
        };
    }
    pub fn add(c1: RGBA, c2: RGBA) RGBA {
        const result = RGBA {
            .r = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.r))/255 + @as(f32, @floatFromInt(c2.r))/255)*255))),
            .g = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.g))/255 + @as(f32, @floatFromInt(c2.g))/255)*255))),
            .b = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.b))/255 + @as(f32, @floatFromInt(c2.b))/255)*255))),
            .a = @intFromFloat(@max(0, @min(255, (@as(f32, @floatFromInt(c1.a))/255 + @as(f32, @floatFromInt(c2.a))/255)*255))),
        };
        return result;
    }
    pub fn scale_raw(self: RGBA, factor: f32) RGBA {
        return RGBA {
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * factor),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * factor),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * factor),
            .a = @intFromFloat(@as(f32, @floatFromInt(self.a)) * factor),
        };
    }
    /// This assumes that the sum of any channel is inside the range of u8, there is no checks!
    pub fn add_raw(c1: RGBA, c2: RGBA) RGBA {
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
    pub fn blend(c1: RGBA, c2: RGBA) RGBA {
        const a1: f32 = @as(f32, @floatFromInt(c1.a)) / 255;
        const result = RGBA {
            .r = @intFromFloat((@as(f32, @floatFromInt(c1.r))/255*a1 + @as(f32, @floatFromInt(c2.r))/255*(1-a1))*255),
            .g = @intFromFloat((@as(f32, @floatFromInt(c1.g))/255*a1 + @as(f32, @floatFromInt(c2.g))/255*(1-a1))*255),
            .b = @intFromFloat((@as(f32, @floatFromInt(c1.b))/255*a1 + @as(f32, @floatFromInt(c2.b))/255*(1-a1))*255),
            .a = @intFromFloat((@as(f32, @floatFromInt(c1.a))/255*a1 + @as(f32, @floatFromInt(c2.a))/255*(1-a1))*255),
        };
        return result;
    }
    pub fn multiply(c1: RGBA, c2: RGBA) RGBA {
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
};

pub const RGB = extern struct {
    r: u8 align(1),
    g: u8 align(1),
    b: u8 align(1),
    comptime { std.debug.assert(@sizeOf(@This()) == 3); }
    pub fn scale(self: RGB, factor: f32) RGB {
        return RGB {
            .r = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.r)) * factor))),
            .g = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.g)) * factor))),
            .b = @intFromFloat(@max(0, @min(255, @as(f32, @floatFromInt(self.b)) * factor))),
        };
    }
    pub fn scale_raw(self: RGB, factor: f32) RGB {
        return RGB {
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * factor),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * factor),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * factor),
        };
    }
    /// This assumes that the sum of any channel is inside the range of u8, there is no checks!
    pub fn add_raw(c1: RGB, c2: RGB) RGB {
        const result = RGB {
            .r = c1.r + c2.r,
            .g = c1.g + c2.g,
            .b = c1.b + c2.b,
        };
        return result;
    }
};

const State = struct {
    pixel_buffer: Buffer2D(RGBA),
    running: bool,
    mouse: Vector2i,
    keys: [256]bool,
    depth_buffer: Buffer2D(f32),
    texture: Buffer2D(RGB),
    vertex_buffer: []f32,
    camera: Camera,
    view_matrix: M44,
    viewport_matrix: M44,
    projection_matrix: M44,
    frame_index: u64,
    time: f64,
};

var wasm: Platform = undefined;
var state: State = undefined;

comptime {
    std.debug.assert(@sizeOf(RGBA) == 4);
    std.debug.assert(@sizeOf(RGB) == 3);
}

fn init() void {
    wasm = Platform.init(external.milli_since_epoch());
    external.util.log("Initialized");
    const w: usize = 200;
    const h: usize = 180;
    state = .{
        .pixel_buffer = Buffer2D(RGBA).from(wasm.memory.allocator().alloc(RGBA, w*h) catch @panic("OOM"), w),
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
        .frame_index = 0,
        .time = 0,
    };
}

fn update() void {
    // do any modifications to the pixel buffer
    for (state.pixel_buffer.data) |*rgba| {
        rgba.* = RGBA {
            .r = if (false) 255 else @intCast(@mod(state.frame_index+255/3*1, 255)),
            .g = if (false) 255   else @intCast(@mod(state.frame_index+255/3*2, 255)),
            .b = if (false) 255   else @intCast(@mod(state.frame_index+255/3*3, 255)),
            .a = 255,
        };
    }

    state.frame_index += 1;
}
