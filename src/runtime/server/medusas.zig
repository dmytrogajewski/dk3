// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").medusa;
const Definition = @import("../domain/actors.zig").Definition;
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        try think(actors, world, slots, projections, entity, actor, pose, body.*, definition, navigation, now);
    }
    if (actor.mode != .chase) {
        velocity.linear[0] = 0;
        velocity.linear[1] = 0;
    }
    try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, actor.threat_position, definition.speed * slow, (try world.get(entity, data.Binding)).slot, now, elapsed);
}
fn think(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, definition: Definition, navigation: @import("../domain/navigation.zig").Service, now: i64) !void {
    const injured = (try world.get(entity, data.Hurt)).revision != actor.receipt;
    const hurt = (try world.get(entity, data.Hurt)).amount;
    const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    const state = &actor.medusa;
    if (actor.reaction_until_ms) |until| if (now >= until) {
        actor.reaction = null;
        actor.reaction_until_ms = null;
    };
    if (injured and (try world.get(entity, data.Hurt)).source != try world.persistentId(entity)) _ = try @import("actor_pain.zig").direct(world, entity, actor, definition, hurt, 1, now);
    if (actor.reaction_until_ms != null) {
        actor.mode = .idle;
        return;
    }
    if (state.phase == .recover) {
        try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
        if (now >= state.until_ms or now - actor.melee.started_ms >= definition.attacks[4].duration()) {
            state.phase = .combat;
            actor.melee.active = false;
            actor.pain_ready_ms = now;
        } else return;
    }
    const target = if (state.phase == .rattle or state.phase == .gaze) world.find(state.target) else sensed.enemy;
    const enemy = target orelse {
        state.phase = .combat;
        state.eyes = false;
        actor.mode = .idle;
        actor.melee.active = false;
        return;
    };
    const other = (try world.get(enemy, data.Transform)).*;
    const delta = v.subtract(other.position, pose.position);
    const angles: v.Vec3 = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
    // The warning tracks the target; the gaze deliberately holds its heading.
    if (state.phase != .gaze) pose.angles[1] += std.math.clamp(@mod(angles[1] - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    const facing = @abs(@mod(angles[1] - pose.angles[1] + 180, 360) - 180) < 5;
    if (state.phase == .rattle or state.phase == .gaze) {
        actor.mode = .attack;
        if (state.phase == .gaze or @mod(@divTrunc(now, 1000), 2) == 1) {
            if (world.get(enemy, data.Player) catch null) |player| {
                if (player.mode != .noclip) state.flash_until_ms = now + 100;
            }
            if (state.phase == .rattle) try @import("events.zig").sound(world, slots, projections, "global/we_gravela.wav", pose.position, (try world.get(entity, data.Binding)).slot, abi.c.CHAN_AUTO, now);
        }
        try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
        if (now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) {
            if (state.phase == .gaze) state.eyes = false;
            actor.melee.begin(3, now);
        }
        if (state.phase == .gaze and (try world.get(enemy, data.Health)).current > 0) {
            const fov: f32 = if (world.get(enemy, data.Actor) catch null) |other_actor| actors.table.definitions[other_actor.definition].fov else 90;
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = other.position, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = abi.c.MASK_SOLID });
            if ((hit.fraction == 1 or hit.entity == (try world.get(enemy, data.Binding)).slot) and policy.eyeContact(angles, pose.angles, other.angles, fov)) {
                try petrify(world, projections, entity, enemy, now);
                state.eyes = false;
            }
        }
        if (now >= state.until_ms) {
            if (state.phase == .rattle) {
                state.phase = .gaze;
                state.until_ms = now + 3000;
                actor.melee.begin(3, now);
            } else {
                state.phase = .recover;
                state.until_ms = now + 10000;
                actor.melee.begin(4, now);
            }
        }
        return;
    }
    const slot = (try world.get(entity, data.Binding)).slot;
    const visibility = try sight(pose.position, body, other.position, (try world.get(enemy, data.Body)).*, slot);
    if (state.phase == .sidestep) {
        if (visibility == 3 or now >= state.until_ms or @import("../domain/navigation.zig").horizontalDistance(pose.position, state.retreat) < 16) state.phase = .combat else {
            actor.mode = .chase;
            actor.threat_position = state.retreat;
            return;
        }
    }
    if (state.phase == .retreat) {
        const d = v.subtract(state.retreat, pose.position);
        if (now >= state.until_ms or (@sqrt(d[0] * d[0] + d[1] * d[1]) < 16 and @abs(d[2]) < 48)) state.phase = .combat else {
            actor.mode = .chase;
            actor.threat_position = state.retreat;
            return;
        }
    }
    const was_attacking = actor.melee.active;
    if (actor.melee.active) {
        actor.mode = .attack;
        try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
        const attack = actor.melee.pose;
        if (actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[attack]) * 1000, definition.attacks[attack].fps), now, false)) {
            if (attack == 1) try @import("venom_spit.zig").medusa(world, slots, projections, entity, enemy, pose.*, definition.medusa_spit, now) else if (facing) try bite(world, slots, entity, enemy, pose.*, definition, now);
        }
        if (now - actor.melee.started_ms < definition.attacks[attack].duration() and now < state.until_ms) return;
        actor.melee.active = false;
    }
    if (!was_attacking and (visibility == 1 or visibility == 2)) {
        // Medusa probes the opposite side before enqueueing her named sidestep.
        if (try sidePoint(pose.position, other.position, body, slot, definition.speed, visibility != 1) != null) {
            if (try sidePoint(pose.position, other.position, body, slot, definition.speed, visibility == 1)) |point| {
                state.phase = .sidestep;
                state.retreat = point;
                state.until_ms = now + 1000;
                actor.threat_position = point;
                actor.mode = .chase;
                return;
            }
        }
    }
    const random = try world.get(entity, data.Random);
    const distance = v.length(delta);
    // Preserve independent predicate rolls when a failed spit roll can admit gaze.
    const in_range = distance <= definition.attack_range or (distance <= 350 and random.next() < 0.5) or (distance <= 1250 and random.next() < 0.05);
    if ((if (was_attacking) sensed.visible else visibility != 0) and in_range) {
        actor.mode = .attack;
        state.until_ms = now + 15000;
        state.eyes = false;
        actor.changed_ms = now;
        if (distance <= definition.attack_range) actor.melee.begin(0, now) else if (distance > 350 or random.next() < 0.05) {
            actor.melee.begin(2, now);
            state.phase = .rattle;
            state.target = try world.persistentId(enemy);
            state.eyes = true;
            state.until_ms = now + 3000;
            actor.pain_ready_ms = now + 24000;
        } else actor.melee.begin(1, now);
        return;
    }
    actor.mode = .chase;
    actor.threat_position = other.position;
    const missing_path = try navigation.next(.{ .position = pose.position, .destination = other.position, .slot = slot }) == null and !try @import("actor_motion.zig").direct(pose.position, other.position, body, slot);
    if (missing_path or (!sensed.visible and delta[2] > 150 and pose.position[2] < -1890 and other.position[2] > -1890)) {
        var nearest: ?v.Vec3 = null;
        var nearest_distance: f32 = std.math.inf(f32);
        for (actors.water_routes.nodes) |node| if (node.flags & 0x2000 != 0) {
            const d = v.length(v.subtract(node.position, pose.position));
            if (d < nearest_distance) {
                nearest = node.position;
                nearest_distance = d;
            }
        };
        if (nearest) |point| {
            state.phase = .retreat;
            state.retreat = point;
            state.until_ms = now + @as(i64, @intFromFloat(nearest_distance / definition.speed * 1000)) + 2000;
            actor.threat_position = point;
        }
    }
}
fn bite(world: *data.World, slots: *Slots, owner: ecs.Entity, enemy: ecs.Entity, pose: data.Transform, definition: Definition, now: i64) !void {
    const random = try world.get(owner, data.Random);
    const aim = try @import("actor_aim.zig").lead(world, enemy, pose, definition.offset, random);
    const hit = try engine.collisionService().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(owner, data.Binding)).slot, .mask = abi.c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |target| {
        const source = try world.persistentId(owner);
        const amount = definition.damage + random.next() * definition.random_damage;
        if (try @import("weapon_damage.zig").hurt(world, target, source, 0, amount, now, false)) try @import("weapon_damage.zig").shove(world, target, source, aim.direction, amount, now);
        try @import("ailments.zig").apply(world, target, .{ .poison = .{ .damage = 1, .duration_ms = 15000, .interval_ms = 3000 } }, source, 0, now);
    };
}
fn petrify(world: *data.World, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, now: i64) !void {
    const slot = (try world.get(target, data.Binding)).slot;
    const frame: u16 = @intCast(projections[slot].state.frame);
    const result = try @import("damage.zig").apply(world, target, 100000, now, .{ .source = try world.persistentId(owner), .attacker_class = "monster_medusa" });
    if ((world.get(target, data.Ailments) catch null) == null) try world.put(target, data.Ailments{});
    const status = try world.get(target, data.Ailments);
    status.stone = true;
    if (result.blood > 0) {
        status.petrified_frame = frame;
        (try world.get(target, data.Velocity)).linear = @splat(0);
        if (world.get(target, data.Player) catch null) |player| player.mode = .frozen;
    }
}

