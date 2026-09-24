// SPDX-License-Identifier: GPL-2.0-or-later
//! Actor attacks share engine mechanisms without pretending to be player weapons.
const s = @import("combat.zig");
const c = s.c;
const v = s.v;
const entry = @import("entry.zig");
export fn DK_ZapFlare(point: [*c]const f32, sprite: [*c]const u8, scale: f32, duration: c_int) callconv(.c) void {
    const ent: *s.Entity = c.G_Spawn();
    ent.classname = @constCast("dk3_zap_flare");
    ent.s.eType = c.ET_DK3_EFFECT;
    ent.s.dk3Effect = c.DK_FX_FLAME;
    ent.s.dk3EffectFlags = c.DK_FX_ENABLED;
    ent.s.dk3EffectStart = s.now();
    ent.s.dk3EffectDuration = duration;
    ent.model = c.G_NewString(sprite);
    ent.s.modelindex = c.G_ModelIndex(ent.model);
    ent.s.dk3Scale = scale;
    ent.s.dk3Alpha = 1;
    ent.s.dk3RenderFlags = 2;
    s.origin(ent, point[0..3].*);
    ent.think = c.G_FreeEntity;
    ent.nextthink = s.now() + duration;
    s.link(ent);
}
export fn DK_DropToxicBomb(raw: [*c]s.Entity, target_raw: [*c]s.Entity, amount: c_int, phase: c_int) callconv(.c) void {
    const owner: *s.Entity = @ptrCast(raw);
    const target: *s.Entity = @ptrCast(target_raw);
    var start = owner.r.currentOrigin;
    start[2] -= 10;
    DK_ZapFlare(&start, "models/global/e_flyellow.sp2", 2, 700);
    start[2] -= 30;
    start = s.trace(owner.r.currentOrigin, start, owner.s.number, c.MASK_SOLID).endpos;
    const direction = v.normal(v.sub(target.r.currentOrigin, start));
    const bomb = entry.spawn(c.DK_W_VENOM, .{ .owner = owner, .start = start, .forward = direction }) orelse return;
    bomb.classname = @constCast("dk3_toxic_bomb");
    bomb.model = @constCast("models/global/e_flyellow.sp2");
    bomb.s.modelindex = c.G_ModelIndex(bomb.model);
    bomb.s.dk3Scale = 1.4;
    bomb.s.dk3Alpha = 0.45;
    bomb.s.dk3RenderFlags = 2;
    bomb.damage = amount;
    bomb.splashDamage = 0;
    bomb.clipmask = c.MASK_SOLID | c.CONTENTS_PLAYERCLIP;
    bomb.dk.expires = s.now() + 15000;
    bomb.dk.abilityState = phase;
    bomb.s.pos.trType = c.TR_LINEAR;
    bomb.s.pos.trDelta = v.scale(direction, 128 + 64 * s.random(owner));
    bomb.r.mins = @splat(-1);
    bomb.r.maxs = @splat(1);
    s.link(bomb);
}
fn lead(owner: *s.Entity, target: *s.Entity, point: v.Vec) v.Vec {
    inline for (.{ "monster_sludgeminion", "monster_rotworm", "monster_mishimaguard", "monster_medusa", "monster_inmater", "monster_deathsphere", "monster_cryotech", "monster_trackattack" }) |name| if (s.named(owner, name)) return point;
    var speed: f32 = if (target.client != null) v.length(target.client[0].ps.velocity) * 0.1 else 0;
    if (speed == 0) speed = 1;
    var angles: v.Vec = .{ 0, if (target.client != null) target.client[0].ps.viewangles[1] else target.s.angles[1], 0 };
    const skill = @max(0, @min(2, @divTrunc(c.trap_Cvar_VariableIntegerValue("g_spSkill") - 1, 2)));
    const err: f32 = if (skill == 0 and s.random(owner) > 0.25) 0.5 else if (skill == 1 and s.random(owner) > 0.25 and speed > 80) 3 else if (skill == 2 and s.random(owner) > 0.85 and speed > 100) 6 else 0;
    if (err != 0) {
        if (s.random(owner) > 0.5) speed = -speed;
        angles[1] += 30 / err + (s.random(owner) * 2 - 1) * 90 / err;
        angles[0] += 5 / err + (s.random(owner) * 2 - 1) * 10 / err;
    }
    return v.madd(point, speed, s.basis(angles).forward);
}
export fn DK_ActorStrike(raw: [*c]s.Entity, target_raw: [*c]s.Entity, weapon: c_int, offset_raw: [*c]const f32, initial_speed: f32, amount: c_int, range: f32, spread_x: f32, spread_z: f32) callconv(.c) void {
    if (target_raw == null or target_raw[0].inuse == 0 or target_raw[0].health <= 0 or amount <= 0) return;
    const owner: *s.Entity = @ptrCast(raw);
    const target: *s.Entity = @ptrCast(target_raw);
    const offset = offset_raw[0..3].*;
    const axes = s.basis(owner.s.angles);
    var start = v.madd(v.madd(v.madd(owner.r.currentOrigin, offset[0], axes.forward), offset[1], axes.right), offset[2], axes.up);
    if (v.dot(offset, offset) < 1) start[2] += owner.r.maxs[2] * 0.6;
    start = s.trace(owner.r.currentOrigin, start, owner.s.number, c.MASK_SHOT).endpos;
    var end = target.r.currentOrigin;
    end[2] += (target.r.mins[2] + target.r.maxs[2]) * 0.5;
    if (range > 160) end = lead(owner, target, end);
    var direction = v.normal(v.sub(end, start));
    direction = v.madd(direction, (s.random(owner) * 2 - 1) * spread_x / 8192, axes.right);
    direction = v.normal(v.madd(direction, (s.random(owner) * 2 - 1) * spread_z / 8192, axes.up));
    const speed = if (s.named(owner, "monster_cryotech")) 250 else initial_speed;
    if (speed <= 0) {
        const hit = s.trace(start, v.madd(start, range, direction), owner.s.number, c.MASK_SHOT);
        if (hit.entityNum < c.ENTITYNUM_WORLD) entry.damage(weapon, .{ .victim = &c.g_entities[@intCast(hit.entityNum)], .inflictor = owner, .owner = owner, .direction = direction, .point = hit.endpos, .amount = v.f(amount) });
        if (range > 160) s.beam(start, hit.endpos, weapon);
        return;
    }
    const ent = entry.spawn(weapon, .{ .owner = owner, .start = start, .forward = direction }) orelse return;
    ent.classname = @constCast("dk3_actor_projectile");
    if (s.named(owner, "monster_froginator") and weapon == c.DK_W_VENOM) {
        ent.model = @constCast("models/e1/me_sludge.dkm");
        ent.s.modelindex = c.G_ModelIndex(ent.model);
        ent.s.dk3Scale = 0.15;
        ent.s.dk3Alpha = 1;
        ent.r.mins = @splat(-3);
        ent.r.maxs = @splat(3);
    }
    ent.damage = amount;
    ent.splashDamage = if (weapon == c.DK_W_SIDEWINDER or weapon == c.DK_W_STAVROS) @divTrunc(amount, 2) else 0;
    ent.dk.expires = s.now() + 8000;
    ent.s.pos.trType = c.TR_LINEAR;
    ent.s.pos.trDelta = v.scale(direction, speed);
    if (s.named(owner, "monster_sludgeminion")) {
        ent.dk.monsterAttack = 1;
        ent.s.dk3Effect = c.DK_FX_SLUDGE;
        ent.model = @constCast("models/e1/me_sludge.dkm");
        ent.s.dk3Scale = 0.85;
        ent.s.apos.trType = c.TR_LINEAR;
        ent.s.apos.trTime = s.now();
        ent.s.apos.trDelta = .{ 0, 35, 35 };
        ent.dk.expires = s.now() + 3000;
    } else if (s.named(owner, "monster_cryotech")) {
        ent.dk.monsterAttack = 2;
        ent.s.dk3Effect = c.DK_FX_CRYO;
        ent.s.modelindex = 0;
        ent.dk.expires = s.now() + 800;
    } else if (s.named(owner, "monster_psyclaw")) {
        ent.dk.monsterAttack = 3;
        ent.s.dk3Effect = c.DK_FX_PSYCLAW;
        ent.model = @constCast("models/e1/me_psyclaw.dkm");
        ent.s.dk3Scale = 0.8;
        ent.s.dk3Alpha = 0.45;
        ent.s.apos.trType = c.TR_LINEAR;
        ent.s.apos.trTime = s.now();
        ent.s.apos.trDelta = .{ 0, 220, 160 };
    } else if (s.named(owner, "monster_deathsphere")) {
        ent.model = @constCast("models/e1/we_dsbolt.dkm");
        ent.s.modelindex = c.G_ModelIndex(ent.model);
        ent.s.dk3ModelScale = .{ 3, 1.5, 1.5 };
        ent.s.dk3Alpha = 0.7;
        ent.dk.expires = s.now() + 3000;
    }
    if (ent.dk.monsterAttack != 0 and ent.model != null and ent.dk.monsterAttack != 2) ent.s.modelindex = c.G_ModelIndex(ent.model);
    s.link(ent);
}
pub fn contact(ent: *s.Entity, hit: *const c.trace_t) bool {
    const owner = s.find(ent.dk.ownerId);
    if (s.named(ent, "dk3_toxic_bomb")) {
        const point = v.madd(hit.endpos, 2, hit.plane.normal);
        _ = c.G_RadiusDamage(@constCast(&point), owner orelse ent, 40, 256, ent, c.MOD_ROCKET_SPLASH);
        s.free(ent);
        return true;
    }
    if (ent.dk.monsterAttack == 0) return false;
    const victim = &c.g_entities[@intCast(hit.entityNum)];
    if (victim.takedamage != 0) {
        c.G_Damage(victim, ent, owner, &ent.s.pos.trDelta, @constCast(&hit.endpos), ent.damage, 0, c.MOD_UNKNOWN);
        if (ent.dk.monsterAttack == 3 and victim.client != null and victim.health > 0) victim.client[0].ps.dk3PsyEnd = s.now() + 8000;
    }
    ent.dk.uses += 1;
    if (ent.dk.monsterAttack == 1 and ent.dk.uses < 2) {
        s.reflect(ent, hit, 0.65);
        s.link(ent);
    } else s.free(ent);
    return true;
}
pub fn think(ent: *s.Entity) bool {
    if (s.named(ent, "dk3_toxic_bomb") or s.named(ent, "dk3_toxic_cloud")) {
        if (s.now() >= ent.dk.expires) {
            s.free(ent);
            return true;
        }
        if (s.named(ent, "dk3_toxic_bomb")) {
            const step = @divTrunc(s.now() - ent.s.time, 100);
            if (@mod(s.now(), 100) < s.tick_ms and s.now() - ent.s.time >= 200) {
                const angle = v.f(@mod(step, 13)) * 3.14159265 / 6;
                const wave = if (ent.dk.abilityState != 0) @sin(angle) else @cos(angle);
                var speed = s.velocity(ent);
                speed[0] += 10 * wave;
                speed[1] += 5 * wave;
                s.steer(ent, speed);
                if (step < 5) ent.s.dk3Scale = 1.4 - 0.25 * v.f(step) else {
                    const cycle = @mod(step - 5, 6);
                    ent.s.dk3Scale = 0.15 + 0.25 * v.f(if (cycle <= 3) cycle else 6 - cycle);
                    if (cycle == 3 and ent.dk.abilityState != 0) s.sound(ent, "global/e_warploopb.wav");
                }
            }
        }
        if (ent.dk.action == 1 and s.now() >= ent.dk.actionTime) {
            const owner = s.find(ent.dk.ownerId);
            for (s.entities()) |*target| {
                if (!s.hostile(owner, target) or v.distance(target.r.currentOrigin, ent.r.currentOrigin) > 96 or c.CanDamage(target, &ent.r.currentOrigin) == 0) continue;
                entry.damage(c.DK_W_VENOM, .{ .victim = target, .inflictor = ent, .owner = owner, .direction = v.zero, .point = target.r.currentOrigin, .amount = 2 });
            }
            ent.dk.actionTime = s.now() + 500;
        }
        return true;
    }
    if (ent.dk.monsterAttack == 0) return false;
    if (s.find(ent.dk.ownerId) == null or s.now() >= ent.dk.expires) {
        s.free(ent);
        return true;
    }
    if (ent.dk.monsterAttack == 3) ent.s.dk3Scale = 1.4 - 0.6 * @cos(v.f(s.now() - ent.s.time) * 0.005);
    return true;
}
