// SPDX-License-Identifier: GPL-2.0-or-later
//! Each job writes its own bounded command buffer; the owner commits by job key.
const std = @import("std");
const Entity = @import("world.zig").Entity;
pub fn Commands(comptime W: type, comptime Component: type) type {
    return struct {
        const Self = @This();
        pub const Target = union(enum) { entity: Entity, created: u16 };
        pub const Operation = union(enum) {
            create: struct { id: ?u32 = null, component: Component },
            destroy: Target,
            put: struct { target: Target, component: Component },
            remove: struct { target: Target, component: std.meta.Tag(Component) },
        };
        pub const Buffer = struct {
            system: u16,
            job: u32,
            operations: [256]Operation = undefined,
            results: [256]?Entity = @splat(null),
            count: u16 = 0,
            pub fn append(self: *Buffer, operation: Operation) !u16 {
                if (self.count == self.operations.len) return error.CommandCapacity;
                const index = self.count;
                self.operations[index] = operation;
                self.count += 1;
                return index;
            }
            fn resolve(self: *const Buffer, target: Target, before: usize) !Entity {
                return switch (target) {
                    .entity => |entity| entity,
                    .created => |index| if (index < before) self.results[index] orelse error.InvalidSpawnReference else error.InvalidSpawnReference,
                };
            }
        };
        fn less(_: void, a: *Buffer, b: *Buffer) bool {
            return a.system < b.system or (a.system == b.system and a.job < b.job);
        }
        pub fn commit(world: *W, buffers: []*Buffer) !void {
            std.mem.sort(*Buffer, buffers, {}, less);
            for (buffers, 0..) |buffer, bi| {
                if (bi > 0 and !less({}, buffers[bi - 1], buffer)) return error.DuplicateJobKey;
            }
            for (buffers) |buffer| {
                @memset(&buffer.results, null);
                for (buffer.operations[0..buffer.count], 0..) |operation, i| switch (operation) {
                    .create => |spawn| {
                        switch (spawn.component) {
                            inline else => |component| buffer.results[i] = try world.create(spawn.id, .{component}),
                        }
                    },
                    .destroy => |target| {
                        const entity = try buffer.resolve(target, i);
                        if (world.alive(entity)) try world.destroy(entity);
                    },
                    .put => |change| {
                        const entity = try buffer.resolve(change.target, i);
                        if (!world.alive(entity)) continue;
                        switch (change.component) {
                            inline else => |component| try world.put(entity, component),
                        }
                    },
                    .remove => |change| {
                        const entity = try buffer.resolve(change.target, i);
                        if (!world.alive(entity)) continue;
                        inline for (std.meta.fields(Component)) |field| {
                            if (change.component == @field(std.meta.Tag(Component), field.name)) try world.remove(entity, field.type);
                        }
                    },
                };
            }
        }
    };
}
test "ordered commands allocate stable IDs independent of completion order" {
    const Position = struct { x: i32 };
    const Health = struct { value: i32 };
    const Component = union(enum) { position: Position, health: Health };
    const W = @import("world.zig").World(.{ Position, Health });
    const C = Commands(W, Component);
    var world = W.init(std.testing.allocator, 8);
    defer world.deinit();
    var later: C.Buffer = .{ .system = 1, .job = 1 };
    var earlier: C.Buffer = .{ .system = 1, .job = 0 };
    _ = try later.append(.{ .create = .{ .component = .{ .position = .{ .x = 20 } } } });
    const ref = try earlier.append(.{ .create = .{ .component = .{ .position = .{ .x = 10 } } } });
    _ = try earlier.append(.{ .put = .{ .target = .{ .created = ref }, .component = .{ .health = .{ .value = 93 } } } });
    var buffers = [_]*C.Buffer{ &later, &earlier };
    try C.commit(&world, &buffers);
    try std.testing.expectEqual(@as(i32, 10), (try world.get(world.find(1).?, Position)).x);
    try std.testing.expectEqual(@as(i32, 93), (try world.get(world.find(1).?, Health)).value);
    try std.testing.expectEqual(@as(i32, 20), (try world.get(world.find(2).?, Position)).x);
}
