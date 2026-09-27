// SPDX-License-Identifier: GPL-2.0-or-later
pub const pipe_attacks = [_][]const u8{ "ataka", "jumpa" };
pub const plague_attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct {
    launched: bool = false,
    poison: bool = false,
    swimming: bool = false,
    water: u2 = 0,
    evasion_until: ?i64 = null,
    strafe: bool = false,
    strafe_yaw: f32 = 0,
    destination: [3]f32 = @splat(0),
};
pub fn inRange(distance: f32, bite: f32, jump: f32, roll: f32) bool {
    return distance < bite or (distance < jump and roll <= 0.3);
}
pub fn poisonous(plague: bool, pose: u3, roll: f32) bool {
    return plague and pose == 0 and roll < 0.2;
}
test "only Plague Rat close attacks choose poison" {
    const t = @import("std").testing;
    try t.expect(poisonous(true, 0, 0.19));
    try t.expect(!poisonous(true, 0, 0.2));
    try t.expect(!poisonous(true, 1, 0));
    try t.expect(!poisonous(false, 0, 0));
    try t.expect(inRange(110, 40, 120, 0.3));
    try t.expect(!inRange(120, 40, 120, 0));
}
