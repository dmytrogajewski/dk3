// SPDX-License-Identifier: GPL-2.0-or-later
//! Nharre's authored node search, cover test and historical yaw fallback.
const std = @import("std");
const data = @import("../domain/components.zig");
const v = @import("../domain/vector.zig");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/server.zig");
const Routes = @import("air_routes.zig").Routes;
const xy = @import("../domain/navigation.zig").horizontalDistance;
fn nearest(routes: *const Routes, point: v.Vec3) ?usize {
    var best: ?usize = null;
    var distance = std.math.inf(f32);
    for (routes.nodes, 0..) |node, i| {
        const d = v.length(v.subtract(node.position, point));
        if (d < distance) {
            distance = d;
            best = i;
        }
    }
    return best;
}
const Search = struct {
    node: usize,
    depth: u8 = 0,
    distance: f32,
    greatest: f32 = 0,
    best: ?usize = null,
};
fn outward(routes: *const Routes, enemy: v.Vec3, maximum: f32, state: *Search) bool {
    if (state.depth >= 5 or state.distance >= maximum) return true;
    var i: usize = 0;
    // The source traversal retains the child cursor after an unsuccessful
    // descent. Node order and that cursor determine the selected retreat.
    while (i < routes.nodes[state.node].links.len) : (i += 1) {
        const link = routes.nodes[state.node].links[i];
        const next = routes.indices[@intCast(link[1])].?;
        if (routes.nodes[next].links.len > 1) {
            const distance = xy(routes.nodes[next].position, enemy);
            if (distance <= state.distance) continue;
            if (state.distance > state.greatest) {
                state.greatest = state.distance;
                state.best = next;
            }
            const previous = state.distance;
            state.distance = distance;
            state.node = next;
            state.depth += 1;
            if (outward(routes, enemy, maximum, state)) return true;
            state.distance = previous;
            state.depth -= 1;
        } else if (state.distance + xy(routes.nodes[state.node].position, enemy) > maximum) return true;
    }
    return false;
}
pub fn find(routes: *const Routes, pose: data.Transform, body: data.Body, enemy: v.Vec3, slot: u16, enemy_slot: u16, navigation: @import("../domain/navigation.zig").Service, random: *data.Random) !v.Vec3 {
    if (nearest(routes, pose.position)) |start| {
        var search: Search = .{ .node = start, .distance = xy(pose.position, enemy) };
        if (outward(routes, enemy, 400 + v.length(v.subtract(pose.position, enemy)), &search)) if (search.best) |best| return routes.nodes[best].position;
    }
    var hide: ?v.Vec3 = null;
    var minimum: f32 = 768;
    for (routes.nodes) |node| {
        if (node.flags & 0x1000 == 0) continue;
        const distance = v.length(v.subtract(node.position, pose.position));
        if (distance >= minimum) continue;
        if (!(try blocked(enemy, node.position, enemy_slot, c.MASK_PLAYERSOLID))) continue;
        if (try navigation.next(.{ .position = pose.position, .destination = node.position, .slot = slot }) == null) continue;
        const direction = v.normalize(.{ enemy[0] - node.position[0], enemy[1] - node.position[1], 0 });
        const side = v.scale(.{ direction[1], -direction[0], 0 }, (body.maxs[0] - body.mins[0]) * 0.6);
        if (try blocked(enemy, v.add(node.position, side), enemy_slot, c.MASK_SOLID) and try blocked(enemy, v.subtract(node.position, side), enemy_slot, c.MASK_SOLID)) {
            hide = node.position;
            minimum = distance;
        }
    }
    if (hide) |point| return point;
    var distance: f32 = 512;
    var choice: f32 = 0;
    probe: while (distance > 50) : (distance -= 50) {
        var angles = pose.angles;
        for ([_]f32{ -90, 0, 90, 180 }) |turn| {
            angles[1] += turn;
            if (!try blocked(pose.position, v.add(pose.position, v.scale(v.basis(angles).forward, distance)), slot, c.MASK_SOLID | c.CONTENTS_BODY)) {
                choice = turn;
                break :probe;
            }
        }
    }
    // Resolution is an integer in this helper; Nharre passes 0.15, hence zero.
    // Choice is applied to pitch, then Z is removed without renormalization.
    _ = random.next();
    var direction = v.basis(.{ choice, 0, 0 }).forward;
    direction[2] = 0;
    const point = v.add(pose.position, v.scale(direction, distance + random.next() * 64));
    var node = nearest(routes, point) orelse return point;
    if (v.length(v.subtract(routes.nodes[node].position, pose.position)) < 64) {
        var i: usize = 0;
        while (i < routes.nodes[node].links.len) : (i += 1) {
            const link = routes.nodes[node].links[i];
            if (link[0] > 64) node = routes.indices[@intCast(link[1])].?;
        }
    }
    return routes.nodes[node].position;
}
fn blocked(from: v.Vec3, to: v.Vec3, slot: u16, mask: u32) !bool {
    const hit = try engine.collisionService().trace(.{ .start = from, .end = to, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = mask });
    return hit.fraction < 1;
}
