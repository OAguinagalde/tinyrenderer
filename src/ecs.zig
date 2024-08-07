const std = @import("std");

pub const Entity = struct {
    id: u32,
    version: u32,
};

pub const EntityData = struct {
    components: std.bit_set.IntegerBitSet(32),
    version: u32
};

pub fn Ecs(comptime types: anytype) type {
    return struct {
    
        comptime {
            // Check that `types` is indeed a tuple...
            const tuple_info = @typeInfo(@TypeOf(types));
            if (tuple_info != .Struct or tuple_info.Struct.is_tuple == false) {
                @compileError("expected tuple, found " ++ @typeName(@TypeOf(types)));
            }
            
            // And that it is made out of `type`s only.
            const tuple: std.builtin.Type.Struct = tuple_info.Struct;
            for (tuple.fields) |field| {
                const ith_value = @field(types, field.name);
                if (@TypeOf(ith_value) != type) @compileError("expected `type`s only, found  " ++ @typeName(@TypeOf(ith_value)));
            }

        }
        
        const Self = @This();
        
        fn getComponentContainer(comptime T: type) *std.ArrayList(T) {
            inline for (@typeInfo(@TypeOf(types)).Struct.fields) |field| {
                const t = @field(types, field.name);
                if (T == t) {
                    const magic = struct {
                        const types_reference = types;
                        var storage: std.ArrayList(T) = undefined;
                    };
                    return &magic.storage;
                }
            } else @panic("The type " ++ @typeName(T) ++ " is not present in the tuple `types` provided");
        }

        pub fn getComponentId(comptime T: type) usize {
            inline for (@typeInfo(@TypeOf(types)).Struct.fields, 0..) |field, i| {
                const t = @field(types, field.name);
                if (T == t) return i;
            } else @panic("The type " ++ @typeName(T) ++ " is not present in the tuple `types` provided");
        }

        entities: std.ArrayList(EntityData),
        deletedEntities: std.ArrayList(u32),
        allocator: std.mem.Allocator,
        capacity: usize,

        const set_without_components = std.bit_set.IntegerBitSet(32).initEmpty();

        /// pre-allocates enough memory for #capacity entities
        pub fn init_capacity(allocator: std.mem.Allocator, capacity: usize) !Self {
            std.debug.assert(capacity <= std.math.maxInt(u32));
            const self = Self {
                .entities = try std.ArrayList(EntityData).initCapacity(allocator, capacity),
                .deletedEntities = try std.ArrayList(u32).initCapacity(allocator, capacity),
                .allocator = allocator,
                .capacity = capacity,
            };
            inline for (@typeInfo(@TypeOf(types)).Struct.fields) |field| {
                const t = @field(types, field.name);
                const container = getComponentContainer(t);
                container.* = try std.ArrayList(t).initCapacity(allocator, capacity);
                _ = container.addManyAsSliceAssumeCapacity(capacity);
            }
            return self;
        }
                
        pub fn newEntity(self: *Self) !Entity {
            if (self.deletedEntities.items.len > 0) {
                // reuse deleted entities whenever possible
                const index_to_be_reused = self.deletedEntities.pop();
                const entity = self.entities.items[index_to_be_reused];
                return Entity {
                    .id = index_to_be_reused,
                    .version = entity.version
                };
            }
            const next_entity_id = self.entities.items.len;
            if (next_entity_id >= self.capacity) return error.MaxEntitiesReached;
            const new_entity_data = EntityData {
                .components = set_without_components,
                .version = 0
            };
            const new_entity_index = Entity {
                .id = @intCast(next_entity_id),
                .version = 0
            };
            self.entities.appendAssumeCapacity(new_entity_data);
            return new_entity_index;
        }

        pub fn new_entity(self: *Self) Entity {
            if (self.deletedEntities.items.len > 0) {
                // reuse deleted entities whenever possible
                const index_to_be_reused = self.deletedEntities.pop();
                const entity = self.entities.items[index_to_be_reused];
                return Entity {
                    .id = index_to_be_reused,
                    .version = entity.version
                };
            }
            const next_entity_id = self.entities.items.len;
            std.debug.assert(next_entity_id < self.capacity); // MaxEntitiesReached
            const new_entity_data = EntityData {
                .components = set_without_components,
                .version = 0
            };
            const new_entity_index = Entity {
                .id = @intCast(next_entity_id),
                .version = 0
            };
            self.entities.appendAssumeCapacity(new_entity_data);
            return new_entity_index;
        }
        
        pub fn require_component(self: Self, comptime T: type, entity: Entity) *T {
            var entity_data: EntityData = self.entities.items[entity.id];
            std.debug.assert(entity_data.version == entity.version);
            std.debug.assert(entity_data.components.isSet(getComponentId(T)));
            return &getComponentContainer(T).items[entity.id];
        }

        pub fn try_component(self: Self, comptime T: type, entity: Entity) ?*T {
            var entity_data: EntityData = self.entities.items[entity.id];
            std.debug.assert(entity_data.version == entity.version);
            if (entity_data.components.isSet(getComponentId(T))) return &getComponentContainer(T).items[entity.id];
            return null;
        }

        pub fn set_component(self: *Self, comptime T: type, entity: Entity) *T {
            const entity_data = &self.entities.items[entity.id];
            std.debug.assert(entity_data.*.version == entity.version); // RemovedEntity
            const component_id = getComponentId(T);
            entity_data.*.components.set(component_id);
            const component_container = getComponentContainer(T);
            return &component_container.*.items[entity.id];
        }

        pub fn remove_component(self: *Self, comptime T: type, entity: Entity) void {
            const entity_data: *EntityData = &self.entities.items[entity.id];
            std.debug.assert(entity_data.*.version == entity.version); // RemovedEntity
            const component_id = getComponentId(T);
            entity_data.*.components.unset(component_id);
        }
        
        pub fn getComponent(self: Self, comptime T: type, entity: Entity) !?*T {
            var entity_data: EntityData = self.entities.items[entity.id];
            if (entity_data.version != entity.version) return error.RemovedEntity;
            const component_id = getComponentId(T);
            if (entity_data.components.isSet(component_id)) {
                const component_container = getComponentContainer(T);
                return &component_container.*.items[entity.id];
            }
            return null;
        }

        pub fn setComponent(self: *Self, comptime T: type, entity: Entity) !*T {
            const entity_data = &self.entities.items[entity.id];
            if (entity_data.*.version != entity.version) return error.RemovedEntity;
            const component_id = getComponentId(T);
            entity_data.*.components.set(component_id);
            const component_container = getComponentContainer(T);
            return &component_container.*.items[entity.id];
        }

        pub fn removeComponent(self: *Self, comptime T: type, entity: Entity) !void {
            const entity_data: *EntityData = &self.entities.items[entity.id];
            if (entity_data.*.version != entity.version) return error.RemovedEntity;
            const component_id = getComponentId(T);
            entity_data.*.components.unset(component_id);
        }

        pub fn valid_entity(self: *Self, entity: Entity) bool {
            const entity_data = &self.entities.items[entity.id];
            return entity_data.*.version == entity.version;
        }

        pub fn deleteEntity(self: *Self, entity: Entity) !void {
            const entity_data = &self.entities.items[entity.id];
            if (entity_data.*.version != entity.version) return error.RemovedEntity;
            entity_data.*.version += 1;
            entity_data.*.components = set_without_components;
            self.deletedEntities.appendAssumeCapacity(entity.id);
        }

        pub fn delete(self: *Self, entity: Entity) void {
            const entity_data = &self.entities.items[entity.id];
            std.debug.assert(entity_data.version == entity.version);
            entity_data.*.version += 1;
            entity_data.*.components = set_without_components;
            self.deletedEntities.appendAssumeCapacity(entity.id);
        }
        
        pub fn deleteAll(self: *Self) void {
            for (self.entities.items, 0..) |*entity_data, i| {
                if (entity_data.components.mask != 0) {
                    entity_data.*.version += 1;
                    entity_data.*.components = set_without_components;
                    self.deletedEntities.appendAssumeCapacity(@intCast(i));
                }
            }
        }

        /// `view_types` is a tuple of `type`s. exameple: `.{u32, i32, bool}`
        pub fn view(comptime view_types: anytype) type {
            return struct {
                
                /// The bit field used as a mask to filter the entities that match this component view
                pub const mask: std.bit_set.IntegerBitSet(32) = blk: {
                    
                    // Check that `view_types` is indeed a tuple of types
                    const type_of_tuple = @TypeOf(view_types);
                    const tuple_info = @typeInfo(type_of_tuple);
                    if (tuple_info != .Struct or tuple_info.Struct.is_tuple == false) {
                        @compileError("expected tuple, found " ++ @typeName(type_of_tuple));
                    }
                    
                    const tuple: std.builtin.Type.Struct = tuple_info.Struct;
                    var bit_field = set_without_components;
                    for (tuple.fields) |field| {
                        const ith_type = @field(view_types, field.name);
                        const component_id = getComponentId(ith_type);
                        bit_field.set(component_id);
                    }
                    break :blk bit_field;
                };

                pub const Iterator = struct {
                    
                    index: usize,

                    // TODO allow the API to take a user provided function with direct acces to the components?
                    pub fn next(it: *Iterator, ecs: *const Self) ?Entity {
                        
                        if (it.index >= ecs.entities.items.len) return null;
                        
                        outer: for (ecs.entities.items[it.index..], it.index..) |entity, i| {
                            it.*.index = i+1;
                            const difference = mask.differenceWith(entity.components);
                            
                            // if (mask.eql(entity.components) == false) continue :outer;
                            if (difference.intersectWith(mask).mask != 0) continue :outer;
                            return .{ .id = @intCast(i), .version = entity.version };
                        }
                        return null;
                    }

                };

                pub fn iterator() Iterator {
                    return Iterator {
                        .index = 0
                    };
                }
            };
        }

        /// `view_types` is a tuple of `type`s. exameple: `.{u32, i32, bool}`
        pub fn Iterator_(comptime view_types: anytype) type {
            return struct {
                
                parent_ecs: *const Self,
                index: usize,

                /// The bit field used as a mask to filter the entities that match this component view
                const mask: std.bit_set.IntegerBitSet(32) = blk: {
                    
                    // Check that `view_types` is indeed a tuple of types
                    const type_of_tuple = @TypeOf(view_types);
                    const tuple_info = @typeInfo(type_of_tuple);
                    if (tuple_info != .Struct or tuple_info.Struct.is_tuple == false) {
                        @compileError("expected tuple, found " ++ @typeName(type_of_tuple));
                    }
                    
                    const tuple: std.builtin.Type.Struct = tuple_info.Struct;
                    var bit_field = set_without_components;
                    for (tuple.fields) |field| {
                        const ith_type = @field(view_types, field.name);
                        const component_id = getComponentId(ith_type);
                        bit_field.set(component_id);
                    }
                    break :blk bit_field;
                };

                pub fn next(self: *@This()) ?Entity {
                    
                    if (self.index >= self.parent_ecs.entities.items.len) return null;
                    
                    for (self.parent_ecs.entities.items[self.index..], self.index..) |entity, i| {
                        self.index = i+1;
                        const difference = mask.differenceWith(entity.components);
                        
                        if (difference.intersectWith(mask).mask != 0) continue;

                        return .{ .id = @intCast(i), .version = entity.version };
                    }
                    return null;
                }

            };
        }

        /// `view_types` is a tuple of `type`s. exameple: `.{u32, i32, bool}`
        pub fn iterator(self: *const Self, comptime view_types: anytype) Iterator_(view_types) {
            return .{
                .index = 0,
                .parent_ecs = self,
            };
        }

        pub fn entityStats(self: *Self, entity: Entity) void {
            var entity_data: EntityData = self.entities.items[entity.id];
            if (entity_data.version != entity.version) {
                std.debug.print("Entity {} on version {} is out of date\n", .{entity.id, entity.version});
                return;
            }
            std.debug.print("Entity {} on version {}\n", .{entity.id, entity.version});
            inline for (@typeInfo(@TypeOf(types)).Struct.fields) |field| {
                const t = @field(types, field.name);
                const component_id = getComponentId(t);
                if (entity_data.components.isSet(component_id)) {
                    const component_container = getComponentContainer(t);
                    const component = &component_container.*.items[entity.id];
                    std.debug.print("- Component {s} set to {?}\n", .{@typeName(t), component.*});
                }
                else std.debug.print("- Component {s} set to -\n", .{@typeName(t)});
            }
        }
        
        pub fn debugPrintStats(self: *Self) void {
            std.debug.print("Entities {} out of {} (MAX_ENTITIES {})\n", .{self.entities.items.len, self.entities.capacity, self.capacity});
            std.debug.print("Size of Entity {}, total space allocated {} bytes ({} kb)\n", .{@sizeOf(EntityData), self.entities.capacity * @sizeOf(EntityData), self.entities.capacity * @sizeOf(EntityData) / 1024});
            inline for (@typeInfo(@TypeOf(types)).Struct.fields) |field| {
                const t = @field(types, field.name);
                const container = getComponentContainer(t);
                std.debug.print("container for {s} has {} / {} | total space allocated {} bytes ({} kb)\n", .{ @typeName(t), container.*.items.len, container.*.capacity, @sizeOf(t) * self.capacity, @sizeOf(t) * self.capacity / 1024});
            }
        }

        pub const Stats = struct {
            entities: usize,
            capacity: usize,
            max: usize,
            entity_size: usize,
            allocated_bytes_kb: usize,
            container_stats: [@typeInfo(@TypeOf(types)).Struct.fields.len] ContainerStats,
        };

        pub const ContainerStats = struct {
            // name: *const [:0]u8,
            count: usize,
            allocated_bytes_kb: usize
        };

        pub fn stats(self: *Self) Stats {
            
            var container_stats: [@typeInfo(@TypeOf(types)).Struct.fields.len] ContainerStats = undefined;

            inline for (@typeInfo(@TypeOf(types)).Struct.fields, 0..) |field, i| {
                const t = @field(types, field.name);
                const container = getComponentContainer(t);
                container_stats[i] = ContainerStats {
                    .count = container.items.len,
                    .allocated_bytes_kb = @sizeOf(t) * self.capacity / 1024
                };
            }

            return Stats {
                .entities = self.entities.items.len,
                .capacity = self.entities.capacity,
                .max = self.capacity,
                .entity_size = @sizeOf(EntityData),
                .allocated_bytes_kb = self.entities.capacity * @sizeOf(EntityData) / 1024,
                .container_stats = container_stats
            };
        }
    };
}

