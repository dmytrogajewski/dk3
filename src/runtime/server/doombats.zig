// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").doombat;
const Definition = @import("../domain/actors.zig").Definition;
pub fn fly(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, now: i64, elapsed: u32) !void {
    const definition = actors.table.definitions[actor.definition];
    const slot = (try world.get(entity, data.Binding)).slot;
    const state = &actor.doombat;
    if (state.speed == 0) state.speed = definition.speed;
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        const hurt = (try world.get(entity, data.Hurt)).*;
        const injured = hurt.revision != actor.receipt;
        const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
        if (actor.reaction_until_ms) |until| if (now >= until) {
            actor.reaction = null;
            actor.reaction_until_ms = null;
        };
        if (injured and hurt.amount > 0 and actor.reaction_until_ms == null and (try world.get(entity, data.Random)).next() < 0.75) if (definition.pain[0]) |hit| {
            actor.reaction = hit;
            actor.reaction_started_ms = now;
            actor.reaction_until_ms = now + hit.duration();
            actor.melee.active = false;
            state.phase = .choose;
        };
        if (actor.reaction_until_ms != null) {
            velocity.linear = @splat(0);
            actor.mode = .idle;
        } else if (sensed.enemy) |target| {
            const enemy = (try world.get(target, data.Transform)).position;
            const previous = state.phase;
            const health: f32 = @floatFromInt((try world.get(entity, data.Health)).current);
            const base: f32 = @floatFromInt(definition.health);
            if (state.phase == .choose or state.phase == .chase or state.phase == .retreat) state.speed = policy.speedAfterHealthCheck(state.speed, health, base);
            if (state.phase == .choose) {
                state.ranged = sensed.visible and policy.ranged(health, base, (try world.get(entity, data.Random)).next());
                if (state.ranged) try retreat(actors, world, entity, actor, pose.*, body, enemy, now) else state.phase = .chase;
            }
            switch (state.phase) {
                .choose => {},
                .chase => {
                    if (sensed.visible and sensed.distance < 80) begin(actor, now) else if (try actors.air_routes.next(pose.position, v.add(enemy, .{ 0, 0, 80 }), body, slot)) |point| {
                        @import("actor_flight.zig").steer(pose, velocity, point, state.speed, 0.15);
                        try avoid(world, slots, pose.*, body, velocity, slot, point, state.speed);
                    } else velocity.linear = @splat(0);
                },
                .retreat => {
                    if (v.length(v.subtract(state.destination, pose.position)) <= 80) {
                        if (state.ranged) {
                            state.phase = .hover;
                            state.started_ms = now;
                            velocity.linear = v.scale(v.normalize(.{ enemy[0] - pose.position[0], enemy[1] - pose.position[1], 0 }), state.speed * 0.25);
                            try @import("events.zig").sound(world, slots, projections, "e3/e_firespitb.wav", pose.position, slot, c.CHAN_AUTO, now);
                        } else state.phase = .choose;
                    } else if (try actors.air_routes.next(pose.position, state.destination, body, slot)) |point| {
                        @import("actor_flight.zig").steer(pose, velocity, point, state.speed, 0.15);
                        try avoid(world, slots, pose.*, body, velocity, slot, point, state.speed);
                    } else velocity.linear = @splat(0);
                },
                .hover => {
                    if (state.started_ms == now) {
                        velocity.linear = v.scale(v.normalize(.{ enemy[0] - pose.position[0], enemy[1] - pose.position[1], 0 }), state.speed * 0.25);
                        try @import("events.zig").sound(world, slots, projections, "e3/e_firespitb.wav", pose.position, slot, c.CHAN_AUTO, now);
                    }
                    face(pose, enemy, definition);
                    if (now - state.started_ms >= 650) begin(actor, now);
                },
                .attack => {
                    velocity.linear = @splat(0);
                    face(pose, enemy, definition);
                    const index = actor.melee.pose;
                    if (actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false)) {
                        try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                        if (state.ranged) try @import("actor_fireballs.zig").launch(world, slots, projections, entity, target, pose.*, .doombat, definition.doombat_fireball, now) else try @import("actor_melee.zig").punch(world, slots, entity, target, pose.*, definition, now);
                    } else if (now - actor.melee.started_ms >= definition.attacks[index].duration()) {
                        actor.melee.active = false;
                        if (state.ranged) state.phase = .choose else try retreat(actors, world, entity, actor, pose.*, body, enemy, now);
                    }
                },
            }
            if (previous != state.phase) actor.changed_ms = now;
            actor.mode = if (state.phase == .attack) .attack else .chase;
        } else {
            velocity.linear = @splat(0);
            state.phase = .choose;
            actor.melee.active = false;
            actor.mode = .idle;
        }
        // The custom think callback starts after first acquisition, not at spawn.
        if (actor.threat_seen_ms > 0) {
            velocity.linear[2] += policy.bobImpulse(state.bob);
            state.bob = if (state.bob == 5) 0 else state.bob + 1;
        }
    }
    try motion(pose, body, velocity, slot, elapsed, state.speed, false);
    actor.ground_entity = c.ENTITYNUM_NONE;
}
fn begin(actor: *data.Actor, now: i64) void {
    actor.doombat.phase = .attack;
    actor.melee.begin(if (actor.doombat.ranged) 0 else 1, now);
}
fn retreat(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: data.Body, enemy: v.Vec3, now: i64) !void {
    const point = try @import("air_escape.zig").find(world, entity, pose, body, enemy, &actors.air_routes, 1000, 80);
    if (point) |destination| {
        actor.doombat.destination = destination;
        actor.doombat.phase = .retreat;
    } else {
        actor.doombat.phase = if (actor.doombat.ranged) .hover else .choose;
        actor.doombat.started_ms = now;
    }
}
fn face(pose: *data.Transform, point: v.Vec3, definition: Definition) void {
    const delta = v.subtract(point, pose.position);
    const wanted: [2]f32 = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi };
    for (wanted, [_]f32{ definition.pitch_speed, definition.yaw_speed }, 0..) |angle, speed, i| pose.angles[i] += std.math.clamp(@mod(angle - pose.angles[i] + 180, 360) - 180, -speed, speed);
}
fn avoid(world: *data.World, slots: *Slots, pose: data.Transform, body: data.Body, velocity: *data.Velocity, slot: u16, point: v.Vec3, speed: f32) !void {
    const delta = v.subtract(point, pose.position);
    const angles: v.Vec3 = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
    const extent = v.subtract(body.maxs, body.mins);
    const width = (extent[0] + extent[1] + extent[2]) / 3.25;
    for ([_][2]f32{ .{ 45, 45 }, .{ 45, -45 }, .{ -45, -45 }, .{ -45, 45 } }) |corner| {
        const direction = v.basis(v.add(angles, .{ corner[0], corner[1], 0 })).forward;
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, width)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
        if (hit.fraction == 1) continue;
        if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |other| if (world.get(other, data.MapObject) catch null) |object| {
            if (std.mem.indexOf(u8, object.classname, "door") != null or std.mem.indexOf(u8, object.classname, "train") != null) continue;
        };
        velocity.linear = v.scale(direction, -speed * 0.5);
        return;
    }
}
pub fn motion(pose: *data.Transform, body: data.Body, velocity: *data.Velocity, slot: u16, elapsed: u32, speed: f32, dead: bool) !void {
    var remaining = elapsed;
    while (remaining > 0) {
        const slice = @min(remaining, 50);
        remaining -= slice;
        const seconds = @as(f32, @floatFromInt(slice)) * 0.001;
        if (dead) velocity.linear[2] -= 600 * seconds;
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity.linear, seconds)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        pose.position = hit.end;
        if (dead) velocity.linear[2] -= 600 * seconds;
        if (hit.fraction < 1 or hit.start_solid) {
            if (dead) {
                velocity.linear = v.scale(v.subtract(velocity.linear, v.scale(hit.normal, 2 * v.dot(velocity.linear, hit.normal))), 0.5);
                if (hit.normal[2] > 0.7 and @abs(velocity.linear[2]) < 60) velocity.linear = @splat(0);
            } else {
                velocity.linear = v.add(v.clip(velocity.linear, hit.normal), v.scale(hit.normal, speed * 0.6));
            }
            pose.position = v.add(pose.position, v.scale(hit.normal, 0.03125));
        }
    }
}
