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
const policy = catalog.archers;
pub fn think(routes: *const @import("air_routes.zig").Routes, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const kind: policy.Kind = if (catalog.entries[actor.definition].kind == .centurion) .centurion else .fletcher;
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
    if (injured and kind == .fletcher and try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 20, 25, now)) return;
    if (injured and kind == .centurion and (try world.get(entity, data.Random)).next() < 0.3) if (definition.pain[0]) |sequence| {
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
    if (actor.archer.sidestep_until) |until| {
        if (now < until and v.length(v.subtract(actor.archer.destination, pose.position)) >= 16) {
            actor.threat_position = actor.archer.destination;
            actor.mode = .chase;
            return;
        }
        actor.archer.sidestep_until = null;
    }
    if (@import("actor_evasion.zig").update(actor, pose.*, now)) return;
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    var completed = false;
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, kind, facing, now);
        if (actor.archer.sidestep_until != null) {
            actor.threat_position = actor.archer.destination;
            actor.mode = .chase;
            return;
        }
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) {
            completed = true;
            const melee = kind == .centurion and actor.melee.pose == 0;
            actor.melee.active = false;
            if (sensed.visible and sensed.distance < (if (melee) definition.range else definition.archer_ranged.range) and (melee or try @import("actor_evasion.zig").targeted(world, entity, target, pose.*))) {
                const roll = (try world.get(entity, data.Random)).next();
                if ((if (kind == .fletcher) roll <= 0.3 else roll > 0.75) and try @import("actor_evasion.zig").start(routes, world, entity, target, actor, pose.*, true, now)) return;
            }
        }
    }
    const in_range = sensed.distance < definition.archer_ranged.range;
    if (!actor.melee.active and tick and now >= actor.archer.ready_ms and facing and sensed.visible and in_range) {
        if (!completed and try @import("actor_evasion.zig").targeted(world, entity, target, pose.*)) {
            const roll = (try world.get(entity, data.Random)).next();
            if ((if (kind == .fletcher) roll <= 0.3 else roll > 0.75) and try @import("actor_evasion.zig").start(routes, world, entity, target, actor, pose.*, true, now)) return;
        }
        actor.melee.begin(policy.select(kind, sensed.distance, definition.range), now);
        actor.archer.clear_ms = now;
        actor.changed_ms = now;
    }
    actor.mode = if (actor.melee.active) .attack else if (in_range and sensed.visible) .idle else .chase;
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, kind, facing, now);
    if (actor.archer.sidestep_until != null) {
        actor.threat_position = actor.archer.destination;
        actor.mode = .chase;
    }
}
fn sidestep(world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, now: i64) !void {
    if (try @import("actor_motion.zig").sidestep(pose, (try world.get(entity, data.Body)).*, (try world.get(entity, data.Binding)).slot, (try world.get(entity, data.Random)).next())) |point| {
        actor.archer.destination = point;
        actor.archer.sidestep_until = now + 2000;
        actor.melee.active = false;
    }
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: ecs.Entity, kind: policy.Kind, facing: bool, now: i64) !void {
    const index = actor.melee.pose;
    const sequence = definition.attacks[index];
    const slot = (try world.get(entity, data.Binding)).slot;
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (kind == .fletcher and facing and now >= actor.archer.clear_ms) {
        actor.archer.clear_ms = now + 100;
        if (!try @import("actor_aim.zig").clearProjectile(world, slots, entity, target, pose, definition.archer_ranged, 0)) {
            try sidestep(world, entity, actor, pose, now);
            return;
        }
    }
    if (kind == .fletcher and !facing) return;
    if (!actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, sequence.fps), now, false) or !facing) return;
    if (kind == .fletcher or index == 1) {
        if (kind == .centurion and !try @import("actor_aim.zig").clearProjectile(world, slots, entity, target, pose, definition.archer_ranged, 0)) {
            try sidestep(world, entity, actor, pose, now);
            return;
        }
        try @import("shafts.zig").launch(world, slots, projections, entity, target, pose, if (kind == .centurion) .centurion else .fletcher, definition.archer_ranged, now);
        if (kind == .centurion) actor.archer.ready_ms = now + 750;
        return;
    }
    const aim = try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(entity, data.Random));
    const hit = try engine.collisionService().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
        if ((world.get(victim, data.Health) catch null) == null) return;
        const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
        _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(amount)), now, .{ .source = try world.persistentId(entity), .attacker_class = "monster_centurion" });
        if (definition.second_attack_sounds[index].len > 0) try @import("events.zig").sound(world, slots, projections, definition.second_attack_sounds[index], pose.position, slot, c.CHAN_WEAPON, now);
    };
}
