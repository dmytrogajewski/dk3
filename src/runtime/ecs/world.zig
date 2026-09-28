// SPDX-License-Identifier: GPL-2.0-or-later
//! Typed archetypes. Structural mutation is legal only between query epochs.
const std = @import("std");
pub const Entity = packed struct(u64) { index: u32, generation: u32 };
pub const chunk_bytes = 16 * 1024;
pub const max_entities = 2046;
pub const Error = error{ OutOfMemory, Capacity, StaleEntity, DuplicateId, MissingComponent, StructuralMutation, TooManyArchetypes, ArchetypeTooLarge };

pub fn World(comptime Components: anytype) type {
    comptime {
        @setEvalBranchQuota(10000);
        if (Components.len == 0 or Components.len > 64) @compileError("component registry must contain 1..64 types");
        for (Components, 0..) |T, i| {
            if (@sizeOf(T) == 0 or @alignOf(T) > 64) @compileError("components must have storage and alignment <= 64");
            for (0..i) |j| if (T == Components[j]) @compileError("duplicate component registration");
        }
    }
    return struct {
        const Self = @This();
        pub const Mask = u64;
        const Slot = struct { generation: u32 = 1, id: u32 = 0, archetype: u16 = 0, chunk: u32 = 0, row: u16 = 0 };
        const Chunk = struct { data: [chunk_bytes]u8 align(64) = undefined, count: u16 = 0 };
        const Layout = struct { capacity: u16, offsets: [Components.len]usize };
        const Archetype = struct { mask: Mask, layout: Layout, chunks: std.ArrayList(*Chunk) = .empty };
        allocator: std.mem.Allocator,
        slots: [max_entities]Slot = @splat(.{}),
        archetypes: std.ArrayList(Archetype) = .empty,
        ids: std.AutoHashMapUnmanaged(u32, Entity) = .empty,
        next_id: u32 = 1,
        id_first: u32 = 1,
        id_last: u32 = std.math.maxInt(u32) - 1,
        query_depth: usize = 0,
        epoch: u64 = 0,
        chunk_count: usize = 0,
        max_chunks: usize,

        pub fn init(allocator: std.mem.Allocator, max_chunks: usize) Self {
            return .{ .allocator = allocator, .max_chunks = max_chunks };
        }
        /// Region-local allocation never consumes another world's namespace.
        /// An imported entity retains its birth identity, including on return.
        pub fn initNamespaced(allocator: std.mem.Allocator, max_chunks: usize, namespace: u7) Self {
            const first = (@as(u32, namespace) << 24) | 1;
            return .{ .allocator = allocator, .max_chunks = max_chunks, .id_first = first, .id_last = first | 0xffffff, .next_id = first };
        }
        pub fn deinit(self: *Self) void {
            std.debug.assert(self.query_depth == 0);
            for (self.archetypes.items) |*a| {
                for (a.chunks.items) |chunk| self.allocator.destroy(chunk);
                a.chunks.deinit(self.allocator);
            }
            self.archetypes.deinit(self.allocator);
            self.ids.deinit(self.allocator);
            self.* = undefined;
        }
        pub fn componentId(comptime T: type) u6 {
            inline for (Components, 0..) |C, i| if (T == C) return @intCast(i);
            @compileError("unregistered component " ++ @typeName(T));
        }
        pub fn mask(comptime Types: anytype) Mask {
            var bits: Mask = 0;
            inline for (Types) |T| bits |= @as(Mask, 1) << componentId(T);
            return bits;
        }
        fn layout(bits: Mask) Error!Layout {
            var bytes: usize = @sizeOf(Entity);
            inline for (Components, 0..) |T, i| if (bits & (@as(Mask, 1) << i) != 0) {
                bytes += @sizeOf(T);
            };
            var capacity = chunk_bytes / bytes;
            while (capacity > 0) : (capacity -= 1) {
                var offsets: [Components.len]usize = @splat(0);
                var cursor = capacity * @sizeOf(Entity);
                inline for (Components, 0..) |T, i| {
                    if (bits & (@as(Mask, 1) << i) != 0) {
                        cursor = std.mem.alignForward(usize, cursor, @alignOf(T));
                        offsets[i] = cursor;
                        cursor += capacity * @sizeOf(T);
                    }
                }
                if (cursor <= chunk_bytes) return .{ .capacity = @intCast(capacity), .offsets = offsets };
            }
            return error.ArchetypeTooLarge;
        }
        fn archetype(self: *Self, bits: Mask) Error!u16 {
            for (self.archetypes.items, 0..) |a, i| if (a.mask == bits) return @intCast(i);
            if (self.archetypes.items.len == 1024) return error.TooManyArchetypes;
            try self.archetypes.append(self.allocator, .{ .mask = bits, .layout = try layout(bits) });
            return @intCast(self.archetypes.items.len - 1);
        }
        fn reserveRow(self: *Self, ai: u16) Error!struct { chunk: u32, row: u16 } {
            const a = &self.archetypes.items[ai];
            for (a.chunks.items, 0..) |chunk, i| if (chunk.count < a.layout.capacity) {
                const row = chunk.count;
                chunk.count += 1;
                return .{ .chunk = @intCast(i), .row = row };
            };
            if (self.chunk_count >= self.max_chunks) return error.Capacity;
            const chunk = try self.allocator.create(Chunk);
            errdefer self.allocator.destroy(chunk);
            chunk.* = .{ .count = 1 };
            try a.chunks.append(self.allocator, chunk);
            self.chunk_count += 1;
            return .{ .chunk = @intCast(a.chunks.items.len - 1), .row = 0 };
        }
        fn handles(chunk: *Chunk) [*]Entity {
            return @ptrCast(@alignCast(&chunk.data));
        }
        fn column(comptime T: type, a: *const Archetype, chunk: *Chunk) [*]T {
            return @ptrCast(@alignCast(chunk.data[a.layout.offsets[componentId(T)]..].ptr));
        }
        fn slot(self: *const Self, entity: Entity) Error!Slot {
            if (entity.index >= max_entities) return error.StaleEntity;
            const s = self.slots[entity.index];
            if (s.id == 0 or s.generation != entity.generation) return error.StaleEntity;
            return s;
        }
        pub fn alive(self: *const Self, entity: Entity) bool {
            _ = self.slot(entity) catch return false;
            return true;
        }
        pub fn find(self: *const Self, id: u32) ?Entity {
            return self.ids.get(id);
        }
        pub fn persistentId(self: *const Self, entity: Entity) Error!u32 {
            return (try self.slot(entity)).id;
        }
        pub fn count(self: *const Self) usize {
            return self.ids.count();
        }
        fn editable(self: *Self) Error!void {
            if (self.query_depth != 0) return error.StructuralMutation;
        }
        pub fn create(self: *Self, requested_id: ?u32, bundle: anytype) Error!Entity {
            const bits = comptime blk: {
                var value: Mask = 0;
                for (@typeInfo(@TypeOf(bundle)).@"struct".fields) |field| {
                    const bit = @as(Mask, 1) << componentId(field.type);
                    if (value & bit != 0) @compileError("duplicate component in bundle");
                    value |= bit;
                }
                break :blk value;
            };
            const entity = try self.reserveEntity(requested_id, bits);
            const s = self.slots[entity.index];
            const a = &self.archetypes.items[s.archetype];
            const chunk = a.chunks.items[s.chunk];
            inline for (std.meta.fields(@TypeOf(bundle))) |field| column(field.type, a, chunk)[s.row] = @field(bundle, field.name);
            return entity;
        }
        fn reserveEntity(self: *Self, requested_id: ?u32, bits: Mask) Error!Entity {
            try self.editable();
            const id = requested_id orelse self.next_id;
            if (id == 0 or id == std.math.maxInt(u32) or (requested_id == null and id > self.id_last)) return error.Capacity;
            if (self.ids.contains(id)) return error.DuplicateId;
            var index: usize = 0;
            while (index < max_entities and (self.slots[index].id != 0 or self.slots[index].generation == 0)) : (index += 1) {}
            if (index == max_entities) return error.Capacity;
            try self.ids.ensureUnusedCapacity(self.allocator, 1);
            const ai = try self.archetype(bits);
            const row = try self.reserveRow(ai);
            const entity: Entity = .{ .index = @intCast(index), .generation = self.slots[index].generation };
            const a = &self.archetypes.items[ai];
            const chunk = a.chunks.items[row.chunk];
            handles(chunk)[row.row] = entity;
            self.slots[index] = .{ .generation = entity.generation, .id = id, .archetype = ai, .chunk = row.chunk, .row = row.row };
            self.ids.putAssumeCapacity(id, entity);
            if (id >= self.id_first and id <= self.id_last) self.next_id = @max(self.next_id, id + 1);
            self.epoch += 1;
            return entity;
        }
        /// Stage a complete transfer without mutating the source. The caller
        /// commits ownership only after destination projection admission succeeds.
        pub fn cloneInto(self: *Self, entity: Entity, destination: *Self) Error!Entity {
            return self.cloneIntoAs(entity, destination, try self.persistentId(entity));
        }
        /// Legacy independent save namespaces are assigned once on admission.
        /// Ordinary transfers must retain their birth ID through cloneInto.
        pub fn cloneIntoAs(self: *Self, entity: Entity, destination: *Self, id: u32) Error!Entity {
            const source_slot = try self.slot(entity);
            const source = &self.archetypes.items[source_slot.archetype];
            const result = try destination.reserveEntity(id, source.mask);
            const target_slot = destination.slots[result.index];
            const target = &destination.archetypes.items[target_slot.archetype];
            inline for (Components, 0..) |T, i| if (source.mask & (@as(Mask, 1) << i) != 0) {
                column(T, target, target.chunks.items[target_slot.chunk])[target_slot.row] = column(T, source, source.chunks.items[source_slot.chunk])[source_slot.row];
            };
            return result;
        }
        pub fn get(self: *Self, entity: Entity, comptime T: type) Error!*T {
            const s = try self.slot(entity);
            const a = &self.archetypes.items[s.archetype];
            if (a.mask & mask(.{T}) == 0) return error.MissingComponent;
            return &column(T, a, a.chunks.items[s.chunk])[s.row];
        }
        fn removeRow(self: *Self, s: Slot) void {
            const a = &self.archetypes.items[s.archetype];
            const chunk = a.chunks.items[s.chunk];
            chunk.count -= 1;
            if (s.row == chunk.count) return;
            const moved = handles(chunk)[chunk.count];
            handles(chunk)[s.row] = moved;
            inline for (Components, 0..) |T, i| if (a.mask & (@as(Mask, 1) << i) != 0) {
                const values = column(T, a, chunk);
                values[s.row] = values[chunk.count];
            };
            self.slots[moved.index].row = s.row;
        }
        pub fn destroy(self: *Self, entity: Entity) Error!void {
            try self.editable();
            const s = try self.slot(entity);
            self.removeRow(s);
            _ = self.ids.remove(s.id);
            self.slots[entity.index] = .{ .generation = s.generation +% 1 };
            self.epoch += 1;
        }
        fn relocate(self: *Self, entity: Entity, bits: Mask) Error!void {
            try self.editable();
            const old = try self.slot(entity);
            const ai = try self.archetype(bits);
            if (ai == old.archetype) return;
            const row = try self.reserveRow(ai);
            const source = &self.archetypes.items[old.archetype];
            const dest = &self.archetypes.items[ai];
            const chunk = dest.chunks.items[row.chunk];
            handles(chunk)[row.row] = entity;
            inline for (Components, 0..) |T, i| if (bits & (@as(Mask, 1) << i) != 0) {
                column(T, dest, chunk)[row.row] = if (source.mask & (@as(Mask, 1) << i) != 0)
                    column(T, source, source.chunks.items[old.chunk])[old.row]
                else
                    undefined; // put initializes the only newly added column before returning.
            };
            self.removeRow(old);
            self.slots[entity.index].archetype = ai;
            self.slots[entity.index].chunk = row.chunk;
            self.slots[entity.index].row = row.row;
            self.epoch += 1;
        }
        pub fn put(self: *Self, entity: Entity, value: anytype) Error!void {
            try self.editable();
            const s = try self.slot(entity);
            try self.relocate(entity, self.archetypes.items[s.archetype].mask | mask(.{@TypeOf(value)}));
            (try self.get(entity, @TypeOf(value))).* = value;
        }
        pub fn remove(self: *Self, entity: Entity, comptime T: type) Error!void {
            const s = try self.slot(entity);
            try self.relocate(entity, self.archetypes.items[s.archetype].mask & ~mask(.{T}));
        }
        pub const View = struct {
            world: *Self,
            archetype: usize,
            chunk: usize,
            epoch: u64,
            readable: Mask,
            writable: Mask,
            pub fn entities(self: View) []const Entity {
                std.debug.assert(self.epoch == self.world.epoch and self.world.query_depth > 0);
                const chunk = self.world.archetypes.items[self.archetype].chunks.items[self.chunk];
                return handles(chunk)[0..chunk.count];
            }
            pub fn read(self: View, comptime T: type) []const T {
                std.debug.assert((self.readable | self.writable) & mask(.{T}) != 0);
                return self.values(T);
            }
            pub fn write(self: View, comptime T: type) []T {
                std.debug.assert(self.writable & mask(.{T}) != 0);
                return self.values(T);
            }
            fn values(self: View, comptime T: type) []T {
                std.debug.assert(self.epoch == self.world.epoch and self.world.query_depth > 0);
                const a = &self.world.archetypes.items[self.archetype];
                std.debug.assert(a.mask & mask(.{T}) != 0);
                const chunk = a.chunks.items[self.chunk];
                return column(T, a, chunk)[0..chunk.count];
            }
        };
        pub const Query = struct {
            world: *Self,
            required: Mask,
            excluded: Mask,
            writable: Mask,
            ai: usize = 0,
            ci: usize = 0,
            pub fn next(self: *Query) ?View {
                while (self.ai < self.world.archetypes.items.len) {
                    const a = &self.world.archetypes.items[self.ai];
                    if (a.mask & self.required == self.required and a.mask & self.excluded == 0) {
                        while (self.ci < a.chunks.items.len) {
                            const ci = self.ci;
                            self.ci += 1;
                            if (a.chunks.items[ci].count > 0) return .{ .world = self.world, .archetype = self.ai, .chunk = ci, .epoch = self.world.epoch, .readable = self.required, .writable = self.writable };
                        }
                    }
                    self.ai += 1;
                    self.ci = 0;
                }
                return null;
            }
            pub fn deinit(self: *Query) void {
                self.world.query_depth -= 1;
                self.* = undefined;
            }
        };
        pub fn query(self: *Self, required: Mask, excluded: Mask) Query {
            return self.queryAccess(required, excluded, required);
        }
        pub fn queryAccess(self: *Self, required: Mask, excluded: Mask, writable: Mask) Query {
            std.debug.assert(writable & ~required == 0);
            self.query_depth += 1;
            return .{ .world = self, .required = required, .excluded = excluded, .writable = writable };
        }
    };
}

