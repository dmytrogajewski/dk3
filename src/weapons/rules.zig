// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared weapon ownership, progression, and sword-combo rules.
const c = @import("abi.zig").c;

pub export fn DK_ExperienceThreshold(level: c_int) callconv(.c) c_int {
    if (level <= 0) return 0;
    const previous = level - 1;
    if (previous < 5) return @as(c_int, 500) << @intCast(previous);
    if (previous < 8) return (previous - 2) * 4000;
    if (previous < 24) return (previous - 3) * 5000;
    return 110000;
}

pub export fn DK_Attribute(ps: *const c.playerState_t, attribute: c_int, time: c_int) callconv(.c) c_int {
    if (attribute < 0 or attribute >= 5) return 0;
    const index: usize = @intCast(attribute);
    return @min(ps.dk3Attributes[index] + @as(c_int, @intFromBool(ps.dk3BoostUntil[index] > time)), 5);
}

pub export fn DK_FirstWeapon(episode: c_int) callconv(.c) c_int {
    inline for (@import("registry.zig").weapons) |W| if (W.spec.start_episode == episode) return W.id;
    return c.DK_W_DISRUPTOR;
}

pub export fn DK_HasWeapon(ps: *const c.playerState_t, weapon: c_int) callconv(.c) c.qboolean {
    if (weapon <= c.DK_W_NONE or weapon >= c.DK_WEAPON_COUNT) return c.qfalse;
    const inventory: u32 = @bitCast(ps.dk3Inventory);
    return if ((inventory & (@as(u32, 1) << @intCast(weapon))) != 0) c.qtrue else c.qfalse;
}
