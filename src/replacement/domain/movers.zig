// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored binary mover transitions. Engine collision commits happen separately.
const std = @import("std");
const v = @import("vector.zig");
const Deadline = @import("time.zig").Deadline;
pub const Curve = enum { linear, accelerate, bounce };
pub fn phase(curve: Curve, fraction: f32) f32 {
    const t = std.math.clamp(fraction, 0, 1);
    return switch (curve) {
        .linear => t,
        .accelerate => t * t,
        .bounce => if (t < 0.7) t * t / 0.49 else 1 - 0.1 * @sin((t - 0.7) / 0.3 * std.math.pi),
    };
}
pub const Motion = struct {
    base: v.Vec3 = @splat(0),
    end: v.Vec3 = @splat(0),
    start_ms: i64 = 0,
    duration_ms: i32 = 1,
    curve: Curve = .linear,
    pub fn sample(self: Motion, now: i64) v.Vec3 {
        const t = @as(f32, @floatFromInt(now - self.start_ms)) / @as(f32, @floatFromInt(self.duration_ms));
        return v.add(self.base, v.scale(v.add(self.end, v.scale(self.base, -1)), phase(self.curve, t)));
    }
    pub fn finished(self: Motion, now: i64) bool {
        return now >= self.start_ms + self.duration_ms;
    }
};
pub const State = enum { closed, opening, open, closing };
pub const Binary = struct {
    closed: v.Vec3,
    opened: v.Vec3,
    motion: Motion,
    state: State = .closed,
    angular: bool = false,
    platform: bool = false,
    speed: f32 = 100,
    wait_ms: i32 = 3000,
    delay_ms: i32 = 0,
    toggle: bool = false,
    return_both: bool = false,
    force: bool = false,
    damage: i32 = 2,
    return_at: Deadline = .{},
    group: u32 = 0,
    owner: u32 = 0,
    pub fn moving(self: Binary) bool {
        return self.state == .opening or self.state == .closing;
    }
    /// null means no transition; repeated use never reverses an opening lift.
    pub fn use(self: *Binary, now: i64, activator: u32) !?bool {
        self.owner = activator;
        if (self.state == .opening) return null;
        if (self.state == .open and !self.toggle) {
            if (self.wait_ms >= 0) self.return_at = try Deadline.after(now, @as(i64, self.wait_ms) + 1);
            return null;
        }
        return self.state != .open;
    }
    pub fn duration(self: Binary, open: bool, current: v.Vec3) !i32 {
        const milliseconds = v.length(v.add(if (open) self.opened else self.closed, v.scale(current, -1))) * 1000 / self.speed;
        if (!std.math.isFinite(milliseconds) or milliseconds >= 2147483648 or milliseconds < 0) return error.InvalidMoverDuration;
        return @max(1, @as(i32, @intFromFloat(milliseconds)));
    }

    pub fn start(self: *Binary, open: bool, current: v.Vec3, now: i64, duration_ms: i32, delayed: bool) void {
        self.motion.base = current;
        self.motion.end = if (open) self.opened else self.closed;
        self.motion.start_ms = now + if (delayed) @as(i64, self.delay_ms) else 0;
        self.motion.duration_ms = duration_ms;
        self.state = if (open) .opening else .closing;
        self.return_at = .{};
    }
    /// Returns true for opening arrival, which owns the single target activation.
    pub fn reached(self: *Binary, now: i64, master: bool) !bool {
        if (!self.moving()) return false;
        const opened = self.state == .opening;
        self.state = if (opened) .open else .closed;
        if (master and self.wait_ms >= 0 and !self.toggle and (opened or self.return_both)) self.return_at = try Deadline.after(now, @as(i64, self.wait_ms) + 1);
        return opened and master;
    }
};
test "opening use cannot reverse a lift and dwell retains the next-frame boundary" {
    var lift: Binary = .{ .closed = .{ 0, 0, 0 }, .opened = .{ 0, 0, 100 }, .motion = .{}, .wait_ms = 0 };
    try std.testing.expectEqual(@as(?bool, true), try lift.use(0, 7));
    lift.start(true, lift.closed, 0, 1000, false);
    try std.testing.expectEqual(@as(?bool, null), try lift.use(500, 7));
    try std.testing.expectEqual(State.opening, lift.state);
    try std.testing.expect(try lift.reached(1000, true));
    try std.testing.expect(!lift.return_at.due(1000));
    try std.testing.expect(lift.return_at.due(1001));
    try std.testing.expectEqual(@as(?bool, null), try lift.use(1001, 7));
    try std.testing.expect(!lift.return_at.due(1001));
}
