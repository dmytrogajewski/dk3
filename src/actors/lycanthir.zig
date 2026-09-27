// SPDX-License-Identifier: GPL-2.0-or-later
//! Lycanthir attack selection and Silverclaw-dependent resurrection.
const std = @import("std");
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc", "atakd", "jumpb" };
pub const death_howl = "e3/m_lycanthirhowla.wav";
pub const jump_range: f32 = 250.0 * (2.0 * (270.0 / 800.0));
pub const State = struct {
    phase: enum { living, collapsed, rising } = .living,
    started_ms: i64 = 0,
    wake_ms: i64 = 0,
    prepared: bool = false,
    launched: bool = false,
    pub fn collapse(self: *State, now: i64, skill: i32) void {
        self.* = .{ .phase = .collapsed, .started_ms = now, .wake_ms = now + if (skill <= 2) @as(i64, 15000) else if (skill == 3) @as(i64, 10000) else 5000 };
    }
};
pub fn select(distance: f32, attack_range: f32, forward_dot_velocity: f32, speed_xy_squared: f32, mode_roll: f32, pose_roll: f32) u3 {
    if (distance < attack_range) {
        if (forward_dot_velocity > -1 and speed_xy_squared > 100 and mode_roll < 0.6) return 3;
        return if (pose_roll < 0.33) 0 else if (pose_roll < 0.666) 1 else 2;
    }
    return if (distance < jump_range and mode_roll < 0.2) 4 else 3;
}
test "lycanthir chase selection uses enemy movement and resurrection uses campaign difficulty" {
    const t = std.testing;
    try t.expectEqual(@as(u3, 3), select(60, 80, 20, 400, 0.5, 0));
    try t.expectEqual(@as(u3, 1), select(60, 80, -20, 400, 0.5, 0.5));
    try t.expectEqual(@as(u3, 4), select(120, 80, 0, 0, 0.1, 0));
    try t.expectEqual(@as(u3, 3), select(180, 80, 0, 0, 0.1, 0));
    var state: State = .{};
    state.collapse(1000, 3);
    try t.expectEqual(@as(i64, 11000), state.wake_ms);
}
