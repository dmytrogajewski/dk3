// SPDX-License-Identifier: GPL-2.0-or-later
//! Griffon air pursuit, authored landings and ground leaps.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const v = @import("../domain/vector.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const flight = @import("actor_flight.zig");
const policy = @import("actor_catalog").griffon;
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    const slot = (try world.get(entity, data.Binding)).slot;
    const state = &actor.griffon;
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        const hurt = (try world.get(entity, data.Hurt)).*;
        const injured = hurt.revision != actor.receipt;
        const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
        if (actor.reaction_until_ms) |until| if (now >= until) {
            actor.reaction = null;
            actor.reaction_until_ms = null;
        };
        if (injured and hurt.amount > 0 and now > actor.pain_ready_ms) {
            const random = try world.get(entity, data.Random);
            const custom = random.next() < 0.15;
            if (custom or @as(u8, @intFromFloat(random.next() * 99.9)) < 10) {
                const hit = definition.pain[if (custom and !state.flying) @as(usize, 1) else 0] orelse return error.MissingGriffonPain;
                actor.reaction = hit;
                actor.reaction_started_ms = now;
                actor.reaction_until_ms = now + hit.duration();
                actor.pain_ready_ms = now + @divTrunc(@as(i64, hit.last - hit.first) * 1000, hit.fps);
                actor.melee.active = false;
                state.phase = .chase;
                state.blocked = 0;
            }
        }
        if (actor.reaction_until_ms != null) {
            actor.mode = .idle;
            velocity.linear = @splat(0);
        } else if (sensed.enemy) |target| {
            const enemy = (try world.get(target, data.Transform)).position;
            const previous = state.phase;
            if (std.mem.eql(f32, &state.previous, &pose.position)) state.blocked +|= 1;
            state.previous = pose.position;
            switch (state.phase) {
                .chase => {
                    if (!state.flying and (@abs(enemy[2] - pose.position[2]) > 150 or !sensed.visible)) state.flying = true;
                    const target_slot = (try world.get(target, data.Binding)).slot;
                    const wet = try @import("actor_water.zig").level(pose.position, body.*, slot) > 0 or try @import("actor_water.zig").level(enemy, (try world.get(target, data.Body)).*, target_slot) > 0;
                    if (state.flying and wet) {
                        try retreat(actors, world, entity, actor, pose.*, body.*, enemy, definition, now);
                        if ((try world.get(entity, data.Random)).next() > 0.5) try sound(world, slots, projections, pose.position, slot, "e2/m_griffonsight.wav", now);
                    } else if (state.flying and try flight.roomHeight(pose.position, slot, 500) <= 250 and !try flight.liquidBelow(pose.position, slot, 8)) {
                        descend(actors, actor, pose.*, now);
                    } else if (sensed.visible and sensed.distance <= definition.range + 35) {
                        state.phase = .attack;
                        actor.melee.begin(if (state.flying) 2 else if ((try world.get(entity, data.Random)).next() > 0.5) 1 else 0, now);
                        if (!state.flying) velocity.linear = @splat(0);
                    } else if (!state.flying and sensed.visible and policy.wantsLeap(sensed.distance, (try world.get(entity, data.Random)).next())) {
                        state.phase = .leap;
                        state.destination = enemy;
                        state.started_ms = now;
                        velocity.linear = v.scale(v.normalize(v.subtract(enemy, pose.position)), definition.speed * 1.65);
                        velocity.linear[2] = definition.upward_speed * 1.1;
                        pose.angles[1] = std.math.atan2(velocity.linear[1], velocity.linear[0]) * 180 / std.math.pi;
                        // Preserve the launch lift, but trace it to avoid moving through a ceiling.
                        const lift = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 0, 0, 10 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
                        pose.position = lift.end;
                        actor.melee.begin(4, now);
                    } else if (state.flying and state.blocked > 2) {
                        try retreat(actors, world, entity, actor, pose.*, body.*, enemy, definition, now);
                    } else if (state.flying) {
                        const goal = v.add(enemy, .{ 0, 0, definition.range - 10 });
                        if (try actors.air_routes.next(pose.position, goal, body.*, slot)) |point| flight.steer(pose, velocity, point, definition.speed * 1.15 * slow, 0.05) else velocity.linear = @splat(0);
                    } else try @import("actor_floor.zig").orient(world, entity, pose, definition.pitch_speed);
                },
                .descend => {
                    flight.steer(pose, velocity, state.destination, definition.speed * slow, 0.45);
                    pose.angles[0] = 0;
                    pose.angles[2] = 0;
                    if (v.length(v.subtract(state.destination, pose.position)) <= 100 or state.blocked > 7) {
                        state.phase = .land;
                        actor.melee.begin(3, now);
                        try sound(world, slots, projections, pose.position, slot, "e2/m_griffondrop.wav", now);
                    }
                },
                .land => if (now - actor.melee.started_ms >= definition.attacks[3].duration()) {
                    state.flying = false;
                    state.phase = .chase;
                    actor.melee.active = false;
                },
                .retreat => {
                    if (v.length(v.subtract(state.destination, pose.position)) <= 90 or (state.until_ms != null and now >= state.until_ms.?)) {
                        state.phase = .chase;
                    } else if (state.blocked > 2) {
                        if (sensed.visible) try retreat(actors, world, entity, actor, pose.*, body.*, enemy, definition, now) else state.phase = .chase;
                    } else if (try actors.air_routes.next(pose.position, state.destination, body.*, slot)) |point| flight.steer(pose, velocity, point, definition.speed * slow, 0.05) else velocity.linear = @splat(0);
                },
                .leap => if (now - state.started_ms >= 1000 or v.length(v.subtract(state.destination, pose.position)) <= 100) {
                    state.phase = .chase;
                    actor.melee.active = false;
                    if (sensed.distance <= 150) {
                        try sound(world, slots, projections, pose.position, slot, "e2/m_griffonataka.wav", now);
                        const source = try world.persistentId(entity);
                        if (try @import("weapon_damage.zig").hurt(world, target, source, 0, 15, now, false)) try @import("weapon_damage.zig").shove(world, target, source, v.normalize(v.subtract(enemy, pose.position)), 15, now);
                    } else if ((try world.get(entity, data.Random)).next() > 0.3) try sound(world, slots, projections, pose.position, slot, "e2/m_griffonsight.wav", now);
                },
                .attack => {
                    const delta = v.subtract(enemy, pose.position);
                    const wanted: [3]f32 = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
                    for (wanted, [_]f32{ definition.pitch_speed, definition.yaw_speed, 9 }, 0..) |angle, speed, i| pose.angles[i] += std.math.clamp(@mod(angle - pose.angles[i] + 180, 360) - 180, -speed, speed);
                    const index = actor.melee.pose;
                    const first = actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false);
                    const second = if (!first) actor.melee.event(2, @divTrunc(@as(i64, definition.second_strikes[index].?) * 1000, definition.attacks[index].fps), now, false) else false;
                    if (first or second) {
                        try @import("actor_melee.zig").punch(world, slots, entity, target, pose.*, definition, now);
                        try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                        if (state.flying and !try flight.liquidBelow(pose.position, slot, 8)) descend(actors, actor, pose.*, now);
                    }
                    if (state.phase == .attack and now - actor.melee.started_ms >= definition.attacks[index].duration()) {
                        actor.melee.active = false;
                        state.phase = .chase;
                    }
                },
            }
            if (previous != state.phase) {
                actor.changed_ms = now;
                state.blocked = 0;
            }
            actor.mode = if (state.phase == .attack or state.phase == .land or state.phase == .leap) .attack else .chase;
        } else {
            state.flying = true;
            state.phase = .chase;
            actor.melee.active = false;
            actor.mode = .idle;
            velocity.linear = @splat(0);
        }
    }
    if (state.phase == .leap) {
        try flight.bounce(pose, body.*, velocity, slot, elapsed, 800, 2, false);
        actor.ground_entity = c.ENTITYNUM_NONE;
        body.grounded = false;
    } else if (state.flying) {
        try flight.move(pose, body.*, velocity, slot, elapsed);
        actor.ground_entity = c.ENTITYNUM_NONE;
        body.grounded = false;
    } else try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, actor.threat_position, definition.speed * slow, slot, now, elapsed);
}
fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, point: v.Vec3, slot: u16, name: []const u8, now: i64) !void {
    try @import("events.zig").sound(world, slots, projections, name, point, slot, c.CHAN_AUTO, now);
}
fn descend(actors: *@import("actors.zig").Actors, actor: *data.Actor, pose: data.Transform, now: i64) void {
    actor.melee.active = false;
    actor.griffon.phase = .chase;
    if (actors.water_routes.nearest(pose.position)) |point| {
        actor.griffon.phase = .descend;
        actor.griffon.destination = point;
        actor.griffon.blocked = 0;
        actor.changed_ms = now;
    }
}
fn retreat(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: data.Body, enemy: v.Vec3, definition: Definition, now: i64) !void {
    const escape = try @import("air_escape.zig").choose(world, entity, pose, body, enemy, &actors.air_routes, 250, 70, 15, &.{ .{ 1, 1, 1 }, .{ 1, 1, 0 }, .{ 1, 1, -1 } });
    actor.melee.active = false;
    actor.griffon.blocked = 0;
    if (escape) |value| {
        actor.griffon.phase = .retreat;
        actor.griffon.destination = value.point;
        actor.griffon.until_ms = now + @as(i64, @intFromFloat(value.distance / definition.speed * 1000));
    } else actor.griffon.phase = .chase;
}
