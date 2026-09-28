// SPDX-License-Identifier: GPL-2.0-or-later
//! Scoped actor queries retain spatial ownership through slide/step alternatives.
//! A rejected probe cannot switch the owner of a different position. Only the
//! final accepted pose commits an entity transfer after its controller returns.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const collision = @import("../domain/collision.zig");
const engine = @import("../engine/server.zig");
const access = @import("region_access.zig");
const geometry = @import("region_collision.zig");
const v = @import("../domain/vector.zig");
const Mark = struct { position: data.Vec3, owner: u32 };
var active: ?*Frame = null;
pub const Frame = struct {
    world: *data.World,
    entity: ecs.Entity,
    marks: [256]Mark = undefined,
    count: usize = 0,
    cursor: usize = 0,
    prior: ?*Frame = null,
    pub fn init(world: *data.World, entity: ecs.Entity) !Frame {
        var frame: Frame = .{ .world = world, .entity = entity };
        const context = access.contextFor(world);
        frame.remember((try world.get(entity, data.Transform)).position, if (context) |owner| @intFromEnum(owner.handle.?) else 0);
        return frame;
    }
    pub fn enter(self: *Frame) void {
        self.prior = active;
        active = self;
    }
    pub fn leave(self: *Frame) void {
        std.debug.assert(active == self);
        active = self.prior;
    }
    fn remember(self: *Frame, point: data.Vec3, owner: u32) void {
        self.marks[self.cursor] = .{ .position = point, .owner = owner };
        self.cursor = (self.cursor + 1) % self.marks.len;
        self.count = @min(self.count + 1, self.marks.len);
    }
    fn nearest(self: *const Frame, point: data.Vec3) Mark {
        std.debug.assert(self.count > 0);
        var best: Mark = undefined;
        var distance: f32 = std.math.inf(f32);
        // Newest first resolves equal-position samples from the same sweep.
        for (0..self.count) |i| {
            const mark = self.marks[(self.cursor + self.marks.len - 1 - i) % self.marks.len];
            const d = v.length(v.subtract(mark.position, point));
            if (d < distance) {
                best = mark;
                distance = d;
            }
        }
        return best;
    }
    fn ownerAt(self: *Frame, point: data.Vec3) !u32 {
        const mark = self.nearest(point);
        if (mark.owner == 0 or v.length(v.subtract(mark.position, point)) < 0.0001) return mark.owner;
        // This classifies coordinate ownership only. The actual query below
        // still checks the complete hull, solids and authored collision mask.
        const hit = try geometry.from(mark.owner, .{ .start = mark.position, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = 2047, .mask = 0 }, 0);
        return hit.world;
    }
    fn trace(raw: *anyopaque, request: collision.Request) !collision.Trace {
        const self: *Frame = @ptrCast(@alignCast(raw));
        const owner = try self.ownerAt(request.start);
        const context = access.contextFor(self.world) orelse return engine.collisionService().trace(request);
        const skip = if (request.slot < context.slots.occupants.len) (if (context.slots.occupants[request.slot]) |entity| try self.world.persistentId(entity) else 0) else 0;
        const hit = try geometry.from(owner, request, skip);
        if (!hit.all_solid) self.remember(hit.end, hit.world);
        return hit;
    }
    fn contents(raw: *anyopaque, point: data.Vec3, slot: u16) !u32 {
        const self: *Frame = @ptrCast(@alignCast(raw));
        const context = access.contextFor(self.world) orelse return engine.collisionService().contents(point, slot);
        const skip = if (slot < context.slots.occupants.len) (if (context.slots.occupants[slot]) |entity| try self.world.persistentId(entity) else 0) else 0;
        return geometry.contents(try self.ownerAt(point), point, skip);
    }
    pub fn finish(self: *Frame, now: i64) !void {
        if (!self.world.alive(self.entity)) return;
        const body = try self.world.get(self.entity, data.Body);
        if (body.motion_owner) |identity| {
            const controller = access.find(self.world, identity) orelse return;
            const projectile = controller.get(data.Projectile) catch return;
            // Impaled actors still use collision-checked physical movement.
            // Cinematic/reaper positioning keeps its controller's own contract.
            if (projectile.flight != .ballista or projectile.flight.ballista.victim != try self.world.persistentId(self.entity)) return;
        }
        const point = (try self.world.get(self.entity, data.Transform)).position;
        const cursor: @import("region_motion.zig").Cursor = .{ .owner = try self.ownerAt(point), .skip = 0 };
        try cursor.finish(self.world, self.entity, now);
    }
};
/// The caller's current pose can already lie across a seam before the enclosing
/// actor frame commits. Offset attacks must start from that accepted owner.
pub fn ownerAt(world: *data.World, point: data.Vec3) !u32 {
    if (active) |frame| if (frame.world == world) return frame.ownerAt(point);
    return @import("region_motion.zig").Cursor.init(world, 0).owner;
}

pub fn service() collision.Collision {
    const frame = active orelse return engine.collisionService();
    return .{ .context = frame, .trace_fn = Frame.trace, .contents_fn = Frame.contents };
}

test "alternate step probes retain the ownership of the accepted position" {
    var world = data.World.init(std.testing.allocator, 1);
    defer world.deinit();
    const entity = try world.create(null, .{data.Transform{}});
    var frame = try Frame.init(&world, entity);
    frame.remember(.{ 0, 0, 0 }, 513);
    frame.remember(.{ 32, 0, 18 }, 514); // Alternative step reaches a neighbor.
    frame.remember(.{ 16, 0, 0 }, 513); // Actual slide is retained in the source.
    try std.testing.expectEqual(@as(u32, 513), frame.nearest(.{ 16, 0, 0 }).owner);
    try std.testing.expectEqual(@as(u32, 514), frame.nearest(.{ 32, 0, 18 }).owner);
    try std.testing.expectEqual(@as(u32, 513), frame.nearest(.{ 0, 0, 0 }).owner);
}
