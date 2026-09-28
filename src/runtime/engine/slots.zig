// SPDX-License-Identifier: GPL-2.0-or-later
//! Engine transport slots are independent of ECS indices and persistent save IDs.
const std = @import("std");
const ecs = @import("../ecs/world.zig");
pub const Slots = struct {
    pub const clients = 64;
    occupants: [ecs.max_entities]?ecs.Entity = @splat(null),
    borrowed: [ecs.max_entities]bool = @splat(false),
    pub fn find(self: *const Slots, entity: ecs.Entity) ?u16 {
        for (self.occupants, 0..) |occupant, index| {
            if (occupant) |other| if (same(entity, other)) return @intCast(index);
        }
        return null;
    }
    fn same(a: ecs.Entity, b: ecs.Entity) bool {
        return a.index == b.index and a.generation == b.generation;
    }
    pub fn acquire(self: *Slots, entity: ecs.Entity, client: ?u16) !u16 {
        if (self.find(entity) != null) return error.AlreadyProjected;
        const index: usize = if (client) |index| blk: {
            if (index >= clients) return error.InvalidClient;
            if (self.occupants[index] != null or self.borrowed[index]) return error.SlotOccupied;
            break :blk index;
        } else blk: {
            for (self.occupants[clients .. ecs.max_entities - 2], clients..) |occupant, index| if (occupant == null and !self.borrowed[index]) break :blk index;
            return error.ProjectionCapacity;
        };
        self.occupants[index] = entity;
        return @intCast(index);
    }
    /// A foreign presentation has a transport slot, never a duplicate ECS actor.
    pub fn borrow(self: *Slots) !u16 {
        for (self.occupants[clients .. ecs.max_entities - 2], clients..) |occupant, index| {
            if (occupant != null or self.borrowed[index]) continue;
            self.borrowed[index] = true;
            return @intCast(index);
        }
        return error.ProjectionCapacity;
    }
    pub fn relinquish(self: *Slots, index: u16) void {
        std.debug.assert(index >= clients and index < ecs.max_entities - 2 and self.borrowed[index] and self.occupants[index] == null);
        self.borrowed[index] = false;
    }
    pub fn release(self: *Slots, index: u16, entity: ecs.Entity) !void {
        if (index >= self.occupants.len) return error.InvalidSlot;
        const occupant = self.occupants[index] orelse return error.StaleProjection;
        if (!same(entity, occupant)) return error.StaleProjection;
        self.occupants[index] = null;
    }
};
test "reserved slots and stale releases cannot alias a recycled entity" {
    var slots: Slots = .{};
    const old: ecs.Entity = .{ .index = 100, .generation = 1 };
    const next: ecs.Entity = .{ .index = 100, .generation = 2 };
    try std.testing.expectEqual(@as(u16, 64), try slots.acquire(old, null));
    try slots.release(64, old);
    try std.testing.expectEqual(@as(u16, 64), try slots.acquire(next, null));
    try std.testing.expectError(error.StaleProjection, slots.release(64, old));
    try std.testing.expectEqual(@as(?u16, 64), slots.find(next));
    try std.testing.expectEqual(@as(u16, 0), try slots.acquire(old, 0));
    try std.testing.expectError(error.AlreadyProjected, slots.acquire(next, 1));
}

test "foreign presentation leases exclude gameplay allocation and collision sentinels" {
    var slots: Slots = .{};
    const alias = try slots.borrow();
    const entity: ecs.Entity = .{ .index = 64, .generation = 1 };
    const local = try slots.acquire(entity, null);
    try std.testing.expect(alias != local and slots.occupants[alias] == null);
    slots.relinquish(alias);
    try std.testing.expectEqual(alias, try slots.borrow());
    while (slots.borrow()) |_| {} else |err| try std.testing.expectEqual(error.ProjectionCapacity, err);
    try std.testing.expect(!slots.borrowed[ecs.max_entities - 1] and !slots.borrowed[ecs.max_entities - 2]);
}
