// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc", "atakd", "atake" };
pub const gaze_tag = 10024;
pub const stone_tag = 10025;
pub const State = struct {
    phase: enum { combat, rattle, gaze, recover, retreat, sidestep } = .combat,
    until_ms: i64 = 0,
    target: u32 = 0,
    eyes: bool = false,
    flash_until_ms: i64 = 0,
    retreat: [3]f32 = @splat(0),
};
pub fn inRange(distance: f32, melee: f32, spit_roll: f32, gaze_roll: f32) bool {
    return distance <= melee or (distance <= 350 and spit_roll < 0.5) or (distance <= 1250 and gaze_roll < 0.05);
}
pub fn eyeContact(toward_enemy: [3]f32, medusa: [3]f32, enemy: [3]f32, enemy_fov: f32) bool {
    return angle(toward_enemy[0], medusa[0]) < 35 and angle(toward_enemy[1], medusa[1]) < 35 and angle(-toward_enemy[0], enemy[0]) < 35 and angle(toward_enemy[1] + 180, enemy[1]) < enemy_fov * 0.5;
}
fn angle(a: f32, b: f32) f32 {
    return @abs(@mod(a - b + 180, 360) - 180);
}
test "Medusa requires mutual yaw and pitch contact with wrapped strict boundaries" {
    const t = std.testing;
    try t.expect(eyeContact(.{ 0, 359, 0 }, .{ 0, 1, 0 }, .{ 0, 179, 0 }, 90));
    try t.expect(!eyeContact(.{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 0, 135, 0 }, 90));
    try t.expect(!eyeContact(.{ 0, 0, 0 }, .{ 35, 0, 0 }, .{ 0, 180, 0 }, 90));
    try t.expect(!eyeContact(.{ 0, 0, 0 }, .{ 0, 0, 0 }, .{ 35, 180, 0 }, 90));
    try t.expect(inRange(350, 80, 0.7, 0.04));
    try t.expect(!inRange(1251, 80, 0, 0));
}
