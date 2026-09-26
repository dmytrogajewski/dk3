// SPDX-License-Identifier: GPL-2.0-or-later
//! Progression and effective attributes shared by simulation and prediction.
const std = @import("std");
pub fn experienceThreshold(level: i32) i32 {
    if (level <= 0) return 0;
    const previous = level - 1;
    if (previous < 5) return @as(i32, 500) << @intCast(previous);
    if (previous < 8) return (previous - 2) * 4000;
    if (previous < 24) return (previous - 3) * 5000;
    return 110000;
}
pub fn attribute(base: i32, until: i64, now: i64) i32 {
    return @min(base + @as(i32, @intFromBool(until > now)), 5);
}
pub fn movementFactor(level: i32) f32 {
    return 1 + 0.08 * @as(f32, @floatFromInt(level));
}
pub fn powerFactor(level: i32) f32 {
    return 1 + 0.3 * @as(f32, @floatFromInt(level));
}
test "progression thresholds and boosts preserve authored steps" {
    try std.testing.expectEqual(@as(i32, 500), experienceThreshold(1));
    try std.testing.expectEqual(@as(i32, 16000), experienceThreshold(7));
    try std.testing.expectEqual(@as(i32, 100000), experienceThreshold(24));
    try std.testing.expectEqual(@as(i32, 110000), experienceThreshold(25));
    try std.testing.expectEqual(@as(i32, 5), attribute(5, 100, 0));
    try std.testing.expectEqual(@as(i32, 2), attribute(2, 100, 100));
}

pub fn ringDamage(mask: u32, attacker_class: []const u8, amount: i32) i32 {
    inline for (.{ .{ 16, "monster_stavros" }, .{ 32, "monster_wyndrax" }, .{ 64, "monster_nharre" } }) |rule| {
        if (mask & rule[0] != 0 and std.ascii.eqlIgnoreCase(attacker_class, rule[1])) return @intCast(@divTrunc(@as(i64, amount) + 3, 4));
    }
    return amount;
}
