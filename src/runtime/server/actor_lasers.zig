// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").laser;
const lifecycle = @import("weapon_entities.zig");
pub fn deathbolt(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: Ref, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    const random = try world.get(owner, data.Random);
    const aim = try @import("actor_aim.zig").direct(world, target, pose, tuning, random);
    const amount = tuning.damage + random.next() * tuning.random_damage;
    const entity = try world.create(null, .{
        data.Transform{ .position = aim.origin, .angles = .{ -std.math.atan2(aim.direction[2], @sqrt(aim.direction[0] * aim.direction[0] + aim.direction[1] * aim.direction[1])) * 180 / std.math.pi, std.math.atan2(aim.direction[1], aim.direction[0]) * 180 / std.math.pi, 0 } },
        data.Velocity{ .linear = v.scale(aim.direction, tuning.speed) },
        data.Body{ .mins = @splat(0), .maxs = @splat(0), .collision_mask = c.MASK_SHOT },
        data.ActorLaser{ .owner = try world.persistentId(owner), .damage = amount, .born_ms = now, .stepped_ms = now, .kind = .death, .seed = random.state },
    });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, @import("actor_catalog").deathsphere.bolt_model);
    try publish(world, entity, projections, now);
}
pub const origin = @import("actor_aim.zig").muzzle;
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: Ref, pose: data.Transform, tuning: policy.Tuning, turret: bool, now: i64) !void {
    const start = origin(pose, tuning.offset);
    const basis = v.basis(pose.angles);
    var direction = basis.forward;
    const random = try world.get(owner, data.Random);
    if (!turret) {
        var point = (try target.get(data.Transform)).position;
        point = v.add(point, v.scale(basis.right, (random.next() * 2 - 1) * tuning.spread[0]));
        point = v.add(point, v.scale(v.cross(basis.right, basis.forward), (random.next() * 2 - 1) * tuning.spread[1]));
        if (target.get(data.Player) catch null) |player| if (player.ducked) {
            const body = (try target.get(data.Body)).*;
            point[2] -= (body.maxs[2] - body.mins[2]) * 0.65;
        };
        direction = v.normalize(v.subtract(point, start));
    }
    const amount = tuning.damage + random.next() * tuning.random_damage;
    const entity = try world.create(null, .{ data.Transform{ .position = start, .angles = pose.angles }, data.Velocity{ .linear = v.scale(direction, tuning.speed) }, data.Body{ .mins = @splat(0), .maxs = @splat(0), .collision_mask = c.MASK_SHOT }, data.ActorLaser{ .owner = try world.persistentId(owner), .damage = amount, .born_ms = now, .stepped_ms = now } });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, policy.sprite);
    try publish(world, entity, projections, now);
    try @import("events.zig").sound(world, slots, projections, "global/we_zapa.wav", start, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const state = (try world.get(entity, data.ActorLaser)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = if (state.kind == .death) @import("actor_catalog").deathsphere.bolt_tag else policy.render_tag;
    projection.state.frame = @intFromBool(state.contact_ms != null);
    projection.state.time = @intCast(state.contact_ms orelse state.born_ms);
    projection.state.time2 = @bitCast(try world.persistentId(entity));
    projection.state.modelindex = binding.model;
    projection.state.origin2 = state.normal;
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, if (state.contact_ms != null) @splat(0) else (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
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
        var laser = (world.get(entity, data.ActorLaser) catch continue).*;
        if (now <= laser.stepped_ms) continue;
        var motion = @import("region_motion.zig").Cursor.init(world, laser.owner);
        if (laser.contact_ms) |at| {
            if (now - at >= 800) try lifecycle.remove(world, slots, projections, entity);
            continue;
        }
        const lifetime: i64 = if (laser.kind == .death) 3000 else 10000;
        const end_ms = @min(now, laser.born_ms + lifetime);
        const pose = (try world.get(entity, data.Transform)).*;
        const velocity = (try world.get(entity, data.Velocity)).linear;
        const slot: u16 = if (world.find(laser.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
        const hit = try motion.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, @as(f32, @floatFromInt(@max(0, end_ms - laser.stepped_ms))) * 0.001)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
        (try world.get(entity, data.Transform)).position = hit.end;
        laser.stepped_ms = end_ms;
        if (hit.fraction < 1 or hit.start_solid) {
            if (laser.kind == .death) {
                if (@import("region_access.zig").victim(world, slots, hit)) |victim| if ((victim.get(data.Health) catch null) != null) {
                    try @import("area_damage.zig").apply(world, slots, .{ .world = motion.owner, .owner = laser.owner, .weapon = 0, .origin = hit.end, .damage = laser.damage, .radius = 96, .skip_slot = slot, .self_scale = 0, .inertial = true }, now);
                };
                laser.contact_ms = now;
                laser.normal = if (v.length(hit.normal) > 0) hit.normal else v.scale(v.normalize(velocity), -1);
                (try world.get(entity, data.Transform)).position[2] += 15;
                var random: data.Random = .{ .state = laser.seed };
                try @import("events.zig").soundOwned(world, slots, projections, motion.owner, if (random.next() > 0.8) "global/we_zapa.wav" else "global/we_zapb.wav", hit.end, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
                laser.seed = random.state;
                (try world.get(entity, data.ActorLaser)).* = laser;
                try publish(world, entity, projections, now);
                try motion.finish(world, entity, now);
                continue;
            }
            if (@import("region_access.zig").victim(world, slots, hit)) |victim| if ((victim.get(data.Health) catch null) != null) {
                _ = try @import("damage.zig").apply(victim.world, victim.entity, @intFromFloat(@ceil(laser.damage)), now, .{ .source = laser.owner });
                try lifecycle.remove(world, slots, projections, entity);
                continue;
            };
            laser.contact_ms = now;
            laser.normal = if (v.length(hit.normal) > 0) hit.normal else v.scale(v.normalize(velocity), -1);
            try @import("events.zig").soundOwned(world, slots, projections, motion.owner, "global/we_zapb.wav", hit.end, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
        } else if (now >= laser.born_ms + lifetime) {
            try lifecycle.remove(world, slots, projections, entity);
            continue;
        }
        (try world.get(entity, data.ActorLaser)).* = laser;
        try publish(world, entity, projections, now);
        try motion.finish(world, entity, now);
    }
}
