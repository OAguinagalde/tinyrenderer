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

// https://lemire.me/blog/2019/03/19/the-fastest-conventional-random-number-generator-that-can-pass-big-crush
// I think I didn't break it when porting it to zig... hopefully?
pub const Wyhash64 = struct {
    state: u64,
    pub fn next(self: *Wyhash64) u64 {
        self.state, _ = @addWithOverflow(self.state, @as(u64, 0x60bee2bee120fc15));
        var tmp: u128 = self.state;
        tmp *= @as(u128, 0xa3b195354a39b70d);
        const m1: u64 = @truncate((tmp >> 64) ^ tmp);
        var tmp2: u128 = m1;
        tmp2 *= @as(u128, 0x1b03738712fad5c9);
        const m2: u64 = @truncate((tmp2 >> 64) ^ tmp2);
        return m2;
    }
};

/// http://www.cse.yorku.ca/~oz/hash.html
pub fn djb2(str: []const u8) u64 {
    var hash: u64 = 5381;
    for (str) |c| {
        hash = @addWithOverflow(@addWithOverflow(hash << 5, hash)[0], c)[0];
    }
    return hash;
}

pub const Random = struct {
    implementation: Wyhash64,
    
    pub fn init(s: u64) Random {
        return Random {
            .implementation = Wyhash64 {
                .state = s
            },
        };
    }

    pub fn seed(self: *Random, s: u64) void {
        self.implementation.state = s;
    }

    pub inline fn u(self: *Random) u64 {
        return self.implementation.next();
    }
    
    pub inline fn f(self: *Random) f64 {
        const max: f64 = comptime @floatFromInt(std.math.maxInt(u64));
        return @as(f64, @floatFromInt(self.u())) / max;
    }

};

pub fn SparseSet(comptime T: type, comptime capacity: usize) type {
    return struct {
        
        const Self = @This();
        
        next: usize,
        dense: [capacity]struct { sparse_index: usize, value: T },
        sparse: [capacity]usize,
        
        pub fn is_set(self: *const Self, index: usize) bool {
            return self.sparse[index] < self.next and self.dense[self.sparse[index]].sparse_index == index;
        }

        pub fn get(self: *const Self, index: usize) *T {
            std.debug.assert(self.is_set(index));
            return &self.dense[self.sparse[index]].value;
        }

        pub fn set(self: *Self, index: usize, v: T) void {
            std.debug.assert(!self.is_set(index));
            self.dense[self.next].sparse_index = index;
            self.dense[self.next].value = v;
            self.sparse[index] = self.next;
            self.next += 1;
        }

        pub fn remove(self: *Self, index: usize) void {
            std.debug.assert(self.is_set(index));
            self.dense[self.sparse[index]].sparse_index = self.dense[self.next - 1].sparse_index;
            self.dense[self.sparse[index]].value = self.dense[self.next - 1].value;
            self.sparse[self.dense[self.next - 1].sparse_index] = self.sparse[index];
            self.sparse[index] = self.next;
            self.next -= 1;
        }

        pub fn clear(self: *Self) void {
            self.next = 0;
        }

    };
}

