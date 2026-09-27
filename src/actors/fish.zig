// SPDX-License-Identifier: GPL-2.0-or-later
//! Aquatic wildlife and Dopefish own their goals; numeric tuning is supplied.
pub const attacks = [_][]const u8{"atak"};
pub const State = struct {
    start: [3]f32 = @splat(0),
    destination: ?[3]f32 = null,
    wander_until_ms: ?i64 = null,
    motion_ms: ?i64 = null,
    owner: u32 = 0,
    aggressive: bool = false,
};
pub fn aggression(previous: bool, distance: f32, roll: f32) bool {
    if (distance > 175) return false;
    if (distance < 150 and roll < 0.5) return true;
    return previous;
}
pub fn turn(speed: f32) f32 {
    return if (speed == 0) 0.01 else speed * 0.0005;
}
pub fn surface(velocity: [3]f32, water: u2) [3]f32 {
    var result = velocity;
    if (water < 3 and result[2] > 0) result[2] = 0;
    return result;
}
test "Dopefish keeps its engagement hysteresis and strict random boundary" {
    const t = @import("std").testing;
    try t.expect(aggression(false, 149, 0.49));
    try t.expect(!aggression(false, 149, 0.5));
    try t.expect(!aggression(false, 150, 0));
    try t.expect(aggression(true, 175, 0.9));
    try t.expect(!aggression(true, 175.01, 0));
    try t.expectEqual([3]f32{ 10, 20, 0 }, surface(.{ 10, 20, 30 }, 2));
    try t.expectEqual([3]f32{ 10, 20, -30 }, surface(.{ 10, 20, -30 }, 2));
    try t.expectEqual([3]f32{ 10, 20, 30 }, surface(.{ 10, 20, 30 }, 3));
}
