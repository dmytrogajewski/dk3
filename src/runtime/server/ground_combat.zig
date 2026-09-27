// SPDX-License-Identifier: GPL-2.0-or-later
//! Collision/event adapter for the admitted class-owned ground attack policies.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;
const catalog = @import("actor_catalog");
pub fn think(routes: *const @import("air_routes.zig").Routes, world: *data.World, slots: *@import("../engine/slots.zig").Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    const kind = catalog.entries[actor.definition].kind;
    const hurt = (try world.get(entity, data.Hurt)).*;
    const newly_hurt = hurt.revision != actor.receipt;
    const perceived = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (kind == .column and actor.column.phase != .awake) {
        actor.mode = .idle;
        if (actor.column.phase == .asleep and perceived.visible and @import("../domain/navigation.zig").horizontalDistance(pose.position, actor.threat_position) <= catalog.column.awakening_distance) {
            actor.column.phase = .awakening;
            actor.column.started_ms = now;
            actor.reaction = definition.awakening;
            actor.reaction_started_ms = now;
            actor.reaction_until_ms = now + definition.awakening.duration();
        }
        if (actor.column.phase == .asleep) return;
        if (now < actor.column.started_ms + definition.awakening.duration()) return;
        actor.column.phase = .awake;
        actor.reaction = null;
        actor.reaction_until_ms = null;
    }
    if (actor.reaction_until_ms) |deadline| {
        if (now < deadline) {
            actor.mode = .idle;
            return;
        }
        actor.reaction = null;
        actor.reaction_until_ms = null;
    }
    if (newly_hurt and (kind == .labmonkey or kind == .femgang) and try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 20, 35, now)) return;
    if (newly_hurt and hurt.amount > 0 and kind != .labmonkey and kind != .femgang) {
        const random = (try world.get(entity, data.Random)).next();
        const chance: f32 = switch (kind) {
            .skeleton, .dwarf => 0.2,
            .lycanthir, .cerberus => 0.1,
            .ragemaster, .satyr => 0.05,
            .column => 1,
            else => unreachable,
        };
        if (random < chance) if (definition.pain[if (kind == .column and hurt.amount >= 20) @as(usize, 1) else 0]) |sequence| {
            actor.reaction = sequence;
            actor.reaction_started_ms = now;
            actor.reaction_until_ms = now + sequence.duration();
            actor.melee.active = false;
            actor.mode = .idle;
            return;
        };
    }
    const target = perceived.enemy orelse {
        if (kind == .femgang and !actor.femgang.idle_chosen) {
            actor.femgang.idle_chosen = true;
            actor.femgang.idle_b = (try world.get(entity, data.Random)).next() >= 0.85;
            actor.changed_ms = now;
        }
        actor.mode = .idle;
        actor.melee.active = false;
        return;
    };
    if (kind == .femgang) actor.femgang.idle_chosen = false;
    if (@import("actor_evasion.zig").update(actor, pose.*, now)) return;
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const turn = @mod(yaw - pose.angles[1] + 180, 360) - 180;
    const decision_tick = now >= actor.think_ms;
    if (decision_tick) {
        pose.angles[1] += std.math.clamp(turn, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= (if (kind == .femgang) @as(f32, 5) else 8);
    const reachable = perceived.visible and (if (kind == .femgang) perceived.distance < catalog.femgang.attack_distance else if (kind == .lycanthir) perceived.distance < 1000 else if (kind == .dwarf) perceived.distance < definition.dwarf.range else if (kind == .labmonkey or kind == .cerberus) perceived.distance < @max(definition.attack_range, definition.jump_distance) else perceived.distance < (if (kind == .column) catalog.column.attack_distance else definition.attack_range));
    // Deliver every crossed authored event before completing its animation. A
    // slow frame must not erase a final strike or sound.
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
    const completed = actor.melee.active and now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration();
    if (completed) {
        if (actor.melee.next_pose) |next| actor.melee.begin(next, now) else actor.melee.active = false;
    }
    var admitted = decision_tick and !actor.melee.active and facing and reachable;
    if (admitted and kind == .dwarf) {
        const random = try world.get(entity, data.Random);
        admitted = catalog.dwarf.inRange(perceived.distance, definition.range, definition.dwarf.range, random.next(), random.next());
    }
    if (admitted and kind == .cerberus) admitted = catalog.cerberus.inRange(perceived.distance, definition.range, definition.jump_distance, (try world.get(entity, data.Random)).next());
    if (admitted and kind == .labmonkey) admitted = catalog.labmonkey.inRange(perceived.distance, definition.attack_range, definition.jump_distance, (try world.get(entity, data.Random)).next());
    if (admitted and kind == .femgang and !completed and try @import("actor_evasion.zig").targeted(world, entity, target, pose.*) and (try world.get(entity, data.Random)).next() > 0.5 and try @import("actor_evasion.zig").start(routes, world, entity, target, actor, pose.*, false, now)) return;
    if (admitted) {
        const random = (try world.get(entity, data.Random)).next();
        const chosen: u3 = switch (kind) {
            .femgang => catalog.femgang.select(perceived.distance, definition.range),
            .cerberus => catalog.cerberus.select(perceived.distance, definition.attack_range, random),
            .ragemaster => catalog.ragemaster.select(random),
            .labmonkey => catalog.labmonkey.select(perceived.distance, random),
            .dwarf => catalog.dwarf.select(perceived.distance, random),
            .lycanthir => blk: {
                const velocity = (try world.get(target, data.Velocity)).linear;
                break :blk catalog.lycanthir.select(perceived.distance, definition.attack_range, v.dot(v.basis(pose.angles).forward, velocity), velocity[0] * velocity[0] + velocity[1] * velocity[1], random, (try world.get(entity, data.Random)).next());
            },
            .skeleton => if (perceived.distance >= definition.range) catalog.skeleton.chase_pose else catalog.skeleton.select(random),
            .satyr => if (perceived.distance >= definition.range) catalog.satyr.chase_pose else catalog.satyr.select(random),
            .column => catalog.column.select(perceived.distance, definition.range),
            else => unreachable,
        };
        const transition = if (kind == .satyr) catalog.satyr.transition(actor.melee.pose, chosen) else null;
        actor.melee.begin(transition orelse chosen, now);
        actor.melee.next_pose = if (transition != null) chosen else null;
        actor.melee.moving = (kind == .femgang and chosen == 1) or (kind == .skeleton and chosen == catalog.skeleton.chase_pose) or (kind == .satyr and chosen == catalog.satyr.chase_pose) or (kind == .column and chosen == 1) or (kind == .dwarf and chosen == 1) or (kind == .lycanthir and chosen == 3);
        if (kind == .labmonkey) {
            const state = try world.get(entity, data.Random);
            const hop = if (completed) catalog.labmonkey.hop(perceived.distance, state.next()) else null;
            if (hop != null or chosen == 2 or chosen == 3) {
                var angles = pose.angles;
                if (hop) |yaw_add| {
                    angles[1] += if (state.next() < 0.5) yaw_add else -yaw_add;
                    actor.melee.begin(2, now);
                }
                const velocity = try world.get(entity, data.Velocity);
                velocity.linear = v.scale(v.basis(angles).forward, if (hop != null) 150 else definition.speed * 1.5);
                velocity.linear[2] = definition.upward_speed;
                actor.ground_entity = c.ENTITYNUM_NONE;
            }
        }
        if (kind == .lycanthir) actor.lycanthir.launched = false;
        if (kind == .cerberus) actor.cerberus.launched = false;
        actor.changed_ms = now;
    }
    actor.mode = if (actor.melee.active) if (actor.melee.moving and (kind == .column or kind == .femgang or perceived.distance >= (if (kind == .lycanthir) @as(f32, 60) else 40))) .chase else .attack else if (!reachable) .chase else .idle;
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, facing, now);
}
pub fn emit(world: *data.World, slots: *@import("../engine/slots.zig").Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: @import("../domain/actors.zig").Definition, target: ecs.Entity, facing: bool, now: i64) !void {
    const kind = catalog.entries[actor.definition].kind;
    if (kind == .satyr and actor.melee.pose >= 3) return;
    const index = actor.melee.pose;
    const sequence = definition.attacks[index];
    const slot = (try world.get(entity, data.Binding)).slot;
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (kind == .lycanthir and index == 4 and !actor.lycanthir.launched and now >= actor.melee.started_ms + definition.attack_sound_ms[index]) {
        actor.lycanthir.launched = true;
        const velocity = try world.get(entity, data.Velocity);
        velocity.linear = v.scale(v.basis(pose.angles).forward, definition.speed * 1.5);
        velocity.linear[2] = definition.upward_speed;
        actor.ground_entity = c.ENTITYNUM_NONE;
    }
    if (kind == .cerberus and index == 2 and !actor.cerberus.launched and now >= actor.melee.started_ms + definition.attack_sound_ms[index]) {
        actor.cerberus.launched = true;
        const velocity = try world.get(entity, data.Velocity);
        velocity.linear = v.scale(v.basis(pose.angles).forward, definition.speed);
        velocity.linear[2] = definition.upward_speed;
        actor.ground_entity = c.ENTITYNUM_NONE;
    }
    const strikes = [_]?u16{ definition.strikes[index], definition.second_strikes[index] };
    for (strikes, 0..) |strike, i| if (strike) |frame| {
        if ((kind == .femgang or kind == .column or kind == .dwarf or kind == .cerberus or kind == .shark or (kind == .lycanthir and index == 4)) and i == 1) continue;
        if (!actor.melee.event(@as(u2, 1) << @intCast(i), (if (kind == .lycanthir and index == 4) definition.jump_strike_ms else @divTrunc(@as(i64, frame) * 1000, sequence.fps)), now, false) or (!facing and kind != .shark and !(kind == .lycanthir and index == 4) and !(kind == .cerberus and index == 2))) continue;
        if (kind == .dwarf and actor.melee.pose == 2) {
            _ = try @import("dwarf_axes.zig").launch(world, slots, projections, entity, target, pose, definition.dwarf, now);
            continue;
        }
        const axes = v.basis(pose.angles);
        const start = v.add(pose.position, v.add(v.scale(axes.right, definition.offset[0]), v.add(v.scale(axes.forward, definition.offset[1]), .{ 0, 0, definition.offset[2] })));
        const body = (try world.get(target, data.Body)).*;
        const aim = v.add((try world.get(target, data.Transform)).position, v.scale(v.add(body.mins, body.maxs), 0.5));
        const leading = if (kind == .femgang or kind == .cerberus or kind == .shark or kind == .dopefish) try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(entity, data.Random)) else null;
        const hit = try engine.collisionService().trace(.{ .start = if (leading) |value| value.origin else start, .end = if (leading) |value| v.add(value.origin, v.scale(value.direction, definition.range)) else v.add(start, v.scale(v.normalize(v.subtract(aim, start)), definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
        if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
            const random = (try world.get(entity, data.Random)).next();
            const before = if (world.get(target, data.Health) catch null) |health| health.current else 0;
            _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(definition.damage + random * definition.random_damage)), now, .{ .source = try world.persistentId(entity), .attacker_class = catalog.entries[actor.definition].classname });
            if (kind == .dopefish and (try world.get(target, data.Health)).current < before) try @import("blood_clouds.zig").spawn(world, slots, projections, target, entity, now);
        };
    };
}
