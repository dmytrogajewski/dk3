// SPDX-License-Identifier: GPL-2.0-or-later
//! Froginator-owned missile. Player weapon identities and tuning are not involved.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").froginator;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: Ref, pose: data.Transform, tuning: policy.Tuning, now: i64) !void {
    const random = try world.get(owner, data.Random);
    const aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, random);
    const origin = aim.origin;
    const direction = aim.direction;
    const amount = tuning.damage + random.next() * tuning.random_damage;
    const entity = try world.create(null, .{
        data.Transform{ .position = v.add(origin, .{ 0, 0, 10 }), .angles = .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 } },
        data.Velocity{ .linear = v.scale(direction, tuning.speed) },
        data.Body{ .mins = @splat(-3), .maxs = @splat(3), .collision_mask = c.MASK_SHOT },
        data.Lifetime{ .expires_ms = now + 5000 },
        data.FrogSpit{ .owner = try world.persistentId(owner), .damage = amount, .born_ms = now, .stepped_ms = now },
    });
    try lifecycle.bind(world, slots, projections, entity, policy.spit_model);
    try publish(world, entity, projections, now);
    var text: [128]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 frog: id={d} spit={d} damage={d:.2}\n", .{ try world.persistentId(owner), try world.persistentId(entity), amount }));
    try @import("actor_aim.zig").finishLaunch(world, pose.position, entity, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const velocity = (try world.get(entity, data.Velocity)).linear;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    projection.state.angles2 = @splat(0.15);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, velocity, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.mins = @splat(-3);
    projection.shared.maxs = @splat(3);
    projection.shared.contents = 0;
    const owner = (try world.get(entity, data.FrogSpit)).owner;
    projection.shared.ownerNum = if (world.find(owner)) |source| (try world.get(source, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var spit = (world.get(entity, data.FrogSpit) catch continue).*;
        if (now <= spit.stepped_ms) continue;
        var motion = @import("region_motion.zig").Cursor.init(world, spit.owner);
        if (now >= (try world.get(entity, data.Lifetime)).expires_ms) {
            try lifecycle.remove(world, slots, projections, entity);
            continue;
        }
        const pose = (try world.get(entity, data.Transform)).*;
        const velocity = (try world.get(entity, data.Velocity)).linear;
        const owner_slot = if (world.find(spit.owner)) |source| (try world.get(source, data.Binding)).slot else c.ENTITYNUM_NONE;
        const hit = try motion.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, @as(f32, @floatFromInt(@max(0, now - spit.stepped_ms))) * 0.001)), .mins = @splat(-3), .maxs = @splat(3), .slot = @intCast(owner_slot), .mask = c.MASK_SHOT });
        if (hit.fraction < 1 or hit.start_solid) {
            if (@import("region_access.zig").victim(world, slots, hit)) |target| if ((target.get(data.Health) catch null) != null) {
                _ = try @import("weapon_damage.zig").hurt(target.world, target.entity, spit.owner, 0, spit.damage, now, false);
                try @import("weapon_damage.zig").shove(target.world, target.entity, spit.owner, velocity, spit.damage, now);
                if ((target.get(data.Player) catch null) != null) try @import("ailments.zig").apply(target.world, target.entity, .{ .poison = .{ .damage = 1, .duration_ms = 15000, .interval_ms = 3000 } }, spit.owner, 0, now);
                var text: [100]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&text, "dk3 frog: spit={d} contact={d}\n", .{ try world.persistentId(entity), try target.id() }));
            };
            try lifecycle.remove(world, slots, projections, entity);
            continue;
        }
        (try world.get(entity, data.Transform)).position = hit.end;
        spit.stepped_ms = now;
        (try world.get(entity, data.FrogSpit)).* = spit;
        try publish(world, entity, projections, now);
        try motion.finish(world, entity, now);
    }
}
