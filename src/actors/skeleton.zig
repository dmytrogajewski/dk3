// SPDX-License-Identifier: GPL-2.0-or-later
//! Six standing sword attacks and a distinct moving attack sequence.
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc", "atakd", "atake", "atakg", "atakf" };
pub fn select(random: f32) u3 {
    return @intFromFloat(@min(@as(f32, 5), random * 6));
}
pub const chase_pose: u3 = 6;
