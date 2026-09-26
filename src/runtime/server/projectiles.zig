// SPDX-License-Identifier: GPL-2.0-or-later
//! Authoritative projectile lifecycle and collision; pure classes own flight/contact policy.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("weapon_catalog");
const weapons = @import("../domain/weapons.zig");
const rules = @import("../domain/combat.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;
const damage = @import("weapon_damage.zig");
fn trace(start: v.Vec3, end: v.Vec3, skip: u16, radius: f32, mask: u32) !@import("../domain/collision.zig").Trace {
    return engine.collisionService().trace(.{ .start = start, .end = end, .mins = @splat(-radius), .maxs = @splat(radius), .slot = skip, .mask = mask });
}
fn victim(slots: *const Slots, slot: u16) ?ecs.Entity {
    return if (slot < slots.occupants.len) slots.occupants[slot] else null;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const binding = (try world.get(entity, data.Binding)).*;
    const transform = (try world.get(entity, data.Transform)).*;
    const velocity = (try world.get(entity, data.Velocity)).linear;
    const projectile = (try world.get(entity, data.Projectile)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_MISSILE;
    projection.state.weapon = projectile.weapon;
    projection.state.time = @intCast(projectile.born_ms);
    projection.state.generic1 = @intFromBool(projectile.stuck);
    projection.state.generic1 |= @as(i32, @intFromBool(projectile.resting)) << 1;
    projection.state.time2 = if (world.get(entity, data.Lifetime) catch null) |lifetime| @intCast(lifetime.expires_ms) else 0;
    projection.state.modelindex = binding.model;
    projection.state.pos = @import("../engine/trajectory.zig").linear(transform.position, velocity, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(transform.angles);
    projection.shared.currentOrigin = transform.position;
    const spec = catalog.find(projectile.weapon).?.spec;
    projection.shared.mins = if (spec.combat == .ion) @splat(-spec.combat.ion.radius) else spec.projectile.mins;
    projection.shared.maxs = if (spec.combat == .ion) @splat(spec.combat.ion.radius) else spec.projectile.maxs;
    projection.shared.contents = 0;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}
fn remove(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity) !void {
    const slot = (try world.get(entity, data.Binding)).slot;
    engine.unlink(&projections[slot]);
    try slots.release(slot, entity);
    try world.destroy(entity);
}
fn splash(world: *data.World, slots: *Slots, projectile: data.Projectile, position: v.Vec3, skip: u16, now: i64) !void {
    for (slots.occupants, 0..) |occupant, index| {
        const target = occupant orelse continue;
        _ = world.get(target, data.Health) catch continue;
        const target_position = (try world.get(target, data.Transform)).position;
        const owner = try world.persistentId(target) == projectile.owner;
        const distance = v.length(v.add(target_position, v.scale(position, -1)));
        const amount = rules.radiusDamage(projectile.damage, distance, catalog.find(projectile.weapon).?.spec.combat.ion.water_radius, owner, projectile.bounces != 0);
        if (amount <= 0) continue;
        const hit = try trace(position, target_position, skip, 0, c.MASK_SOLID);
        if (hit.fraction < 1 and hit.entity != index) continue;
        _ = try damage.hurt(world, target, projectile.owner, projectile.weapon, amount, now, true);
    }
}
fn stepIon(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (catalog.find(projectile.weapon).?.spec.combat != .ion) continue;
        const binding = (try world.get(entity, data.Binding)).*;
        const policy = catalog.find(projectile.weapon).?.spec.combat.ion;
        if (now - projectile.born_ms > policy.cleanup_ms) {
            try remove(world, slots, projections, entity);
            continue;
        }
        var position = (try world.get(entity, data.Transform)).position;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        var remaining: f32 = @as(f32, @floatFromInt(@max(0, now - projectile.stepped_ms))) * 0.001;
        var destroyed = false;
        while (remaining > 0) {
            const skip: u16 = if (projectile.bounces == 0) (if (world.find(projectile.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE) else c.ENTITYNUM_NONE;
            const hit = try trace(position, v.add(position, v.scale(velocity, remaining)), skip, policy.radius, c.MASK_SHOT | c.MASK_WATER);
            position = hit.end;
            const wet = hit.contents & c.MASK_WATER != 0 or (try engine.collisionService().contents(position, binding.slot)) & c.MASK_WATER != 0;
            if (hit.sky) {
                try remove(world, slots, projections, entity);
                destroyed = false;
                break;
            }
            if (wet) {
                try splash(world, slots, projectile, position, binding.slot, now);
                try @import("events.zig").impact(world, slots, projections, .{ .weapon = projectile.weapon, .kind = .water, .normal = v.scale(v.normalize(velocity), -1) }, position, now);
                destroyed = true;
                break;
            }
            if (hit.fraction == 1) break;
            try @import("impacts.zig").contact(world, slots, projections, projectile.weapon, hit, .{}, now);
            if (victim(slots, hit.entity)) |target| {
                if (world.get(target, data.Health)) |_| {
                    _ = try damage.hurt(world, target, projectile.owner, projectile.weapon, projectile.damage * (if (try world.persistentId(target) == projectile.owner) @as(f32, 0.5) else 1), now, true);
                    destroyed = true;
                    break;
                } else |_| {}
            }
            projectile.bounces += 1;
            if (projectile.bounces >= policy.max_bounces or hit.all_solid) {
                destroyed = true;
                break;
            }
            velocity = rules.reflect(velocity, hit.normal, policy.bounce_retention);
            position = v.add(position, hit.normal);
            remaining *= 1 - hit.fraction;
        }
        if (!world.alive(entity)) continue;
        if (destroyed) {
            // Copy all state before structural changes from transient presentation events.
            try remove(world, slots, projections, entity);
        } else {
            projectile.stepped_ms = now;
            (try world.get(entity, data.Projectile)).* = projectile;
            (try world.get(entity, data.Transform)).position = position;
            (try world.get(entity, data.Velocity)).linear = velocity;
            try publish(world, entity, projections, now);
        }
    }
}

pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const spec = catalog.find(shot.weapon).?.spec;
    const tuning = table.entries[shot.weapon];
    const owner_id = try world.persistentId(owner);
    const owner_slot = (try world.get(owner, data.Binding)).slot;
    const attack: u8 = if (world.get(owner, data.Character) catch null) |character| @intCast(character.attribute(.attack, now)) else 0;
    const launch_pose = catalog.flightLaunch(shot.weapon, tuning, shot.sequence, attack);
    const eye = rules.eye(shot.position, shot.view_height);
    const start = (try engine.collisionService().trace(.{ .start = eye, .end = rules.muzzle(eye, shot.angles, launch_pose.muzzle), .mins = spec.projectile.mins, .maxs = spec.projectile.maxs, .slot = owner_slot, .mask = c.MASK_SHOT })).end;
    var angles = shot.angles;
    angles[0] += launch_pose.pitch;
    const forward = v.basis(angles).forward;
    const target = (try trace(eye, v.add(eye, v.scale(forward, spec.projectile.aim_range)), owner_slot, 0, c.MASK_SHOT)).end;
    const speed = (if (tuning.speed > 0) tuning.speed else 400) * (1 + 0.3 * @as(f32, @floatFromInt(attack)));
    var projectile: data.Projectile = .{ .owner = owner_id, .weapon = shot.weapon, .damage = tuning.damage, .born_ms = now, .stepped_ms = now, .flight = try catalog.flightState(shot.weapon), .launch_position = start, .speed = speed };
    projectile.wet = (try engine.collisionService().contents(start, owner_slot)) & c.MASK_WATER != 0;
    const initial = try catalog.flightMotion(shot.weapon, &projectile.flight, .{ .age_ms = 0, .delta_ms = 0, .distance = 0, .wet = projectile.wet, .was_wet = false, .velocity = v.scale(rules.aim(start, target, forward), speed), .speed = speed });
    const lifetime: i64 = if (spec.projectile.lifetime_ms != 0) spec.projectile.lifetime_ms else @intFromFloat(std.math.clamp((if (tuning.lifetime > 0) tuning.lifetime * 1000 else 5000) * spec.projectile.lifetime_scale, 1, 3600000));
    projectile.lifetime_ms = lifetime;
    const model = try @import("resources.zig").model(spec.visual.projectile_model);
    angles[2] = launch_pose.roll;
    const entity = try world.create(null, .{ data.Transform{ .position = start, .angles = angles }, data.Velocity{ .linear = initial.velocity }, projectile, data.Lifetime{ .expires_ms = now + lifetime } });
    errdefer world.destroy(entity) catch unreachable;
    const slot = try slots.acquire(entity, null);
    errdefer slots.release(slot, entity) catch unreachable;
    try world.put(entity, data.Binding{ .slot = slot, .model = model });
    projections[slot] = std.mem.zeroes(abi.EntityProjection);
    try publish(world, entity, projections, now);
}

fn explode(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, projectile: data.Projectile, hit: @import("../domain/collision.zig").Trace, now: i64) !void {
    const spec = catalog.find(projectile.weapon).?.spec;
    const skip = (try world.get(entity, data.Binding)).slot;
    for (slots.occupants, 0..) |occupant, index| {
        const target = occupant orelse continue;
        const health = world.get(target, data.Health) catch continue;
        if (health.current <= 0) continue;
        const body = (try world.get(target, data.Body)).*;
        const origin = (try world.get(target, data.Transform)).position;
        const center = v.add(origin, v.scale(v.add(body.mins, body.maxs), 0.5));
        const distance = v.length(v.subtract(center, hit.end));
        const owner = try world.persistentId(target) == projectile.owner;
        const amount = rules.radiusDamage(projectile.damage * spec.projectile.splash_scale, distance, spec.projectile.splash_radius, false, false) * (if (owner) spec.projectile.self_splash else 1);
        if (amount <= 0) continue;
        const visible = try trace(hit.end, center, skip, 0, c.MASK_SOLID);
        if (visible.fraction < 1 and visible.entity != index) continue;
        _ = try damage.hurt(world, target, projectile.owner, projectile.weapon, amount, now, false);
    }
    try @import("impacts.zig").contact(world, slots, projections, projectile.weapon, hit, .{ .detonation = true }, now);
    if (engine.integer("developer") > 0) {
        var message: [144]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig projectile: weapon={d} exploded age={d} bounces={d}\n", .{ projectile.weapon, now - projectile.born_ms, projectile.bounces }));
    }
    try remove(world, slots, projections, entity);
}

fn directHit(world: *data.World, target: ecs.Entity, projectile: data.Projectile, velocity: v.Vec3, now: i64) !void {
    const object = world.get(target, data.MapObject) catch null;
    const hit = catalog.flightDamage(projectile.weapon, .{ .damage = projectile.damage, .age_ms = now - projectile.born_ms, .lifetime_ms = projectile.lifetime_ms, .self_hit = try world.persistentId(target) == projectile.owner, .victim_class = if (object) |value| value.classname else "" });
    if (try damage.hurt(world, target, projectile.owner, projectile.weapon, hit.amount, now, false)) {
        if (catalog.find(projectile.weapon).?.spec.projectile.inertial) try damage.shove(world, target, projectile.owner, velocity, hit.amount, now);
        try @import("ailments.zig").apply(world, target, hit.effect, projectile.owner, projectile.weapon, now);
    }
}
fn restingContact(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, projectile: data.Projectile, position: v.Vec3, now: i64) !bool {
    const bounds = catalog.find(projectile.weapon).?.spec.projectile;
    for (slots.occupants, 0..) |occupant, slot| {
        const target = occupant orelse continue;
        const health = world.get(target, data.Health) catch continue;
        if (health.current <= 0) continue;
        if ((world.get(target, data.Actor) catch null) == null and (world.get(target, data.Player) catch null) == null) continue;
        const pose = (try world.get(target, data.Transform)).*;
        const body = (try world.get(target, data.Body)).*;
        var overlaps = true;
        for (0..3) |axis| if (position[axis] + bounds.maxs[axis] < pose.position[axis] + body.mins[axis] or position[axis] + bounds.mins[axis] > pose.position[axis] + body.maxs[axis]) {
            overlaps = false;
            break;
        };
        if (!overlaps) continue;
        const visible = try trace(position, v.add(pose.position, v.scale(v.add(body.mins, body.maxs), 0.5)), (try world.get(entity, data.Binding)).slot, 0, c.MASK_SOLID);
        if (visible.fraction < 1 and visible.entity != slot) continue;
        try directHit(world, target, projectile, @splat(0), now);
        try @import("events.zig").impact(world, slots, projections, .{ .weapon = projectile.weapon, .kind = .flesh, .normal = .{ 0, 0, 1 } }, position, now);
        try remove(world, slots, projections, entity);
        return true;
    }
    return false;
}

pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    try stepIon(world, slots, projections, now);
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        const spec = catalog.find(projectile.weapon).?.spec;
        if (spec.combat != .projectile) continue;
        const binding = (try world.get(entity, data.Binding)).*;
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        const expires = (try world.get(entity, data.Lifetime)).expires_ms;
        if (now >= expires) {
            if (!projectile.stuck and spec.projectile.splash_scale > 0) try explode(world, slots, projections, entity, projectile, .{ .fraction = 0, .end = pose.position, .normal = .{ 0, 0, 1 }, .entity = c.ENTITYNUM_NONE, .contents = if (projectile.wet) c.MASK_WATER else 0 }, now) else try remove(world, slots, projections, entity);
            continue;
        }
        if (projectile.stuck) continue;
        if (projectile.resting) {
            if (spec.projectile.remove_when_resting) try remove(world, slots, projections, entity) else if (spec.projectile.contact_when_resting) {
                _ = try restingContact(world, slots, projections, entity, projectile, pose.position, now);
            }
            continue;
        }
        var at = projectile.stepped_ms;
        while (at < now) {
            const milliseconds: u32 = @intCast(@min(20, now - at));
            const seconds = @as(f32, @floatFromInt(milliseconds)) * 0.001;
            const wet = (try engine.collisionService().contents(pose.position, binding.slot)) & c.MASK_WATER != 0;
            const motion = try catalog.flightMotion(projectile.weapon, &projectile.flight, .{ .age_ms = at - projectile.born_ms, .delta_ms = milliseconds, .distance = v.length(v.subtract(pose.position, projectile.launch_position)), .wet = wet, .was_wet = projectile.wet, .velocity = velocity, .speed = projectile.speed });
            if (motion.remove) {
                if (wet) try @import("events.zig").impact(world, slots, projections, .{ .weapon = projectile.weapon, .kind = .water, .normal = .{ 0, 0, 1 } }, pose.position, now);
                try remove(world, slots, projections, entity);
                break;
            }
            projectile.wet = wet;
            velocity = motion.velocity;
            const goal = v.add(v.add(pose.position, v.scale(velocity, seconds)), .{ 0, 0, -0.5 * motion.gravity * seconds * seconds });
            velocity[2] -= motion.gravity * seconds;
            const skip: u16 = if (spec.projectile.collide_owner_after_bounce and projectile.bounces != 0) c.ENTITYNUM_NONE else if (world.find(projectile.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = goal, .mins = spec.projectile.mins, .maxs = spec.projectile.maxs, .slot = skip, .mask = c.MASK_SHOT });
            pose.position = hit.end;
            at += milliseconds;
            if (hit.sky or hit.no_impact) {
                try remove(world, slots, projections, entity);
                break;
            }
            if (hit.fraction == 1) continue;
            const target = victim(slots, hit.entity);
            const damageable = if (target) |who| (world.get(who, data.Health) catch null) != null else false;
            const living = if (target) |who| (world.get(who, data.Actor) catch null) != null or (world.get(who, data.Player) catch null) != null else false;
            const brush = hit.entity < projections.len and projections[hit.entity].shared.bmodel != 0;
            const response = try catalog.flightContact(projectile.weapon, .{ .damageable = damageable, .living = living, .brush = brush });
            if (response == .explode) {
                try explode(world, slots, projections, entity, projectile, hit, now);
                break;
            }
            try @import("impacts.zig").contact(world, slots, projections, projectile.weapon, hit, .{}, now);
            switch (response) {
                .direct => {
                    if (target) |who| try directHit(world, who, projectile, velocity, now);
                    try remove(world, slots, projections, entity);
                    break;
                },
                .remove => {
                    try remove(world, slots, projections, entity);
                    break;
                },
                .stick => |duration| {
                    projectile.stuck = true;
                    velocity = @splat(0);
                    (try world.get(entity, data.Lifetime)).expires_ms = now + duration;
                    break;
                },
                .bounce => |retention| {
                    projectile.bounces +|= 1;
                    velocity = rules.reflect(velocity, hit.normal, retention);
                    pose.position = v.add(pose.position, v.scale(hit.normal, 0.5));
                    if (hit.normal[2] > 0.7 and @abs(velocity[2]) < 30) {
                        velocity = @splat(0);
                        projectile.resting = true;
                        if (spec.projectile.resting_lifetime_scale > 0) (try world.get(entity, data.Lifetime)).expires_ms = now + @as(i64, @intFromFloat(@as(f32, @floatFromInt(projectile.lifetime_ms)) * spec.projectile.resting_lifetime_scale));
                        break;
                    }
                },
                .explode => unreachable,
            }
        }
        if (!world.alive(entity)) continue;
        projectile.stepped_ms = now;
        if (v.length(velocity) > 1) {
            pose.angles[0] = -std.math.atan2(velocity[2], @sqrt(velocity[0] * velocity[0] + velocity[1] * velocity[1])) * (180.0 / std.math.pi);
            pose.angles[1] = std.math.atan2(velocity[1], velocity[0]) * (180.0 / std.math.pi);
        }
        (try world.get(entity, data.Projectile)).* = projectile;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = velocity;
        try publish(world, entity, projections, now);
    }
}
