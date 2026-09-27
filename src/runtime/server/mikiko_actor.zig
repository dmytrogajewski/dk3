// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").mikiko;
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        const hurt = (try world.get(entity, data.Hurt)).*;
        const injured = hurt.revision != actor.receipt;
        const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
        const random = try world.get(entity, data.Random);
        if (sensed.enemy != null) {
            if (sensed.visible and !actor.mikiko.awakened) {
                actor.mikiko.awakened = true;
                actor.mikiko.aura = true;
                actor.mikiko.aura_started_ms = now;
                actor.mikiko.light_red = 1 + random.next();
            } else if (!sensed.visible and actor.mikiko.voice_pose == 1) {
                // The class clears acro_boost, not fatigue: this aura is one-shot.
                actor.mikiko.voice_pose = 0;
                actor.mikiko.aura = false;
            }
        }
        if (actor.reaction_until_ms) |until| if (now >= until) {
            actor.reaction = null;
            actor.reaction_until_ms = null;
        };
        if (injured) _ = try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 10, 35, now);
        if (actor.reaction_until_ms != null) actor.mode = .idle else if (@import("actor_evasion.zig").update(actor, pose.*, now)) {} else if (sensed.enemy) |target| {
            const delta = v.subtract((try world.get(target, data.Transform)).position, pose.position);
            const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
            pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
            const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) < 5;
            if (actor.melee.active) {
                actor.mode = .attack;
                const sequence = definition.attacks[actor.melee.pose];
                if (policy.sound(actor.mikiko.voice_pose, sequence.frame(now - actor.melee.started_ms, false))) |sound| try @import("events.zig").sound(world, slots, projections, sound, pose.position, (try world.get(entity, data.Binding)).slot, abi.c.CHAN_AUTO, now);
                const dodge = try @import("actor_evasion.zig").targeted(world, entity, target, pose.*) and random.next() >= 0.5;
                if (facing) {
                    const first = actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[actor.melee.pose]) * 1000, sequence.fps), now, false);
                    const second = if (!first) if (definition.second_strikes[actor.melee.pose]) |frame| actor.melee.event(2, @divTrunc(@as(i64, frame) * 1000, sequence.fps), now, false) else false else false;
                    if (first or second) try @import("actor_melee.zig").punch(world, slots, entity, target, pose.*, definition, now);
                }
                if (now - actor.melee.started_ms >= sequence.duration()) actor.melee.active = false;
                // A queued dodge does not cancel the strike in this callback.
                if (dodge) _ = try @import("actor_evasion.zig").dodge(&actors.water_routes, world, entity, target, actor, pose.*, now);
            }
            if (!actor.melee.active and actor.evasion.until_ms == null) {
                if (sensed.visible and sensed.distance < definition.attack_range) {
                    actor.mode = .attack;
                    if (facing) {
                        const selected: u2 = @intFromFloat(@min(2, random.next() * 3));
                        actor.melee.begin(selected, now);
                        actor.mikiko.voice_pose = selected;
                        actor.changed_ms = now;
                    }
                } else actor.mode = .chase;
            }
        } else {
            actor.mode = .idle;
            actor.melee.active = false;
        }
    }
    const slot = (try world.get(entity, data.Binding)).slot;
    if (try @import("actor_water.zig").level(pose.position, body.*, slot) >= 2) {
        _ = try @import("actor_water.zig").move(&actors.water_routes, actor, pose, body, velocity, definition.speed * slow, slot, elapsed);
    } else {
        if (actor.mode != .chase) {
            velocity.linear[0] = 0;
            velocity.linear[1] = 0;
        }
        try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, actor.threat_position, definition.speed * slow, slot, now, elapsed);
    }
}
