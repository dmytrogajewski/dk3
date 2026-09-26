// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared timed-inventory policy; adapters own snapshot fields and notifications.
const std = @import("std");
pub const maximum_ms: i64 = 3600000;
pub fn extend(current: i64, now: i64, lifetime: f32) !?i64 {
    if (!std.math.isFinite(lifetime) or lifetime <= 0) return error.InvalidGasLifetime;
    const duration: i64 = @intFromFloat(@min(lifetime, 3600) * 1000);
    if (duration <= 0) return error.InvalidGasLifetime;
    const remaining = @max(0, current - now);
    if (remaining >= maximum_ms) return null;
    return now + remaining + @min(duration, maximum_ms - remaining);
}
/// null requests expiration, including death. Paused inventory retains remaining time.
pub fn advance(current: i64, now: i64, elapsed: i64, healthy: bool, paused: bool) ?i64 {
    if (!healthy) return null;
    const deadline = current + if (paused and current > 0) elapsed else 0;
    return if (deadline > now) deadline else null;
}
test "Gas Hands duration validation, saturation, freeze and death" {
    try std.testing.expectError(error.InvalidGasLifetime, extend(0, 10, 0));
    try std.testing.expectEqual(@as(?i64, 3600010), try extend(0, 10, 7200));
    try std.testing.expectEqual(@as(?i64, null), try extend(3600010, 10, 1));
    try std.testing.expectEqual(@as(?i64, 1050), advance(1000, 1000, 50, true, true));
    try std.testing.expectEqual(@as(?i64, null), advance(1000, 1000, 50, true, false));
    try std.testing.expectEqual(@as(?i64, null), advance(1000, 500, 50, false, true));
}
