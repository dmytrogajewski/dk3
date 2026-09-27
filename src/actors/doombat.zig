// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct {
    phase: enum { choose, chase, retreat, hover, attack } = .choose,
    ranged: bool = false,
    started_ms: i64 = 0,
    destination: [3]f32 = @splat(0),
    bob: u3 = 0,
    speed: f32 = 0,
};
pub fn ranged(health: f32, base: f32, roll: f32) bool {
    // The active callback compares a percentage against half of base health.
    return 100 * health / base <= base * 0.5 and roll < 0.25;
}
pub fn speedAfterHealthCheck(speed: f32, health: f32, base: f32) f32 {
    return if (100 * health / base <= health * 0.5) speed * 1.35 else speed;
}
pub fn bobImpulse(index: u3) f32 {
    const std = @import("std");
    const phase = @as(u8, @intFromFloat(@as(f32, @floatFromInt(index)) * 2.5)) % 12;
    return 50 * @round(@sin(@as(f32, @floatFromInt(1 + @as(u16, phase) * 30)) * std.math.pi / 180) * 1000) * 0.001;
}
test "doombat keeps the authored health comparison rather than a generic half-health rule" {
    const t = @import("std").testing;
    try t.expect(!ranged(20, 50, 0));
    try t.expect(ranged(12, 50, 0.24));
    try t.expect(!ranged(12, 50, 0.25));
    try t.expectEqual(@as(f32, 250), speedAfterHealthCheck(250, 12, 50));
}
