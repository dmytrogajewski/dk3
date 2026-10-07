// SPDX-License-Identifier: GPL-2.0-or-later
//! Bounded cosmetic physics for fitted creature rigs, including anchored machines.
const std = @import("std");
const v = @import("vector.zig");
const collision = @import("collision.zig");
pub const capacity = 64;
fn finite(point: v.Vec3) bool {
    for (point) |value| if (!std.math.isFinite(value)) return false;
    return true;
}
pub const Body = struct {
    count: usize,
    points: [capacity]v.Vec3,
    previous: [capacity]v.Vec3,
    rest: [capacity]v.Vec3,
    parents: [capacity]i32,
    radius: [capacity]f32 = @splat(1),
    length: [capacity]f32 = @splat(0),
    anchored: bool,
    accumulator: f32 = 0,
    quiet: f32 = 0,
    contacts: u32 = 0,
    sleeping: bool = false,
    pub fn applyImpulse(self: *Body, kick: v.Vec3, point: v.Vec3) void {
        const magnitude = v.length(kick);
        if (magnitude < 0.001) return;
        const bounded = v.scale(kick, @min(1, 600 / magnitude));
        for (0..self.count) |i| {
            if (self.weight(i) == 0) continue;
            const distance = v.length(v.subtract(self.points[i], point));
            const factor = 0.25 + 0.75 / (1 + distance * distance / (24 * 24));
            self.previous[i] = v.subtract(self.previous[i], v.scale(bounded, factor / 120));
        }
        self.sleeping = false;
        self.quiet = 0;
    }

    pub fn init(count: usize, points: [capacity]v.Vec3, parents: [capacity]i32, velocity: v.Vec3, anchored: bool) !Body {
        if (count < 2 or count > capacity or parents[0] != -1) return error.InvalidCreatureBody;
        var result: Body = .{ .count = count, .points = points, .previous = points, .rest = points, .parents = parents, .anchored = anchored };
        for (0..count) |i| {
            if (!finite(points[i]) or (i > 0 and (parents[i] < 0 or parents[i] >= @as(i32, @intCast(i))))) return error.InvalidCreatureBody;
            if (i > 0) {
                result.length[i] = v.length(v.subtract(points[i], points[@intCast(parents[i])]));
                if (result.length[i] < 0.01) return error.InvalidCreatureBody;
                result.radius[i] = std.math.clamp(result.length[i] * 0.25, 0.5, 6);
            }
            result.previous[i] = v.subtract(points[i], v.scale(velocity, 1.0 / 120.0));
        }
        result.radius[0] = result.radius[1];
        return result;
    }
    fn weight(self: *const Body, i: usize) f32 {
        return if (self.anchored and i == 0) 0 else 1;
    }
    fn constrain(self: *Body, a: usize, b: usize, length: f32) void {
        const delta = v.subtract(self.points[b], self.points[a]);
        const size = v.length(delta);
        const wa, const wb = .{ self.weight(a), self.weight(b) };
        if (size < 0.0001 or wa + wb == 0) return;
        const correction = v.scale(delta, (size - length) / (size * (wa + wb)));
        self.points[a] = v.add(self.points[a], v.scale(correction, wa));
        self.points[b] = v.subtract(self.points[b], v.scale(correction, wb));
    }
    pub fn advance(self: *Body, seconds: f32, service: collision.Collision, slot: u16, mask: u32) !void {
        if (self.sleeping) return;
        self.accumulator += std.math.clamp(seconds, 0, 0.1);
        const dt: f32 = 1.0 / 120.0;
        while (self.accumulator + 0.000001 >= dt) {
            self.accumulator -= dt;
            const before = self.points;
            for (0..self.count) |i| {
                if (self.weight(i) == 0) continue;
                const velocity = v.scale(v.subtract(self.points[i], self.previous[i]), 0.995);
                self.previous[i] = self.points[i];
                self.points[i] = v.add(v.add(self.points[i], velocity), .{ 0, 0, -800 * dt * dt });
            }
            var normals: [capacity]v.Vec3 = @splat(@splat(0));
            for (0..8) |iteration| {
                if (self.anchored) self.points[0] = self.rest[0];
                for (1..self.count) |i| self.constrain(i, @intCast(self.parents[i]), self.length[i]);
                // Bounded chord lengths resist complete limb fold-through while
                // retaining the actual source topology (wings, tails and limbs).
                for (1..self.count) |i| {
                    const parent: usize = @intCast(self.parents[i]);
                    if (self.parents[parent] >= 0) {
                        const grandparent: usize = @intCast(self.parents[parent]);
                        const rest_length = v.length(v.subtract(self.rest[i], self.rest[grandparent]));
                        const current = v.length(v.subtract(self.points[i], self.points[grandparent]));
                        const limit = std.math.clamp(current, rest_length * 0.5, rest_length * 1.5);
                        if (current != limit) self.constrain(i, grandparent, limit);
                    }
                }
                for (0..self.count) |a| for (a + 1..self.count) |b| {
                    if (self.parents[b] == @as(i32, @intCast(a)) or self.parents[a] == @as(i32, @intCast(b))) continue;
                    const radius = self.radius[a] + self.radius[b];
                    if (v.length(v.subtract(self.rest[a], self.rest[b])) < radius * 1.2) continue;
                    if (v.length(v.subtract(self.points[a], self.points[b])) < radius) self.constrain(a, b, radius);
                };
                if (iteration % 4 != 3) continue;
                for (0..self.count) |i| {
                    if (self.weight(i) == 0) continue;
                    const hit = try service.trace(.{ .brushes_only = true, .start = before[i], .end = self.points[i], .mins = @splat(-self.radius[i]), .maxs = @splat(self.radius[i]), .slot = slot, .mask = mask });
                    if (hit.all_solid) {
                        self.points[i] = before[i];
                        self.previous[i] = before[i];
                    } else if (hit.fraction < 1) {
                        self.points[i] = v.add(hit.end, v.scale(hit.normal, 0.03));
                        normals[i] = hit.normal;
                        self.contacts +|= 1;
                    }
                }
            }
            var activity: f32 = 0;
            for (0..self.count) |i| {
                var velocity = v.subtract(self.points[i], self.previous[i]);
                if (v.length(normals[i]) > 0) {
                    const normal_speed = v.dot(velocity, normals[i]);
                    if (normal_speed < 0) velocity = v.subtract(velocity, v.scale(normals[i], normal_speed));
                    velocity = v.scale(velocity, 0.65);
                    self.previous[i] = v.subtract(self.points[i], velocity);
                }
                activity = @max(activity, v.length(velocity) / dt);
            }
            self.quiet = if (activity < 2 and self.contacts > 0) self.quiet + dt else 0;
            if (self.quiet >= 0.8) {
                self.sleeping = true;
                return;
            }
        }
    }
};