fn sight(position: v.Vec3, body: data.Body, target: v.Vec3, target_body: data.Body, slot: u16) !u2 {
    const origin = v.add(position, .{ 0, 0, (body.maxs[2] - body.mins[2]) * 0.4 });
    const end = v.add(target, .{ 0, 0, (target_body.maxs[2] - target_body.mins[2]) * 0.4 });
    const direction = v.normalize(v.subtract(target, position));
    const left: v.Vec3 = .{ -direction[1], direction[0], 0 };
    const width = (body.maxs[0] - body.mins[0]) * 0.6;
    var result: u2 = 0;
    for ([_]f32{ 1, -1 }, 0..) |sign, i| {
        const hit = try engine.collisionService().trace(.{ .start = v.add(origin, v.scale(left, width * sign)), .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = abi.c.MASK_SOLID });
        if (hit.fraction == 1 and !hit.start_solid and !hit.all_solid) result |= @as(u2, 1) << @intCast(i);
    }
    return result;
}
fn sidePoint(position: v.Vec3, target: v.Vec3, body: data.Body, slot: u16, speed: f32, left: bool) !?v.Vec3 {
    var delta = v.subtract(target, position);
    delta[2] = 0;
    delta = v.normalize(delta);
    const perpendicular: v.Vec3 = if (left) .{ -delta[1], delta[0], 0 } else .{ delta[1], -delta[0], 0 };
    const distance = @max(30, speed * 0.126);
    var point = v.add(position, v.scale(perpendicular, distance));
    const hit = try engine.collisionService().trace(.{ .start = position, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = abi.c.MASK_SOLID });
    if (hit.fraction < 1) point = v.add(position, v.scale(perpendicular, distance * hit.fraction - (body.maxs[0] - body.mins[0]) * 0.5));
    const actual = @import("../domain/navigation.zig").horizontalDistance(position, point);
    if (@as(i32, @intFromFloat(actual)) <= @as(i32, @intFromFloat(speed * 0.015))) return null;
    const floor = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -72 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = abi.c.MASK_SOLID });
    if (floor.fraction == 1 or floor.normal[2] < 0.9) return null;
    return point;
}

