// SPDX-License-Identifier: GPL-2.0-or-later
//! Garroth selects his authored punch, stave, NPC Wisp and Buboid summon.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").garroth;
const Definition = @import("../domain/actors.zig").Definition;
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        try think(actors, world, slots, projections, entity, actor, pose, definition, now);
    }
    if (actor.mode != .chase) {
        velocity.linear[0] = 0;
        velocity.linear[1] = 0;
    }
    try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, actor.threat_position, definition.speed * slow, (try world.get(entity, data.Binding)).slot, now, elapsed);
}
fn select(world: *data.World, entity: ecs.Entity, actor: *data.Actor, definition: Definition, distance: f32, facing: bool, now: i64) !void {
    const random = try world.get(entity, data.Random);
    const skill = engine.integer("g_spSkill");
    const chance: f32 = if (skill <= 1) 0.3 else if (skill == 2) 0.7 else 0.85;
    actor.garroth.weapon = .none;
    if (facing) {
        if (distance < definition.range) actor.garroth.weapon = .punch else if (random.next() < chance) actor.garroth.weapon = policy.choose(distance, definition.range, definition.stave.range, definition.garroth_wisp.range, @intFromFloat(random.next() * 3));
    }
    actor.melee.begin(switch (actor.garroth.weapon) {
        .none => 2,
        .punch => 1,
        else => 0,
    }, now);
    actor.changed_ms = now;
    actor.mode = .attack;
}
fn think(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (actor.reaction_until_ms) |until| if (now >= until) {
        actor.reaction = null;
        actor.reaction_until_ms = null;
    };
    if (injured) _ = try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 5, 40, now);
    if (actor.reaction_until_ms != null) {
        actor.mode = .idle;
        return;
    }
    const target = sensed.enemy orelse {
        actor.mode = .idle;
        actor.melee.active = false;
        return;
    };
    const delta = v.subtract((try world.get(target, data.Transform)).position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) < 5;
    if (!actor.melee.active) {
        if (!sensed.visible or !policy.inRange(sensed.distance, definition.range)) {
            actor.mode = .chase;
            return;
        }
        try select(world, entity, actor, definition, sensed.distance, facing, now);
    }
    actor.mode = .attack;
    const index = actor.melee.pose;
    const sequence = definition.attacks[index];
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (actor.garroth.weapon != .none) {
        const first = actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[index]) * 1000, sequence.fps), now, false);
        const second = if (!first) if (definition.second_strikes[index]) |frame| actor.melee.event(2, @divTrunc(@as(i64, frame) * 1000, sequence.fps), now, false) else false else false;
        if (first or second) switch (actor.garroth.weapon) {
            .punch => try @import("actor_melee.zig").punch(world, slots, entity, target, pose.*, definition, now),
            .stave => try @import("meteors.zig").launch(world, slots, projections, entity, target, pose.*, definition.stave, now),
            .wisp => try @import("wyndrax_attacks.zig").wisp(world, slots, projections, entity, target, pose.*, now),
            .summon => try summon(actors, world, slots, projections, target, now),
            .none => unreachable,
        };
    }
    if (now - actor.melee.started_ms >= sequence.duration()) {
        if (!sensed.visible or sensed.distance > definition.attack_range) {
            actor.melee.active = false;
            actor.mode = .chase;
        } else try select(world, entity, actor, definition, sensed.distance, facing, now);
    }
}
fn summon(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, target: ecs.Entity, now: i64) !void {
    const direction = try @import("clear_direction.zig").choose(world, target, c.MASK_SOLID);
    const enemy = (try world.get(target, data.Transform)).*;
    const point = v.add(enemy.position, v.scale(direction, 100));
    const definition = actors.table.definitions[@import("actor_catalog").find("monster_buboid").?];
    // Retain the authored location, but reject a full-hull obstruction instead
    // of creating a solid monster inside a mover or another character.
    const hit = try engine.collisionService().trace(.{ .start = point, .end = point, .mins = definition.mins, .maxs = definition.maxs, .slot = c.ENTITYNUM_NONE, .mask = c.MASK_PLAYERSOLID });
    if (hit.start_solid or hit.all_solid) return;
    const spawned = try actors.spawnDynamic(world, slots, projections, "monster_buboid", point, @splat(0), now);
    const actor = try world.get(spawned, data.Actor);
    actor.threat = try world.persistentId(target);
    actor.threat_position = enemy.position;
    actor.ignore_player = false;
    // Dynamic authoring starts empty, so the summoner's death outputs are never inherited.
}
