// SPDX-License-Identifier: GPL-2.0-or-later
//! Pod hatching and Slaughterskeet flight consume class policy and supplied tuning.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/actors.zig");
const v = @import("../domain/vector.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const perceive = @import("actor_perception.zig").perceive;
pub fn pod(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: *data.Body, now: i64) !void {
    if (now < actor.think_ms) return;
    actor.think_ms = now + 100;
    const definition = actors.table.definitions[actor.definition];
    const enemy = try perceive(world, slots, entity, actor, pose, definition, now);
    const random = try world.get(entity, data.Random);
    const xy = if (enemy.enemy) |target| @import("../domain/navigation.zig").horizontalDistance(pose.position, (try target.get(data.Transform)).position) else std.math.inf(f32);
    actor.pod.notice(now, enemy.visible, xy, random.next(), random.next());
    const previous = actor.pod.phase;
    if (actor.pod.tick(now, definition.hatch.duration())) {
        actor.changed_ms = now;
        body.mass = 0.5;
        const child = try actors.spawnDynamic(world, slots, projections, "monster_slaughterskeet", v.add(pose.position, .{ 0, 0, 10 }), pose.angles, now);
        const child_actor = try world.get(child, data.Actor);
        child_actor.threat = actor.threat;
        child_actor.threat_position = actor.threat_position;
        child_actor.skeeter.enter(.hatching, now, actors.table.definitions[child_actor.definition].hatch.duration());
        try @import("events.zig").sound(world, slots, projections, definition.hatch_sound, pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
        var buffer: [140]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 pod: id={d} hatched={d} enemy={d}\n", .{ try world.persistentId(entity), try world.persistentId(child), actor.threat }));
    }
    if (previous != .shell and actor.pod.phase == .shell) {
        body.mins = .{ -8, -8, -2 };
        body.maxs = .{ 8, 8, 2 };
        (try world.get(entity, data.Health)).current = 1;
    }
}
pub fn fly(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, now: i64, elapsed: u32) !void {
    const definition = actors.table.definitions[actor.definition];
    const slot = (try world.get(entity, data.Binding)).slot;
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        var enemy = try perceive(world, slots, entity, actor, pose.*, definition, now);
        // A submerged player is out of reach. The enemy may be a companion
        // (Superfly), which has no player state.
        if (enemy.enemy) |target| if (target.get(data.Player) catch null) |player| if (player.water_level == 3) {
            actor.threat = 0;
            enemy.enemy = null;
        };
        const previous = actor.skeeter.phase;
        const strike_ms = @divTrunc(@as(i64, definition.strikes[0]) * 1000, definition.attacks[0].fps);
        const hit = actor.skeeter.tick(now, enemy.enemy != null, enemy.visible, enemy.distance, definition.range, definition.attacks[0].duration(), strike_ms, v.length(v.subtract(actor.skeeter.retreat, pose.position)));
        if (actor.skeeter.phase != previous) {
            actor.changed_ms = now;
            if (actor.skeeter.phase == .retreat) actor.skeeter.retreat = (try @import("air_escape.zig").find(world, entity, pose.*, body, actor.threat_position, &actors.air_routes, 512, 178)) orelse return error.MissingSkeeterAirNodes;
        }
        if (hit and enemy.enemy != null) {
            const target = enemy.enemy.?;
            const point = v.add((try target.get(data.Transform)).position, .{ 0, 0, 8 });
            const direction = v.normalize(v.subtract(point, pose.position));
            const contact = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
            if (@import("region_access.zig").victim(world, slots, contact)) |victim| if ((victim.get(data.Player) catch null) != null) {
                const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
                _ = try @import("damage.zig").apply(victim.world, victim.entity, @intFromFloat(@ceil(amount)), now, .{ .source = try world.persistentId(entity) });
                var buffer: [120]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 skeeter: id={d} melee={d} damage={d:.2}\n", .{ try world.persistentId(entity), try victim.id(), amount }));
            };
        }
        if (actor.skeeter.phase == .attack) try @import("actor_attack_sounds.zig").at(world, slots, projections, entity, actor, definition, 0, actor.skeeter.started_ms, now, 3);
        velocity.linear = @splat(0);
        if (actor.skeeter.phase == .hatching) {
            // Supplied hatch animation lifts the emerging skeeter four units per think.
            const destination = v.add(pose.position, .{ 0, 0, 4 });
            const trace = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = destination, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID });
            pose.position = trace.end;
        } else if (enemy.enemy != null and actor.skeeter.phase != .attack) {
            const destination = if (actor.skeeter.phase == .retreat) actor.skeeter.retreat else v.add(actor.threat_position, .{ 0, 0, 24 });
            if (try actors.air_routes.next(pose.position, destination, body, slot)) |waypoint| {
                const offset = v.subtract(waypoint, pose.position);
                const distance = v.length(offset);
                const speed = definition.speed * (if (actor.skeeter.phase == .dart) @as(f32, 1.5) else 1);
                velocity.linear = v.scale(v.normalize(offset), @min(speed, distance * 10));
            }
        }
        actor.mode = if (actor.skeeter.phase == .attack) .attack else if (v.length(velocity.linear) > 0.1 or actor.skeeter.phase == .hatching) .chase else .idle;
        if (enemy.enemy != null) {
            const direction = v.subtract(actor.threat_position, pose.position);
            pose.angles[1] = std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi;
            pose.angles[0] = -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi;
        }
    }
    try @import("actor_flight.zig").move(pose, body, velocity, slot, elapsed);
    actor.ground_entity = c.ENTITYNUM_NONE;
}
