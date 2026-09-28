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
const policy = @import("actor_catalog").thief;
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
    if (injured and try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 30, 35, now)) {
        return;
    }
    const target = sensed.enemy orelse {
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    if (actor.thief.sidestep_until) |until| {
        if (now < until and v.length(v.subtract(actor.thief.destination, pose.position)) >= 16) {
            actor.threat_position = actor.thief.destination;
            actor.mode = .chase;
            return;
        }
        actor.thief.sidestep_until = null;
    }
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const tick = now >= actor.think_ms;
    if (tick) {
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    // Thief ranged callbacks explicitly schedule the next AI update one second away.
    if (actor.melee.active and now >= actor.thief.next_attack_ms) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
        actor.thief.next_attack_ms = now + (if (actor.melee.pose == 0) @as(i64, 1000) else 100);
        if (actor.thief.sidestep_until != null) {
            actor.threat_position = actor.thief.destination;
            actor.mode = .chase;
            return;
        }
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) actor.melee.active = false;
    }
    if (!actor.melee.active and tick and facing and sensed.visible) {
        const random = try world.get(entity, data.Random);
        if (policy.inRange(sensed.distance, definition.range, definition.thief_knife.range, random.next(), random.next())) {
            actor.melee.begin(policy.select(sensed.distance), now);
            actor.changed_ms = now;
            actor.thief.next_attack_ms = now;
        }
    }
    actor.mode = if (actor.melee.active) .attack else .chase;
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: Ref, facing: bool, now: i64) !void {
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (!facing) return;
    const index = actor.melee.pose;
    if (!actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false)) return;
    if (index == 0) {
        if (!try @import("actor_aim.zig").clearProjectile(world, slots, entity, target, pose, definition.thief_knife, 0)) {
            if (try @import("actor_motion.zig").sidestep(pose, (try world.get(entity, data.Body)).*, (try world.get(entity, data.Binding)).slot, (try world.get(entity, data.Random)).next())) |point| {
                actor.thief.destination = point;
                actor.thief.sidestep_until = now + 2000;
                actor.melee.active = false;
            }
            return;
        }
        return @import("shafts.zig").launch(world, slots, projections, entity, target, pose, .thief, definition.thief_knife, now);
    }
    const aim = try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(entity, data.Random));
    const hit = try @import("region_collision.zig").trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SHOT });
    if (@import("region_access.zig").victim(world, slots, hit)) |victim| {
        if ((victim.get(data.Health) catch null) == null) return;
        const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
        _ = try @import("damage.zig").apply(victim.world, victim.entity, @intFromFloat(@ceil(amount)), now, .{ .source = try world.persistentId(entity), .attacker_class = "monster_thief" });
        if (definition.second_attack_sounds[index].len > 0) try @import("events.zig").sound(world, slots, projections, definition.second_attack_sounds[index], pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_WEAPON, now);
    }
}
