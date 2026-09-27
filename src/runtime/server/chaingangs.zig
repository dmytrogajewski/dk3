// SPDX-License-Identifier: GPL-2.0-or-later
//! Chaingang combat and terrain-mode transitions, driven by supplied sequences.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const flight = @import("actor_flight.zig");
pub fn initialize(world: *data.World, entity: ecs.Entity, now: i64) !void {
    const actor = try world.get(entity, data.Actor);
    const pose = (try world.get(entity, data.Transform)).*;
    actor.chaingang.flying = (try floorTrace(pose.position, (try world.get(entity, data.Binding)).slot)).fraction * 500 >= 100;
    actor.chaingang.strafe_ms = now;
    actor.chaingang.start_position = pose.position;
}
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    const state = &actor.chaingang;
    const slot = (try world.get(entity, data.Binding)).slot;
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
            const hit = definition.pain[0] orelse return error.MissingChaingangPain;
            actor.reaction = hit;
            actor.reaction_started_ms = now;
            actor.reaction_until_ms = now + hit.duration();
            actor.pain_ready_ms = now + @divTrunc(@as(i64, hit.last - hit.first) * 1000, hit.fps);
            actor.melee.active = false;
            state.phase = .chase;
        }
        if (actor.reaction_until_ms != null) {
            velocity.linear = @splat(0);
            actor.mode = .idle;
        } else if (sensed.enemy) |target| {
            const enemy = (try world.get(target, data.Transform)).position;
            const previous = state.phase;
            switch (state.phase) {
                .chase => {
                    if (try terrain(actors, world, target, entity, actor, pose.*, slot, definition, now)) {
                        velocity.linear = @splat(0);
                    } else if (sensed.visible and sensed.distance <= definition.range) {
                        state.phase = .attack;
                        actor.melee.begin(if (state.flying) 3 else 2, now);
                        velocity.linear = @splat(0);
                    } else if (state.flying and (try wet(pose.position, body.*, slot) or try wet(enemy, (try world.get(target, data.Body)).*, (try world.get(target, data.Binding)).slot))) {
                        try wander(actors, world, entity, actor, pose.*, definition, now);
                    } else if (state.flying) try moveAir(actors, pose, body.*, velocity, enemy, slot, definition.speed * slow);
                },
                .attack => {
                    face(pose, enemy, definition, state.flying);
                    if (state.flying and (try wet(pose.position, body.*, slot) or try wet(enemy, (try world.get(target, data.Body)).*, (try world.get(target, data.Binding)).slot))) {
                        try wander(actors, world, entity, actor, pose.*, definition, now);
                    } else {
                        if (state.flying) try strafe(actors, world, entity, actor, pose.*, body.*, velocity, enemy, definition, slow, now) else velocity.linear = @splat(0);
                        const sequence = definition.attacks[actor.melee.pose];
                        const ended = now - actor.melee.started_ms >= sequence.duration();
                        if (ended and actor.melee.pose < 2 and !state.flying) {
                            if (!try terrain(actors, world, target, entity, actor, pose.*, slot, definition, now)) try dodge(actors, world, entity, actor, pose.*, body.*);
                        } else if (ended) {
                            if (!sensed.visible or sensed.distance > definition.attack_range) {
                                state.phase = .chase;
                                actor.melee.active = false;
                            } else if (facing(pose.*, enemy)) {
                                actor.melee.begin(if (state.flying) 1 else 0, now);
                            }
                        }
                        if (state.phase == .attack and actor.melee.pose < 2) {
                            const index = actor.melee.pose;
                            const ready = actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false);
                            if ((ready and facing(pose.*, enemy)) or state.burst > 0) {
                                if (try obstructed(world, slots, pose.*, body.*, enemy, slot)) {
                                    try dodge(actors, world, entity, actor, pose.*, body.*);
                                    state.burst = 0;
                                } else {
                                    if (state.burst % 7 != 0) try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                                    if (state.gunTick()) try @import("gunner_bursts.zig").launch(world, slots, projections, entity, target, pose.*, .chaingang, false, .{ .damage = definition.damage, .random_damage = definition.random_damage, .range = definition.range, .offset = definition.offset, .spread = definition.spread }, now);
                                }
                            }
                        }
                    }
                },
                .dodge, .approach_land, .wander => {
                    const delta = v.subtract(state.destination, pose.position);
                    const moving_speed = if (state.phase == .wander) definition.walk_speed else definition.speed;
                    const close = @sqrt(delta[0] * delta[0] + delta[1] * delta[1]) < moving_speed * (if (moving_speed > 175) @as(f32, 0.1) else 0.2) and @abs(delta[2]) < 32;
                    if (close or (state.phase != .dodge and now >= state.until_ms)) {
                        if (state.phase == .approach_land and close) {
                            state.phase = .landing;
                            actor.melee.begin(5, now);
                            try sound(world, slots, projections, entity, pose.position, "e4/m_chgangjetland.wav", now);
                        } else if (state.phase == .wander and close and (try wet(pose.position, body.*, slot) or try wet(enemy, (try world.get(target, data.Body)).*, (try world.get(target, data.Binding)).slot))) {
                            try wander(actors, world, entity, actor, pose.*, definition, now);
                        } else state.phase = .chase;
                        velocity.linear = @splat(0);
                    } else if (state.flying) try moveAir(actors, pose, body.*, velocity, state.destination, slot, moving_speed * slow);
                },
                .takeoff => {
                    const frame = definition.attacks[4].frame(now - actor.melee.started_ms, false);
                    if (frame >= 293 and frame <= 294) try sound(world, slots, projections, entity, pose.position, "e4/m_chgangjetsrta.wav", now);
                    if (frame >= 299) {
                        state.phase = .rising;
                        state.flying = true;
                        state.started_ms = now;
                        pose.angles[0] = 0;
                        pose.angles[2] = 0;
                        velocity.linear = .{ 0, 0, 275 };
                    }
                },
                .rising => if (now - state.started_ms > 750) {
                    state.phase = .chase;
                    actor.melee.active = false;
                    try sound(world, slots, projections, entity, pose.position, "e4/m_chgangflya.wav", now);
                },
                .landing => if (definition.attacks[5].frame(now - actor.melee.started_ms, false) >= 316) {
                    state.phase = .settling;
                    state.started_ms = now;
                    pose.angles[0] = 0;
                    pose.angles[2] = 0;
                    velocity.linear = .{ 0, 0, 35 };
                    try sound(world, slots, projections, entity, pose.position, "e4/m_chgangjetland.wav", now);
                },
                .settling => if (now - state.started_ms > 500) {
                    state.phase = .chase;
                    state.flying = false;
                    actor.melee.active = false;
                },
            }
            if (previous != state.phase) actor.changed_ms = now;
            actor.mode = switch (state.phase) {
                .chase, .dodge, .approach_land, .wander => .chase,
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
fn floorTrace(point: v.Vec3, slot: u16) !@import("../domain/collision.zig").Trace {
    return engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -500 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
}
fn wet(point: v.Vec3, body: data.Body, slot: u16) !bool {
    return try engine.collisionService().contents(v.add(point, .{ 0, 0, body.mins[2] + 1 }), slot) & c.MASK_WATER != 0;
}
fn terrain(actors: *@import("actors.zig").Actors, world: *data.World, target: ecs.Entity, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, slot: u16, definition: Definition, now: i64) !bool {
    const state = &actor.chaingang;
    const target_room = try flight.roomHeight((try world.get(target, data.Transform)).position, (try world.get(target, data.Binding)).slot, 500);
    const own_room = try flight.roomHeight(pose.position, slot, 500);
    const random = try world.get(entity, data.Random);
    if (state.flying and target_room < 250 and random.next() > 0.45) {
        if (try flight.liquidBelow(pose.position, slot, 15)) return false;
        const floor = try floorTrace(pose.position, slot);
        const node = actors.water_routes.nearest(v.add(floor.end, .{ 0, 0, 50 })) orelse return false;
        state.destination = v.add(node, .{ 0, 0, 100 });
        state.phase = .approach_land;
        state.until_ms = now + 2000 + @as(i64, @intFromFloat(v.length(v.subtract(state.destination, pose.position)) / definition.speed * 1000));
        actor.melee.active = false;
        return true;
    }
    if (!state.flying and target_room > 350 and own_room > 350 and random.next() > 0.45) {
        state.phase = .takeoff;
        actor.melee.begin(4, now);
        return true;
    }
    return false;
}
fn face(pose: *data.Transform, point: v.Vec3, definition: Definition, flying: bool) void {
    const delta = v.subtract(point, pose.position);
    const desired: [2]f32 = .{ if (flying) -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi else 0, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi };
    for (desired, [_]f32{ definition.pitch_speed, definition.yaw_speed }, 0..) |angle, speed, i| pose.angles[i] += std.math.clamp(@mod(angle - pose.angles[i] + 180, 360) - 180, -speed, speed);
    pose.angles[2] = 0;
}
fn facing(pose: data.Transform, point: v.Vec3) bool {
    const delta = v.subtract(point, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    return @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) < 5;
}
fn moveAir(actors: *@import("actors.zig").Actors, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, point: v.Vec3, slot: u16, speed: f32) !void {
    if (try actors.air_routes.next(pose.position, point, body, slot)) |goal| {
        velocity.linear = v.scale(v.normalize(v.subtract(goal, pose.position)), speed);
        pose.angles = .{ 0, std.math.atan2(velocity.linear[1], velocity.linear[0]) * 180 / std.math.pi, 0 };
    } else velocity.linear = @splat(0);
}
fn dodge(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: data.Body) !void {
    actor.melee.active = false;
    actor.chaingang.phase = .chase;
    if (try @import("actor_dodge.zig").destination(actors, world, entity, pose, body)) |point| {
        actor.chaingang.destination = point;
        actor.chaingang.phase = .dodge;
    }
}
fn obstructed(world: *data.World, slots: *Slots, pose: data.Transform, body: data.Body, enemy: v.Vec3, slot: u16) !bool {
    const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(enemy, .{ 0, 0, -24 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |other| return (world.get(other, data.Actor) catch null) != null and (world.get(other, data.Health) catch return false).current > 0;
    return false;
}
fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, point: v.Vec3, name: []const u8, now: i64) !void {
    try @import("events.zig").sound(world, slots, projections, name, point, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
fn wander(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, now: i64) !void {
    const state = &actor.chaingang;
    const nearest = actors.air_routes.nearest(pose.position) orelse {
        actor.melee.active = false;
        state.phase = .chase;
        return;
    };
    for (actors.air_routes.nodes) |node| if (v.length(v.subtract(node.position, nearest)) < 0.01 and node.links.len != 0) {
        var choices: [6]usize = undefined;
        var count: usize = 0;
        for (node.links, 0..) |link, i| {
            const point = actors.air_routes.nodes[actors.air_routes.indices[@intCast(link[1])].?].position;
            const delta = v.subtract(point, pose.position);
            const horizontal = @sqrt(delta[0] * delta[0] + delta[1] * delta[1]);
            const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
            if (horizontal < definition.walk_speed * 0.2 and @abs(delta[2]) < 32) continue;
            if (v.length(v.subtract(point, state.start_position)) >= definition.sight_range or @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) > 90) continue;
            choices[count] = i;
            count += 1;
        }
        const roll = (try world.get(entity, data.Random)).next();
        const index: usize = if (count > 0) choices[@intFromFloat(roll * @as(f32, @floatFromInt(count)))] else @intFromFloat(roll * @as(f32, @floatFromInt(node.links.len)));
        state.destination = actors.air_routes.nodes[actors.air_routes.indices[@intCast(node.links[index][1])].?].position;
        state.phase = .wander;
        state.until_ms = now + 1000 + @as(i64, @intFromFloat(v.length(v.subtract(state.destination, pose.position)) / definition.walk_speed * 1000));
        actor.melee.active = false;
        return;
    };
}
fn strafe(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: data.Body, velocity: *data.Velocity, enemy: v.Vec3, definition: Definition, slow: f32, now: i64) !void {
    const state = &actor.chaingang;
    const random = try world.get(entity, data.Random);
    if (!state.swoop and state.strafe_ms <= now) {
        state.strafe_ms = now + 1500 + @as(i64, @intFromFloat(random.next() * 640 / definition.attack_speed * 1000));
        state.strafe = @intFromFloat(random.next() * 6);
        if (random.next() < 0.25) {
            state.swoop = true;
            state.strafe = @intFromFloat(random.next() * 2);
        }
    }
    const away = v.subtract(pose.position, enemy);
    const yaw = std.math.atan2(away[1], away[0]) * 180 / std.math.pi;
    const pitch: f32 = if (state.swoop) -15 else if (state.strafe >= 4) -15 else if (state.strafe >= 2) -50 else -40;
    const turn: f32 = if (state.swoop) 90 else 45;
    const distance = definition.attack_range * (if (state.swoop) @as(f32, 0.2) else 0.5);
    const goal = v.add(enemy, v.scale(v.basis(.{ pitch, yaw + turn * (if (state.strafe % 2 == 0) @as(f32, 1) else -1), 0 }).forward, distance));
    const speed = definition.speed * (if (state.swoop) @as(f32, 1.3) else 1) * slow;
    const direction = try @import("chaingang_collision.zig").steer(actors, pose, body, (try world.get(entity, data.Binding)).slot, v.normalize(v.subtract(goal, pose.position)), speed, v.length(velocity.linear) > 0, state, random);
    velocity.linear = v.scale(direction, speed);
    if (velocity.linear[0] > 1000) velocity.linear = v.scale(v.normalize(velocity.linear), definition.speed * slow);
    if (state.swoop and v.length(v.subtract(goal, pose.position)) < distance + 25) {
        state.swoop = false;
        state.strafe_ms = now + 3000;
    }
}
