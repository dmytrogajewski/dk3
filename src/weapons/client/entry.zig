// SPDX-License-Identifier: GPL-2.0-or-later
const r = @import("render.zig");
const c = r.c;
const registry = @import("../registry.zig");
const effects = @import("effects.zig");
var last_time: c_int = 0;
export fn DK_ResetWeaponPresentation() callconv(.c) void {
    previous_inventory = 0;
    last_time = 0;
    @import("view.zig").selected = 0;
    @import("view.zig").muzzle_weapon = 0;
    @import("particles.zig").reset();
    inline for (registry.weapons) |W| {
        effects.Effects(W).reset();
        if (@hasDecl(W, "resetClient")) W.resetClient();
    }
}
export fn DK_DrawViewWeapon(ps: [*c]c.playerState_t) callconv(.c) void {
    inline for (registry.weapons) |W| if (ps[0].weapon == W.id) {
        W.drawView(@ptrCast(ps));
        return;
    };
}
export fn DK_DrawPlayerWeapon(parent: [*c]c.refEntity_t, cent: [*c]c.centity_t) callconv(.c) void {
    inline for (registry.weapons) |W| if (cent[0].currentState.weapon == W.id) {
        W.drawWorld(@ptrCast(parent), @ptrCast(cent));
        return;
    };
}
export fn DK_DrawProjectile(cent: [*c]c.centity_t) callconv(.c) void {
    inline for (registry.weapons) |W| if (cent[0].currentState.weapon == W.id) {
        W.drawProjectile(@ptrCast(cent));
        return;
    };
}
export fn DK_WeaponImpact(cent: [*c]c.centity_t) callconv(.c) void {
    inline for (registry.weapons) |W| if (cent[0].currentState.weapon == W.id) {
        W.drawImpact(@ptrCast(cent));
        return;
    };
}
export fn DK_WeaponFireSound(raw: [*c]c.centity_t) callconv(.c) void {
    const cent: *c.centity_t = @ptrCast(raw);
    // ioquake3 dispatches predictable events by event sequence. Distinct events
    // can arrive in one render frame; a timestamp filter would discard shots.
    if (r.now() < last_time) DK_ResetWeaponPresentation();
    last_time = r.now();
    inline for (registry.weapons) |W| if (cent.currentState.weapon == W.id) {
        W.fireSound(cent);
        return;
    };
}
export fn DK_CombatEffect(cent: [*c]c.centity_t, blast: c.qboolean) callconv(.c) void {
    inline for (registry.weapons) |W| if (cent[0].currentState.weapon == W.id) {
        effects.Effects(W).event(@ptrCast(cent), blast != 0);
        return;
    };
}
export fn DK_AddCombatEffects() callconv(.c) void {
    if (r.now() < last_time) DK_ResetWeaponPresentation();
    last_time = r.now();
    inline for (registry.weapons) |W| {
        if (@hasDecl(W, "clientFrame")) W.clientFrame();
        effects.Effects(W).frame();
    }
    @import("particles.zig").draw();
}
export fn DK_WeaponOverlay() callconv(.c) void {
    inline for (registry.weapons) |W| if (@hasDecl(W, "overlay")) W.overlay();
}
export fn DK_SelectWeapon(direction: c_int, requested: c_int) callconv(.c) void {
    if (c.cg.snap == null or (c.cg.snap[0].ps.pm_flags & c.PMF_FOLLOW) != 0) return;
    if (direction == 0) {
        if (c.DK_HasWeapon(&c.cg.snap[0].ps, requested) != 0) c.cg.weaponSelect = requested;
    } else {
        var weapon = c.cg.weaponSelect;
        for (0..c.DK_WEAPON_COUNT) |_| {
            weapon = @mod(weapon + direction, c.DK_WEAPON_COUNT);
            if (c.DK_HasWeapon(&c.cg.snap[0].ps, weapon) != 0) {
                c.cg.weaponSelect = weapon;
                break;
            }
        }
    }
    c.cg.weaponSelectTime = r.now();
}
export fn DK_OutOfAmmo() callconv(.c) void {
    if (c.cg.snap == null) return;
    var weapon: c_int = c.DK_W_FLASHLIGHT - 1;
    while (weapon > 0) : (weapon -= 1) {
        const index: usize = @intCast(weapon);
        const data = c.dk_weapons[index];
        if (c.DK_HasWeapon(&c.cg.snap[0].ps, weapon) != 0 and (data.ammoCost == 0 or c.cg.snap[0].ps.ammo[index] >= data.ammoCost)) {
            c.cg.weaponSelect = weapon;
            c.cg.weaponSelectTime = r.now();
            return;
        }
    }
}
var previous_inventory: c_uint = 0;
export fn DK_UpdateWeaponSelection() callconv(.c) void {
    const ps = &c.cg.predictedPlayerState;
    const current: c_uint = @bitCast(ps.dk3Inventory);
    var eligible: c_uint = 0;
    inline for (registry.weapons) |W| if (W.spec.auto_select) {
        eligible |= @as(c_uint, 1) << W.id;
    };
    const acquired = current & ~previous_inventory & eligible;
    if (previous_inventory == 0 or c.DK_HasWeapon(ps, c.cg.weaponSelect) == 0) c.cg.weaponSelect = ps.weapon else if (acquired != 0 and c.cg_autoswitch.integer != 0) {
        if ((acquired & (@as(c_uint, 1) << @as(u5, @intCast(ps.weapon)))) != 0) c.cg.weaponSelect = ps.weapon else {
            var chosen: c_int = 0;
            inline for (registry.weapons) |W| if (chosen == 0 and (acquired & (@as(c_uint, 1) << W.id)) != 0) {
                chosen = W.id;
            };
            c.cg.weaponSelect = chosen;
        }
        c.cg.weaponSelectTime = r.now();
    }
    previous_inventory = current;
}
