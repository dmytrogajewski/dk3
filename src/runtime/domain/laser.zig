// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored fixed/tracking lasers, separate from weapon and actor projectiles.
pub const render_tag = 10032;
pub const State = struct {
    enabled: bool = false,
    initialized: bool = false,
    next_ms: i64 = 0,
    target: u32 = 0,
    direction: [3]f32 = .{ 1, 0, 0 },
    endpoint: [3]f32 = @splat(0),
    normal: [3]f32 = @splat(0),
    damage: i32 = 1,
    sound: u16 = 0,
    changed: bool = true,
    spark_ms: ?i64 = null,
    spark_count: u8 = 0,
    pub fn toggle(self: *State, now: i64) void {
        self.enabled = !self.enabled;
        if (self.enabled) self.changed = true;
        self.next_ms = now;
    }
};
