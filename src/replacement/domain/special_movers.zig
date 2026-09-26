// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const v = @import("vector.zig");
const Motion = @import("movers.zig").Motion;
const Deadline = @import("time.zig").Deadline;
pub const Rotation = struct {
    base: v.Vec3,
    rate: v.Vec3,
    started_ms: i64 = 0,
    active: bool = false,
    damage: i32 = 2,
    pub fn sample(self: Rotation, now: i64) v.Vec3 {
        return if (self.active) v.add(self.base, v.scale(self.rate, @as(f32, @floatFromInt(now - self.started_ms)) * 0.001)) else self.base;
    }
    pub fn toggle(self: *Rotation, current: v.Vec3, now: i64) void {
        self.base = current;
        self.started_ms = now;
        self.active = !self.active;
    }
};
pub const SecretPhase = enum { closed, opening_first, waiting_first, opening_second, open, returning_first, waiting_return, returning_second };
pub const Secret = struct {
    closed: v.Vec3,
    first: v.Vec3,
    opened: v.Vec3,
    motion: Motion,
    phase: SecretPhase = .closed,
    action: Deadline = .{},
    speed: f32 = 100,
    wait_ms: i32 = 3000,
    stay_open: bool = false,
    damage: i32 = 2,
    owner: u32 = 0,
    group: u32 = 0,
    pub fn moving(self: Secret) bool {
        return switch (self.phase) {
            .opening_first, .opening_second, .returning_first, .returning_second => true,
            else => false,
        };
    }
    fn travel(self: *Secret, destination: v.Vec3, current: v.Vec3, now: i64) !void {
        const milliseconds = v.length(v.add(destination, v.scale(current, -1))) * 1000 / self.speed;
        if (!std.math.isFinite(milliseconds) or milliseconds < 0 or milliseconds >= 2147483648) return error.InvalidSecretDuration;
        self.motion = .{ .base = current, .end = destination, .start_ms = now, .duration_ms = @max(1, @as(i32, @intFromFloat(milliseconds))) };
        self.action = .{};
    }
    pub fn use(self: *Secret, current: v.Vec3, now: i64, owner: u32) !bool {
        if (self.phase != .closed) return false;
        self.owner = owner;
        try self.travel(self.first, current, now);
        self.phase = .opening_first;
        return true;
    }
    pub fn prepare(self: *Secret, current: v.Vec3, now: i64) !void {
        if (!self.action.due(now)) return;
        switch (self.phase) {
            .waiting_first => {
                try self.travel(self.opened, current, now);
                self.phase = .opening_second;
            },
            .open => {
                try self.travel(self.first, current, now);
                self.phase = .returning_first;
            },
            .waiting_return => {
                try self.travel(self.closed, current, now);
                self.phase = .returning_second;
            },
            else => return error.InvalidSecretPhase,
        }
    }
    /// Only full opening fires targets; the side-step and return do not.
    pub fn finish(self: *Secret, now: i64) !bool {
        if (!self.moving() or !self.motion.finished(now)) return false;
        switch (self.phase) {
            .opening_first => {
                self.phase = .waiting_first;
                self.action = try Deadline.after(now, 1000);
            },
            .opening_second => {
                self.phase = .open;
                self.action = if (self.stay_open or self.wait_ms < 0) .{} else try Deadline.after(now, @as(i64, self.wait_ms) + 1);
                return true;
            },
            .returning_first => {
                self.phase = .waiting_return;
                self.action = try Deadline.after(now, 1000);
            },
            .returning_second => {
                self.phase = .closed;
                self.action = .{};
            },
            else => unreachable,
        }
        return false;
    }
};
test "secret door side-steps, pauses, opens once, then retraces both legs" {
    var door: Secret = .{ .closed = .{ 0, 0, 0 }, .first = .{ 0, 100, 0 }, .opened = .{ 100, 100, 0 }, .motion = .{}, .wait_ms = 500 };
    try std.testing.expect(try door.use(door.closed, 0, 5));
    try std.testing.expect(!try door.use(door.closed, 500, 5));
    try std.testing.expect(!try door.finish(1000));
    try door.prepare(door.first, 1999);
    try std.testing.expectEqual(SecretPhase.waiting_first, door.phase);
    try door.prepare(door.first, 2000);
    try std.testing.expect(try door.finish(3000));
    try std.testing.expectEqual(@as(?i64, 3501), door.action.at_ms);
    try door.prepare(door.opened, 3501);
    try std.testing.expect(!try door.finish(4501));
    try door.prepare(door.first, 5501);
    try std.testing.expect(!try door.finish(6501));
    try std.testing.expectEqual(SecretPhase.closed, door.phase);
}
test "continuous rotation resumes from stopped orientation" {
    var rotation: Rotation = .{ .base = @splat(0), .rate = .{ 0, 90, 0 } };
    rotation.toggle(rotation.base, 1000);
    const stopped = rotation.sample(2000);
    rotation.toggle(stopped, 2000);
    try std.testing.expectEqual(v.Vec3{ 0, 90, 0 }, rotation.sample(9000));
    rotation.toggle(stopped, 9000);
    try std.testing.expectEqual(v.Vec3{ 0, 180, 0 }, rotation.sample(10000));
}
