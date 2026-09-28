// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const catalog = @import("actor_catalog");
const policy = catalog.gunners;
pub fn kindOf(kind: catalog.Kind) policy.Kind {
    return switch (kind) {
        .sealcaptain => .captain,
        .sealcommando => .commando,
        .sealgirl => .girl,
        .uzigang => .uzi,
        else => unreachable,
    };
}
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const kind = kindOf(catalog.entries[actor.definition].kind);
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
    if (injured and try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 20, policy.painLimit(kind), now)) return;
    const target = sensed.enemy orelse {
        actor.melee.active = false;
        actor.gunner.pursuing = true;
        actor.mode = .idle;
        return;
    };
    if (@import("actor_evasion.zig").update(actor, pose.*, now)) return;
    const flags = (try world.get(entity, data.MapObject)).flags;
    if (kind == .commando or flags & 0x80 != 0) actor.gunner.pursuing = false;
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        actor.think_ms = now + 100;
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    const in_range = sensed.distance < definition.range;
    const can_chase_fire = sensed.visible and (kind == .uzi or in_range);
    if (actor.melee.active and actor.gunner.pursuing and !can_chase_fire) actor.melee.active = false;
    if (actor.melee.active) {
        if (tick) try emit(world, slots, projections, entity, target, actor, pose.*, definition, kind, facing, now);
        if (actor.evasion.until_ms != null) return;
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) {
            actor.melee.active = false;
            if (actor.gunner.pursuing and sensed.distance < policy.chaseDistance(kind)) actor.gunner.pursuing = false else if (!actor.gunner.pursuing and flags & 0x80 == 0 and kind != .commando) {
                // Uzi's positive in-range test is authored; Captain repeats at rest.
                if (kind == .girl or (kind == .uzi and in_range) or !in_range or !sensed.visible) actor.gunner.pursuing = true;
            }
        }
    }
    if (!actor.melee.active and tick and sensed.visible and now >= actor.gunner.ready_ms) {
        if (kind == .uzi and sensed.distance < policy.chaseDistance(kind)) actor.gunner.pursuing = false;
        if ((actor.gunner.pursuing and can_chase_fire) or (!actor.gunner.pursuing and in_range and facing)) {
            const index: u3 = if (kind == .commando) @intFromBool((try world.get(entity, data.Random)).next() >= 0.5) else @intFromBool(actor.gunner.pursuing);
            actor.melee.begin(index, now);
            actor.gunner.emit_ms = now + 100;
            actor.changed_ms = now;
        }
    }
    actor.mode = if (actor.melee.active) if (actor.gunner.pursuing) .chase else .attack else if (sensed.visible and in_range and !actor.gunner.pursuing) .idle else .chase;
}
fn sidestep(world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, now: i64) !void {
    if ((try world.get(entity, data.MapObject)).flags & 0x80 != 0) return;
    if (try @import("actor_motion.zig").sidestep(pose, (try world.get(entity, data.Body)).*, (try world.get(entity, data.Binding)).slot, (try world.get(entity, data.Random)).next())) |point| {
        actor.evasion = .{ .until_ms = now + 2000, .destination = point, .kind = .sidestep, .yaw = pose.angles[1] };
        actor.threat_position = point;
        actor.melee.active = false;
        actor.mode = .chase;
    }
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, target: Ref, actor: *data.Actor, pose: data.Transform, definition: Definition, kind: policy.Kind, facing: bool, now: i64) !void {
    if (now < actor.gunner.emit_ms) return;
    actor.gunner.emit_ms = now + 100;
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (actor.gunner.pursuing and kind != .uzi and !facing) return;
    const index = actor.melee.pose;
    const first = actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false);
    const second = if (!first and (kind == .uzi or actor.gunner.pursuing)) if (definition.second_strikes[index]) |frame| actor.melee.event(2, @divTrunc(@as(i64, frame) * 1000, definition.attacks[index].fps), now, false) else false else false;
    if ((!first and !second) or (kind != .uzi and !facing)) return;
    const tuning: catalog.weapon.Tuning = .{ .damage = definition.damage, .random_damage = definition.random_damage, .range = definition.range, .offset = definition.offset, .spread = definition.spread };
    const needs_clear = kind == .uzi or kind == .commando or (kind == .girl and !actor.gunner.pursuing);
    if (needs_clear and !try @import("actor_aim.zig").clearProjectile(world, slots, entity, target, pose, tuning, if (kind == .uzi) 10 else 0)) {
        if (!actor.gunner.pursuing) try sidestep(world, entity, actor, pose, now);
        return;
    }
    try @import("gunner_bursts.zig").launch(world, slots, projections, entity, target, pose, if (kind == .uzi) .uzi else if (kind == .commando) .commando else .shotgun, kind == .commando and index == 0, tuning, now);
    if (kind == .girl and !actor.gunner.pursuing) actor.gunner.ready_ms = now + 2000;
}
