// SPDX-License-Identifier: GPL-2.0-or-later
//! Fixed-step position-based articulated bodies. Collision is supplied by the
//! caller; this module owns no renderer, engine, networking or allocation state.
const std = @import("std");
pub const v = @import("vector.zig");
pub const collision = @import("collision.zig");
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
/// Joint ranges in degrees, measured in the torso frame (see `Body.cone`).
const Cone = struct { pitch: [2]f32, spread: [2]f32, upright: bool = false };
/// Thigh: flexion to 120, extension to 25; abduction to 50, adduction to 20.
const hip_cone: Cone = .{ .pitch = .{ -25, 120 }, .spread = .{ -20, 50 } };
/// Upper arm: forward and up past overhead, back to 55; out to the side
/// fully, across the chest to 35.
const shoulder_cone: Cone = .{ .pitch = .{ -55, 200 }, .spread = .{ -35, 90 } };
/// Head on the chest: nod 50 forward, 35 back, lean 30 to either side.
const neck_cone: Cone = .{ .pitch = .{ -35, 50 }, .spread = .{ -30, 30 }, .upright = true };
const trunk_radius: f32 = 6;
/// Share of a step's motion a point keeps after meeting a joint's end stop.
const stop_keep: f32 = 0.5;
/// Overshoot (radians, per side) past a stop in one step that counts as meeting it hard.
const stop_impact: f32 = 0.03;
/// `vector` turned by `angle` radians about the unit `axis` (Rodrigues).
fn rotate(vector: Vec, axis: Vec, angle: f32) Vec {
    const cosine = @cos(angle);
    return v.add(v.add(v.scale(vector, cosine), v.scale(v.cross(axis, vector), @sin(angle))), v.scale(axis, v.dot(axis, vector) * (1 - cosine)));
}
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
    /// Points of a limb that reached the end of its range this step.
    stopped: [count]bool = @splat(false),
    pub fn applyImpulse(self: *Body, kick: Vec, point: Vec) void {
        const magnitude = v.length(kick);
        if (magnitude < 0.001) return;
        const bounded = v.scale(kick, @min(1, 600 / magnitude));
        for (&self.previous, self.points) |*old, position| {
            const separation = v.length(v.subtract(position, point));
            const weight = 0.25 + 0.75 / (1 + separation * separation / (24 * 24));
            old.* = v.subtract(old.*, v.scale(bounded, weight / 120));
        }
        self.sleeping = false;
        self.quiet = 0;
    }
    pub fn init(points: [count]Vec, velocity: Vec, impulse: Vec) Body {
        var result: Body = .{ .points = points, .previous = points, .rest = points };
        for (1..count) |i| result.link(i, parents[i]);
        const core = [_]usize{ 0, 1, 3, 6, 9, 13 };
        for (core, 0..) |a, i| for (core[i + 1 ..]) |b| {
            result.link(a, b);
        };
        // The head rides the chest; the neck cone (not rigid links to the
        // shoulders) bounds how far it nods, tips back or leans aside.
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
        // The bend plane follows the limb, so a living pose already lies in
        // it: the hinge holds from the first step.
        const release = std.math.clamp(self.elapsed / 0.4, 0, 1);
        self.points[b] = v.add(self.points[b], v.scale(v.subtract(desired, self.points[b]), 0.7 * release * release));
        self.distance(a, c, d);
    }
    /// Keep the direction from `joint` to `limb[0]` inside an anatomical cone
    /// of the torso frame: `pitch` about the side axis (0 along the rest axis,
    /// positive toward forward, wrapping past overhead), `spread` toward the
    /// body's own side (positive) or across it (negative). The whole limb
    /// turns about the joint, so the joints further along keep their shape.
    fn cone(self: *Body, joint: usize, limb: []const usize, basis: Frame, side: f32, limits: Cone) void {
        const delta = v.subtract(self.points[limb[0]], self.points[joint]);
        const length = v.length(delta);
        if (length < 0.01) return;
        const axis = v.scale(delta, 1 / length);
        const desired = bound(axis, basis, side, limits) orelse return;
        // A living pose starts inside every range: the limits hold from the
        // first step (unlike the hinge planes, which release gradually).
        const angle = std.math.acos(std.math.clamp(v.dot(axis, desired), -1, 1)) * 0.5;
        var pivot = v.cross(axis, desired);
        if (v.length(pivot) < 0.0001) pivot = basis.left;
        pivot = v.normalize(pivot);
        const origin = self.points[joint];
        // Both sides of the joint turn, by mass: a limb held by the floor
        // rolls the body instead.
        var limb_mass: f32 = 0;
        var total_mass: f32 = 0;
        for (0..count) |i| {
            total_mass += 1 / inverse_mass[i];
            if (std.mem.indexOfScalar(usize, limb, i) != null) limb_mass += 1 / inverse_mass[i];
        }
        const share = limb_mass / total_mass;
        for (0..count) |i| {
            if (i == joint) continue;
            const own = std.mem.indexOfScalar(usize, limb, i) != null;
            const turn = if (own) angle * (1 - share) else -angle * share;
            self.points[i] = v.add(origin, rotate(v.subtract(self.points[i], origin), pivot, turn));
            // Both sides of a stop met hard lose motion to it, so the reaction
            // rolls the body over rather than throwing it. Merely resting on
            // a stop costs nothing, so a later shove still carries the body.
            if (angle > stop_impact) self.stopped[i] = true;
        }
    }
    /// The nearest direction inside `limits` for a limb along `axis`, or
    /// null when it is already inside.
    fn bound(axis: Vec, basis: Frame, side: f32, limits: Cone) ?Vec {
        const rest: f32 = if (limits.upright) 1 else -1;
        const radians = std.math.pi / 180.0;
        var pitch = std.math.atan2(v.dot(axis, basis.forward), rest * v.dot(axis, basis.up)) / radians;
        const spread = std.math.asin(std.math.clamp(v.dot(axis, basis.left) * side, -1, 1)) / radians;
        if (pitch < limits.pitch[0]) pitch += 360;
        var bounded = pitch;
        // Outside the range, return to the nearer bound around the circle.
        if (pitch > limits.pitch[1]) bounded = if (pitch - limits.pitch[1] < limits.pitch[0] + 360 - pitch) limits.pitch[1] else limits.pitch[0];
        const spread_bounded = std.math.clamp(spread, limits.spread[0], limits.spread[1]);
        if (bounded == pitch and spread_bounded == spread) return null;
        const p = bounded * radians;
        const q = spread_bounded * radians;
        return v.normalize(v.add(v.add(v.scale(basis.forward, @sin(p) * @cos(q)), v.scale(basis.left, side * @sin(q))), v.scale(basis.up, rest * @cos(p) * @cos(q))));
    }
    /// The toe stays roughly perpendicular to the shin (ankle flex +-45 degrees).
    fn ankle(self: *Body, knee: usize, foot: usize, toe: usize, basis: Frame) void {
        const shin = v.normalize(v.subtract(self.points[foot], self.points[knee]));
        const toe_vector = v.subtract(self.points[toe], self.points[foot]);
        const toe_length = v.length(v.subtract(self.rest[toe], self.rest[foot]));
        const forward = v.normalize(v.subtract(basis.forward, v.scale(shin, v.dot(basis.forward, shin))));
        if (v.length(forward) < 0.1) return;
        const angle = std.math.clamp(v.dot(v.normalize(toe_vector), shin), -0.707, 0.707);
        const target = v.scale(v.add(v.scale(shin, angle), v.scale(forward, @sqrt(1 - angle * angle))), toe_length);
        self.points[toe] = v.add(self.points[toe], v.scale(v.subtract(target, toe_vector), 0.5));
    }
    /// Limbs cannot pass through the trunk: a capsule from pelvis to chest.
    fn trunk(self: *Body, i: usize) void {
        const a = self.points[0];
        const b = self.points[1];
        const ab = v.subtract(b, a);
        const t = std.math.clamp(v.dot(v.subtract(self.points[i], a), ab) / @max(v.dot(ab, ab), 0.0001), 0, 1);
        const closest = v.add(a, v.scale(ab, t));
        const offset = v.subtract(self.points[i], closest);
        const gap = v.length(offset);
        const minimum = trunk_radius + radii[i];
        if (gap >= minimum) return;
        const out = if (gap > 0.001) v.scale(offset, 1 / gap) else v.normalize(v.subtract(self.points[i], self.points[2]));
        const push = minimum - gap;
        const total = inverse_mass[i] + inverse_mass[0] + inverse_mass[1];
        self.points[i] = v.add(self.points[i], v.scale(out, push * inverse_mass[i] / total));
        const back = v.scale(out, -push / total);
        self.points[0] = v.add(self.points[0], v.scale(back, inverse_mass[0] * (1 - t)));
        self.points[1] = v.add(self.points[1], v.scale(back, inverse_mass[1] * t));
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
            self.stopped = @splat(false);
            // Free motion (momentum and gravity) before any constraint acts:
            // friction holds that back, never a joint's own correction.
            const predicted = self.points;
            var normals: [count]Vec = @splat(@splat(0));
            for (0..8) |iteration| {
                for (self.links[0..self.link_count]) |l| self.distance(l.a, l.b, l.length);
                const basis = frame(self.points);
                // Knees bend so the shin folds behind the thigh, elbows so the
                // forearm folds in front of the upper arm, whatever the limb's
                // direction: the bend plane follows the limb, not the trunk.
                for ([_][3]usize{ .{ 9, 10, 11 }, .{ 13, 14, 15 } }) |leg| {
                    const axis = v.normalize(v.subtract(self.points[leg[2]], self.points[leg[0]]));
                    self.hinge(leg[0], leg[1], leg[2], v.cross(axis, basis.left), 145 * std.math.pi / 180.0);
                }
                for ([_][3]usize{ .{ 3, 4, 5 }, .{ 6, 7, 8 } }, [_]f32{ 1, -1 }) |arm, side| {
                    const axis = v.normalize(v.subtract(self.points[arm[2]], self.points[arm[0]]));
                    self.hinge(arm[0], arm[1], arm[2], v.add(v.cross(basis.left, axis), v.scale(basis.left, side * 0.35)), 150 * std.math.pi / 180.0);
                }
                self.ankle(10, 11, 12, basis);
                self.ankle(14, 15, 16, basis);
                // Hips and shoulders swing within anatomical cones (after the
                // hinges, which rebuild a knee or elbow from its end points);
                // the neck nods and leans within its own.
                self.cone(9, &.{ 10, 11, 12 }, basis, 1, hip_cone);
                self.cone(13, &.{ 14, 15, 16 }, basis, -1, hip_cone);
                self.cone(3, &.{ 4, 5 }, basis, 1, shoulder_cone);
                self.cone(6, &.{ 7, 8 }, basis, -1, shoulder_cone);
                self.cone(1, &.{2}, basis, 1, neck_cone);
                // Hands, elbows and feet stay outside the trunk; a flexed knee
                // may come up to the chest (the hip cone bounds it).
                for ([_]usize{ 4, 5, 7, 8, 11, 12, 15, 16 }) |limb| self.trunk(limb);
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
            for (&self.points, &self.previous, normals, predicted, 0..) |*p, *old, n, free_end, i| {
                var delta = v.subtract(p.*, old.*);
                if (v.length(n) > 0.1) {
                    const normal = v.dot(delta, n);
                    const tangent = v.subtract(delta, v.scale(n, normal));
                    delta = v.scale(tangent, 0.65);
                    // Static friction must cancel tangential displacement too,
                    // otherwise gravity adds fresh slope drift every substep.
                    // Only the free part: a joint limit turning a resting limb
                    // back into range is not held by the floor.
                    const free = v.subtract(free_end, old.*);
                    const free_tangent = v.subtract(free, v.scale(n, v.dot(free, n)));
                    if (n[2] > 0.3 and v.length(tangent) < 5 * dt) {
                        p.* = v.subtract(p.*, free_tangent);
                        delta = @splat(0);
                    }
                    if (normal < 0) delta = v.add(delta, v.scale(n, -normal * 0.05));
                }
                // Contact energy dissipates through the connected body too.
                if (supported >= 4) delta = v.scale(delta, 0.85);
                // A joint's end stop is inelastic, as tissue at the end of a
                // range is: the limb does not spring back off it.
                if (self.stopped[i]) delta = v.scale(delta, stop_keep);
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
test "dead bodies release the living pose gradually and wake on a localized hit" {
    var world: TestWorld = .{};
    var body = Body.init(testPose(), @splat(0), .{ -18, 6, 0 });
    const initial = body.points;
    try body.advance(1.0 / 60.0, world.service(), 0, 1);
    try std.testing.expect(v.length(v.subtract(body.points[0], initial[0])) < 2);
    for (0..600) |_| try body.advance(1.0 / 60.0, world.service(), 0, 1);
    try std.testing.expect(body.sleeping);
    const settled = body.points[0];
    body.applyImpulse(.{ 150, 0, 100 }, body.points[1]);
    try std.testing.expect(!body.sleeping);
    for (0..30) |_| try body.advance(1.0 / 60.0, world.service(), 0, 1);
    try std.testing.expect(body.points[0][0] > settled[0] + 5);
    for (body.links[0..body.link_count]) |l| try std.testing.expect(@abs(v.length(v.subtract(body.points[l.a], body.points[l.b])) - l.length) < 2);
}
/// Degrees by which the limb from `joint` to `child` lies outside its cone.
fn excess(points: [count]Vec, joint: usize, child: usize, side: f32, limits: Cone) f32 {
    const axis = v.normalize(v.subtract(points[child], points[joint]));
    const desired = Body.bound(axis, frame(points), side, limits) orelse return 0;
    return std.math.acos(std.math.clamp(v.dot(axis, desired), -1, 1)) * 180 / std.math.pi;
}
test "settled bodies keep hips, shoulders, neck and knees within anatomical range" {
    for ([_]f32{ 0, 0.2 }) |slope| for (0..8) |heading| for ([_]f32{ 90, 280 }) |speed| {
        var world: TestWorld = .{ .slope = slope };
        const yaw = @as(f32, @floatFromInt(heading)) * std.math.pi / 4;
        const push: Vec = .{ @cos(yaw) * speed, @sin(yaw) * speed, 60 };
        var body = Body.init(testPose(), push, v.scale(push, 0.3));
        for (0..600) |_| try body.advance(1.0 / 60.0, world.service(), 0, 1);
        // A thigh tucked to the chest may pass the hip's flexion bound a little.
        try std.testing.expect(excess(body.points, 9, 10, 1, hip_cone) < 30);
        try std.testing.expect(excess(body.points, 13, 14, -1, hip_cone) < 30);
        try std.testing.expect(excess(body.points, 3, 4, 1, shoulder_cone) < 12);
        try std.testing.expect(excess(body.points, 6, 7, -1, shoulder_cone) < 12);
        try std.testing.expect(excess(body.points, 1, 2, 1, neck_cone) < 5);
        for ([_][3]usize{ .{ 9, 10, 11 }, .{ 13, 14, 15 } }) |leg| {
            const thigh = v.length(v.subtract(body.rest[leg[1]], body.rest[leg[0]]));
            const shin = v.length(v.subtract(body.rest[leg[2]], body.rest[leg[1]]));
            const folded = @sqrt(thigh * thigh + shin * shin + 2 * thigh * shin * @cos(@as(f32, 150 * std.math.pi / 180.0)));
            try std.testing.expect(v.length(v.subtract(body.points[leg[2]], body.points[leg[0]])) > folded);
        }
    };
}
test "joint stops absorb a landing instead of throwing the body back up" {
    for (0..8) |heading| {
        var world: TestWorld = .{};
        const yaw = @as(f32, @floatFromInt(heading)) * std.math.pi / 4;
        var pose = testPose();
        for (&pose) |*p| p.* = v.add(p.*, .{ 0, 0, 24 });
        var body = Body.init(pose, .{ @cos(yaw) * 200, @sin(yaw) * 200, -150 }, .{ @cos(yaw) * 60, @sin(yaw) * 60, 0 });
        var lowest: ?f32 = null;
        var rebound: f32 = 0;
        for (0..600) |_| {
            try body.advance(1.0 / 60.0, world.service(), 0, 1);
            const height = body.points[0][2];
            if (lowest == null and body.contacts == 0) continue;
            lowest = @min(lowest orelse height, height);
            rebound = @max(rebound, height - lowest.?);
        }
        try std.testing.expect(body.sleeping);
        try std.testing.expect(rebound < 12);
    }
}
test "a body dropped in any posture falls freely and comes to rest on the floor" {
    for (0..8) |heading| {
        var world: TestWorld = .{};
        const yaw = @as(f32, @floatFromInt(heading)) * std.math.pi / 4;
        var pose = testPose();
        for (&pose) |*p| p.* = v.add(p.*, .{ 0, 0, 200 });
        var body = Body.init(pose, .{ @cos(yaw) * 120, @sin(yaw) * 120, 0 }, .{ @cos(yaw) * 80, @sin(yaw) * 80, 40 });
        // Free fall from 200 units takes about 0.7 s; joint stops must not
        // brake it (a body that meets its stops in the air would hover).
        for (0..48) |_| try body.advance(1.0 / 60.0, world.service(), 0, 1);
        try std.testing.expect(body.points[0][2] < 120);
        for (0..600) |_| try body.advance(1.0 / 60.0, world.service(), 0, 1);
        try std.testing.expect(body.sleeping);
        var lowest: f32 = std.math.inf(f32);
        for (body.points, 0..) |p, i| lowest = @min(lowest, p[2] - radii[i]);
        try std.testing.expect(lowest < 1);
    }
}
