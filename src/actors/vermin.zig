// SPDX-License-Identifier: GPL-2.0-or-later
//! VenomVermin's bite, short leap and accelerating missile.
pub const attacks = [_][]const u8{ "ataka", "runa", "atakc", "atakd" };
pub const State = struct { ready_ms: i64 = 0 };
pub fn select(distance: f32) ?u3 {
    return if (distance <= 40) 0 else if (distance <= 192) 1 else if (distance <= 400) 2 else null;
}
test "Vermin attack bands keep authored boundaries" {
    const t = @import("std").testing;
    try t.expectEqual(@as(?u3, 0), select(40));
    try t.expectEqual(@as(?u3, 1), select(192));
    try t.expectEqual(@as(?u3, 2), select(400));
    try t.expectEqual(@as(?u3, null), select(401));
}
