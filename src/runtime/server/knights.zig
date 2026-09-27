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
const policy = catalog.knights;
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    const perceived = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    actor.knight.sword_lit = perceived.visible;
    if (actor.reaction_until_ms) |until| {
        if (now < until) {
            actor.mode = .idle;
            return;
        }
        actor.reaction = null;
        actor.reaction_until_ms = null;
    }
    if (injured and hurt.amount >= 35 and (try world.get(entity, data.Random)).next() < 0.05) if (definition.pain[0]) |sequence| {
        actor.reaction = sequence;
        actor.reaction_started_ms = now;
        actor.reaction_until_ms = now + sequence.duration();
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    const target = perceived.enemy orelse {
        actor.mode = .idle;
        actor.melee.active = false;
        return;
    };
    if (actor.knight.sidestep_until) |until| {
        if (now < until and v.length(v.subtract(actor.knight.destination, pose.position)) >= 16) {
            actor.mode = .chase;
            actor.threat_position = actor.knight.destination;
            return;
        }
        actor.knight.sidestep_until = null;
    }
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
        if (actor.knight.sidestep_until != null) {
            actor.mode = .chase;
            actor.threat_position = actor.knight.destination;
            return;
        }
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) actor.melee.active = false;
    }
    if (!actor.melee.active and tick and facing and perceived.visible) {
        const random = try world.get(entity, data.Random);
        if (policy.inRange(perceived.distance, definition.range, definition.knight_ranged.range, random.next(), random.next())) {
            actor.melee.begin(policy.select(perceived.distance), now);
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
    const times = [_]?i64{ definition.attack_sound_ms[index], definition.second_sound_ms[index] };
    const sounds = [_][]const u8{ definition.attack_sounds[index], definition.second_attack_sounds[index] };
    for (times, sounds, 0..) |at, name, i| if (at) |time| {
        if (name.len > 0 and actor.melee.event(@as(u2, 1) << @intCast(i), time, now, true)) try @import("events.zig").sound(world, slots, projections, name, pose.position, slot, c.CHAN_WEAPON, now);
    };
    if (!actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, sequence.fps), now, false) or !facing) return;
    const lightning = catalog.entries[actor.definition].kind == .knight2;
    if (index == 1) {
        if (!try @import("actor_aim.zig").clearProjectile(world, slots, entity, target, pose, definition.knight_ranged, 0)) {
            if (try @import("actor_motion.zig").sidestep(pose, (try world.get(entity, data.Body)).*, slot, (try world.get(entity, data.Random)).next())) |point| {
                actor.knight.destination = point;
                actor.knight.sidestep_until = now + 2000;
                actor.melee.active = false;
            }
            return;
        }
        if (lightning) try @import("knight_attacks.zig").zap(world, slots, projections, entity, target, pose, now) else try @import("actor_fireballs.zig").launch(world, slots, projections, entity, target, pose, .knight, definition.knight_ranged, now);
        return;
    }
    const aim = try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(entity, data.Random));
    const hit = try engine.collisionService().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
        if ((world.get(victim, data.Health) catch null) == null) return;
        const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
        _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(amount)), now, .{ .source = try world.persistentId(entity), .attacker_class = catalog.entries[actor.definition].classname });
        if (lightning) {
            try @import("knight_attacks.zig").punch(world, slots, projections, entity, pose, now);
            if ((world.get(victim, data.Actor) catch null) != null or (world.get(victim, data.Player) catch null) != null) {
                var impulse = v.scale(v.basis(pose.angles).forward, amount * 30);
                impulse[2] = 40 + amount;
                const velocity = try world.get(victim, data.Velocity);
                velocity.linear = v.add(velocity.linear, impulse);
                (try world.get(victim, data.Body)).grounded = false;
                if (world.get(victim, data.Actor) catch null) |other| other.ground_entity = c.ENTITYNUM_NONE;
                if (world.get(victim, data.Player) catch null) |other| other.ground_entity = c.ENTITYNUM_NONE;
            }
        }
    };
}
