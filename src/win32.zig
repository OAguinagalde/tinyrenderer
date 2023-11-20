const std = @import("std");

/// The actual `windows.h` API
pub const c = @import("win32").everything;

pub const falsei32: i32 = 0;
pub const call_convention = std.os.windows.WINAPI;
