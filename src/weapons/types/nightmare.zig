// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../abi.zig").c;
const impact = @import("../impact.zig");
const shot_rules = @import("../shot.zig");
const d = @import("../definition.zig");
const AudioContext = d.AudioContext;
const pointer = d.pointer;
const basicView = d.basicView;
const basicAudio = d.basicAudio;
const v = @import("../vector.zig");
const server = @import("../server/combat.zig");

const description = @import("../descriptions/nightmare.zig");
pub const id = c.DK_W_NIGHTMARE;
comptime {
    if (id != description.id) @compileError("weapon transport ID mismatch");
}
pub const spec = description.spec;
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return description.predictionShot(controller);
}
pub fn update(controller: anytype) void {
    description.update(controller);
}

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

pub fn impactCue(context: impact.Context) impact.Cue {
    return impact.none(context);
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = description.identity;
const Incantation = enum(c_int) { start, marking, reaping };
pub fn fire(shot: server.Fire) void {
    _ = server.controller(@This(), shot.owner, shot.start, .nightmare, 60000);
}
fn mark(ent: *server.Entity, target: *server.Entity, model: [:0]const u8, lifetime: c_int) *server.Entity {
    const effect = server.controller(@This(), server.find(ent.dk.ownerId), target.r.currentOrigin, .stuck, lifetime);
    effect.model = c.G_NewString(model);
    effect.s.modelindex = c.G_ModelIndex(effect.model);
    effect.s.eType = c.ET_DK3_MISSILE;
    effect.r.svFlags &= ~@as(c_int, c.SVF_NOCLIENT);
    effect.dk.destinationId = @bitCast(target.dk.id);
    effect.s.dk3Scale = 1;
    effect.s.dk3Alpha = 1;
    effect.s.otherEntityNum = target.s.number;
    server.link(effect);
    return effect;
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.stuck(ent)) return;
    const owner = server.find(ent.dk.ownerId) orelse {
        server.free(ent);
        return;
    };
    if (owner.health <= 0 or server.now() >= ent.dk.expires) {
        finish(ent, owner);
        return;
    }
    const pentagram = "models/e3/we_nnpent.dkm";
    const phase: Incantation = @enumFromInt(ent.dk.action);
    if (phase == .start) {
        ent.dk.action = @intFromEnum(Incantation.marking);
        if (owner.client != null) {
            const boost = c.DK_Attribute(&owner.client[0].ps, 1, server.now());
            const pent = mark(ent, owner, pentagram, 10000);
            pent.s.dk3AnimationRate = if (boost != 0) v.i(10 * (v.f(boost) + (if (boost == 1) @as(f32, 1.5) else 1))) else 20;
            ent.dk.weaponParentId = pent.dk.id;
        }
        ent.dk.combatNext = server.now() + 3100;
        return;
    }
    if (phase == .marking) {
        if (server.now() < ent.dk.combatNext) return;
        ent.dk.action = @intFromEnum(Incantation.reaping);
        var found = false;
        for (server.entities()) |*target| {
            if (!server.creatureTarget(owner, target) or v.distance(target.r.currentOrigin, ent.r.currentOrigin) > server.info(@This()).range or c.CanDamage(target, &owner.r.currentOrigin) == 0) continue;
            found = true;
            if (server.named(target, "monster_garroth") or ent.dk.combatCount >= 10) continue;
            server.remember(ent, target);
            if (target.client != null) mark(ent, target, pentagram, 11500).s.dk3AnimationRate = 66;
        }
        if (!found) server.remember(ent, owner);
        if (server.find(ent.dk.weaponParentId)) |pent| {
            pent.s.generic1 = if (found) 1 else 2;
            pent.dk.expires = server.now() + @as(c_int, if (found) 2000 else 4000);
        }
        ent.dk.combatNext = server.now() + (if (c.g_gametype.integer == c.GT_SINGLE_PLAYER) @as(c_int, 500) else 1500);
    }
    if (server.now() < ent.dk.combatNext) return;
    if (ent.dk.uses >= ent.dk.combatCount) {
        finish(ent, owner);
        return;
    }
    const target = server.find(ent.dk.combatTargets[@intCast(ent.dk.uses)]);
    if (target == null or target.?.health <= 0 or target.?.takedamage == 0 or server.named(target.?, "monster_garroth")) {
        ent.dk.uses += 1;
        ent.dk.abilityState = 0;
        return;
    }
    const victim = target.?;
    if (ent.dk.abilityState == 0) {
        ent.dk.abilityState = 1;
        var point = victim.r.currentOrigin;
        for (0..8) |step| {
            const angle = v.f(step) * 3.14159265 / 4;
            const goal = v.add(victim.r.currentOrigin, .{ @cos(angle) * 100, @sin(angle) * 100, 0 });
            const sight = server.trace(victim.r.currentOrigin, goal, victim.s.number, c.MASK_SOLID);
            if (sight.fraction == 1) {
                point = goal;
                break;
            }
        }
        const reaper = mark(ent, victim, "models/e3/we_nnreaper.dkm", 5000);
        reaper.dk.destinationId = 0;
        server.origin(reaper, point);
        reaper.s.time = server.now() + 500;
        const facing = v.sub(victim.r.currentOrigin, point);
        c.vectoangles(&facing, &reaper.s.angles);
        server.link(reaper);
        ent.dk.destinationId = @bitCast(reaper.dk.id);
        victim.dk.weaponHoldUntil = server.now() + 4750;
        server.sound(reaper, "e3/we_reaperappear2.wav");
        server.sound(reaper, "e3/we_nharrewind.wav");
        ent.dk.combatNext = server.now() + 4750;
        return;
    }
    victim.dk.weaponHoldUntil = 0;
    const reaper = server.find(ent.dk.destinationId);
    const point = if (reaper) |actor| actor.r.currentOrigin else ent.r.currentOrigin;
    var origin = point;
    origin[2] -= 24;
    const direction = v.normal(v.sub(victim.r.currentOrigin, origin));
    if (victim.client != null) victim.client[0].ps.velocity = v.scale(direction, 1500);
    server.sound(if (reaper) |actor| actor else ent, "e3/we_reaperattack2.wav");
    server.damage(@This(), .{ .victim = victim, .inflictor = ent, .owner = owner, .direction = direction, .point = victim.r.currentOrigin, .amount = v.f(ent.damage), .inertial = true });
    ent.dk.uses += 1;
    ent.dk.abilityState = 0;
    ent.dk.combatNext = server.now() + 250;
}
fn finish(ent: *server.Entity, owner: *server.Entity) void {
    for (ent.dk.combatTargets[0..@intCast(@max(0, @min(ent.dk.combatCount, 10)))]) |target_id| {
        if (server.find(target_id)) |target| target.dk.weaponHoldUntil = 0;
    }
    if (owner.client != null and owner.client[0].ps.weapon == id) owner.client[0].ps.weaponTime = 100;
    server.free(ent);
}

