// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct { next_attack_ms: i64 = 0, sidestep_until: ?i64 = null, destination: [3]f32 = @splat(0) };
pub fn select(distance: f32) u3 {
    return if (distance > 80) 0 else 1;
}
pub const inRange = @import("knights.zig").inRange;
test "thief throws only beyond eighty units" {
    const t = @import("std").testing;
    try t.expectEqual(@as(u3, 1), select(80));
    try t.expectEqual(@as(u3, 0), select(81));
}
