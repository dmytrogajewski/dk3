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
const policy = @import("actor_catalog").sludge;
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    actor.sludge.water = try @import("actor_water.zig").level(pose.position, (try world.get(entity, data.Body)).*, (try world.get(entity, data.Binding)).slot);
    if (actor.reaction_until_ms) |until| {
        if (now < until) {
            actor.mode = .idle;
            return;
        }
        actor.reaction = null;
        actor.reaction_until_ms = null;
    }
    if (injured and hurt.amount >= 45 and (try world.get(entity, data.Random)).next() < 0.05) if (definition.pain[0]) |hit| {
        actor.reaction = hit;
        actor.reaction_started_ms = now;
        actor.reaction_until_ms = now + hit.duration();
        actor.melee.active = false;
        actor.sludge.phase = .normal;
        actor.mode = .idle;
        return;
    };
    if (actor.sludge.phase == .scooping) {
        actor.mode = .attack;
        if (now - actor.melee.started_ms < definition.attacks[2].duration()) return;
        const random = try world.get(entity, data.Random);
        if (actor.sludge.ammo < 3 + 5 * random.next()) {
            actor.sludge.ammo += 2 + 5 * random.next();
            actor.melee.begin(2, now);
            try scoopSound(world, slots, projections, entity, pose.*, now);
        } else {
            actor.sludge.phase = .raising;
            actor.melee.begin(3, now);
        }
        return;
    }
    if (actor.sludge.phase == .raising) {
        actor.mode = .attack;
        if (now - actor.melee.started_ms < definition.attacks[3].duration()) return;
        actor.sludge.phase = .normal;
        actor.melee.active = false;
    }
    const target = sensed.enemy orelse {
        if (!actor.sludge.idle_chosen) {
            actor.sludge.idle_chosen = true;
            actor.sludge.idle_scoop = actor.sludge.water > 0 and (try world.get(entity, data.Random)).next() >= 0.4;
            actor.changed_ms = now;
        }
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    actor.sludge.idle_chosen = false;
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
        if (actor.melee.active) try orient(world, entity, pose, definition.pitch_speed);
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) actor.melee.active = false;
    }
    if (!actor.melee.active and tick and sensed.visible and sensed.distance < definition.sludge_weapons[1].range) {
        if (actor.sludge.ammo <= 0 and actor.sludge.water > 0) {
            actor.sludge.ammo = policy.scoop(actor.sludge.ammo, (try world.get(entity, data.Random)).next());
            actor.sludge.phase = .scooping;
            actor.melee.begin(2, now);
            try scoopSound(world, slots, projections, entity, pose.*, now);
        } else if (facing) actor.melee.begin(policy.select((try world.get(entity, data.Random)).next()), now);
        actor.changed_ms = now;
    }
    actor.mode = if (actor.melee.active) .attack else .chase;
    if (actor.melee.active and actor.sludge.phase == .normal) try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
}
fn scoopSound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, pose: data.Transform, now: i64) !void {
    try @import("events.zig").sound(world, slots, projections, "e1/m_sludgegetmud.wav", pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: ecs.Entity, facing: bool, now: i64) !void {
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (!facing) return;
    const index = actor.melee.pose;
    const strikes = [_]?u16{ definition.strikes[index], definition.second_strikes[index] };
    for (strikes, 0..) |frame, hand| if (frame) |at| {
        if (!actor.melee.event(@as(u2, 1) << @intCast(hand), @divTrunc(@as(i64, at) * 1000, definition.attacks[index].fps), now, false)) continue;
        actor.sludge.ammo -= 1;
        try @import("sludge_globs.zig").launch(world, slots, projections, entity, target, pose, definition.sludge_weapons[hand], now);
    };
}
fn orient(world: *data.World, entity: ecs.Entity, pose: *data.Transform, pitch_speed: f32) !void {
    const axes = v.basis(pose.angles);
    const slot = (try world.get(entity, data.Binding)).slot;
    const directions = [_]v.Vec3{ v.subtract(axes.forward, axes.right), v.add(axes.forward, axes.right), v.scale(v.subtract(axes.forward, axes.right), -1) };
    var points: [3]v.Vec3 = undefined;
    for (directions, &points) |direction, *point| {
        const start = v.add(pose.position, .{ direction[0] * 8, direction[1] * 8, 32 });
        const hit = try engine.collisionService().trace(.{ .start = start, .end = v.add(start, .{ 0, 0, -64 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
        point.* = hit.end;
    }
    const slope = v.subtract(points[1], points[2]);
    const wanted = std.math.clamp(-std.math.atan2(slope[2], @sqrt(slope[0] * slope[0] + slope[1] * slope[1])) * 180 / std.math.pi, -45, 45);
    pose.angles[0] += std.math.clamp(wanted - pose.angles[0], -pitch_speed, pitch_speed);
}
