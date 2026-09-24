// SPDX-License-Identifier: GPL-2.0-or-later
const s = @import("combat.zig");
const c = s.c;
const registry = @import("../registry.zig");
export fn DK_AddWeapon(inventory: [*c]c_int, ammo: [*c]c_int, selected: [*c]c_int, weapon: c_int, rounds: c_int) callconv(.c) c.qboolean {
    inline for (registry.weapons) |W| if (weapon == W.id) {
        const data = s.info(W);
        const mask = @as(c_int, 1) << W.id;
        const owned = (inventory[0] & mask) != 0;
        if (owned and (data.ammoMax == 0 or ammo[W.id] >= data.ammoMax)) return c.qfalse;
        inventory[0] |= mask;
        ammo[W.id] = @min(data.ammoMax, ammo[W.id] + @max(0, rounds));
        if (!owned and W.spec.auto_select) selected[0] = W.id;
        if (@hasDecl(W, "acquired")) W.acquired(inventory, ammo);
        return c.qtrue;
    };
    return c.qfalse;
}
export fn DK_GiveWeapon(raw: [*c]s.Entity, weapon: c_int, rounds: c_int) callconv(.c) c.qboolean {
    const player: *s.Entity = @ptrCast(raw);
    if (player.client == null) return c.qfalse;
    inline for (registry.weapons) |W| if (weapon == W.id) {
        if (@hasDecl(W, "pickup")) if (W.pickup(player)) |result| return @intFromBool(result);
        const ps = &player.client[0].ps;
        return DK_AddWeapon(&ps.dk3Inventory, &ps.ammo, &ps.weapon, weapon, rounds);
    };
    return c.qfalse;
}
export fn DK_RunItemEffects() callconv(.c) void {
    for (s.entities()[0..@intCast(c.level.maxclients)]) |*player| {
        if (player.inuse == 0 or player.client == null) continue;
        inline for (registry.weapons) |W| if (@hasDecl(W, "inventoryTick")) W.inventoryTick(player);
    }
}
export fn DK_PlayerWeaponLoop(raw: [*c]s.Entity) callconv(.c) c_int {
    const player: *s.Entity = @ptrCast(raw);
    if (player.client == null) return 0;
    inline for (registry.weapons) |W| if (player.client[0].ps.weapon == W.id) {
        if (@hasDecl(W, "loopSound")) return W.loopSound(player);
        return 0;
    };
    return 0;
}
export fn DK_StartingInventory(raw: [*c]s.Entity) callconv(.c) void {
    const player: *s.Entity = @ptrCast(raw);
    var map: [c.MAX_QPATH]u8 = undefined;
    c.trap_Cvar_VariableStringBuffer("mapname", &map, map.len);
    const episode: c_int = if (map[0] == 'e' and map[1] >= '1' and map[1] <= '4') map[1] - '0' else 1;
    const ps = &player.client[0].ps;
    const initial = c.DK_FirstWeapon(episode);
    player.health = ps.stats[c.STAT_MAX_HEALTH];
    ps.stats[c.STAT_HEALTH] = player.health;
    ps.dk3Inventory = 0;
    ps.stats[c.STAT_ARMOR] = 0;
    ps.dk3ArmorAbsorption = 0;
    ps.ammo = @splat(0);
    inline for (registry.weapons) |W| if (@hasDecl(W, "initializePlayer")) W.initializePlayer(@ptrCast(ps));
    _ = DK_GiveWeapon(player, initial, c.dk_weapons[@intCast(initial)].initialAmmo);
    ps.weapon = initial;
    ps.stats[c.STAT_WEAPONS] = 0;
    ps.dk3Level = 1;
    ps.dk3Episode = episode;
    ps.dk3SoundEnvironment = 0;
    ps.dk3Reverb = 0;
    ps.dk3SoundGain = 1;
}
export fn DK_DropInventory(raw: [*c]s.Entity) callconv(.c) void {
    const player: *s.Entity = @ptrCast(raw);
    c.DK_DropObjective(player);
    if (c.g_gametype.integer == c.GT_SINGLE_PLAYER or player.client == null) return;
    const ps = &player.client[0].ps;
    inline for (registry.weapons) |W| if (ps.weapon == W.id) {
        if (!W.spec.droppable or s.info(W).ammoMax == 0 or ps.ammo[W.id] <= 0) return;
        const item: *s.Entity = c.G_Spawn();
        item.classname = c.G_NewString(W.identity.classname);
        item.count = ps.ammo[W.id];
        item.s.origin = player.r.currentOrigin;
        if (c.DK_SpawnItem(item) == 0) {
            s.free(item);
            return;
        }
        item.dk.expires = s.now() + 30000;
        item.think = c.G_FreeEntity;
        item.nextthink = item.dk.expires;
        return;
    };
}
export fn DK_CompanionWeaponValue(raw: [*c]s.Entity, weapon: c_int) callconv(.c) f32 {
    const actor: *s.Entity = @ptrCast(raw);
    inline for (registry.weapons) |W| if (weapon == W.id) {
        if (!W.spec.companion_pickup) return 0;
        if ((actor.dk.inventory & (@as(c_int, 1) << W.id)) == 0) return 300;
        return if (actor.dk.ammunition[W.id] < s.info(W).ammoMax) 60 else 0;
    };
    return 0;
}
export fn DK_RestoreWeaponItem(raw: [*c]s.Entity) callconv(.c) void {
    const ent: *s.Entity = @ptrCast(raw);
    const weapon = c.DK_WeaponId(ent.classname);
    const ammo = c.DK_AmmoWeapon(ent.classname);
    inline for (registry.weapons) |W| {
        var old: [*c]const u8 = null;
        if (weapon == W.id) {
            if (W.spec.ammo_class) |name| old = c.va(@constCast("models/%s.dkm"), c.DK_ItemModelName(name));
            if (@hasDecl(W, "obsolete_pickup_model")) old = W.obsolete_pickup_model;
        }
        if (ammo == W.id) old = c.DK_WeaponWorldModel(W.id);
        if (old != null and ent.model != null and c.Q_stricmp(ent.model, old) == 0) {
            ent.model = c.DK_ItemModel(ent.classname);
            ent.s.modelindex = c.G_ModelIndex(ent.model);
            return;
        }
    }
}
export fn DK_GiveAllWeapons(raw: [*c]s.Entity) callconv(.c) void {
    const player: *s.Entity = @ptrCast(raw);
    if (player.client == null) return;
    const selected = player.client[0].ps.weapon;
    inline for (registry.weapons) |W| _ = DK_GiveWeapon(player, W.id, 0);
    player.client[0].ps.weapon = selected;
}
