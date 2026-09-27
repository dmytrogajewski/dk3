// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb", "jumpa" };
pub const State = struct { launched: bool = false };
pub fn inRange(distance: f32, melee: f32, jump: f32, roll: f32) bool {
    return distance < melee or (distance < jump and roll <= 0.4);
}
pub fn select(distance: f32, melee: f32, roll: f32) u3 {
    return if (distance > melee) 2 else if (roll < 0.5) 0 else 1;
}
test "Cerberus jump admission and selection are separate from bite selection" {
    const t = @import("std").testing;
    try t.expect(inRange(200, 108, 250, 0.4));
    try t.expect(!inRange(200, 108, 250, 0.41));
    try t.expectEqual(@as(u3, 2), select(200, 108, 0));
    try t.expectEqual(@as(u3, 1), select(108, 108, 0.5));
}
