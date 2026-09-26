// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const v = @import("../domain/vector.zig");
const prop = @import("properties.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const pusher = @import("pusher.zig");
const c = abi.c;
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn spawn(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const object = (try world.get(entity, data.MapObject)).*;
        const rotating = eq(object.classname, "func_door_rotate");
        const platform = eq(object.classname, "func_plat");
        const button = eq(object.classname, "func_button");
        if (!rotating and !platform and !button and !eq(object.classname, "func_door") and !eq(object.classname, "func_water")) continue;
        const transform = (try world.get(entity, data.Transform)).*;
        const body = (try world.get(entity, data.Body)).*;
        var closed = if (rotating) transform.angles else transform.position;
        var opened = closed;
        const lip = try prop.number(object, "lip", if (button) 4 else 8);
        const size = v.add(body.maxs, v.scale(body.mins, -1));
        if (rotating) {
            const axis: usize = if (object.flags & 128 != 0) 2 else if (object.flags & 256 != 0) 0 else 1;
            opened[axis] += (try prop.number(object, "distance", 90)) * @as(f32, if (object.flags & 2 != 0) -1 else 1);
        } else if (platform) {
            closed[2] -= try prop.number(object, "height", size[2] - lip);
        } else {
            const yaw = try prop.number(object, "angle", 0);
            const angles = if (prop.text(object, "angles")) |text| try @import("map.zig").vector(text) else v.Vec3{ 0, yaw, 0 };
            const direction: v.Vec3 = if (yaw == -1) .{ 0, 0, 1 } else if (yaw == -2) .{ 0, 0, -1 } else v.basis(angles).forward;
            var distance: f32 = -lip;
            for (0..3) |axis| distance += @abs(direction[axis]) * size[axis];
            opened = v.add(closed, v.scale(direction, distance));
        }
        if (object.flags & 1 != 0 and !button) std.mem.swap(v.Vec3, &closed, &opened);
        const speed = try prop.number(object, "speed", if (button) 40 else 100);
        const mover: data.Mover = .{ .closed = closed, .opened = opened, .motion = .{ .base = closed, .end = closed, .curve = if (try prop.number(object, "boing", 0) != 0) .bounce else if (try prop.number(object, "accelerate", 0) != 0) .accelerate else .linear }, .angular = rotating, .platform = platform, .speed = if (speed > 0) speed else if (button) 40 else 100, .wait_ms = try prop.milliseconds(object, "wait", if (button) 1 else 3), .delay_ms = if (std.mem.startsWith(u8, object.classname, "func_door")) @max(0, try prop.milliseconds(object, "delay", 0)) else 0, .toggle = object.flags & (8 | 32) != 0, .return_both = object.flags & 64 != 0, .force = (try prop.number(object, "forcemove", 0) != 0) or (!rotating and object.flags & 512 != 0), .damage = @intFromFloat(try prop.number(object, "damage", try prop.number(object, "dmg", 2))), .group = try world.persistentId(entity) };
        try world.put(entity, mover);
        const actual = try world.get(entity, data.Transform);
        if (rotating) actual.angles = closed else {
            actual.position = closed;
            actual.angles = @splat(0);
        }
        try publish(world, entity, projections);
    }
    // Stable, transitive grouping by explicit team or touching doors with equal targetname.
    var changed = true;
    while (changed) {
        changed = false;
        for (slots.occupants, 0..) |left, i| {
            const a = left orelse continue;
            const ma = world.get(a, data.Mover) catch continue;
            const oa = (try world.get(a, data.MapObject)).*;
            for (slots.occupants[i + 1 ..]) |right| {
                const b = right orelse continue;
                const mb = world.get(b, data.Mover) catch continue;
                if (ma.group == mb.group) continue;
                const ob = (try world.get(b, data.MapObject)).*;
                const team = prop.text(oa, "team") orelse "";
                var match = team.len > 0 and eq(team, prop.text(ob, "team") orelse "");
                if (!match and oa.flags & 4 == 0 and ob.flags & 4 == 0 and std.mem.startsWith(u8, oa.classname, "func_door") and std.mem.startsWith(u8, ob.classname, "func_door") and eq(oa.targetname, ob.targetname)) {
                    const pa = &projections[(try world.get(a, data.Binding)).slot];
                    const pb = &projections[(try world.get(b, data.Binding)).slot];
                    match = true;
                    for (0..3) |axis| if (pa.shared.absmin[axis] > pb.shared.absmax[axis] + 1 or pb.shared.absmin[axis] > pa.shared.absmax[axis] + 1) {
                        match = false;
                        break;
                    };
                }
                if (match) {
                    const group = @min(ma.group, mb.group);
                    ma.group = group;
                    mb.group = group;
                    changed = true;
                }
            }
        }
    }
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const mover = (try world.get(entity, data.Mover)).*;
    const transform = (try world.get(entity, data.Transform)).*;
    const projection = &projections[(try world.get(entity, data.Binding)).slot];
    projection.shared.currentOrigin = transform.position;
    projection.shared.currentAngles = transform.angles;
    const wire = @import("../engine/trajectory.zig");
    projection.state.pos = wire.stationary(transform.position);
    projection.state.apos = wire.stationary(transform.angles);
    if (mover.moving()) {
        if (mover.angular) projection.state.apos = wire.fromMotion(mover.motion) else projection.state.pos = wire.fromMotion(mover.motion);
    }
    engine.link(projection);
}
fn start(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, group: u32, opened: bool, now: i64, delayed: bool) !void {
    var duration: i32 = 1;
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const mover = world.get(entity, data.Mover) catch continue;
        if (mover.group != group) continue;
        const transform = (try world.get(entity, data.Transform)).*;
        duration = @max(duration, try mover.duration(opened, if (mover.angular) transform.angles else transform.position));
    }
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const mover = world.get(entity, data.Mover) catch continue;
        if (mover.group != group) continue;
        const transform = (try world.get(entity, data.Transform)).*;
        mover.start(opened, if (mover.angular) transform.angles else transform.position, now, duration, delayed);
        try publish(world, entity, projections);
    }
}
pub fn use(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) !void {
    const original = world.get(entity, data.Mover) catch return;
    const master = world.find(original.group) orelse return error.MissingMoverMaster;
    const mover = try world.get(master, data.Mover);
    const object = (try world.get(master, data.MapObject)).*;
    if (!@import("keys.zig").allows(world, object, activator)) return;
    if (try mover.use(now, activator)) |opened| try start(world, slots, projections, mover.group, opened, now, true);
}
pub const Arrivals = struct { entities: [ecs.max_entities]ecs.Entity = undefined, count: usize = 0 };
pub fn prepare(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const mover = world.get(entity, data.Mover) catch continue;
        if (mover.group == try world.persistentId(entity) and mover.return_at.due(now)) try start(world, slots, projections, mover.group, mover.state == .closed, now, false);
    }
}
pub fn step(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64, elapsed: u32) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const master = world.get(entity, data.Mover) catch continue;
        if (master.group != try world.persistentId(entity) or @import("attachments.zig").attached(world, entity)) continue;
        var moves: [ecs.max_entities]pusher.Move = undefined;
        var count: usize = 0;
        for (slots.occupants) |part_occupant| {
            const part = part_occupant orelse continue;
            const mover = world.get(part, data.Mover) catch continue;
            if (mover.group != master.group) continue;
            var transform = (try world.get(part, data.Transform)).*;
            if (mover.moving()) {
                if (mover.angular) transform.angles = mover.motion.sample(now) else transform.position = mover.motion.sample(now);
            }
            moves[count] = .{ .entity = part, .destination = transform };
            count += 1;
        }
        if (try pusher.push(world, slots, projections, moves[0..count], now, elapsed)) |blocker| {
            _ = try @import("damage.zig").apply(world, blocker, master.damage, now, .{});
            if (!master.force and master.moving()) try start(world, slots, projections, master.group, master.state == .closing, now, false);
        }
    }
}
pub fn finish(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64) !Arrivals {
    var arrivals: Arrivals = .{};
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const mover = world.get(entity, data.Mover) catch continue;
        if (mover.moving() and mover.motion.finished(now)) {
            if (try mover.reached(now, mover.group == try world.persistentId(entity))) {
                arrivals.entities[arrivals.count] = entity;
                arrivals.count += 1;
            }
        }
        try publish(world, entity, projections);
    }
    return arrivals;
}
