// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakc", "amba" };
pub const Weapon = enum { none, punch, stave, wisp, summon };
pub const State = struct { weapon: Weapon = .none };
pub fn inRange(distance: f32, melee: f32) bool {
    return if (distance < 200) distance < melee else distance <= 600;
}
pub fn choose(distance: f32, melee: f32, stave: f32, wisp: f32, choice: u2) Weapon {
    if (distance < melee) return .punch;
    return switch (choice) {
        1 => if (distance <= stave) .stave else if (distance <= wisp) .wisp else .summon,
        2 => if (distance <= wisp) .wisp else if (distance <= stave) .stave else .summon,
        else => if (distance <= stave) .summon else .wisp,
    };
}

test "Garroth pursues through his melee/ranged gap and keeps weapon fallback order" {
    const t = @import("std").testing;
    try t.expect(inRange(119, 120));
    try t.expect(!inRange(120, 120));
    try t.expect(!inRange(199, 120));
    try t.expect(inRange(200, 120));
    try t.expect(inRange(600, 120));
    try t.expect(!inRange(601, 120));
    try t.expectEqual(Weapon.wisp, choose(500, 120, 400, 600, 1));
    try t.expectEqual(Weapon.stave, choose(500, 120, 600, 400, 2));
    try t.expectEqual(Weapon.summon, choose(700, 120, 400, 600, 1));
    try t.expectEqual(Weapon.summon, choose(500, 120, 600, 400, 0));
}
