// SPDX-License-Identifier: GPL-2.0-or-later
//! Buboid's coffin, resurrection and holy-ground-aware melt lifecycle.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
pub fn initialize(world: *data.World, entity: ecs.Entity, now: i64) !void {
    const name = @import("properties.zig").text((try world.get(entity, data.MapObject)).*, "aistate") orelse return;
    if (!std.ascii.eqlIgnoreCase(name, "buboidcoffin")) return;
    const actor = try world.get(entity, data.Actor);
    actor.buboid.phase = .coffin;
    actor.buboid.started_ms = now;
    actor.ignore_player = true;
    actor.melee.begin(4, now);
}
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        if (actor.buboid.phase != .living) try special(actors, world, slots, projections, entity, actor, pose, body, velocity, definition, now) else try combat(world, slots, projections, entity, actor, pose, body, definition, now);
    }
    if (actor.buboid.phase != .collapsed and actor.mode != .chase) velocity.linear = @splat(0);
    const mode = actor.mode;
    // A fallen Buboid uses toss movement without stair stepping, while retaining
    // its living identity until the class explicitly authorizes a permanent kill.
    if (actor.buboid.phase == .collapsed) actor.mode = .dead;
    try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, actor.threat_position, definition.speed * slow, (try world.get(entity, data.Binding)).slot, now, elapsed);
    actor.mode = mode;
}
fn combat(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, definition: Definition, now: i64) !void {
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (actor.reaction_until_ms) |until| if (now >= until) {
        actor.reaction = null;
        actor.reaction_until_ms = null;
    };
    if (injured) {
        _ = try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 20, 40, now);
        if (sensed.enemy != null and hurt.amount > 0 and (try world.get(entity, data.Random)).next() < 0.75 and sensed.distance > 250) {
            melt(actor, body, now);
            return;
        }
    }
    if (actor.reaction_until_ms != null) {
        actor.mode = .idle;
        return;
    }
    const target = sensed.enemy orelse {
        actor.mode = .idle;
        actor.melee.active = false;
        return;
    };
    const enemy = (try target.get(data.Transform)).position;
    const delta = v.subtract(enemy, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) < 5;
    if (actor.melee.active and sensed.distance >= definition.range) actor.melee.active = false;
    if (actor.melee.active) {
        try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
        if (facing) {
            const index = actor.melee.pose;
            const first = actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps), now, false);
            const second = if (!first) if (definition.second_strikes[index]) |frame| actor.melee.event(2, @divTrunc(@as(i64, frame) * 1000, definition.attacks[index].fps), now, false) else false else false;
            if (first or second) try @import("actor_melee.zig").punch(world, slots, entity, target, pose.*, definition, now);
        }
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) actor.melee.active = false;
    }
    if (!actor.melee.active) {
        if (sensed.visible and sensed.distance < definition.range) {
            actor.melee.begin(if ((try world.get(entity, data.Random)).next() * 3 < 2) 1 else 0, now);
            actor.changed_ms = now;
        } else {
            const point = v.add(pose.position, v.scale(v.basis(pose.angles).forward, 36));
            const ground = try @import("actor_collision.zig").service().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -200 }), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
            if ((!sensed.visible and sensed.distance > 300) or (ground.fraction < 1 and ground.holy)) {
                melt(actor, body, now);
                return;
            }
        }
    }
    actor.mode = if (actor.melee.active) .attack else .chase;
    if (actor.mode == .chase) actor.think_ms = now + 200;
}
fn melt(actor: *data.Actor, body: *data.Body, now: i64) void {
    actor.buboid.phase = .melting;
    actor.buboid.started_ms = now;
    actor.buboid.alpha = 0.8;
    actor.ignore_player = true;
    actor.melee.begin(2, now);
    actor.reaction = null;
    actor.reaction_until_ms = null;
    actor.mode = .attack;
    actor.changed_ms = now;
    body.contents = 0;
}
fn special(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, definition: Definition, now: i64) !void {
    const state = &actor.buboid;
    actor.mode = .attack;
    if (state.phase != .collapsed) velocity.linear = @splat(0);
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    const ended = now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration();
    switch (state.phase) {
        .coffin => if (ended) finish(actor, body, now),
        .collapsed => if (now >= state.until_ms) {
            state.phase = .rising;
            state.started_ms = now;
            state.until_ms = now + 10000;
            actor.melee.begin(4, now);
            (try world.get(entity, data.Health)).current = definition.health;
        },
        .rising => if (ended or now >= state.until_ms) {
            (try world.get(entity, data.Health)).current = definition.health;
            actor.receipt = (try world.get(entity, data.Hurt)).revision;
            finish(actor, body, now);
        },
        .melting => {
            if (state.alpha > 0.05) state.alpha = @max(0, state.alpha - 0.25);
            if (ended) {
                state.phase = .melted;
                state.until_ms = now + 3000 + @as(i64, @intFromFloat(@floor((try world.get(entity, data.Random)).next() * 4) * 1000));
            }
        },
        .melted => if (now > state.until_ms) {
            if (try emerge(actors, world, entity, actor, pose, definition, now)) {
                state.phase = .unmelting;
                state.started_ms = now;
                actor.melee.begin(3, now);
                body.contents = c.CONTENTS_BODY;
            } else state.until_ms = now + 1000;
        },
        .unmelting => {
            state.alpha = @min(1, state.alpha + 0.2);
            actor.think_ms = now + 200;
            if (ended) finish(actor, body, now);
        },
        .living, .terminal => {},
    }
}
fn finish(actor: *data.Actor, body: *data.Body, now: i64) void {
    actor.buboid.phase = .living;
    actor.buboid.alpha = 1;
    actor.ignore_player = false;
    actor.melee.active = false;
    actor.mode = .idle;
    actor.changed_ms = now;
    body.contents = c.CONTENTS_BODY;
}
fn emerge(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !bool {
    const target = @import("region_access.zig").find(world, actor.threat) orelse {
        actor.think_ms = now + 1000;
        return false;
    };
    const enemy = (try target.get(data.Transform)).position;
    const enemy_body = (try target.get(data.Body)).*;
    const grounded = if (target.get(data.Player) catch null) |player| player.ground_entity != c.ENTITYNUM_NONE else if (target.get(data.Actor) catch null) |other| other.ground_entity != c.ENTITYNUM_NONE else enemy_body.grounded;
    if (!grounded) {
        actor.think_ms = now + 1000;
        return false;
    }
    const ground = try @import("actor_collision.zig").service().trace(.{ .start = enemy, .end = v.add(enemy, .{ 0, 0, -0.5 }), .mins = enemy_body.mins, .maxs = enemy_body.maxs, .slot = (try target.get(data.Binding)).slot, .mask = c.MASK_SOLID });
    if (ground.fraction == 1 or ground.start_solid) {
        actor.think_ms = now + 1000;
        return false;
    }
    if (ground.holy) {
        actor.think_ms = now + 3000;
        return false;
    }
    const slot = (try world.get(entity, data.Binding)).slot;
    const mins = v.scale(definition.mins, 1.35);
    const maxs = v.scale(definition.maxs, 1.35);
    for (0..8) |i| {
        const direction = v.basis(.{ 0, @as(f32, @floatFromInt(i)) * 45, 0 }).forward;
        const ray = try @import("actor_collision.zig").service().trace(.{ .start = v.add(enemy, v.scale(direction, 32)), .end = v.add(enemy, v.scale(direction, 64)), .mins = mins, .maxs = maxs, .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
        if (ray.fraction < 1 or ray.start_solid) continue;
        const node = actors.water_routes.nearest(ray.end) orelse continue;
        const above = v.add(node, .{ 0, 0, 32 });
        const clear = try @import("actor_collision.zig").service().trace(.{ .start = above, .end = above, .mins = mins, .maxs = maxs, .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
        if (clear.start_solid or clear.all_solid or clear.fraction < 1) continue;
        const destination = v.add(node, .{ 0, 0, 16 });
        // Qualify the final standing hull too; the source probes sixteen units
        // higher than its placement, which can emerge inside a mover/player.
        const placement = try @import("actor_collision.zig").service().trace(.{ .start = destination, .end = destination, .mins = definition.mins, .maxs = definition.maxs, .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
        if (placement.start_solid or placement.all_solid or placement.fraction < 1) continue;
        pose.position = destination;
        return true;
    }
    return false;
}
