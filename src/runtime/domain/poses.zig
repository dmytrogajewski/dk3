// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const v = @import("vector.zig");
pub const Pose = struct { position: v.Vec3 = @splat(0), angles: v.Vec3 = @splat(0) };
pub fn axes(angles: v.Vec3) [3]v.Vec3 {
    const basis = v.basis(angles);
    const left = v.scale(basis.right, -1);
    return .{ basis.forward, left, v.cross(basis.forward, left) };
}
pub fn rotate(vector: v.Vec3, from: v.Vec3, to: v.Vec3) v.Vec3 {
    const before = axes(from);
    const after = axes(to);
    var result: v.Vec3 = @splat(0);
    for (before, after) |old, new| result = v.add(result, v.scale(new, v.dot(vector, old)));
    return result;
}
pub fn point(value: v.Vec3, from: Pose, to: Pose) v.Vec3 {
    return v.add(to.position, rotate(v.add(value, v.scale(from.position, -1)), from.angles, to.angles));
}
pub fn orientation(value: v.Vec3, from: v.Vec3, to: v.Vec3) v.Vec3 {
    if (std.mem.eql(f32, &from, &to)) return value;
    var basis = axes(value);
    for (&basis) |*axis| axis.* = rotate(axis.*, from, to);
    const forward = basis[0];
    const yaw = std.math.atan2(forward[1], forward[0]) * 180 / std.math.pi;
    const pitch = -std.math.atan2(forward[2], @sqrt(forward[0] * forward[0] + forward[1] * forward[1])) * 180 / std.math.pi;
    const roll = std.math.atan2(basis[1][2], basis[2][2]) * 180 / std.math.pi;
    return .{ pitch, yaw, roll };
}
test "attachment pose rotates around parent and composes translation" {
    const from: Pose = .{ .position = .{ 10, 20, 30 } };
    const to: Pose = .{ .position = .{ 40, 50, 60 }, .angles = .{ 0, 90, 0 } };
    const result = point(.{ 12, 20, 30 }, from, to);
    for (result, [_]f32{ 40, 52, 60 }) |actual, expected| try std.testing.expectApproxEqAbs(expected, actual, 0.0001);
    const angles = orientation(.{ 0, 15, 0 }, from.angles, to.angles);
    try std.testing.expectApproxEqAbs(@as(f32, 105), angles[1], 0.0001);
}
