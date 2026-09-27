// SPDX-License-Identifier: GPL-2.0-or-later
//! Lab monkey chooses close punches, far punches, leaps and lateral hops.
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc", "atakd", "atake" };
pub fn select(distance: f32, roll: f32) u3 {
    if (distance > 108) return if (roll > 0.5) 2 else 3;
    if (distance > 56) return if (roll < 0.5) 0 else 4;
    return 1;
}
pub fn inRange(distance: f32, melee: f32, jump: f32, roll: f32) bool {
    return distance < melee or (distance < jump and roll < 0.5);
}
pub fn hop(distance: f32, roll: f32) ?f32 {
    if (distance > 108) return null;
    if (distance > 56) return if (roll < 0.75) 70 else null;
    return if (roll < 0.5) 110 else null;
}
test "lab monkey distance boundaries select distinct attacks and hop chances" {
    const t = @import("std").testing;
    try t.expectEqual(@as(u3, 1), select(56, 0.8));
    try t.expectEqual(@as(u3, 4), select(108, 0.8));
    try t.expectEqual(@as(u3, 2), select(109, 0.8));
    try t.expect(!inRange(250, 80, 250, 0));
    try t.expect(inRange(200, 80, 250, 0.49));
    try t.expectEqual(@as(?f32, 70), hop(100, 0.7));
    try t.expectEqual(@as(?f32, null), hop(50, 0.7));
}
