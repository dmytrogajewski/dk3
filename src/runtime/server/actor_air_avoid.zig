// SPDX-License-Identifier: GPL-2.0-or-later
//! Node-backed horizontal escape used by DeathSphere and hovering wall avoidance.
const std = @import("std");
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub const Result = struct { point: v.Vec3, node: bool };
pub fn choose(actors: *@import("actors.zig").Actors, pose: data.Transform, slot: u16, random: *data.Random, requested: f32, resolution: f32) !Result {
    var distance = @min(requested, 1000);
    var choice: f32 = 0;
    search: while (distance > 50) : (distance -= 50) {
        var yaw = pose.angles[1];
        for ([_]f32{ -90, 0, 90, 180 }) |turn| {
            yaw += turn;
            const point = v.add(pose.position, v.scale(v.basis(.{ pose.angles[0], yaw, pose.angles[2] }).forward, distance));
            const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID | c.CONTENTS_BODY });
            if (hit.fraction == 1) {
                choice = turn;
                break :search;
            }
        }
    }
    // Preserve the callback's pitch-based final projection, not its suggestive name.
    var direction = v.basis(.{ choice + (random.next() * 2 - 1) * resolution, 0, 0 }).forward;
    direction[2] = 0;
    const point = v.add(pose.position, v.scale(direction, distance + 64 * random.next()));
    var result: Result = .{ .point = actors.air_routes.nearest(point) orelse point, .node = actors.air_routes.nearest(point) != null };
    var nearest: ?usize = null;
    var shortest = std.math.inf(f32);
    for (actors.air_routes.nodes, 0..) |node, i| {
        const d = v.length(v.subtract(node.position, point));
        if (d < shortest) {
            shortest = d;
            nearest = i;
        }
    }
    if (nearest) |index| {
        const node = actors.air_routes.nodes[index];
        if (v.length(v.subtract(node.position, pose.position)) < 64) for (node.links) |link| {
            if (link[0] > 64) if (actors.air_routes.indices[@intCast(link[1])]) |next| {
                result.point = actors.air_routes.nodes[next].position;
            };
        };
    }
    return result;
}
