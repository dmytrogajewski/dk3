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
const policy = @import("actor_catalog").inmater;
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    const perceived = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (actor.reaction_until_ms) |until| {
        if (now < until) {
            actor.mode = .idle;
            return;
        }
        actor.reaction = null;
        actor.reaction_until_ms = null;
    }
    if (injured and (try world.get(entity, data.Random)).next() < 0.05) if (definition.pain[0]) |sequence| {
        actor.reaction = sequence;
        actor.reaction_started_ms = now;
        actor.reaction_until_ms = now + sequence.duration();
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    const target = perceived.enemy orelse {
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    if (actor.inmater.sidestep_until) |until| {
        if (now < until and v.length(v.subtract(actor.inmater.destination, pose.position)) >= 16) {
            actor.threat_position = actor.inmater.destination;
            actor.mode = .chase;
            return;
        }
        actor.inmater.sidestep_until = null;
    }
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    if (now >= actor.think_ms) {
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180);
    const reachable = perceived.visible and perceived.distance < definition.attack_range;
    if (actor.melee.active and ((actor.melee.pose == 1) != (perceived.distance <= 128)) and facing <= 1) actor.melee.active = false;
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing <= 5, now);
        if (actor.inmater.sidestep_until != null) {
            actor.mode = .chase;
            actor.threat_position = actor.inmater.destination;
            return;
        }
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) actor.melee.active = false;
    }
    if (!actor.melee.active and reachable and facing <= 1) {
        actor.melee.begin(policy.select(perceived.distance, (try world.get(entity, data.Random)).next()), now);
        actor.inmater.pulse = 0;
        actor.changed_ms = now;
    }
    actor.mode = if (actor.melee.active) .attack else if (reachable) .idle else .chase;
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing <= 5, now);
}
fn clearSweep(world: *data.World, slots: *Slots, entity: ecs.Entity, target: ecs.Entity, pose: data.Transform) !bool {
    const point = (try world.get(target, data.Transform)).position;
    const slot = (try world.get(entity, data.Binding)).slot;
    for (policy.sweep) |event| {
        const start = @import("actor_lasers.zig").origin(pose, event.offset);
        const hit = try engine.collisionService().trace(.{ .start = start, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
        if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |other| {
            if (other.index == target.index or (world.get(other, data.Companion) catch null) != null) continue;
            if ((world.get(other, data.Actor) catch null) != null and (try world.get(other, data.Health)).current > 0) return false;
        };
    }
    return true;
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: ecs.Entity, facing: bool, now: i64) !void {
    const index = actor.melee.pose;
    const sequence = definition.attacks[index];
    const slot = (try world.get(entity, data.Binding)).slot;
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (index == 2) {
        while (actor.inmater.pulse < policy.sweep.len) {
            const event = policy.sweep[actor.inmater.pulse];
            if ((now - actor.melee.started_ms) * sequence.fps < @as(i64, event.frame) * 1000) break;
            actor.inmater.pulse += 1;
            if (!try clearSweep(world, slots, entity, target, pose)) {
                if (try @import("actor_motion.zig").sidestep(pose, (try world.get(entity, data.Body)).*, slot, (try world.get(entity, data.Random)).next())) |point| {
                    actor.inmater.destination = point;
                    actor.inmater.sidestep_until = now + 2000;
                    actor.melee.active = false;
                    return;
                }
                continue;
            }
            var tuning = definition.laser;
            tuning.offset = event.offset;
            try @import("actor_lasers.zig").launch(world, slots, projections, entity, target, pose, tuning, false, now);
        }
        return;
    }
    if (!actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, sequence.fps), now, false) or !facing) return;
    const crouched = if (world.get(target, data.Player) catch null) |player| player.ducked else false;
    if (index == 0 and !crouched) return @import("actor_lasers.zig").launch(world, slots, projections, entity, target, pose, definition.laser, false, now);
    var victim: ?ecs.Entity = if (crouched) target else null;
    if (!crouched) {
        const start = @import("actor_lasers.zig").origin(pose, definition.offset);
        const body = (try world.get(target, data.Body)).*;
        const point = v.add((try world.get(target, data.Transform)).position, v.scale(v.add(body.mins, body.maxs), 0.5));
        const hit = try engine.collisionService().trace(.{ .start = start, .end = v.add(start, v.scale(v.normalize(v.subtract(point, start)), definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
        if (hit.entity < slots.occupants.len) victim = slots.occupants[hit.entity];
    }
    if (victim) |other| {
        const damage = if (index == 1) definition.damage else definition.laser.damage;
        const random_damage = if (index == 1) definition.random_damage else definition.laser.random_damage;
        _ = try @import("damage.zig").apply(world, other, @intFromFloat(@ceil(damage + (try world.get(entity, data.Random)).next() * random_damage)), now, .{ .source = try world.persistentId(entity) });
    }
}
