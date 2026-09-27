// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct { selected: u1 = 1, flashed: bool = false };
pub const flash_tag = 10010;
pub fn select(distance: f32, roll: f32) u1 {
    return @intFromBool(distance > 120 and roll > 0.15);
}
test "boar guns remain mandatory at close distance" {
    const t = @import("std").testing;
    try t.expectEqual(@as(u1, 0), select(120, 0.9));
    try t.expectEqual(@as(u1, 0), select(121, 0.15));
    try t.expectEqual(@as(u1, 1), select(121, 0.16));
}
