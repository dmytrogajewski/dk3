// SPDX-License-Identifier: GPL-2.0-or-later
//! Camera acquisition, alarm propagation and class-specific hovering pursuit.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const access = @import("region_access.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const catalog = @import("actor_catalog");
const policy = catalog.cambot;
fn alive(target: Ref) bool {
    const player = target.get(data.Player) catch return false;
    return player.mode == .normal and (target.get(data.Health) catch return false).current > 0;
}
fn clear(a: v.Vec3, b: v.Vec3, slot: u16) !bool {
    const hit = try @import("actor_collision.zig").service().trace(.{ .start = a, .end = b, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
    return !hit.start_solid and !hit.all_solid and hit.fraction == 1;
}
fn visibleClear(world: *data.World, target: Ref, a: v.Vec3, b: v.Vec3, slot: u16) !bool {
    const hit = try @import("actor_collision.zig").service().trace(.{ .start = a, .end = b, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
    return @import("region_collision.zig").reaches(world, hit, target);
}
fn visible(world: *data.World, entity: ecs.Entity, target: Ref, pose: data.Transform, body: data.Body, seen: bool, now: i64) !bool {
    if (!seen and (try target.get(data.Character)).invisible_until > now) return false;
    const point = (try target.get(data.Transform)).position;
    const offset = v.subtract(point, pose.position);
    if (!policy.sees(std.math.atan2(offset[1], offset[0]) * 180 / std.math.pi - pose.angles[1])) return false;
    const target_body = (try target.get(data.Body)).*;
    const end = v.add(point, .{ 0, 0, (target_body.maxs[2] - target_body.mins[2]) * 0.6 });
    const start = v.add(pose.position, .{ 0, 0, (body.maxs[2] - body.mins[2]) * 0.6 });
    const direction = v.normalize(.{ offset[0], offset[1], 0 });
    const side = v.scale(.{ -direction[1], direction[0], 0 }, (body.maxs[0] - body.mins[0]) * 0.6);
    const slot = (try world.get(entity, data.Binding)).slot;
    return (target.world != world or engine.inPvs(start, end)) and try visibleClear(world, target, start, end, slot) and try visibleClear(world, target, v.add(start, side), end, slot) and try visibleClear(world, target, v.subtract(start, side), end, slot);
}
pub fn sense(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: data.Body, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    if (actor.ignore_player) return;
    if (access.find(world, actor.threat)) |target| {
        if (!alive(target)) actor.threat = 0;
    } else actor.threat = 0;
    const hurt = (try world.get(entity, data.Hurt)).*;
    if (hurt.revision != actor.receipt) {
        actor.receipt = hurt.revision;
        if (access.find(world, hurt.source)) |target| {
            if (alive(target)) actor.threat = hurt.source;
        }
    }
    if (actor.threat == 0) {
        const range = if (actor.cambot.seen) 5000 else try @import("properties.zig").number((try world.get(entity, data.MapObject)).*, "sight", definition.sight_range);
        var candidates = access.Damageables.init(world, slots);
        while (candidates.next()) |target| {
            if (!alive(target) or v.length(v.subtract((try target.get(data.Transform)).position, pose.position)) >= range) continue;
            if (!try visible(world, entity, target, pose, body, actor.cambot.seen, now)) continue;
            actor.threat = try target.id();
            break;
        }
    }
    const target = access.find(world, actor.threat) orelse return;
    actor.threat_position = (try target.get(data.Transform)).position;
    actor.cambot.seen = true;
    if (actor.cambot.alarmed == actor.threat) return;
    actor.cambot.alarmed = actor.threat;
    try @import("events.zig").sound(world, slots, projections, policy.alarm, pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
    // Reference uses camera-to-player distance here, not camera-to-monster.
    if (v.length(v.subtract(actor.threat_position, pose.position)) < 1024) for (slots.occupants) |occupant| {
        const other = occupant orelse continue;
        if (other.index == entity.index or !world.alive(other)) continue;
        const state = world.get(other, data.Actor) catch continue;
        if ((try world.get(other, data.Health)).current <= 0) continue;
        if (catalog.entries[state.definition].kind == .protopod and state.pod.phase == .shell) continue;
        if (!engine.inPhs(pose.position, (try world.get(other, data.Transform)).position)) continue;
        state.threat = actor.threat;
        state.threat_position = actor.threat_position;
        state.threat_seen_ms = now;
    };
    var text: [100]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 cambot: id={d} alarm={d}\n", .{ try world.persistentId(entity), actor.threat }));
}
fn backAway(pose: data.Transform, enemy: v.Vec3, speed: f32, slot: u16, state: *policy.State) !?v.Vec3 {
    var away = v.normalize(.{ pose.position[0] - enemy[0], pose.position[1] - enemy[1], 0 });
    if (@abs(pose.position[2] - enemy[2]) < 72) away[2] = 0.2;
    away = v.normalize(away);
    const direct = v.add(pose.position, v.scale(away, 72));
    const service = @import("actor_collision.zig").service();
    const hit = try service.trace(.{ .start = pose.position, .end = direct, .mins = @splat(-8), .maxs = @splat(8), .slot = slot, .mask = c.MASK_SOLID });
    if (!hit.start_solid and hit.fraction == 1) {
        state.back_direction = 0;
        return direct;
    }
    var directions: [2]v.Vec3 = undefined;
    for ([_]f32{ -60, 60 }, 0..) |degrees, i| {
        const angle = degrees * std.math.pi / 180;
        directions[i] = .{ away[0] * @cos(angle) - away[1] * @sin(angle), away[0] * @sin(angle) + away[1] * @cos(angle), away[2] };
    }
    for (0..2) |_| {
        var best: f32 = 72;
        var choice: ?usize = null;
        const prior = directions;
        for (&directions, 0..) |*direction, i| {
            const result = try service.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction.*, 1024)), .mins = @splat(-8), .maxs = @splat(8), .slot = slot, .mask = c.MASK_SOLID });
            if (!result.start_solid and result.fraction * 1024 >= best) {
                best = result.fraction * 1024;
                choice = i;
            }
            direction.* = v.normalize(v.add(direction.*, result.normal));
        }
        if (choice) |i| {
            const selected: i8 = if (i == 0) -1 else 1;
            if (state.back_direction != 0 and state.back_direction != selected) return null;
            state.back_direction = selected;
            return v.add(pose.position, v.scale(prior[i], speed * 0.15));
        }
    }
    return null;
}
fn dodge(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, pose: data.Transform, body: data.Body, enemy: v.Vec3) !?v.Vec3 {
    const random = try world.get(entity, data.Random);
    var degrees = random.next() * 360;
    const increment: f32 = if (random.next() > 0.5) 10 else -10;
    var distance: f32 = 250;
    while (distance > 100) : (distance *= 0.65) for (0..36) |_| {
        const direction = v.basis(.{ -20, pose.angles[1] + @trunc(degrees), pose.angles[2] }).forward;
        var point = v.add(pose.position, v.scale(direction, distance));
        if (random.next() > 0.5 and pose.position[2] > enemy[2] + distance / 2) point[2] = pose.position[2] - direction[2] * distance;
        const hit = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = point, .mins = v.scale(body.mins, 1.25), .maxs = v.scale(body.maxs, 1.25), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
        if (!hit.start_solid and hit.fraction == 1) return actors.air_routes.nearest(point);
        degrees += increment;
    };
    return null;
}
pub fn fly(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, now: i64, elapsed: u32) !void {
    const definition = actors.table.definitions[actor.definition];
    const slot = (try world.get(entity, data.Binding)).slot;
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        const random = try world.get(entity, data.Random);
        velocity.linear = @splat(0);
        if (access.find(world, actor.threat)) |enemy| {
            const point = (try enemy.get(data.Transform)).position;
            const delta = v.subtract(point, pose.position);
            pose.angles[1] = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
            pose.angles[0] = -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi;
            var destination: ?v.Vec3 = null;
            if (actor.cambot.evade) |away| {
                if (v.length(v.subtract(away, pose.position)) < 32) actor.cambot.evade = null else destination = away;
            } else if (!try clear(pose.position, point, slot)) destination = v.add(point, .{ 0, 0, 72 }) else switch (policy.movement(@sqrt(delta[0] * delta[0] + delta[1] * delta[1]))) {
                .follow => destination = v.add(point, .{ 0, 0, 72 }),
                .back_away => {
                    if (try backAway(pose.*, point, definition.speed, slot, &actor.cambot)) |away| {
                        if (try clear(point, away, (try enemy.get(data.Binding)).slot)) destination = away;
                    }
                },
                .hover => {
                    const enemy_pose = (try enemy.get(data.Transform)).*;
                    // The enemy may be a companion: no player view height.
                    const view_height: f32 = if (enemy.get(data.Player) catch null) |player| player.view_height else 22;
                    const eye = v.add(enemy_pose.position, .{ 0, 0, view_height });
                    const aim = try @import("actor_collision.zig").service().trace(.{ .start = eye, .end = v.add(eye, v.scale(v.basis(enemy_pose.angles).forward, 8192)), .mins = @splat(0), .maxs = @splat(0), .slot = (try enemy.get(data.Binding)).slot, .mask = c.MASK_SHOT });
                    // Until native auto-aim is connected, direct crosshair contact
                    // is the narrower compatibility definition of being targeted.
                    if (random.next() > 0.75 and aim.entity == slot) {
                        actor.cambot.evade = try dodge(actors, world, entity, pose.*, body, point);
                        destination = actor.cambot.evade;
                    }
                },
            }
            if (destination) |goal| if (try actors.air_routes.next(pose.position, goal, body, slot)) |waypoint| {
                // Follow tasks zero velocity before their 0.1-turn steering call;
                // normalized steering therefore starts directly toward the goal.
                velocity.linear = v.scale(v.normalize(v.subtract(waypoint, pose.position)), definition.speed);
            };
        }
        const phase = actor.cambot.wave;
        velocity.linear[2] += 15 * @sin((1 + 30 * @as(f32, @floatFromInt(phase))) * std.math.pi / 180);
        actor.cambot.wave = (phase + 1) % 12;
        actor.mode = if (v.length(velocity.linear) > 1) .chase else .idle;
        if (phase == 0) try @import("events.zig").sound(world, slots, projections, if (actor.threat == 0) "global/e_roomtoned.wav" else "global/e_roomtonee.wav", pose.position, slot, c.CHAN_AUTO, now);
        if (phase == 4 and (try world.get(entity, data.Random)).next() > (if (actor.threat == 0) @as(f32, 0.65) else 0.30)) {
            var sound: [64]u8 = undefined;
            const letter: u8 = 'a' + @as(u8, @intFromFloat((try world.get(entity, data.Random)).next() * 9));
            try @import("events.zig").sound(world, slots, projections, try std.fmt.bufPrint(&sound, "global/e_cntrltone{c}.wav", .{letter}), pose.position, slot, c.CHAN_AUTO, now);
        }
    }
    try @import("actor_flight.zig").move(pose, body, velocity, slot, elapsed);
    actor.ground_entity = c.ENTITYNUM_NONE;
}
