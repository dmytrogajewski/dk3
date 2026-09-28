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
const policy = @import("actor_catalog").rotworm;
pub fn initialize(world: *data.World, entity: ecs.Entity, now: i64) !void {
    const object = (try world.get(entity, data.MapObject)).*;
    if (object.flags & 0x800 == 0) return;
    const pose = try world.get(entity, data.Transform);
    const body = (try world.get(entity, data.Body)).*;
    const hit = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 0, 0, 10000 }), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
    if (hit.fraction == 1 or hit.start_solid) return error.InvalidRotwormCeiling;
    const distance = hit.end[2] - pose.position[2];
    const height = body.maxs[2] - body.mins[2];
    if (distance > height) pose.position[2] += distance - height;
    pose.angles[0] = 90;
    const actor = try world.get(entity, data.Actor);
    actor.rotworm.phase = .ceiling;
    actor.think_ms = now + 100;
}
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const state = &actor.rotworm;
    const tick = now >= actor.think_ms;
    if (state.phase == .ceiling and !tick) {
        actor.mode = .idle;
        return;
    }
    const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (tick) actor.think_ms = now + (if (state.phase == .ceiling) @as(i64, 300) else 100);
    if (state.phase == .ceiling) {
        actor.mode = .idle;
        if (sensed.enemy != null and sensed.visible and sensed.distance < definition.sight_range) state.phase = .ground;
        return;
    }
    const target = sensed.enemy orelse {
        actor.melee.active = false;
        actor.mode = .idle;
        if (state.phase != .flight or now - state.started_ms >= 5000) state.phase = .ground;
        return;
    };
    if (state.phase == .flight) {
        actor.mode = .attack;
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, false, now);
        const elapsed = now - state.started_ms;
        if (policy.landed(elapsed, v.length(v.subtract(state.destination, pose.position)), actor.ground_entity != c.ENTITYNUM_NONE)) {
            if (actor.ground_entity == (try target.get(data.Binding)).slot) {
                state.phase = .jump_bite;
                state.started_ms = now;
                actor.melee.begin(0, now);
                actor.changed_ms = now;
            } else {
                state.phase = .ground;
                actor.melee.active = false;
                actor.mode = .chase;
            }
        } else if (elapsed >= 5000) {
            state.phase = .ground;
            actor.melee.active = false;
            actor.mode = .chase;
        }
        return;
    }
    pose.angles[0] = 0;
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    if (tick) pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, true, now);
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) {
            actor.melee.active = false;
            state.phase = .ground;
            actor.mode = .chase;
            return;
        }
        actor.mode = .attack;
        return;
    }
    actor.mode = .chase;
    if (!tick or !sensed.visible) return;
    const random = try world.get(entity, data.Random);
    if (policy.jump(sensed.distance, sensed.visible, random.next())) {
        state.phase = .flight;
        state.started_ms = now;
        state.destination = (try target.get(data.Transform)).position;
        const direction = v.normalize(v.subtract(state.destination, pose.position));
        pose.angles[1] = std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi;
        const velocity = try world.get(entity, data.Velocity);
        velocity.linear = v.scale(direction, definition.speed * 1.95);
        velocity.linear[2] = definition.upward_speed * 1.3;
        actor.ground_entity = c.ENTITYNUM_NONE;
        actor.melee.begin(2, now);
        actor.mode = .attack;
        actor.changed_ms = now;
    } else if (sensed.distance < definition.range or random.next() > 0.25) {
        actor.melee.begin(policy.select(sensed.distance, random.next()), now);
        actor.mode = .attack;
        actor.changed_ms = now;
    }
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, state.phase != .flight, now);
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: Ref, attacks: bool, now: i64) !void {
    const index = actor.melee.pose;
    const sequence = definition.attacks[index];
    const slot = (try world.get(entity, data.Binding)).slot;
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (!attacks or !actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, sequence.fps), now, false)) return;
    if (index == 1) return @import("venom_spit.zig").launch(world, slots, projections, entity, target, pose, definition.rotworm_spit, now);
    const aim = try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(entity, data.Random));
    const hit = try @import("actor_collision.zig").service().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
    if (@import("region_access.zig").victim(world, slots, hit)) |victim| {
        if ((victim.get(data.Health) catch null) == null) return;
        const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
        const source = try world.persistentId(entity);
        _ = try @import("damage.zig").apply(victim.world, victim.entity, @intFromFloat(@ceil(amount)), now, .{ .source = source, .attacker_class = "monster_rotworm" });
        try @import("ailments.zig").apply(victim.world, victim.entity, .{ .poison = .{ .damage = 1, .duration_ms = 15000, .interval_ms = 3000 } }, source, 0, now);
    }
}
