// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied numeric weapon tuning is validated once for both runtime adapters.
const std = @import("std");
pub const Values = struct {
    ammoMax: i32 = 0,
    ammoCost: i32 = 0,
    initialAmmo: i32 = 0,
    damage: f32 = 0,
    range: f32 = 0,
    speed: f32 = 0,
    lifetime: f32 = 0,
    muzzle: [3]f32 = .{ 8, 12, 0 },
    cube_charges: i32 = 120,
    cube_health: i32 = 1000,
    cube_lifetime_ms: i32 = 60000,
};
pub fn parse(id: u5, row: anytype) !Values {
    var result: Values = .{};
    inline for (.{ .{ "ammoMax", "ammo_max" }, .{ "ammoCost", "ammo_per_use" }, .{ "initialAmmo", "initial_ammo" } }) |field| {
        const value = try row.number(field[1], 0);
        if (!std.math.isFinite(value) or value < 0 or value > 32767) return error.InvalidWeaponAmmo;
        @field(result, field[0]) = @intFromFloat(value);
    }
    if (result.initialAmmo > result.ammoMax) return error.InvalidWeaponAmmo;
    inline for (.{ "damage", "range", "speed", "lifetime" }) |field| {
        const value = try row.number(field, 0);
        if (!std.math.isFinite(value) or value < 0) return error.InvalidWeaponValue;
        @field(result, field) = value;
    }
    inline for (.{ "x", "y", "z" }, 0..) |axis, i| {
        const fallback: f32 = if (id == 26) ([_]f32{ 6, 18, 19 })[i] else try row.number("projectile_" ++ axis, ([_]f32{ 8, 12, 0 })[i]);
        result.muzzle[i] = try row.number("projectile_" ++ axis ++ "1", fallback);
        if (!std.math.isFinite(result.muzzle[i])) return error.InvalidWeaponMuzzle;
    }
    if (id == 26) {
        const charges = try row.number("projectile_x2", 120);
        const health = try row.number("projectile_y2", 1000);
        const lifetime = try row.number("projectile_z2", 60);
        if (!std.math.isFinite(charges) or charges < 1 or charges > 120 or !std.math.isFinite(health) or health < 1 or health > 32767 or !std.math.isFinite(lifetime) or lifetime <= 0 or lifetime > 3600) return error.InvalidCube;
        result.cube_charges = @intFromFloat(charges);
        result.cube_health = @intFromFloat(health);
        result.cube_lifetime_ms = @intFromFloat(lifetime * 1000);
    }
    return result;
}
