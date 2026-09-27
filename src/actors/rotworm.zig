// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakc", "atakb" };
pub const State = struct {
    phase: enum { ground, ceiling, flight, jump_bite } = .ground,
    started_ms: i64 = 0,
    destination: [3]f32 = @splat(0),
};
pub const Spit = struct { damage: f32 };
pub const spit_model = "models/e3/me_rotspit.dkm";
pub const spit_tag = 10008;
pub fn select(distance: f32, roll: f32) u3 {
    return if (distance < 60 or roll < 0.25) 0 else 1;
}
pub fn jump(distance: f32, visible: bool, roll: f32) bool {
    return distance > 200 and visible and roll > 0.25;
}
pub fn landed(elapsed: i64, distance: f32, grounded: bool) bool {
    return grounded and (distance < 32 or elapsed > 3000);
}
test "Rotworm chooses authored bite, spit and leap boundaries" {
    const t = @import("std").testing;
    try t.expectEqual(@as(u3, 0), select(59, 1));
    try t.expectEqual(@as(u3, 1), select(60, 0.25));
    try t.expect(!jump(200, true, 1));
    try t.expect(jump(201, true, 0.26));
    try t.expect(!landed(3001, 100, false));
    try t.expect(landed(3001, 100, true));
    try t.expect(landed(100, 31, true));
}
