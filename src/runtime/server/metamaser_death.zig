// SPDX-License-Identifier: GPL-2.0-or-later
//! Metamaser destruction bands and delayed laser sweeps retain independent deadlines.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const access = @import("region_access.zig");
const geometry = @import("region_collision.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").metamaser;
const v = @import("../domain/vector.zig");
const c = abi.c;
const entities = @import("weapon_entities.zig");
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    if (world.get(entity, data.MetaRing) catch null) |ring| {
        const value = ring.*;
        try entities.effect(world, entity, projections, .{ .weapon = W.id, .owner = value.owner, .phase = 10, .born_ms = value.born_ms, .end_ms = value.born_ms + 2000 });
    } else {
        const value = (try world.get(entity, data.MetaLaser)).*;
        try entities.effect(world, entity, projections, .{ .weapon = W.id, .owner = value.owner, .phase = if (value.fired) 11 else 12, .endpoint = value.endpoint, .end_ms = value.expires_ms });
    }
}
pub fn burstOwned(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: u32, cube: ecs.Entity, projectile: data.Projectile, random: *data.Random, expires: i64, now: i64) !void {
    const pose = (try world.get(cube, data.Transform)).*;
    const cube_id = try world.persistentId(cube);
    if (owner != 0) {
        const context = access.byHandle(@enumFromInt(owner)) orelse return error.BurstWorldUnavailable;
        if (&context.world.? != world) {
            const scope = try context.select();
            defer scope.deinit();
            try context.expose(now);
            return burst(&context.world.?, &context.slots, &context.projection, cube_id, pose, projectile, random, expires, now);
        }
    }
    return burst(world, slots, projections, cube_id, pose, projectile, random, expires, now);
}
fn burst(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, cube_id: u32, pose: data.Transform, projectile: data.Projectile, random: *data.Random, expires: i64, now: i64) !void {
    const ring = try world.create(null, .{ pose, data.MetaRing{ .owner = projectile.owner, .cube = cube_id, .damage = projectile.damage, .born_ms = now, .next_ms = now + 100 } });
    try entities.bind(world, slots, projections, ring, "");
    try publish(world, ring, projections);
    for (0..4) |index| {
        _ = random.next();
        const laser = try world.create(null, .{ pose, data.MetaLaser{ .owner = projectile.owner, .cube = cube_id, .damage = projectile.damage, .next_ms = now + @as(i64, @intCast(100 * (index + 1))), .expires_ms = expires }, data.Random{ .state = random.state } });
        try entities.bind(world, slots, projections, laser, "");
        try publish(world, laser, projections);
    }
}
fn push(world: *data.World, target: ecs.Entity, direction: v.Vec3, magnitude: f32) !void {
    const velocity = world.get(target, data.Velocity) catch return;
    var forward = v.normalize(direction);
    if (forward[2] > -0.1 and forward[2] < 0.4) forward[2] = 0.4;
    velocity.linear = v.add(velocity.linear, v.scale(forward, magnitude));
    if (world.get(target, data.Body) catch null) |body| body.grounded = false;
    if (world.get(target, data.Player) catch null) |player| player.ground_entity = c.ENTITYNUM_NONE;
    if (world.get(target, data.Actor) catch null) |actor| actor.ground_entity = c.ENTITYNUM_NONE;
}
fn ringStep(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var ring = (try world.get(entity, data.MetaRing)).*;
    if (now > ring.born_ms + 2000) {
        try entities.remove(world, slots, projections, entity);
        return;
    }
    if (now < ring.next_ms) return;
    ring.next_ms = now + 50;
    const pose = (try world.get(entity, data.Transform)).*;
    const cube = access.find(world, ring.cube);
    const origin = if (cube) |parent| (try parent.get(data.Transform)).position else pose.position;
    const source_world = if (cube) |parent| parent.world else world;
    var candidates = access.Damageables.init(world, slots);
    while (candidates.next()) |target| {
        if ((cube != null and cube.?.same(target)) or (try target.get(data.Health)).current <= 0) continue;
        const identity = try target.id();
        const point = (try target.get(data.Transform)).position;
        const delta = v.subtract(point, origin);
        var amount = W.ringDamage(ring.damage, now - ring.born_ms, v.length(delta), delta[2], identity == ring.owner);
        if (amount <= 0 or !geometry.reaches(world, try trace(source_world, origin, point, ring.cube, c.MASK_SOLID), target)) continue;
        if (target.get(data.Projectile) catch null) |projectile| if (projectile.flight == .metamaser) {
            amount = 32000;
        };
        _ = try @import("weapon_damage.zig").hurt(target.world, target.entity, ring.owner, W.id, amount, now, false);
        try push(target.world, target.entity, delta, 50 * amount);
    }
    (try world.get(entity, data.MetaRing)).* = ring;
}
fn trace(world: *data.World, origin: v.Vec3, end: v.Vec3, skip: u32, mask: u32) !@import("../domain/collision.zig").Trace {
    return geometry.owned(world, .{ .start = origin, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = mask }, skip);
}
fn damageable(world: *data.World, slots: *Slots, hit: @import("../domain/collision.zig").Trace) ?Ref {
    const target = access.victim(world, slots, hit) orelse return null;
    if ((target.get(data.Health) catch return null).current <= 0) return null;
    return target;
}
fn laserStep(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var laser = (try world.get(entity, data.MetaLaser)).*;
    const cube = access.find(world, laser.cube);
    if (now > laser.expires_ms or cube == null) {
        try entities.remove(world, slots, projections, entity);
        return;
    }
    if (laser.fired or now < laser.next_ms) return;
    const origin = (try cube.?.get(data.Transform)).position;
    var random = (try world.get(entity, data.Random)).*;
    var hit: ?@import("../domain/collision.zig").Trace = null;
    var candidates = access.Damageables.init(world, slots);
    if (random.next() < 0.025) while (candidates.next()) |target| {
        if (target.same(cube.?) or (try target.get(data.Health)).current <= 0) continue;
        const point = (try target.get(data.Transform)).position;
        if (!geometry.reaches(world, try trace(cube.?.world, origin, point, laser.cube, c.MASK_SOLID), target)) continue;
        const result = try trace(cube.?.world, origin, v.add(origin, v.scale(v.subtract(point, origin), 2)), laser.cube, c.MASK_SHOT);
        if (damageable(world, slots, result) != null) {
            hit = result;
            break;
        }
    };
    if (hit == null) {
        const pose = (try cube.?.get(data.Transform)).*;
        const up = @import("../domain/poses.zig").axes(pose.angles)[2];
        var angles: v.Vec3 = .{ -std.math.atan2(up[2], @sqrt(up[0] * up[0] + up[1] * up[1])) * (180.0 / std.math.pi), std.math.atan2(up[1], up[0]) * (180.0 / std.math.pi), 0 };
        angles[0] += 180 * (random.next() - 0.5);
        angles[1] += 360 * (random.next() - 0.5);
        hit = try trace(cube.?.world, origin, v.add(origin, v.scale(v.basis(angles).forward, 4000)), laser.cube, c.MASK_SHOT);
    }
    laser.endpoint = hit.?.end;
    if (damageable(world, slots, hit.?)) |target| {
        _ = try @import("weapon_damage.zig").hurt(target.world, target.entity, laser.owner, W.id, laser.damage, now, false);
        try push(target.world, target.entity, v.subtract(laser.endpoint, origin), 750);
    }
    laser.fired = true;
    (try world.get(entity, data.Transform)).position = origin;
    (try world.get(entity, data.MetaLaser)).* = laser;
    (try world.get(entity, data.Random)).* = random;
    const motion = @import("region_motion.zig").Cursor.init(cube.?.world, 0);
    try @import("events.zig").soundOwned(world, slots, projections, motion.owner, W.sounds.large[random.state & 1], origin, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
    try publish(world, entity, projections);
    try motion.finish(world, entity, now);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        if ((world.get(entity, data.MetaRing) catch null) != null) try ringStep(world, slots, projections, entity, now) else if ((world.get(entity, data.MetaLaser) catch null) != null) try laserStep(world, slots, projections, entity, now);
    }
}
