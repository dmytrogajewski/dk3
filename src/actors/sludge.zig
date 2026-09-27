// SPDX-License-Identifier: GPL-2.0-or-later
//! Sludgeminion ammo is refilled only when standing in fluid.
pub const attacks = [_][]const u8{ "ataka", "atakb", "ambb", "atakstart" };
pub const State = struct {
    ammo: f32 = 5,
    water: u2 = 0,
    phase: enum { normal, scooping, raising } = .normal,
    idle_chosen: bool = false,
    idle_scoop: bool = false,
};
pub const Glob = struct { damage: f32, contacts: u2 = 0, spin: [3]f32 = .{ 0, 0, 35 } };
pub const model = "models/e1/me_sludge.dkm";
pub const glow = "models/global/e_sflgreen.sp2";
pub const render_tag = 10012;
pub fn select(roll: f32) u3 {
    return if (roll < 0.2) 1 else 0;
}
pub fn scoop(ammo: f32, roll: f32) f32 {
    return if (ammo < 0) 2 + 7 * roll else ammo + 3;
}
test "sludge replenishes negative ammo separately from an empty reservoir" {
    const t = @import("std").testing;
    try t.expectEqual(@as(f32, 3), scoop(0, 0.9));
    try t.expectEqual(@as(f32, 5.5), scoop(-1, 0.5));
    try t.expectEqual(@as(u3, 1), select(0.19));
    try t.expectEqual(@as(u3, 0), select(0.2));
}
