// SPDX-License-Identifier: GPL-2.0-or-later
//! Shockwave orb contacts and persistent, overlapping expanding damage bands.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").shockwave;
const v = @import("../domain/vector.zig");
const area = @import("area_damage.zig");
const damage = @import("weapon_damage.zig");
const entities = @import("weapon_entities.zig");
const c = abi.c;
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const wave = (try world.get(entity, data.Shockwave)).*;
    const slot = (try world.get(entity, data.Binding)).slot;
    const position = (try world.get(entity, data.Transform)).position;
    const projection = &projections[slot];
    projection.state.number = slot;
    projection.state.eType = c.ET_DK3_EFFECT;
    projection.state.weapon = W.id;
    projection.state.time = @intCast(wave.born_ms);
    projection.state.time2 = @intCast(wave.rings[wave.count - 1].start_ms);
    projection.state.frame = wave.count;
    projection.state.generic1 = @bitCast(try world.persistentId(entity));
    for (wave.rings[0..wave.count], 0..) |ring, index| {
        const offset: f32 = @floatFromInt(ring.start_ms - wave.born_ms);
        if (index < 3) projection.state.angles2[index] = offset else projection.state.origin2[index - 3] = offset;
    }
    projection.state.pos = @import("../engine/trajectory.zig").stationary(position);
    projection.shared.currentOrigin = position;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    projection.shared.contents = 0;
    engine.link(projection);
}
fn actor(world: *data.World, entity: ecs.Entity) bool {
    return (world.get(entity, data.Actor) catch null) != null or (world.get(entity, data.Player) catch null) != null;
}
fn setVelocity(world: *data.World, entity: ecs.Entity, velocity: v.Vec3) !void {
    (try world.get(entity, data.Velocity)).linear = velocity;
    (try world.get(entity, data.Body)).grounded = false;
    if (world.get(entity, data.Player) catch null) |player| player.ground_entity = c.ENTITYNUM_NONE;
    if (world.get(entity, data.Actor) catch null) |state| state.ground_entity = c.ENTITYNUM_NONE;
}
fn wallPush(world: *data.World, slots: *const Slots, position: v.Vec3) !void {
    for (slots.occupants) |occupant| {
        const target = occupant orelse continue;
        if (!actor(world, target) or (try world.get(target, data.Health)).current <= 0 or !(try world.get(target, data.Body)).grounded) continue;
        const delta = v.subtract((try world.get(target, data.Transform)).position, position);
        const distance = v.length(delta);
        if (distance > 1000) continue;
        const impulse = v.scale(W.pushDirection(delta), 2000 * (1 - distance * 0.001));
        try setVelocity(world, target, v.scale(v.add((try world.get(target, data.Velocity)).linear, impulse), 0.3));
    }
}
fn detonate(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, projectile: data.Projectile, position: v.Vec3, now: i64) !void {
    const center = try world.create(null, .{ data.Transform{ .position = position }, W.Wave.init(projectile.owner, projectile.damage, now), data.Random{ .state = (try world.persistentId(entity)) ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) } });
    errdefer world.destroy(center) catch unreachable;
    try entities.bind(world, slots, projections, center, "");
    try publish(world, center, projections);
    try @import("events.zig").impact(world, slots, projections, .{ .weapon = W.id, .kind = .world, .normal = .{ 0, 0, 1 }, .detonation = true }, position, now);
    if (engine.integer("developer") > 0) {
        var text: [180]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig shockwave: center={d} age={d} bounces={d} water={d}\n", .{ try world.persistentId(center), now - projectile.born_ms, projectile.bounces, @intFromBool(projectile.flight.shockwave.touched_water) }));
    }
    try entities.remove(world, slots, projections, entity);
}
fn spheres(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.weapon != W.id) continue;
        const slot = (try world.get(entity, data.Binding)).slot;
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        var at = projectile.stepped_ms;
        while (at < now) {
            const milliseconds = @min(20, now - at);
            const wet = (try engine.collisionService().contents(pose.position, slot)) & c.MASK_WATER != 0;
            projectile.wet = wet;
            const motion = W.think(&projectile.flight.shockwave, at - projectile.born_ms, wet, pose.position, velocity);
            velocity = motion.velocity;
            if (motion.explode or at >= (try world.get(entity, data.Lifetime)).expires_ms) {
                try detonate(world, slots, projections, entity, projectile, pose.position, now);
                break;
            }
            if (motion.trail) try @import("events.zig").impact(world, slots, projections, .{ .weapon = W.id, .kind = .world, .normal = v.normalize(velocity), .trail = true }, pose.position, now);
            const skip: u16 = if (world.find(projectile.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, @as(f32, @floatFromInt(milliseconds)) * 0.001)), .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = skip, .mask = c.MASK_SHOT });
            pose.position = hit.end;
            at += milliseconds;
            if (hit.sky or hit.no_impact) {
                try entities.remove(world, slots, projections, entity);
                break;
            }
            if (hit.fraction == 1) continue;
            if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |target| if ((world.get(target, data.Health) catch null) != null) {
                _ = try damage.hurt(world, target, projectile.owner, W.id, projectile.damage * W.spec.projectile.direct_scale, now, false);
                try detonate(world, slots, projections, entity, projectile, pose.position, now);
                break;
            };
            projectile.bounces +|= 1;
            projectile.flight.shockwave.rings = 6;
            try area.apply(world, slots, .{ .owner = projectile.owner, .weapon = W.id, .origin = pose.position, .damage = projectile.damage * W.spec.projectile.splash_scale, .radius = W.spec.projectile.splash_radius, .skip_slot = slot, .occlusion = false }, now);
            try wallPush(world, slots, pose.position);
            try @import("impacts.zig").contact(world, slots, projections, W.id, hit, .{}, now);
            if (projectile.bounces > 5 or projectile.flight.shockwave.touched_water or hit.all_solid) {
                try detonate(world, slots, projections, entity, projectile, v.add(pose.position, v.scale(hit.normal, 40)), now);
                break;
            }
            velocity = @import("../domain/combat.zig").reflect(velocity, hit.normal, 0.75);
            pose.position = v.add(pose.position, v.scale(hit.normal, 0.5));
        }
        if (!world.alive(entity)) continue;
        projectile.stepped_ms = now;
        const seconds = @as(f32, @floatFromInt(now - projectile.born_ms)) * 0.001;
        pose.angles = .{ @mod(seconds * 45, 360), @mod(seconds * 90, 360), @mod(seconds * 180, 360) };
        (try world.get(entity, data.Projectile)).* = projectile;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = velocity;
        try @import("projectiles.zig").publish(world, entity, projections, now);
    }
}
fn ringDamage(world: *data.World, slots: *const Slots, position: v.Vec3, wave: data.Shockwave, ring: W.Ring, now: i64) !void {
    if (ring.outer >= 350) return;
    for (slots.occupants, 0..) |occupant, slot| {
        const target = occupant orelse continue;
        const health = world.get(target, data.Health) catch continue;
        if (health.current <= 0) continue;
        const origin = (try world.get(target, data.Transform)).position;
        const body = (try world.get(target, data.Body)).*;
        const point = v.add(origin, v.scale(v.add(body.mins, body.maxs), 0.5));
        const distance = v.length(v.subtract(point, position));
        if (distance < @max(0, ring.inner) or distance > ring.outer) continue;
        const amount = W.ringDamage(wave.damage, distance, try world.persistentId(target) == wave.owner, engine.inPvs(position, origin), try area.visible(position, point, c.ENTITYNUM_NONE, @intCast(slot)));
        _ = try damage.hurt(world, target, wave.owner, W.id, amount, now, false);
        if (actor(world, target)) try setVelocity(world, target, v.add((try world.get(target, data.Velocity)).linear, v.scale(W.pushDirection(v.subtract(origin, position)), 1500 * @max(0, 1 - distance * 0.001))));
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    try spheres(world, slots, projections, now);
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        var wave = (world.get(entity, data.Shockwave) catch continue).*;
        if (now < wave.next_ms) continue;
        const position = (try world.get(entity, data.Transform)).position;
        for (wave.rings[0..wave.count]) |ring| try ringDamage(world, slots, position, wave, ring, now);
        var random = (try world.get(entity, data.Random)).*;
        for (slots.occupants) |target_occupant| {
            const target = target_occupant orelse continue;
            if (!actor(world, target) or !(try world.get(target, data.Body)).grounded or (try world.get(target, data.Health)).current <= 0) continue;
            if (v.length(v.subtract(position, (try world.get(target, data.Transform)).position)) * 0.7 > 350) continue;
            var velocity = (try world.get(target, data.Velocity)).linear;
            velocity[0] += (random.next() - 0.5) * 200;
            velocity[1] += (random.next() - 0.5) * 200;
            try setVelocity(world, target, velocity);
        }
        const previous = wave.count;
        if (wave.advance(now)) {
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        (try world.get(entity, data.Shockwave)).* = wave;
        (try world.get(entity, data.Random)).* = random;
        if (wave.count != previous) {
            try @import("events.zig").impact(world, slots, projections, .{ .weapon = W.id, .kind = .world, .normal = .{ 0, 0, 1 }, .detonation = true, .sequence = wave.count - 1 }, position, now);
            if (engine.integer("developer") > 0) {
                var text: [128]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig shockwave: center={d} rings={d} age={d}\n", .{ try world.persistentId(entity), wave.count, now - wave.born_ms }));
            }
        }
        try publish(world, entity, projections);
    }
}
