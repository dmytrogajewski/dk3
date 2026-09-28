// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed monster projectile lead contract shared by frog and thunder attacks.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const v = @import("../domain/vector.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const Slots = @import("../engine/slots.zig").Slots;
pub fn muzzle(pose: data.Transform, offset: v.Vec3) v.Vec3 {
    const axes = v.basis(pose.angles);
    return v.add(pose.position, v.add(v.scale(axes.right, offset[0]), v.add(v.scale(axes.forward, offset[1]), v.scale(v.cross(axes.right, axes.forward), offset[2]))));
}
pub fn lead(_: *data.World, target: Ref, pose: data.Transform, offset: v.Vec3, random: *data.Random) !struct { origin: v.Vec3, direction: v.Vec3 } {
    const target_pose = (try target.get(data.Transform)).*;
    const target_velocity = (try target.get(data.Velocity)).linear;
    const basis = v.basis(pose.angles);
    const origin = v.add(pose.position, v.add(v.scale(basis.right, offset[0]), v.add(v.scale(basis.forward, offset[1]), v.scale(v.cross(basis.right, basis.forward), offset[2]))));
    // Reference leading follows target view direction, not velocity direction. Its
    // supplied spread and vertical offset are unused in this projectile aim path.
    var lead_angles = target_pose.angles;
    var lead_distance = @max(1, v.length(target_velocity) * 0.1);
    const skill = engine.integer("g_spSkill");
    const roll = random.next();
    const deviation: f32 = if (skill <= 2 and roll > 0.25) 0.5 else if (skill == 3 and roll > 0.25 and lead_distance > 80) 3 else if (skill >= 4 and roll > 0.85 and lead_distance > 100) 6 else 0;
    if (deviation != 0) {
        lead_distance = v.length(target_velocity) * 0.1;
        if (random.next() > 0.5) lead_distance = -lead_distance;
        lead_angles[1] += 30 / deviation * ((random.next() * 2 - 1) * (90 / deviation));
        lead_angles[0] += 5 / deviation * ((random.next() * 2 - 1) * (10 / deviation));
    }
    var destination = v.add(target_pose.position, v.scale(v.basis(lead_angles).forward, lead_distance));
    if (target.get(data.Player) catch null) |player| if (player.ducked) {
        const target_body = (try target.get(data.Body)).*;
        destination[2] -= target_body.maxs[2] - target_body.mins[2];
    };
    return .{ .origin = origin, .direction = v.normalize(v.subtract(destination, origin)) };
}

pub fn clearProjectile(world: *data.World, slots: *Slots, entity: ecs.Entity, target: Ref, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, minimum: f32) !bool {
    const aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, try world.get(entity, data.Random));
    const distance = v.length(v.subtract((try target.get(data.Transform)).position, pose.position));
    const hit = try @import("region_collision.zig").trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, distance)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SHOT });
    if (@import("region_collision.zig").reaches(world, hit, target)) return true;
    if (@import("region_access.zig").victim(world, slots, hit)) |other| {
        if ((other.get(data.Player) catch null) != null) return true;
        if ((other.get(data.Actor) catch null) != null and (other.get(data.Companion) catch null) == null) return false;
    }
    return hit.fraction * distance > (if (minimum == 0) tuning.damage + 32 else minimum);
}

// ITF_NOLEAD aims at the actual target with authored spread and crouch offset.
pub fn direct(_: *data.World, target: Ref, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, random: *data.Random) !struct { origin: v.Vec3, direction: v.Vec3 } {
    const origin = muzzle(pose, tuning.offset);
    const axes = v.basis(pose.angles);
    const right_spread = tuning.spread[0] * random.next() * (if (random.next() < 0.5) @as(f32, -1) else 1);
    const up_spread = tuning.spread[1] * random.next() * (if (random.next() < 0.5) @as(f32, -1) else 1);
    var point = v.add((try target.get(data.Transform)).position, v.add(v.scale(axes.right, right_spread), v.scale(v.cross(axes.right, axes.forward), up_spread)));
    if (target.get(data.Player) catch null) |player| if (player.ducked) {
        const body = (try target.get(data.Body)).*;
        point[2] -= (body.maxs[2] - body.mins[2]) * 0.65;
    };
    return .{ .origin = origin, .direction = v.normalize(v.subtract(point, origin)) };
}
