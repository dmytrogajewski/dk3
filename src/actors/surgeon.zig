// SPDX-License-Identifier: GPL-2.0-or-later
//! Non-combat surgeon cower timing; original goals resume after reevaluation.
pub const poses = [_][]const u8{ "gamba", "gambc" };
pub const State = struct {
    active: bool = false,
    returning: bool = false,
    until_ms: i64 = 0,
    reconsider_ms: i64 = 0,
    started_ms: i64 = 0,
    home: [3]f32 = @splat(0),
    pose: u1 = 0,
    pub fn hurt(self: *State, position: [3]f32, now: i64, roll: f32) void {
        self.until_ms = now + 15000;
        if (self.active) return;
        self.active = true;
        self.returning = false;
        self.home = position;
        self.started_ms = now;
        self.reconsider_ms = now + 10000;
        self.pose = if (roll > 0.5) 0 else 1;
    }
    pub fn advance(self: *State, distance: f32, visible: bool, active_distance: f32, now: i64) enum { cower, resume_goal, return_home } {
        if (distance < 300 and visible and now > self.reconsider_ms) {
            self.active = false;
            return .resume_goal;
        }
        if (distance > active_distance and now > self.until_ms) {
            self.active = false;
            self.returning = true;
            return .return_home;
        }
        return .cower;
    }
};
test "injury extends cowering without restarting its pose or reevaluation timer" {
    const t = @import("std").testing;
    var state: State = .{};
    state.hurt(.{ 1, 2, 3 }, 1000, 0.75);
    state.hurt(.{ 4, 5, 6 }, 5000, 0.2);
    try t.expectEqual(@as(i64, 20000), state.until_ms);
    try t.expectEqual(@as(i64, 1000), state.started_ms);
    try t.expectEqual(@as(u1, 0), state.pose);
    try t.expectEqual(.cower, state.advance(900, false, 800, 19999));
    try t.expectEqual(.return_home, state.advance(900, false, 800, 20001));
}
