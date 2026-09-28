// SPDX-License-Identifier: GPL-2.0-or-later
//! NPC Wyndrax/Garroth wisps and Wyndrax's fixed-point lightning discharge.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const access = @import("region_access.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").wyndrax;
const life = @import("weapon_entities.zig");
pub fn active(world: *data.World, owner: u32) u16 {
    var count = countActive(world, owner);
    if (access.contextFor(world)) |context| {
        var neighbors = access.Neighbors.init(context);
        while (neighbors.next()) |neighbor| if (&neighbor.world.? != world) {
            count += countActive(&neighbor.world.?, owner);
        };
    }
    return count;
}
fn countActive(world: *data.World, owner: u32) u16 {
    var count: u16 = 0;
    var query = world.queryAccess(data.World.mask(.{data.ActorAttack}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.ActorAttack)) |attack| if (attack.owner == owner and attack.attack == .npc_wisp) {
        count += 1;
    };
    return count;
}

pub fn wisp(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: Ref, pose: data.Transform, now: i64) !void {
    var random = (try world.get(owner, data.Random)).*;
    const speed = 500 + random.next() * 500;
    var personality = random.next();
    if (random.next() > 0.5) personality = -personality;
    const state: policy.Wisp = .{ .target = try target.id(), .next_ms = now + 100, .personality = personality, .forward = v.basis(pose.angles).forward, .sprite_scale = 1 + random.next() * 0.5 };
    (try world.get(owner, data.Random)).* = random;
    const entity = try world.create(null, .{
        data.Transform{ .position = v.add(pose.position, .{ -10, 10, 22 }), .angles = pose.angles },                                     data.Velocity{ .linear = v.scale(v.normalize(v.subtract((try target.get(data.Transform)).position, pose.position)), speed) },
        data.Body{ .mins = @splat(-1), .maxs = @splat(1), .contents = c.CONTENTS_BODY, .collision_mask = c.MASK_SOLID },                 data.Health{ .current = 10, .maximum = 10 },
        data.Hurt{},                                                                                                                     random,
        data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .npc_wisp = state } },
    });
    errdefer world.destroy(entity) catch unreachable;
    try life.bind(world, slots, projections, entity, policy.model);
    try publish(world, entity, projections, now);
    try @import("events.zig").sound(world, slots, projections, "e3/we_wwispshoota.wav", pose.position, (try world.get(owner, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn zap(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: Ref, pose: data.Transform, now: i64) !void {
    const entity = try world.create(null, .{ data.Transform{ .position = v.add(pose.position, .{ 0, 0, 24 }) }, data.Velocity{}, data.Body{}, data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .wyndrax_zap = .{ .target = try target.id(), .destination = (try target.get(data.Transform)).position } } } });
    errdefer world.destroy(entity) catch unreachable;
    try life.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections, now);
}
fn countBolts(world: *data.World, parent: u32, scenery: bool) usize {
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.ActorAttack}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.ActorAttack)) |attack| if (attack.attack == .wyndrax_bolt and attack.attack.wyndrax_bolt.parent == parent and (!scenery or attack.attack.wyndrax_bolt.kind == .scenery)) {
        count += 1;
    };
    return count;
}
fn bolt(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: u32, point: v.Vec3, value: policy.Bolt, now: i64) !void {
    if (countBolts(world, value.parent, false) >= 20) return;
    const entity = try world.create(null, .{ data.Transform{ .position = point }, data.Velocity{}, data.Body{}, data.ActorAttack{ .owner = owner, .born_ms = now, .stepped_ms = now, .attack = .{ .wyndrax_bolt = value } } });
    errdefer world.destroy(entity) catch unreachable;
    try life.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections, now);
}
pub fn charge(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, origin: v.Vec3, destination: v.Vec3, now: i64) !void {
    const id = try world.persistentId(owner);
    // Charging uses the same visible arc, but the source's owner is null:
    // its ZapThink therefore does not apply radius damage to the boss.
    for (0..2) |i| try bolt(world, slots, projections, id, origin, .{ .parent = id, .target = id, .destination = destination, .contact = (try world.get(owner, data.Transform)).position, .next_ms = now + 100, .until_ms = now + 750, .kind = .charge, .color = .{ 0.25, 0.45, 0.85 }, .flare = if (i == 0) origin else null, .flare_until_ms = now + 1350, .flare_scale = 5 }, now);
}
fn alive(world: *data.World, id: u32) bool {
    const entity = access.find(world, id) orelse return false;
    return (entity.get(data.Health) catch return false).current > 0;
}
fn angles(direction: v.Vec3) v.Vec3 {
    return .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 };
}
fn visible(world: *data.World, owner: u32, start: v.Vec3, end: v.Vec3, skip: u32, target: ?Ref) !bool {
    const hit = try @import("region_collision.zig").from(owner, .{ .start = start, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SOLID }, skip);
    return if (target) |other| @import("region_collision.zig").reaches(world, hit, other) else !hit.start_solid and !hit.all_solid and hit.fraction == 1;
}

