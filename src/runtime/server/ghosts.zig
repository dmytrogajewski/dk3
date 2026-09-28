// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("actor_catalog");
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, now: i64, elapsed: u32) !bool {
    const definition = actors.table.definitions[actor.definition];
    const state = &actor.ghost;
    const slot = (try world.get(entity, data.Binding)).slot;
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        if ((try world.get(entity, data.Health)).current <= 0) state.fade(now);
        if (state.owner != 0) {
            const owner = world.find(state.owner);
            const owner_actor = if (owner) |parent| world.get(parent, data.Actor) catch null else null;
            if (owner_actor == null or (try world.get(owner.?, data.Health)).current <= 0 or !owner_actor.?.kage.recharging()) state.fade(now);
        }
        if (state.phase == .fading) {
            actor.melee.active = false;
            actor.mode = .chase;
            state.alpha -= 0.02;
            if (state.alpha < 0.1) {
                try @import("weapon_entities.zig").remove(world, slots, projections, entity);
                return true;
            }
        } else {
            const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
            if (sensed.enemy) |target| {
                const point = (try target.get(data.Transform)).position;
                switch (state.phase) {
                    .dormant => {
                        state.phase = .waking;
                        state.started_ms = now;
                        actor.mode = .idle;
                        actor.changed_ms = now;
                    },
                    .waking => {
                        if (now - state.started_ms >= definition.idle.duration()) {
                            state.alpha = 0.4;
                            state.phase = .chase;
                            state.started_ms = now;
                        } else state.alpha += 0.04;
                    },
                    .chase => {
                        actor.mode = .chase;
                        if (now - state.started_ms >= definition.run.duration()) {
                            state.started_ms = now;
                            if (now > state.sound_ready_ms) {
                                for (slots.occupants) |maybe| if (maybe) |other| if (world.get(other, data.Actor) catch null) |value| if (catalog.entries[value.definition].kind == .ghost) {
                                    state.sound_ready_ms = @max(state.sound_ready_ms, value.ghost.sound_ready_ms);
                                };
                                if (now > state.sound_ready_ms) {
                                    state.sound_ready_ms = now + 4000;
                                    for (slots.occupants) |maybe| if (maybe) |other| if (world.get(other, data.Actor) catch null) |value| if (catalog.entries[value.definition].kind == .ghost) {
                                        value.ghost.sound_ready_ms = state.sound_ready_ms;
                                    };
                                    try @import("events.zig").sound(world, slots, projections, if ((try world.get(entity, data.Random)).next() > 0.5) "e4/m_kage_ghost_attack.wav" else "e4/m_kage_ghost_am.wav", pose.position, slot, abi.c.CHAN_AUTO, now);
                                }
                            }
                        }
                        if (sensed.visible and sensed.distance < 128) {
                            state.phase = .attack;
                            actor.mode = .attack;
                            actor.melee.begin(0, now);
                        } else if (try actors.air_routes.next(pose.position, v.add(point, .{ 0, 0, 8 }), body, slot)) |destination| {
                            @import("actor_flight.zig").steer(pose, velocity, destination, definition.speed, 0.03);
                        } else velocity.linear = @splat(0);
                    },
                    .attack => {
                        actor.mode = .attack;
                        const sequence = definition.attacks[0];
                        if (actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[0]) * 1000, sequence.fps), now, false)) {
                            try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                            _ = try @import("weapon_damage.zig").hurt(target.world, target.entity, try world.persistentId(entity), 0, 1 + 3 * (try world.get(entity, data.Random)).next(), now, false);
                        }
                        if (now - actor.melee.started_ms >= sequence.duration()) {
                            state.fade(now);
                            actor.melee.active = false;
                        } else if (sensed.distance > definition.attack_range) {
                            state.phase = .chase;
                            state.started_ms = now;
                            actor.melee.active = false;
                        }
                    },
                    .fading => unreachable,
                }
            } else {
                actor.mode = .idle;
                actor.melee.active = false;
                velocity.linear = @splat(0);
                if (state.phase == .attack) state.phase = .chase;
            }
        }
    }
    try @import("actor_flight.zig").move(pose, body, velocity, slot, elapsed);
    actor.ground_entity = abi.c.ENTITYNUM_NONE;
    return false;
}
