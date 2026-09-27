// SPDX-License-Identifier: GPL-2.0-or-later
//! Chaingang's six feelers distinguish walls from high/low obstacles.
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn steer(actors: *@import("actors.zig").Actors, pose: data.Transform, body: data.Body, slot: u16, direction: v.Vec3, speed: f32, moving: bool, state: *@import("actor_catalog").chaingang.State, random: *data.Random) !v.Vec3 {
    const distance = @max(32, speed * (if (moving) @as(f32, 0.2) else 0.1));
    const obstacle = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, distance)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
    if (obstacle.fraction == 1) return direction;
    const width = (body.maxs[0] - body.mins[0]) * 0.5;
    const right: v.Vec3 = .{ direction[1], -direction[0], 0 };
    var blocked: [2][3]bool = undefined;
    for ([_]f32{ -1, 1 }, 0..) |side, i| for ([_]f32{ -body.mins[2] + 0.1, 0, body.maxs[2] }, 0..) |height, j| {
        const point = v.add(v.add(pose.position, v.scale(right, side * width)), .{ 0, 0, height });
        const hit = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, v.scale(direction, distance + width * 2)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
        blocked[i][j] = hit.fraction < 1;
    };
    const lower = blocked[0][0] or blocked[1][0];
    const upper = blocked[0][2] or blocked[1][2];
    const left = blocked[0][0] or blocked[0][1] or blocked[0][2];
    const right_blocked = blocked[1][0] or blocked[1][1] or blocked[1][2];
    if (upper and !lower) return if (obstacle.normal[2] < -0.7) v.normalize(.{ direction[0], direction[1], 0 }) else .{ 0, 0, -1 };
    if (lower and !upper) return if (obstacle.normal[2] > 0.7) v.normalize(.{ direction[0], direction[1], 0 }) else .{ 0, 0, 1 };
    state.reflectStrafe();
    if (left != right_blocked) return v.normalize(if (right_blocked) .{ obstacle.normal[1], -obstacle.normal[0], direction[2] } else .{ -obstacle.normal[1], obstacle.normal[0], direction[2] });
    const all = blocked[0][0] and blocked[0][1] and blocked[0][2] and blocked[1][0] and blocked[1][1] and blocked[1][2];
    // The reference's general-obstruction branch writes a global temporary and
    // leaves the requested direction intact. Retain that observable decision.
    if (!all) return direction;
    // Its float .15 argument is passed to an integer resolution parameter (zero).
    const escape = try @import("actor_air_avoid.zig").choose(actors, pose, slot, random, 300, 0);
    if (escape.node) return v.normalize(v.subtract(escape.point, pose.position));
    const tangent: v.Vec3 = if (obstacle.normal[0] == 0 and obstacle.normal[1] == 0) .{ -direction[1], direction[0], 0 } else .{ obstacle.normal[1], -obstacle.normal[0], 0 };
    return v.scale(v.normalize(tangent), if (v.dot(direction, tangent) > 0) @as(f32, 1) else -1);
}
