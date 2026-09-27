// SPDX-License-Identifier: GPL-2.0-or-later
//! Proximity-triggered hatching; tuning and pose durations remain supplied data.
pub const State = struct {
    phase: enum { closed, waiting, opening, shell } = .closed,
    next_ms: i64 = 0,
    pub fn notice(self: *State, now: i64, visible: bool, distance: f32, chance: f32, delay: f32) void {
        if (self.phase != .closed or !visible) return;
        if (distance > 200 and !(distance <= 512 and chance < 0.05)) return;
        self.phase = .waiting;
        self.next_ms = now + @as(i64, @intFromFloat(500 + 3000 * delay));
    }
    pub fn use(self: *State, now: i64) void {
        if (self.phase != .closed) return;
        self.phase = .waiting;
        self.next_ms = now;
    }
    pub fn tick(self: *State, now: i64, animation_ms: i64) bool {
        if (now < self.next_ms) return false;
        switch (self.phase) {
            .waiting => {
                self.phase = .opening;
                self.next_ms = now + animation_ms;
                return true;
            },
            .opening => self.phase = .shell,
            else => {},
        }
        return false;
    }
};
test "pod hatches once after its authored proximity delay" {
    const t = @import("std").testing;
    var pod: State = .{};
    pod.notice(1000, false, 100, 0, 0);
    try t.expectEqual(.closed, pod.phase);
    pod.notice(1000, true, 300, 0.1, 0);
    try t.expectEqual(.closed, pod.phase);
    pod.notice(1000, true, 100, 0.9, 0.5);
    try t.expectEqual(@as(i64, 3000), pod.next_ms);
    try t.expect(!pod.tick(2999, 1000));
    try t.expect(pod.tick(3000, 1000));
    try t.expect(!pod.tick(4000, 1000));
    try t.expectEqual(.shell, pod.phase);
    pod.use(5000);
    try t.expect(!pod.tick(5000, 1000));
}
