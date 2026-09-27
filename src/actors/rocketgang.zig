// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct { selected: u1 = 1, ready_ms: i64 = 0 };
pub fn select(distance: f32) u1 {
    return @intFromBool(distance >= 500);
}
test "gang kneels at five hundred units" {
    const t = @import("std").testing;
    try t.expectEqual(@as(u1, 0), select(499));
    try t.expectEqual(@as(u1, 1), select(500));
}
