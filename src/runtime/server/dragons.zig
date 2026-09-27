// SPDX-License-Identifier: GPL-2.0-or-later
//! Active Dragon combat: hover, breath warning and the authored fireball event.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, definition: Definition, now: i64, elapsed: u32) !void {
    const state = &actor.dragon;
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        const hurt = (try world.get(entity, data.Hurt)).*;
        const injured = hurt.revision != actor.receipt;
        const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
        if (actor.reaction_until_ms) |until| if (now >= until) {
            actor.reaction = null;
            actor.reaction_until_ms = null;
        };
        if (injured and hurt.amount > 0 and now > actor.pain_ready_ms and @as(u8, @intFromFloat((try world.get(entity, data.Random)).next() * 99.9)) < 75) {
            const hit = definition.pain[0] orelse return error.MissingDragonPain;
            actor.reaction = hit;
            actor.reaction_started_ms = now;
            actor.reaction_until_ms = now + hit.duration();
            actor.pain_ready_ms = now + @divTrunc(@as(i64, hit.last - hit.first) * 1000, hit.fps);
            actor.melee.active = false;
            state.phase = .choose;
            state.breath_until_ms = null;
        }
        velocity.linear = @splat(0);
        if (actor.reaction_until_ms != null) {
            actor.mode = .idle;
        } else if (sensed.enemy) |target| {
            const enemy = (try world.get(target, data.Transform)).position;
            const delta = v.subtract(enemy, pose.position);
            const angles: [2]f32 = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi };
            for (angles, [_]f32{ definition.pitch_speed, definition.yaw_speed }, 0..) |angle, speed, i| pose.angles[i] += std.math.clamp(@mod(angle - pose.angles[i] + 180, 360) - 180, -speed, speed);
            pose.angles[2] = 0;
            switch (state.phase) {
                .choose => {
                    if (sensed.visible) {
                        state.phase = .hover;
                        state.until_ms = now + 1000 + @as(i64, @intFromFloat((try world.get(entity, data.Random)).next() * 2000));
                        actor.melee.begin(1, now);
                        try @import("events.zig").sound(world, slots, projections, "e3/m_dragonsighta.wav", pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
                    } else actor.threat = 0;
                },
                .hover => if (now >= state.until_ms) {
                    state.phase = .attack;
                    actor.melee.begin(0, now);
                    state.breath_emitted = false;
                    state.breath_until_ms = null;
                },
                .attack => {
                    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                    if (!state.breath_emitted and now > actor.melee.started_ms + 1100) {
                        state.breath_emitted = true;
                        state.breath_until_ms = now + 850;
                        state.breath_direction = v.normalize(delta);
                    }
                    if (state.breath_until_ms) |until| if (now > until) {
                        state.breath_until_ms = null;
                    };
                    if (actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[0]) * 1000, definition.attacks[0].fps), now, false)) try @import("actor_fireballs.zig").launch(world, slots, projections, entity, target, pose.*, .dragon, definition.dragon_fireball, now);
                    if (now - actor.melee.started_ms >= definition.attacks[0].duration()) {
                        state.phase = .choose;
                        actor.melee.active = false;
                        state.breath_until_ms = null;
                    }
                },
            }
            actor.mode = if (actor.melee.active) .attack else .idle;
        } else {
            state.phase = .choose;
            state.breath_until_ms = null;
            actor.melee.active = false;
            actor.mode = .idle;
        }
    }
    try @import("actor_flight.zig").move(pose, body, velocity, (try world.get(entity, data.Binding)).slot, elapsed);
    actor.ground_entity = c.ENTITYNUM_NONE;
}
pub fn patrol(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, now: i64) !void {
    if (now <= actor.dragon.ambient_ms) return;
    actor.dragon.ambient_ms = now + 5000;
    const random = try world.get(entity, data.Random);
    if (random.next() < 0.25) try @import("events.zig").sound(world, slots, projections, if (random.next() > 0.5) "e3/m_dragonsighta.wav" else "e3/m_dragonsightb.wav", pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
