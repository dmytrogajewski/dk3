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
const policy = @import("actor_catalog").vermin;
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
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
    if (injured and hurt.amount >= 35 and (try world.get(entity, data.Random)).next() < 0.5) if (definition.pain[0]) |sequence| {
        actor.reaction = sequence;
        actor.reaction_started_ms = now;
        actor.reaction_until_ms = now + sequence.duration();
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    const target = sensed.enemy orelse {
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    if (now < actor.vermin.ready_ms) {
        actor.mode = .attack;
        return;
    }
    const chosen = policy.select(sensed.distance) orelse {
        actor.melee.active = false;
        actor.mode = .chase;
        return;
    };
    const current = if (actor.melee.pose == 3) @as(u3, 1) else actor.melee.pose;
    if (actor.melee.active and current != chosen) actor.melee.active = false;
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) actor.melee.active = false;
    }
    if (!actor.melee.active and tick and facing and sensed.visible) {
        actor.melee.begin(chosen, now);
        actor.changed_ms = now;
    }
    actor.mode = if (actor.melee.active) .attack else if (sensed.visible) .idle else .chase;
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: ecs.Entity, facing: bool, now: i64) !void {
    const index = actor.melee.pose;
    const sequence = definition.attacks[index];
    const slot = (try world.get(entity, data.Binding)).slot;
    const times = [_]?i64{ definition.attack_sound_ms[index], definition.second_sound_ms[index] };
    const sounds = [_][]const u8{ definition.attack_sounds[index], definition.second_attack_sounds[index] };
    for (times, sounds, 0..) |time, name, i| if (time) |at| {
        if (name.len > 0 and actor.melee.event(@as(u2, 1) << @intCast(i), at, now, true)) try @import("events.zig").sound(world, slots, projections, name, pose.position, slot, c.CHAN_WEAPON, now);
    };
    const jump = index == 1 or index == 3;
    const first = actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, sequence.fps), now, false);
    if (jump and first) {
        const velocity = try world.get(entity, data.Velocity);
        velocity.linear = v.scale(v.basis(pose.angles).forward, definition.speed * 1.5);
        velocity.linear[2] = definition.upward_speed * 0.5;
        actor.ground_entity = c.ENTITYNUM_NONE;
        if (index == 1 and definition.vermin_has_leap) {
            actor.melee.begin(3, now);
            return;
        }
    }
    const strike = if (jump) actor.melee.event(2, @divTrunc(@as(i64, definition.second_strikes[index].?) * 1000, sequence.fps), now, false) else first;
    if (!strike or (index != 0 and !facing)) return;
    if (index == 2) {
        try @import("vermin_rockets.zig").launch(world, slots, projections, entity, target, pose, definition.vermin_rocket, now);
        actor.vermin.ready_ms = now + 1500;
        return;
    }
    const aim = try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(entity, data.Random));
    const hit = try engine.collisionService().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
        if ((world.get(victim, data.Health) catch null) == null) return;
        const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
        const source = try world.persistentId(entity);
        _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(amount)), now, .{ .source = source, .attacker_class = "monster_venomvermin" });
        try @import("ailments.zig").apply(world, victim, .{ .poison = .{ .damage = 1, .duration_ms = 15000, .interval_ms = 3000 } }, source, 0, now);
        if (definition.second_attack_sounds[index].len > 0) try @import("events.zig").sound(world, slots, projections, definition.second_attack_sounds[index], pose.position, slot, c.CHAN_WEAPON, now);
    };
}
