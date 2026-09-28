// SPDX-License-Identifier: GPL-2.0-or-later
//! Shockwave orb contacts and persistent, overlapping expanding damage bands.
const std = @import("std");
const data = @import("../domain/components.zig");
const access = @import("region_access.zig");
const geometry = @import("region_collision.zig");
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
    var candidates = access.Damageables.init(world, slots);
    while (candidates.next()) |target| {
        if (!actor(target.world, target.entity) or (try target.get(data.Health)).current <= 0 or !(try target.get(data.Body)).grounded) continue;
        const delta = v.subtract((try target.get(data.Transform)).position, position);
        const distance = v.length(delta);
        if (distance > 1000) continue;
        const impulse = v.scale(W.pushDirection(delta), 2000 * (1 - distance * 0.001));
        try setVelocity(target.world, target.entity, v.scale(v.add((try target.get(data.Velocity)).linear, impulse), 0.3));
    }
}
fn detonate(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, projectile: data.Projectile, position: v.Vec3, owner: u32, now: i64) !void {
    if (owner != 0) {
        const destination = access.byHandle(@enumFromInt(owner)) orelse return error.ShockwaveWorldUnavailable;
        if (&destination.world.? != world) {
            const identity = try world.persistentId(entity);
            (try world.get(entity, data.Transform)).position = position;
            (try world.get(entity, data.Projectile)).* = projectile;
            const cursor: @import("region_motion.zig").Cursor = .{ .owner = owner, .skip = 0 };
            try cursor.finish(world, entity, now);
            const scope = try destination.select();
            defer scope.deinit();
            return detonate(&destination.world.?, &destination.slots, &destination.projection, destination.world.?.find(identity).?, projectile, position, owner, now);
        }
    }
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
        if (projectile.weapon != W.id or now <= projectile.stepped_ms) continue;
        var cursor = @import("region_motion.zig").Cursor.init(world, projectile.owner);
        const slot = (try world.get(entity, data.Binding)).slot;
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        var at = projectile.stepped_ms;
        while (at < now) {
            const milliseconds = @min(20, now - at);
            const wet = (try cursor.contents(pose.position)) & c.MASK_WATER != 0;
            projectile.wet = wet;
            const motion = W.think(&projectile.flight.shockwave, at - projectile.born_ms, wet, pose.position, velocity);
            velocity = motion.velocity;
            if (motion.explode or at >= (try world.get(entity, data.Lifetime)).expires_ms) {
                try detonate(world, slots, projections, entity, projectile, pose.position, cursor.owner, now);
                break;
            }
            if (motion.trail) try @import("events.zig").impactOwned(world, slots, projections, cursor.owner, .{ .weapon = W.id, .kind = .world, .normal = v.normalize(velocity), .trail = true }, pose.position, now);
            const skip: u16 = if (world.find(projectile.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
            const hit = try cursor.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, @as(f32, @floatFromInt(milliseconds)) * 0.001)), .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = skip, .mask = c.MASK_SHOT });
            pose.position = hit.end;
            at += milliseconds;
            if (hit.sky or hit.no_impact) {
                try entities.remove(world, slots, projections, entity);
                break;
            }
            if (hit.fraction == 1) continue;
            if (access.victim(world, slots, hit)) |target| if ((target.get(data.Health) catch null) != null) {
                _ = try damage.hurt(target.world, target.entity, projectile.owner, W.id, projectile.damage * W.spec.projectile.direct_scale, now, false);
                try detonate(world, slots, projections, entity, projectile, pose.position, cursor.owner, now);
                break;
            };
            projectile.bounces +|= 1;
            projectile.flight.shockwave.rings = 6;
            try area.apply(world, slots, .{ .world = cursor.owner, .owner = projectile.owner, .weapon = W.id, .origin = pose.position, .damage = projectile.damage * W.spec.projectile.splash_scale, .radius = W.spec.projectile.splash_radius, .skip_slot = slot, .occlusion = false }, now);
            try wallPush(world, slots, pose.position);
            try @import("impacts.zig").contact(world, slots, projections, W.id, hit, .{}, now);
            if (projectile.bounces > 5 or projectile.flight.shockwave.touched_water or hit.all_solid) {
                try detonate(world, slots, projections, entity, projectile, v.add(pose.position, v.scale(hit.normal, 40)), cursor.owner, now);
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
        try cursor.finish(world, entity, now);
    }
}
fn ringDamage(world: *data.World, slots: *const Slots, position: v.Vec3, wave: data.Shockwave, ring: W.Ring, now: i64) !void {
    if (ring.outer >= 350) return;
    var candidates = access.Damageables.init(world, slots);
    while (candidates.next()) |target| {
        const health = target.get(data.Health) catch continue;
        if (health.current <= 0) continue;
        const origin = (try target.get(data.Transform)).position;
        const body = (try target.get(data.Body)).*;
        const point = v.add(origin, v.scale(v.add(body.mins, body.maxs), 0.5));
        const distance = v.length(v.subtract(point, position));
        if (distance < @max(0, ring.inner) or distance > ring.outer) continue;
        const amount = W.ringDamage(wave.damage, distance, try target.id() == wave.owner, try geometry.inPvs(world, position, target, origin), geometry.reaches(world, try geometry.owned(world, .{ .start = position, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SOLID }, 0), target));
        _ = try damage.hurt(target.world, target.entity, wave.owner, W.id, amount, now, false);
        if (actor(target.world, target.entity)) try setVelocity(target.world, target.entity, v.add((try target.get(data.Velocity)).linear, v.scale(W.pushDirection(v.subtract(origin, position)), 1500 * @max(0, 1 - distance * 0.001))));
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
        var candidates = access.Damageables.init(world, slots);
        while (candidates.next()) |target| {
            if (!actor(target.world, target.entity) or !(try target.get(data.Body)).grounded or (try target.get(data.Health)).current <= 0) continue;
            if (v.length(v.subtract(position, (try target.get(data.Transform)).position)) * 0.7 > 350) continue;
            var velocity = (try target.get(data.Velocity)).linear;
            velocity[0] += (random.next() - 0.5) * 200;
            velocity[1] += (random.next() - 0.5) * 200;
            try setVelocity(target.world, target.entity, velocity);
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
