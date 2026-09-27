// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored monitor views use the existing camera transport and body ownership.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
const targets = @import("names.zig");

pub fn spawn(world: *data.World) !void {
    var handles: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| {
            if (std.mem.eql(u8, object.classname, "func_monitor") and (world.get(entity, data.Monitor) catch null) == null) {
                handles[count] = entity;
                count += 1;
            }
        };
    }
    for (handles[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        const duration = @max(750, try prop.milliseconds(object, "wait", 3));
        if (duration > 3600000) return error.InvalidMonitorDuration;
        try world.put(entity, data.Monitor{ .duration_ms = duration });
    }
}
fn named(world: *data.World, name: []const u8) !ecs.Entity {
    if (name.len == 0) return error.MissingMonitorTarget;
    const matches = try targets.named(world, name);
    if (matches.count == 0) return error.MissingMonitorTarget;
    return world.find(matches.ids[0]) orelse error.MissingMonitorTarget;
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) !void {
    var monitor = (try world.get(entity, data.Monitor)).*;
    if (monitor.viewer != null or @import("cinematics.zig").active(world)) return;
    var viewer = world.find(activator) orelse return;
    if ((world.get(viewer, data.Player) catch null) == null) {
        viewer = slots.occupants[0] orelse return;
    }
    if ((try world.get(viewer, data.Health)).current <= 0 or (try world.get(viewer, data.Player)).mode != .normal or (try world.get(viewer, data.Body)).motion_owner != null) return;
    const viewpoint = try named(world, (try world.get(entity, data.MapObject)).target);
    const target = try named(world, (try world.get(viewpoint, data.MapObject)).target);
    monitor.origin = (try world.get(viewpoint, data.Transform)).position;
    const direction = v.subtract((try world.get(target, data.Transform)).position, monitor.origin);
    if (v.length(direction) == 0) return error.InvalidMonitorDirection;
    monitor.angles = .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 };
    monitor.camera = try world.persistentId(viewpoint);
    monitor.target = try world.persistentId(target);
    monitor.viewer = try world.persistentId(viewer);
    monitor.until_ms = now + monitor.duration_ms;
    try @import("weapon_actions.zig").cancel(world, slots, projections, viewer);
    (try world.get(entity, data.Monitor)).* = monitor;
    (try world.get(viewer, data.Body)).motion_owner = try world.persistentId(entity);
    (try world.get(viewer, data.Player)).mode = .frozen;
    (try world.get(viewer, data.Velocity)).linear = @splat(0);
    engine.print("dk3 monitor: view started\n");
}
pub fn stop(world: *data.World, entity: ecs.Entity) !void {
    const monitor = world.get(entity, data.Monitor) catch return;
    const identity = monitor.viewer orelse return;
    monitor.viewer = null;
    monitor.until_ms = null;
    if (world.find(identity)) |viewer| {
        const body = try world.get(viewer, data.Body);
        if (body.motion_owner != try world.persistentId(entity)) return;
        body.motion_owner = null;
        const player = try world.get(viewer, data.Player);
        if (player.mode == .frozen) player.mode = if ((try world.get(viewer, data.Health)).current > 0) .normal else .dead;
    }
}
pub fn detach(world: *data.World, viewer: ecs.Entity) !void {
    const owner = (try world.get(viewer, data.Body)).motion_owner orelse return;
    if (world.find(owner)) |entity| try stop(world, entity);
}
pub fn step(world: *data.World, slots: *const Slots, now: i64) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const monitor = world.get(entity, data.Monitor) catch continue;
        const identity = monitor.viewer orelse continue;
        const viewer = world.find(identity);
        if (now >= monitor.until_ms.? or viewer == null or (try world.get(viewer.?, data.Health)).current <= 0) {
            try stop(world, entity);
            engine.print("dk3 monitor: view completed\n");
        }
    }
}
pub fn active(world: *data.World) bool {
    var query = world.queryAccess(data.World.mask(.{data.Monitor}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.Monitor)) |monitor| if (monitor.viewer != null and engine.integer("g_gametype") == abi.c.GT_SINGLE_PLAYER) return true;
    return false;
}
pub fn camera(world: *data.World, viewer: ecs.Entity, ps: *abi.c.playerState_t) !void {
    const owner = (try world.get(viewer, data.Body)).motion_owner orelse return;
    const entity = world.find(owner) orelse return;
    const monitor = world.get(entity, data.Monitor) catch return;
    if (monitor.viewer != try world.persistentId(viewer)) return;
    ps.dk3CameraActive = 1;
    ps.dk3CameraOrigin = monitor.origin;
    ps.dk3CameraAngles = monitor.angles;
    ps.dk3CameraFov = 90; // Existing native player view uses this same FOV.
    ps.dk3CameraBlend = @splat(0);
}

test "monitor release preserves another body owner and cannot revive a dead viewer" {
    var world = data.World.init(std.testing.allocator, 8);
    defer world.deinit();
    const viewer = try world.create(1, .{ data.Body{ .motion_owner = 2 }, data.Player{ .mode = .frozen }, data.Health{} });
    const monitor = try world.create(2, .{data.Monitor{ .viewer = 1, .until_ms = 8000 }});
    try stop(&world, monitor);
    try std.testing.expect((try world.get(viewer, data.Player)).mode == .normal);
    try std.testing.expectEqual(@as(?u32, null), (try world.get(viewer, data.Body)).motion_owner);
    (try world.get(monitor, data.Monitor)).viewer = 1;
    (try world.get(monitor, data.Monitor)).until_ms = 8000;
    (try world.get(viewer, data.Body)).motion_owner = 3;
    (try world.get(viewer, data.Player)).mode = .frozen;
    try stop(&world, monitor);
    try std.testing.expectEqual(@as(?u32, 3), (try world.get(viewer, data.Body)).motion_owner);
    try std.testing.expect((try world.get(viewer, data.Player)).mode == .frozen);
    (try world.get(monitor, data.Monitor)).viewer = 1;
    (try world.get(monitor, data.Monitor)).until_ms = 8000;
    (try world.get(viewer, data.Body)).motion_owner = 2;
    (try world.get(viewer, data.Health)).current = 0;
    try stop(&world, monitor);
    try std.testing.expect((try world.get(viewer, data.Player)).mode == .dead);
}
