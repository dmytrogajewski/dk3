// SPDX-License-Identifier: GPL-2.0-or-later
//! Knight attack selection and persistent, class-owned effects.
const std = @import("std");
pub const flame_attacks = [_][]const u8{ "ataka", "atakb" };
// The supplied Knight2 model and event table contain only atakc. Use that
// authored stroke for the close punch too; the reference requests absent ataka.
pub const lightning_attacks = [_][]const u8{ "atakc", "atakc" };
pub const render_tag = 10044;
pub const State = struct {
    sidestep_until: ?i64 = null,
    destination: [3]f32 = @splat(0),
    sword_lit: bool = false,
};
pub fn select(distance: f32) u3 {
    return if (distance <= 80) 0 else 1;
}
pub fn inRange(distance: f32, melee_range: f32, ranged_range: f32, ranged_roll: f32, chase_roll: f32) bool {
    return distance < melee_range or (distance < ranged_range and ranged_roll < 0.6) or (distance > 100 and distance < 250 and chase_roll < 0.6);
}
pub const Weapon = @import("weapon.zig").Tuning;
pub const Bolt = struct {
    born_ms: i64,
    next_ms: i64,
    origin: [3]f32,
    contact: [3]f32,
    active: bool = true,
};
pub const Zap = struct {
    target: u32,
    destination: [3]f32,
    emitted: u2 = 0,
    bolts: [2]?Bolt = @splat(null),
};
test "knights select melee at eighty and admit authored range probabilities" {
    try std.testing.expectEqual(@as(u3, 0), select(80));
    try std.testing.expectEqual(@as(u3, 1), select(81));
    try std.testing.expect(inRange(119, 120, 800, 1, 1));
    try std.testing.expect(!inRange(800, 120, 800, 0, 0));
    try std.testing.expect(inRange(249, 120, 800, 1, 0.59));
}
