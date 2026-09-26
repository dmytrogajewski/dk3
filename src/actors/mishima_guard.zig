// SPDX-License-Identifier: GPL-2.0-or-later
//! Guard-owned eight-round pistol cycle. Times are simulation milliseconds.
const std = @import("std");
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc" };
pub const reload_animation = "reload";
pub const reload_sound = "global/i_scammo.wav";
pub const reload_sound_frame: u16 = 15;
pub const Phase = enum { ready, firing, reloading, recovering };
pub const Timing = struct { attack_ms: [3]i64, strike_ms: [3]i64, reload_ms: i64, reload_sound_ms: i64 };
pub const Events = struct { fire: bool = false, reload_sound: bool = false };
pub const State = struct {
    phase: Phase = .ready,
    rounds: u8 = 8,
    pose: u8 = 0,
    started_ms: i64 = 0,
    ready_ms: i64 = 0,
    fired: bool = false,
    sounded_reload: bool = false,
    random: u32 = 1,
    pub fn fraction(self: *State) f32 {
        self.random = self.random *% 1664525 +% 1013904223;
        return @as(f32, @floatFromInt(self.random >> 8)) / 16777216;
    }
    pub fn tick(self: *State, now: i64, clear_shot: bool, timing: Timing) Events {
        var events: Events = .{};
        switch (self.phase) {
            .firing => {
                if (!self.fired and now >= self.started_ms + timing.strike_ms[self.pose]) {
                    self.fired = true;
                    if (clear_shot and self.rounds > 0) {
                        self.rounds -= 1;
                        events.fire = true;
                    }
                }
                if (now >= self.started_ms + timing.attack_ms[self.pose]) self.phase = .ready;
            },
            .reloading => {
                if (!self.sounded_reload and now >= self.started_ms + timing.reload_sound_ms) {
                    self.sounded_reload = true;
                    events.reload_sound = true;
                }
                if (now >= self.started_ms + timing.reload_ms) {
                    self.rounds = 8;
                    self.ready_ms = now + 500 + @as(i64, @intFromFloat(self.fraction() * 1000));
                    self.phase = .recovering;
                }
            },
            .recovering => if (now >= self.ready_ms) {
                self.phase = .ready;
            },
            .ready => {
                if (self.rounds == 0) {
                    self.phase = .reloading;
                    self.started_ms = now;
                    self.sounded_reload = false;
                } else if (clear_shot and now >= self.ready_ms) {
                    self.pose = if (self.rounds % 4 == 0) @intFromFloat(self.fraction() * 3) else 0;
                    self.started_ms = now;
                    self.ready_ms = now + 200 + @as(i64, @intFromFloat(self.fraction() * 1000));
                    self.phase = .firing;
                    self.fired = false;
                }
            },
        }
        return events;
    }
};
test "guard fires eight rounds, reloads once, and cannot fire through a blocked shot" {
    const timing: Timing = .{ .attack_ms = .{ 600, 600, 700 }, .strike_ms = .{ 100, 100, 100 }, .reload_ms = 2400, .reload_sound_ms = 1500 };
    var state: State = .{};
    var fired: usize = 0;
    var reloads: usize = 0;
    var now: i64 = 0;
    while (now < 20000 and fired < 9) : (now += 50) {
        const events = state.tick(now, true, timing);
        fired += @intFromBool(events.fire);
        reloads += @intFromBool(events.reload_sound);
        if (events.reload_sound) try std.testing.expectEqual(@as(usize, 8), fired);
    }
    try std.testing.expectEqual(@as(usize, 9), fired);
    try std.testing.expectEqual(@as(usize, 1), reloads);
    state = .{};
    _ = state.tick(0, true, timing);
    try std.testing.expect(!state.tick(100, false, timing).fire);
    try std.testing.expectEqual(@as(u8, 8), state.rounds);
}
