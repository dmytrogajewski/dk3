// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored launched brush debris uses a delayed hull expansion and finite motion.
const std = @import("std");
pub const render_tag = 10034;
pub const State = struct {
    visible: bool = false,
    initialized: bool = false,
    active: bool = false,
    stopped: bool = false,
    flags: u32 = 0,
    owner: u32 = 0,
    activator: u32 = 0,
    destination: [3]f32 = @splat(0),
    spin: [3]f32 = @splat(0),
    parameters: @import("audio.zig").Parameters = .{},
    water: bool = false,
    next_ms: i64 = 0,
    started_ms: i64 = 0,
    stepped_ms: i64 = 0,
    expand_ms: ?i64 = null,
};
/// The class samples descending flight in 100 ms intervals and uses full distance.
pub fn forwardSpeed(start_z: f32, target_z: f32, distance: f32, upward: f32) !f32 {
    if (!std.math.isFinite(start_z) or !std.math.isFinite(target_z) or !std.math.isFinite(distance) or !std.math.isFinite(upward) or distance < 0) return error.InvalidDebrisFlight;
    for (2..16384) |tick| {
        const time = @as(f32, @floatFromInt(tick)) * 0.1;
        if (upward - 800 * time < 0 and start_z + upward * time - 400 * time * time <= target_z) return distance / time;
    }
    return error.InvalidDebrisFlight;
}
pub fn contact(velocity: [3]f32, normal: [3]f32) [3]f32 {
    var dot: f32 = 0;
    for (velocity, normal) |speed, axis| dot += speed * axis;
    var result: [3]f32 = undefined;
    for (&result, velocity, normal) |*value, speed, axis| {
        value.* = speed - axis * dot * 1.5;
        if (@abs(value.*) < 0.1) value.* = 0;
    }
    return result;
}
test "targeted debris uses descending sample and bounce retains tangential motion" {
    const t = std.testing;
    try t.expectApproxEqAbs(@as(f32, 1000), try forwardSpeed(0, 0, 1000, 400), 0.001);
    try t.expectApproxEqAbs(@as(f32, 500), try forwardSpeed(0, -800, 1000, 400), 0.001);
    try t.expectEqual([3]f32{ 50, 20, 40 }, contact(.{ 50, 20, -80 }, .{ 0, 0, 1 }));
    try t.expectEqual([3]f32{ 50, 20, -80 }, contact(.{ -100, 20, -80 }, .{ 1, 0, 0 }));
}
