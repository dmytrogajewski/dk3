// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").missiles;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, kind: policy.Kind, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    const random = try world.get(owner, data.Random);
    const aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, random);
    var origin = aim.origin;
    if (kind == .battleboar) origin[2] += 15;
    if (kind == .vermin) origin = @import("actor_aim.zig").muzzle(pose, .{ 0, 0, 20 });
    if (kind == .rocketdude) {
        const direction = v.normalize(v.subtract((try world.get(target, data.Transform)).position, pose.position));
        const angles: v.Vec3 = .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi - 65, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi - 55, 0 };
        origin = v.add(pose.position, v.scale(v.basis(angles).forward, 25));
    }
    if (kind == .mp_left or kind == .mp_right) {
        const axes = v.basis(pose.angles);
        origin = v.add(pose.position, v.add(v.scale(axes.right, if (kind == .mp_left) -8 else 12), v.scale(v.cross(axes.right, axes.forward), 30)));
    }
    const divisor: u3 = switch (kind) {
        .battleboar => 1,
        .mp_left, .mp_right => 4,
        else => 7,
    };
    const entity = try world.create(null, .{
        data.Transform{ .position = origin, .angles = if (kind == .vermin or kind == .mp_left or kind == .mp_right) pose.angles else .{ -std.math.atan2(aim.direction[2], @sqrt(aim.direction[0] * aim.direction[0] + aim.direction[1] * aim.direction[1])) * 180 / std.math.pi, std.math.atan2(aim.direction[1], aim.direction[0]) * 180 / std.math.pi, 0 } },
        data.Velocity{ .linear = v.scale(aim.direction, tuning.speed / @as(f32, @floatFromInt(divisor))) },
        data.Body{ .mins = @splat(0), .maxs = @splat(0), .collision_mask = c.MASK_SHOT },
        data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .rocket = .{ .kind = kind, .divisor = divisor, .damage = tuning.damage + random.next() * tuning.random_damage, .speed = tuning.speed, .next_ms = now + (if (kind == .battleboar) @as(i64, 5000) else 10) } } },
    });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, policy.model(kind));
    try publish(world, entity, projections, now);
    try @import("events.zig").sound(world, slots, projections, if (kind == .battleboar) "global/e_firetravelb.wav" else "e4/m_rockgangataka.wav", origin, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const state = (try world.get(entity, data.ActorAttack)).*;
    const rocket = state.attack.rocket;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = policy.render_tag;
    projection.state.modelindex = binding.model;
    projection.state.frame = rocket.frame;
    projection.state.time = @intCast(state.born_ms);
    projection.state.angles2 = @splat(policy.modelScale(rocket.kind));
    projection.state.weapon = @intFromEnum(rocket.kind);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = @splat(0);
    projection.shared.maxs = @splat(0);
    projection.shared.contents = 0;
    projection.shared.ownerNum = if (world.find(state.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.ActorAttack)).*;
    var rocket = state.attack.rocket;
    var pose = (try world.get(entity, data.Transform)).*;
    var velocity = (try world.get(entity, data.Velocity)).linear;
    const skip: u16 = if (world.find(state.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    const until = @min(now, state.born_ms + policy.lifetime(rocket.kind));
    while (state.stepped_ms < until) {
        const at = @min(until, rocket.next_ms);
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, @as(f32, @floatFromInt(at - state.stepped_ms)) * 0.001)), .mins = @splat(0), .maxs = @splat(0), .slot = skip, .mask = c.MASK_SHOT });
        pose.position = hit.end;
        state.stepped_ms = at;
        if (hit.fraction < 1 or hit.start_solid) {
            try @import("area_damage.zig").apply(world, slots, .{ .owner = state.owner, .weapon = 0, .origin = pose.position, .damage = rocket.damage, .radius = 128, .skip_slot = skip, .self_scale = 0 }, now);
            try @import("scenery.zig").explosion(world, slots, projections, pose.position, 1, now);
            try @import("events.zig").sound(world, slots, projections, "global/e_explodeb.wav", pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
            return lifecycle.remove(world, slots, projections, entity);
        }
        if (at == rocket.next_ms) {
            policy.accelerate(&rocket);
            velocity = v.scale(v.normalize(velocity), rocket.speed / @as(f32, @floatFromInt(rocket.divisor)));
        }
    }
    if (now >= state.born_ms + policy.lifetime(rocket.kind)) return lifecycle.remove(world, slots, projections, entity);
    state.attack.rocket = rocket;
    (try world.get(entity, data.ActorAttack)).* = state;
    (try world.get(entity, data.Transform)).* = pose;
    (try world.get(entity, data.Velocity)).linear = velocity;
    try publish(world, entity, projections, now);
}
