const std = @import("std");

pub const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", {});
    @cInclude("cimgui.h");
});

/// This is a zigified wrapper for the ImVectors used around the imgui API
pub fn ImVector(comptime T: type) type {
    // Original ImVectors look like this
    // 
    //     pub const struct_ImVector_ImDrawIdx = extern struct {
    //         Size: c_int,
    //         Capacity: c_int,
    //         Data: [*c]ImDrawIdx,
    //     };
    // 
    return struct {
        const Self = @This();
        
        used: usize,
        data: []T,
        
        pub fn used_slice(self: Self) []T {
            return self.data[0..self.used];
        }

        pub fn from(im_vector: anytype) Self {
            const size: usize = @intCast(@field(im_vector, "Size"));
            const capacity: usize = @intCast(@field(im_vector, "Capacity"));
            const data = @field(im_vector, "Data");
            const slice: []T = @ptrCast(data[0..capacity]);
            return Self {
                .used = size,
                .data = slice
            };
        }
    };
}

fn im_vector_guess_type(comptime im_vector_type: type) type {
    const info: std.builtin.Type = @typeInfo(im_vector_type);
    for (info.Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, "Data")) {
            const data_type: std.builtin.Type = @typeInfo(field.type);
            return data_type.Pointer.child;
        }
    }
    @panic("Provided type isn't an ImVector");
}

pub fn im_vector_from(im_vector: anytype) ImVector(im_vector_guess_type(@TypeOf(im_vector))) {
    return ImVector(im_vector_guess_type(@TypeOf(im_vector))).from(im_vector);
}