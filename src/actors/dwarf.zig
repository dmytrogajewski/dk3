// SPDX-License-Identifier: GPL-2.0-or-later
//! Dwarf combat choices and throwing-axe lifecycle. Numeric weapon tuning is supplied.
const std = @import("std");
pub const attacks = [_][]const u8{ "ataka", "atakc", "atakd" };
pub const axe_model = "models/e3/me_axe.dkm";
pub const flight_sound = "e3/m_dwaraxfly.wav";
pub const wall_sound = "global/m_bodyhitc.wav";
pub const flesh_sound = "global/e_bulfleshc.wav";
pub const axe_tag = 10001;
pub fn select(distance: f32, random: f32) u3 {
    if (distance <= 80) return 0;
    return if (distance > 100 and distance < 250 and random < 0.7) 1 else 2;
}
pub fn inRange(distance: f32, melee_range: f32, axe_range: f32, ranged_roll: f32, chase_roll: f32) bool {
    return distance < melee_range or (ranged_roll < 0.6 and distance < axe_range) or (distance > 100 and distance < 250 and chase_roll < 0.6);
}
pub const Tuning = struct {
    damage: f32 = 0,
    random_damage: f32 = 0,
    speed: f32 = 0,
    range: f32 = 0,
    offset: [3]f32 = @splat(0),
    pub fn parse(row: anytype) !Tuning {
        var value: Tuning = .{ .damage = try row.number("weapon2_base_damage", 0), .random_damage = try row.number("weapon2_random_damage", 0), .speed = try row.number("weapon2_speed", 0), .range = try row.number("weapon2_distance", 0) };
        inline for (.{ "x", "y", "z" }, 0..) |axis, i| value.offset[i] = try row.number("weapon2_offset_" ++ axis, 0);
        if (value.damage <= 0 or value.damage > 1000000 or value.random_damage < 0 or value.random_damage > 1000000 or value.speed <= 0 or value.speed > 65536 or value.range <= 0 or value.range > 65536) return error.InvalidDwarfTuning;
        for (value.offset) |axis| if (@abs(axis) > 1024) return error.InvalidDwarfOffset;
        return value;
    }
};
pub const Axe = struct {
    owner: u32,
    damage: f32,
    born_ms: i64,
    stepped_ms: i64,
    contact_ms: ?i64 = null,
    phase: enum { flying, falling, resting } = .flying,
};
test "dwarf distinguishes close chops, running chops and thrown axes" {
    const t = std.testing;
    try t.expectEqual(@as(u3, 0), select(80, 0.9));
    try t.expectEqual(@as(u3, 1), select(180, 0.69));
    try t.expectEqual(@as(u3, 2), select(180, 0.7));
    try t.expectEqual(@as(u3, 2), select(250, 0));
    try t.expect(inRange(79, 80, 500, 1, 1));
    try t.expect(!inRange(500, 80, 500, 0, 0));
}
