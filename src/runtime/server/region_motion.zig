// SPDX-License-Identifier: GPL-2.0-or-later
//! A moving controller keeps the world reached by each accepted segment. Queries
//! do not transfer ECS state; the controller commits once after writing its state.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const collision = @import("../domain/collision.zig");
const access = @import("region_access.zig");
const geometry = @import("region_collision.zig");
pub const Cursor = struct {
    owner: u32,
    skip: u32,
    pub fn init(world: *data.World, skip: u32) Cursor {
        return .{ .owner = if (access.contextFor(world)) |context| @intFromEnum(context.handle.?) else 0, .skip = skip };
    }
    pub fn trace(self: *Cursor, request: collision.Request) !collision.Trace {
        const hit = try geometry.from(self.owner, request, self.skip);
        self.owner = hit.world;
        return hit;
    }
    pub fn contents(self: Cursor, point: data.Vec3) !u32 {
        return geometry.contents(self.owner, point, self.skip);
    }
    pub fn finish(self: Cursor, world: *data.World, entity: ecs.Entity, now: i64) !void {
        if (self.owner == 0) return;
        const source = access.contextFor(world) orelse return error.MovingWorldUnavailable;
        const destination = access.byHandle(@enumFromInt(self.owner)) orelse return error.MovingWorldUnavailable;
        if (source != destination) try @import("world_transfer.zig").relocate(source, destination, entity, now);
    }
};
