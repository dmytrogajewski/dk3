// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").rotworm;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    const random = try world.get(owner, data.Random);
    const origin = @import("actor_aim.zig").muzzle(pose, tuning.offset);
    const axes = v.basis(pose.angles);
    const right_spread = tuning.spread[0] * random.next() * (if (random.next() < 0.5) @as(f32, -1) else 1);
    const up_spread = tuning.spread[1] * random.next() * (if (random.next() < 0.5) @as(f32, -1) else 1);
    var point = v.add((try world.get(target, data.Transform)).position, v.add(v.scale(axes.right, right_spread), v.scale(v.cross(axes.right, axes.forward), up_spread)));
    if (world.get(target, data.Player) catch null) |player| if (player.ducked) {
        const body = (try world.get(target, data.Body)).*;
        point[2] -= (body.maxs[2] - body.mins[2]) * 0.65;
    };
    const direction = v.normalize(v.subtract(point, origin));
    const start = v.add(origin, .{ 0, 0, 10 });
    const amount = tuning.damage + random.next() * tuning.random_damage;
    const entity = try world.create(null, .{
        data.Transform{ .position = start, .angles = .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 } },
        data.Velocity{ .linear = v.scale(direction, tuning.speed) },
        data.Body{ .mins = @splat(-3), .maxs = @splat(3), .collision_mask = c.MASK_SHOT },
        data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .rotworm_spit = .{ .damage = amount } } },
    });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, policy.spit_model);
    try publish(world, entity, projections, now);
    try @import("events.zig").sound(world, slots, projections, "e3/e_firespitf.wav", pose.position, (try world.get(owner, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const attack = (try world.get(entity, data.ActorAttack)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = policy.spit_tag;
    projection.state.modelindex = binding.model;
    projection.state.frame = 0;
    projection.state.angles2 = @splat(0.1);
    projection.state.time = @intCast(attack.born_ms);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = @splat(0);
    projection.shared.maxs = @splat(0);
    projection.shared.contents = 0;
    projection.shared.ownerNum = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var attack = (try world.get(entity, data.ActorAttack)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const velocity = (try world.get(entity, data.Velocity)).linear;
    const end_ms = @min(now, attack.born_ms + 5000);
    const skip: u16 = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, @as(f32, @floatFromInt(@max(0, end_ms - attack.stepped_ms))) * 0.001)), .mins = @splat(-3), .maxs = @splat(3), .slot = skip, .mask = c.MASK_SHOT });
    if (hit.fraction < 1 or hit.start_solid) {
        if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
            if ((world.get(victim, data.Health) catch null) != null) {
                const amount = attack.attack.rotworm_spit.damage;
                _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(amount)), now, .{ .source = attack.owner, .attacker_class = "monster_rotworm" });
                try @import("weapon_damage.zig").shove(world, victim, attack.owner, velocity, amount, now);
                if ((world.get(victim, data.Player) catch null) != null) try @import("ailments.zig").apply(world, victim, .{ .poison = .{ .damage = 1, .duration_ms = 15000, .interval_ms = 3000 } }, attack.owner, 0, now);
            }
        };
        return lifecycle.remove(world, slots, projections, entity);
    }
    if (now >= attack.born_ms + 5000) return lifecycle.remove(world, slots, projections, entity);
    attack.stepped_ms = end_ms;
    (try world.get(entity, data.ActorAttack)).* = attack;
    (try world.get(entity, data.Transform)).position = hit.end;
    try publish(world, entity, projections, now);
}
