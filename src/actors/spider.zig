// SPDX-License-Identifier: GPL-2.0-or-later
//! Large and small spider attack/retreat contracts share their authored animations.
pub const attacks = [_][]const u8{ "ataka", "jumpa" };
pub const State = struct {
    launched: bool = false,
    retreat_until: ?i64 = null,
    sidestep_until: ?i64 = null,
    sidestep: [3]f32 = @splat(0),
};
pub fn inRange(distance: f32, melee: f32, jump: f32, roll: f32) bool {
    // Both classes retain the reference AI's zero initial jump chance. Do not
    // invent a higher jump frequency from the mere presence of jumpa frames.
    return distance < melee or (distance < jump and roll == 0);
}
pub fn retreatMilliseconds(roll: f32) i64 {
    return 2000 + @as(i64, @intFromFloat(roll * 5000));
}
