// SPDX-License-Identifier: GPL-2.0-or-later
//! The damage pulse and its visible spray have distinct lifetimes.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").cryotech;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ?ecs.Entity, pose: data.Transform, offset: v.Vec3, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    const axes = v.basis(pose.angles);
    const origin = v.add(pose.position, v.add(v.scale(axes.right, offset[0]), v.add(v.scale(axes.forward, offset[1]), v.scale(v.cross(axes.right, axes.forward), offset[2]))));
    var direction = axes.forward;
    if (target) |enemy| {
        direction = v.subtract((try world.get(enemy, data.Transform)).position, origin);
        if (world.get(enemy, data.Player) catch null) |player| if (player.ducked) {
            const body = (try world.get(enemy, data.Body)).*;
            direction[2] -= (body.maxs[2] - body.mins[2]) * 0.65;
        };
        direction = v.normalize(direction);
    }
    const amount = definition.damage + (try world.get(owner, data.Random)).next() * definition.random_damage;
    const entity = try world.create(null, .{ data.Transform{ .position = origin, .angles = pose.angles }, data.Velocity{ .linear = v.scale(direction, policy.spray_speed) }, data.Body{ .mins = @splat(0), .maxs = @splat(0), .collision_mask = c.MASK_SHOT }, data.CryoSpray{ .owner = try world.persistentId(owner), .damage = amount, .origin = origin, .angles = pose.angles, .born_ms = now, .stepped_ms = now } });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const state = (try world.get(entity, data.CryoSpray)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = policy.render_tag;
    projection.state.frame = @bitCast(try world.persistentId(entity));
    projection.state.time = @intCast(state.born_ms);
    projection.state.origin2 = state.origin;
    projection.state.angles2 = state.angles;
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, if (state.contacted) @splat(0) else (try world.get(entity, data.Velocity)).linear, now);
    projection.shared.currentOrigin = pose.position;
    projection.shared.contents = 0;
    projection.shared.mins = @splat(0);
    projection.shared.maxs = @splat(0);
    projection.shared.ownerNum = if (world.find(state.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var spray = (world.get(entity, data.CryoSpray) catch continue).*;
        if (!spray.contacted) {
            const until = @min(now, spray.born_ms + policy.spray_lifetime_ms);
            const pose = (try world.get(entity, data.Transform)).*;
            const velocity = (try world.get(entity, data.Velocity)).linear;
            const slot: u16 = if (world.find(spray.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, @as(f32, @floatFromInt(@max(0, until - spray.stepped_ms))) * 0.001)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
            (try world.get(entity, data.Transform)).position = hit.end;
            spray.stepped_ms = until;
            if (hit.fraction < 1 or hit.start_solid) {
                spray.contacted = true;
                if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
                    _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(spray.damage)), now, .{ .source = spray.owner });
                };
            }
            if (until >= spray.born_ms + policy.spray_lifetime_ms) spray.contacted = true;
        }
        if (now >= spray.born_ms + 1500) {
            try lifecycle.remove(world, slots, projections, entity);
            continue;
        }
        (try world.get(entity, data.CryoSpray)).* = spray;
        try publish(world, entity, projections, now);
    }
}
