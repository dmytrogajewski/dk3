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
    if (injured and try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 15, 35, now)) return;
    if (actor.psyclaw.jump_started_ms) |start| {
        if (!actor.psyclaw.reduced and now - start > 450) {
            actor.psyclaw.reduced = true;
            const velocity = try world.get(entity, data.Velocity);
            velocity.linear[0] = actor.psyclaw.horizontal[0];
            velocity.linear[1] = actor.psyclaw.horizontal[1];
        }
        if ((now - start > 450 and (try world.get(entity, data.Body)).grounded) or now - start >= 5000) actor.psyclaw.jump_started_ms = null;
        actor.mode = .chase;
        return;
    }
    const target = sensed.enemy orelse {
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    if (@import("actor_evasion.zig").update(actor, pose.*, now)) return;
    const other = (try world.get(target, data.Transform)).position;
    const delta = v.subtract(other, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        actor.think_ms = now + 100;
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    const warped = if (world.get(target, data.Ailments) catch null) |state| if (state.warp) |warp| warp.until_ms > now else false else false;
    const selected: u3 = @intFromBool(sensed.distance <= 135 or warped);
    if (warped and sensed.distance > 135) actor.melee.active = false;
    if (actor.melee.active and actor.melee.pose != selected and facing) {
        actor.melee.begin(selected, now);
        actor.psyclaw.emit_ms = now + 100;
    }
    var completed = false;
    if (actor.melee.active) {
        if (tick) try emit(world, slots, projections, entity, target, actor, pose.*, definition, facing, now);
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) {
            const ranged = actor.melee.pose == 0;
            actor.melee.active = false;
            completed = true;
            if (ranged and try evade(world, entity, target, actor, pose.*, now)) return;
        }
    }
    const in_range = sensed.distance < (if (warped) definition.range else definition.psyclaw_blast.range);
    if (!actor.melee.active and tick and in_range and sensed.visible and facing) {
        if (!completed and try evade(world, entity, target, actor, pose.*, now)) return;
        actor.melee.begin(selected, now);
        actor.psyclaw.emit_ms = now + 100;
        actor.changed_ms = now;
        try @import("actor_floor.zig").orient(world, entity, pose, definition.pitch_speed);
    }
    actor.mode = if (actor.melee.active) .attack else .chase;
    const can_move = (try world.get(entity, data.MapObject)).flags & 0x80 == 0;
    if (actor.mode == .chase and tick and can_move and (try world.get(entity, data.Body)).grounded and @sqrt(delta[0] * delta[0] + delta[1] * delta[1]) < 200 and delta[2] > 32 and delta[2] < 136) {
        const direction = v.normalize(delta);
        const speed = definition.upward_speed * 0.9;
        const velocity = try world.get(entity, data.Velocity);
        velocity.linear = .{ direction[0] * speed, direction[1] * speed, speed };
        actor.psyclaw.horizontal = .{ velocity.linear[0] * 0.25, velocity.linear[1] * 0.25 };
        actor.psyclaw.jump_started_ms = now;
        actor.psyclaw.reduced = false;
        actor.ground_entity = c.ENTITYNUM_NONE;
        pose.angles = .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, yaw, 0 };
    }
}
fn evade(world: *data.World, entity: ecs.Entity, target: ecs.Entity, actor: *data.Actor, pose: data.Transform, now: i64) !bool {
    if ((try world.get(entity, data.MapObject)).flags & 0x80 != 0 or !try @import("actor_evasion.zig").targeted(world, entity, target, pose) or (try world.get(entity, data.Random)).next() <= 0.5) return false;
    const point = try @import("actor_motion.zig").sidestep(pose, (try world.get(entity, data.Body)).*, (try world.get(entity, data.Binding)).slot, (try world.get(entity, data.Random)).next()) orelse return false;
    actor.evasion = .{ .until_ms = now + 2500, .destination = point, .yaw = pose.angles[1] };
    actor.threat_position = point;
    actor.mode = .chase;
    actor.melee.active = false;
    return true;
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, target: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, facing: bool, now: i64) !void {
    if (now < actor.psyclaw.emit_ms) return;
    actor.psyclaw.emit_ms = now + 100;
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    const index = actor.melee.pose;
    const first = actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false);
    const second = if (!first) if (definition.second_strikes[index]) |frame| actor.melee.event(2, @divTrunc(@as(i64, frame) * 1000, definition.attacks[index].fps), now, false) else false else false;
    if ((!first and !second) or !facing) return;
    if (index == 0) return @import("psyclaw_spheres.zig").launch(world, slots, projections, entity, target, pose, definition.psyclaw_blast, now);
    const aim = try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(entity, data.Random));
    const hit = try engine.collisionService().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
        if ((world.get(victim, data.Health) catch null) == null) return;
        const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
        const source = try world.persistentId(entity);
        _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(amount)), now, .{ .source = source, .attacker_class = "monster_psyclaw" });
        try @import("weapon_damage.zig").shove(world, victim, source, aim.direction, amount, now);
    };
}
