// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("actor_catalog");
const policy = catalog.kage;
const fx = @import("summon_effects.zig");
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        try think(actors, world, slots, projections, entity, actor, pose, body, now);
    }
    if (actor.mode != .chase or actor.kage.phase != .combat) velocity.linear = @splat(0);
    try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, actor.threat_position, actors.table.definitions[actor.definition].speed * slow, (try world.get(entity, data.Binding)).slot, now, elapsed);
}
fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, point: v.Vec3, name: []const u8, now: i64) !void {
    try @import("events.zig").sound(world, slots, projections, name, point, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
fn recharge(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, point: v.Vec3, now: i64) !void {
    const state = &actor.kage;
    if (state.phase != .combat) {
        state.suspended = state.phase;
        state.suspended_next_ms = state.next_ms;
    }
    state.phase = .protectors;
    state.protectors = 0;
    state.next_ms = now;
    actor.melee.begin(3, now);
    actor.mode = .attack;
    actor.ignore_player = true;
    actor.reaction = null;
    actor.reaction_until_ms = null;
    try sound(world, slots, projections, entity, point, "e4/m_kage_spawn.wav", now);
}
fn smoke(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, point: v.Vec3, body: *data.Body, now: i64) !void {
    actor.kage.phase = .smoke;
    actor.kage.aura = false;
    actor.kage.alpha = 1;
    actor.melee.begin(2, now);
    actor.mode = .attack;
    actor.ignore_player = true;
    body.contents = 0;
    for ([_]f32{ -16, 0, 16 }) |z| try fx.smoke(world, slots, projections, entity, v.add(point, .{ 0, 0, z }), now);
    try sound(world, slots, projections, entity, point, "e4/m_kage_hide.wav", now);
}
fn think(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, now: i64) !void {
    const definition = actors.table.definitions[actor.definition];
    const state = &actor.kage;
    const skill = engine.integer("g_spSkill");
    const health = (try world.get(entity, data.Health)).current;
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    const target = world.find(actor.threat);
    if (target) |enemy| {
        const visible = try @import("actors.zig").Actors.visible(pose.position, (try world.get(enemy, data.Transform)).position, (try world.get(entity, data.Binding)).slot, (try world.get(enemy, data.Binding)).slot);
        if (visible and !state.awakened) {
            state.aura = true;
            state.awakened = true;
            state.humming = true;
            state.aura_started_ms = now;
        } else if (!visible and state.voice_pose == 1) {
            state.aura = false;
            state.awakened = false;
        }
    }
    if (state.feedback) {
        state.feedback = false;
        if (now > state.feedback_ready_ms) {
            state.feedback_ready_ms = now + 1000;
            const direction = if (target) |enemy| v.normalize(v.subtract((try world.get(enemy, data.Transform)).position, pose.position)) else @as(v.Vec3, @splat(0));
            const point = v.add(v.add(pose.position, v.scale(direction, 32)), .{ 0, 0, 18 });
            try fx.flare(world, slots, projections, entity, point, .{ 5, 10, 7.5 }, .{ 60, 5, 10 }, 700, true, false, now);
            try fx.flare(world, slots, projections, entity, point, .{ 7.5, 5, 10 }, .{ 5, 60, 10 }, 500, true, false, now);
            try sound(world, slots, projections, entity, pose.position, "e4/ykeypickup.wav", now);
        }
    }
    if (injured and state.eligible(health, skill, now)) {
        actor.receipt = hurt.revision;
        try recharge(world, slots, projections, entity, actor, pose.position, now);
        return;
    }
    if (state.phase != .combat) {
        actor.receipt = hurt.revision;
        actor.mode = .attack;
        switch (state.phase) {
            .smoke => {
                state.alpha -= 0.25;
                if (state.alpha < 0.05) {
                    state.alpha = 0;
                    state.phase = .hidden;
                    state.next_ms = now + 5000 + @as(i64, @intFromFloat((try world.get(entity, data.Random)).next() * 4000));
                    try fx.smoke(world, slots, projections, entity, pose.position, now);
                }
            },
            .hidden => if (now > state.next_ms) {
                const point = if (target) |enemy| try returnPoint(actors, world, entity, pose.*, body.*, (try world.get(enemy, data.Transform)).position) else null;
                if (point) |destination| {
                    pose.position = destination;
                    body.contents = c.CONTENTS_BODY;
                    body.grounded = false;
                    actor.route = .{};
                    actor.ground_entity = c.ENTITYNUM_NONE;
                    state.phase = .returning;
                    state.return_steps = 0;
                } else state.next_ms = now + 5000 + @as(i64, @intFromFloat((try world.get(entity, data.Random)).next() * 4000));
            },
            .returning => {
                state.return_steps += 1;
                state.alpha = @min(1, @as(f32, @floatFromInt(state.return_steps)) * 0.25);
                // The callback restores damage only after alpha exceeds one.
                if (state.return_steps > 4) {
                    state.phase = .combat;
                    state.escapes -= 1;
                    actor.ignore_player = false;
                    actor.melee.active = false;
                }
            },
            .protectors => if (state.protectors == 12) {
                state.phase = .charging;
                state.next_ms = now + 1000;
                actor.melee.begin(3, now);
            } else if (now > state.next_ms) {
                try sound(world, slots, projections, entity, pose.position, "e4/m_kage_spawnloop.wav", now);
                try protector(actors, world, slots, projections, entity, actor, pose.*, now);
                state.protectors += 1;
                state.next_ms = now + 650;
            },
            .charging => {
                const value = try world.get(entity, data.Health);
                if (@as(f32, @floatFromInt(value.current)) + state.health_fraction < state.base_health * policy.limit(skill)) {
                    if (now > state.next_ms) {
                        value.current += ([_]i32{ 1, 5, 10 })[policy.difficulty(skill)];
                        state.next_ms = now + ([_]i64{ 2000, 1500, 1000 })[policy.difficulty(skill)];
                    }
                } else {
                    state.base_health = @as(f32, @floatFromInt(value.current)) + state.health_fraction;
                    state.recharge_ready_ms = now + ([_]i64{ 15000, 7500, 4500 })[policy.difficulty(skill)];
                    state.charges -= 1;
                    state.phase = state.suspended orelse .combat;
                    state.suspended = null;
                    state.next_ms = state.suspended_next_ms;
                    actor.ignore_player = state.phase != .combat;
                    actor.melee.active = state.phase != .combat;
                }
            },
            .combat => unreachable,
        }
        if (state.eligible((try world.get(entity, data.Health)).current, skill, now)) try recharge(world, slots, projections, entity, actor, pose.position, now);
        return;
    }
    const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (actor.reaction_until_ms) |until| if (now >= until) {
        actor.reaction = null;
        actor.reaction_until_ms = null;
    };
    if (injured) _ = try @import("actor_pain.zig").direct(world, entity, actor, definition, hurt.amount, 2, now);
    if (actor.reaction_until_ms != null) actor.mode = .idle else if (sensed.enemy) |enemy| {
        const delta = v.subtract((try world.get(enemy, data.Transform)).position, pose.position);
        const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) < 5;
        if (!actor.melee.active and sensed.visible and sensed.distance < definition.attack_range and facing) try select(world, entity, actor, now);
        if (actor.melee.active) {
            actor.mode = .attack;
            const sequence = definition.attacks[actor.melee.pose];
            try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
            if (actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[actor.melee.pose]) * 1000, sequence.fps), now, false) and facing) try slice(world, slots, projections, entity, enemy, actor, pose.*, definition, now);
            if (now - actor.melee.started_ms >= sequence.duration()) {
                actor.melee.active = false;
                if (sensed.visible and sensed.distance <= definition.attack_range and facing) try select(world, entity, actor, now) else actor.mode = .chase;
            }
            if (state.escapes > 0 and now > state.dodge_ready_ms and try @import("actor_evasion.zig").targeted(world, entity, enemy, pose.*)) {
                state.dodge_ready_ms = now + 5000;
                if ((try world.get(entity, data.Random)).next() < 0.3) try smoke(world, slots, projections, entity, actor, pose.position, body, now);
            }
        } else actor.mode = .chase;
    } else {
        actor.mode = .idle;
        actor.melee.active = false;
    }
    if (state.eligible((try world.get(entity, data.Health)).current, skill, now)) try recharge(world, slots, projections, entity, actor, pose.position, now);
}
fn select(world: *data.World, entity: ecs.Entity, actor: *data.Actor, now: i64) !void {
    actor.kage.voice_pose = @intFromFloat(@min(2, (try world.get(entity, data.Random)).next() * 3));
    actor.melee.begin(actor.kage.voice_pose, now);
    actor.changed_ms = now;
}
fn slice(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, target: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    const aim = try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(entity, data.Random));
    const hit = try engine.collisionService().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| if (world.get(victim, data.Health) catch null) |health| {
        const amount: f32 = if (health.current > 1) @floatFromInt(health.current - 1) else definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
        _ = try @import("weapon_damage.zig").hurt(world, victim, try world.persistentId(entity), 0, amount, now, false);
        const name = definition.second_attack_sounds[actor.melee.pose];
        if (name.len > 0) try sound(world, slots, projections, entity, pose.position, name, now);
    };
}
fn protector(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, now: i64) !void {
    const point = v.add(v.add(pose.position, v.scale(v.basis(.{ -5, @as(f32, @floatFromInt(actor.kage.protectors)) * 30, pose.angles[2] }).forward, 64)), .{ 0, 0, 16 });
    const definition = actors.table.definitions[catalog.find("monster_ghost").?];
    const hit = try engine.collisionService().trace(.{ .start = point, .end = point, .mins = definition.mins, .maxs = definition.maxs, .slot = c.ENTITYNUM_NONE, .mask = c.MASK_PLAYERSOLID });
    _ = (try world.get(entity, data.Random)).next(); // The reference consumes an otherwise unused three-way type roll.
    if (hit.start_solid or hit.all_solid) return;
    var angles: v.Vec3 = @splat(0);
    if (world.find(actor.threat)) |target| {
        const direction = v.subtract((try world.get(target, data.Transform)).position, point);
        angles[1] = std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi;
    }
    const ghost = try actors.spawnDynamic(world, slots, projections, "monster_ghost", point, angles, now);
    const spawned = try world.get(ghost, data.Actor);
    spawned.threat = actor.threat;
    spawned.threat_position = actor.threat_position;
    spawned.ghost.owner = try world.persistentId(entity);
    try fx.flare(world, slots, projections, ghost, point, .{ 0.75, 5, 10 }, .{ 10, 5, 5 }, 1500, false, false, now);
    try fx.flare(world, slots, projections, ghost, v.add(point, .{ 0, 0, 18 }), .{ 10, 0.75, 5 }, .{ 5, 5, 10 }, 1100, false, false, now);
    try fx.smoke(world, slots, projections, ghost, v.add(point, .{ 0, 0, 18 }), now);
}
fn returnPoint(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, pose: data.Transform, body: data.Body, enemy: v.Vec3) !?v.Vec3 {
    if (@abs(pose.position[2] - enemy[2]) >= 64) return null;
    const slot = (try world.get(entity, data.Binding)).slot;
    var point: ?v.Vec3 = null;
    const initial = try engine.collisionService().trace(.{ .start = enemy, .end = enemy, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
    if (!initial.start_solid and !initial.all_solid and initial.fraction == 1) point = v.add(enemy, .{ 0, 0, 6 });
    var yaw = pose.angles[1];
    for (0..8) |i| {
        if (point != null) break;
        if (i > 0) yaw += @as(f32, @floatFromInt(i)) * 45;
        var distance: f32 = 128;
        while (distance > 32) : (distance -= 8) {
            const end = v.add(v.add(enemy, v.scale(v.basis(.{ -5, yaw, pose.angles[2] }).forward, distance)), .{ 0, 0, 8 });
            const mid = v.add(enemy, v.scale(v.normalize(v.subtract(end, enemy)), distance * 0.75));
            const hit = try engine.collisionService().trace(.{ .start = mid, .end = end, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
            if (!hit.start_solid and !hit.all_solid and hit.fraction == 1) {
                point = end;
                break;
            }
        }
    }
    const nearest = actors.water_routes.nearest(point orelse return null) orelse return null;
    const destination = v.add(nearest, .{ 0, 0, 4 });
    // The authored search snaps to a node after testing a different point.
    // Reject a newly obstructed destination instead of embedding the boss.
    const hit = try engine.collisionService().trace(.{ .start = destination, .end = destination, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
    return if (hit.start_solid or hit.all_solid) null else destination;
}
pub fn death(world: *data.World, slots: *Slots) !void {
    for (slots.occupants) |maybe| if (maybe) |entity| if ((world.get(entity, data.Player) catch null) != null) {
        const weapons = try world.get(entity, data.Weapons);
        weapons.dk3Inventory &= ~(@as(i32, 1) << @import("weapon_catalog").daikatana.id);
        // Inventory deletion unlinks ownership without changing the selected
        // weapon. Ordinary input can switch away; ownership already prevents fire.
        return;
    };
}