fn sine(state: *policy.Wisp, pose: data.Transform, velocity: *data.Velocity, enemy: v.Vec3, random: *data.Random) void {
    var delta = v.subtract(enemy, pose.position);
    const distance = v.length(delta);
    delta[2] += 10 + random.next() * 50;
    var direction = v.scale(v.normalize(delta), 150);
    const phase: u4 = if (state.personality < 0) 11 - state.phase else state.phase;
    const radians = (1 + @as(f32, @floatFromInt(phase)) * 30) * std.math.pi / 180;
    const cs = @round(@cos(radians) * 1000) / 1000 * 100 * state.personality;
    if (@abs(@trunc(direction[0])) > @abs(@trunc(direction[1]))) direction[1] += cs else direction[0] -= cs;
    direction[2] += @round(@sin(radians) * 1000) / 1000 * 100 * state.personality;
    if (distance < 64) {
        direction[0] = -direction[0];
        direction[1] = -direction[1];
    } else if (distance < 100) {
        direction[0] = 0;
        direction[1] = 0;
    }
    velocity.linear = direction;
    if (state.phase == 11) {
        state.phase = 0;
        if (random.next() > 0.75) state.personality = @max(0.5, random.next()) * (if (state.personality < 0) @as(f32, -1) else 1);
    } else state.phase += 1;
}
pub fn fade(state: *policy.Wisp, now: i64) void {
    if (state.fading) return;
    state.fading = true;
    state.personality = if (state.personality < 0) -1 else 1;
    state.next_ms = now + 100;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const state = (try world.get(entity, data.ActorAttack)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = policy.render_tag;
    projection.state.modelindex = binding.model;
    projection.state.time = @intCast(state.born_ms);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    switch (state.attack) {
        .npc_wisp => |value| {
            projection.state.weapon = 0;
            projection.state.frame = 0;
            projection.state.angles2 = value.scale;
            projection.state.origin2 = .{ value.alpha, value.sprite_scale, 0 };
        },
        .wyndrax_zap => {
            projection.state.weapon = 1;
        },
        .wyndrax_bolt => |value| {
            projection.state.weapon = 2;
            projection.state.origin2 = value.destination;
            projection.state.angles2 = value.color;
            projection.state.time2 = @intCast(value.until_ms);
            projection.state.frame = if (value.kind == .wisp or value.kind == .scenery) 4 else 12;
            projection.state.legsAnim = if (value.flare != null) @intCast(value.flare_until_ms) else 0;
            projection.state.angles = value.flare orelse @splat(0);
            projection.state.torsoAnim = @intFromFloat(value.flare_scale * 100);
        },
        else => return error.InvalidWyndraxAttack,
    }
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = @bitCast(body.contents);
    projection.shared.ownerNum = if (world.find(state.owner)) |owner| if (world.get(owner, data.Binding) catch null) |other| other.slot else c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var attack = (try world.get(entity, data.ActorAttack)).*;
    if (now <= attack.stepped_ms) return;
    var motion = @import("region_motion.zig").Cursor.init(world, try world.persistentId(entity));
    var pose = (try world.get(entity, data.Transform)).*;
    var velocity = (try world.get(entity, data.Velocity)).*;
    const slot = (try world.get(entity, data.Binding)).slot;
    const id = try world.persistentId(entity);
    switch (attack.attack) {
        .npc_wisp => |*state| {
            var random = (try world.get(entity, data.Random)).*;
            const target = access.find(world, state.target);
            // A missing/dead target begins the existing fade, avoiding the
            // source's dangling enemy pointer during departures and reloads.
            if (!alive(world, state.target)) fade(state, now);
            while (attack.stepped_ms < now) {
                const at = @min(now, @min(attack.stepped_ms + 50, state.next_ms));
                const body = (try world.get(entity, data.Body)).*;
                const hit = try motion.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity.linear, @as(f32, @floatFromInt(at - attack.stepped_ms)) * 0.001)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
                pose.position = hit.end;
                if (hit.fraction < 1 or hit.start_solid) {
                    const speed = v.length(velocity.linear);
                    const incident = v.normalize(velocity.linear);
                    var reflected = v.subtract(incident, v.scale(hit.normal, 2 * v.dot(incident, hit.normal)));
                    for (&reflected) |*axis| if (@abs(axis.*) < 0.1) {
                        axis.* = 0;
                    };
                    velocity.linear = v.scale(v.normalize(reflected), speed * 0.75);
                    state.forward = v.subtract(state.forward, v.scale(hit.normal, 2 * v.dot(state.forward, hit.normal)));
                    pose.angles = angles(state.forward);
                    pose.position = v.add(pose.position, v.scale(hit.normal, 0.03125));
                    state.sine_ms = at + 200;
                }
                attack.stepped_ms = at;
                if (at < state.next_ms) continue;
                state.next_ms = at + 100;
                const enemy = if (target) |other| (try other.get(data.Transform)).position else pose.position;
                if (state.fading) {
                    state.alpha -= 0.05;
                    state.scale[0] -= 0.1;
                    state.scale[1] -= 0.1;
                    state.scale[2] += if (state.alpha < 0.5) @as(f32, -0.2) else 0.1;
                    sine(state, pose, &velocity, enemy, &random);
                    if (state.alpha < 0.001) {
                        try @import("events.zig").soundOwned(world, slots, projections, motion.owner, "e3/we_wwispaway.wav", pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, at);
                        return remove(world, slots, projections, entity);
                    }
                    continue;
                }
                pose.angles = angles(v.subtract(enemy, pose.position));
                if (at >= attack.born_ms + 20000 or !alive(world, attack.owner)) {
                    fade(state, at);
                    continue;
                }
                if (at >= state.sine_ms) sine(state, pose, &velocity, enemy, &random);
                if (random.next() > 0.55 and v.length(v.subtract(enemy, pose.position)) < 200 and target != null and try visible(world, motion.owner, pose.position, enemy, id, target)) {
                    // sinofs/12 is integer division in the authored callback.
                    try bolt(world, slots, projections, attack.owner, pose.position, .{ .parent = id, .target = state.target, .destination = enemy, .contact = enemy, .next_ms = at + 100, .until_ms = at + 200, .kind = .wisp }, at);
                }
                if (countBolts(world, id, true) < 10) {
                    const direction = v.normalize(.{ random.next() * 2 - 1, random.next() * 2 - 1, random.next() * 2 - 1 });
                    const ray = try @import("region_collision.zig").from(motion.owner, .{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, 1000)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT }, id);
                    if (ray.entity == c.ENTITYNUM_WORLD and ray.fraction < 1) try bolt(world, slots, projections, attack.owner, pose.position, .{ .parent = id, .destination = ray.end, .contact = ray.end, .next_ms = at + 100, .until_ms = at + 200, .kind = .scenery }, at);
                }
            }
            (try world.get(entity, data.Random)).* = random;
        },
        .wyndrax_zap => |*state| {
            while (attack.stepped_ms + 100 <= now and attack.stepped_ms + 100 < attack.born_ms + 550) {
                attack.stepped_ms += 100;
                const at = attack.stepped_ms;
                if (state.emitted >= 4) continue;
                const target = access.find(world, state.target) orelse break;
                const point = (try target.get(data.Transform)).position;
                const aim = angles(v.subtract(point, pose.position));
                for (0..2) |i| {
                    const forward = v.basis(v.add(aim, .{ 0, if (i == 0) @as(f32, -35) else 45, 0 })).forward;
                    const start = v.add(v.add(pose.position, v.scale(forward, if (i == 0) @as(f32, 15) else 40)), .{ 0, 0, if (i == 0) @as(f32, 10) else 15 });
                    const flare = if (i == 0) v.add(start, .{ 0, 0, -3 }) else v.add(v.add(pose.position, v.scale(forward, 24)), .{ 0, 0, 15 });
                    try bolt(world, slots, projections, attack.owner, start, .{ .parent = id, .target = state.target, .destination = state.destination, .contact = point, .next_ms = at + 100, .until_ms = at + 250, .kind = .zap, .color = .{ 0.25, 0.45, 0.85 }, .flare = flare, .flare_until_ms = at + 150 }, at);
                    state.emitted += 1;
                }
            }
            if (now >= attack.born_ms + 550) return remove(world, slots, projections, entity);
        },
        .wyndrax_bolt => |*state| {
            const parent = access.find(world, state.parent) orelse return life.remove(world, slots, projections, entity);
            const parent_pose = (try parent.get(data.Transform)).position;
            const target = access.find(world, state.target);
            if (state.kind == .wisp or state.kind == .scenery) {
                pose.position = parent_pose;
                if (target) |other| {
                    state.destination = (try other.get(data.Transform)).position;
                    state.contact = state.destination;
                }
            }
            while (now >= state.next_ms and state.next_ms <= state.until_ms + 100) {
                const at = state.next_ms;
                state.next_ms += 100;
                if (state.kind == .wisp and target != null and state.target != attack.owner) {
                    _ = try @import("weapon_damage.zig").hurt(target.?.world, target.?.entity, attack.owner, 0, 2, at, false);
                } else if (state.kind == .zap) {
                    const skip: u16 = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
                    const contact = try @import("region_collision.zig").owned(parent.world, .{ .start = parent_pose, .end = state.contact, .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = 0 }, state.parent);
                    try @import("area_damage.zig").apply(world, slots, .{ .world = contact.world, .owner = attack.owner, .weapon = 0, .origin = state.contact, .damage = 5, .radius = 90, .skip_slot = skip, .self_scale = 0, .inertial = true }, at);
                }
                if (state.kind == .wisp or state.kind == .scenery) {
                    var random = (try parent.get(data.Random)).*;
                    const variant: u8 = 'a' + @as(u8, @intFromFloat(random.next() * 3));
                    (try parent.get(data.Random)).* = random;
                    var buffer: [40]u8 = undefined;
                    try @import("events.zig").sound(world, slots, projections, try std.fmt.bufPrint(&buffer, "e3/we_wwispcordite{c}.wav", .{variant}), pose.position, slot, c.CHAN_AUTO, at);
                }
                const source_dead = if (state.kind == .wisp or state.kind == .scenery) !alive(world, state.parent) else false;
                const target_dead = state.kind == .wisp and !alive(world, state.target);
                if (at >= state.until_ms or source_dead or target_dead or !try visible(parent.world, @import("region_motion.zig").Cursor.init(parent.world, state.parent).owner, parent_pose, state.contact, state.parent, target)) {
                    // A charge flare outlives the arc that created it.
                    state.until_ms = @min(state.until_ms, at);
                    if (state.flare_until_ms <= now) return life.remove(world, slots, projections, entity);
                    state.next_ms = state.flare_until_ms + 1;
                    break;
                }
            }
            if (now >= @max(state.until_ms + 100, state.flare_until_ms) and state.next_ms > state.until_ms) return life.remove(world, slots, projections, entity);
            attack.stepped_ms = now;
        },
        else => return error.InvalidWyndraxAttack,
    }
    (try world.get(entity, data.ActorAttack)).* = attack;
    (try world.get(entity, data.Transform)).* = pose;
    (try world.get(entity, data.Velocity)).* = velocity;
    try publish(world, entity, projections, now);
    try motion.finish(world, entity, now);
}
fn remove(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, parent: ecs.Entity) !void {
    const id = try world.persistentId(parent);
    const occupants = slots.occupants;
    for (occupants) |maybe| if (maybe) |entity| {
        const attack = world.get(entity, data.ActorAttack) catch continue;
        if (attack.attack == .wyndrax_bolt and attack.attack.wyndrax_bolt.parent == id) try life.remove(world, slots, projections, entity);
    };
    try life.remove(world, slots, projections, parent);
}
