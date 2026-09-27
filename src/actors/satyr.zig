// SPDX-License-Identifier: GPL-2.0-or-later
//! Alternating-side melee has authored transition poses; running swings stop at 40 units.
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc", "transa", "transb" };
pub const chase_pose: u3 = 2;
pub fn select(random: f32) u3 {
    return if (random < 0.5) 0 else 1;
}
pub fn transition(previous: u3, next: u3) ?u3 {
    if (previous == 1 and next == 0) return 3;
    if (previous == 0 and next == 1) return 4;
    return null;
}
