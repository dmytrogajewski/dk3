// SPDX-License-Identifier: GPL-2.0-or-later
//! Resolves copied fire intents after movement releases ECS component pointers.
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
fn trace(start: v.Vec3, end: v.Vec3, skip: u16, radius: f32, mask: u32) !@import("../domain/collision.zig").Trace {
    return engine.collisionService().trace(.{ .start = start, .end = end, .mins = @splat(-radius), .maxs = @splat(radius), .slot = skip, .mask = mask });
}
fn victim(slots: *const Slots, slot: u16) ?ecs.Entity {
    return if (slot < slots.occupants.len) slots.occupants[slot] else null;
}
fn hurt(world: *data.World, target: ecs.Entity, owner_id: u32, amount: f32, now: i64, bypass_armor: bool) !bool {
    const scaled = amount * try powerFactor(world, target, owner_id, now);
    if (!std.math.isFinite(scaled) or scaled <= 0) return false;
    const result = try @import("damage.zig").apply(world, target, @intFromFloat(@min(@ceil(scaled), 1000000)), now, .{ .bypass_armor = bypass_armor, .source = owner_id });
    if (engine.integer("developer") != 0 and (result.blood > 0 or result.armor > 0)) {
        var buffer: [160]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 zig combat: target={d} blood={d} armor={d} killed={d}\n", .{ try world.persistentId(target), result.blood, result.armor, @intFromBool(result.killed) }));
    }
    return result.blood > 0 or result.armor > 0;
}
fn powerFactor(world: *data.World, target: ecs.Entity, owner_id: u32, now: i64) !f32 {
    if (world.find(owner_id)) |owner| {
        if (try world.persistentId(target) != owner_id) {
            if (world.get(owner, data.Character)) |state| return catalog.character.powerFactor(state.attribute(.power, now)) else |_| {}
        }
    }
    return 1;
}
fn shove(world: *data.World, target: ecs.Entity, owner: u32, direction: v.Vec3, amount: f32, now: i64) !void {
    if ((world.get(target, data.Player) catch null) == null and (world.get(target, data.Actor) catch null) == null) return;
    if ((try world.get(target, data.Health)).current <= 0) return;
    const force = amount * try powerFactor(world, target, owner, now);
    const body = try world.get(target, data.Body);
    const kick = v.scale(v.add(v.scale(v.normalize(direction), force * 1.75), .{ 0, 0, force * 2 }), 100 / @max(100, body.mass));
    const velocity = try world.get(target, data.Velocity);
    velocity.linear = v.add(velocity.linear, kick);
    body.grounded = false;
    if (world.get(target, data.Player) catch null) |player| player.ground_entity = c.ENTITYNUM_NONE;
    if (world.get(target, data.Actor) catch null) |actor| actor.ground_entity = c.ENTITYNUM_NONE;
}
pub fn fire(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const entry = catalog.find(shot.weapon) orelse return error.UnknownWeapon;
    const tuning = table.entries[shot.weapon];
    const owner_id = try world.persistentId(owner);
    const slot = (try world.get(owner, data.Binding)).slot;
    const eye = rules.eye(shot.position, shot.view_height);
    const forward = v.basis(shot.angles).forward;
    switch (entry.spec.combat) {
        .pending => {
            engine.print("dk3 zig: weapon combat policy pending\n");
            return;
        },
        .hitscan => |policy| {
            const height = (if (shot.ducked) policy.crouching_height else policy.standing_height) orelse shot.view_height;
            const start = rules.eye(shot.position, height);
            const hit = try trace(start, v.add(start, v.scale(forward, tuning.range)), slot, 0, c.MASK_SHOT);
            if (hit.fraction < 1) if (victim(slots, hit.entity)) |target| {
                const amount = tuning.damage * (if (engine.integer("g_gametype") == c.GT_SINGLE_PLAYER) policy.single_player_scale else 1);
                if (try hurt(world, target, owner_id, amount, now, false)) if (policy.inertial) try shove(world, target, owner_id, forward, amount, now);
            };
            try @import("impacts.zig").contact(world, slots, projections, shot.weapon, hit, hit.entity < c.ENTITYNUM_WORLD or v.length(v.subtract(hit.end, shot.position)) < 40, now);
        },
        .pellets => |policy| {
            const start = (try trace(eye, rules.muzzle(eye, shot.angles, tuning.muzzle), slot, 0, c.MASK_SHOT)).end;
            const aim = (try trace(eye, v.add(eye, v.scale(forward, if (policy.aim_reach) policy.range else 2000)), slot, 0, c.MASK_SHOT)).end;
            const direction = rules.aim(start, aim, forward);
            const perpendicular = v.cross(direction, .{ 0, 0, 1 });
            const right = if (v.length(perpendicular) > 0.001) v.normalize(perpendicular) else v.basis(shot.angles).right;
            const reach = if (policy.aim_reach) v.length(v.subtract(aim, start)) + 64 else policy.range;
            if ((world.get(owner, data.Random) catch null) == null) try world.put(owner, data.Random{ .state = owner_id ^ 0x91e10da5 });
            var random = (try world.get(owner, data.Random)).*;
            var hits: @import("../domain/pellets.zig").Hits = .{};
            var last: @import("../domain/collision.zig").Trace = undefined;
            for (0..policy.count) |_| {
                const x = random.next();
                const y = random.next();
                const spread = @import("../domain/pellets.zig").direction(direction, right, x, y, policy.spread);
                last = try trace(start, v.add(start, v.scale(spread, reach)), slot, 0, c.MASK_SHOT);
                if (last.fraction < 1) if (victim(slots, last.entity)) |target| {
                    if ((world.get(target, data.Health) catch null) != null) hits.add(try world.persistentId(target), policy.max_victims);
                };
            }
            (try world.get(owner, data.Random)).* = random;
            const damage = tuning.damage * (if (engine.integer("g_gametype") == c.GT_SINGLE_PLAYER) policy.single_player_scale else 1);
            for (hits.ids[0..hits.used], 0..) |id, i| if (world.find(id)) |target| {
                const amount = hits.damage(i, damage, policy.count);
                if (try hurt(world, target, owner_id, amount, now, false)) if (policy.inertial) try shove(world, target, owner_id, direction, amount, now);
            };
            try @import("impacts.zig").contact(world, slots, projections, shot.weapon, last, false, now);
            if (engine.integer("developer") > 0) {
                var text: [128]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig pellets: weapon={d} pellets={d} victims={d}\n", .{ shot.weapon, policy.count, hits.used }));
            }
        },
        .ion => |policy| {
            const start = (try trace(eye, rules.muzzle(eye, shot.angles, tuning.muzzle), slot, policy.radius, c.MASK_SHOT)).end;
            const aimed = (try trace(eye, v.add(eye, v.scale(forward, 2000)), slot, 0, c.MASK_SHOT)).end;
            const speed_factor = if (world.get(owner, data.Character)) |state| 1 + 0.3 * @as(f32, @floatFromInt(state.attribute(.attack, now))) else |_| 1;
            const model = try @import("resources.zig").model(entry.spec.visual.projectile_model);
            const bolt = try world.create(null, .{ data.Transform{ .position = start, .angles = shot.angles }, data.Velocity{ .linear = v.scale(rules.aim(start, aimed, forward), tuning.speed * speed_factor) }, data.Projectile{ .owner = owner_id, .weapon = shot.weapon, .damage = tuning.damage, .born_ms = now, .stepped_ms = now } });
            errdefer world.destroy(bolt) catch unreachable;
            const bolt_slot = try slots.acquire(bolt, null);
            errdefer slots.release(bolt_slot, bolt) catch unreachable;
            try world.put(bolt, data.Binding{ .slot = bolt_slot, .model = model });
            projections[bolt_slot] = std.mem.zeroes(abi.EntityProjection);
            try publish(world, bolt, projections, now);
        },
    }
    if (entry.spec.audio.fire) |sound| try @import("events.zig").sound(world, slots, projections, sound, eye, slot, c.CHAN_WEAPON, now);
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
    projection.state.modelindex = binding.model;
    projection.state.pos = @import("../engine/trajectory.zig").linear(transform.position, velocity, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(transform.angles);
    projection.shared.currentOrigin = transform.position;
    const radius = catalog.find(projectile.weapon).?.spec.combat.ion.radius;
    projection.shared.mins = @splat(-radius);
    projection.shared.maxs = @splat(radius);
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
        _ = try hurt(world, target, projectile.owner, amount, now, true);
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
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
            try @import("impacts.zig").contact(world, slots, projections, projectile.weapon, hit, false, now);
            if (victim(slots, hit.entity)) |target| {
                if (world.get(target, data.Health)) |_| {
                    _ = try hurt(world, target, projectile.owner, projectile.damage * (if (try world.persistentId(target) == projectile.owner) @as(f32, 0.5) else 1), now, true);
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
