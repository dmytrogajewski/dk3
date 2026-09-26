// SPDX-License-Identifier: GPL-2.0-or-later
//! Attack geometry and projectile state; collision and entity ownership are adapters.
const std = @import("std");
const v = @import("vector.zig");
pub const Projectile = struct {
    owner: u32,
    weapon: u5,
    damage: f32,
    born_ms: i64,
    stepped_ms: i64,
    bounces: u8 = 0,
};
pub fn eye(position: v.Vec3, height: f32) v.Vec3 {
    return v.add(position, .{ 0, 0, height });
}
pub fn muzzle(origin: v.Vec3, angles: v.Vec3, offset: v.Vec3) v.Vec3 {
    const basis = v.basis(angles);
    return v.add(v.add(origin, v.scale(basis.forward, offset[1])), v.add(v.scale(basis.right, offset[0]), .{ 0, 0, offset[2] - 22 }));
}
pub fn aim(start: v.Vec3, target: v.Vec3, forward: v.Vec3) v.Vec3 {
    const delta = v.add(target, v.scale(start, -1));
    return if (v.dot(delta, forward) > 1) v.normalize(delta) else forward;
}
pub fn reflect(velocity: v.Vec3, normal: v.Vec3, retention: f32) v.Vec3 {
    return v.scale(v.add(velocity, v.scale(normal, -2 * v.dot(velocity, normal))), retention);
}
pub fn radiusDamage(damage: f32, distance: f32, radius: f32, owner: bool, bounced: bool) f32 {
    if (distance >= radius) return 0;
    return damage * (1 - distance * distance / (radius * radius)) * (if (owner and !bounced) @as(f32, 0.5) else 1);
}
test "projectile muzzle cannot reverse aim and radius damage has bounded quadratic falloff" {
    try std.testing.expectEqual(v.Vec3{ 1, 0, 0 }, aim(.{ 10, 0, 0 }, .{ 0, 0, 0 }, .{ 1, 0, 0 }));
    try std.testing.expectEqual(v.Vec3{ -125, 0, 0 }, reflect(.{ 100, 0, 0 }, .{ -1, 0, 0 }, 1.25));
    try std.testing.expectEqual(@as(f32, 50), radiusDamage(100, 0, 64, true, false));
    try std.testing.expectEqual(@as(f32, 75), radiusDamage(100, 32, 64, false, false));
    try std.testing.expectEqual(@as(f32, 0), radiusDamage(100, 65, 64, false, false));
}
