// SPDX-License-Identifier: GPL-2.0-or-later
const s = @import("combat.zig");
const c = s.c;
const v = s.v;
export fn DK_ModifyDamage(victim: [*c]s.Entity, attacker: [*c]s.Entity, amount: c_int) callconv(.c) c_int {
    if (s.named(@ptrCast(victim), "monster_kage") and victim[0].dk.abilityState == 1) return 0;
    if (victim[0].client == null or attacker == null) return amount;
    const status = victim[0].client[0].ps.dk3Status;
    inline for (.{ .{ 16, "monster_stavros" }, .{ 32, "monster_wyndrax" }, .{ 64, "monster_nharre" } }) |rule| {
        if ((status & rule[0]) != 0 and s.named(@ptrCast(attacker), rule[1])) return @divTrunc(amount + 3, 4);
    }
    return amount;
}
export fn DK_ColdWater(raw: [*c]s.Entity, protected: c.qboolean) callconv(.c) void {
    const ent: *s.Entity = @ptrCast(raw);
    if (protected != 0 or ent.client == null or ent.client[0].ps.dk3Episode != 3 or ent.waterlevel <= 0 or (ent.watertype & c.CONTENTS_WATER) == 0 or ent.health <= 0) {
        ent.dk.freezeStart = 0;
        return;
    }
    if (ent.dk.freezeStart == 0) ent.dk.freezeStart = s.now() + 4000;
    if (s.now() >= ent.dk.freezeStart and s.now() >= ent.dk.freezeNext) {
        ent.dk.freezeLevel = @min(1, ent.dk.freezeLevel + 0.15);
        if ((ent.dk.status & 4) == 0) ent.dk.statusOwnerId = 0;
        ent.dk.status |= 4;
    }
}
fn voice(ent: *s.Entity) [*:0]const u8 {
    var buffer: [c.MAX_INFO_STRING]u8 = undefined;
    c.trap_GetUserinfo(ent.s.number, &buffer, buffer.len);
    const model = c.Info_ValueForKey(&buffer, "model");
    return if (c.Q_stricmpn(model, "mikiko", 6) == 0) "mikiko" else if (c.Q_stricmpn(model, "superfly", 8) == 0) "superfly" else "hiro";
}
export fn DK_RunStatus() callconv(.c) void {
    for (s.entities()) |*ent| {
        if (ent.inuse == 0 or ent.dk.status == 0) continue;
        const owner = s.find(ent.dk.statusOwnerId);
        if (ent.health <= 0) {
            ent.dk.status = 0;
            ent.dk.freezeLevel = 0;
        }
        if ((ent.dk.status & 1) != 0) {
            if (s.now() >= ent.dk.poisonEnd) {
                ent.dk.status &= ~@as(c_int, 1);
                s.sound(ent, "global/a_poisonfade.wav");
                if (ent.client != null) c.trap_SendServerCommand(ent.s.number, "print \"Poison has worn off.\n\"");
            } else if (s.now() >= ent.dk.poisonNext) {
                ent.dk.poisonFraction += ent.dk.poisonDamage;
                const amount = v.i(ent.dk.poisonFraction);
                ent.dk.poisonFraction -= v.f(amount);
                if (amount > 0) c.G_Damage(ent, owner, owner, null, null, amount, c.DAMAGE_NO_KNOCKBACK, c.DK_WEAPON_MOD(c.DK_W_VENOM));
                ent.dk.poisonNext = s.now() + @as(c_int, if (ent.dk.poisonInterval > 0) ent.dk.poisonInterval else 1000);
            }
        }
        if ((ent.dk.status & 2) != 0) {
            if (s.now() >= ent.dk.burnEnd) ent.dk.status &= ~@as(c_int, 2) else if (s.now() >= ent.dk.burnNext) {
                c.G_Damage(ent, owner, owner, null, null, 6, c.DAMAGE_NO_KNOCKBACK, c.DK_WEAPON_MOD(c.DK_W_SUNFLARE));
                ent.dk.burnNext = s.now() + 1000;
            }
        }
        if ((ent.dk.status & 4) != 0) {
            if (s.now() >= ent.dk.freezeNext) {
                const before = ent.health;
                c.G_Damage(ent, owner, owner, null, null, v.i(@ceil(ent.dk.freezeLevel * 5)), c.DAMAGE_NO_ARMOR | c.DAMAGE_NO_KNOCKBACK, c.DK_WEAPON_MOD(c.DK_W_KINETICORE));
                if (ent.client != null and ent.health < before) c.G_Sound(ent, c.CHAN_AUTO, c.DK_SoundIndex(c.va(@constCast("%s/icehurt%d.wav"), voice(ent), @as(c_int, 1 + (@divTrunc(s.now(), 50) & 1)))));
                ent.dk.freezeNext = s.now() + 2000;
            }
            if (!(ent.client != null and ent.client[0].ps.dk3Episode == 3 and ent.waterlevel > 1)) ent.dk.freezeLevel -= 0.1 * v.f(c.level.time - c.level.previousTime) / 1000;
            if (ent.dk.freezeLevel <= 0) {
                ent.dk.freezeLevel = 0;
                ent.dk.status &= ~@as(c_int, 4);
            }
        }
        const frozen: c_int = if ((ent.dk.status & 4) != 0) (if (ent.dk.freezeLevel > 0.66) @as(c_int, 3) else if (ent.dk.freezeLevel > 0.33) @as(c_int, 2) else 1) << c.DK3_RF_FROZEN_SHIFT else 0;
        ent.s.dk3RenderFlags = (ent.s.dk3RenderFlags & ~@as(c_int, c.DK3_RF_FROZEN)) | frozen;
        if (ent.client != null) {
            ent.client[0].ps.dk3Status = (ent.client[0].ps.dk3Status & ~@as(c_int, 7)) | ent.dk.status;
            ent.client[0].ps.dk3FreezeLevel = ent.dk.freezeLevel;
        }
    }
}
