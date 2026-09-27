// SPDX-License-Identifier: GPL-2.0-or-later
//! Stave growth/acceleration and independently bouncing meteor fragments.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").meteors;
const life = @import("weapon_entities.zig");
fn angles(dir: v.Vec3) v.Vec3 {
    return .{ -std.math.atan2(dir[2], @sqrt(dir[0] * dir[0] + dir[1] * dir[1])) * 180 / std.math.pi, std.math.atan2(dir[1], dir[0]) * 180 / std.math.pi, 0 };
}
fn create(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: u32, pose: data.Transform, velocity: v.Vec3, state: policy.State, random: data.Random, now: i64) !void {
    const size: f32 = switch (state.phase) {
        .stave => 12,
        .fragment => 5,
        .flare, .impact => 0,
    };
    const entity = try world.create(null, .{ pose, random, data.Velocity{ .linear = velocity }, data.Body{ .mins = @splat(-size), .maxs = @splat(size), .collision_mask = c.MASK_SHOT }, data.ActorAttack{ .owner = owner, .born_ms = now, .stepped_ms = now, .attack = .{ .meteor = state } } });
    errdefer world.destroy(entity) catch unreachable;
    try life.bind(world, slots, projections, entity, if (state.phase == .flare) "models/e3/we_blackhole.sp2" else policy.model);
    try publish(world, entity, projections, now);
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    var random = (try world.get(owner, data.Random)).*;
    const aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, &random);
    const turn = v.add(angles(v.subtract((try world.get(target, data.Transform)).position, pose.position)), .{ -45, 35, 0 });
    const point = v.add(v.add(pose.position, v.scale(v.basis(turn).forward, 25)), .{ 0, 0, 25 });
    const state: policy.State = .{ .next_ms = now + 100, .spin = .{ (random.next() * 2 - 1) * 40, (random.next() * 2 - 1) * 40, (random.next() * 2 - 1) * 40 }, .damage = tuning.damage, .radius = tuning.damage, .speed = tuning.speed };
    const id = try world.persistentId(owner);
    (try world.get(owner, data.Random)).* = random;
    try create(world, slots, projections, id, .{ .position = point, .angles = angles(aim.direction) }, v.scale(aim.direction, tuning.speed * 0.05), state, random, now);
    try create(world, slots, projections, id, .{ .position = point }, @splat(0), .{ .phase = .flare, .next_ms = now + 100, .scale = @splat(0.1), .spin = .{ 0, 0, 15 }, .damage = 0, .radius = 0, .speed = 0 }, random, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const attack = (try world.get(entity, data.ActorAttack)).*;
    const state = attack.attack.meteor;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = policy.render_tag;
    projection.state.modelindex = binding.model;
    projection.state.weapon = @intFromEnum(state.phase);
    projection.state.time = @intCast(attack.born_ms);
    projection.state.frame = if (state.phase == .flare) 10 else 0;
    projection.state.angles2 = state.scale;
    projection.state.origin2 = if (state.phase == .impact) state.normal else .{ state.glow, 0, 0 };
    projection.state.otherEntityNum = @intFromBool(state.scorch);
    projection.state.time2 = @intFromFloat(state.radius);
    projection.state.loopSound = if (state.phase == .stave) try @import("resources.zig").sound("global/e_torchd.wav") else 0;
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = 0;
    projection.shared.ownerNum = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
fn impact(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, attack: data.ActorAttack, state: policy.State, pose: data.Transform, velocity: v.Vec3, normal: v.Vec3, world_contact: bool, now: i64) !void {
    var random = (try world.get(entity, data.Random)).*;
    if (state.phase == .stave) {
        const count: usize = 4 + @as(usize, @intFromFloat(random.next() * 3));
        const reflection = angles(v.scale(v.normalize(velocity), -1));
        for (0..count) |_| {
            const direction = v.basis(v.add(reflection, .{ (random.next() * 2 - 1) * 45, (random.next() * 2 - 1) * 45, 0 })).forward;
            const point = v.add(pose.position, .{ (random.next() * 2 - 1) * 25, (random.next() * 2 - 1) * 25, (random.next() * 2 - 1) * 25 });
            const size = 0.3 + random.next() * 0.35;
            const scale: v.Vec3 = .{ size + random.next() * 0.2, size + random.next() * 0.2, size + random.next() * 0.2 };
            const spin: v.Vec3 = .{ (random.next() * 2 - 1) * 30, 0, (random.next() * 2 - 1) * 30 };
            const bounce_max = 2 + random.next() * 3;
            // Fragment health is never assigned by the source spawn callback.
            // Its radius is scaled, but its damage remains zero; do not invent it.
            try create(world, slots, projections, attack.owner, .{ .position = point, .angles = angles(direction) }, v.scale(direction, v.length(velocity) * 1.85), .{ .phase = .fragment, .next_ms = now + 100, .scale = scale, .spin = spin, .damage = 0, .radius = size / 0.25 * state.damage, .speed = 0, .glow = 1.2 * size * 0.65, .bounce_max = bounce_max }, random, now);
        }
    }
    const point = v.add(pose.position, v.scale(normal, 4));
    const skip: u16 = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    try @import("area_damage.zig").apply(world, slots, .{ .owner = attack.owner, .weapon = 0, .origin = point, .damage = state.damage, .radius = state.radius, .skip_slot = skip, .self_scale = 0 }, now);
    try @import("scenery.zig").explosion(world, slots, projections, point, 1, now);
    const wet = try engine.collisionService().contents(point, skip) & c.CONTENTS_WATER != 0;
    try @import("events.zig").sound(world, slots, projections, if (wet) "global/e_wexplodee.wav" else "global/e_explode1.wav", point, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
    (try world.get(entity, data.Transform)).position = point;
    (try world.get(entity, data.Velocity)).linear = @splat(0);
    const effect = try world.get(entity, data.ActorAttack);
    effect.born_ms = now;
    effect.stepped_ms = now;
    effect.attack.meteor = .{ .phase = .impact, .next_ms = now + 500, .scale = @splat(if (state.phase == .stave) @as(f32, 2) else 1), .spin = @splat(0), .damage = 0, .radius = if (state.phase == .stave) 450 else 250, .speed = 0, .normal = normal, .scorch = world_contact };
    try publish(world, entity, projections, now);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var attack = (try world.get(entity, data.ActorAttack)).*;
    const state = &attack.attack.meteor;
    var pose = (try world.get(entity, data.Transform)).*;
    var velocity = (try world.get(entity, data.Velocity)).*;
    const body = (try world.get(entity, data.Body)).*;
    const skip: u16 = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    if (state.phase == .impact) {
        if (now >= attack.born_ms + 500) return life.remove(world, slots, projections, entity);
        return;
    }
    while (attack.stepped_ms < now) {
        const at = @min(now, @min(attack.stepped_ms + 50, state.next_ms));
        const seconds = @as(f32, @floatFromInt(at - attack.stepped_ms)) * 0.001;
        attack.stepped_ms = at;
        if (state.phase != .flare) {
            if (state.phase == .fragment) velocity.linear[2] -= 400 * seconds;
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity.linear, seconds)), .mins = body.mins, .maxs = body.maxs, .slot = skip, .mask = body.collision_mask });
            pose.position = hit.end;
            if (state.phase == .fragment) velocity.linear[2] -= 400 * seconds;
            if (hit.fraction < 1 or hit.start_solid) {
                if (state.phase == .stave or @as(f32, @floatFromInt(state.bounces)) >= state.bounce_max) return impact(world, slots, projections, entity, attack, state.*, pose, velocity.linear, hit.normal, hit.entity == c.ENTITYNUM_WORLD, at);
                state.bounces +|= 1;
                velocity.linear = v.subtract(velocity.linear, v.scale(hit.normal, 1.5 * v.dot(velocity.linear, hit.normal)));
                for (&velocity.linear) |*axis| if (@abs(axis.*) < 0.1) {
                    axis.* = 0;
                };
                pose.position = v.add(pose.position, v.scale(hit.normal, 0.03125));
            }
        }
        if (at < state.next_ms) continue;
        state.next_ms = at + 100;
        if (at > attack.born_ms + (if (state.phase == .flare) @as(i64, 900) else 12000) or (state.phase == .fragment and v.length(velocity.linear) < 10)) return life.remove(world, slots, projections, entity);
        pose.angles = v.add(pose.angles, state.spin);
        if (state.phase == .flare) {
            if (state.scale[0] > 0.8) state.delta = -0.07 else if (state.scale[0] < 0.1) state.delta = 0;
            for (&state.scale) |*axis| axis.* += state.delta;
        } else if (state.phase == .stave and state.scale[0] < 1) {
            for (&state.scale) |*axis| axis.* += 0.05;
            if (state.spin[2] > 5) for (&state.spin) |*axis| {
                axis.* -= 15;
            };
            const speed = v.length(velocity.linear);
            if (speed < state.speed) velocity.linear = v.scale(velocity.linear, if (speed < state.speed * 0.2) @as(f32, 1.18) else 1.35);
        }
    }
    (try world.get(entity, data.ActorAttack)).* = attack;
    (try world.get(entity, data.Transform)).* = pose;
    (try world.get(entity, data.Velocity)).* = velocity;
    try publish(world, entity, projections, now);
}
