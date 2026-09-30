// SPDX-License-Identifier: GPL-2.0-or-later
//! Fixed-step position-based articulated bodies. Collision is supplied by the
//! caller; this module owns no renderer, engine, networking or allocation state.
const std = @import("std");
const v = @import("vector.zig");
const collision = @import("collision.zig");
pub const Vec = v.Vec3;
pub const names = [_][:0]const u8{ "pelvis", "chest", "head", "upperarm_l", "forearm_l", "hand_l", "upperarm_r", "forearm_r", "hand_r", "thigh_l", "shin_l", "foot_l", "toe_l", "thigh_r", "shin_r", "foot_r", "toe_r" };
pub const count = names.len;
const parents = [_]usize{ 0, 0, 1, 1, 3, 4, 1, 6, 7, 0, 9, 10, 11, 0, 13, 14, 15 };
pub const radii = [_]f32{ 5, 6, 4, 3, 2.5, 2, 3, 2.5, 2, 4, 3, 2.5, 2, 4, 3, 2.5, 2 };
const inverse_mass = [_]f32{ 0.08, 0.06, 0.2, 0.2, 0.4, 0.6, 0.2, 0.4, 0.6, 0.12, 0.25, 0.4, 0.5, 0.12, 0.25, 0.4, 0.5 };
pub const Frame = struct { forward: Vec, left: Vec, up: Vec };
pub fn frame(points: [count]Vec) Frame {
    const left = v.normalize(v.subtract(points[9], points[13]));
    const up = v.normalize(v.subtract(points[1], points[0]));
    const forward = v.normalize(v.cross(left, up));
    return .{ .forward = forward, .left = v.normalize(v.cross(up, forward)), .up = up };
}
const Link = struct { a: usize, b: usize, length: f32 };
pub const Body = struct {
    points: [count]Vec,
    previous: [count]Vec,
    rest: [count]Vec,
    links: [48]Link = undefined,
    link_count: usize = 0,
    accumulator: f32 = 0,
    elapsed: f32 = 0,
    quiet: f32 = 0,
    sleeping: bool = false,
    contacts: u32 = 0,
    pub fn init(points: [count]Vec, velocity: Vec, impulse: Vec) Body {
        var result: Body = .{ .points = points, .previous = points, .rest = points };
        for (1..count) |i| result.link(i, parents[i]);
        const core = [_]usize{ 0, 1, 3, 6, 9, 13 };
        for (core, 0..) |a, i| for (core[i + 1 ..]) |b| {
            result.link(a, b);
        };
        // Keep the head on the shoulder girdle while allowing a modest neck bend.
        result.link(2, 3);
        result.link(2, 6);
        for (&result.previous, 0..) |*p, i| {
            const kick = v.scale(impulse, if (i < 3) @as(f32, 1) else 0.35);
            p.* = v.subtract(p.*, v.scale(v.add(velocity, kick), 1.0 / 120.0));
        }
        return result;
    }
    fn link(self: *Body, a: usize, b: usize) void {
        for (self.links[0..self.link_count]) |l| if ((l.a == a and l.b == b) or (l.a == b and l.b == a)) return;
        self.links[self.link_count] = .{ .a = a, .b = b, .length = v.length(v.subtract(self.rest[a], self.rest[b])) };
        self.link_count += 1;
    }
    fn distance(self: *Body, a: usize, b: usize, length: f32) void {
        const delta = v.subtract(self.points[b], self.points[a]);
        const size = v.length(delta);
        if (size < 0.0001) return;
        const correction = v.scale(delta, (size - length) / (size * (inverse_mass[a] + inverse_mass[b])));
        self.points[a] = v.add(self.points[a], v.scale(correction, inverse_mass[a]));
        self.points[b] = v.subtract(self.points[b], v.scale(correction, inverse_mass[b]));
    }
    fn hinge(self: *Body, a: usize, b: usize, c: usize, pole: Vec, limit: f32) void {
        const l1 = v.length(v.subtract(self.rest[b], self.rest[a]));
        const l2 = v.length(v.subtract(self.rest[c], self.rest[b]));
        const delta = v.subtract(self.points[c], self.points[a]);
        const d = std.math.clamp(v.length(delta), @sqrt(l1 * l1 + l2 * l2 + 2 * l1 * l2 * @cos(limit)), l1 + l2 - 0.02);
        const axis = v.normalize(delta);
        var bend = v.subtract(pole, v.scale(axis, v.dot(pole, axis)));
        if (v.length(bend) < 0.001) return;
        bend = v.normalize(bend);
        const along = (l1 * l1 - l2 * l2 + d * d) / (2 * d);
        const desired = v.add(self.points[a], v.add(v.scale(axis, along), v.scale(bend, @sqrt(@max(0, l1 * l1 - along * along)))));
        // Project the hinge plane; endpoints are reconciled by the length solve.
        self.points[b] = v.add(self.points[b], v.scale(v.subtract(desired, self.points[b]), 0.7));
        self.distance(a, c, d);
    }
    fn legLimits(self: *Body, hip: usize, knee: usize, foot: usize, toe: usize, side: f32, basis: Frame) void {
        const delta = v.subtract(self.points[foot], self.points[hip]);
        const length = v.length(delta);
        if (length < 0.01) return;
        const axis = v.scale(delta, 1 / length);
        const pitch = std.math.clamp(std.math.atan2(v.dot(axis, basis.forward), -v.dot(axis, basis.up)), -60 * std.math.pi / 180.0, 110 * std.math.pi / 180.0);
        const spread = std.math.clamp(std.math.asin(std.math.clamp(v.dot(axis, basis.left) * side, -1, 1)), -15 * std.math.pi / 180.0, 55 * std.math.pi / 180.0);
        const desired = v.add(v.add(v.scale(basis.forward, @sin(pitch) * @cos(spread)), v.scale(basis.left, side * @sin(spread))), v.scale(basis.up, -@cos(pitch) * @cos(spread)));
        const correction = v.scale(v.subtract(v.scale(desired, length), delta), 0.5);
        self.points[foot] = v.add(self.points[foot], correction);
        self.points[hip] = v.subtract(self.points[hip], v.scale(correction, 0.15));
        const shin = v.normalize(v.subtract(self.points[foot], self.points[knee]));
        const toe_vector = v.subtract(self.points[toe], self.points[foot]);
        const toe_length = v.length(v.subtract(self.rest[toe], self.rest[foot]));
        const forward = v.normalize(v.subtract(basis.forward, v.scale(shin, v.dot(basis.forward, shin))));
        if (v.length(forward) < 0.1) return;
        const angle = std.math.clamp(v.dot(v.normalize(toe_vector), shin), -0.707, 0.707);
        const target = v.scale(v.add(v.scale(shin, angle), v.scale(forward, @sqrt(1 - angle * angle))), toe_length);
        self.points[toe] = v.add(self.points[toe], v.scale(v.subtract(target, toe_vector), 0.5));
    }
    pub fn advance(self: *Body, seconds: f32, service: collision.Collision, slot: u16, mask: u32) !void {
        if (self.sleeping) return;
        self.accumulator += std.math.clamp(seconds, 0, 0.1);
        const dt: f32 = 1.0 / 120.0;
        while (self.accumulator + 0.000001 >= dt) {
            self.accumulator -= dt;
            self.elapsed += dt;
            const before = self.points;
            for (&self.points, &self.previous) |*p, *old| {
                const speed = v.scale(v.subtract(p.*, old.*), 0.996);
                old.* = p.*;
                p.* = v.add(v.add(p.*, speed), .{ 0, 0, -800 * dt * dt });
            }
            var normals: [count]Vec = @splat(@splat(0));
            for (0..8) |iteration| {
                for (self.links[0..self.link_count]) |l| self.distance(l.a, l.b, l.length);
                const basis = frame(self.points);
                self.legLimits(9, 10, 11, 12, 1, basis);
                self.legLimits(13, 14, 15, 16, -1, basis);
                self.hinge(9, 10, 11, basis.forward, 145 * std.math.pi / 180.0);
                self.hinge(13, 14, 15, basis.forward, 145 * std.math.pi / 180.0);
                self.hinge(3, 4, 5, v.subtract(v.scale(basis.left, 0.7), basis.forward), 155 * std.math.pi / 180.0);
                self.hinge(6, 7, 8, v.subtract(v.scale(basis.left, -0.7), basis.forward), 155 * std.math.pi / 180.0);
                // Non-neighbor spheres keep extremities out of the trunk and
                // the opposite leg. Adjacent anatomical volumes overlap by design.
                for (0..count) |a| for (a + 1..count) |b| {
                    const radius = radii[a] + radii[b];
                    if (v.length(v.subtract(self.rest[a], self.rest[b])) < radius + 2) continue;
                    if (v.length(v.subtract(self.points[a], self.points[b])) < radius) self.distance(a, b, radius);
                };
                if (iteration % 4 != 3) continue;
                for (&self.points, 0..) |*p, i| {
                    const hit = try service.trace(.{ .brushes_only = true, .start = before[i], .end = p.*, .mins = @splat(-radii[i]), .maxs = @splat(radii[i]), .slot = slot, .mask = mask });
                    if (hit.all_solid) {
                        p.* = before[i];
                        continue;
                    }
                    if (hit.fraction < 1 and !hit.start_solid) {
                        p.* = v.add(hit.end, v.scale(hit.normal, 0.02));
                        normals[i] = hit.normal;
                        self.contacts += 1;
                    }
                }
            }
            var supported: usize = 0;
            for (normals) |n| if (n[2] > 0.3) {
                supported += 1;
            };
            var maximum: f32 = 0;
            for (&self.points, &self.previous, normals) |*p, *old, n| {
                var delta = v.subtract(p.*, old.*);
                if (v.length(n) > 0.1) {
                    const normal = v.dot(delta, n);
                    const tangent = v.subtract(delta, v.scale(n, normal));
                    delta = v.scale(tangent, 0.65);
                    // Static friction must cancel tangential displacement too,
                    // otherwise gravity adds fresh slope drift every substep.
                    if (n[2] > 0.3 and v.length(tangent) < 5 * dt) {
                        p.* = v.subtract(p.*, tangent);
                        delta = @splat(0);
                    }
                    if (normal < 0) delta = v.add(delta, v.scale(n, -normal * 0.05));
                }
                // Contact energy dissipates through the connected body too.
                if (supported >= 4) delta = v.scale(delta, 0.85);
                old.* = v.subtract(p.*, delta);
                maximum = @max(maximum, v.length(delta) / dt);
            }
            self.quiet = if (maximum < 5 and supported >= 3) self.quiet + dt else 0;
            if (self.quiet > 0.6) {
                self.sleeping = true;
                break;
            }
        }
    }
};

