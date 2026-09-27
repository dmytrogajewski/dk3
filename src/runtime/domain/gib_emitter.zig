// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored gib generator. Scheduling and toggle state are intentionally distinct.
const v = @import("vector.zig");
pub const State = struct {
    initialized: bool = false,
    on: bool = false,
    flags: u32 = 0,
    count: u8 = 3,
    spread: f32 = 10,
    speed: f32 = 85,
    scale: f32 = 1,
    duration_ms: i64 = 1000,
    until_ms: i64 = 0,
    next_ms: ?i64,
    direction: v.Vec3 = @splat(0),
    parameters: @import("audio.zig").Parameters = .{ .volume = 0.75, .minimum = 128, .maximum = 512 },
    pub fn use(self: *State, now: i64) void {
        if (!self.initialized or (self.flags & 16 != 0 and self.on)) return;
        self.on = !self.on;
        self.next_ms = if (self.on) now + 100 else null;
        if (self.on) self.until_ms = now + self.duration_ms;
    }
    pub fn emit(self: *State, now: i64) bool {
        if (self.next_ms == null or now < self.next_ms.?) return false;
        if (now >= self.until_ms) {
            self.on = false;
            self.next_ms = null;
            return false;
        }
        self.next_ms = now + 800;
        return true;
    }
};
test "start-on emission does not consume the first no-toggle activation; expiration is strict" {
    const t = @import("std").testing;
    var state: State = .{ .initialized = true, .flags = 24, .next_ms = 1100, .until_ms = 2000 };
    try t.expect(!state.emit(1099));
    try t.expect(state.emit(1100));
    state.use(1500);
    try t.expect(state.on);
    try t.expectEqual(@as(i64, 2500), state.until_ms);
    state.use(1700);
    try t.expectEqual(@as(i64, 2500), state.until_ms);
    try t.expect(state.emit(1700));
    try t.expect(!state.emit(2500));
    try t.expect(state.next_ms == null and !state.on);
}
