// SPDX-License-Identifier: GPL-2.0-or-later
//! Wisp acquisition and collision adapters; the weapon class owns its oscillator and fade.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const access = @import("region_access.zig");
const geometry = @import("region_collision.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").wyndrax;
const weapons = @import("../domain/weapons.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;
const entities = @import("weapon_entities.zig");
const damage = @import("weapon_damage.zig");
fn slot(world: *data.World, id: u32) i32 {
    const entity = world.find(id) orelse return c.ENTITYNUM_NONE;
    return (world.get(entity, data.Binding) catch return c.ENTITYNUM_NONE).slot;
}
pub fn project(world: *data.World, wisp: W.BallisticState, state: *c.entityState_t) void {
    state.angles2 = wisp.scale;
    state.otherEntityNum = slot(world, wisp.targets[0]);
    state.otherEntityNum2 = slot(world, wisp.targets[1]);
    state.origin2 = .{ @floatFromInt(slot(world, wisp.targets[2])), @floatFromInt(slot(world, wisp.targets[3])), wisp.alpha };
}
fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, name: [:0]const u8, now: i64) !void {
    try @import("events.zig").sound(world, slots, projections, name, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const tuning = table.entries[W.id];
    if (tuning.lifetime <= 0) return error.InvalidWispLifetime;
    const owner_id = try world.persistentId(owner);
    var random: data.Random = .{ .state = owner_id ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) ^ 0x2b6471c9 };
    const eye = @import("../domain/combat.zig").eye(shot.position, shot.view_height);
    var motion = @import("region_motion.zig").Cursor.init(world, owner_id);
    const position = (try motion.trace(.{ .start = eye, .end = @import("../domain/combat.zig").muzzle(eye, shot.angles, tuning.muzzle), .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = (try world.get(owner, data.Binding)).slot, .mask = c.MASK_SOLID })).end;
    const speed = 500 + 500 * random.next();
    const wisp: W.BallisticState = .{ .personality = random.next(), .sound_ms = 100 + @as(i64, @intFromFloat(200 * random.next())) };
    const lifetime: i64 = @intFromFloat(tuning.lifetime * 1000);
    const projectile: data.Projectile = .{ .owner = owner_id, .weapon = W.id, .damage = tuning.damage, .born_ms = now, .stepped_ms = now, .flight = .{ .wyndrax = wisp }, .launch_position = position, .speed = speed, .lifetime_ms = lifetime };
    const entity = try world.create(null, .{ data.Transform{ .position = position, .angles = shot.angles }, data.Velocity{ .linear = v.scale(v.basis(shot.angles).forward, speed) }, projectile, random, data.Lifetime{ .expires_ms = now + lifetime + 2100 } });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, W.spec.visual.projectile_model);
    try @import("projectiles.zig").publish(world, entity, projections, now);
    try sound(world, slots, projections, owner, W.spec.audio.fire.?, now);
    try motion.finish(world, entity, now);
}
fn alive(world: *data.World, id: u32) bool {
    const entity = access.find(world, id) orelse return false;
    return (entity.get(data.Health) catch return false).current > 0;
}
fn valid(entity: Ref, owner: u32) !bool {
    if (try entity.id() == owner or (entity.get(data.Health) catch return false).current <= 0) return false;
    if ((entity.get(data.Actor) catch null) != null) return true;
    return engine.integer("g_gametype") != c.GT_SINGLE_PLAYER and (entity.get(data.Player) catch null) != null;
}
fn visible(world: *data.World, position: v.Vec3, skip: u32, target: Ref) !bool {
    const hit = try geometry.owned(world, .{ .start = position, .end = (try target.get(data.Transform)).position, .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SOLID }, skip);
    return geometry.reaches(world, hit, target);
}
fn acquire(world: *data.World, slots: *Slots, entity: ecs.Entity, projectile: data.Projectile, wisp: *W.BallisticState, random: *data.Random, position: v.Vec3) !void {
    const skip = try world.persistentId(entity);
    const old = wisp.enemy;
    if (old) |id| if (!alive(world, id) or !try visible(world, position, skip, access.find(world, id).?)) {
        wisp.enemy = null;
    };
    const gather = random.next() > 0.02;
    var nearest: f32 = std.math.inf(f32);
    var next = wisp.enemy;
    var candidates = access.Damageables.init(world, slots);
    while (candidates.next()) |target| {
        if (!try valid(target, projectile.owner)) continue;
        const distance = v.length(v.subtract((try target.get(data.Transform)).position, position));
        if ((!gather or distance > 300) and wisp.enemy != null) continue;
        if (!try visible(world, position, skip, target)) continue;
        const id = try target.id();
        if (gather and distance <= 300) _ = wisp.include(id);
        if (wisp.enemy == null and distance < nearest) {
            nearest = distance;
            next = id;
        }
    }
    wisp.enemy = next;
    if (wisp.enemy == null) if (old) |id| if (alive(world, id)) {
        wisp.enemy = id;
    };
}
fn zap(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, projectile: data.Projectile, wisp: *W.BallisticState, random: *data.Random, position: v.Vec3, owner_world: u32, now: i64) !void {
    const age = now - projectile.born_ms;
    var audible = age > wisp.sound_ms;
    for (&wisp.targets) |*id| {
        if (id.* == 0) continue;
        audible = true;
        const target = access.find(world, id.*) orelse {
            id.* = 0;
            continue;
        };
        const delta = v.subtract((try target.get(data.Transform)).position, position);
        if (v.length(delta) > 250) continue;
        const amount = projectile.damage * 0.5;
        if (try damage.hurt(target.world, target.entity, projectile.owner, W.id, amount, now, false)) try damage.shove(target.world, target.entity, projectile.owner, v.normalize(delta), amount, now);
        if (!alive(world, id.*) or random.next() > 0.9) id.* = 0;
    }
    if (audible) {
        wisp.sound_ms = age + 100 + @as(i64, @intFromFloat(200 * random.next()));
        try @import("events.zig").soundOwned(world, slots, projections, owner_world, W.sounds[@min(2, @as(usize, @intFromFloat(random.next() * 3)))], position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.flight != .wyndrax or now <= projectile.stepped_ms) continue;
        var motion = @import("region_motion.zig").Cursor.init(world, try world.persistentId(entity));
        var wisp = projectile.flight.wyndrax;
        var random = (try world.get(entity, data.Random)).*;
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        const skip = (try world.get(entity, data.Binding)).slot;
        const age = now - projectile.born_ms;
        if (wisp.phase == .active) try acquire(world, slots, entity, projectile, &wisp, &random, pose.position);
        var at = projectile.stepped_ms;
        while (at < now) {
            const delta_ms = @min(20, now - at);
            const goal = v.add(pose.position, v.scale(velocity, @as(f32, @floatFromInt(delta_ms)) * 0.001));
            const hit = try motion.trace(.{ .start = pose.position, .end = goal, .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = skip, .mask = c.MASK_SOLID });
            pose.position = hit.end;
            at += delta_ms;
            if (hit.fraction < 1) {
                velocity = @import("../domain/combat.zig").reflect(velocity, hit.normal, 0.75);
                pose.position = v.add(pose.position, v.scale(hit.normal, 0.5));
                wisp.sine_ms = at - projectile.born_ms + 200;
            }
        }
        var remove = now >= (try world.get(entity, data.Lifetime)).expires_ms;
        if (age >= wisp.next_ms) {
            wisp.next_ms = age + 100;
            try zap(world, slots, projections, projectile, &wisp, &random, pose.position, motion.owner, now);
            const fading = wisp.phase == .fading;
            if (fading) remove = remove or wisp.fade() else if (age >= projectile.lifetime_ms or !alive(world, projectile.owner)) wisp.phase = .fading;
            if (fading or (wisp.phase == .active and age >= wisp.sine_ms)) {
                var heading = velocity;
                var distance: f32 = 200;
                if (wisp.enemy) |id| if (access.find(world, id)) |target| {
                    const position = (try target.get(data.Transform)).position;
                    const body = (try target.get(data.Body)).*;
                    distance = v.length(v.subtract(position, pose.position));
                    heading = v.subtract(v.add(position, body.maxs), pose.position);
                };
                velocity = wisp.steer(heading, distance, &random);
            }
        }
        if (remove) {
            try @import("events.zig").soundOwned(world, slots, projections, motion.owner, W.spec.audio.away.?, pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        if (v.length(velocity) > 0) pose.angles = .{ -std.math.atan2(velocity[2], @sqrt(velocity[0] * velocity[0] + velocity[1] * velocity[1])) * (180.0 / std.math.pi), std.math.atan2(velocity[1], velocity[0]) * (180.0 / std.math.pi), 0 };
        projectile.flight.wyndrax = wisp;
        projectile.stepped_ms = now;
        (try world.get(entity, data.Projectile)).* = projectile;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = velocity;
        (try world.get(entity, data.Random)).* = random;
        try @import("projectiles.zig").publish(world, entity, projections, now);
        try motion.finish(world, entity, now);
    }
}
