// SPDX-License-Identifier: GPL-2.0-or-later
//! Rocket MP keeps knife, stationary rockets and pursuing attacks distinct.
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc" };
pub const State = struct {
    ready_ms: i64 = 0,
    pursuing: bool = false,
    evade_until: ?i64 = null,
    destination: [3]f32 = @splat(0),
};
pub fn select(distance: f32, roll: f32, stationary: bool) ?u3 {
    if (stationary or distance > 120) return 0;
    if (distance < 120 and roll < 0.5) return 1;
    return null;
}
pub fn chase(ready: bool) u3 {
    return if (ready) 2 else 1;
}
test "rocket MP close attack alternates knife and chase evade" {
    const t = @import("std").testing;
    try t.expectEqual(@as(?u3, 1), select(119, 0.49, false));
    try t.expectEqual(@as(?u3, null), select(119, 0.5, false));
    try t.expectEqual(@as(?u3, 0), select(119, 0.5, true));
    try t.expectEqual(@as(?u3, null), select(120, 0, false));
    try t.expectEqual(@as(u3, 1), chase(false));
}
