// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const catalog = @import("actor_catalog");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
fn sidestep(world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, now: i64) !void {
    if (try @import("actor_motion.zig").sidestep(pose, (try world.get(entity, data.Body)).*, (try world.get(entity, data.Binding)).slot, (try world.get(entity, data.Random)).next())) |destination| {
        actor.spider.sidestep = destination;
        actor.spider.sidestep_until = now + 2000;
    }
}

pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const small = catalog.entries[actor.definition].kind == .smallspider;
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = actor.receipt != hurt.revision;
    const perceived = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (small and injured) {
        actor.melee.active = false;
        actor.spider.retreat_until = now + catalog.spider.retreatMilliseconds((try world.get(entity, data.Random)).next());
        actor.spider.sidestep_until = null;
    }
    const enemy = perceived.enemy orelse {
        actor.mode = .idle;
        actor.melee.active = false;
        return;
    };
    if (actor.spider.retreat_until) |deadline| {
        if (now < deadline) {
            actor.mode = .flee;
            return;
        }
        actor.spider.retreat_until = null;
    }
    if (actor.spider.sidestep_until) |deadline| {
        if (now < deadline and v.length(v.subtract(actor.spider.sidestep, pose.position)) >= 16) {
            actor.threat_position = actor.spider.sidestep;
            actor.mode = .chase;
            return;
        }
        actor.spider.sidestep_until = null;
    }
    const delta = v.subtract((try world.get(enemy, data.Transform)).position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        actor.think_ms = now + 100;
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    }
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, enemy, small, now);
        if (now >= actor.melee.started_ms + definition.attacks[actor.melee.pose].duration()) {
            actor.melee.active = false;
            if (small and perceived.visible and perceived.distance < definition.range and (try world.get(entity, data.Random)).next() > 0.5) {
                try sidestep(world, entity, actor, pose.*, now);
                if (actor.spider.sidestep_until != null) {
                    actor.threat_position = actor.spider.sidestep;
                    actor.mode = .chase;
                    return;
                }
            }
        }
    }
    const admitted = perceived.visible and catalog.spider.inRange(perceived.distance, definition.range, definition.jump_distance, if (tick) (try world.get(entity, data.Random)).next() else 1);
    if (tick and !actor.melee.active and admitted) {
        const bite = catalog.spider.inRange(perceived.distance, definition.range, definition.jump_distance, (try world.get(entity, data.Random)).next());
        actor.melee.begin(if (bite) 0 else 1, now);
        actor.spider.launched = false;
        actor.changed_ms = now;
        try emit(world, slots, projections, entity, actor, pose.*, definition, enemy, small, now);
    }
    actor.mode = if (actor.melee.active) .attack else .chase;
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, enemy: ecs.Entity, small: bool, now: i64) !void {
    const index = actor.melee.pose;
    const slot = (try world.get(entity, data.Binding)).slot;
    const jump = index == 1;
    if (actor.melee.event(1, definition.attack_sound_ms[index], now, true)) {
        if (definition.attack_sounds[index].len > 0) try @import("events.zig").sound(world, slots, projections, definition.attack_sounds[index], pose.position, slot, c.CHAN_AUTO, now);
        if (jump and !actor.spider.launched) {
            actor.spider.launched = true;
            (try world.get(entity, data.Velocity)).linear = v.add(v.scale(v.basis(pose.angles).forward, definition.speed * 1.5), .{ 0, 0, definition.upward_speed });
            actor.ground_entity = c.ENTITYNUM_NONE;
        }
    }
    if (jump and small) return; // Small-spider leap deliberately has no bite.
    const strike_ms = if (jump) definition.jump_strike_ms else @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps);
    if (!actor.melee.event(1, strike_ms, now, false)) return;
    const axes = v.basis(pose.angles);
    const start = v.add(pose.position, v.add(v.scale(axes.right, definition.offset[0]), v.add(v.scale(axes.forward, definition.offset[1]), .{ 0, 0, definition.offset[2] })));
    const target_body = (try world.get(enemy, data.Body)).*;
    const aim = v.add((try world.get(enemy, data.Transform)).position, v.scale(v.add(target_body.mins, target_body.maxs), 0.5));
    const hit = try engine.collisionService().trace(.{ .start = start, .end = v.add(start, v.scale(v.normalize(v.subtract(aim, start)), definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
        _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage)), now, .{ .source = try world.persistentId(entity), .attacker_class = catalog.entries[actor.definition].classname });
    };
}
