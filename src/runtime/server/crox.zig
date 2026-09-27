// SPDX-License-Identifier: GPL-2.0-or-later
//! Crox sensing, supplied melee events and amphibious movement.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/actors.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").crox;
const Routes = @import("air_routes.zig").Routes;

pub fn waterLevel(point: v.Vec3, body: data.Body, slot: u16) !u2 {
    var level: u2 = 0;
    for ([_]f32{ body.mins[2] + 1, 0, body.maxs[2] - 1 }) |height| {
        if (try engine.collisionService().contents(v.add(point, .{ 0, 0, height }), slot) & c.MASK_WATER == 0) break;
        level += 1;
    }
    return level;
}

fn wander(routes: *const Routes, pose: data.Transform, state: policy.State, definition: rules.Definition, random: *data.Random) ?v.Vec3 {
    var nearest: usize = 0;
    var distance = std.math.inf(f32);
    if (routes.nodes.len == 0) return null;
    for (routes.nodes, 0..) |node, i| {
        const separation = v.length(v.subtract(node.position, pose.position));
        if (separation < distance) {
            nearest = i;
            distance = separation;
        }
    }
    const links = routes.nodes[nearest].links;
    if (links.len == 0) return null;
    var eligible: [6]usize = undefined;
    var count: usize = 0;
    for (links, 0..) |link, i| {
        const point = routes.nodes[routes.indices[@intCast(link[1])].?].position;
        const offset = v.subtract(point, pose.position);
        if (!policy.wanderCandidate(v.length(v.subtract(point, state.start)), definition.sight_range, @sqrt(offset[0] * offset[0] + offset[1] * offset[1]), offset[2], std.math.atan2(offset[1], offset[0]) * 180 / std.math.pi - pose.angles[1], definition.walk_speed)) continue;
        eligible[count] = i;
        count += 1;
    }
    const fraction = random.next();
    const index = if (count == 0) @as(usize, @intFromFloat(fraction * @as(f32, @floatFromInt(links.len)))) else eligible[@intFromFloat(fraction * @as(f32, @floatFromInt(count)))];
    return routes.nodes[routes.indices[@intCast(links[index][1])].?].position;
}

fn strike(world: *data.World, slots: *Slots, entity: ecs.Entity, enemy: ecs.Entity, pose: data.Transform, definition: rules.Definition, now: i64) !void {
    const direction = v.normalize(v.subtract((try world.get(enemy, data.Transform)).position, pose.position));
    const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SHOT });
    if (hit.entity >= slots.occupants.len) return;
    const target = slots.occupants[hit.entity] orelse return;
    if ((world.get(target, data.Health) catch null) == null) return;
    const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
    _ = try @import("weapon_damage.zig").hurt(world, target, try world.persistentId(entity), 0, amount, now, false);
    try @import("weapon_damage.zig").shove(world, target, try world.persistentId(entity), direction, amount, now);
    var text: [128]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 crox: id={d} contact={d} damage={d:.2}\n", .{ try world.persistentId(entity), try world.persistentId(target), amount }));
}

