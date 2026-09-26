// SPDX-License-Identifier: GPL-2.0-or-later
//! Returning projectile collision and inventory transfer. The class owns steering clocks.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("weapon_catalog");
const W = catalog.discus;
const v = @import("../domain/vector.zig");
const c = abi.c;
const remove = @import("weapon_entities.zig").remove;
fn trace(start: v.Vec3, end: v.Vec3, skip: u16, boxed: bool) !@import("../domain/collision.zig").Trace {
    return engine.collisionService().trace(.{ .start = start, .end = end, .mins = if (boxed) W.spec.projectile.mins else @splat(0), .maxs = if (boxed) W.spec.projectile.maxs else @splat(0), .slot = skip, .mask = if (boxed) c.MASK_SHOT else c.MASK_SOLID });
}
fn catchDisc(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, collector: ecs.Entity, table: *const @import("../domain/weapons.zig").Table, now: i64) !void {
    const loadout = try world.get(collector, data.Weapons);
    const selected = loadout.weapon;
    _ = loadout.acquire(table, W.id, 1);
    // A returned disc must not interrupt another selected weapon.
    if (selected != 0 and selected != W.id) loadout.weapon = selected;
    const position = (try world.get(collector, data.Transform)).position;
    const slot = (try world.get(collector, data.Binding)).slot;
    const selected_after = loadout.weapon;
    try remove(world, slots, projections, entity);
    try @import("events.zig").sound(world, slots, projections, W.catch_sound, position, slot, c.CHAN_ITEM, now);
    if (selected_after != selected) {
        var command: [48]u8 = undefined;
        engine.send(slot, try std.fmt.bufPrintZ(&command, "dk3_weapon {d}", .{selected_after}));
    }
    if (engine.integer("developer") > 0) engine.print("dk3 zig discus: caught\n");
}
fn selectTarget(world: *data.World, slots: *Slots, owner: u32, slot: u16, position: v.Vec3, direction: v.Vec3) !?u32 {
    var best: f32 = 0.5;
    var result: ?u32 = null;
    for (slots.occupants, 0..) |occupant, index| {
        const target = occupant orelse continue;
        const id = try world.persistentId(target);
        if (id == owner) continue;
        const health = world.get(target, data.Health) catch continue;
        if (health.current <= 0) continue;
        if (engine.integer("g_gametype") == c.GT_SINGLE_PLAYER and (world.get(target, data.Player) catch null) != null) continue;
        const goal = @import("area_damage.zig").center(world, target) catch continue;
        const delta = v.subtract(goal, position);
        if (v.length(delta) > 2000) continue;
        const deviation = v.subtract(direction, v.normalize(delta));
        const score = @abs(deviation[0]) + @abs(deviation[1]);
        if (@abs(deviation[0]) >= 0.25 or @abs(deviation[1]) >= 0.25 or score >= best) continue;
        const visible = try trace(position, goal, slot, false);
        if (visible.fraction < 1 and visible.entity != index) continue;
        best = score;
        result = id;
    }
    return result;
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, table: *const @import("../domain/weapons.zig").Table, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.flight != .discus) continue;
        const owner = world.find(projectile.owner) orelse {
            try remove(world, slots, projections, entity);
            continue;
        };
        if ((try world.get(owner, data.Health)).current <= 0 or now >= (try world.get(entity, data.Lifetime)).expires_ms) {
            try remove(world, slots, projections, entity);
            continue;
        }
        const owner_position = (try world.get(owner, data.Transform)).position;
        const slot = (try world.get(entity, data.Binding)).slot;
        const owner_slot = (try world.get(owner, data.Binding)).slot;
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        var disc = projectile.flight.discus;
        var at = projectile.stepped_ms;
        while (at < now) {
            const milliseconds: u32 = @intCast(@min(20, now - at));
            const seconds = @as(f32, @floatFromInt(milliseconds)) * 0.001;
            const age = at - projectile.born_ms;
            projectile.wet = (try engine.collisionService().contents(pose.position, slot)) & c.MASK_WATER != 0;
            if (disc.tick(age, projectile.wet)) {
                if (disc.dropped) {
                    const visible = try trace(pose.position, owner_position, slot, false);
                    if (visible.fraction == 1 or visible.entity == owner_slot) {
                        disc.dropped = false;
                        disc.speed = disc.base_speed;
                        disc.home(v.subtract(owner_position, pose.position), true);
                        velocity = v.scale(disc.forward, disc.speed);
                    }
                } else if (disc.mustDrop(age)) {
                    disc.drop(projectile.owner, age);
                    velocity[2] = 60;
                } else {
                    if ((disc.reflected or (disc.seek and disc.target == projectile.owner)) and v.length(v.subtract(pose.position, owner_position)) < 100) {
                        try catchDisc(world, slots, projections, entity, owner, table, now);
                        break;
                    }
                    if (disc.target) |id| {
                        const target = world.find(id);
                        if (target == null or (world.get(target.?, data.Health) catch null) == null or (try world.get(target.?, data.Health)).current <= 0) disc.target = projectile.owner;
                    }
                    if (disc.seek) {
                        if (disc.target) |id| {
                            if (world.find(id)) |target| disc.home(v.subtract(try @import("area_damage.zig").center(world, target), pose.position), id == projectile.owner);
                        } else disc.target = try selectTarget(world, slots, projectile.owner, slot, pose.position, disc.forward);
                    }
                    velocity = v.scale(disc.forward, disc.speed);
                }
            }
            // Dropped discs remain ordinary touch pickups, including after resuming flight.
            if (disc.pickup_only) {
                for (slots.occupants[0..Slots.clients]) |client| {
                    const target = client orelse continue;
                    if ((try world.get(target, data.Health)).current <= 0) continue;
                    const position = (try world.get(target, data.Transform)).position;
                    const body = (try world.get(target, data.Body)).*;
                    var overlaps = true;
                    for (0..3) |axis| if (pose.position[axis] + W.spec.projectile.maxs[axis] < position[axis] + body.mins[axis] or pose.position[axis] + W.spec.projectile.mins[axis] > position[axis] + body.maxs[axis]) {
                        overlaps = false;
                        break;
                    };
                    if (overlaps) {
                        try catchDisc(world, slots, projections, entity, target, table, now);
                        break;
                    }
                }
                if (!world.alive(entity)) break;
            }
            const gravity: f32 = if (disc.dropped) 800 else 0;
            const goal = v.add(v.add(pose.position, v.scale(velocity, seconds)), .{ 0, 0, -0.5 * gravity * seconds * seconds });
            velocity[2] -= gravity * seconds;
            const hit = try trace(pose.position, goal, if (disc.reflected) c.ENTITYNUM_NONE else owner_slot, true);
            pose.position = hit.end;
            at += milliseconds;
            if (hit.sky or hit.no_impact) {
                try remove(world, slots, projections, entity);
                break;
            }
            if (hit.fraction == 1) continue;
            const target = if (hit.entity < slots.occupants.len) slots.occupants[hit.entity] else null;
            if (target) |who| if ((world.get(who, data.Player) catch null) != null and (try world.get(who, data.Health)).current > 0 and (disc.pickup_only or try world.persistentId(who) == projectile.owner)) {
                try catchDisc(world, slots, projections, entity, who, table, now);
                break;
            };
            if (disc.dropped) {
                velocity = @import("../domain/combat.zig").reflect(velocity, hit.normal, 0.6);
                if (hit.normal[2] > 0.7 and @abs(velocity[2]) < 30) velocity = @splat(0);
                pose.position = v.add(pose.position, v.scale(hit.normal, 0.5));
                continue;
            }
            disc.seek = !(disc.target != null and disc.seek);
            disc.target = projectile.owner;
            var back_to_owner = false;
            var living = false;
            if (target) |who| {
                living = (world.get(who, data.Actor) catch null) != null or (world.get(who, data.Player) catch null) != null;
                if (!disc.pickup_only and disc.clear == 0 and (world.get(who, data.Health) catch null) != null) {
                    disc.clear = 3;
                    const protected = disc.reflected and engine.integer("g_gametype") == c.GT_SINGLE_PLAYER and (world.get(who, data.Player) catch null) != null;
                    if (!protected and try @import("weapon_damage.zig").hurt(world, who, projectile.owner, W.id, projectile.damage, now, false)) try @import("weapon_damage.zig").shove(world, who, projectile.owner, velocity, projectile.damage, now);
                    back_to_owner = projections[hit.entity].shared.bmodel != 0 or (try world.get(who, data.Health)).current <= 0;
                }
            }
            try @import("impacts.zig").contact(world, slots, projections, W.id, hit, .{}, now);
            if (back_to_owner) {
                disc.seek = true;
                disc.home(v.subtract(owner_position, pose.position), true);
                pose.position = v.add(pose.position, v.scale(disc.forward, 15));
            } else if (living) {
                const home_trace = try trace(pose.position, owner_position, c.ENTITYNUM_NONE, true);
                if (home_trace.entity == hit.entity) {
                    disc.seek = false;
                    disc.target = null;
                    var random = (try world.get(entity, data.Random)).*;
                    var normal = hit.normal;
                    for (0..2) |axis| normal[axis] += (if (random.next() < 0.5) @as(f32, -1) else 1) * (0.1 + 0.2 * random.next());
                    (try world.get(entity, data.Random)).* = random;
                    disc.forward = @import("../domain/combat.zig").reflect(disc.forward, v.normalize(normal), 1);
                } else disc.home(v.subtract(owner_position, pose.position), true);
            } else disc.forward = @import("../domain/combat.zig").reflect(disc.forward, hit.normal, 1);
            disc.reflected = true;
            velocity = v.scale(disc.forward, disc.speed);
            pose.position = v.add(pose.position, v.scale(hit.normal, 0.5));
        }
        if (!world.alive(entity)) continue;
        projectile.flight.discus = disc;
        projectile.resting = disc.dropped;
        projectile.stepped_ms = now;
        if (v.length(velocity) > 1) {
            pose.angles[0] = -std.math.atan2(velocity[2], @sqrt(velocity[0] * velocity[0] + velocity[1] * velocity[1])) * (180.0 / std.math.pi);
            pose.angles[1] = std.math.atan2(velocity[1], velocity[0]) * (180.0 / std.math.pi);
        }
        (try world.get(entity, data.Projectile)).* = projectile;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = velocity;
        try @import("projectiles.zig").publish(world, entity, projections, now);
    }
}
