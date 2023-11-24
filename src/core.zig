const std = @import("std");

/// given a pointer to a value, returns a const byte slice of the underlying bytes
pub fn byte_slice(v_ptr: anytype) []const u8 {
    return @as([]const u8, @as([*]const u8, @ptrCast(v_ptr))[0..@sizeOf(@typeInfo(@TypeOf(v_ptr)).Pointer.child)]);
}

/// from byte slice to value
pub fn value(out_ptr: anytype, bytes: []const u8) void {
    const bs: []u8 = @as([*]u8, @ptrCast(out_ptr))[0..@sizeOf(@typeInfo(@TypeOf(out_ptr)).Pointer.child)];
    @memcpy(bs, bytes);
}

