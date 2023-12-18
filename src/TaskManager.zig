/// finishing a task doesnt free up any allocations done on `register`!

const std = @import("std");
const core = @import("core.zig");

const TaskManager = @This();

const CallbackType = fn(context_register: []const u8, context_finish: []const u8) void;
const Task = struct {
    callback: *const CallbackType,
    context: []const u8
};

arena: std.heap.ArenaAllocator,
/// key: the id of the task. value: the task itself, which contains a callback and a context provided to the callback on execution.
tasks: std.StringHashMap(Task),

pub fn init(allocator: std.mem.Allocator) TaskManager {
    const arena = std.heap.ArenaAllocator.init(allocator);
    const task_map = std.StringHashMap(Task).init(allocator);
    return .{
        .arena = arena,
        .tasks = task_map,
    };
}

pub fn deinit(self: *TaskManager) void {
    self.tasks.deinit();
    self.arena.deinit();
}

pub fn finished(self: TaskManager) bool {
    return self.tasks.count() == 0;
}

/// clones context and id and manages internally
pub fn register(self: *TaskManager, id: []const u8, cb: *const CallbackType, context_value: anytype) !void {
    const context_size = @sizeOf(@TypeOf(context_value));
    // allocate enough space to store the task until it gets completed and freed on `finish`
    const size = context_size+id.len;
    var task_storage = try self.arena.allocator().alloc(u8, size);
    const id_storage: []u8 = task_storage[0..id.len];
    const context_storage: []u8 = task_storage[id.len..size];
    std.debug.assert(context_size == context_storage.len);
    std.mem.copy(u8, id_storage, id);
    std.mem.copy(u8, context_storage, core.byte_slice(&context_value));        
    // the task itself just contains a pointer to the context (its memory is manually managed), and a pointer to the callback (which is static code, so no need to manage its lifetime)
    try self.tasks.put(id_storage, .{ .callback = cb, .context = context_storage });
}

pub fn finish(self: *TaskManager, id: []const u8, context_value: anytype) void {
    const task = self.tasks.get(id).?;
    task.callback(task.context, core.byte_slice(&context_value));
    _ = self.tasks.remove(id);
}