test "ecs" {
    const Color = struct { r: u8, g: u8, b: u8, a: u8 };
    const Position = struct { x: i32, y: i32 };

    var ecs = try Ecs(.{Color, Position}).init_capacity(std.heap.page_allocator, 100);

    // Creating entities
    const e1 = try ecs.newEntity();
    try std.testing.expectEqual(@as(u32, 0), e1.id);
    const e2 = try ecs.newEntity();
    try std.testing.expectEqual(@as(u32, 1), e2.id);

    // Getting non-set components
    try std.testing.expect(null == try ecs.getComponent(Color, e1));
    try std.testing.expect(null == try ecs.getComponent(Position, e1));

    // Setting components
    const pos2 = try ecs.setComponent(Position, e2);
    pos2.* = .{.x = 7, .y = 10};
    const pos2_again = try ecs.getComponent(Position, e2);
    try std.testing.expectEqual(pos2.x, pos2_again.?.x);
    try std.testing.expectEqual(pos2.y, pos2_again.?.y);

    // Deleting works fine, and deleting again fails or using a deleted one fails as well
    try ecs.deleteEntity(e2);
    try std.testing.expectError(error.RemovedEntity, ecs.deleteEntity(e2));
    try std.testing.expectError(error.RemovedEntity, ecs.getComponent(Position, e2));
    
    // Reusing removed entities
    const e3 = try ecs.newEntity();
    try std.testing.expectEqual(@as(u32, 1), e3.id);

    // Check that components for deleted e2 (now e3) got components reset
    try std.testing.expect(null == try ecs.getComponent(Position, e3));

    ecs.debugPrintStats();
}

