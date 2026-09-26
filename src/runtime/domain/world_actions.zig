// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit state for authored world actions; all deadlines use simulation time.
pub const Hazard = struct {
    enabled: bool = true,
    toggleable: bool = false,
    damage: i32 = 5,
    interval_ms: i64 = 500,
    ready_ms: i64 = 0,
    sound: []const u8 = "",
};
pub const Destructible = struct {
    hidden: bool = false,
    broken: bool = false,
    shootable: bool = true,
    nonsolid: bool = false,
    damage: f32 = 0,
    radius: f32 = 160,
};
pub const Wall = struct { visible: bool = true, toggleable: bool = false, nonsolid: bool = false, used: bool = false };
pub const Event = struct { target: []const u8, delay_ms: i64 };
pub const Sequence = struct {
    events: []const Event = &.{},
    active: bool = false,
    once: bool = false,
    used: bool = false,
    actor_allowed: bool = false,
    touch: bool = false,
    cursor: usize = 0,
    started_ms: i64 = 0,
    ready_ms: i64 = 0,
    wait_ms: i64 = 200,
    activator: u32 = 0,
    sound: []const u8 = "",
    pub fn start(self: *Sequence, activator: u32, now: i64) bool {
        if (self.active or now < self.ready_ms or (self.once and self.used)) return false;
        self.active = true;
        self.used = true;
        self.cursor = 0;
        self.started_ms = now;
        self.activator = activator;
        return true;
    }
    pub fn next(self: *Sequence, now: i64) ?[]const u8 {
        if (!self.active) return null;
        if (self.cursor == self.events.len) {
            self.active = false;
            self.ready_ms = now + self.wait_ms;
            return null;
        }
        const event = self.events[self.cursor];
        if (now < self.started_ms + event.delay_ms) return null;
        self.cursor += 1;
        return event.target;
    }
};
test "timed targets preserve order, consume before dispatch and respect repeat cooldown" {
    const std = @import("std");
    var state: Sequence = .{ .events = &.{ .{ .target = "first", .delay_ms = 0 }, .{ .target = "later", .delay_ms = 300 } } };
    try std.testing.expect(state.start(7, 100));
    try std.testing.expectEqualStrings("first", state.next(100).?);
    try std.testing.expect(state.next(399) == null);
    try std.testing.expect(!state.start(8, 400));
    try std.testing.expectEqualStrings("later", state.next(400).?);
    try std.testing.expect(state.next(400) == null);
    try std.testing.expect(!state.start(8, 599));
    try std.testing.expect(state.start(8, 600));
    state.once = true;
    _ = state.next(1000);
    _ = state.next(1000);
    _ = state.next(1000);
    try std.testing.expect(!state.start(8, 5000));
}
