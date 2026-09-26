// SPDX-License-Identifier: GPL-2.0-or-later
//! Ground locomotion shared by actor policies. Pathfinding never changes position directly.
const std = @import("std");
const data = @import("../domain/components.zig");
const nav = @import("../domain/navigation.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const slide = @import("../domain/slide.zig");

fn floor(position: v.Vec3, body: data.Body, slot: u16) !?v.Vec3 {
    const hit = try engine.collisionService().trace(.{ .start = v.add(position, .{ 0, 0, 18 }), .end = v.add(position, .{ 0, 0, -32 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
    if (hit.start_solid or hit.fraction == 1 or hit.normal[2] < 0.7 or hit.contents & (c.CONTENTS_LAVA | c.CONTENTS_SLIME) != 0) return null;
    return hit.end;
}
fn direct(position: v.Vec3, destination: v.Vec3, body: data.Body, slot: u16) !bool {
    const distance = v.length(v.subtract(destination, position));
    if (distance > 512) return false;
    const count: usize = @intFromFloat(@ceil(distance / 24));
    var previous = position;
    for (0..@max(count, 1)) |i| {
        const fraction = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(@max(count, 1)));
        const point = v.add(position, v.scale(v.subtract(destination, position), fraction));
        const supported = try floor(point, body, slot) orelse return false;
        const hit = try engine.collisionService().trace(.{ .start = v.add(previous, .{ 0, 0, 18 }), .end = v.add(supported, .{ 0, 0, 18 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        if (hit.start_solid or hit.fraction < 1) return false;
        previous = supported;
    }
    return true;
}
fn escape(service: nav.Service, position: v.Vec3, threat: v.Vec3, body: data.Body, slot: u16) !?v.Vec3 {
    const away = @import("../domain/actors.zig").fleeVelocity(position, threat, 1);
    var best: ?v.Vec3 = null;
    var score: f32 = nav.horizontalDistance(position, threat);
    // Prefer increasing distance from danger; retain only supported, reachable destinations.
    for ([_]f32{ 0, 45, -45, 90, -90, 135, -135, 180 }) |degrees| {
        const radians = degrees * std.math.pi / 180;
        const direction: v.Vec3 = .{ away[0] * @cos(radians) - away[1] * @sin(radians), away[0] * @sin(radians) + away[1] * @cos(radians), 0 };
        for ([_]f32{ 192, 96 }) |distance| {
            const candidate = try floor(v.add(position, v.scale(direction, distance)), body, slot) orelse continue;
            const rank = nav.horizontalDistance(candidate, threat) - @abs(degrees) * 0.1;
            if (rank <= score) continue;
            if (!try direct(position, candidate, body, slot) and try service.next(.{ .position = position, .destination = candidate, .slot = slot }) == null) continue;
            best = candidate;
            score = rank;
        }
    }
    return best;
}
pub fn step(actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, service: nav.Service, threat: v.Vec3, speed: f32, slot: u16, now: i64, elapsed: u32) !void {
    const moving = actor.mode == .flee or actor.mode == .chase;
    if (moving and actor.mode == .flee) {
        if (!actor.route.fleeing or now >= actor.escape_until or actor.route.blocked or nav.horizontalDistance(pose.position, actor.route.destination) < 24) {
            const destination = try escape(service, pose.position, threat, body.*, slot);
            actor.route = .{ .destination = destination orelse pose.position, .fleeing = true, .progress_ms = now, .progress_position = pose.position };
            actor.escape_until = now + 800;
        }
    } else if (actor.route.fleeing) actor.route = .{};
    var goal: ?nav.Waypoint = null;
    if (moving) {
        const destination = if (actor.mode == .flee) actor.route.destination else actor.threat_position;
        goal = try actor.route.update(service, .{ .position = pose.position, .destination = destination, .slot = slot }, now);
        // A nearby visible goal needs no detour, but must have a continuous safe floor.
        if (try direct(pose.position, destination, body.*, slot)) goal = .{ .point = destination };
    }
    var motion: slide.State = .{ .position = pose.position, .velocity = velocity.linear };
    var remaining = elapsed;
    while (remaining > 0) {
        const milliseconds = @min(remaining, 50);
        remaining -= milliseconds;
        const delta = @as(f32, @floatFromInt(milliseconds)) * 0.001;
        const ground = try engine.collisionService().trace(.{ .start = motion.position, .end = v.add(motion.position, .{ 0, 0, -0.25 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        var grounded = !ground.start_solid and ground.fraction < 1 and ground.normal[2] >= 0.7;
        actor.ground_entity = if (grounded) ground.entity else c.ENTITYNUM_NONE;
        body.grounded = grounded;
        if (grounded) {
            motion.velocity[0] = 0;
            motion.velocity[1] = 0;
            if (motion.velocity[2] < 0) motion.velocity[2] = 0;
            if (goal) |point| {
                const horizontal = nav.velocity(motion.position, point.point, speed, delta);
                const ahead = v.add(motion.position, v.scale(horizontal, @max(delta, 0.1)));
                if (point.jump or try floor(ahead, body.*, slot) != null) {
                    motion.velocity[0] = horizontal[0];
                    motion.velocity[1] = horizontal[1];
                    if (v.length(horizontal) > 0.1) pose.angles[1] = std.math.atan2(horizontal[1], horizontal[0]) * (180.0 / std.math.pi);
                    if (point.jump and now >= actor.jump_ready_ms) {
                        motion.velocity[2] = 270;
                        grounded = false;
                        body.grounded = false;
                        actor.ground_entity = c.ENTITYNUM_NONE;
                        actor.jump_ready_ms = now + 700;
                    }
                }
            }
        }
        var movement: slide.Context = .{ .service = engine.collisionService(), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask, .delta = delta, .gravity = 800, .ground = if (grounded) ground.normal else null };
        if (actor.mode == .dead) _ = try movement.move(&motion) else try movement.step(&motion);
    }
    pose.position = motion.position;
    velocity.linear = motion.velocity;
}