pub fn think(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, now: i64) !void {
    if (now < actor.think_ms) return;
    actor.think_ms = now + 100;
    const definition = actors.table.definitions[actor.definition];
    const slot = (try world.get(entity, data.Binding)).slot;
    const state = &actor.crox;
    state.water = try waterLevel(pose.position, body, slot);
    const enemy = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    var point: ?v.Vec3 = null;
    if (enemy.enemy) |target| point = (try world.get(target, data.Transform)).position;
    state.wandering = point == null or policy.beyondHeight(point.?[2] - pose.position[2]);
    if (!state.attacking and now >= state.cycle_ms) {
        state.swimming = state.water >= 2;
        const sequence = if (state.swimming) definition.swim else if (state.wandering) definition.walk else definition.run;
        state.cycle_ms = now + sequence.duration();
        actor.changed_ms = now;
        if (state.swimming and @mod(@divTrunc(now, 1000), 2) == 1) {
            var sound: [32]u8 = undefined;
            const index: u8 = 1 + @as(u8, @intFromFloat((try world.get(entity, data.Random)).next() * 3));
            try @import("events.zig").sound(world, slots, projections, try std.fmt.bufPrint(&sound, "hiro/swim{d}.wav", .{index}), pose.position, slot, c.CHAN_AUTO, now);
        }
    }
    if (state.wandering) {
        state.attacking = false;
        if (state.destination == null or now >= state.wander_until_ms or v.length(v.subtract(state.destination.?, pose.position)) < definition.walk_speed * 0.2) {
            state.destination = wander(&actors.crox_routes, pose.*, state.*, definition, try world.get(entity, data.Random));
            if (state.destination) |destination| state.wander_until_ms = now + @as(i64, @intFromFloat(v.length(v.subtract(destination, pose.position)) / definition.walk_speed * 1000)) + 1000;
        }
        if (state.destination) |destination| actor.threat_position = destination;
        actor.mode = if (state.destination != null) .chase else .idle;
        return;
    }
    state.destination = null;
    const delta = v.subtract(point.?, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    const turn = @mod(yaw - pose.angles[1] + 180, 360) - 180;
    pose.angles[1] += std.math.clamp(turn, -definition.yaw_speed, definition.yaw_speed);
    const facing = policy.facing(yaw - pose.angles[1]);
    if (enemy.distance > definition.range or !enemy.visible) {
        state.attacking = false;
        actor.mode = .chase;
        return;
    }
    velocity.linear = @splat(0);
    if (!state.attacking) {
        actor.mode = .idle;
        if (!facing) return;
        state.begin(now, (try world.get(entity, data.Random)).next());
    }
    actor.mode = .attack;
    const index = state.pose;
    const elapsed = now - state.started_ms;
    if (!state.struck and facing and elapsed >= @divTrunc(@as(i64, definition.strikes[index]) * 1000, definition.attacks[index].fps)) {
        state.struck = true;
        try strike(world, slots, entity, enemy.enemy.?, pose.*, definition, now);
    }
    const times = [_]?i64{ definition.attack_sound_ms[index], definition.second_sound_ms[index] };
    const sounds = [_][]const u8{ definition.attack_sounds[index], definition.second_attack_sounds[index] };
    for (times, sounds, 0..) |time, sound, bit| if (time) |at| {
        const flag = @as(u2, 1) << @as(u1, @intCast(bit));
        if (state.sounded & flag == 0 and elapsed >= at) {
            state.sounded |= flag;
            if (sound.len != 0) try @import("events.zig").sound(world, slots, projections, sound, pose.position, slot, c.CHAN_WEAPON, now);
        }
    };
    if (elapsed >= definition.attacks[index].duration()) {
        state.attacking = false;
        state.cycle_ms = now;
        actor.mode = .idle;
    }
}

pub fn swim(actors: *@import("actors.zig").Actors, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, definition: rules.Definition, slot: u16, elapsed: u32, slow: f32) !void {
    if (actor.mode == .chase) {
        if (try actors.crox_routes.next(pose.position, actor.threat_position, body.*, slot)) |destination| {
            velocity.linear = v.scale(v.normalize(v.subtract(destination, pose.position)), definition.speed * slow);
            const delta = velocity.linear;
            pose.angles = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
        } else velocity.linear = @splat(0);
    } else velocity.linear = @splat(0);
    var motion: @import("../domain/slide.zig").State = .{ .position = pose.position, .velocity = velocity.linear };
    var remaining = elapsed;
    while (remaining > 0) {
        const slice = @min(50, remaining);
        remaining -= slice;
        actor.crox.water = try waterLevel(motion.position, body.*, slot);
        const floor = try engine.collisionService().trace(.{ .start = motion.position, .end = v.add(motion.position, .{ 0, 0, -0.25 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        body.grounded = !floor.start_solid and floor.fraction < 1 and floor.normal[2] >= 0.7;
        actor.ground_entity = if (body.grounded) floor.entity else c.ENTITYNUM_NONE;
        var context: @import("../domain/slide.zig").Context = .{ .service = engine.collisionService(), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask, .delta = @as(f32, @floatFromInt(slice)) * 0.001, .gravity = if (actor.crox.water == 3 or body.grounded) 0 else 800 };
        _ = try context.move(&motion);
    }
    pose.position = motion.position;
    velocity.linear = motion.velocity;
}
