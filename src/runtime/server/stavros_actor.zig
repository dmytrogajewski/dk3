// SPDX-License-Identifier: GPL-2.0-or-later
//! Stavros uses the stave callback with his own attack/pain and pitch-facing rules.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").stavros;
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        const hurt = (try world.get(entity, data.Hurt)).*;
        const injured = hurt.revision != actor.receipt;
        const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
        if (actor.reaction_until_ms) |until| if (now >= until) {
            actor.reaction = null;
            actor.reaction_until_ms = null;
        };
        if (injured) _ = try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, policy.pain_chance, policy.pain_limit, now);
        if (actor.reaction_until_ms != null) actor.mode = .idle else if (sensed.enemy) |target| {
            const delta = v.subtract((try target.get(data.Transform)).position, pose.position);
            const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
            const pitch = -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi;
            pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
            pose.angles[0] += std.math.clamp(@mod(pitch - pose.angles[0] + 180, 360) - 180, -definition.pitch_speed, definition.pitch_speed);
            const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) < 5 and @abs(@mod(pitch - pose.angles[0] + 180, 360) - 180) < 5;
            if (actor.melee.active) {
                actor.mode = .attack;
                try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                if (facing and actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[0]) * 1000, definition.attacks[0].fps), now, false)) try @import("meteors.zig").launch(world, slots, projections, entity, target, pose.*, definition.stave, now);
                if (now - actor.melee.started_ms >= definition.attacks[0].duration()) actor.melee.active = false;
            }
            if (!actor.melee.active) {
                if (sensed.visible and sensed.distance < definition.range) {
                    actor.mode = .attack;
                    if (facing) {
                        actor.melee.begin(0, now);
                        actor.changed_ms = now;
                    }
                } else actor.mode = .chase;
            }
        } else {
            actor.mode = .idle;
            actor.melee.active = false;
        }
    }
    if (actor.mode != .chase) {
        velocity.linear[0] = 0;
        velocity.linear[1] = 0;
    }
    try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, actor.threat_position, definition.speed * slow, (try world.get(entity, data.Binding)).slot, now, elapsed);
}
