// SPDX-License-Identifier: GPL-2.0-or-later
//! Inmater and Lasergat share the authored laser projectile, with distinct aiming.
pub const sprite = "models/e1/me_mater.sp2";
pub const muzzle_model = "models/e1/me_mater.dkm";
pub const render_tag = 10006;
pub const Tuning = struct {
    damage: f32 = 0,
    random_damage: f32 = 0,
    speed: f32 = 0,
    range: f32 = 0,
    offset: [3]f32 = @splat(0),
    spread: [2]f32 = @splat(0),
    pub fn parse(row: anytype, comptime prefix: []const u8) !Tuning {
        var result: Tuning = .{ .damage = try row.number(prefix ++ "base_damage", 0), .random_damage = try row.number(prefix ++ "random_damage", 0), .speed = try row.number(prefix ++ "speed", 0), .range = try row.number(prefix ++ "distance", 0), .spread = .{ try row.number(prefix ++ "spread_x", 0), try row.number(prefix ++ "spread_z", 0) } };
        inline for (.{ "x", "y", "z" }, 0..) |axis, i| result.offset[i] = try row.number(prefix ++ "offset_" ++ axis, 0);
        if (result.damage < 0 or result.damage > 1000000 or result.random_damage < 0 or result.random_damage > 1000000 or result.speed <= 0 or result.speed > 65536 or result.range <= 0 or result.range > 65536) return error.InvalidActorLaser;
        for (result.offset) |value| if (@abs(value) > 1024) return error.InvalidActorLaser;
        for (result.spread) |value| if (value < 0 or value > 8192) return error.InvalidActorLaser;
        return result;
    }
};
pub const State = struct { owner: u32, damage: f32, born_ms: i64, stepped_ms: i64, contact_ms: ?i64 = null, normal: [3]f32 = @splat(0), kind: enum { ordinary, death } = .ordinary, seed: u32 = 0 };
