// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Actors = @import("actors.zig").Actors;
const policy = @import("actor_catalog").shark;
pub fn think(actors: *Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, now: i64) !void {
    const definition = actors.table.definitions[actor.definition];
    const state = &actor.shark;
    if (state.suspended_target != 0) {
        if (@import("region_access.zig").find(world, state.suspended_target)) |target| {
            if ((try target.get(data.Health)).current <= 0) {
                state.suspended_target = 0;
                actor.ignore_player = false;
            } else if (policy.resumes(try @import("actor_water.zig").levelOwned(target))) {
                actor.threat = state.suspended_target;
                actor.ignore_player = false;
                state.suspended_target = 0;
            }
        } else {
            state.suspended_target = 0;
            actor.ignore_player = false;
        }
    }
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    var sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (sensed.enemy) |target| if (policy.abandons(try @import("actor_water.zig").levelOwned(target))) {
        state.suspended_target = try target.id();
        actor.ignore_player = true;
        actor.threat = 0;
        sensed.enemy = null;
    };
    state.wandering = sensed.enemy == null;
    if (actor.reaction_until_ms) |until| {
        if (now < until) {
            actor.mode = .idle;
            return;
        }
        actor.reaction = null;
        actor.reaction_until_ms = null;
    }
    if (injured and hurt.amount >= 25) if (definition.pain[0]) |sequence| {
        actor.reaction = sequence;
        actor.reaction_started_ms = now;
        actor.reaction_until_ms = now + sequence.duration();
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    const tick = now >= actor.think_ms;
    if (tick) actor.think_ms = now + 100;
    if (state.wandering) {
        actor.melee.active = false;
        if (tick and (state.destination == null or now >= state.wander_until_ms or v.length(v.subtract(state.destination.?, pose.position)) < definition.walk_speed * 0.2)) {
            state.destination = try @import("actor_wander.zig").next(&actors.water_routes, pose.*, state.start, definition, try world.get(entity, data.Random), .{ .body = (try world.get(entity, data.Body)).*, .slot = (try world.get(entity, data.Binding)).slot });
            if (state.destination) |destination| state.wander_until_ms = now + @as(i64, @intFromFloat(v.length(v.subtract(destination, pose.position)) / definition.walk_speed * 1000)) + 1000;
        }
        if (state.destination) |destination| actor.threat_position = destination;
        actor.mode = if (state.destination == null) .idle else .chase;
        return;
    }
    state.destination = null;
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    if (tick) pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    const target = sensed.enemy.?;
    if (actor.melee.active) {
        try @import("ground_combat.zig").emit(world, slots, projections, entity, actor, pose.*, definition, target, true, now);
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) actor.melee.active = false;
    }
    if (!actor.melee.active and tick and sensed.visible and sensed.distance < definition.range and sensed.distance < 100) {
        actor.melee.begin(policy.select((try world.get(entity, data.Random)).next()), now);
        actor.changed_ms = now;
    }
    actor.mode = if (actor.melee.active) .attack else .chase;
    if (actor.melee.active) try @import("ground_combat.zig").emit(world, slots, projections, entity, actor, pose.*, definition, target, true, now);
}
pub fn swim(actors: *Actors, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, slot: u16, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    velocity.linear = @splat(0);
    if (actor.mode == .chase) {
        var destination = actor.threat_position;
        // A target with only its feet in water must be approached horizontally;
        // the shark's own route and hull stay in the water.
        if (try @import("actor_collision.zig").service().contents(destination, slot) & c.MASK_WATER == 0) destination[2] = pose.position[2];
        if (try actors.water_routes.nextWater(pose.position, destination, body.*, slot)) |next| {
            const speed = (if (actor.shark.wandering) definition.walk_speed else definition.speed) * slow;
            var direction = v.normalize(v.subtract(next, pose.position));
            if (try @import("actor_water.zig").level(pose.position, body.*, slot) < 3) direction[2] = 0;
            velocity.linear = v.scale(v.normalize(direction), speed);
            if (v.length(velocity.linear) > 0) pose.angles = .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 };
        }
    }
    var remaining = elapsed;
    while (remaining > 0) {
        const slice = @min(50, remaining);
        remaining -= slice;
        const endpoint = v.add(pose.position, v.scale(velocity.linear, @as(f32, @floatFromInt(slice)) * 0.001));
        if (try @import("actor_collision.zig").service().contents(endpoint, slot) & c.MASK_WATER == 0) {
            velocity.linear = @splat(0);
            break;
        }
        try @import("actor_flight.zig").move(pose, body.*, velocity, slot, slice);
    }
    body.grounded = false;
    actor.ground_entity = c.ENTITYNUM_NONE;
}
