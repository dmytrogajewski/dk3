// SPDX-License-Identifier: GPL-2.0-or-later
//! Native weapon implementation shared by the game and prediction modules.
const registry = @import("registry.zig");
const movement = @import("movement.zig");
const rules = @import("rules.zig");
comptime {
    _ = rules;
    _ = @import("data.zig");
    _ = @import("types/sword_rules.zig");
    _ = registry.GasHands;
    _ = registry.Novabeam;
}
const c = @import("abi.zig").c;

fn pointer(value: ?[:0]const u8) [*c]const u8 {
    return if (value) |string| string.ptr else null;
}

export fn DK_WeaponSwitchTime(weapon: c_int, raising: c.qboolean) callconv(.c) c_int {
    return @import("controller.zig").switchTime(weapon, raising != 0);
}
export fn DK_WeaponWorldModel(weapon: c_int) callconv(.c) [*c]const u8 {
    inline for (registry.weapons) |W| if (weapon == W.id) return if (W.spec.world_model) |path| path.ptr else "";
    return "";
}

export fn DK_WeaponMoveZig(move: *c.pmove_t, msec: c_int) callconv(.c) void {
    movement.run(move, msec);
}

export fn DK_WeaponProtectsWater(weapon: c_int) callconv(.c) c.qboolean {
    inline for (registry.weapons) |W| if (weapon == W.id) return @intFromBool(W.spec.protects_water);
    return c.qfalse;
}
export fn DK_CompanionFirstWeapon(episode: c_int) callconv(.c) c_int {
    inline for (registry.weapons) |W| if (episode == W.spec.companion_episode) return W.id;
    return registry.Ion.id;
}
export fn DK_WeaponInventoryVisible(weapon: c_int) callconv(.c) c.qboolean {
    inline for (registry.weapons) |W| if (weapon == W.id) return @intFromBool(W.spec.auto_select);
    return c.qfalse;
}
export fn DK_WeaponInventoryModel(weapon: c_int) callconv(.c) [*c]const u8 {
    inline for (registry.weapons) |W| if (weapon == W.id) return if (W.spec.inventory_view_model) W.spec.animation.view_model.ptr else pointer(W.spec.world_model);
    return "";
}
export fn DK_WeaponInventoryText(ps: *const c.playerState_t, weapon: c_int, time: c_int, buffer: [*c]u8, size: c_int) callconv(.c) void {
    if (size <= 0) return;
    buffer[0] = 0;
    inline for (registry.weapons) |W| if (weapon == W.id) {
        if (@hasDecl(W, "inventoryText")) W.inventoryText(ps, time, buffer, size) else if (c.dk_weapons[W.id].ammoMax > 0) _ = c.Com_sprintf(buffer, size, "%d", ps.ammo[W.id]);
        return;
    };
}
export fn DK_ValidWeaponPlayer(ps: *const c.playerState_t, time: c_int) callconv(.c) c.qboolean {
    if (ps.dk3Burst < 0 or ps.dk3Burst > 6 or ps.dk3AttackHeld < 0 or ps.dk3AttackHeld > 1) return c.qfalse;
    inline for (registry.weapons) |W| if (@hasDecl(W, "validPlayer")) {
        if (!W.validPlayer(ps, time)) return c.qfalse;
    };
    return c.qtrue;
}
export fn DK_WeaponHudValue(ps: *const c.playerState_t, time: c_int) callconv(.c) c_int {
    inline for (registry.weapons) |W| if (ps.weapon == W.id) {
        if (@hasDecl(W, "hudValue")) return W.hudValue(ps, time);
        return if (c.dk_weapons[W.id].ammoMax > 0) @max(0, ps.ammo[W.id]) else 0;
    };
    return 0;
}
export fn DK_WeaponChangeEpisode(ps: *c.playerState_t, starting: *const c.playerState_t) callconv(.c) void {
    var carried: c_int = 0;
    inline for (registry.weapons) |W| {
        if (@hasDecl(W, "carry_between_episodes")) carried |= ps.dk3Inventory & (@as(c_int, 1) << W.id);
        if (@hasDecl(W, "changeEpisode")) W.changeEpisode(ps);
    }
    ps.dk3Inventory = starting.dk3Inventory | carried;
    ps.weapon = starting.weapon;
    ps.ammo = starting.ammo;
}
