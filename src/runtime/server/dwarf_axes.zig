// SPDX-License-Identifier: GPL-2.0-or-later
//! Dwarf axes fly, embed in the world or fall after hitting an entity, then fade.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").dwarf;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, tuning: policy.Tuning, now: i64) !bool {
    const random = try world.get(owner, data.Random);
    const aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, random);
    const owner_slot = (try world.get(owner, data.Binding)).slot;
    const target_position = (try world.get(target, data.Transform)).position;
    const clear = try engine.collisionService().trace(.{ .start = aim.origin, .end = target_position, .mins = @splat(0), .maxs = @splat(0), .slot = owner_slot, .mask = c.MASK_SHOT });
    if (clear.fraction < 1 and clear.entity != (try world.get(target, data.Binding)).slot) return false;
    const amount = tuning.damage + random.next() * tuning.random_damage;
    const entity = try world.create(null, .{
        data.Transform{ .position = aim.origin, .angles = .{ -std.math.atan2(aim.direction[2], @sqrt(aim.direction[0] * aim.direction[0] + aim.direction[1] * aim.direction[1])) * 180 / std.math.pi, std.math.atan2(aim.direction[1], aim.direction[0]) * 180 / std.math.pi, 0 } },
        data.Velocity{ .linear = v.scale(aim.direction, tuning.speed) },
        data.Body{ .mins = @splat(0), .maxs = @splat(0), .collision_mask = c.MASK_SHOT },
        data.DwarfAxe{ .owner = try world.persistentId(owner), .damage = amount, .born_ms = now, .stepped_ms = now },
    });
    try lifecycle.bind(world, slots, projections, entity, policy.axe_model);
    try publish(world, entity, projections, now);
    try @import("events.zig").sound(world, slots, projections, policy.flight_sound, aim.origin, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
    return true;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const state = (try world.get(entity, data.DwarfAxe)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    projection.state.angles2 = @splat(1);
    projection.state.generic1 = policy.axe_tag;
    projection.state.time2 = @intCast((state.contact_ms orelse state.born_ms) + 5000);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = if (state.phase == .flying) @import("../engine/trajectory.zig").linear(pose.angles, .{ 300, 0, 0 }, now) else @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = @splat(0);
    projection.shared.maxs = @splat(0);
    projection.shared.contents = 0;
    projection.shared.ownerNum = if (world.find(state.owner)) |source| (try world.get(source, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |maybe| {
        const entity = maybe orelse continue;
        if (!world.alive(entity)) continue;
        var state = (world.get(entity, data.DwarfAxe) catch continue).*;
        if (now >= (state.contact_ms orelse state.born_ms) + 5000) {
            try lifecycle.remove(world, slots, projections, entity);
            continue;
        }
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        const dt = @as(f32, @floatFromInt(@max(0, now - state.stepped_ms))) * 0.001;
        if (state.phase == .flying) pose.angles[0] = @mod(pose.angles[0] + 300 * dt, 360);
        if (state.phase == .falling) velocity[2] -= 800 * dt;
        if (state.phase != .resting) {
            const skip = if (world.find(state.owner)) |source| (try world.get(source, data.Binding)).slot else c.ENTITYNUM_NONE;
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, dt)), .mins = @splat(0), .maxs = @splat(0), .slot = @intCast(skip), .mask = if (state.phase == .flying) c.MASK_SHOT else c.MASK_SOLID });
            pose.position = hit.end;
            if (hit.sky) {
                try lifecycle.remove(world, slots, projections, entity);
                continue;
            }
            if (hit.fraction < 1 or hit.start_solid) {
                if (state.phase == .flying) {
                    state.contact_ms = now;
                    state.phase = if (hit.entity == c.ENTITYNUM_WORLD) .resting else .falling;
                    if (state.phase == .resting) {
                        pose.angles[0] = 0;
                        pose.position = v.add(pose.position, v.scale(v.basis(pose.angles).forward, -12));
                        pose.angles[0] = 300;
                    } else {
                        if (hit.entity < occupants.len) if (occupants[hit.entity]) |target| {
                            _ = try @import("damage.zig").apply(world, target, @intFromFloat(@ceil(state.damage)), now, .{ .source = state.owner, .attacker_class = "monster_dwarf" });
                            try @import("weapon_damage.zig").shove(world, target, state.owner, velocity, state.damage, now);
                        };
                        pose.angles = .{ 0, 90, 0 };
                    }
                    try @import("events.zig").sound(world, slots, projections, if (state.phase == .resting) policy.wall_sound else policy.flesh_sound, pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
                    velocity = @splat(0);
                } else {
                    velocity = v.subtract(velocity, v.scale(hit.normal, 1.5 * v.dot(velocity, hit.normal)));
                    if (hit.normal[2] > 0.7 and @abs(velocity[2]) < 60) {
                        state.phase = .resting;
                        velocity = @splat(0);
                    }
                    pose.position = v.add(pose.position, v.scale(hit.normal, 0.03125));
                }
            }
        }
        state.stepped_ms = now;
        (try world.get(entity, data.DwarfAxe)).* = state;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = velocity;
        try publish(world, entity, projections, now);
    }
}