test "creature body preserves anchor, connection lengths and world contacts" {
    const Fixture = struct {
        fn trace(_: *anyopaque, request: collision.Request) !collision.Trace {
            var end = request.end;
            const floor = -request.mins[2];
            if (end[2] < floor) {
                end[2] = floor;
                return .{ .fraction = 0.5, .end = end, .normal = .{ 0, 0, 1 } };
            }
            return .{ .fraction = 1, .end = end, .normal = .{ 0, 0, 1 } };
        }
    };
    var context: u8 = 0;
    const service: collision.Collision = .{ .context = &context, .trace_fn = Fixture.trace };
    var points: [capacity]v.Vec3 = @splat(@splat(0));
    points[0] = .{ 0, 0, 12 };
    points[1] = .{ 10, 0, 12 };
    points[2] = .{ 20, 0, 12 };
    var parents: [capacity]i32 = @splat(-1);
    parents[1] = 0;
    parents[2] = 1;
    var anchored = try Body.init(3, points, parents, .{ 0, 0, 0 }, true);
    for (0..120) |_| try anchored.advance(1.0 / 60.0, service, 0, 1);
    try std.testing.expectEqual(points[0], anchored.points[0]);
    try std.testing.expect(anchored.contacts > 0);
    for (1..3) |i| try std.testing.expectApproxEqAbs(@as(f32, 10), v.length(v.subtract(anchored.points[i], anchored.points[i - 1])), 0.3);
    var free = try Body.init(3, points, parents, .{ 5, 0, 0 }, false);
    for (0..120) |_| try free.advance(1.0 / 60.0, service, 0, 1);
    try std.testing.expect(free.points[0][2] < points[0][2]);
    try std.testing.expect(free.contacts > 0);
    for (0..3) |i| try std.testing.expect(finite(free.points[i]));
    parents[2] = 3;
    try std.testing.expectError(error.InvalidCreatureBody, Body.init(3, points, parents, .{ 0, 0, 0 }, false));
}
