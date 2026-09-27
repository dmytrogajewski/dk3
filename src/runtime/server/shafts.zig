// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").shafts;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, kind: policy.Kind, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    const random = try world.get(owner, data.Random);
    const aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, random);
    const amount = tuning.damage + random.next() * tuning.random_damage;
    const entity = try world.create(null, .{
        data.Transform{ .position = aim.origin, .angles = .{ -std.math.atan2(aim.direction[2], @sqrt(aim.direction[0] * aim.direction[0] + aim.direction[1] * aim.direction[1])) * 180 / std.math.pi, std.math.atan2(aim.direction[1], aim.direction[0]) * 180 / std.math.pi, 0 } },
        data.Velocity{ .linear = v.scale(aim.direction, tuning.speed) },
        data.Body{ .mins = @splat(0), .maxs = @splat(0), .collision_mask = c.MASK_SHOT },
        data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .shaft = .{ .kind = kind, .damage = amount } } },
    });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, policy.model(kind));
    try publish(world, entity, projections, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const attack = (try world.get(entity, data.ActorAttack)).*;
    const shaft = attack.attack.shaft;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = policy.render_tag;
    projection.state.modelindex = binding.model;
    projection.state.angles2 = @splat(if (policy.magic(shaft.kind)) @as(f32, 0.5) else 1);
    projection.state.frame = 0;
    projection.state.time = @intCast(attack.born_ms);
    projection.state.time2 = if (shaft.contact_ms) |at| @intCast(at + 5000) else 0;
    projection.state.weapon = @intFromEnum(shaft.kind);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = if (shaft.kind == .thief and shaft.phase == .flying) @import("../engine/trajectory.zig").linear(pose.angles, .{ 300, 0, 0 }, now) else @import("../engine/trajectory.zig").stationary(pose.angles);
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
    var shaft = attack.attack.shaft;
    var pose = (try world.get(entity, data.Transform)).*;
    var velocity = (try world.get(entity, data.Velocity)).linear;
    const skip: u16 = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    var expiry = if (shaft.contact_ms) |at| at + 5000 else attack.born_ms + policy.flightTime(shaft.kind);
    while (attack.stepped_ms < @min(now, expiry) and shaft.phase != .resting) {
        const at = @min(@min(now, expiry), attack.stepped_ms + 50);
        const seconds = @as(f32, @floatFromInt(at - attack.stepped_ms)) * 0.001;
        if (shaft.kind == .thief and shaft.phase == .flying) pose.angles[0] = @mod(pose.angles[0] + 300 * seconds, 360);
        if (shaft.phase == .falling) velocity[2] -= 800 * seconds;
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, seconds)), .mins = @splat(0), .maxs = @splat(0), .slot = skip, .mask = if (shaft.phase == .flying) c.MASK_SHOT else c.MASK_SOLID });
        pose.position = hit.end;
        attack.stepped_ms = at;
        if (hit.fraction < 1 or hit.start_solid) {
            if (hit.sky and shaft.kind == .thief) return lifecycle.remove(world, slots, projections, entity);
            if (shaft.phase == .flying) {
                if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
                    if ((world.get(victim, data.Health) catch null) != null) {
                        _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(shaft.damage)), now, .{ .source = attack.owner, .attacker_class = switch (shaft.kind) {
                            .centurion => "monster_centurion",
                            .fletcher => "monster_fletcher",
                            .thief => "monster_thief",
                            .harpy => "monster_harpy",
                        } });
                        try @import("weapon_damage.zig").shove(world, victim, attack.owner, velocity, shaft.damage, now);
                    }
                };
                if (policy.magic(shaft.kind)) {
                    if (hit.entity == c.ENTITYNUM_WORLD) try @import("events.zig").sound(world, slots, projections, "global/e_arrowimp.wav", pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
                    return lifecycle.remove(world, slots, projections, entity);
                }
                shaft.contact_ms = at;
                expiry = at + 5000;
                shaft.phase = if (hit.entity == c.ENTITYNUM_WORLD) .resting else .falling;
                if (shaft.phase == .falling) pose.angles = .{ 0, 90, 0 };
                if (shaft.kind == .thief and shaft.phase == .resting) {
                    pose.angles[0] = 0;
                    pose.position = v.add(pose.position, v.scale(v.basis(pose.angles).forward, -12));
                    pose.angles[0] = 300;
                }
                velocity = @splat(0);
                try @import("events.zig").sound(world, slots, projections, if (shaft.phase == .resting) (if (shaft.kind == .thief) @as([]const u8, "global/m_bodyhitc.wav") else "global/m_armorhite.wav") else "global/e_bulfleshc.wav", pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
            } else {
                velocity = v.subtract(velocity, v.scale(hit.normal, 1.5 * v.dot(velocity, hit.normal)));
                if (hit.normal[2] > 0.7 and @abs(velocity[2]) < 60) {
                    shaft.phase = .resting;
                    velocity = @splat(0);
                }
            }
            pose.position = v.add(pose.position, v.scale(hit.normal, 0.03125));
        }
    }
    if (now >= expiry) return lifecycle.remove(world, slots, projections, entity);
    attack.attack.shaft = shaft;
    (try world.get(entity, data.ActorAttack)).* = attack;
    (try world.get(entity, data.Transform)).* = pose;
    (try world.get(entity, data.Velocity)).linear = velocity;
    try publish(world, entity, projections, now);
}
