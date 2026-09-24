// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const abi = @import("abi.zig");
const c = abi.c;
const registry = @import("registry.zig");
export var dk_weapons: [c.DK_WEAPON_COUNT]c.dkWeaponInfo_t = blk: {
    var result = std.mem.zeroes([c.DK_WEAPON_COUNT]c.dkWeaponInfo_t);
    result[0].classname = "";
    result[0].label = "Unarmed";
    for (registry.weapons) |W| {
        result[W.id].classname = W.identity.classname;
        result[W.id].label = W.identity.label;
        result[W.id].episode = W.identity.episode;
        result[W.id].interval = W.identity.interval;
    }
    break :blk result;
};
export fn DK_WeaponId(name: [*c]const u8) callconv(.c) c_int {
    if (name == null) return 0;
    if (c.Q_stricmp(name, "weapon_c4viz") == 0) return c.DK_W_C4;
    inline for (registry.weapons) |W| if (c.Q_stricmp(name, W.identity.classname) == 0) return W.id;
    return 0;
}
fn failure(message: [*:0]const u8, name: [*c]const u8) noreturn {
    if (abi.side == .client) c.CG_Error(message, name) else c.G_Error(message, name);
    unreachable;
}
fn read(row: [*c]const c.dkRecord_t) callconv(.c) void {
    const name = c.DK_Field(row, "classname");
    const id = DK_WeaponId(name);
    if (id == 0) failure("dk3: unsupported weapon table class %s", name);
    const weapon = &dk_weapons[@intCast(id)];
    if (weapon.loaded != 0) failure("dk3: duplicate weapon table class %s", name);
    const ints = .{ .{ "ammoMax", "ammo_max" }, .{ "ammoCost", "ammo_per_use" }, .{ "initialAmmo", "initial_ammo" } };
    inline for (ints) |field| {
        const value = c.DK_Number(row, field[1], 0);
        if (!std.math.isFinite(value) or value < 0 or value > 32767) failure("dk3: invalid ammunition for %s", name);
        @field(weapon, field[0]) = @intFromFloat(value);
    }
    inline for (.{ "damage", "speed", "range", "lifetime" }) |field| {
        const value = c.DK_Number(row, field, 0);
        if (!std.math.isFinite(value) or value < 0) failure("dk3: invalid weapon value for %s", name);
        @field(weapon, field) = value;
    }
    inline for (.{ "x", "y", "z" }, 0..) |axis, index| {
        weapon.muzzle[index] = c.DK_Number(row, "projectile_" ++ axis ++ "1", c.DK_Number(row, "projectile_" ++ axis, .{ 8, 12, 0 }[index]));
        if (!std.math.isFinite(weapon.muzzle[index])) failure("dk3: invalid muzzle for %s", name);
    }
    if (weapon.initialAmmo > weapon.ammoMax) failure("dk3: invalid initial ammunition for %s", name);
    var model: [*c]const u8 = "";
    inline for (registry.weapons) |W| if (id == W.id) {
        model = W.spec.animation.view_model.ptr;
    };
    c.Q_strncpyz(&weapon.model, if (model != null) model else "", weapon.model.len);
    weapon.loaded = c.qtrue;
}
export fn DK_LoadWeaponData() callconv(.c) void {
    for (&dk_weapons) |*weapon| weapon.loaded = c.qfalse;
    c.DK_ReadTable("weapons", read);
    for (dk_weapons[1..c.DK_W_FLASHLIGHT]) |weapon| if (weapon.loaded == 0) failure("dk3: required weapon row missing: %s", weapon.classname);
}
export fn DK_AmmoWeapon(name: [*c]const u8) callconv(.c) c_int {
    if (name == null) return 0;
    inline for (registry.weapons) |W| if (W.spec.ammo_class) |classname| {
        if (c.Q_stricmp(name, classname) == 0) return W.id;
    };
    return 0;
}
export fn DK_AddAmmunition(ammo: [*c]c_int, weapon: c_int, rounds: c_int) callconv(.c) c.qboolean {
    if (weapon <= 0 or weapon >= c.DK_WEAPON_COUNT) return c.qfalse;
    const index: usize = @intCast(weapon);
    const data = dk_weapons[index];
    if (ammo[index] >= data.ammoMax) return c.qfalse;
    ammo[index] = @min(data.ammoMax, ammo[index] + @max(0, if (rounds > 0) rounds else data.initialAmmo));
    return c.qtrue;
}
