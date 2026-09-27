// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored emitter scheduling is separate from client particle lifetimes.
const std = @import("std");
const v = @import("vector.zig");
pub const render_tag = 10037;
pub const Kind = enum(u8) { simple, cp3, rain, smoke, cp1, cp2, cp4, bubble };
pub fn kind(flags: u32) Kind {
    for (0..8) |bit| if (flags & (@as(u32, 1) << @as(u5, @intCast(bit))) != 0) return @enumFromInt(bit);
    return .simple;
}
pub const Phase = enum { parse, idle, spawn, check };
pub const State = struct {
    flags: u32 = 0,
    phase: Phase = .parse,
    on: bool = false,
    tracked: bool = false,
    outside: bool = false,
    next_ms: ?i64,
    until_ms: i64 = 0,
    started_ms: i64 = 0,
    duration_ms: i64 = 0,
    count: u8 = 1,
    spread: i16 = 2,
    velocity: f32 = 35,
    gravity: f32 = 0,
    radius: f32 = 0,
    scale: f32 = 1,
    alpha: f32 = 0.75,
    fade: f32 = 0.75,
    frequency: f32 = 0,
    emission_time: f32 = 12,
    color: v.Vec3 = @splat(1),
    direction: v.Vec3 = @splat(0),
    acceleration: v.Vec3 = .{ 0, 0, -1 },
    pub fn start(self: *State, now: i64) void {
        self.on = true; self.tracked = true; self.started_ms = now; self.phase = .check; self.next_ms = now + 500;
    }
    pub fn use(self: *State, now: i64) void {
        if (self.phase == .parse or self.flags & (1024 | 2048) == 0) return;
        if (!self.on) {
            self.on = true;
            if (self.duration_ms == 0) { self.phase = .spawn; self.next_ms = now + 200; } else {
                self.start(now); self.until_ms = now + self.duration_ms; self.next_ms = now + 300;
            }
        } else if (self.flags & 2048 != 0) {
            self.on = false; self.tracked = false; self.phase = .idle; self.next_ms = null;
        }
    }
    pub fn check(self: *State, visible: bool, now: i64) void {
        if (!visible and self.on and !self.outside) {
            self.tracked = false; self.outside = true; self.next_ms = now + 500; return;
        }
        if (visible and self.outside) {
            if (self.on) {
                if (self.duration_ms == 0) self.phase = .spawn else {
                    self.start(now); self.until_ms = now + self.duration_ms;
                }
            }
            self.outside = false;
        }
        if (self.duration_ms != 0 and self.on and self.until_ms < now) { self.tracked = false; self.on = false; }
        self.next_ms = now + 300;
    }
};
/// Authored emission values count frames. Native evaluates them at a fixed 60 Hz
/// so monitor refresh rate does not change the amount of smoke/sparks in gameplay.
pub const Cadence = struct {
    frequency: f32,
    alternate: f32,
    active_window: bool = false,
    pub fn emit(self: *Cadence, tick: i64, toggle: bool, random: bool, fraction: f32) bool {
        if (self.frequency == 0) return true;
        const interval: i64 = @max(1, @as(i64, @intFromFloat(self.frequency)));
        const due = @mod(tick, interval) == 0;
        if (due and toggle) {
            const previous = self.frequency;
            self.frequency = self.alternate * (if (!self.active_window and random) 0.25 + fraction * 0.75 else @as(f32, 1));
            self.alternate = previous;
            self.active_window = !self.active_window;
        }
        return due or self.active_window;
    }
};
pub fn angles(direction: v.Vec3) v.Vec3 {
    if (direction[0] == 0 and direction[1] == 0) return .{ if (direction[2] > 0) -90 else 90, 0, 0 };
    return .{ -@trunc(std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi), @trunc(std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi), 0 };
}
test "finite emitter retrigger and PVS resumption keep authored toggle and strict expiry" {
    const t = std.testing;
    var state: State = .{ .flags = 3080, .phase = .idle, .next_ms = null, .duration_ms = 1000 };
    state.use(2000);
    try t.expect(state.on and state.tracked);
    state.check(false, 2300);
    try t.expect(state.on and !state.tracked and state.outside);
    state.check(true, 2800);
    try t.expectEqual(@as(i64, 3800), state.until_ms);
    state.check(true, 3800);
    try t.expect(state.on);
    state.check(true, 4100);
    try t.expect(!state.on and !state.tracked);
    state.use(4500);
    state.use(4600);
    try t.expect(state.phase == .idle and state.next_ms == null and !state.tracked);
}
test "emission cadence distinguishes a frame interval from a toggled window" {
    const t = std.testing;
    var cadence: Cadence = .{ .frequency = 3, .alternate = 12 };
    try t.expect(!cadence.emit(2, true, false, 0));
    try t.expect(cadence.emit(3, true, false, 0));
    try t.expect(cadence.emit(4, true, false, 0));
    try t.expect(cadence.emit(12, true, false, 0));
    try t.expect(!cadence.emit(13, true, false, 0));
    try t.expect(cadence.emit(15, true, false, 0));
    try t.expectEqual(Kind.simple, kind(9));
    try t.expectEqual(Kind.smoke, kind(3080));
}
