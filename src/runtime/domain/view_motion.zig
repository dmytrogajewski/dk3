// SPDX-License-Identifier: GPL-2.0-or-later
//! First-person offsets follow the admitted ioquake3 step/duck presentation contract.
//! Collision height and movement stay authoritative; prediction replay cannot add a step twice.
const std = @import("std");
pub const Boundary = struct { world: i32, incarnation: i32, teleport: bool, camera: i32, mode: i32 };
pub const State = struct {
    boundary: ?Boundary = null,
    command_ms: i64 = 0,
    height: ?f32 = null,
    duck_change: f32 = 0,
    duck_ms: i64 = 0,
    step_change: f32 = 0,
    step_ms: i64 = 0,
    previous_ms: i64 = 0,
    steps: u32 = 0,
    pub fn synchronize(self: *State, boundary: Boundary, command_ms: i64, now: i64) void {
        if (self.boundary == null or !std.meta.eql(self.boundary.?, boundary) or now < self.previous_ms) self.* = .{ .boundary = boundary, .command_ms = command_ms };
        self.previous_ms = now;
    }
    fn remaining(change: f32, started: i64, now: i64, duration: i64) f32 {
        return change * @as(f32, @floatFromInt(duration - std.math.clamp(now - started, 0, duration))) / @as(f32, @floatFromInt(duration));
    }
    pub fn command(self: *State, at: i64, step: f32, now: i64) void {
        if (at <= self.command_ms) return;
        self.command_ms = at;
        if (step <= 0) return;
        self.step_change = @min(32, remaining(self.step_change, self.step_ms, now, 200) + step);
        self.step_ms = now;
        self.steps +%= 1;
    }
    pub fn offset(self: *State, height: f32, now: i64) f32 {
        if (self.height) |prior| if (prior != height) {
            self.duck_change = remaining(self.duck_change, self.duck_ms, now, 100) + height - prior;
            self.duck_ms = now;
        };
        self.height = height;
        return -remaining(self.duck_change, self.duck_ms, now, 100) - remaining(self.step_change, self.step_ms, now, 200);
    }
};

test "view transitions stay continuous, predicted steps deduplicate, and boundaries reset" {
    var view: State = .{};
    const boundary: Boundary = .{ .world = 1, .incarnation = 1, .teleport = false, .camera = 0, .mode = 0 };
    view.synchronize(boundary, 100, 100);
    try std.testing.expectEqual(@as(f32, 0), view.offset(22, 100));
    try std.testing.expectEqual(@as(f32, 24), view.offset(-2, 200));
    try std.testing.expectEqual(@as(f32, 12), view.offset(-2, 250));
    // Releasing crouch before it finishes preserves the current eye position.
    try std.testing.expectEqual(@as(f32, -12), view.offset(22, 250));
    try std.testing.expectEqual(@as(f32, 0), view.offset(22, 350));
    view.command(400, 16, 400);
    try std.testing.expectEqual(@as(f32, -16), view.offset(22, 400));
    view.command(400, 16, 450);
    try std.testing.expectEqual(@as(f32, -12), view.offset(22, 450));
    try std.testing.expectEqual(@as(u32, 1), view.steps);
    view.command(500, 16, 500);
    try std.testing.expectEqual(@as(f32, -24), view.offset(22, 500));
    var moved = boundary;
    moved.teleport = true;
    view.synchronize(moved, 500, 510);
    try std.testing.expectEqual(@as(f32, 0), view.offset(22, 510));
}
