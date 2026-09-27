// SPDX-License-Identifier: GPL-2.0-or-later
//! Thunderskeet spray: authored oscillation, world contact and radial damage.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").thunderskeet;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, alternate: bool, offset: v.Vec3, now: i64) !void {
    const random = try world.get(owner, data.Random);
    const speed = 128 + random.next() * 64;
    const aim = try @import("actor_aim.zig").lead(world, target, pose, offset, random);
    const entity = try world.create(null, .{
        data.Transform{ .position = v.add(pose.position, .{ 0, 0, -40 }) },
        data.Velocity{ .linear = v.scale(aim.direction, speed) },
        data.Body{ .mins = @splat(-1), .maxs = @splat(1), .collision_mask = c.CONTENTS_SOLID | c.CONTENTS_PLAYERCLIP },
        data.Lifetime{ .expires_ms = now + 15000 },
        data.ThunderSpray{ .owner = try world.persistentId(owner), .alternate = alternate, .born_ms = now, .stepped_ms = now, .next_ms = now + 200 },
    });
    try lifecycle.bind(world, slots, projections, entity, policy.spray_model);
    try publish(world, entity, projections, now);
    if (alternate) try @import("events.zig").sound(world, slots, projections, policy.spray_sound, pose.position, (try world.get(owner, data.Binding)).slot, c.CHAN_AUTO, now);
    var text: [128]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 thunder: id={d} spray={d} alternate={d}\n", .{ try world.persistentId(owner), try world.persistentId(entity), @intFromBool(alternate) }));
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const velocity = (try world.get(entity, data.Velocity)).linear;
    const spray = (try world.get(entity, data.ThunderSpray)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    projection.state.generic1 = policy.spray_tag;
    projection.state.angles2 = @splat(spray.scale);
    projection.state.time = @intCast(spray.born_ms);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, velocity, now);
    projection.shared.currentOrigin = pose.position;
    projection.shared.mins = @splat(-1);
    projection.shared.maxs = @splat(1);
    projection.shared.contents = 0;
    projection.shared.ownerNum = if (world.find(spray.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
fn explode(world: *data.World, slots: *Slots, entity: ecs.Entity, point: v.Vec3, now: i64) !void {
    const spray = (try world.get(entity, data.ThunderSpray)).*;
    for (slots.occupants) |occupant| {
        const target = occupant orelse continue;
        if ((world.get(target, data.Health) catch null) == null) continue;
        const target_pose = (try world.get(target, data.Transform)).*;
        const body = (try world.get(target, data.Body)).*;
        var center = target_pose.position;
        if (world.get(target, data.MapObject) catch null) |object| if (object.model.len > 0 and object.model[0] == '*') {
            center = v.add(center, v.scale(v.add(body.mins, body.maxs), 0.5));
        };
        const delta = v.subtract(center, point);
        const amount = policy.blast(v.length(delta), try world.persistentId(target) == spray.owner);
        if (amount <= 0) continue;
        const target_slot = (try world.get(target, data.Binding)).slot;
        const trace = try engine.collisionService().trace(.{ .start = point, .end = center, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
        if (trace.fraction < 1 and trace.entity != target_slot) continue;
        _ = try @import("weapon_damage.zig").hurt(world, target, spray.owner, 0, amount, now, false);
        try @import("weapon_damage.zig").shove(world, target, spray.owner, delta, amount, now);
    }
    var text: [100]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 thunder: spray={d} world-contact blast=40 radius=256\n", .{try world.persistentId(entity)}));
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var spray = (world.get(entity, data.ThunderSpray) catch continue).*;
        if (now >= (try world.get(entity, data.Lifetime)).expires_ms) {
            try lifecycle.remove(world, slots, projections, entity);
            continue;
        }
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        const slot = (try world.get(entity, data.Binding)).slot;
        var contact = false;
        while (spray.stepped_ms < now) {
            const until = @min(now, spray.next_ms);
            const delta = @as(f32, @floatFromInt(until - spray.stepped_ms)) * 0.001;
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, delta)), .mins = @splat(-1), .maxs = @splat(1), .slot = slot, .mask = c.CONTENTS_SOLID | c.CONTENTS_PLAYERCLIP });
            pose.position = hit.end;
            spray.stepped_ms = until;
            if (hit.fraction < 1 or hit.start_solid) {
                contact = true;
                break;
            }
            if (until == spray.next_ms) {
                if (spray.tick(&velocity)) try @import("events.zig").sound(world, slots, projections, policy.spray_sound, pose.position, slot, c.CHAN_AUTO, now);
                spray.next_ms += 100;
            }
        }
        if (contact) {
            try explode(world, slots, entity, pose.position, now);
            try lifecycle.remove(world, slots, projections, entity);
        } else {
            (try world.get(entity, data.ThunderSpray)).* = spray;
            (try world.get(entity, data.Transform)).* = pose;
            (try world.get(entity, data.Velocity)).linear = velocity;
            try publish(world, entity, projections, now);
        }
    }
}
