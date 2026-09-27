// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct {
    suspended_target: u32 = 0,
    wandering: bool = false,
    start: [3]f32 = @splat(0),
    destination: ?[3]f32 = null,
    wander_until_ms: i64 = 0,
};
pub fn select(roll: f32) u3 {
    return if (roll < 1.0 / 3.0) 0 else 1;
}
pub fn abandons(water: u2) bool {
    return water == 0;
}
pub fn resumes(water: u2) bool {
    return water == 3;
}
test "Shark target suspension uses separate dry and submerged boundaries" {
    const t = @import("std").testing;
    try t.expect(abandons(0));
    try t.expect(!abandons(1));
    try t.expect(!resumes(2));
    try t.expect(resumes(3));
    try t.expectEqual(@as(u3, 0), select(0.32));
    try t.expectEqual(@as(u3, 1), select(0.34));
}
