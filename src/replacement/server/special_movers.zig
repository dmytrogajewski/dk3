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
pub fn spawn(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const object = (world.get(entity, data.MapObject) catch continue).*;
        if (!std.mem.eql(u8, object.classname, "func_rotate") and !std.mem.eql(u8, object.classname, "func_door_secret")) continue;
        const transform = (try world.get(entity, data.Transform)).*;
        const speed = try prop.number(object, "speed", 100);
        if (std.mem.eql(u8, object.classname, "func_rotate")) {
            var rate: data.Vec3 = @splat(0);
            rate[if (object.flags & 4 != 0) @as(usize, 2) else if (object.flags & 8 != 0) 0 else 1] = (if (speed > 0) speed else 100) * @as(f32, if (object.flags & 2 != 0) -1 else 1);
            try world.put(entity, data.Rotation{ .base = transform.angles, .rate = rate, .active = object.flags & 1 != 0, .started_ms = now, .damage = @intFromFloat(try prop.number(object, "damage", try prop.number(object, "dmg", 2))) });
        } else if (std.mem.eql(u8, object.classname, "func_door_secret")) {
            const body = (try world.get(entity, data.Body)).*;
            const size = v.add(body.maxs, v.scale(body.mins, -1));
            const basis = v.basis(transform.angles);
            const direction = if (object.flags & 4 != 0) v.cross(basis.right, basis.forward) else basis.right;
            var first: f32 = 0;
            var second: f32 = 0;
            for (0..3) |axis| {
                first += @abs(direction[axis]) * size[axis];
                second += @abs(basis.forward[axis]) * size[axis];
            }
            const middle = v.add(transform.position, v.scale(direction, first * @as(f32, if (object.flags & (2 | 4) != 0) -1 else 1)));
            var group = try world.persistentId(entity);
            if (prop.text(object, "team")) |team| if (team.len > 0) {
                for (slots.occupants) |other| {
                    const part = other orelse continue;
                    const secret = world.get(part, data.Secret) catch continue;
                    const part_object = (try world.get(part, data.MapObject)).*;
                    if (std.mem.eql(u8, team, prop.text(part_object, "team") orelse "")) group = @min(group, secret.group);
                }
            };
            try world.put(entity, data.Secret{ .closed = transform.position, .first = middle, .opened = v.add(middle, v.scale(basis.forward, second)), .motion = .{ .base = transform.position, .end = transform.position }, .speed = if (speed > 0) speed else 100, .wait_ms = try prop.milliseconds(object, "wait", 3), .stay_open = object.flags & 1 != 0, .damage = @intFromFloat(try prop.number(object, "damage", try prop.number(object, "dmg", 2))), .group = group });
            (try world.get(entity, data.Transform)).angles = @splat(0);
        } else continue;
        try publish(world, entity, projections);
    }
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const transform = (try world.get(entity, data.Transform)).*;
    const projection = &projections[(try world.get(entity, data.Binding)).slot];
    projection.shared.currentOrigin = transform.position;
    projection.shared.currentAngles = transform.angles;
    const wire = @import("../engine/trajectory.zig");
    projection.state.pos = wire.stationary(transform.position);
    projection.state.apos = wire.stationary(transform.angles);
    if (world.get(entity, data.Rotation)) |rotation| {
        if (rotation.active) projection.state.apos = wire.linear(rotation.base, rotation.rate, rotation.started_ms);
    } else |_| if (world.get(entity, data.Secret)) |secret| {
        if (secret.moving()) projection.state.pos = wire.fromMotion(secret.motion);
    } else |_| {}
    engine.link(projection);
}
/// Rotation fires targets on each toggle; secrets fire only on full opening.
pub fn use(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, entity: ecs.Entity, owner: u32, now: i64) !bool {
    if (world.get(entity, data.Rotation)) |rotation| {
        rotation.toggle((try world.get(entity, data.Transform)).angles, now);
        try publish(world, entity, projections);
        return true;
    } else |_| {}
    const original = try world.get(entity, data.Secret);
    const master = world.find(original.group) orelse return error.MissingMoverMaster;
    const control = try world.get(master, data.Secret);
    if (control.phase != .closed or !@import("keys.zig").allows(world, (try world.get(master, data.MapObject)).*, owner)) return false;
    for (slots.occupants) |occupant| {
        const part = occupant orelse continue;
        const secret = world.get(part, data.Secret) catch continue;
        if (secret.group != control.group) continue;
        secret.phase = .closed;
        _ = try secret.use((try world.get(part, data.Transform)).position, now, owner);
        try publish(world, part, projections);
    }
    return false;
}
pub fn prepare(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const secret = world.get(entity, data.Secret) catch continue;
        try secret.prepare((try world.get(entity, data.Transform)).position, now);
        try publish(world, entity, projections);
    }
}
pub fn step(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64, elapsed: u32) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        if (@import("attachments.zig").attached(world, entity)) continue;
        var moves: [ecs.max_entities]pusher.Move = undefined;
        var count: usize = 0;
        var damage: i32 = 0;
        if (world.get(entity, data.Rotation)) |rotation| {
            var transform = (try world.get(entity, data.Transform)).*;
            transform.angles = rotation.sample(now);
            moves[0] = .{ .entity = entity, .destination = transform };
            count = 1;
            damage = rotation.damage;
        } else |_| if (world.get(entity, data.Secret)) |master| {
            if (master.group != try world.persistentId(entity)) continue;
            damage = master.damage;
            for (slots.occupants) |part_occupant| {
                const part = part_occupant orelse continue;
                const secret = world.get(part, data.Secret) catch continue;
                if (secret.group != master.group) continue;
                var transform = (try world.get(part, data.Transform)).*;
                if (secret.moving()) transform.position = secret.motion.sample(now);
                moves[count] = .{ .entity = part, .destination = transform };
                count += 1;
            }
        } else |_| continue;
        if (try pusher.push(world, slots, projections, moves[0..count], now, elapsed)) |blocker| {
            _ = try @import("damage.zig").apply(world, blocker, damage, now, .{});
        }
    }
}
pub fn finish(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64) !@import("movers.zig").Arrivals {
    var arrivals: @import("movers.zig").Arrivals = .{};
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const secret = world.get(entity, data.Secret) catch continue;
        if (try secret.finish(now)) {
            arrivals.entities[arrivals.count] = entity;
            arrivals.count += 1;
        }
        try publish(world, entity, projections);
    }
    return arrivals;
}
