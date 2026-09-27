// SPDX-License-Identifier: GPL-2.0-or-later
//! Amphibious hull movement; individual actors own their attack and animation state.
const std = @import("std");
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn level(point: v.Vec3, body: data.Body, slot: u16) !u2 {
    var result: u2 = 0;
    for ([_]f32{ body.mins[2] + 1, 0, body.maxs[2] - 1 }) |height| {
        if (try engine.collisionService().contents(v.add(point, .{ 0, 0, height }), slot) & c.MASK_WATER == 0) break;
        result += 1;
    }
    return result;
}
pub fn move(routes: *const @import("air_routes.zig").Routes, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, speed: f32, slot: u16, elapsed: u32) !u2 {
    if (actor.mode == .chase) {
        if (try routes.next(pose.position, actor.threat_position, body.*, slot)) |destination| {
            velocity.linear = v.scale(v.normalize(v.subtract(destination, pose.position)), speed);
            const delta = velocity.linear;
            pose.angles = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
        } else velocity.linear = @splat(0);
    } else velocity.linear = @splat(0);
    var motion: @import("../domain/slide.zig").State = .{ .position = pose.position, .velocity = velocity.linear };
    var remaining = elapsed;
    var water = try level(motion.position, body.*, slot);
    while (remaining > 0) {
        const slice = @min(50, remaining);
        remaining -= slice;
        water = try level(motion.position, body.*, slot);
        const floor = try engine.collisionService().trace(.{ .start = motion.position, .end = v.add(motion.position, .{ 0, 0, -0.25 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        body.grounded = !floor.start_solid and floor.fraction < 1 and floor.normal[2] >= 0.7;
        actor.ground_entity = if (body.grounded) floor.entity else c.ENTITYNUM_NONE;
        var context: @import("../domain/slide.zig").Context = .{ .service = engine.collisionService(), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask, .delta = @as(f32, @floatFromInt(slice)) * 0.001, .gravity = if (water == 3 or body.grounded) 0 else 800 };
        _ = try context.move(&motion);
    }
    pose.position = motion.position;
    velocity.linear = motion.velocity;
    return water;
}
