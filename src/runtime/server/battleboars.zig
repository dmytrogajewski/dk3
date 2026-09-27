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
const policy = @import("actor_catalog").battleboar;

pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const injured = (try world.get(entity, data.Hurt)).revision != actor.receipt;
    const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (actor.reaction_until_ms) |until| {
        if (now < until) {
            actor.mode = .idle;
            return;
        }
        actor.reaction = null;
        actor.reaction_until_ms = null;
    }
    // Battleboar's callback chooses one of three hits after the general pain call.
    if (injured) {
        const roll = (try world.get(entity, data.Random)).next();
        const sequence = if (roll < 1.0 / 3.0) definition.pain[0] else if (roll < 2.0 / 3.0) definition.pain_c else definition.pain[1];
        if (sequence) |hit| {
            actor.reaction = hit;
            actor.reaction_started_ms = now;
            actor.reaction_until_ms = now + hit.duration();
            actor.melee.active = false;
            actor.battleboar.flashed = false;
            actor.mode = .idle;
            return;
        }
    }
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
    const clear = try clearShot(world, entity, target, pose.*);
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, clear, now);
        if (clear and now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) actor.melee.active = false;
    }
    const in_range = sensed.distance < definition.boar_weapons[actor.battleboar.selected].range;
    if (!actor.melee.active and tick and facing and sensed.visible and in_range) {
        actor.battleboar.selected = policy.select(sensed.distance, (try world.get(entity, data.Random)).next());
        actor.battleboar.flashed = false;
        actor.melee.begin(actor.battleboar.selected, now);
        actor.changed_ms = now;
    }
    actor.mode = if (actor.melee.active) .attack else .chase;
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, clear, now);
}
fn clearShot(world: *data.World, entity: ecs.Entity, target: ecs.Entity, pose: data.Transform) !bool {
    var end = v.add((try world.get(target, data.Transform)).position, .{ 0, 0, 12 });
    if (world.get(target, data.Player) catch null) |player| if (player.ducked) {
        end[2] -= 32;
    };
    const hit = try engine.collisionService().trace(.{ .start = v.add(pose.position, .{ 0, 0, 15 }), .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SHOT });
    return hit.entity == (try world.get(target, data.Binding)).slot and (try world.get(target, data.Health)).current > 0;
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: ecs.Entity, facing: bool, clear: bool, now: i64) !void {
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    const index = actor.melee.pose;
    // The second authored strike is unused by the active Battleboar callback.
    if (!clear or !actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false) or !facing) return;
    if (index == 0) {
        _ = try @import("actor_bullets.zig").fire(world, slots, projections, entity, target, pose, definition.boar_weapons[0], now);
        actor.battleboar.flashed = true;
    } else try @import("actor_rockets.zig").launch(world, slots, projections, entity, target, pose, .battleboar, definition.boar_weapons[1], now);
}
