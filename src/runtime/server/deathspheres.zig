// SPDX-License-Identifier: GPL-2.0-or-later
//! DeathSphere charge/volley controller and its authored aerial evasions.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const policy = @import("actor_catalog").deathsphere;
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    const state = &actor.deathsphere;
    const slot = (try world.get(entity, data.Binding)).slot;
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        const hurt = (try world.get(entity, data.Hurt)).*;
        const injured = hurt.revision != actor.receipt;
        const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
        if (actor.reaction_until_ms) |until| if (now >= until) {
            actor.reaction_until_ms = null;
        };
        if (injured and hurt.amount > 0 and now > actor.pain_ready_ms and @as(u8, @intFromFloat((try world.get(entity, data.Random)).next() * 99.9)) < 10) {
            // Supplied DeathSphere has no hita. The failed force-sequence request
            // retains the current pose; the pain task returns at its next tick.
            const sequence = if (actor.melee.active) definition.attacks[actor.melee.pose] else if (actor.mode == .chase) definition.run else definition.idle;
            actor.pain_ready_ms = now + @divTrunc(@as(i64, sequence.last - sequence.first) * 1000, sequence.fps);
            actor.reaction_until_ms = now + 100;
        }
        if (actor.reaction_until_ms == null) {
            if (sensed.enemy) |target| {
                const enemy = (try world.get(target, data.Transform)).position;
                face(pose, enemy, definition);
                const previous = state.phase;
                switch (state.phase) {
                    .chase => {
                        if (sensed.visible and sensed.distance <= definition.attack_range) {
                            state.phase = .charge;
                            state.charge_ms = now + 750;
                            actor.melee.begin(1, now);
                            velocity.linear = @splat(0);
                            try sound(world, slots, projections, entity, pose.position, "e1/m_dspherechargea.wav", now);
                        } else try move(actors, pose.*, body, velocity, enemy, slot, definition.speed * slow);
                    },
                    .charge => {
                        velocity.linear = @splat(0);
                        if (now > state.charge_ms) {
                            if (facing(pose.*, enemy)) {
                                state.phase = .attack;
                                state.boost_frame = -1;
                                state.extra = 0;
                                actor.melee.begin(0, now);
                            } else try avoid(actors, world, slots, projections, entity, actor, pose.*, now);
                        }
                    },
                    .attack => {
                        if (try @import("actor_evasion.zig").targeted(world, entity, target, pose.*) and (try world.get(entity, data.Random)).next() >= 0.5) {
                            try avoid(actors, world, slots, projections, entity, actor, pose.*, now);
                        } else if (try obstructed(world, slots, pose.*, body, enemy, slot)) {
                            sidestep(actor, pose.*, enemy, definition.attack_range, (try world.get(entity, data.Random)).next(), now);
                        } else {
                            const first = actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[0]) * 1000, definition.attacks[0].fps), now, false);
                            const frame = definition.attacks[0].frame(now - actor.melee.started_ms, false);
                            var fire = first;
                            if (first) state.boost_frame = frame + 4 else fire = state.extraVolley(frame);
                            if (fire) {
                                try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                                for (policy.muzzles) |offset| {
                                    var tuning = definition.death_bolt;
                                    tuning.offset = offset;
                                    tuning.spread = @splat(0);
                                    try @import("actor_lasers.zig").deathbolt(world, slots, projections, entity, target, pose.*, tuning, now);
                                }
                            }
                            if (now - actor.melee.started_ms >= definition.attacks[0].duration()) {
                                state.phase = .chase;
                                actor.melee.active = false;
                            }
                        }
                    },
                    .move, .sidestep => {
                        const limit: f32 = if (state.phase == .move) 34 else definition.speed * 0.1;
                        if (now > state.until_ms or v.length(v.subtract(state.destination, pose.position)) < limit) {
                            state.phase = if (state.phase == .sidestep) .chase else switch (state.resume_phase) {
                                .chase => .chase,
                                .charge => .charge,
                                .recover => .recover,
                            };
                            if (state.phase == .chase) actor.melee.active = false;
                        } else try move(actors, pose.*, body, velocity, state.destination, slot, definition.speed * slow);
                    },
                    .recover => if (now - actor.melee.started_ms >= definition.attacks[2].duration()) {
                        state.phase = .chase;
                        actor.melee.active = false;
                    },
                }
                if (previous != state.phase) actor.changed_ms = now;
                actor.mode = if (state.phase == .charge or state.phase == .attack or state.phase == .recover) .attack else .chase;
            } else if (state.phase == .move) {
                if (now > state.until_ms or v.length(v.subtract(state.destination, pose.position)) < 34) {
                    state.phase = .chase;
                    actor.melee.active = false;
                } else try move(actors, pose.*, body, velocity, state.destination, slot, definition.speed * slow);
                actor.mode = .chase;
            } else {
                state.phase = .chase;
                actor.melee.active = false;
                actor.mode = .idle;
                velocity.linear = @splat(0);
            }
        }
        const ceiling = try height(pose.position, slot, 300);
        const floor = try height(pose.position, slot, -300);
        if (state.phase != .move and (ceiling < 32 or floor < 32)) {
            const amount = 96 + 128 * (try world.get(entity, data.Random)).next();
            // The supplied callback's "up" angle is (0,0,1), whose forward is +X.
            const destination: ?v.Vec3 = if (ceiling < 32) v.add(pose.position, .{ 0, 0, -amount }) else actors.air_routes.nearest(v.add(pose.position, .{ amount, 0, 0 }));
            if (destination) |point| {
                state.resume_phase = if (state.phase == .charge) .charge else if (state.phase == .attack) .recover else .chase;
                state.phase = .move;
                state.destination = point;
                state.until_ms = now + 250;
                actor.melee.begin(2, now);
                try sound(world, slots, projections, entity, pose.position, "e1/m_dspheresteama.wav", now);
            }
        } else if (ceiling >= 32 and floor >= 32) {
            velocity.linear[2] += policy.bobImpulse(state.bob);
            state.bob = if (state.bob == 11) 0 else state.bob + 1;
        }
    }
    try @import("actor_flight.zig").move(pose, body, velocity, slot, elapsed);
    actor.ground_entity = c.ENTITYNUM_NONE;
}
fn height(point: v.Vec3, slot: u16, offset: f32) !f32 {
    const hit = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, offset }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = if (offset > 0) c.MASK_SOLID else c.MASK_SOLID | c.CONTENTS_BODY });
    return hit.fraction * @abs(offset);
}
fn face(pose: *data.Transform, point: v.Vec3, definition: Definition) void {
    const delta = v.subtract(point, pose.position);
    const angles: [2]f32 = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi };
    for (angles, [_]f32{ definition.pitch_speed, definition.yaw_speed }, 0..) |angle, speed, i| pose.angles[i] += std.math.clamp(@mod(angle - pose.angles[i] + 180, 360) - 180, -speed, speed);
}
fn facing(pose: data.Transform, point: v.Vec3) bool {
    const delta = v.subtract(point, pose.position);
    const pitch = -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi;
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    return @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 2 and @abs(@mod(pitch - pose.angles[0] + 180, 360) - 180) <= 10;
}
fn move(actors: *@import("actors.zig").Actors, pose: data.Transform, body: data.Body, velocity: *data.Velocity, point: v.Vec3, slot: u16, speed: f32) !void {
    if (try actors.air_routes.next(pose.position, point, body, slot)) |goal| velocity.linear = v.scale(v.normalize(v.subtract(goal, pose.position)), speed) else velocity.linear = @splat(0);
}
fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, point: v.Vec3, name: []const u8, now: i64) !void {
    try @import("events.zig").sound(world, slots, projections, name, point, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
fn obstructed(world: *data.World, slots: *Slots, pose: data.Transform, body: data.Body, enemy: v.Vec3, slot: u16) !bool {
    const ahead = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(v.basis(pose.angles).forward, 64)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID });
    if (ahead.fraction < 1) return true;
    const sight = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(enemy, .{ 0, 0, -24 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
    if (sight.entity < slots.occupants.len) if (slots.occupants[sight.entity]) |other| return (world.get(other, data.Actor) catch null) != null and (world.get(other, data.Health) catch return false).current > 0;
    return false;
}
fn sidestep(actor: *data.Actor, pose: data.Transform, enemy: v.Vec3, range: f32, roll: f32, now: i64) void {
    const direction = v.normalize(v.subtract(pose.position, enemy));
    const side: u8 = @intFromFloat(roll * 6);
    const pitch = -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi - 40 + (if (side >= 4) @as(f32, 25) else if (side >= 2) @as(f32, -10) else 0);
    const yaw = std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi + (if (side % 2 == 0) @as(f32, 45) else -45);
    actor.deathsphere.destination = v.add(enemy, v.scale(v.basis(.{ pitch, yaw, 0 }).forward, range * 0.5));
    actor.deathsphere.phase = .sidestep;
    actor.deathsphere.until_ms = now + 2000;
    actor.melee.begin(2, now);
}
fn avoid(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, now: i64) !void {
    const slot = (try world.get(entity, data.Binding)).slot;
    actor.deathsphere.destination = (try @import("actor_air_avoid.zig").choose(actors, pose, slot, try world.get(entity, data.Random), 500, 20)).point;
    actor.deathsphere.phase = .move;
    actor.deathsphere.resume_phase = .chase;
    actor.deathsphere.until_ms = now + 250;
    actor.melee.begin(2, now);
    try sound(world, slots, projections, entity, pose.position, "e1/m_dspheresteama.wav", now);
}