test "petrification retains the struck pose and damage protection still applies" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 4);
    defer world.deinit();
    const owner = try world.create(1, .{data.Transform{}});
    const target = try world.create(2, .{ data.Player{}, data.Body{}, data.Velocity{ .linear = .{ 20, 0, 0 } }, data.Binding{ .slot = 0 }, data.Health{}, data.Hurt{}, data.Ailments{}, data.Character{ .invincible_until = 1500 } });
    var projections: [1]abi.EntityProjection = @splat(std.mem.zeroes(abi.EntityProjection));
    projections[0].state.frame = 27;
    try petrify(&world, &projections, owner, target, 1000);
    try t.expect((try world.get(target, data.Ailments)).stone);
    try t.expectEqual(null, (try world.get(target, data.Ailments)).petrified_frame);
    try t.expectEqual(@as(i32, 100), (try world.get(target, data.Health)).current);
    try petrify(&world, &projections, owner, target, 1500);
    try t.expect((try world.get(target, data.Health)).current <= 0);
    try t.expectEqual(@as(?u16, 27), (try world.get(target, data.Ailments)).petrified_frame);
    try t.expectEqual(@import("../domain/player_move.zig").Mode.frozen, (try world.get(target, data.Player)).mode);
    try t.expectEqual(v.Vec3{ 0, 0, 0 }, (try world.get(target, data.Velocity)).linear);
}
