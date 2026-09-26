// SPDX-License-Identifier: GPL-2.0-or-later
//! Ballistic pickup bounce semantics adapted from GPL ioquake3 g_items.c.
const std = @import("std");
const v = @import("vector.zig");
const collision = @import("collision.zig");
pub const State = struct {
    base: v.Vec3 = @splat(0),
    velocity: v.Vec3 = @splat(0),
    started_ms: i64 = 0,
    bounce: f32 = 0.2,
    ground: ?u16 = null,
    pub fn sample(self: State, now: i64) v.Vec3 {
        if (self.ground != null) return self.base;
        const seconds = @as(f32, @floatFromInt(now - self.started_ms)) * 0.001;
        var result = v.add(self.base, v.scale(self.velocity, seconds));
        result[2] -= 400 * seconds * seconds;
        return result;
    }
    pub fn impact(self: *State, trace: collision.Trace, now: i64, elapsed: u32) v.Vec3 {
        const hit = now - elapsed + @as(i64, @intFromFloat(@as(f32, @floatFromInt(elapsed)) * trace.fraction));
        var velocity = self.velocity;
        velocity[2] -= 800 * @as(f32, @floatFromInt(hit - self.started_ms)) * 0.001;
        self.velocity = v.scale(v.add(velocity, v.scale(trace.normal, -2 * v.dot(velocity, trace.normal))), self.bounce);
        var position = trace.end;
        if (trace.normal[2] > 0 and self.velocity[2] < 40) {
            position[2] += 1;
            // The native engine's snap ABI rounds to nearest, ties to even.
            for (&position) |*value| value.* = v.snap(value.*);
            self.ground = trace.entity;
            self.velocity = @splat(0);
        } else position = v.add(position, trace.normal);
        self.base = position;
        self.started_ms = now;
        return position;
    }
};
test "gravity uses actual time and low floor bounce comes to rest" {
    var state: State = .{ .base = .{ 0, 0, 100 }, .started_ms = 1000 };
    try std.testing.expectEqual(@as(f32, 0), state.sample(1500)[2]);
    const result = state.impact(.{ .end = .{ 0, 0, 10 }, .normal = .{ 0, 0, 1 }, .fraction = 1, .entity = 12 }, 1100, 100);
    try std.testing.expectEqual(@as(?u16, 12), state.ground);
    try std.testing.expectEqual(result, state.sample(9000));
}
