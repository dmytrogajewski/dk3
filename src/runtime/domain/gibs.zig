// SPDX-License-Identifier: GPL-2.0-or-later
//! Flesh fragment lifecycle; actor policies decide which deaths fragment.
pub const State = struct { next_ms: i64, fade_ms: ?i64 = null, robotic: bool = false, skin_model: []const u8 = "" };
pub fn count(mass: f32, multiplayer: bool) usize {
    return @intFromFloat((if (multiplayer) @as(f32, 3) else 8) * @import("std").math.clamp(mass / 500, 0.35, 1));
}
pub fn bounds(index: usize) [3]f32 {
    return switch (index) {
        0 => @splat(2),
        2, 5 => @splat(3),
        4 => .{ 1, 1, 3 },
        else => @splat(1),
    };
}
pub fn model(index: usize) []const u8 {
    return switch (index % 9) {
        0 => "models/global/e_gibtorso.dkm",
        1 => "models/global/e_gibleg.dkm",
        2 => "models/global/e_gibfoot.dkm",
        3 => "models/global/e_gibhand.dkm",
        4 => "models/global/e_gibhead.dkm",
        5 => "models/global/e_gibchest.dkm",
        6 => "models/global/e_gibeye.dkm",
        7 => "models/global/e_gibarm.dkm",
        else => "models/global/e_gibmisc.dkm",
    };
}
test "gib count uses mass and mode rather than a fixed fragment count" {
    const t = @import("std").testing;
    try t.expectEqual(@as(usize, 2), count(20, false));
    try t.expectEqual(@as(usize, 6), count(400, false));
    try t.expectEqual(@as(usize, 8), count(3000, false));
    try t.expectEqual(@as(usize, 3), count(3000, true));
}
