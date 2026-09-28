// SPDX-License-Identifier: GPL-2.0-or-later
//! A persistent identity names its current owner, even after leaving its birth map.
//! Callers retain an explicit world/entity pair; local ECS handles never alias.
const std = @import("std");
const data = @import("components.zig");
const ecs = @import("../ecs/world.zig");
pub const Ref = struct {
    world: *data.World,
    entity: ecs.Entity,
    pub fn get(self: Ref, comptime T: type) !*T {
        return self.world.get(self.entity, T);
    }
    pub fn require(self: Ref, comptime types: anytype) !void {
        inline for (types) |T| _ = try self.get(T);
    }
    pub fn id(self: Ref) !u32 {
        return self.world.persistentId(self.entity);
    }
};
pub const Worlds = struct {
    entries: []const *data.World,
    pub fn find(self: Worlds, id: u32) ?Ref {
        if (id == 0) return null;
        for (self.entries) |world| if (world.find(id)) |entity| return .{ .world = world, .entity = entity };
        return null;
    }
    pub fn validate(self: Worlds, allocator: std.mem.Allocator) !void {
        var owners: std.AutoHashMapUnmanaged(u32, void) = .empty;
        defer owners.deinit(allocator);
        for (self.entries) |world| {
            var ids = world.ids.keyIterator();
            while (ids.next()) |id| {
                const entry = try owners.getOrPut(allocator, id.*);
                if (entry.found_existing) return error.DuplicateRegionIdentity;
            }
        }
    }
};
