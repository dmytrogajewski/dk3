// SPDX-License-Identifier: GPL-2.0-or-later
//! Row-major affine matrices shared by skeletal presentation and its tests.
const v = @import("vector.zig");
pub const Mat = [12]f32;
pub const identity: Mat = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 };
pub fn point(m: Mat, p: v.Vec3) v.Vec3 {
    return v.add(direction(m, p), position(m));
}
pub fn position(m: Mat) v.Vec3 {
    return .{ m[3], m[7], m[11] };
}
pub fn direction(m: Mat, p: v.Vec3) v.Vec3 {
    return .{ m[0] * p[0] + m[1] * p[1] + m[2] * p[2], m[4] * p[0] + m[5] * p[1] + m[6] * p[2], m[8] * p[0] + m[9] * p[1] + m[10] * p[2] };
}
pub fn translated(m: Mat, p: v.Vec3) Mat {
    var result = m;
    result[3] = p[0];
    result[7] = p[1];
    result[11] = p[2];
    return result;
}
pub fn mul(a: Mat, b: Mat) Mat {
    var out: Mat = undefined;
    for (0..3) |r| for (0..4) |c| {
        out[r * 4 + c] = a[r * 4] * b[c] + a[r * 4 + 1] * b[4 + c] + a[r * 4 + 2] * b[8 + c] + (if (c == 3) a[r * 4 + 3] else @as(f32, 0));
    };
    return out;
}
pub fn inverse(a: Mat) Mat {
    const x: v.Vec3 = .{ a[0], a[4], a[8] };
    const y: v.Vec3 = .{ a[1], a[5], a[9] };
    const z: v.Vec3 = .{ a[2], a[6], a[10] };
    const inv = 1 / v.dot(x, v.cross(y, z));
    const rows = [_]v.Vec3{ v.scale(v.cross(y, z), inv), v.scale(v.cross(z, x), inv), v.scale(v.cross(x, y), inv) };
    var result: Mat = undefined;
    for (rows, 0..) |row, i| {
        @memcpy(result[i * 4 ..][0..3], &row);
        result[i * 4 + 3] = -v.dot(row, position(a));
    }
    return result;
}
pub fn attached(parent_pose: Mat, parent_initial: Mat, child_initial: Mat) Mat {
    return mul(mul(parent_pose, inverse(parent_initial)), child_initial);
}
pub fn basis(x: v.Vec3, y: v.Vec3, z: v.Vec3, p: v.Vec3) Mat {
    return .{ x[0], y[0], z[0], p[0], x[1], y[1], z[1], p[1], x[2], y[2], z[2], p[2] };
}
pub fn quaternion(q: [4]f32, scale: v.Vec3, p: v.Vec3) Mat {
    const x = q[0];
    const y = q[1];
    const z = q[2];
    const w = q[3];
    return basis(v.scale(.{ 1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y) }, scale[0]), v.scale(.{ 2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x) }, scale[1]), v.scale(.{ 2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y) }, scale[2]), p);
}
pub fn swing(from: v.Vec3, to: v.Vec3) Mat {
    const a = v.normalize(from);
    const b = v.normalize(to);
    var axis = v.cross(a, b);
    var w = 1 + v.dot(a, b);
    if (w < 0.0001) {
        axis = v.normalize(v.cross(a, if (@abs(a[2]) < 0.8) @as(v.Vec3, .{ 0, 0, 1 }) else .{ 0, 1, 0 }));
        w = 0;
    }
    const inv = 1 / @sqrt(v.dot(axis, axis) + w * w);
    return quaternion(.{ axis[0] * inv, axis[1] * inv, axis[2] * inv, w * inv }, @splat(1), @splat(0));
}
test "live skin matrices preserve bind pose and rotate limbs without scaling" {
    const std = @import("std");
    const bind = quaternion(.{ 0, 0, @sin(@as(f32, 0.4)), @cos(@as(f32, 0.4)) }, .{ 2, 3, 0.5 }, .{ 11, -9, 40 });
    const vertex: v.Vec3 = .{ 3, 5, -7 };
    try std.testing.expect(v.length(v.subtract(point(mul(bind, inverse(bind)), vertex), vertex)) < 0.0001);
    for ([_]v.Vec3{ .{ -1, 0, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 0 } }) |target| {
        const rotation = swing(.{ 1, 0, 0 }, target);
        try std.testing.expect(v.length(v.subtract(direction(rotation, .{ 1, 0, 0 }), target)) < 0.0001);
        try std.testing.expectApproxEqAbs(v.length(vertex), v.length(direction(rotation, vertex)), 0.0001);
    }
}
test "connected limb anchors retain their local offset under extreme target rotations" {
    const std = @import("std");
    const initial_parent = translated(identity, .{ 11, -9, 40 });
    const initial_child = translated(identity, .{ 11, -9, 25 });
    for ([_]v.Vec3{ .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ -1, 0.2, 0.01 } }) |target| {
        const posed_parent = translated(swing(.{ 0, 0, -1 }, target), .{ 100, -20, 7 });
        const child = attached(posed_parent, initial_parent, initial_child);
        try std.testing.expectApproxEqAbs(@as(f32, 15), v.length(v.subtract(position(child), position(posed_parent))), 0.0001);
        const local = mul(inverse(posed_parent), child);
        try std.testing.expect(v.length(v.subtract(position(local), .{ 0, 0, -15 })) < 0.0001);
    }
}
