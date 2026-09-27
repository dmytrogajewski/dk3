// SPDX-License-Identifier: GPL-2.0-or-later
//! Cryotech spray timings and muzzle positions reviewed against the authored class.
const std = @import("std");
pub const attacks = [_][]const u8{ "bambb", "bambc" };
pub const Event = struct { frame: u16, offset: [3]f32 };
pub const pulses = [_]Event{
    .{ .frame = 8, .offset = .{ 17.30, 27.28, 11.96 } },   .{ .frame = 10, .offset = .{ 12.44, 29.27, 14.44 } },
    .{ .frame = 12, .offset = .{ 6.15, 30.87, 16.48 } },   .{ .frame = 14, .offset = .{ 0.15, 31.36, 18.29 } },
    .{ .frame = 16, .offset = .{ -5.34, 30.82, 19.59 } },  .{ .frame = 18, .offset = .{ -8.84, 29.94, 19.62 } },
    .{ .frame = 20, .offset = .{ -11.23, 29.48, 17.42 } }, .{ .frame = 22, .offset = .{ -11.39, 29.53, 13.50 } },
};
pub const maintenance = [_]Event{
    .{ .frame = 0, .offset = .{ 9.16, 32.68, 9.67 } },   .{ .frame = 2, .offset = .{ 10.59, 34.30, 10.29 } },
    .{ .frame = 4, .offset = .{ 9.38, 33.97, 10.75 } },  .{ .frame = 6, .offset = .{ 9.94, 34.60, 10.54 } },
    .{ .frame = 8, .offset = .{ 10.34, 34.20, 10.59 } },
};
pub const State = struct {
    pulse: u4 = 0,
    ready_ms: i64 = 0,
    ambient_started: ?i64 = null,
    ambient_frame: u16 = 0,
    ambient_elapsed: i64 = -1,
    pub fn begin(self: *State, now: i64) void {
        self.pulse = 0;
        self.ready_ms = now + 3000;
    }
    pub fn next(self: *State, elapsed: i64, fps: u16) ?Event {
        if (self.pulse >= pulses.len) return null;
        const event = pulses[self.pulse];
        if (elapsed * fps < @as(i64, event.frame) * 1000) return null;
        self.pulse += 1;
        return event;
    }
};
pub const Spray = struct {
    owner: u32,
    damage: f32,
    origin: [3]f32,
    angles: [3]f32,
    born_ms: i64,
    stepped_ms: i64,
    contacted: bool = false,
};
pub const spray_speed: f32 = 250;
pub const spray_lifetime_ms: i64 = 800;
pub const render_tag = 10005;
test "a delayed Cryotech frame emits every crossed pulse exactly once" {
    var state: State = .{};
    state.begin(1000);
    try std.testing.expect(state.next(799, 10) == null);
    for (pulses[0..4]) |expected| try std.testing.expectEqual(expected, state.next(1400, 10).?);
    try std.testing.expect(state.next(1400, 10) == null);
    var restored = state;
    for (pulses[4..]) |expected| try std.testing.expectEqual(expected, restored.next(2900, 10).?);
    try std.testing.expect(restored.next(2900, 10) == null);
    try std.testing.expectEqual(@as(i64, 4000), restored.ready_ms);
}
