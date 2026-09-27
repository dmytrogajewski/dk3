// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc" };
pub const sweep = [_]struct { frame: u16, offset: [3]f32 }{
    .{ .frame = 10, .offset = .{ 5, 16, 16 } },   .{ .frame = 14, .offset = .{ -3, 16, 16 } },
    .{ .frame = 18, .offset = .{ -11, 16, 16 } }, .{ .frame = 22, .offset = .{ -19, 16, 16 } },
    .{ .frame = 26, .offset = .{ -27, 16, 16 } }, .{ .frame = 36, .offset = .{ -18, 16, 16 } },
};
pub const State = struct { pulse: u3 = 0, sidestep_until: ?i64 = null, destination: [3]f32 = @splat(0) };
pub fn select(distance: f32, roll: f32) u3 {
    return if (distance <= 128) 1 else if (roll < 0.75) 0 else 2;
}
test "Inmater's three attacks retain the melee boundary and sweep probability" {
    const t = @import("std").testing;
    try t.expectEqual(@as(u3, 1), select(128, 0.9));
    try t.expectEqual(@as(u3, 0), select(129, 0.74));
    try t.expectEqual(@as(u3, 2), select(129, 0.75));
}
