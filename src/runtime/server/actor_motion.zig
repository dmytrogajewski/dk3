// SPDX-License-Identifier: GPL-2.0-or-later
//! Ground locomotion shared by actor policies. Pathfinding never changes position directly.
const std = @import("std");
const data = @import("../domain/components.zig");
const nav = @import("../domain/navigation.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const slide = @import("../domain/slide.zig");
const Collision = @import("../domain/collision.zig").Collision;

fn floorWith(collision: Collision, position: v.Vec3, body: data.Body, slot: u16) !?v.Vec3 {
    const hit = try collision.trace(.{ .start = v.add(position, .{ 0, 0, 18 }), .end = v.add(position, .{ 0, 0, -32 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
    if (hit.start_solid or hit.fraction == 1 or hit.normal[2] < 0.7 or hit.contents & (c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO) != 0) return null;
    return hit.end;
}
pub fn direct(position: v.Vec3, destination: v.Vec3, body: data.Body, slot: u16) !bool {
    return directWith(@import("actor_collision.zig").service(), position, destination, body, slot);
}
fn directWith(collision: Collision, position: v.Vec3, destination: v.Vec3, body: data.Body, slot: u16) !bool {
    const distance = v.length(v.subtract(destination, position));
    if (distance > 512) return false;
    const count: usize = @intFromFloat(@ceil(distance / 24));
    var previous = position;
    for (0..@max(count, 1)) |i| {
        const fraction = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(@max(count, 1)));
        const point = v.add(position, v.scale(v.subtract(destination, position), fraction));
        const supported = try floorWith(collision, point, body, slot) orelse return false;
        const hit = try collision.trace(.{ .start = v.add(previous, .{ 0, 0, 18 }), .end = v.add(supported, .{ 0, 0, 18 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        if (hit.start_solid or hit.fraction < 1) return false;
        previous = supported;
    }
    return true;
}
pub fn escape(service: nav.Service, position: v.Vec3, threat: v.Vec3, body: data.Body, slot: u16) !?v.Vec3 {
    return escapeWith(@import("actor_collision.zig").service(), service, position, threat, body, slot);
}
fn escapeWith(collision: Collision, service: nav.Service, position: v.Vec3, threat: v.Vec3, body: data.Body, slot: u16) !?v.Vec3 {
    const away = @import("../domain/actors.zig").fleeVelocity(position, threat, 1);
    var best: ?v.Vec3 = null;
    var score: f32 = nav.horizontalDistance(position, threat);
    // Prefer increasing distance from danger; retain only supported, reachable destinations.
    for ([_]f32{ 0, 45, -45, 90, -90, 135, -135, 180 }) |degrees| {
        const radians = degrees * std.math.pi / 180;
        const direction: v.Vec3 = .{ away[0] * @cos(radians) - away[1] * @sin(radians), away[0] * @sin(radians) + away[1] * @cos(radians), 0 };
        for ([_]f32{ 192, 96 }) |distance| {
            const candidate = try floorWith(collision, v.add(position, v.scale(direction, distance)), body, slot) orelse continue;
            const rank = nav.horizontalDistance(candidate, threat) - @abs(degrees) * 0.1;
            if (rank <= score) continue;
            if (!try directWith(collision, position, candidate, body, slot) and try service.next(.{ .position = position, .destination = candidate, .slot = slot }) == null) continue;
            best = candidate;
            score = rank;
        }
    }
    return best;
}
pub fn step(actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, service: nav.Service, threat: v.Vec3, speed: f32, slot: u16, now: i64, elapsed: u32) !void {
    return stepWithCollision(@import("actor_collision.zig").service(), actor, pose, body, velocity, service, threat, speed, slot, now, elapsed);
}
fn stepWithCollision(collision: Collision, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, service: nav.Service, threat: v.Vec3, speed: f32, slot: u16, now: i64, elapsed: u32) !void {
    const driven = body.motion_owner != null;
    var moving = !driven and (actor.mode == .flee or actor.mode == .chase);
    const worker = @import("actor_catalog").workers.owns(@import("actor_catalog").entries[actor.definition].classname);
    if (moving and actor.mode == .flee and worker and actor.route.fleeing and (actor.route.blocked or nav.horizontalDistance(pose.position, actor.route.destination) < 24 or now >= actor.panic_until)) {
        actor.worker.stop(now);
        actor.mode = .idle;
        actor.changed_ms = now;
        moving = false;
    }
    if (moving and actor.mode == .flee) {
        if (!actor.route.fleeing or (!worker and now >= actor.escape_until) or actor.route.blocked or nav.horizontalDistance(pose.position, actor.route.destination) < 24) {
            const destination = try escapeWith(collision, service, pose.position, threat, body.*, slot);
            actor.route = .{ .destination = destination orelse pose.position, .fleeing = true, .progress_ms = now, .progress_position = pose.position };
            actor.escape_until = now + 800;
            if (worker and destination == null) {
                actor.worker.stop(now);
                actor.mode = .idle;
                actor.changed_ms = now;
                moving = false;
            }
        }
    } else if (actor.route.fleeing) actor.route = .{};
    var goal: ?nav.Waypoint = null;
    if (moving) {
        const destination = if (actor.mode == .flee) actor.route.destination else actor.threat_position;
        goal = try actor.route.update(service, .{ .position = pose.position, .destination = destination, .slot = slot }, now);
        // A nearby visible goal needs no detour, but must have a continuous safe floor.
        if (try directWith(collision, pose.position, destination, body.*, slot)) goal = .{ .point = destination };
    }
    var motion: slide.State = .{ .position = pose.position, .velocity = velocity.linear };
    var remaining = elapsed;
    while (remaining > 0) {
        const milliseconds = @min(remaining, 50);
        remaining -= milliseconds;
        const delta = @as(f32, @floatFromInt(milliseconds)) * 0.001;
        const ground = try collision.trace(.{ .start = motion.position, .end = v.add(motion.position, .{ 0, 0, -0.25 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        // Match the existing slide/player contract: overclip leaves a small
        // positive separating velocity at rest. Only a real upward departure
        // from the supporting plane should disable ground locomotion.
        const departing = motion.velocity[2] > 0 and v.dot(motion.velocity, ground.normal) > 10;
        var grounded = !departing and !ground.all_solid and !ground.start_solid and ground.fraction < 1 and ground.normal[2] >= 0.7;
        actor.ground_entity = if (grounded) ground.entity else c.ENTITYNUM_NONE;
        body.grounded = grounded;
        if (grounded and !driven) {
            motion.velocity[0] = 0;
            motion.velocity[1] = 0;
            if (motion.velocity[2] < 0) motion.velocity[2] = 0;
            if (goal) |point| {
                const horizontal = nav.velocity(motion.position, point.point, speed, delta);
                const ahead = v.add(motion.position, v.scale(horizontal, @max(delta, 0.1)));
                if (point.jump or try floorWith(collision, ahead, body.*, slot) != null) {
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
        var movement: slide.Context = .{ .service = collision, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask, .delta = delta, .gravity = 800, .ground = if (grounded) ground.normal else null };
        if (actor.mode == .dead) _ = try movement.move(&motion) else try movement.step(&motion);
    }
    pose.position = motion.position;
    velocity.linear = motion.velocity;
}

pub fn sidestep(pose: data.Transform, body: data.Body, slot: u16, roll: f32) !?v.Vec3 {
    return sidestepDistance(pose, body, slot, roll, 96);
}
pub fn sidestepDistance(pose: data.Transform, body: data.Body, slot: u16, roll: f32, requested: f32) !?v.Vec3 {
    const distance = @import("actor_catalog").evasion.distance(requested);
    const right = v.basis(pose.angles).right;
    const side: f32 = if (roll < 0.5) -1 else 1;
    for ([_]f32{ side, -side }) |sign| {
        const destination = v.add(pose.position, v.scale(right, sign * distance));
        const hit = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = destination, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        if (hit.start_solid or hit.fraction < 1) continue;
        const ground = try @import("actor_collision.zig").service().trace(.{ .start = destination, .end = v.add(destination, .{ 0, 0, -32 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        if (ground.start_solid or ground.fraction == 1 or ground.normal[2] < 0.7 or !try direct(pose.position, ground.end, body, slot)) continue;
        return ground.end;
    }
    return null;
}

test "settled ground actors start pursuit despite overclip lift and still jump" {
    const Fixture = struct {
        fn trace(_: *anyopaque, request: @import("../domain/collision.zig").Request) !@import("../domain/collision.zig").Trace {
            const bottom = request.start[2] + request.mins[2];
            const end_bottom = request.end[2] + request.mins[2];
            if (end_bottom < 0.125 and bottom >= 0.1249) {
                const fraction = std.math.clamp((bottom - 0.125) / (bottom - end_bottom), 0, 1);
                return .{ .fraction = fraction, .end = v.add(request.start, v.scale(v.subtract(request.end, request.start), fraction)), .normal = .{ 0, 0, 1 }, .entity = c.ENTITYNUM_WORLD };
            }
            return .{ .fraction = 1, .end = request.end, .normal = @splat(0) };
        }
        fn next(_: *anyopaque, request: nav.Request) !?nav.Waypoint {
            return .{ .point = request.destination };
        }
    };
    var fixture: u8 = 0;
    const collision: Collision = .{ .context = &fixture, .trace_fn = Fixture.trace };
    const navigation: nav.Service = .{ .context = &fixture, .next_fn = Fixture.next };
    var actor: data.Actor = .{ .definition = @import("actor_catalog").find("monster_mishimaguard").? };
    var pose: data.Transform = .{ .position = .{ 0, 0, 24.125 } };
    var body: data.Body = .{ .mins = .{ -16, -16, -24 }, .maxs = .{ 16, 16, 32 }, .collision_mask = c.MASK_PLAYERSOLID };
    // Captured from stationary authored workers in e1m2a.
    var velocity: data.Velocity = .{ .linear = .{ 0, 0, 0.04 } };
    for (0..10) |i| try stepWithCollision(collision, &actor, &pose, &body, &velocity, navigation, @splat(0), 100, 64, @intCast(i * 50), 50);
    // Exercise the actual idle-to-chase motor after real slide settling.
    try std.testing.expect(body.grounded);
    actor.mode = .chase;
    actor.threat_position = .{ 200, 0, 24.125 };
    for (0..20) |i| try stepWithCollision(collision, &actor, &pose, &body, &velocity, navigation, actor.threat_position, 100, 64, @intCast(500 + i * 50), 50);
    try std.testing.expect(pose.position[0] > 90);
    try std.testing.expect(body.grounded);
    try std.testing.expectApproxEqAbs(@as(f32, 24.125), pose.position[2], 0.25);
    velocity.linear = .{ 0, 0, 270 };
    try stepWithCollision(collision, &actor, &pose, &body, &velocity, navigation, actor.threat_position, 100, 64, 1550, 50);
    try std.testing.expect(!body.grounded and pose.position[2] > 30 and velocity.linear[2] > 200);
}
