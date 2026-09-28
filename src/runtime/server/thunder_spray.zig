// SPDX-License-Identifier: GPL-2.0-or-later
//! Thunderskeet spray: authored oscillation, world contact and radial damage.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").thunderskeet;
const lifecycle = @import("weapon_entities.zig");
/// Diagnostic prediction only: copies the controller and traces current geometry.
/// Moving geometry can invalidate a forecast; this neither steps nor damages the
/// live world. The class oscillator, hull, mask and lifetime remain authoritative.
pub fn forecast(world: *data.World, entity: ecs.Entity, now: i64) !?struct { eta: f32, point: v.Vec3 } {
    var spray = (try world.get(entity, data.ThunderSpray)).*;
    var position = (try world.get(entity, data.Transform)).position;
    var velocity = (try world.get(entity, data.Velocity)).linear;
    const end = @min(now + 3000, (try world.get(entity, data.Lifetime)).expires_ms);
    const slot = (try world.get(entity, data.Binding)).slot;
    var cursor = @import("region_motion.zig").Cursor.init(world, try world.persistentId(entity));
    while (spray.stepped_ms < end) {
        const until = @min(end, spray.next_ms);
        const elapsed = @as(f32, @floatFromInt(until - spray.stepped_ms));
        const hit = try cursor.trace(.{ .start = position, .end = v.add(position, v.scale(velocity, elapsed * 0.001)), .mins = @splat(-1), .maxs = @splat(1), .slot = slot, .mask = c.CONTENTS_SOLID | c.CONTENTS_PLAYERCLIP });
        if (hit.fraction < 1 or hit.start_solid) return .{
            .eta = @max(0, @as(f32, @floatFromInt(spray.stepped_ms - now)) + elapsed * hit.fraction) * 0.001,
            .point = hit.end,
        };
        position = hit.end;
        spray.stepped_ms = until;
        if (until == spray.next_ms) {
            _ = spray.tick(&velocity);
            spray.next_ms += 100;
        }
    }
    return null;
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: Ref, pose: data.Transform, alternate: bool, offset: v.Vec3, now: i64) !void {
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
    try @import("actor_aim.zig").finishLaunch(world, pose.position, entity, now);
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
fn explode(world: *data.World, slots: *Slots, entity: ecs.Entity, owner_world: u32, point: v.Vec3, now: i64) !void {
    const spray = (try world.get(entity, data.ThunderSpray)).*;
    var candidates = @import("region_access.zig").Damageables.init(world, slots);
    while (candidates.next()) |target| {
        if ((target.get(data.Health) catch null) == null) continue;
        const target_pose = (try target.get(data.Transform)).*;
        const body = (try target.get(data.Body)).*;
        var center = target_pose.position;
        if (target.get(data.MapObject) catch null) |object| if (object.model.len > 0 and object.model[0] == '*') {
            center = v.add(center, v.scale(v.add(body.mins, body.maxs), 0.5));
        };
        const delta = v.subtract(center, point);
        const amount = policy.blast(v.length(delta), try target.id() == spray.owner);
        if (amount <= 0) continue;
        const trace = try @import("region_collision.zig").from(owner_world, .{ .start = point, .end = center, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID }, try world.persistentId(entity));
        if (!@import("region_collision.zig").reaches(world, trace, target)) continue;
        _ = try @import("weapon_damage.zig").hurt(target.world, target.entity, spray.owner, 0, amount, now, false);
        try @import("weapon_damage.zig").shove(target.world, target.entity, spray.owner, delta, amount, now);
    }
    var text: [180]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 thunder: spray={d} world-contact blast=40 radius=256 at={d} position={d:.3},{d:.3},{d:.3}\n", .{ try world.persistentId(entity), now, point[0], point[1], point[2] }));
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var spray = (world.get(entity, data.ThunderSpray) catch continue).*;
        if (now <= spray.stepped_ms) continue;
        var motion = @import("region_motion.zig").Cursor.init(world, try world.persistentId(entity));
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
            const hit = try motion.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, delta)), .mins = @splat(-1), .maxs = @splat(1), .slot = slot, .mask = c.CONTENTS_SOLID | c.CONTENTS_PLAYERCLIP });
            pose.position = hit.end;
            spray.stepped_ms = until;
            if (hit.fraction < 1 or hit.start_solid) {
                contact = true;
                break;
            }
            if (until == spray.next_ms) {
                if (spray.tick(&velocity)) try @import("events.zig").soundOwned(world, slots, projections, motion.owner, policy.spray_sound, pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
                spray.next_ms += 100;
            }
        }
        if (contact) {
            try explode(world, slots, entity, motion.owner, pose.position, now);
            try lifecycle.remove(world, slots, projections, entity);
        } else {
            (try world.get(entity, data.ThunderSpray)).* = spray;
            (try world.get(entity, data.Transform)).* = pose;
            (try world.get(entity, data.Velocity)).linear = velocity;
            try publish(world, entity, projections, now);
            try motion.finish(world, entity, now);
        }
    }
}
