// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const catalog = @import("actor_catalog");
const policy = catalog.rats;
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const plague = catalog.entries[actor.definition].kind == .plague_rat;
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (actor.reaction_until_ms) |until| {
        if (now < until) {
            actor.mode = .idle;
            return;
        }
        actor.reaction = null;
        actor.reaction_until_ms = null;
    }
    if (injured and (!plague or hurt.amount >= 35) and (try world.get(entity, data.Random)).next() < (if (plague) @as(f32, 0.25) else 0.1)) if (definition.pain[0]) |sequence| {
        actor.reaction = sequence;
        actor.reaction_started_ms = now;
        actor.reaction_until_ms = now + sequence.duration();
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    const target = sensed.enemy orelse {
        actor.mode = .idle;
        actor.melee.active = false;
        return;
    };
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
    }
    actor.rat.strafe_yaw = pose.angles[1];
    if (actor.rat.evasion_until) |until| {
        if (now < until and v.length(v.subtract(actor.rat.destination, pose.position)) >= 16) {
            actor.mode = .chase;
            actor.threat_position = actor.rat.destination;
            return;
        }
        actor.rat.evasion_until = null;
        actor.rat.strafe = false;
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) {
            actor.melee.active = false;
            const random = try world.get(entity, data.Random);
            if (sensed.visible and policy.inRange(sensed.distance, definition.range, definition.jump_distance, random.next()) and random.next() > 0.5) {
                const strafe = random.next() <= 0.5;
                if (try @import("actor_motion.zig").sidestepDistance(pose.*, (try world.get(entity, data.Body)).*, (try world.get(entity, data.Binding)).slot, random.next(), if (strafe) 80 else 96)) |point| {
                    actor.rat.evasion_until = now + (if (strafe) @as(i64, 1100) else 2000);
                    actor.rat.strafe = strafe;
                    actor.rat.destination = point;
                    actor.mode = .chase;
                    actor.threat_position = point;
                    return;
                }
            }
        }
    }
    if (!actor.melee.active and tick and facing and sensed.visible) {
        const random = try world.get(entity, data.Random);
        if (policy.inRange(sensed.distance, definition.range, definition.jump_distance, random.next())) {
            // The reference range predicate is called again when choosing the
            // animation; keep this second roll rather than guaranteeing a leap.
            const selected: u3 = if (policy.inRange(sensed.distance, definition.range, definition.jump_distance, random.next())) 0 else 1;
            actor.melee.begin(selected, now);
            actor.rat.launched = false;
            actor.rat.poison = policy.poisonous(plague, selected, random.next());
            actor.changed_ms = now;
        }
    }
    actor.mode = if (actor.melee.active) .attack else .chase;
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: ecs.Entity, facing: bool, now: i64) !void {
    const index = actor.melee.pose;
    const sequence = definition.attacks[index];
    const slot = (try world.get(entity, data.Binding)).slot;
    const jump = index == 1;
    try @import("actor_attack_sounds.zig").at(world, slots, projections, entity, actor, definition, index, actor.melee.started_ms, now, if (jump and definition.attack_alternative[index] == null) 1 else 3);
    if (actor.melee.event(1, definition.attack_sound_ms[index], now, true)) {
        if (jump) {
            actor.rat.launched = true;
            const velocity = try world.get(entity, data.Velocity);
            velocity.linear = v.scale(v.basis(pose.angles).forward, definition.speed * 1.5);
            velocity.linear[2] = definition.upward_speed;
            actor.ground_entity = c.ENTITYNUM_NONE;
        }
    }

    const at = if (jump) definition.jump_strike_ms else @divTrunc(@as(i64, definition.strikes[index]) * 1000, sequence.fps);
    if (!actor.melee.event(1, at, now, false) or (!jump and !facing)) return;
    const weapon: catalog.weapon.Tuning = if (actor.rat.poison) definition.rat_poison else .{ .damage = definition.damage, .random_damage = definition.random_damage, .range = definition.range, .offset = definition.offset, .spread = definition.spread };
    const aim = try @import("actor_aim.zig").lead(world, target, pose, weapon.offset, try world.get(entity, data.Random));
    const hit = try engine.collisionService().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, weapon.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
        if ((world.get(victim, data.Health) catch null) == null) return;
        const source = try world.persistentId(entity);
        const amount = weapon.damage + (try world.get(entity, data.Random)).next() * weapon.random_damage;
        _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(amount)), now, .{ .source = source, .attacker_class = catalog.entries[actor.definition].classname });
        if (actor.rat.poison) {
            try @import("ailments.zig").apply(world, victim, .{ .poison = .{ .damage = 1, .duration_ms = 15000, .interval_ms = 3000 } }, source, 0, now);
            if (definition.second_attack_sounds[index].len > 0) try @import("events.zig").sound(world, slots, projections, definition.second_attack_sounds[index], pose.position, slot, c.CHAN_WEAPON, now);
        }
    };
}
