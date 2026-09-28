// SPDX-License-Identifier: GPL-2.0-or-later
//! Shootable thrown cubes: settle, arm, retain targets, acquire locks, then discharge.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const access = @import("region_access.zig");
const geometry = @import("region_collision.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").metamaser;
const weapons = @import("../domain/weapons.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;
const entities = @import("weapon_entities.zig");
pub fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, name: [:0]const u8, now: i64) !void {
    try @import("events.zig").sound(world, slots, projections, name, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const projectile = (try world.get(entity, data.Projectile)).*;
    const cube = projectile.flight.metamaser;
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_MISSILE;
    projection.state.weapon = W.id;
    projection.state.modelindex = binding.model;
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.state.time = @intCast(projectile.born_ms);
    projection.state.time2 = @intCast(projectile.born_ms + cube.pause_ms);
    projection.state.generic1 = @intFromEnum(cube.phase);
    projection.state.angles2[0] = @floatFromInt(cube.bursts);
    var targets: [4]i32 = @splat(c.ENTITYNUM_NONE);
    if (cube.phase == .tracking and now >= projectile.born_ms + cube.pause_ms) for (cube.acquired, &targets) |lock, *slot| {
        if (world.find(lock.target)) |target| slot.* = (try world.get(target, data.Binding)).slot;
    };
    projection.state.otherEntityNum = targets[0];
    projection.state.otherEntityNum2 = targets[1];
    projection.state.origin2 = .{ @floatFromInt(targets[2]), @floatFromInt(targets[3]), 0 };
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = @bitCast(body.contents);
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const tuning = table.entries[W.id];
    const rules = @import("../domain/combat.zig");
    const eye = rules.eye(shot.position, shot.view_height);
    const forward = v.basis(shot.angles).forward;
    const skip = (try world.get(owner, data.Binding)).slot;
    const owner_id = try world.persistentId(owner);
    var motion = @import("region_motion.zig").Cursor.init(world, owner_id);
    const start = (try motion.trace(.{ .start = eye, .end = rules.muzzle(eye, shot.angles, tuning.muzzle), .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = skip, .mask = c.MASK_SOLID })).end;
    const target = (try geometry.owned(world, .{ .start = eye, .end = v.add(eye, v.scale(forward, 2000)), .mins = @splat(0), .maxs = @splat(0), .slot = skip, .mask = c.MASK_SHOT }, owner_id)).end;
    const speed = 800 * (1 + 0.3 * @as(f32, @floatFromInt((try world.get(owner, data.Character)).attribute(.attack, now))));
    const cube: W.BallisticState = .{ .charges = tuning.cube_charges, .end_ms = tuning.cube_lifetime_ms, .range = if (tuning.range == 0) 512 else tuning.range };
    const entity = try world.create(null, .{
        data.Transform{ .position = start, .angles = shot.angles },                                                                               data.Velocity{ .linear = v.scale(rules.aim(start, target, forward), speed) },
        data.Body{ .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .contents = c.CONTENTS_BODY, .collision_mask = c.MASK_SOLID }, data.Health{ .current = tuning.cube_health, .maximum = tuning.cube_health },
        data.Hurt{},                                                                                                                              data.Projectile{ .owner = owner_id, .weapon = W.id, .damage = tuning.damage, .born_ms = now, .stepped_ms = now, .flight = .{ .metamaser = cube }, .launch_position = start, .speed = speed, .lifetime_ms = tuning.cube_lifetime_ms },
        data.Random{ .state = owner_id ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) ^ 0x619b76e3 },                                             data.Lifetime{ .expires_ms = now + tuning.cube_lifetime_ms + 5000 },
    });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, W.spec.visual.projectile_model);
    try publish(world, entity, projections, now);
    try motion.finish(world, entity, now);
}
fn valid(target: Ref) bool {
    if ((target.get(data.Health) catch return false).current <= 0) return false;
    return (target.get(data.Actor) catch null) != null or (target.get(data.Player) catch null) != null;
}
fn visible(world: *data.World, owner: u32, origin: v.Vec3, skip: u32, target: Ref) !bool {
    const hit = try geometry.from(owner, .{ .start = origin, .end = (try target.get(data.Transform)).position, .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SOLID }, skip);
    return geometry.reaches(world, hit, target);
}
fn track(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, projectile: data.Projectile, cube: *W.BallisticState, random: *data.Random, owner: u32, now: i64) !void {
    const age = now - projectile.born_ms;
    if (age < cube.pause_ms) return;
    const position = (try world.get(entity, data.Transform)).position;
    const skip = try world.persistentId(entity);
    // Restore/prune before acquisition so stale persistent references never consume capacity.
    const retained = cube.targets;
    for (retained) |target| {
        if (target.target == 0) continue;
        const candidate = access.find(world, target.target) orelse {
            cube.forget(target.target);
            continue;
        };
        if (age >= target.until_ms or !valid(candidate) or !try visible(world, owner, position, skip, candidate)) cube.forget(target.target);
    }
    var candidates = access.Damageables.init(world, slots);
    while (candidates.next()) |target| {
        if (!valid(target) or v.length(v.subtract((try target.get(data.Transform)).position, position)) > cube.range or !try visible(world, owner, position, skip, target)) continue;
        _ = cube.include(try target.id(), age);
    }
    // Same bounded random search and four simultaneous locks; no synthetic target fallback.
    for (0..4) |_| {
        for (0..50) |_| {
            const candidate = cube.targets[@min(11, @as(usize, @intFromFloat(random.next() * 12)))].target;
            if (candidate != 0) {
                _ = cube.lock(candidate, age, random.next());
                break;
            }
        }
    }
    for (0..cube.acquired.len) |index| {
        var lock = cube.acquired[index];
        if (lock.target == 0) continue;
        if (age >= lock.until_ms) {
            cube.forget(lock.target);
            continue;
        }
        const target = access.find(world, lock.target) orelse {
            cube.forget(lock.target);
            continue;
        };
        const end = (try target.get(data.Transform)).position;
        const hit = try geometry.from(owner, .{ .start = position, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SHOT }, skip);
        const contact = access.victim(world, slots, hit) orelse continue;
        if (!contact.same(target)) continue;
        const interval: i64 = 250 + @as(i64, @intFromFloat(250 * random.next()));
        if (age >= lock.sound_ms) {
            try @import("events.zig").soundOwned(world, slots, projections, owner, W.sounds.small[@min(1, @as(usize, @intFromFloat(random.next() * 2)))], position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
            lock.sound_ms = age + interval;
        }
        if (age >= lock.damage_ms) {
            if (cube.charges == 0) {
                cube.die(age);
                return;
            }
            cube.charges -= 1;
            _ = try @import("weapon_damage.zig").hurt(target.world, target.entity, projectile.owner, W.id, projectile.damage, now, false);
            lock.damage_ms = age + interval;
        }
        cube.acquired[index] = lock;
    }
}
fn deployed(world: *data.World) usize {
    var count = localDeployed(world);
    if (access.contextFor(world)) |context| {
        var neighbors = access.Neighbors.init(context);
        while (neighbors.next()) |neighbor| if (&neighbor.world.? != world) {
            count += localDeployed(&neighbor.world.?);
        };
    }
    return count;
}
fn localDeployed(world: *data.World) usize {
    var query = world.queryAccess(data.World.mask(.{data.Projectile}), 0, 0);
    defer query.deinit();
    var count: usize = 0;
    while (query.next()) |view| for (view.read(data.Projectile)) |projectile| if (projectile.flight == .metamaser) {
        count += 1;
    };
    return count;
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    try @import("metamaser_death.zig").step(world, slots, projections, now);
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.flight != .metamaser or now <= projectile.stepped_ms) continue;
        var motion = @import("region_motion.zig").Cursor.init(world, try world.persistentId(entity));
        var cube = projectile.flight.metamaser;
        var random = (try world.get(entity, data.Random)).*;
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        const binding = (try world.get(entity, data.Binding)).*;
        const age = now - projectile.born_ms;
        var at = projectile.stepped_ms;
        while (!cube.settled and at < now) {
            const milliseconds = @min(20, now - at);
            const seconds = @as(f32, @floatFromInt(milliseconds)) * 0.001;
            const goal = v.add(v.add(pose.position, v.scale(velocity, seconds)), .{ 0, 0, -400 * seconds * seconds });
            velocity[2] -= 800 * seconds;
            const hit = try motion.trace(.{ .start = pose.position, .end = goal, .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = binding.slot, .mask = c.MASK_SOLID });
            pose.position = hit.end;
            at += milliseconds;
            if (hit.fraction < 1) {
                velocity = v.subtract(velocity, v.scale(hit.normal, v.dot(velocity, hit.normal)));
                if (hit.normal[2] > 0.7 and velocity[2] < 60) {
                    velocity = @splat(0);
                    cube.settled = true;
                }
                pose.position = v.add(pose.position, v.scale(hit.normal, 0.1));
            }
        }
        (try world.get(entity, data.Transform)).* = pose;
        const health = (try world.get(entity, data.Health)).current;
        const hurt = (try world.get(entity, data.Hurt)).*;
        if (cube.phase != .dying and health <= 0) cube.die(age);
        if (cube.phase != .dying and hurt.revision != cube.receipt) {
            cube.receipt = hurt.revision;
            if (health <= cube.pain_level) {
                cube.pain_level = health - 300;
                cube.pause_ms = age + 1500;
            }
        }
        if (age >= cube.next_ms) {
            cube.next_ms = age + 100;
            if (cube.phase == .flight and v.length(velocity) < 10) {
                cube.settle(age);
                pose.angles = @splat(0);
                velocity = @splat(0);
            }
            if (cube.phase != .dying and (age >= cube.end_ms or (cube.phase != .flight and (cube.charges == 0 or deployed(world) >= 3)))) cube.die(age);
            switch (cube.phase) {
                .flight => {},
                .arming => {
                    if (age > cube.beep_ms) {
                        try @import("events.zig").soundOwned(world, slots, projections, motion.owner, W.sounds.beep, pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
                        cube.beep_ms = age + 500;
                    }
                    if (age > cube.arm_ms) cube.phase = .tracking;
                },
                .tracking => try track(world, slots, projections, entity, projectile, &cube, &random, motion.owner, now),
                .dying => if (age >= cube.burst_ms and age <= cube.end_ms and health >= -20000) {
                    cube.bursts +|= 1;
                    try @import("metamaser_death.zig").burstOwned(world, slots, projections, motion.owner, entity, projectile, &random, projectile.born_ms + cube.end_ms, now);
                    cube.burst_ms = age + 250 + @as(i64, @intFromFloat(750 * random.next()));
                },
            }
        }
        if (cube.phase == .dying and (age > cube.end_ms or health < -20000)) {
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        projectile.flight.metamaser = cube;
        projectile.stepped_ms = now;
        (try world.get(entity, data.Projectile)).* = projectile;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = velocity;
        (try world.get(entity, data.Random)).* = random;
        (try world.get(entity, data.Lifetime)).expires_ms = projectile.born_ms + cube.end_ms;
        try publish(world, entity, projections, now);
        try motion.finish(world, entity, now);
    }
}