const Position = struct { x: f32, y: f32, z: f32 };
const Health = struct { value: i32 };
const TestWorld = World(.{ Position, Health });
test "archetype relocation preserves identities and swap-removed rows" {
    var world = TestWorld.init(std.testing.allocator, 16);
    defer world.deinit();
    const first = try world.create(42, .{Position{ .x = 1, .y = 2, .z = 3 }});
    const second = try world.create(null, .{Position{ .x = 4, .y = 5, .z = 6 }});
    try world.put(first, Health{ .value = 93 });
    try std.testing.expectEqual(@as(f32, 4), (try world.get(second, Position)).x);
    try world.remove(first, Health);
    try std.testing.expectEqual(@as(f32, 1), (try world.get(first, Position)).x);
    try world.destroy(first);
    const reused = try world.create(null, .{Health{ .value = 100 }});
    try std.testing.expectEqual(first.index, reused.index);
    try std.testing.expect(first.generation != reused.generation);
    try std.testing.expectError(error.StaleEntity, world.get(first, Health));
    try std.testing.expect(world.find(42) == null);
}
test "query epochs block structural changes and chunks stay bounded" {
    var world = TestWorld.init(std.testing.allocator, 1);
    defer world.deinit();
    const ent = try world.create(null, .{Position{ .x = 0, .y = 0, .z = 0 }});
    var query = world.query(TestWorld.mask(.{Position}), 0);
    const view = query.next().?;
    view.write(Position)[0].x = 8;
    try std.testing.expectError(error.StructuralMutation, world.destroy(ent));
    query.deinit();
    try std.testing.expectError(error.Capacity, world.put(ent, Health{ .value = 1 }));
    try std.testing.expectEqual(@as(f32, 8), (try world.get(ent, Position)).x);
    try std.testing.expectEqual(@as(usize, 1), world.count());
}

