// SPDX-License-Identifier: GPL-2.0-or-later
//! Resolves co-op route selectors to authored world entities and their physical
//! extents. Read-only: selection never creates, moves or activates anything.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const route = @import("../domain/coop_route.zig");
const catalog = @import("actor_catalog");
const Frame = @import("coop_motor.zig").Frame;
pub const Filter = enum { any, pickup, actor, hostile, mover, exit };
pub const Resolved = struct {
    entity: ?ecs.Entity = null,
    id: u32 = 0,
    /// Origin for point entities, box centre for brush entities.
    point: v.Vec3,
    mins: v.Vec3,
    maxs: v.Vec3,
    slot: ?u16 = null,
    brush: bool = false,
};
pub fn resolve(frame: Frame, target: route.Target, filter: Filter) !?Resolved {
    if (target.entityless()) return .{ .point = target.point.?, .mins = target.point.?, .maxs = target.point.? };
    const world = frame.world;
    if (target.id != 0 or target.index != 0) {
        const id = if (target.id != 0) target.id else namespace(world) | target.index;
        const entity = world.find(id) orelse return null;
        if (!try accepts(world, entity, filter, true)) return null;
        return try describe(frame, entity);
    }
    const origin = target.near orelse (try world.get(frame.entity, data.Transform)).position;
    var best: ?Resolved = null;
    var nearest: f32 = std.math.inf(f32);
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| {
        if (!target.name.empty() and !std.mem.eql(u8, object.targetname, target.name.slice())) continue;
        if (!target.class.empty() and !std.mem.eql(u8, object.classname, target.class.slice())) continue;
        if (!try accepts(world, entity, filter, !target.name.empty())) continue;
        const candidate = try describe(frame, entity);
        const distance = v.length(v.subtract(candidate.point, origin));
        if (distance >= nearest) continue;
        nearest = distance;
        best = candidate;
    };
    return best;
}
/// Authored entities keep the birth namespace of their map, which survives
/// restoration; stationary exits identify it independently of admission order.
pub fn namespace(world: *data.World) u32 {
    var query = world.queryAccess(data.World.mask(.{ data.Exit, data.MapObject }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities()) |entity| return (world.persistentId(entity) catch continue) & 0xff000000;
    return world.id_first & 0xff000000;
}
fn accepts(world: *data.World, entity: ecs.Entity, filter: Filter, named: bool) !bool {
    return switch (filter) {
        .any => true,
        .pickup => if (world.get(entity, data.Pickup) catch null) |pickup| pickup.visible else false,
        .actor, .hostile => blk: {
            const actor = world.get(entity, data.Actor) catch break :blk false;
            const health = world.get(entity, data.Health) catch break :blk false;
            if (health.current <= 0) break :blk false;
            // An explicitly named actor is a valid target whatever its class.
            break :blk filter == .actor or named or route.hostile(catalog.entries[actor.definition].kind);
        },
        .mover => (world.get(entity, data.Mover) catch null) != null or (world.get(entity, data.Train) catch null) != null,
        .exit => (world.get(entity, data.Exit) catch null) != null,
    };
}
pub fn describe(frame: Frame, entity: ecs.Entity) !Resolved {
    const world = frame.world;
    const pose = (try world.get(entity, data.Transform)).*;
    var result: Resolved = .{ .entity = entity, .id = try world.persistentId(entity), .point = pose.position, .mins = pose.position, .maxs = pose.position };
    if (world.get(entity, data.Body) catch null) |body| {
        result.mins = v.add(pose.position, body.mins);
        result.maxs = v.add(pose.position, body.maxs);
    }
    if (world.get(entity, data.Binding) catch null) |binding| if (binding.slot < frame.projections.len) {
        const shared = frame.projections[binding.slot].shared;
        result.slot = binding.slot;
        if (shared.linked != 0 and (shared.bmodel != 0 or shared.contents & c.CONTENTS_TRIGGER != 0)) {
            result.mins = shared.absmin;
            result.maxs = shared.absmax;
            result.point = v.scale(v.add(shared.absmin, shared.absmax), 0.5);
            result.brush = true;
        }
    };
    return result;
}
/// Observable authored state; a change means a control, trigger or target reacted.
/// Moving now: binary movers (doors, plats) or path trains (lifts, carts).
pub fn moving(world: *data.World, entity: ecs.Entity) bool {
    if (world.get(entity, data.Mover) catch null) |mover| return mover.moving();
    if (world.get(entity, data.Train) catch null) |train| return train.phase == .moving;
    return false;
}
/// "closed"/"opening"/"open"/"closing" for movers, the phase name for trains.
pub fn moverState(world: *data.World, entity: ecs.Entity) ?[]const u8 {
    if (world.get(entity, data.Mover) catch null) |mover| return @tagName(mover.state);
    if (world.get(entity, data.Train) catch null) |train| return @tagName(train.phase);
    return null;
}
pub fn signature(world: *data.World, id: u32) u64 {
    const entity = world.find(id) orelse return 0;
    var hash = std.hash.Wyhash.init(1);
    if (world.get(entity, data.Mover) catch null) |mover| hash.update(std.mem.asBytes(&mover.state));
    if (world.get(entity, data.Train) catch null) |train| hash.update(std.mem.asBytes(&train.phase));
    if (world.get(entity, data.Trigger) catch null) |trigger| hash.update(std.mem.asBytes(&trigger.uses));
    if (world.get(entity, data.WorldControl) catch null) |control| hash.update(std.mem.asBytes(&control.uses));
    if (world.get(entity, data.Health) catch null) |health| hash.update(std.mem.asBytes(&health.current));
    if (world.get(entity, data.Pickup) catch null) |pickup| hash.update(std.mem.asBytes(&pickup.visible));
    if (world.get(entity, data.Exit) catch null) |exit| hash.update(std.mem.asBytes(&exit.latched));
    if (world.get(entity, data.HealthTree) catch null) |tree| hash.update(std.mem.asBytes(&tree.fruit));
    return hash.final() | 1;
}