const TestWorld = struct {
    slope: f32 = 0,
    stairs: bool = false,
    fn trace(raw: *anyopaque, request: collision.Request) !collision.Trace {
        const self: *TestWorld = @ptrCast(@alignCast(raw));
        if (self.stairs) {
            var best: collision.Trace = .{ .fraction = 1, .end = request.end, .normal = .{ 0, 0, 1 } };
            // Descending eight-unit treads, with vertical risers and a landing.
            for ([_]Vec{ .{ -16, -1000, -100 }, .{ -32, -1000, -100 }, .{ -1000, -1000, -100 } }, [_]Vec{ .{ 1000, 1000, 0 }, .{ 1000, 1000, -8 }, .{ 1000, 1000, -24 } }) |mins, maxs| {
                var enter: f32 = -1;
                var leave: f32 = 1;
                var normal: Vec = @splat(0);
                for (0..3) |axis| {
                    const lo = mins[axis] - request.maxs[axis];
                    const hi = maxs[axis] - request.mins[axis];
                    const delta = request.end[axis] - request.start[axis];
                    if (@abs(delta) < 0.000001) {
                        if (request.start[axis] < lo or request.start[axis] > hi) {
                            leave = -2;
                            break;
                        }
                        continue;
                    }
                    const a = (lo - request.start[axis]) / delta;
                    const b = (hi - request.start[axis]) / delta;
                    if (@min(a, b) > enter) {
                        enter = @min(a, b);
                        normal = @splat(0);
                        normal[axis] = if (delta > 0) -1 else 1;
                    }
                    leave = @min(leave, @max(a, b));
                }
                if (enter >= 0 and enter <= leave and enter < best.fraction) best = .{ .fraction = enter, .end = v.add(request.start, v.scale(v.subtract(request.end, request.start), enter)), .normal = normal };
            }
            return best;
        }
        const n = v.normalize(.{ -self.slope, 0, 1 });
        const extent = @abs(n[0]) * request.maxs[0] + n[2] * request.maxs[2];
        const start = v.dot(n, request.start) - extent;
        const end = v.dot(n, request.end) - extent;
        if (end >= 0) return .{ .fraction = 1, .end = request.end, .normal = n };
        const fraction = if (start > 0) start / (start - end) else 0;
        return .{ .fraction = fraction, .end = v.add(request.start, v.scale(v.subtract(request.end, request.start), fraction)), .normal = n };
    }
    fn service(self: *TestWorld) collision.Collision {
        return .{ .context = self, .trace_fn = trace };
    }
};
fn testPose() [count]Vec {
    return .{ .{ 0, 0, 32 }, .{ 0, 0, 45 }, .{ 0, 0, 55 }, .{ 0, 8, 46 }, .{ 0, 12, 37 }, .{ 2, 14, 30 }, .{ 0, -8, 46 }, .{ 0, -12, 37 }, .{ 2, -14, 30 }, .{ 0, 4, 31 }, .{ 0, 6, 20 }, .{ 0, 8, 4 }, .{ 6, 8, 3 }, .{ 0, -4, 31 }, .{ 0, -6, 20 }, .{ 0, -8, 4 }, .{ 6, -8, 3 } };
}
test "physical death falls, collides and preserves connected limbs on floor and slope" {
    for ([_]f32{ 0, 0.2 }) |slope| {
        var world: TestWorld = .{ .slope = slope };
        var body = Body.init(testPose(), .{ 10, 0, 0 }, .{ -42, 13, 0 });
        for (0..360) |_| try body.advance(1.0 / 60.0, world.service(), 0, 1);
        std.debug.print("slope={d} pelvis={any} sleeping={} contacts={d}\n", .{ slope, body.points[0], body.sleeping, body.contacts });
        try std.testing.expect(body.contacts > 0);
        try std.testing.expect(body.sleeping);
        try std.testing.expect(body.points[0][2] < 22);
        const n = v.normalize(.{ -slope, 0, 1 });
        for (body.points, 0..) |p, i| {
            for (p) |value| try std.testing.expect(std.math.isFinite(value));
            try std.testing.expect(v.dot(n, p) >= radii[i] * (@abs(n[0]) + n[2]) - 0.1);
        }
        for (body.links[0..body.link_count]) |link_value| try std.testing.expect(@abs(v.length(v.subtract(body.points[link_value.a], body.points[link_value.b])) - link_value.length) < 2);
    }
}
test "physical body falls down stair treads without penetrating landing" {
    var world: TestWorld = .{ .stairs = true };
    var pose = testPose();
    for (&pose) |*p| p.* = v.add(p.*, .{ -10, 0, 12 });
    var body = Body.init(pose, .{ -180, 0, 0 }, .{ -42, 13, 0 });
    for (0..720) |_| try body.advance(1.0 / 60.0, world.service(), 0, 1);
    try std.testing.expect(body.contacts > 0);
    try std.testing.expect(body.points[0][0] < -32);
    try std.testing.expect(body.points[0][2] < 0);
    for (body.points, 0..) |p, i| {
        const height: f32 = if (p[0] + radii[i] > -16) 0 else if (p[0] + radii[i] > -32) -8 else -24;
        try std.testing.expect(p[2] >= height + radii[i] - 0.1);
    }
    for (body.links[0..body.link_count]) |l| try std.testing.expect(@abs(v.length(v.subtract(body.points[l.a], body.points[l.b])) - l.length) < 2);
}
test "ragdoll fixed steps agree across presentation cadence" {
    var world: TestWorld = .{};
    var a = Body.init(testPose(), .{ 20, 0, 0 }, .{ -42, 13, 0 });
    var b = a;
    for (0..180) |_| try a.advance(1.0 / 60.0, world.service(), 0, 1);
    for (0..90) |_| try b.advance(1.0 / 30.0, world.service(), 0, 1);
    for (a.points, b.points) |x, y| try std.testing.expect(v.length(v.subtract(x, y)) < 0.01);
}
