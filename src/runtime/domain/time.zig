// SPDX-License-Identifier: GPL-2.0-or-later
//! Simulation time comes from the engine frame, never from worker wall clocks.
const std = @import("std");
pub const Clock = struct {
    now_ms: i64,
    frame: u64 = 0,
    pub fn advance(self: *Clock, now_ms: i64) !u32 {
        const delta = std.math.sub(i64, now_ms, self.now_ms) catch return error.InvalidTime;
        if (delta < 0 or delta > std.math.maxInt(u32) or self.frame == std.math.maxInt(u64)) return error.InvalidTime;
        self.now_ms = now_ms;
        self.frame += 1;
        return @intCast(delta);
    }
};
/// Optional deadlines keep "inactive" distinct from a deadline due right now.
pub const Deadline = struct {
    at_ms: ?i64 = null,
    pub fn after(now_ms: i64, delay_ms: i64) !Deadline {
        return .{ .at_ms = std.math.add(i64, now_ms, delay_ms) catch return error.InvalidTime };
    }
    pub fn due(self: Deadline, now_ms: i64) bool {
        return if (self.at_ms) |at| now_ms >= at else false;
    }
    pub fn remaining(self: Deadline, now_ms: i64) !?i64 {
        return if (self.at_ms) |at| std.math.sub(i64, at, now_ms) catch return error.InvalidTime else null;
    }
    pub fn restore(now_ms: i64, remaining_ms: ?i64) !Deadline {
        return if (remaining_ms) |remaining_ms_value| after(now_ms, remaining_ms_value) else .{};
    }
};
test "engine delta is exact and relative deadlines preserve overdue state" {
    var clock: Clock = .{ .now_ms = 1000 };
    try std.testing.expectEqual(@as(u32, 17), try clock.advance(1017));
    try std.testing.expectError(error.InvalidTime, clock.advance(1016));
    try std.testing.expectEqual(@as(i64, 1017), clock.now_ms);
    const deadline = try Deadline.after(1000, 10);
    const restored = try Deadline.restore(5000, try deadline.remaining(clock.now_ms));
    try std.testing.expectEqual(@as(?i64, 4993), restored.at_ms);
    try std.testing.expect(restored.due(5000));
    try std.testing.expect(!(try Deadline.restore(5000, null)).due(5000));
    try std.testing.expectError(error.InvalidTime, Deadline.after(std.math.maxInt(i64), 1));
}
