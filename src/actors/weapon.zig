// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied attack tuning; class policies choose which authored weapon to use.
pub const Tuning = struct {
    damage: f32 = 0,
    random_damage: f32 = 0,
    range: f32 = 0,
    speed: f32 = 0,
    offset: [3]f32 = @splat(0),
    spread: [2]f32 = @splat(0),
    pub fn parse(row: anytype, comptime prefix: []const u8) !Tuning {
        var result: Tuning = .{ .damage = try row.number(prefix ++ "base_damage", 0), .random_damage = try row.number(prefix ++ "random_damage", 0), .range = try row.number(prefix ++ "distance", 0), .speed = try row.number(prefix ++ "speed", 0), .spread = .{ try row.number(prefix ++ "spread_x", 0), try row.number(prefix ++ "spread_z", 0) } };
        inline for (.{ "x", "y", "z" }, 0..) |axis, i| result.offset[i] = try row.number(prefix ++ "offset_" ++ axis, 0);
        if (result.damage <= 0 or result.damage > 1000000 or result.random_damage < 0 or result.random_damage > 1000000 or result.range <= 0 or result.range > 65536 or result.speed < 0 or result.speed > 65536) return error.InvalidActorWeaponTuning;
        for (result.offset) |axis| if (@abs(axis) > 1024) return error.InvalidActorWeaponOffset;
        for (result.spread) |axis| if (axis < 0 or axis > 8192) return error.InvalidActorWeaponSpread;
        return result;
    }
};
