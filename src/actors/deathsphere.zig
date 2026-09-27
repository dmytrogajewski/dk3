// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "ready", "flya" };
pub const bolt_model = "models/e1/we_dsbolt.dkm";
pub const bolt_flare = "models/e1/we_dsboltf.sp2";
pub const bolt_tag = 10017;
pub const muzzles = [_][3]f32{ .{ 1.21, 10.90, 27.18 }, .{ 23.99, 11.05, 9.38 }, .{ 0.77, 11.05, -7.40 }, .{ -24.23, 11.05, 9.21 } };
pub const State = struct {
    phase: enum { chase, charge, attack, move, recover, sidestep } = .chase,
    resume_phase: enum { chase, charge, recover } = .chase,
    until_ms: i64 = 0,
    charge_ms: i64 = 0,
    destination: [3]f32 = @splat(0),
    boost_frame: i32 = -1,
    extra: u2 = 0,
    bob: u4 = 0,
    pub fn extraVolley(self: *State, frame: i32) bool {
        if (self.boost_frame < 0 or frame < self.boost_frame or frame > self.boost_frame + 1) return false;
        const bit = @as(u2, 1) << @as(u1, @intCast(frame - self.boost_frame));
        if (self.extra & bit != 0) return false;
        self.extra |= bit;
        return true;
    }
};
pub fn bobImpulse(index: u4) f32 {
    const std = @import("std");
    return 15 * @round(@sin(@as(f32, @floatFromInt(1 + @as(u16, index) * 30)) * std.math.pi / 180) * 1000) * 0.001;
}
test "deathsphere extra volleys survive a checkpoint without repeating a fired frame" {
    const t = @import("std").testing;
    var state: State = .{ .boost_frame = 34 };
    try t.expect(!state.extraVolley(33));
    try t.expect(state.extraVolley(34));
    var restored = state;
    try t.expect(!restored.extraVolley(34));
    try t.expect(restored.extraVolley(35));
    try t.expect(!restored.extraVolley(36));
}
