// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared animation-event cursor; class policies select attacks and movement.
pub const State = struct {
    active: bool = false,
    moving: bool = false,
    next_pose: ?u3 = null,
    pose: u3 = 0,
    started_ms: i64 = 0,
    struck: u2 = 0,
    sounds: u2 = 0,
    pub fn begin(self: *State, pose: u3, now: i64) void {
        self.* = .{ .active = true, .pose = pose, .started_ms = now };
    }
    pub fn event(self: *State, bit: u2, milliseconds: i64, now: i64, sound: bool) bool {
        const mask = if (sound) &self.sounds else &self.struck;
        if (!self.active or mask.* & bit != 0 or now - self.started_ms < milliseconds) return false;
        mask.* |= bit;
        return true;
    }
};
