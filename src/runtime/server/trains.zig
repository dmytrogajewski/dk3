// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/trains.zig");
const prop = @import("properties.zig");
const names = @import("names.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const c = abi.c;
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    var entities: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.mem.eql(u8, object.classname, "func_train")) {
            entities[count] = entity;
            count += 1;
        };
    }
    for (entities[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        const transform = (try world.get(entity, data.Transform)).*;
        if (slots.find(entity) == null) {
            if (object.model.len != 0) return error.InvalidTrainModel;
            const slot = try slots.acquire(entity, null);
            try world.put(entity, data.Binding{ .slot = slot });
            try world.put(entity, data.Body{});
            projections[slot].shared.svFlags = c.SVF_NOCLIENT;
            projections[slot].state.eType = c.ET_MOVER;
        }
        const speed = try prop.number(object, "speed", 100);
        try world.put(entity, data.Train{ .next_target = object.target, .speed = if (speed > 0) speed else 100, .position = .{ .base = transform.position, .end = transform.position }, .angles = .{ .base = transform.angles, .end = transform.angles }, .action = try @import("../domain/time.zig").Deadline.after(now, 100), .force = object.flags & 64 != 0 or try prop.number(object, "forcemove", 0) != 0, .damage = @intFromFloat(try prop.number(object, "damage", try prop.number(object, "dmg", 2))) });
        try publish(world, entity, projections);
    }
}
fn corner(world: *data.World, name: []const u8) !?ecs.Entity {
    if (name.len == 0) return null;
    const matches = try names.named(world, name);
    if (matches.count == 0) return null;
    const entity = world.find(matches.ids[0]).?;
    if (!std.mem.eql(u8, (try world.get(entity, data.MapObject)).classname, "path_corner_train")) return null;
    return entity;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const transform = (try world.get(entity, data.Transform)).*;
    const train = (try world.get(entity, data.Train)).*;
    const projection = &projections[(try world.get(entity, data.Binding)).slot];
    projection.shared.currentOrigin = transform.position;
    projection.shared.currentAngles = transform.angles;
    projection.state.pos = if (train.phase == .moving) @import("../engine/trajectory.zig").fromMotion(train.position) else @import("../engine/trajectory.zig").stationary(transform.position);
    projection.state.apos = if (train.phase == .moving) @import("../engine/trajectory.zig").fromMotion(train.angles) else @import("../engine/trajectory.zig").stationary(transform.angles);
    engine.link(projection);
}
fn arrived(world: *data.World, entity: ecs.Entity, now: i64) !void {
    const train = try world.get(entity, data.Train);
    const destination = world.find(train.destination) orelse {
        train.phase = .paused;
        train.action = .{};
        return;
    };
    const object = (try world.get(destination, data.MapObject)).*;
    train.next_target = object.target;
    train.arrival_pending = true;
    try train.reached(now, object.flags & 8 != 0, try prop.number(object, "health", 0));
}
fn initialize(world: *data.World, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !bool {
    const train = try world.get(entity, data.Train);
    const object = (try world.get(entity, data.MapObject)).*;
    const first = try corner(world, train.next_target) orelse {
        train.phase = .paused;
        train.action = .{};
        return false;
    };
    const point = (try world.get(first, data.Transform)).position;
    try @import("pusher.zig").teleport(world, projections, entity, point, now);
    train.position = .{ .base = point, .end = point };
    train.destination = try world.persistentId(first);
    train.next_target = (try world.get(first, data.MapObject)).target;
    train.phase = .paused;
    train.action = .{};
    train.departure_wait_ms = 0;
    if (object.targetname.len > 0 and object.flags & 128 == 0) return false;
    try arrived(world, entity, now);
    return true;
}
fn leave(world: *data.World, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const train = try world.get(entity, data.Train);
    const destination = try corner(world, train.next_target) orelse {
        train.phase = .paused;
        train.action = .{};
        return;
    };
    const previous = if (world.find(train.destination)) |point| (try world.get(point, data.MapObject)).* else null;
    var speed = train.speed;
    var rotation: data.Vec3 = @splat(0);
    var rates: data.Vec3 = @splat(0);
    var flags: u32 = 0;
    train.departure_wait_ms = 0;
    if (previous) |object| {
        train.departure_wait_ms = try prop.milliseconds(object, "wait", 0);
        const supplied_speed = try prop.number(object, "speed", 0);
        if (supplied_speed > 0) speed = supplied_speed;
        flags = object.flags;
        inline for (.{ "y", "z", "x" }, 0..) |axis, i| {
            rotation[i] = try prop.number(object, axis ++ "_distance", 0);
            rates[i] = try prop.number(object, axis ++ "_speed", 0);
        }
    }
    const transform = try world.get(entity, data.Transform);
    const destination_point = (try world.get(destination, data.Transform)).position;
    const leg = try rules.leg(transform.position, destination_point, transform.angles, speed, rotation, rates, flags);
    train.destination = try world.persistentId(destination);
    train.action = .{};
    train.position = .{ .base = transform.position, .end = destination_point, .start_ms = now, .duration_ms = leg.duration_ms };
    train.angles = .{ .base = transform.angles, .end = leg.angular_end, .start_ms = now, .duration_ms = leg.duration_ms };
    train.phase = .moving;
    if (flags & 32 != 0) {
        try @import("pusher.zig").teleport(world, projections, entity, destination_point, now);
        train.phase = .teleporting;
        train.action = try @import("../domain/time.zig").Deadline.after(now, 1);
    }
}
pub fn use(world: *data.World, projections: []abi.EntityProjection, entity: ecs.Entity, source: ?ecs.Entity, activator: u32, now: i64) !void {
    const train = try world.get(entity, data.Train);
    train.owner = activator;
    if (train.phase == .initializing) _ = try initialize(world, projections, entity, now);
    if (source) |other| if (world.alive(other)) {
        const object = (world.get(other, data.MapObject) catch null);
        if (object) |value| {
            const redirected = prop.text(value.*, "path_target") orelse prop.text(value.*, "pathtarget");
            if (redirected) |name| if (name.len > 0) {
                train.next_target = name;
                try leave(world, projections, entity, now);
                try publish(world, entity, projections);
                return;
            };
        }
    };
    const triggered = if (world.find(train.destination)) |point| (try world.get(point, data.MapObject)).flags & 8 != 0 else false;
    if (train.canUse(triggered)) try leave(world, projections, entity, now);
    try publish(world, entity, projections);
}
pub const Arrivals = struct { entities: [ecs.max_entities]ecs.Entity = undefined, count: usize = 0 };
pub fn prepare(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const train = world.get(entity, data.Train) catch continue;
        if (!train.action.due(now)) continue;
        switch (train.phase) {
            .initializing => {
                _ = try initialize(world, projections, entity, now);
            },
            .dwelling => try leave(world, projections, entity, now),
            .teleporting => try arrived(world, entity, now),
            else => {},
        }
        try publish(world, entity, projections);
    }
}
pub fn step(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64, elapsed: u32) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const train = world.get(entity, data.Train) catch continue;
        if (@import("attachments.zig").attached(world, entity)) continue;
        const destination = if (train.phase == .moving) data.Transform{ .position = train.position.sample(now), .angles = train.angles.sample(now) } else (try world.get(entity, data.Transform)).*;
        const move: @import("pusher.zig").Move = .{ .entity = entity, .destination = destination };
        if (try @import("pusher.zig").push(world, slots, projections, &.{move}, now, elapsed)) |blocker| {
            _ = try @import("damage.zig").apply(world, blocker, train.damage, now, .{});
        }
    }
}
pub fn finish(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, now: i64) !Arrivals {
    var arrivals: Arrivals = .{};
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const train = world.get(entity, data.Train) catch continue;
        if (train.phase == .moving and train.position.finished(now)) try arrived(world, entity, now);
        try publish(world, entity, projections);
        if (train.arrival_pending) {
            train.arrival_pending = false;
            arrivals.entities[arrivals.count] = entity;
            arrivals.count += 1;
        }
    }
    return arrivals;
}
