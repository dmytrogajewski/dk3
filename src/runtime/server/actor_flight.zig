// SPDX-License-Identifier: GPL-2.0-or-later
//! Collision movement shared by combat flight and authored actor paths.
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
pub fn bounce(pose: *data.Transform, body: data.Body, velocity: *data.Velocity, slot: u16, elapsed: u32, gravity: f32, elasticity: f32, settle: bool) !void {
    const v = @import("../domain/vector.zig");
    var remaining = elapsed;
    while (remaining > 0) {
        const slice = @min(remaining, 50);
        remaining -= slice;
        const delta = @as(f32, @floatFromInt(slice)) * 0.001;
        velocity.linear[2] -= gravity * 0.5 * delta;
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity.linear, delta)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        pose.position = hit.end;
        velocity.linear[2] -= gravity * 0.5 * delta;
        if (hit.fraction < 1 or hit.start_solid) {
            velocity.linear = v.scale(v.subtract(velocity.linear, v.scale(hit.normal, 2 * v.dot(velocity.linear, hit.normal))), elasticity);
            if (settle and hit.normal[2] > 0.7 and @abs(velocity.linear[2]) < 60) velocity.linear = @splat(0);
            pose.position = v.add(pose.position, v.scale(hit.normal, 0.03125));
        }
    }
}
pub fn roomHeight(point: data.Vec3, slot: u16, distance: f32) !f32 {
    const c = @import("../engine/abi.zig").c;
    const v = @import("../domain/vector.zig");
    var height: f32 = 0;
    for ([_]f32{ distance, -distance }) |offset| {
        const hit = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, offset }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = if (offset > 0) c.MASK_SOLID else c.MASK_SOLID | c.CONTENTS_BODY });
        height += hit.fraction * distance;
    }
    return height;
}
pub fn liquidBelow(point: data.Vec3, slot: u16, resolution: u8) !bool {
    const c = @import("../engine/abi.zig").c;
    const v = @import("../domain/vector.zig");
    for (1..resolution) |i| {
        const end = v.add(point, .{ 0, 0, -100 * @as(f32, @floatFromInt(i)) });
        const liquid = try engine.collisionService().trace(.{ .start = point, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_WATER });
        if (liquid.fraction < 1 or liquid.start_solid) return true;
        const floor = try engine.collisionService().trace(.{ .start = point, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
        if (floor.fraction < 1) return false;
    }
    return true;
}
pub fn move(pose: *data.Transform, body: data.Body, velocity: *data.Velocity, slot: u16, elapsed: u32) !void {
    var motion: @import("../domain/slide.zig").State = .{ .position = pose.position, .velocity = velocity.linear };
    var remaining = elapsed;
    while (remaining > 0) {
        const slice = @min(remaining, 50);
        remaining -= slice;
        var context: @import("../domain/slide.zig").Context = .{ .service = engine.collisionService(), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask, .delta = @as(f32, @floatFromInt(slice)) * 0.001, .gravity = 0 };
        _ = try context.move(&motion);
    }
    pose.position = motion.position;
    velocity.linear = motion.velocity;
}

/// Smooth velocity turning used by the authored swooping fliers.
pub fn steer(pose: *data.Transform, velocity: *data.Velocity, destination: data.Vec3, speed: f32, turn: f32) void {
    const std = @import("std");
    const v = @import("../domain/vector.zig");
    const goal = v.subtract(destination, pose.position);
    const distance = v.length(goal);
    if (distance < 0.001) {
        velocity.linear = @splat(0);
        return;
    }
    const old = velocity.linear;
    const weight = turn + (1.05 - turn) * std.math.pi * speed * 0.1 / distance;
    const desired = if (weight < 1) v.add(v.scale(old, 1 - weight), v.scale(goal, weight)) else goal;
    velocity.linear = v.scale(v.normalize(desired), speed);
    const direction = v.normalize(velocity.linear);
    const yaw = std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi;
    const previous = std.math.atan2(old[1], old[0]) * 180 / std.math.pi;
    const yaw_change = @mod(yaw - previous + 180, 360) - 180;
    const roll = std.math.clamp(yaw_change * 2.75, -45, 45);
    if (@abs(roll - pose.angles[2]) > 5) pose.angles[2] += if (roll > pose.angles[2]) @as(f32, 5) else -5;
    pose.angles[0] = -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi;
    pose.angles[1] = yaw;
}
