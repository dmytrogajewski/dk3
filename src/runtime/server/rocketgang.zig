// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const policy = @import("actor_catalog").rocketgang;
pub fn think(routes: *const @import("air_routes.zig").Routes, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
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
    if (injured and hurt.amount >= 50 and (try world.get(entity, data.Random)).next() < 0.1) if (definition.pain[0]) |hit| {
        actor.reaction = hit;
        actor.reaction_started_ms = now;
        actor.reaction_until_ms = now + hit.duration();
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    const target = sensed.enemy orelse {
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    if (@import("actor_evasion.zig").update(actor, pose.*, now)) return;
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
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) {
            actor.melee.active = false;
            if (sensed.visible and sensed.distance < definition.gang_rockets[actor.rocketgang.selected].range and try @import("actor_evasion.zig").targeted(world, entity, target, pose.*) and (try world.get(entity, data.Random)).next() > 0.2 and try @import("actor_evasion.zig").start(routes, world, entity, target, actor, pose.*, true, now)) return;
        }
    }
    const in_range = sensed.distance < definition.gang_rockets[actor.rocketgang.selected].range;
    if (!actor.melee.active and tick and facing and sensed.visible and in_range and now >= actor.rocketgang.ready_ms) {
        if (try @import("actor_evasion.zig").targeted(world, entity, target, pose.*) and (try world.get(entity, data.Random)).next() > 0.5 and try @import("actor_evasion.zig").start(routes, world, entity, target, actor, pose.*, true, now)) return;
        actor.rocketgang.selected = policy.select(sensed.distance);
        actor.melee.begin(actor.rocketgang.selected, now);
        actor.changed_ms = now;
    }
    actor.mode = if (actor.melee.active) .attack else if (in_range and sensed.visible) .idle else .chase;
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: ecs.Entity, facing: bool, now: i64) !void {
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (!facing) return;
    // The reference refreshes this deadline throughout the facing attack sequence.
    actor.rocketgang.ready_ms = now + 2000;
    const index = actor.melee.pose;
    if (!actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false)) return;
    try @import("actor_rockets.zig").launch(world, slots, projections, entity, target, pose, .rocketdude, definition.gang_rockets[index], now);
}