const render = @import("../client/render.zig");
pub fn drawView(ps: *c.playerState_t) void {
    @import("../client/view.zig").draw(@This(), ps);
}
pub fn drawWorld(parent: *c.refEntity_t, cent: *c.centity_t) void {
    @import("../client/view.zig").world(@This(), parent, cent);
}
pub fn fireSound(cent: *c.centity_t) void {
    render.fired(@This(), cent);
}
pub fn drawImpact(cent: *c.centity_t) void {
    render.impact(@This(), cent);
}
var flash_time: c_int = 0;
pub fn resetClient() void {
    flash_time = 0;
}
pub fn overlay() void {
    if (flash_time == 0 or render.now() < flash_time or render.now() - flash_time >= 600) return;
    const tint = [4]f32{ 0.9, 0.6, 0.6, 0.6 * (1 - v.f(render.now() - flash_time) / 600) };
    c.trap_R_SetColor(&tint);
    c.trap_R_DrawStretchPic(0, 0, v.f(c.cgs.glconfig.vidWidth), v.f(c.cgs.glconfig.vidHeight), 0, 0, 1, 1, c.cgs.media.whiteShader);
    c.trap_R_SetColor(null);
}
pub fn projectileAnimation(cent: *c.centity_t, path: [*c]const u8, entity: *c.refEntity_t) void {
    if (cent.currentState.modelindex != 0) c.DK_ModelAnimation(path, if (c.strstr(path, "pent") != null) "pent" else "ataka", cent.currentState.time, c.qfalse, entity);
}
pub fn drawProjectile(cent: *c.centity_t) void {
    if (render.now() < cent.currentState.time) return;
    const path = if (cent.currentState.modelindex != 0) c.CG_ConfigString(c.CS_MODELS + cent.currentState.modelindex) else spec.visual.projectile_model.ptr;
    if (c.strstr(path, "we_nnpent") == null or c.cg.renderingThirdPerson != 0 or c.cg.snap == null or cent.currentState.otherEntityNum != c.cg.snap[0].ps.clientNum) {
        render.model(@This(), cent);
        return;
    }
    const std = @import("std");
    var entity = std.mem.zeroes(c.refEntity_t);
    entity.reType = c.RT_MODEL;
    entity.hModel = c.DK_RegisterModel(path);
    c.DK_ModelAnimationRate(path, "pent", cent.currentState.time, c.qfalse, if (cent.currentState.dk3AnimationRate > 0) cent.currentState.dk3AnimationRate else 20, &entity);
    entity.origin = v.madd(c.cg.refdef.vieworg, 13, c.cg.refdef.viewaxis[0]);
    entity.oldorigin = entity.origin;
    for (&entity.axis, 0..) |*axis, index| axis.* = v.scale(c.cg.refdef.viewaxis[index], 1.6);
    entity.nonNormalizedAxes = c.qtrue;
    entity.renderfx = c.RF_DEPTHHACK | c.RF_MINLIGHT | c.RF_FIRST_PERSON;
    entity.skinNum = 1;
    entity.shaderRGBA = .{ 255, 255, 255, render.byte(@max(0, @min(0.8, cent.currentState.dk3Alpha * 0.8))) };
    c.trap_R_AddRefEntityToScene(&entity);
    if (cent.currentState.generic1 == 1) render.light(entity.origin, 200, .{ 0.8, 0.4, 0.2 });
    if (cent.currentState.generic1 == 2 and cent.trailTime < cent.currentState.time) {
        cent.trailTime = render.now();
        flash_time = render.now();
    }
}
pub fn validProjectile(ent: *const server.Entity) bool {
    return ent.dk.action >= 0 and ent.dk.action <= 2 and ent.dk.uses >= 0 and ent.dk.uses <= ent.dk.combatCount;
}
