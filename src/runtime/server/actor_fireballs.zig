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
const policy = @import("actor_catalog").fireballs;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: Ref, pose: data.Transform, kind: policy.Kind, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    const random = try world.get(owner, data.Random);
    var aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, random);
    const amount = tuning.damage + random.next() * tuning.random_damage;
    aim.origin = (try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, random)).origin;
    if (kind == .dragon) {
        aim.origin[2] += 96;
        aim.direction = v.normalize(v.subtract((try target.get(data.Transform)).position, aim.origin));
    }
    const entity = try world.create(null, .{ data.Transform{ .position = aim.origin, .angles = .{ -std.math.atan2(aim.direction[2], @sqrt(aim.direction[0] * aim.direction[0] + aim.direction[1] * aim.direction[1])) * 180 / std.math.pi, std.math.atan2(aim.direction[1], aim.direction[0]) * 180 / std.math.pi, 0 } }, data.Velocity{ .linear = v.scale(aim.direction, tuning.speed) }, data.Body{ .mins = @splat(0), .maxs = @splat(0), .collision_mask = c.MASK_SHOT }, data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .fireball = .{ .kind = kind, .damage = amount, .drift_ms = now + 100 } } } });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, policy.model);
    try publish(world, entity, projections, now);
    try @import("events.zig").sound(world, slots, projections, "global/e_firetraveld.wav", pose.position, (try world.get(owner, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const attack = (try world.get(entity, data.ActorAttack)).*;
    const fire = attack.attack.fireball;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    projection.state.generic1 = policy.render_tag;
    projection.state.weapon = @intFromEnum(fire.kind);
    projection.state.angles2 = @splat(policy.scale(fire.kind));
    projection.state.frame = @intCast(@mod(@divTrunc(now - attack.born_ms, 100), 5));
    projection.state.time = @intCast(attack.born_ms);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").linear(pose.angles, .{ 0, 0, 200 }, now);
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
    if (now <= attack.stepped_ms) return;
    var motion = @import("region_motion.zig").Cursor.init(world, attack.owner);
    var fire = attack.attack.fireball;
    var pose = (try world.get(entity, data.Transform)).*;
    const velocity = (try world.get(entity, data.Velocity)).linear;
    const skip: u16 = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    const expiry = attack.born_ms + 5000;
    var impact = false;
    while (attack.stepped_ms < @min(now, expiry)) {
        const at = @min(@min(now, expiry), fire.drift_ms);
        const seconds = @as(f32, @floatFromInt(at - attack.stepped_ms)) * 0.001;
        const hit = try motion.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, seconds)), .mins = @splat(0), .maxs = @splat(0), .slot = skip, .mask = c.MASK_SHOT });
        pose.position = hit.end;
        pose.angles[2] += 200 * seconds;
        attack.stepped_ms = at;
        if (hit.fraction < 1 or hit.start_solid) {
            impact = true;
            break;
        }
        if (at == fire.drift_ms) {
            const drift = try motion.trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 1, 0, 0 }), .mins = @splat(0), .maxs = @splat(0), .slot = skip, .mask = c.MASK_SHOT });
            pose.position = drift.end;
            fire.drift_ms += 100;
            if (drift.fraction < 1 or drift.start_solid) {
                impact = true;
                break;
            }
        }
    }
    if (impact) {
        try @import("scenery.zig").explosionOwned(world, slots, projections, motion.owner, pose.position, 1, now);
        if (policy.pulses(fire.kind) == 5) {
            for ([_]v.Vec3{ .{ 40, 0, 0 }, .{ -40, 0, 0 }, .{ 0, -40, 0 }, .{ 0, 40, 0 } }) |offset| {
                try @import("scenery.zig").explosionOwned(world, slots, projections, motion.owner, v.add(pose.position, offset), 1, now);
                // The extra sprites move, but each damage pulse stays at the orb.
                try blast(world, slots, motion.owner, attack.owner, skip, pose.position, fire.damage * 0.3, now);
            }
            for ([_][]const u8{ "global/e_explodef.wav", "global/e_explodeq.wav", "global/e_exploded.wav" }) |name| try @import("events.zig").soundOwned(world, slots, projections, motion.owner, name, pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
        } else try @import("events.zig").soundOwned(world, slots, projections, motion.owner, "global/e_explodeh.wav", pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
        try blast(world, slots, motion.owner, attack.owner, skip, pose.position, fire.damage, now);
        return lifecycle.remove(world, slots, projections, entity);
    }
    if (now >= expiry) return lifecycle.remove(world, slots, projections, entity);
    attack.attack.fireball = fire;
    (try world.get(entity, data.ActorAttack)).* = attack;
    (try world.get(entity, data.Transform)).* = pose;
    try publish(world, entity, projections, now);
    try motion.finish(world, entity, now);
}
fn blast(world: *data.World, slots: *Slots, owner_world: u32, owner: u32, skip: u16, position: v.Vec3, damage: f32, now: i64) !void {
    try @import("area_damage.zig").apply(world, slots, .{ .world = owner_world, .owner = owner, .weapon = 0, .origin = position, .damage = damage, .radius = 64, .skip_slot = skip, .self_scale = 0 }, now);
}
