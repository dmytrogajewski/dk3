// SPDX-License-Identifier: GPL-2.0-or-later
//! Centurion and Fletcher own distinct attack and projectile contracts.
pub const Kind = enum { centurion, fletcher };
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct {
    ready_ms: i64 = 0,
    clear_ms: i64 = 0,
    sidestep_until: ?i64 = null,
    destination: [3]f32 = @splat(0),
};
pub fn select(kind: Kind, distance: f32, melee_range: f32) u3 {
    return @intFromBool(distance >= (if (kind == .centurion) melee_range else 400));
}
test "Centurion melee and Fletcher far shots have different boundaries" {
    const t = @import("std").testing;
    try t.expectEqual(@as(u3, 0), select(.centurion, 89, 90));
    try t.expectEqual(@as(u3, 1), select(.centurion, 90, 90));
    try t.expectEqual(@as(u3, 0), select(.fletcher, 399, 1000));
    try t.expectEqual(@as(u3, 1), select(.fletcher, 400, 1000));
    try t.expectEqual(@as(i64, 10000), @import("shafts.zig").flightTime(.fletcher));
}
