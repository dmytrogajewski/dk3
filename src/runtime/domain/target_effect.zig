// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const v = @import("vector.zig");
pub const render_tag = 10041;
pub const State = struct {
    flags: u32,
    next_ms: ?i64 = null,
    until_ms: ?i64 = null,
    pulse_ms: ?i64 = null,
    serial: u32 = 0,
    visible: bool = false,
    interval_ms: i64 = 100,
    duration_ms: i64 = 100,
    direction: v.Vec3 = @splat(0),
    color: v.Vec3 = @splat(0.5),
    speed: u8 = 5,
    count: u8 = 10,
    kind: u8 = 9,
    gravity: f32 = 125,
    sound: u16 = 0,
    pub fn use(self: *State, now: i64) bool {
        if (self.flags & 1 != 0) return false;
        self.until_ms = now + self.duration_ms;
        return true;
    }
    pub fn pulse(self: *State, now: i64, random: f32) void {
        self.visible = true; self.pulse_ms = now;
        self.serial +%= 1; if (self.serial == 0) self.serial = 1;
        if (self.flags & 4 != 0) {
            // Native compatibility correction: saved per-emitter randomness replaces
            // the reference's shared fixed table and unsaved global cursor.
            self.next_ms = now + (1 + @as(i64, @intFromFloat(random * 9))) * 100;
        } else if (self.until_ms == null or now + self.interval_ms < self.until_ms.?) {
            self.next_ms = now + self.interval_ms;
        } else self.next_ms = null;
    }
};
test "target effect use emits immediately and excludes the terminal interval" {
    const t = std.testing;
    var state: State = .{ .flags = 0, .duration_ms = 300 };
    try t.expect(state.use(1000));
    state.pulse(1000, 0); try t.expectEqual(@as(?i64, 1100), state.next_ms);
    state.pulse(1100, 0); try t.expectEqual(@as(?i64, 1200), state.next_ms);
    state.pulse(1200, 0); try t.expectEqual(@as(?i64, null), state.next_ms);
    state.flags = 1; state.until_ms = null;
    try t.expect(!state.use(2000));
    state.pulse(2000, 0); try t.expectEqual(@as(?i64, 2100), state.next_ms);
}
