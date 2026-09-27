// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").knights;
const lifecycle = @import("weapon_entities.zig");
pub fn zap(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, now: i64) !void {
    const entity = try world.create(null, .{
        data.Transform{ .position = v.add(pose.position, .{ 0, 0, 24 }) },                                                                                                                                                                          data.Velocity{}, data.Body{ .mins = @splat(0), .maxs = @splat(0) },
        data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .knight_zap = .{ .target = try world.persistentId(target), .destination = (try world.get(target, data.Transform)).position } } },
    });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections, now);
    try @import("events.zig").sound(world, slots, projections, "e3/m_wwisplightning.wav", pose.position, (try world.get(owner, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn punch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, pose: data.Transform, now: i64) !void {
    const entity = try world.create(null, .{ pose, data.Velocity{}, data.Body{ .mins = @splat(0), .maxs = @splat(0) }, data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .knight_punch } });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections, now);
    try @import("events.zig").sound(world, slots, projections, "e3/we_wwispcorditec.wav", pose.position, (try world.get(owner, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const state = (try world.get(entity, data.ActorAttack)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = policy.render_tag;
    projection.state.modelindex = binding.model;
    projection.state.time = @intCast(state.born_ms);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.state.angles2 = @splat(0.45);
    projection.state.frame = @intFromEnum(state.attack);
    switch (state.attack) {
        .meteor, .npc_wisp, .wyndrax_zap, .wyndrax_bolt, .rocket, .rotworm_spit, .shaft, .prisoner_rock, .sludge_glob, .gunner_burst, .psyclaw_sphere, .fireball => return error.InvalidKnightAttack,
        .knight_punch => {},
        .knight_zap => |value| {
            projection.state.origin2 = value.destination;
            projection.state.otherEntityNum = 0;
            for (value.bolts, 0..) |maybe, i| if (maybe) |bolt| {
                if (bolt.active) projection.state.otherEntityNum |= @as(i32, 1) << @intCast(i);
                if (i == 0) {
                    projection.state.angles = bolt.origin;
                    projection.state.time2 = @intCast(bolt.born_ms);
                } else {
                    projection.state.angles2 = bolt.origin;
                    projection.state.legsAnim = @intCast(bolt.born_ms);
                }
            };
        },
    }
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.contents = 0;
    projection.shared.mins = @splat(0);
    projection.shared.maxs = @splat(0);
    projection.shared.ownerNum = if (world.find(state.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.ActorAttack)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const skip: u16 = if (world.find(state.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    switch (state.attack) {
        .meteor, .npc_wisp, .wyndrax_zap, .wyndrax_bolt, .rocket, .rotworm_spit, .shaft, .prisoner_rock, .sludge_glob, .gunner_burst, .psyclaw_sphere, .fireball => return error.InvalidKnightAttack,
        .knight_zap => |*value| {
            while (state.stepped_ms + 100 <= @min(now, state.born_ms + 500)) {
                state.stepped_ms += 100;
                const at = state.stepped_ms;
                if (value.emitted < 2) {
                    if (world.find(value.target)) |target| {
                        const point = (try world.get(target, data.Transform)).position;
                        const delta = v.subtract(point, pose.position);
                        const horizontal = @sqrt(delta[0] * delta[0] + delta[1] * delta[1]);
                        const angles: v.Vec3 = .{ -std.math.atan2(delta[2], horizontal) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi - 5, 0 };
                        value.bolts[value.emitted] = .{ .born_ms = at, .next_ms = at + 100, .origin = v.add(v.add(pose.position, v.scale(v.basis(angles).forward, 40)), .{ 0, 0, -40 }), .contact = point };
                    }
                    value.emitted += 1;
                }
                for (&value.bolts) |*maybe| if (maybe.*) |*bolt| {
                    if (!bolt.active or bolt.next_ms > at) continue;
                    // Each child applies its final tick before its expiry/visibility test.
                    try @import("area_damage.zig").apply(world, slots, .{ .owner = state.owner, .weapon = 0, .origin = bolt.contact, .damage = 5, .radius = 90, .skip_slot = skip, .self_scale = 0, .inertial = true }, at);
                    bolt.next_ms += 100;
                    const clear = try engine.collisionService().trace(.{ .start = pose.position, .end = bolt.contact, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
                    if (at >= bolt.born_ms + 250 or clear.fraction < 1) bolt.active = false;
                };
            }
            if (now >= state.born_ms + 550) return lifecycle.remove(world, slots, projections, entity);
        },
        .knight_punch => if (now >= state.born_ms + 500) {
            return lifecycle.remove(world, slots, projections, entity);
        },
    }
    (try world.get(entity, data.Transform)).* = pose;
    (try world.get(entity, data.ActorAttack)).* = state;
    try publish(world, entity, projections, now);
}