test "view" {
    const Color = struct { r: u8, g: u8, b: u8, a: u8 };
    const Position = struct { x: i32, y: i32 };
    const ECS = Ecs(.{Color, Position});
    
    var ecs = try ECS.init_capacity(std.heap.page_allocator, 100);

    std.debug.print("Create 10 Position. Also set Color for 3 and 7\n", .{});
    for (0..10) |i| {
        const e = try ecs.newEntity();
        const pos = try ecs.setComponent(Position, e);
        pos.* = .{.x = 7, .y = 10};
        if (i == 3 or i == 7) {
            const color = try ecs.setComponent(Color, e);
            color.* = .{
                .r = 123,
                .g = 124,
                .b = 125,
                .a = 255
            };
            std.debug.print("{}: {?} {?}\n", .{i, pos, color});
        }
        else {
            std.debug.print("{}: {?}\n", .{i, pos});
        }
    }

    std.debug.print("Iterate those with Position. Change Position of 3. Delete 7\n", .{});
    var it = ECS.view(.{Position}).iterator();
    while (it.next(&ecs)) |e| {
        const pos = (try ecs.getComponent(Position, e)).?;
        if (e.id == 3) {
            pos.* = .{.x = 999, .y = 999};
        }
        const color = try ecs.getComponent(Color, e);
        if (color) |c| std.debug.print("{}: {?} {?}\n", .{e.id, pos, c})
        else std.debug.print("{}: {?}\n", .{e.id, pos});

        if (e.id == 7) try ecs.deleteEntity(e);
    }

    std.debug.print("Iterate those with Position and Color\n", .{});
    var it2 = ECS.view(.{Position, Color}).iterator();
    while (it2.next(&ecs)) |e| {
        const pos = (try ecs.getComponent(Position, e)).?;
        const color = (try ecs.getComponent(Color, e)).?;
        std.debug.print("{}: {?} {?}\n", .{e.id, pos, color});
    }
}
