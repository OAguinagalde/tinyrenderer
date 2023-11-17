const std = @import("std");

// functions provided by the wasm module caller (in js, the `env` object passed to `instantiateStreaming`)
const external = struct {
    pub extern fn consoleLog(arg: u32) void;
};

/// This buffer is used as a communications buffer between js and wasm
var wasm_interface_buffer: [256]u8 = undefined;
pub export fn wasm_get_interface_buffer() [*]u8 {
    return @ptrCast(&wasm_interface_buffer);
}

/// NOTE the pointer provided is basically an offset in the wasm module memory
/// provided byt the wasm runtime
pub export fn wasm_get_pixel_buffer_ptr() [*]u8 {
    return @ptrCast(&pixel_buffer);
}

pub export fn wasm_get_canvas_size(out_w: *u32, out_h: *u32) void {
    out_w.* = w;
    out_h.* = h;
}

pub export fn wasm_tick() void {
    update();
}

const w: u32 = 10;
const h: u32 = 10;
var pixel_buffer: [w*h*4]u8 = undefined;
var t: u32 = 0;

fn update() void {
    external.consoleLog(61);
    
    // do any modifications to the pixel buffer
    for (&pixel_buffer, 0..) |*byte, i| {
        if (@mod(i, 4) == 3) byte.* = 255; // make the alpha channel of every pixel 255
        if (@mod(i, 4) == 0) byte.* = @intCast(@mod(t+255/3*1, 255)); // red channel
        if (@mod(i, 4) == 1) byte.* = @intCast(@mod(t+255/3*2, 255)); // green channel
        if (@mod(i, 4) == 2) byte.* = @intCast(@mod(t+255/3*3, 255)); // blue channel
    }
    
    t += 1;
}
