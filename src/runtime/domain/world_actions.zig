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
    wall_explode: ?@import("wall_breakage.zig").State = null,
    hidden: bool = false,
    broken: bool = false,
    shootable: bool = true,
    nonsolid: bool = false,
    damage: f32 = 0,
    radius: f32 = 160,
};
pub const Wall = struct { visible: bool = true, toggleable: bool = false, nonsolid: bool = false, used: bool = false };
pub const Event = struct { target: []const u8, delay_ms: i64 };
pub fn eventProperty(key: []const u8, value: []const u8, count: usize) !?Event {
    const std = @import("std");
    // Completion wiring and ordinary entity fields accompany timed targets.
    // Their string values are metadata, not event-delay entries.
    for ([_][]const u8{ "classname", "model", "origin", "angle", "angles", "targetname", "target", "killtarget", "spawnflags", "wait", "sound", "volume", "health", "delay", "_color", "min", "max", "coop", "ctf", "deathtag", "cinetrigger", "cinekill" }) |name| {
        if (std.ascii.eqlIgnoreCase(key, name)) return null;
    }
    const seconds = std.fmt.parseFloat(f32, value) catch return error.InvalidEventDelay;
    if (!std.math.isFinite(seconds) or seconds < 0 or seconds > 3600 or count >= 128) return error.InvalidEventDelay;
    return .{ .target = key, .delay_ms = @intFromFloat(seconds * 1000) };
}
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
test "cinematic completion metadata does not become a timed target" {
    const std = @import("std");
    try std.testing.expect(try eventProperty("cinetrigger", "e2m2_cinemid", 0) == null);
    try std.testing.expect(try eventProperty("CINEKILL", "e2m2_cinemid", 0) == null);
    try std.testing.expect(try eventProperty("target", "killbod", 0) == null);
    const first = (try eventProperty("lockincin", "0", 0)).?;
    const later = (try eventProperty("bdeath", "3", 1)).?;
    var state: Sequence = .{ .events = &.{ first, later } };
    try std.testing.expect(state.start(7, 100));
    try std.testing.expectEqualStrings("lockincin", state.next(100).?);
    try std.testing.expect(state.next(3099) == null);
    try std.testing.expectEqualStrings("bdeath", state.next(3100).?);
    try std.testing.expectError(error.InvalidEventDelay, eventProperty("bdeath", "not-a-delay", 0));
    try std.testing.expectError(error.InvalidEventDelay, eventProperty("bdeath", "-1", 0));
    try std.testing.expectError(error.InvalidEventDelay, eventProperty("bdeath", "nan", 0));
    try std.testing.expectError(error.InvalidEventDelay, eventProperty("bdeath", "0", 128));
}
