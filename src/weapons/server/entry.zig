// SPDX-License-Identifier: GPL-2.0-or-later
//! Thin native ABI entrypoints. Runtime IDs are resolved only at dispatch.
const s = @import("combat.zig");
const c = s.c;
const v = s.v;
const registry = @import("../registry.zig");
comptime {
    _ = @import("actors.zig");
    _ = @import("status.zig");
    _ = @import("inventory.zig");
}
pub fn projectileThink(raw: [*c]s.Entity) callconv(.c) void {
    const ent: *s.Entity = @ptrCast(raw);
    ent.nextthink = s.now() + s.tick_ms;
    if (@import("actors.zig").think(ent)) return;
    inline for (registry.weapons) |W| if (ent.s.weapon == W.id) {
        if (@hasDecl(W, "projectileTick")) W.projectileTick(ent) else s.free(ent);
        return;
    };
    s.free(ent);
}
export fn DK_ProjectileImpact(raw: [*c]s.Entity, trace: [*c]c.trace_t) callconv(.c) void {
    const ent: *s.Entity = @ptrCast(raw);
    const hit: *const c.trace_t = @ptrCast(trace);
    if ((hit.surfaceFlags & c.SURF_NOIMPACT) != 0) {
        s.free(ent);
        return;
    }
    if (@import("actors.zig").contact(ent, hit)) return;
    inline for (registry.weapons) |W| if (ent.s.weapon == W.id) {
        if (@hasDecl(W, "contact")) W.contact(.{ .ent = ent, .hit = hit }) else s.free(ent);
        return;
    };
    s.free(ent);
}
export fn DK_RestoreProjectile(raw: [*c]s.Entity) callconv(.c) void {
    const ent: *s.Entity = @ptrCast(raw);
    ent.think = projectileThink;
    ent.r.ownerNum = if (ent.parent != null) ent.parent[0].s.number else c.ENTITYNUM_NONE;
    inline for (registry.weapons) |W| if (ent.s.weapon == W.id) {
        if (W.spec.projectile.water_collision) ent.clipmask |= c.MASK_WATER;
        if (@hasDecl(W, "restore")) W.restore(ent);
        return;
    };
}
pub fn fire(weapon: c_int, shot: s.Fire) void {
    inline for (registry.weapons) |W| if (weapon == W.id) {
        W.fire(shot);
        return;
    };
}
pub fn spawn(weapon: c_int, shot: s.Fire) ?*s.Entity {
    inline for (registry.weapons) |W| if (weapon == W.id) return s.spawn(W, shot);
    return null;
}
pub fn damage(weapon: c_int, hit: s.Hit) void {
    inline for (registry.weapons) |W| if (weapon == W.id) {
        s.damage(W, hit);
        return;
    };
}
export fn DK_FireWeapon(raw: [*c]s.Entity) callconv(.c) void {
    const owner: *s.Entity = @ptrCast(raw);
    if (owner.client == null) return;
    const ps = &owner.client[0].ps;
    inline for (registry.weapons) |W| if (ps.weapon == W.id) {
        const data = s.info(W);
        const axes = s.basis(ps.viewangles);
        var eye = ps.origin;
        eye[2] += v.f(ps.viewheight);
        var start = eye;
        if (W.spec.projectile_muzzle) {
            start = v.madd(v.madd(eye, data.muzzle[1], axes.forward), data.muzzle[0], axes.right);
            start[2] += data.muzzle[2] - c.DEFAULT_VIEWHEIGHT;
        }
        start = s.trace(eye, start, owner.s.number, c.MASK_SHOT).endpos;
        const aim = s.trace(eye, v.madd(eye, 2000, axes.forward), owner.s.number, c.MASK_SHOT).endpos;
        const delta = v.sub(aim, start);
        const direction = if (v.dot(delta, axes.forward) > 1 and v.length(delta) > 0) v.normal(delta) else axes.forward;
        if (c.trap_Cvar_VariableIntegerValue("dk3_weaponTrace") != 0) c.G_Printf("dk3 weapon: fire %d owner %d sequence %d time %d\n", @as(c_int, W.id), owner.s.number, ps.dk3WeaponSequence, s.now());
        W.fire(.{ .owner = owner, .start = start, .forward = direction, .charge_ms = ps.dk3Charge });
        return;
    };
}
export fn DK_FireCompanionWeapon(raw: [*c]s.Entity, target_raw: [*c]s.Entity) callconv(.c) c_int {
    const owner: *s.Entity = @ptrCast(raw);
    const target: *s.Entity = @ptrCast(target_raw);
    var start = owner.r.currentOrigin;
    start[2] += owner.r.maxs[2] * 0.6;
    const distance = v.distance(owner.r.currentOrigin, target.r.currentOrigin);
    var best: f32 = -1;
    var chosen: c_int = 0;
    inline for (registry.weapons) |W| {
        const data = s.info(W);
        if ((@as(c_uint, @bitCast(owner.dk.inventory)) & (@as(c_uint, 1) << W.id)) != 0 and (data.ammoCost == 0 or owner.dk.ammunition[W.id] >= data.ammoCost) and (data.speed > 0 or distance <= data.range)) {
            var score = data.damage / (v.f(data.interval) + 1);
            if (@hasDecl(W, "companionScore")) score = W.companionScore(score, distance, start, owner);
            if (score > best and score >= 0) {
                best = score;
                chosen = W.id;
            }
        }
    }
    if (chosen == 0) return 0;
    owner.s.weapon = chosen;
    const index: usize = @intCast(chosen);
    owner.dk.ammunition[index] -= c.dk_weapons[index].ammoCost;
    var direction = v.sub(target.r.currentOrigin, start);
    direction[2] += target.r.maxs[2] * 0.5;
    fire(chosen, .{ .owner = owner, .start = start, .forward = v.normal(direction), .charge_ms = 1800 });
    return c.dk_weapons[index].interval;
}
export fn DK_DetonateCharges(owner: [*c]s.Entity) callconv(.c) c_int {
    return registry.C4.detonate(@ptrCast(owner));
}
export fn DK_WeaponSplash(weapon: c_int) callconv(.c) c.qboolean {
    inline for (registry.weapons) |W| if (weapon == W.id) return @intFromBool(W.spec.splash_hazard);
    return c.qfalse;
}
export fn DK_BotWeaponRange(weapon: c_int) callconv(.c) f32 {
    inline for (registry.weapons) |W| if (weapon == W.id) return W.spec.bot_range orelse s.info(W).range;
    return 0;
}
export fn DK_BotWeaponScore(raw: [*c]s.Entity, weapon: c_int, distance: f32) callconv(.c) f32 {
    const owner: *s.Entity = @ptrCast(raw);
    inline for (registry.weapons) |W| if (weapon == W.id) {
        const data = s.info(W);
        if (!W.spec.auto_select or c.DK_HasWeapon(&owner.client[0].ps, weapon) == 0 or (data.ammoCost != 0 and owner.client[0].ps.ammo[W.id] < data.ammoCost)) return -1;
        if (@hasDecl(W, "botUsable")) if (!W.botUsable(owner)) return -1;
        const scale = if (W.spec.bot_charge_ms > 0) v.f(W.spec.bot_charge_ms) / 1800 else 1;
        var score = data.damage * scale / (v.f(data.interval + W.spec.bot_charge_ms) + 1);
        if (DK_BotWeaponRange(weapon) < distance and data.speed <= 0) score *= 0.05;
        if (W.spec.splash_hazard and distance < 160) score *= 0.1;
        return score;
    };
    return -1;
}
export fn DK_BotWeaponAttack(ps: [*c]const c.playerState_t, weapon: c_int, ready: c.qboolean) callconv(.c) c.qboolean {
    inline for (registry.weapons) |W| if (weapon == W.id) {
        if (W.spec.bot_charge_ms > 0) return @intFromBool(!(ps[0].dk3AttackHeld != 0 and ps[0].dk3Charge >= W.spec.bot_charge_ms and ready != 0));
        return ready;
    };
    return c.qfalse;
}
export fn DK_WeaponKilled(victim: [*c]s.Entity, attacker: [*c]s.Entity, mod: c_int) callconv(.c) void {
    inline for (registry.weapons) |W| if (mod == c.DK_WEAPON_MOD(W.id)) {
        if (@hasDecl(W, "killed")) W.killed(@ptrCast(victim), attacker);
        return;
    };
}
export fn DK_WeaponControllerLimit(weapon: c_int) callconv(.c) c_int {
    inline for (registry.weapons) |W| if (weapon == W.id) return if (@hasDecl(W, "controller_limit")) W.controller_limit else 32;
    return 32;
}
export fn DK_ValidateWeaponEntity(raw: [*c]const s.Entity) callconv(.c) c.qboolean {
    const ent: *const s.Entity = @ptrCast(raw);
    if (ent.dk.projectile == 0) return c.qtrue;
    if (ent.dk.combatState < 0 or ent.dk.combatState > 10 or ent.dk.combatCount < 0 or ent.dk.combatCount > DK_WeaponControllerLimit(ent.s.weapon)) return c.qfalse;
    inline for (registry.weapons) |W| if (ent.s.weapon == W.id) {
        if (@hasDecl(W, "validProjectile")) return @intFromBool(W.validProjectile(ent));
        return c.qtrue;
    };
    return c.qfalse;
}
export fn DK_ScriptWeaponCommand(raw: [*c]s.Entity, command: [*c]const u8) callconv(.c) c.qboolean {
    const player: *s.Entity = @ptrCast(raw);
    if (player.client == null) return c.qfalse;
    var selected: c_int = 0;
    var recognized = false;
    inline for (registry.weapons) |W| if (@hasDecl(W, "script_command")) if (c.Q_stricmp(command, W.script_command) == 0) {
        selected = W.id;
        recognized = true;
    };
    if (c.Q_stricmpn(command, "weapon_select_", 14) == 0 and command[14] >= '1' and command[14] <= '6' and command[15] == 0) {
        var slot: c_int = command[14] - '0';
        var map: [c.MAX_QPATH]u8 = undefined;
        c.trap_Cvar_VariableStringBuffer("mapname", &map, map.len);
        const episode: c_int = if (map[0] == 'e') map[1] - '0' else 1;
        inline for (registry.weapons) |W| if (W.identity.episode == episode and slot > 0) {
            slot -= 1;
            if (slot == 0) selected = W.id;
        };
        recognized = true;
    }
    if (selected > 0 and c.DK_HasWeapon(&player.client[0].ps, selected) != 0) {
        player.client[0].ps.weapon = selected;
        c.trap_SendServerCommand(player.s.number, c.va(@constCast("dk3_weapon %d"), selected));
    }
    return @intFromBool(recognized);
}
export fn DK_WeaponSwordExperience(weapon: c_int, health: c_int) callconv(.c) c_int {
    inline for (registry.weapons) |W| if (weapon == W.id) {
        return if (@hasDecl(W, "swordExperience")) W.swordExperience(health) else 0;
    };
    return 0;
}
export fn DK_WeaponSlaysRevenants(weapon: c_int) callconv(.c) c.qboolean {
    inline for (registry.weapons) |W| if (weapon == W.id) return @intFromBool(@hasDecl(W, "slays_revenants"));
    return c.qfalse;
}
