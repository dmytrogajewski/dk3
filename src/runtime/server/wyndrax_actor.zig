// SPDX-License-Identifier: GPL-2.0-or-later
//! Wyndrax's combat, power station and authored Wisp collection goals.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const wisps = @import("wisps.zig");
const attacks = @import("wyndrax_attacks.zig");
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        if (actor.reaction_until_ms) |until| if (now >= until) {
            actor.reaction = null;
            actor.reaction_until_ms = null;
        };
        const hurt = (try world.get(entity, data.Hurt)).*;
        if (hurt.revision != actor.receipt) {
            actor.receipt = hurt.revision;
            _ = try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 5, 40, now);
            if (actor.wyndrax.phase == .combat and world.find(hurt.source) != null) actor.threat = hurt.source;
        }
        if (actor.reaction_until_ms == null) try think(actors, world, slots, projections, entity, actor, pose, body.*, definition, now) else actor.mode = .idle;
    }
    if (actor.mode != .chase) {
        velocity.linear[0] = 0;
        velocity.linear[1] = 0;
    }
    const speed = if (actor.wyndrax.running) definition.speed else definition.walk_speed;
    try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, actor.threat_position, speed * slow, (try world.get(entity, data.Binding)).slot, now, elapsed);
}
fn face(pose: *data.Transform, target: v.Vec3, speed: f32) bool {
    const delta = v.subtract(target, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -speed, speed);
    return @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) < 5;
}
fn begin(actor: *data.Actor, index: u3, now: i64) void {
    actor.melee.begin(index, now);
    actor.mode = .attack;
    actor.changed_ms = now;
}
fn resumeCombat(actor: *data.Actor, now: i64) void {
    actor.wyndrax.phase = .combat;
    actor.wyndrax.source = 0;
    actor.wyndrax.running = true;
    actor.ignore_player = false;
    actor.melee.active = false;
    actor.mode = .idle;
    actor.changed_ms = now;
}
fn findCharge(world: *data.World) ?ecs.Entity {
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.ascii.eqlIgnoreCase(object.targetname, "WyndraxCharge")) return entity;
    return null;
}
fn findSwarm(world: *data.World, point: v.Vec3) ?ecs.Entity {
    var closest: ?ecs.Entity = null;
    var distance: f32 = 10000;
    var query = world.queryAccess(data.World.mask(.{ data.WispSwarm, data.Transform }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.WispSwarm), view.read(data.Transform)) |entity, swarm, pose| {
        const candidate = v.length(v.subtract(pose.position, point));
        if (candidate < distance and wisps.active(world, swarm) > 0) {
            closest = entity;
            distance = candidate;
        }
    };
    return closest;
}
fn floor(world: *data.World, entity: ecs.Entity, distance: f32) !v.Vec3 {
    const point = (try world.get(entity, data.Transform)).position;
    const slot: u16 = if (world.get(entity, data.Binding) catch null) |binding| binding.slot else c.ENTITYNUM_NONE;
    return (try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -distance }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY })).end;
}
fn close(point: v.Vec3, destination: v.Vec3, speed: f32) bool {
    const delta = v.subtract(destination, point);
    return @sqrt(delta[0] * delta[0] + delta[1] * delta[1]) < @max(16, speed * 0.1) and @abs(delta[2]) < 32;
}
fn speak(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, point: v.Vec3, chance: f32, now: i64) !void {
    const random = try world.get(entity, data.Random);
    if (random.next() >= chance) return;
    const sound = if (random.next() > 0.5) "e3/m_wyndraxsightb.wav" else "e3/m_wyndraxsightc.wav";
    try @import("events.zig").sound(world, slots, projections, sound, point, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
fn think(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, definition: Definition, now: i64) !void {
    const state = &actor.wyndrax;
    switch (state.phase) {
        .combat => {
            const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
            const target = sensed.enemy orelse {
                actor.mode = .idle;
                actor.melee.active = false;
                return;
            };
            const enemy = (try world.get(target, data.Transform)).position;
            const facing = face(pose, enemy, definition.yaw_speed);
            if (!actor.melee.active) {
                if (!sensed.visible or sensed.distance >= definition.range) {
                    actor.mode = .chase;
                    return;
                }
                if ((try world.get(entity, data.Health)).current > @divTrunc(definition.health, 2)) {
                    if (!state.charged) {
                        state.phase = .powerup;
                        actor.mode = .idle;
                        return;
                    }
                    begin(actor, 0, now);
                    try @import("events.zig").sound(world, slots, projections, "e3/m_wyndraxataka.wav", pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
                } else if (state.ammo == 0) {
                    state.phase = .find_swarm;
                    actor.ignore_player = true;
                    actor.mode = .idle;
                    return;
                } else if (attacks.active(world, try world.persistentId(entity)) >= 10) {
                    if (try retreat(actors, world, entity, pose.*, body, target)) |point| {
                        state.phase = .retreat;
                        state.destination = point;
                        state.until_ms = now + 2000;
                        state.running = v.length((try world.get(target, data.Velocity)).linear) > 75;
                        actor.mode = .chase;
                        actor.threat_position = point;
                    } else actor.mode = .idle;
                    return;
                } else begin(actor, 1, now);
            }
            actor.mode = .attack;
            const sequence = definition.attacks[actor.melee.pose];
            if ((try world.get(entity, data.Health)).current > @divTrunc(definition.health, 2)) {
                if (state.charged and sequence.frame(now - actor.melee.started_ms, false) > 120 and facing) {
                    try @import("events.zig").sound(world, slots, projections, "e3/m_wwisplightning.wav", pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
                    try attacks.zap(world, slots, projections, entity, target, pose.*, now);
                    state.charged = false;
                    actor.melee.active = false;
                }
            } else if (state.ammo == 0) {
                state.phase = .find_swarm;
                actor.ignore_player = true;
                actor.melee.active = false;
            } else if (attacks.active(world, try world.persistentId(entity)) < 10) {
                try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
                if (facing and actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[actor.melee.pose]) * 1000, sequence.fps), now, false)) {
                    try attacks.wisp(world, slots, projections, entity, target, pose.*, now);
                    state.ammo -= 1;
                }
                if (now - actor.melee.started_ms >= sequence.duration()) actor.melee.active = false;
            }
        },
        .powerup => {
            const source = world.find(state.charge) orelse findCharge(world);
            if (source) |station| {
                state.charge = try world.persistentId(station);
                if (v.length(v.subtract((try world.get(station, data.Transform)).position, pose.position)) >= 500) {
                    state.destination = v.add(try floor(world, station, 2000), .{ 0, 0, 24 });
                    state.phase = .approach_charge;
                    actor.ignore_player = true;
                    actor.melee.active = false;
                    actor.mode = .chase;
                    actor.threat_position = state.destination;
                    try speak(world, slots, projections, entity, pose.position, 0.3, now);
                    return;
                }
            }
            if (!actor.melee.active) begin(actor, 2, now);
            const sequence = definition.attacks[2];
            if (now - actor.melee.started_ms >= sequence.duration()) {
                state.charged = true;
                resumeCombat(actor, now);
                return;
            }
            const frame = sequence.frame(now - actor.melee.started_ms, false);
            if (frame > 83 and frame < 87) if (source) |station| try attacks.charge(world, slots, projections, entity, (try world.get(station, data.Transform)).position, v.add(pose.position, .{ 0, 0, 55 }), now);
        },
        .approach_charge, .approach_swarm => {
            actor.mode = .chase;
            actor.threat_position = state.destination;
            if (close(pose.position, state.destination, definition.speed)) {
                actor.mode = .idle;
                if (state.phase == .approach_charge) state.phase = .powerup else {
                    const source = world.find(state.source) orelse {
                        state.phase = .find_swarm;
                        return;
                    };
                    try wisps.collect(world, source, entity);
                    state.phase = .collect;
                    begin(actor, 3, now);
                }
            }
        },
        .find_swarm, .wander => {
            actor.ignore_player = true;
            actor.melee.active = false;
            const source = findSwarm(world, pose.position) orelse {
                // No active swarm is a missing authored dependency, not ammo.
                // Keep wandering/rechecking so dormant swarms can recover.
                if (state.phase != .wander or close(pose.position, state.destination, definition.walk_speed)) {
                    const point = try @import("actor_wander.zig").next(&actors.water_routes, pose.*, state.start_position, definition, try world.get(entity, data.Random), null);
                    state.destination = point orelse pose.position;
                }
                state.phase = .wander;
                state.running = false;
                actor.mode = .chase;
                actor.threat_position = state.destination;
                return;
            };
            state.running = true;
            state.source = try world.persistentId(source);
            state.destination = v.add(try floor(world, source, 1000), .{ 10, -10, 0 });
            if (v.length(v.subtract(state.destination, pose.position)) < 200) {
                try wisps.collect(world, source, entity);
                state.phase = .collect;
                begin(actor, 3, now);
            } else {
                state.phase = .approach_swarm;
                actor.mode = .chase;
                actor.threat_position = state.destination;
                try speak(world, slots, projections, entity, pose.position, 0.1, now);
            }
        },
        .collect => {
            const source = world.find(state.source) orelse {
                state.phase = .find_swarm;
                actor.melee.active = false;
                return;
            };
            _ = face(pose, (try world.get(source, data.Transform)).position, definition.yaw_speed);
            actor.mode = .attack;
            state.ammo = @intCast(@min(255, @as(u16, state.ammo) +| try wisps.take(world, source)));
            if (state.ammo >= 10) {
                try wisps.release(world, source);
                resumeCombat(actor, now);
                return;
            }
            const swarm = (try world.get(source, data.WispSwarm)).*;
            // The monitor must acknowledge its last delivered leaf before the
            // collector retires this source, including across restored frames.
            if (wisps.active(world, swarm) == 0 and swarm.sending == null) {
                try wisps.release(world, source);
                state.ammo +|= 1;
                actor.melee.active = false;
                state.source = 0;
                if (state.ammo >= 10) resumeCombat(actor, now) else state.phase = .find_swarm;
                return;
            }
            if (!actor.melee.active or now - actor.melee.started_ms >= definition.attacks[actor.melee.pose].duration()) begin(actor, 4, now);
        },
        .retreat => {
            actor.mode = .chase;
            actor.threat_position = state.destination;
            if (now >= state.until_ms or close(pose.position, state.destination, if (state.running) definition.speed else definition.walk_speed)) resumeCombat(actor, now);
        },
    }
}
fn retreat(actors: *@import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, pose: data.Transform, body: data.Body, target: ecs.Entity) !?v.Vec3 {
    const direction = v.normalize(v.subtract(pose.position, (try world.get(target, data.Transform)).position));
    const fast = v.length((try world.get(target, data.Velocity)).linear) > 75;
    const first = v.add(pose.position, v.scale(direction, if (fast) @as(f32, 96) else 48));
    const goal = v.add(pose.position, v.scale(direction, if (fast) @as(f32, 128) else 96));
    var nearest: usize = 0;
    var distance: f32 = std.math.inf(f32);
    for (actors.water_routes.nodes, 0..) |node, i| {
        const d = v.length(v.subtract(node.position, first));
        if (d < distance) {
            nearest = i;
            distance = d;
        }
    }
    if (actors.water_routes.nodes.len > 0) {
        var result: ?v.Vec3 = null;
        distance = 1024;
        for (actors.water_routes.nodes[nearest].links) |link| {
            const point = actors.water_routes.nodes[actors.water_routes.indices[@intCast(link[1])].?].position;
            const d = v.length(v.subtract(point, goal));
            if (d < distance) {
                result = point;
                distance = d;
            }
        }
        if (result) |point| return point;
    }
    const slot = (try world.get(entity, data.Binding)).slot;
    const yaw = std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi;
    for (0..24) |i| for (0..7) |j| {
        const point = v.add(pose.position, v.scale(v.basis(.{ 0, yaw + @as(f32, @floatFromInt(i)) * 15, 0 }).forward, 64 - @as(f32, @floatFromInt(j)) * 8));
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = point, .mins = v.scale(body.mins, 0.5), .maxs = v.scale(body.maxs, 0.5), .slot = slot, .mask = body.collision_mask });
        if (hit.fraction < 1 or hit.start_solid or hit.all_solid) continue;
        var supported = true;
        for (0..5) |n| {
            const along = v.add(pose.position, v.scale(v.subtract(point, pose.position), @as(f32, @floatFromInt(n)) / 4));
            const ground = try engine.collisionService().trace(.{ .start = along, .end = v.add(along, .{ 0, 0, body.mins[2] - 32 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
            if (ground.fraction == 1) {
                supported = false;
                break;
            }
        }
        if (supported) return point;
    };
    return actors.water_routes.nearest(v.add(pose.position, v.scale(direction, 48)));
}
