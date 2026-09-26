// SPDX-License-Identifier: GPL-2.0-or-later
pub const Vec3 = [3]f32;
pub fn add(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
pub fn scale(a: Vec3, factor: f32) Vec3 {
    return .{ a[0] * factor, a[1] * factor, a[2] * factor };
}
pub fn dot(a: Vec3, b: Vec3) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
pub fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
pub fn length(a: Vec3) f32 {
    return @sqrt(dot(a, a));
}
pub fn normalize(a: Vec3) Vec3 {
    const size = length(a);
    return if (size > 0) scale(a, 1 / size) else @splat(0);
}
pub fn clip(a: Vec3, normal: Vec3) Vec3 {
    const into = dot(a, normal);
    const backoff = if (into < 0) into * 1.001 else into / 1.001;
    return add(a, scale(normal, -backoff));
}
pub fn basis(angles: Vec3) struct { forward: Vec3, right: Vec3 } {
    const degrees = @import("std").math.pi / 180.0;
    const yaw = angles[1] * degrees;
    const pitch = angles[0] * degrees;
    const roll = angles[2] * degrees;
    const sy = @sin(yaw);
    const cy = @cos(yaw);
    const sp = @sin(pitch);
    const cp = @cos(pitch);
    const sr = @sin(roll);
    const cr = @cos(roll);
    return .{ .forward = .{ cp * cy, cp * sy, -sp }, .right = .{ -sr * sp * cy + cr * sy, -sr * sp * sy - cr * cy, -sr * cp } };
}
