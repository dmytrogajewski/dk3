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
const Definition = @import("../domain/actors.zig").Definition;
pub fn initialize(world: *data.World, slots: *Slots, now: i64) void {
    // LastSummon was shared by all instances and reset by each spawn. Replicate
    // that deadline into the existing persisted class states.
    for (slots.occupants) |maybe| if (maybe) |entity| if (world.get(entity, data.Actor) catch null) |actor| if (catalog.entries[actor.definition].kind == .nharre) {
        actor.nharre.summon_ready_ms = now;
    };
}
fn teleports(world: *data.World, state: *catalog.nharre.State) !void {
    if (state.teleports_ready) return;
    var found: [ecs.max_entities]u32 = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.ascii.eqlIgnoreCase(object.targetname, "nharre")) {
            found[count] = try world.persistentId(entity);
            count += 1;
        };
    }
    std.mem.sort(u32, found[0..count], {}, std.sort.asc(u32));
    state.teleport_count = @intCast(@min(count, state.teleports.len));
    for (found[0..state.teleport_count], state.teleports[0..state.teleport_count]) |id, *point| point.* = (try world.get(world.find(id).?, data.Transform)).position;
    state.teleports_ready = true;
}
fn teleport(world: *data.World, entity: ecs.Entity, actor: *data.Actor, now: i64) !bool {
    const state = &actor.nharre;
    try teleports(world, state);
    const index = state.teleportIndex((try world.get(entity, data.Random)).next()) orelse return false;
    state.phase = .fading_out;
    state.destination = state.teleports[index];
    state.teleport_ready_ms = now + 2000;
    actor.melee.begin(0, now);
    actor.reaction = null;
    actor.reaction_until_ms = null;
    actor.mode = .attack;
    return true;
}
fn choose(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, entity: ecs.Entity, target: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: data.Body, navigation: @import("../domain/navigation.zig").Service, now: i64) !void {
    const random = try world.get(entity, data.Random);
    if (try @import("actor_evasion.zig").targeted(world, entity, target, pose) and random.next() < 0.25 and now > actor.nharre.teleport_ready_ms) if (try teleport(world, entity, actor, now)) return;
    for (slots.occupants) |maybe| if (maybe) |other| if (world.get(other, data.Actor) catch null) |value| if (catalog.entries[value.definition].kind == .nharre) {
        actor.nharre.summon_ready_ms = @max(actor.nharre.summon_ready_ms, value.nharre.summon_ready_ms);
    };
    if (random.next() < 0.75 and now > actor.nharre.summon_ready_ms) {
        const demon = random.next() < 0.1;
        actor.nharre.summon_ready_ms = now + (if (demon) @as(i64, 10000) else 1500);
        for (slots.occupants) |maybe| if (maybe) |other| if (world.get(other, data.Actor) catch null) |value| if (catalog.entries[value.definition].kind == .nharre) {
            value.nharre.summon_ready_ms = actor.nharre.summon_ready_ms;
        };
        actor.nharre.phase = .combat;
        actor.melee.begin(@intFromBool(demon), now);
        actor.mode = .attack;
        actor.changed_ms = now;
    } else {
        const enemy = (try world.get(target, data.Transform)).position;
        actor.nharre.destination = try @import("nharre_retreat.zig").find(&actors.water_routes, pose, body, enemy, (try world.get(entity, data.Binding)).slot, (try world.get(target, data.Binding)).slot, navigation, random);
        actor.nharre.phase = .retreat;
        actor.nharre.retreat_until_ms = now + 3000 + @as(i64, @intFromFloat(v.length(v.subtract(actor.nharre.destination, pose.position)) / actors.table.definitions[actor.definition].speed * 1000));
        actor.melee.active = false;
        actor.mode = .chase;
        actor.changed_ms = now;
        actor.route = .{};
    }
}
pub fn step(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32, slow: f32) !void {
    const definition = actors.table.definitions[actor.definition];
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        try think(actors, world, slots, projections, entity, actor, pose, body, definition, navigation, now);
    }
    if (actor.mode != .chase) {
        velocity.linear[0] = 0;
        velocity.linear[1] = 0;
    }
    try @import("actor_motion.zig").step(actor, pose, body, velocity, navigation, if (actor.nharre.phase == .retreat) actor.nharre.destination else actor.threat_position, definition.speed * slow, (try world.get(entity, data.Binding)).slot, now, elapsed);
}
fn think(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, definition: Definition, navigation: @import("../domain/navigation.zig").Service, now: i64) !void {
    const state = &actor.nharre;
    if (state.invulnerable()) {
        actor.mode = .attack;
        var clear = false;
        if (state.phase == .fading_out and state.alpha <= 0.1) {
            const hit = try engine.collisionService().trace(.{ .start = state.destination, .end = state.destination, .mins = body.mins, .maxs = body.maxs, .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_PLAYERSOLID });
            clear = !hit.start_solid and !hit.all_solid;
        }
        switch (state.fade(clear)) {
            .waiting => {},
            .relocate => {
                pose.position = state.destination;
                actor.route = .{};
                body.grounded = false;
                actor.ground_entity = c.ENTITYNUM_NONE;
            },
            .finished => {
                actor.melee.active = false;
                actor.mode = .idle;
                if (world.find(actor.threat)) |target| if ((try world.get(target, data.Health)).current > 0) try choose(actors, world, slots, entity, target, actor, pose.*, body.*, navigation, now);
            },
        }
        return;
    }
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    const attacking = actor.melee.active;
    const sensed = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (actor.reaction_until_ms) |until| if (now >= until) {
        actor.reaction = null;
        actor.reaction_until_ms = null;
    };
    if (injured) {
        _ = try @import("actor_pain.zig").generic(world, entity, actor, definition, hurt.amount, 1, 35, now);
        if (attacking and now > actor.pain_ready_ms and now > state.teleport_ready_ms) if (try teleport(world, entity, actor, now)) return;
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
    if (state.phase == .retreat) {
        const close = @import("../domain/navigation.zig").horizontalDistance(pose.position, state.destination) < definition.speed * (if (definition.speed > 175) @as(f32, 0.1) else 0.2) and @abs(pose.position[2] - state.destination[2]) < 32;
        if (close or now >= state.retreat_until_ms) try choose(actors, world, slots, entity, target, actor, pose.*, body.*, navigation, now) else actor.mode = .chase;
        return;
    }
    const offset = v.subtract((try world.get(target, data.Transform)).position, pose.position);
    const yaw = std.math.atan2(offset[1], offset[0]) * 180 / std.math.pi;
    pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    if (!actor.melee.active) {
        if (sensed.visible and sensed.distance <= definition.attack_range) try choose(actors, world, slots, entity, target, actor, pose.*, body.*, navigation, now) else actor.mode = .chase;
        return;
    }
    actor.mode = .attack;
    state.alpha = 1;
    const sequence = definition.attacks[actor.melee.pose];
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (actor.melee.event(1, @divTrunc(@as(i64, definition.strikes[actor.melee.pose]) * 1000, sequence.fps), now, false) and @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) < 5) {
        if (actor.melee.pose == 1) {
            if (sensed.visible) try @import("nharre_reaper.zig").launch(world, slots, projections, entity, target, now);
        } else try summon(actors, world, slots, projections, entity, target, pose.*, body.*, definition, now);
    } else {
        // The ranged callback faces a second time when no strike is delivered.
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
    }
    if (now - actor.melee.started_ms >= sequence.duration()) try choose(actors, world, slots, entity, target, actor, pose.*, body.*, navigation, now);
}
fn summon(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, target: ecs.Entity, pose: data.Transform, body: data.Body, definition: Definition, now: i64) !void {
    const slot = (try world.get(entity, data.Binding)).slot;
    var yaw = pose.angles[1];
    var point: ?v.Vec3 = null;
    for (0..8) |i| {
        if (i > 0) yaw += @as(f32, @floatFromInt(i)) * 45;
        const candidate = v.add(v.add(pose.position, v.scale(v.basis(.{ -5, yaw, pose.angles[2] }).forward, 96)), .{ 0, 0, 32 });
        if (!try ground(pose.position, candidate, definition.speed)) continue;
        const hit = try engine.collisionService().trace(.{ .start = candidate, .end = v.add(candidate, .{ 0, 0, -1 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        if (hit.fraction == 1 and !hit.start_solid and !hit.all_solid) {
            point = candidate;
            break;
        }
    }
    const selected: usize = @intFromFloat(@min(2, (try world.get(entity, data.Random)).next() * 3));
    const position = point orelse return; // No uninitialized spawn position on failed clearance.
    const classname = ([_][]const u8{ "monster_buboid", "monster_doombat", "monster_plague_rat" })[selected];
    const shape = actors.table.definitions[catalog.find(classname).?];
    const hit = try engine.collisionService().trace(.{ .start = position, .end = position, .mins = shape.mins, .maxs = shape.maxs, .slot = c.ENTITYNUM_NONE, .mask = c.MASK_PLAYERSOLID });
    if (hit.start_solid or hit.all_solid) return;
    const direction = v.subtract((try world.get(target, data.Transform)).position, position);
    const spawned = try actors.spawnAuthored(world, slots, projections, .{ .classname = classname, .properties = if (selected == 0) &.{.{ .key = "aistate", .value = "buboidcoffin" }} else &.{} }, .{ .position = position, .angles = .{ 0, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 } }, now);
    const child = try world.get(spawned, data.Actor);
    child.threat = try world.persistentId(target);
    child.threat_position = (try world.get(target, data.Transform)).position;
    if (selected == 1) child.mode = .chase;
    try actors.publish(world, spawned, projections, now);
    const fx = @import("summon_effects.zig");
    try fx.flare(world, slots, projections, spawned, position, .{ 1, 8, 10 }, .{ 25, 15, 45 }, 700, false, true, now);
    try fx.smoke(world, slots, projections, spawned, position, now);
}
fn ground(from: v.Vec3, to: v.Vec3, speed: f32) !bool {
    if (!try floor(to)) return false;
    const delta = v.subtract(to, from);
    const distance = v.length(delta);
    if (speed <= 0) return false;
    var sample = speed * 0.1;
    while (sample < distance) : (sample += speed * 0.1) if (!try floor(v.add(from, v.scale(v.normalize(delta), sample)))) return false;
    return true;
}
fn floor(point: v.Vec3) !bool {
    const hit = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -72 }), .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SOLID });
    return hit.fraction < 1 or hit.start_solid;
}