test "structural relocation preserves tagged unions without zero initialization" {
    const Value = union(enum) { count: u32, label: []const u8 };
    const Extra = struct { number: u32 };
    var world = World(.{ Value, Extra }).init(std.testing.allocator, 4);
    defer world.deinit();
    const entity = try world.create(null, .{Value{ .label = "key" }});
    try world.put(entity, Extra{ .number = 9 });
    try std.testing.expectEqualStrings("key", (try world.get(entity, Value)).label);
    try world.remove(entity, Extra);
    try std.testing.expectEqualStrings("key", (try world.get(entity, Value)).label);
    try world.put(entity, Value{ .count = 17 });
    try std.testing.expectEqual(@as(u32, 17), (try world.get(entity, Value)).count);
}

test "resident transfers retain birth IDs and never consume a destination namespace" {
    const t = std.testing;
    var first = TestWorld.initNamespaced(t.allocator, 4, 0);
    defer first.deinit();
    var second = TestWorld.initNamespaced(t.allocator, 4, 1);
    defer second.deinit();
    const traveler = try first.create(null, .{ Position{ .x = 7, .y = 8, .z = 9 }, Health{ .value = 41 } });
    const local = try second.create(null, .{Health{ .value = 100 }});
    const identity = try first.persistentId(traveler);
    const moved = try first.cloneInto(traveler, &second);
    try t.expectEqual(identity, try second.persistentId(moved));
    try t.expectEqual(@as(i32, 41), (try second.get(moved, Health)).value);
    try t.expectEqual(@as(f32, 7), (try second.get(moved, Position)).x);
    try t.expect(first.alive(traveler));
    try t.expectError(error.DuplicateId, first.cloneInto(traveler, &second));
    try first.destroy(traveler);
    const returned = try second.cloneInto(moved, &first);
    try t.expectEqual(identity, try first.persistentId(returned));
    _ = try second.cloneInto(local, &first);
    const next = try first.create(null, .{Health{ .value = 2 }});
    try t.expectEqual(identity + 1, try first.persistentId(next));
    try t.expectEqual(@as(u32, 0x1000002), second.next_id);
    first.next_id = first.id_last + 1;
    try t.expectError(error.Capacity, first.create(null, .{Health{ .value = 0 }}));
    var full = TestWorld.initNamespaced(t.allocator, 0, 2);
    defer full.deinit();
    try t.expectError(error.Capacity, second.cloneInto(moved, &full));
    try t.expect(second.alive(moved));
    try t.expectEqual(@as(usize, 0), full.count());
}
