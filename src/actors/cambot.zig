// SPDX-License-Identifier: GPL-2.0-or-later
//! Surveillance actor: acquisition/alarm and following, with no damage weapon.
const std = @import("std");
pub const alarm = "e1/m_cambotalarm.wav";
pub const idle_light = "models/e1/me_cambotf.sp2";
pub const alert_light = "models/global/e_sflred.sp2";
pub const idle_tag: i32 = 0x43414d;
pub const alert_tag: i32 = idle_tag + 1;
pub const searchlight = .{ .reach = 600, .radius = 2, .pitch = 45, .sweep_rate = 0.08, .sweep_span = 109, .idle_color = [3]f32{ 0.6, 0.6, 0.1 }, .alert_color = [3]f32{ 0.8, 0.1, 0.1 } };
pub const State = struct {
    seen: bool = false,
    alarmed: u32 = 0,
    wave: u4 = 0,
    back_direction: i8 = 0,
    evade: ?[3]f32 = null,
};
pub const Movement = enum { back_away, hover, follow };
pub fn movement(horizontal_distance: f32) Movement {
    return if (horizontal_distance < 72) .back_away else if (horizontal_distance > 192) .follow else .hover;
}
pub fn sees(yaw_delta: f32) bool {
    return @abs(@mod(yaw_delta + 180, 360) - 180) < 75;
}
test "camera follows outside the authored band and requires its facing cone" {
    try std.testing.expectEqual(Movement.back_away, movement(71));
    try std.testing.expectEqual(Movement.hover, movement(72));
    try std.testing.expectEqual(Movement.hover, movement(192));
    try std.testing.expectEqual(Movement.follow, movement(193));
    try std.testing.expect(sees(359));
    try std.testing.expect(sees(-74));
    try std.testing.expect(!sees(75));
    try std.testing.expect(!sees(180));
}
