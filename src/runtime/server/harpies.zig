// SPDX-License-Identifier: GPL-2.0-or-later
//! Harpy terrain transitions and magic-arrow combat. Its active movement mode is fly;
//! the reference's hover-only strafing callback is not selected by this class.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const flight = @import("actor_flight.zig");
const policy = @import("actor_catalog").harpy;
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    const slot = (try world.get(entity, data.Binding)).slot;
    const state = &actor.harpy;
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        const hurt = (try world.get(entity, data.Hurt)).*;
        const injured = hurt.revision != actor.receipt;
        const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
        if (actor.reaction_until_ms) |until| if (now >= until) {
            actor.reaction = null;
            actor.reaction_until_ms = null;
        };
        if (injured and try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 10, 25, now)) {
            if (!actor.melee.active) state.phase = .chase;
        }
        if (actor.reaction_until_ms != null) {
            velocity.linear = @splat(0);
            actor.mode = .idle;
        } else if (sensed.enemy) |target| {
            const enemy = (try target.get(data.Transform)).position;
            const previous = state.phase;
            switch (state.phase) {
                .chase => {
                    if (try terrain(actors, world, target, actor, pose.*, slot, definition, now)) {
                        velocity.linear = @splat(0);
                    } else if (sensed.visible and sensed.distance <= definition.harpy_arrow.range) {
                        state.phase = .attack;
                        velocity.linear = @splat(0);
                        const sequence = if (state.flying) definition.run else definition.ground_run;
                        state.warmup_started_ms = actor.changed_ms;
                        state.ready_ms = now + sequence.duration() - @mod(now - actor.changed_ms, sequence.duration());
                    } else if (state.flying) {
                        try moveAir(actors, pose, body.*, velocity, enemy, slot, definition.speed * slow);
                    }
                },
                .attack => {
                    velocity.linear = @splat(0);
                    face(pose, enemy, definition, state.flying);
                    const delta = v.subtract(enemy, pose.position);
                    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
                    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) < 5;
                    if (actor.melee.active and now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) {
                        actor.melee.active = false;
                        if (!state.flying) {
                            if (!try terrain(actors, world, target, actor, pose.*, slot, definition, now)) try dodge(actors, world, entity, actor, pose.*, body.*, now);
                        } else if (!sensed.visible or sensed.distance > definition.attack_range) state.phase = .chase;
                    }
                    if (state.phase == .attack and !actor.melee.active and now >= state.ready_ms and facing) {
                        actor.melee.begin(if (state.flying) 1 else 0, now);
                    }
                    if (state.phase == .attack and actor.melee.active) {
                        const index = actor.melee.pose;
                        if (actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false) and facing) {
                            try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                            if (try monsterInPath(world, slots, pose.*, body.*, enemy, slot)) {
                                try dodge(actors, world, entity, actor, pose.*, body.*, now);
                            } else {
                                try @import("shafts.zig").launch(world, slots, projections, entity, target, pose.*, .harpy, definition.harpy_arrow, now);
                                if (now < state.shot_ms) {
                                    state.phase = .chase;
                                    actor.melee.active = false;
                                }
                                state.shot_ms = now + 1000;
                            }
                        }
                    }
                },
                .dodge, .approach_land => {
                    const difference = v.subtract(state.destination, pose.position);
                    const close = @sqrt(difference[0] * difference[0] + difference[1] * difference[1]) < definition.speed * (if (definition.speed > 175) @as(f32, 0.1) else 0.2) and @abs(difference[2]) < 32;
                    if (close) {
                        if (state.phase == .approach_land) {
                            state.phase = .landing;
                            state.started_ms = now;
                            actor.melee.begin(2, now);
                        } else state.phase = .chase;
                        velocity.linear = @splat(0);
                    } else if (state.phase == .approach_land and state.until_ms != null and now >= state.until_ms.?) {
                        state.phase = .chase;
                        velocity.linear = @splat(0);
                    } else if (state.flying) {
                        try moveAir(actors, pose, body.*, velocity, state.destination, slot, definition.speed * slow);
                    } else actor.threat_position = state.destination;
                },
                .landing => {
                    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                    if (definition.attacks[2].frame(now - state.started_ms, false) >= 209) {
                        state.phase = .settling;
                        state.started_ms = now;
                        pose.angles[0] = 0;
                        pose.angles[2] = 0;
                        velocity.linear = .{ 0, 0, 35 };
                    }
                },
                .settling => if (now - state.started_ms > 500) {
                    state.flying = false;
                    state.phase = .chase;
                    actor.melee.active = false;
                },
                .takeoff => if (@as(i64, definition.attacks[2].last) - @divTrunc((now - state.started_ms) * definition.attacks[2].fps, 1000) <= 191) {
                    state.phase = .rising;
                    state.flying = true;
                    state.started_ms = now;
                    pose.angles[0] = 0;
                    pose.angles[2] = 0;
                    velocity.linear = .{ 0, 0, 275 };
                },
                .rising => if (now - state.started_ms > 750) {
                    state.phase = .chase;
                    actor.melee.active = false;
                },
            }
            if (previous != state.phase) actor.changed_ms = now;
            actor.mode = switch (state.phase) {
                .chase, .dodge, .approach_land => .chase,
                else => .attack,
            };
        } else {
            state.phase = .chase;
            actor.melee.active = false;
            actor.mode = .idle;
            velocity.linear = @splat(0);
        }
    }
    if (state.flying) {
        try flight.move(pose, body.*, velocity, slot, elapsed);
        actor.ground_entity = c.ENTITYNUM_NONE;
        body.grounded = false;
    } else {
        if (state.phase == .dodge) actor.threat_position = state.destination;
        try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, actor.threat_position, definition.speed * slow, slot, now, elapsed);
    }
}
fn terrain(actors: *@import("actors.zig").Actors, _: *data.World, target: Ref, actor: *data.Actor, pose: data.Transform, slot: u16, definition: Definition, now: i64) !bool {
    const target_room = try flight.roomHeight((try target.get(data.Transform)).position, (try target.get(data.Binding)).slot, 500);
    const own_room = try flight.roomHeight(pose.position, slot, 500);
    const state = &actor.harpy;
    switch (policy.transition(state.flying, target_room, own_room)) {
        .land => {
            const floor = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 0, 0, -500 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
            const node = actors.water_routes.nearest(v.add(floor.end, .{ 0, 0, 50 })) orelse return false;
            state.destination = v.add(node, .{ 0, 0, 85 });
            state.until_ms = now + 2000 + @as(i64, @intFromFloat(v.length(v.subtract(state.destination, pose.position)) / definition.speed * 1000));
            state.phase = .approach_land;
        },
        .fly => {
            state.phase = .takeoff;
            state.started_ms = now;
            actor.melee.begin(2, now);
        },
        .none => return false,
    }
    if (state.phase != .takeoff) actor.melee.active = false;
    return true;
}
fn face(pose: *data.Transform, point: v.Vec3, definition: Definition, flying: bool) void {
    const delta = v.subtract(point, pose.position);
    const angles: [2]f32 = .{ if (flying) -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi else 0, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi };
    for (angles, [_]f32{ definition.pitch_speed, definition.yaw_speed }, 0..) |angle, speed, i| pose.angles[i] += std.math.clamp(@mod(angle - pose.angles[i] + 180, 360) - 180, -speed, speed);
    pose.angles[2] = 0;
}
fn moveAir(actors: *@import("actors.zig").Actors, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, goal: v.Vec3, slot: u16, speed: f32) !void {
    if (try actors.air_routes.next(pose.position, goal, body, slot)) |point| {
        velocity.linear = v.scale(v.normalize(v.subtract(point, pose.position)), speed);
        pose.angles = .{ 0, std.math.atan2(velocity.linear[1], velocity.linear[0]) * 180 / std.math.pi, 0 };
    } else velocity.linear = @splat(0);
}
fn monsterInPath(world: *data.World, slots: *Slots, pose: data.Transform, body: data.Body, enemy: v.Vec3, slot: u16) !bool {
    const hit = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = v.add(enemy, .{ 0, 0, -24 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
    if (@import("region_access.zig").victim(world, slots, hit)) |other| {
        return (other.get(data.Actor) catch null) != null and (other.get(data.Health) catch return false).current > 0;
    }
    return false;
}
fn dodge(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: data.Body, now: i64) !void {
    actor.melee.active = false;
    actor.harpy.phase = .chase;
    if (try @import("actor_dodge.zig").destination(actors, world, entity, pose, body)) |point| {
        actor.harpy.destination = point;
        actor.harpy.phase = .dodge;
        actor.changed_ms = now;
    }
}
