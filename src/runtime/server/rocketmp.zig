// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const policy = @import("actor_catalog").rocketmp;
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
    if (injured and try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 20, 25, now)) {
        return;
    }
    const target = sensed.enemy orelse {
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    if (actor.rocketmp.evade_until) |until| {
        if (now < until and v.length(v.subtract(actor.rocketmp.destination, pose.position)) >= 16) {
            actor.threat_position = actor.rocketmp.destination;
            actor.mode = .chase;
            return;
        }
        actor.rocketmp.evade_until = null;
    }
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    const stationary = (try world.get(entity, data.MapObject)).flags & 0x80 != 0;
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
        if (actor.rocketmp.evade_until != null) {
            actor.threat_position = actor.rocketmp.destination;
            actor.mode = .chase;
            return;
        }
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) {
            actor.melee.active = false;
            if (sensed.distance > 120) actor.rocketmp.pursuing = true;
        }
    }
    if (!actor.melee.active and tick and facing and sensed.visible and sensed.distance < definition.mp_rockets[0].range) {
        if (actor.rocketmp.pursuing and sensed.distance >= 120 and !stationary) {
            actor.melee.begin(policy.chase(now >= actor.rocketmp.ready_ms), now);
        } else if (now >= actor.rocketmp.ready_ms) {
            actor.rocketmp.pursuing = false;
            if (policy.select(sensed.distance, (try world.get(entity, data.Random)).next(), stationary)) |index| {
                actor.melee.begin(index, now);
            } else try evade(world, entity, actor, pose.*, definition.speed, now);
        }
        actor.changed_ms = now;
    }
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
    actor.mode = if (stationary) (if (actor.melee.active) .attack else .idle) else if (actor.rocketmp.evade_until != null) .chase else if (actor.melee.active) (if ((actor.rocketmp.pursuing or actor.melee.pose == 1) and sensed.distance >= definition.attack_range) .chase else .attack) else .chase;
    if (actor.rocketmp.evade_until != null) actor.threat_position = actor.rocketmp.destination;
}
fn evade(world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, speed: f32, now: i64) !void {
    const direction = v.normalize(v.subtract(actor.threat_position, pose.position));
    const angle: f32 = (if ((try world.get(entity, data.Random)).next() > 0.5) @as(f32, -25) else 25) * std.math.pi / 180;
    const forward = v.normalize(.{ direction[0] * @cos(angle) - direction[1] * @sin(angle), direction[0] * @sin(angle) + direction[1] * @cos(angle), 0 });
    const distance = speed * 0.5;
    const hit = try @import("region_collision.zig").trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(forward, distance)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
    actor.rocketmp.destination = if (hit.fraction < 1) v.add(pose.position, v.scale(forward, distance * hit.fraction - 16)) else hit.end;
    actor.rocketmp.evade_until = now + 1100;
    actor.melee.active = false;
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: Ref, facing: bool, now: i64) !void {
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (!facing) return;
    const index = actor.melee.pose;
    const frames = [_]?u16{ definition.strikes[index], definition.second_strikes[index] };
    for (frames, 0..) |frame, hand| if (frame) |at| {
        if (index == 1 and hand == 1) continue;
        if (!actor.melee.event(@as(u2, 1) << @intCast(hand), @divTrunc(@as(i64, at) * 1000, definition.attacks[index].fps), now, false)) continue;
        if (index == 1) {
            const aim = try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(entity, data.Random));
            const hit = try @import("region_collision.zig").from(aim.world, .{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SHOT }, try world.persistentId(entity));
            if (@import("region_access.zig").victim(world, slots, hit)) |victim| {
                if ((victim.get(data.Health) catch null) == null) continue;
                const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
                _ = try @import("damage.zig").apply(victim.world, victim.entity, @intFromFloat(@ceil(amount)), now, .{ .source = try world.persistentId(entity), .attacker_class = "monster_rocketmp" });
                if (definition.second_attack_sounds[index].len > 0) try @import("events.zig").sound(world, slots, projections, definition.second_attack_sounds[index], pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_WEAPON, now);
            }
            continue;
        }
        if (index == 0 and hand == 1 and !try @import("actor_aim.zig").clearProjectile(world, slots, entity, target, pose, definition.mp_rockets[1], 10)) {
            if (try @import("actor_motion.zig").sidestep(pose, (try world.get(entity, data.Body)).*, (try world.get(entity, data.Binding)).slot, (try world.get(entity, data.Random)).next())) |point| {
                actor.rocketmp.destination = point;
                actor.rocketmp.evade_until = now + 2000;
                actor.melee.active = false;
            }
            return;
        }
        try @import("actor_rockets.zig").launch(world, slots, projections, entity, target, pose, if (hand == 0) .mp_left else .mp_right, definition.mp_rockets[hand], now);
        if (index == 2 or hand == 1) actor.rocketmp.ready_ms = now + 2000;
    };
}
