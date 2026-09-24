// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../abi.zig").c;
const profiles = @import("../profiles.zig");
const impact = @import("../impact.zig");
const shot_rules = @import("../shot.zig");
const d = @import("../definition.zig");
const AudioContext = d.AudioContext;
const pointer = d.pointer;
const basicView = d.basicView;
const basicAudio = d.basicAudio;
const v = @import("../vector.zig");
const server = @import("../server/combat.zig");

pub const id = c.DK_W_SWORD;
pub const spec: profiles.Spec = .{
    .companion_pickup = false, // sword
    .world_model = "models/global/a_daikatana.dkm",
    .animation = .{
        .view_model = "models/global/w_daikatana.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "ataka",
        .idle = .{ "amba", null, null },
        .raise_ms = 600,
        .drop_ms = 500,
    },
};
pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (!controller.pressed() and ps.dk3Burst == 0) {
        ps.dk3AttackHeld = 0;
        if (ps.weaponTime <= 0) {
            if (((ps.dk3WeaponSequence >> 3) & 15) != 0) {
                ps.dk3WeaponSequence &= 7;
                const factor: f32 = 1 - 0.1 * @as(f32, @floatFromInt(controller.boost()));
                ps.weaponTime += @intFromFloat(500 * factor);
            }
            ps.weaponstate = c.WEAPON_READY;
            ps.dk3NovaSpent = 0;
        }
        return;
    }
    ps.dk3AttackHeld = @intFromBool(controller.pressed());
    if (ps.weaponTime <= 0) fireSwing(controller);
}
fn fireSwing(controller: anytype) void {
    const ps = controller.ps;
    const level = c.DK_SwordLevel(ps.dk3SwordExperience);
    const chain = (ps.dk3WeaponSequence >> 3) & 15;
    const previous = if (chain != 0) ps.dk3WeaponSequence & 7 else -1;
    const selected = if (chain >= 2 * level) -1 else c.DK_SwordSelect(previous, @bitCast(controller.move.cmd.serverTime));
    if (selected < 0) {
        ps.dk3WeaponSequence &= 7;
        ps.weaponstate = c.WEAPON_READY;
        const factor: f32 = 1 - 0.1 * @as(f32, @floatFromInt(controller.boost()));
        ps.weaponTime += @intFromFloat(1000 * factor);
        return;
    }
    ps.dk3WeaponSequence = selected | ((chain + 1) << 3);
    ps.weaponstate = c.WEAPON_FIRING;
    controller.fireEvent();
    const duration = c.dk_swordSwings[@intCast(selected)].followThrough * c.DK_SwordFrameTime(ps.dk3SwordExperience);
    ps.weaponTime += controller.scaled(duration);
}

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

pub fn viewCue(sequence: c_int, experience: c_int) d.ViewCue {
    var cue = basicView(spec);
    const selected: usize = @intCast(sequence & 7);
    if (selected < c.DK_SWORD_SWINGS and c.dk_swordSwings[selected].pose != null) {
        cue.pose = c.dk_swordSwings[selected].pose;
        cue.rate = @divTrunc(1000, c.DK_SwordFrameTime(experience));
    }
    return cue;
}
pub fn audioCue(context: AudioContext) d.AudioCue {
    const whoosh = [_][:0]const u8{ "global/we_swordwhoosha.wav", "global/we_swordwhooshb.wav", "global/we_swordwhooshc.wav", "global/we_swordwhooshd.wav", "global/we_swordwhooshe.wav", "global/we_swordwhooshf.wav" };
    return .{ .fire = pointer(whoosh[@intCast(@mod(@divTrunc(context.now, 7) + context.entity, 6))]), .extra = null };
}
pub fn impactCue(context: impact.Context) impact.Cue {
    const flesh = [_][:0]const u8{ "global/we_swordstaba.wav", "global/we_swordstabb.wav", "global/we_swordstabc.wav", "global/we_swordstabd.wav" };
    const solid = [_][:0]const u8{ "global/m_swordhita.wav", "global/m_swordhitb.wav", "global/m_swordhitc.wav", "global/m_swordhitd.wav", "global/m_swordhite.wav" };
    var cue = impact.none(context);
    cue.sound = if (context.kind == 1)
        pointer(flesh[@intCast(context.entity & 3)])
    else
        pointer(solid[@intCast(@mod(context.entity, 5))]);
    return cue;
}

pub const identity = .{ .classname = "weapon_daikatana", .label = "Daikatana", .episode = 0, .interval = 420 };
pub fn fire(shot: server.Fire) void {
    const index: usize = @intCast(shot.sequence() & 7);
    const selected = if (index < c.DK_SWORD_SWINGS) index else 0;
    const ent = server.controller(@This(), shot.owner, shot.start, .melee, 3000);
    ent.dk.action = @intCast(selected);
    ent.dk.delay = c.DK_SwordFrameTime(if (shot.owner.client != null) shot.owner.client[0].ps.dk3SwordExperience else 0);
    ent.dk.combatNext = server.now() + c.dk_swordSwings[selected].damageFrame[0] * ent.dk.delay;
}
pub fn modifyHit(hit: *server.Hit) void {
    inline for (.{ "monster_column", "monster_medusa", "monster_cerberus" }) |name| if (server.named(hit.victim, name)) {
        hit.amount = 0;
        return;
    };
    const owner = hit.owner orelse return;
    if (owner.client == null) return;
    var forward = server.basis(owner.client[0].ps.viewangles).forward;
    var facing = server.basis(if (hit.victim.client != null) hit.victim.client[0].ps.viewangles else hit.victim.s.angles).forward;
    forward[2] = 0;
    facing[2] = 0;
    const dot = v.dot(v.normal(forward), v.normal(facing));
    hit.amount += v.f((c.DK_SwordLevel(owner.client[0].ps.dk3SwordExperience) - 1) * 10);
    if (dot >= 0.85) hit.amount *= 2 else if (dot <= -0.85 and hit.victim.client != null and hit.victim.client[0].ps.weapon == id) {
        hit.amount *= 0.5;
        const sounds = [_][:0]const u8{ "global/we_swordwclanka.wav", "global/we_swordwclankb.wav", "global/we_swordwclankc.wav", "global/we_swordwclankd.wav", "global/we_swordwclanke.wav" };
        server.sound(owner, sounds[@intCast(@mod(server.now(), 5))]);
    }
}
fn swipe(owner: *server.Entity, from: v.Vec, to: v.Vec, amount: f32) void {
    var eye = owner.r.currentOrigin;
    eye[2] += if (owner.client != null) v.f(owner.client[0].ps.viewheight) else 24;
    const axes = server.basis(if (owner.client != null) owner.client[0].ps.viewangles else owner.s.angles);
    const range = server.info(@This()).range;
    if (v.length(from) < 0.01) {
        server.traceShot(@This(), .{ .owner = owner, .start = eye, .forward = axes.forward }, amount, range);
        return;
    }
    for (0..10) |step| {
        const distance = (0.01 + v.f(step) * 0.1) * range;
        const a = v.scale(v.normal(from), distance);
        const b = v.scale(v.normal(to), distance);
        const mid = v.scale(v.normal(v.add(a, b)), distance);
        var points: [3]v.Vec = undefined;
        for ([_]v.Vec{ a, mid, b }, 0..) |offset, index| points[index] = v.madd(v.madd(v.madd(eye, offset[0], axes.forward), offset[1], axes.right), offset[2], axes.up);
        for (0..2) |index| {
            const hit = server.trace(points[index], points[index + 1], owner.s.number, c.MASK_SHOT);
            if (hit.fraction >= 1) continue;
            _ = server.impact(@This(), &hit, hit.entityNum < c.ENTITYNUM_WORLD and c.g_entities[@intCast(hit.entityNum)].takedamage != 0);
            if (hit.entityNum < c.ENTITYNUM_WORLD) server.damage(@This(), .{ .victim = &c.g_entities[@intCast(hit.entityNum)], .inflictor = owner, .owner = owner, .direction = v.normal(v.sub(hit.endpos, eye)), .point = hit.endpos, .amount = amount });
            return;
        }
    }
}
pub fn projectileTick(ent: *server.Entity) void {
    const owner = server.find(ent.dk.ownerId) orelse {
        server.free(ent);
        return;
    };
    if (owner.health <= 0 or owner.client == null or owner.client[0].ps.weapon != id or server.now() >= ent.dk.expires) {
        server.free(ent);
        return;
    }
    if (ent.dk.action < 0 or ent.dk.action >= c.DK_SWORD_SWINGS) {
        server.free(ent);
        return;
    }
    const swing = &c.dk_swordSwings[@intCast(ent.dk.action)];
    if (server.now() < ent.dk.combatNext) return;
    if (ent.dk.uses < 0 or ent.dk.uses >= swing.hits) {
        server.free(ent);
        return;
    }
    const index: usize = @intCast(ent.dk.uses);
    swipe(owner, swing.from[index], swing.to[index], v.f(ent.damage));
    ent.dk.uses += 1;
    if (ent.dk.uses >= swing.hits) {
        server.free(ent);
        return;
    }
    ent.dk.combatNext = ent.s.time + swing.damageFrame[@intCast(ent.dk.uses)] * ent.dk.delay;
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
pub fn drawProjectile(cent: *c.centity_t) void {
    render.model(@This(), cent);
}
var level_seen: c_int = 0;
var level_time: c_int = 0;
var level_rings: c_int = 0;
var ring_sounds: u8 = 0;
pub fn resetClient() void {
    level_seen = 0;
    level_time = 0;
    level_rings = 0;
    ring_sounds = 0;
}
pub fn clientFrame() void {
    const std = @import("std");
    const ps = &c.cg.predictedPlayerState;
    const level = c.DK_SwordLevel(ps.dk3SwordExperience);
    if (level_seen != 0 and level > level_seen) {
        level_time = render.now();
        level_rings = level;
        ring_sounds = 0;
        c.trap_S_StartLocalSound(render.sound(if ((render.now() & 1) != 0) "global/we_dk_cnt_02.wav" else "global/we_dk_cnt_01.wav"), c.CHAN_ANNOUNCER);
    }
    level_seen = level;
    const ambience = [_]?[:0]const u8{ null, null, "global/we_dk_01.wav", "global/we_dk_02.wav", "global/we_dk_03a.wav", "global/we_dk_03a.wav" };
    if (ps.weapon == id and ps.stats[c.STAT_HEALTH] > 0 and level >= 0 and level < ambience.len) if (ambience[@intCast(level)]) |name| c.trap_S_AddLoopingSound(c.ENTITYNUM_NONE, &c.cg.predictedPlayerEntity.lerpOrigin, &v.zero, render.sound(name));
    var ring: c_int = 0;
    while (ring < level_rings) : (ring += 1) {
        const age = render.now() - level_time - ring * 500;
        if (age < 0 or age > 1500) continue;
        const bit = @as(u8, 1) << @as(u3, @intCast(ring));
        if ((ring_sounds & bit) == 0) {
            ring_sounds |= bit;
            render.worldSound(if ((ring & 1) != 0) "global/e_windb.wav" else "global/e_windc.wav", c.cg.predictedPlayerEntity.lerpOrigin);
        }
        var spread: f32 = undefined;
        var height: f32 = 0;
        if (age < 500) spread = 20 - 16.5 * v.f(age) / 500 else {
            spread = 3.5 - 1.8 * v.f(age - 500) / 1000;
            height = v.f(age - 500) / 50 * 4;
            if (height > 64) spread *= 0.65;
        }
        var entity = std.mem.zeroes(c.refEntity_t);
        entity.reType = c.RT_MODEL;
        entity.hModel = c.DK_RegisterModel("models/global/we_dklevel.dkm");
        entity.customShader = c.trap_R_RegisterShader("dk3/fx/dklevel");
        entity.origin = c.cg.predictedPlayerEntity.lerpOrigin;
        entity.origin[2] += c.MINS_Z + height;
        const angles: v.Vec = .{ -90, 0, v.f(age) * (0.5 + 0.25 * v.f(ring & 1)) };
        c.AnglesToAxis(&angles, &entity.axis);
        entity.axis[0] = v.scale(entity.axis[0], 3);
        entity.axis[1] = v.scale(entity.axis[1], spread);
        entity.axis[2] = v.scale(entity.axis[2], spread);
        entity.nonNormalizedAxes = c.qtrue;
        entity.shaderRGBA = .{ 26, 26, 204, render.byte(@max(0.5, @min(0.8, 0.5 + v.f(age) * 0.0006))) };
        c.trap_R_AddRefEntityToScene(&entity);
    }
}

pub fn killed(victim: *server.Entity, attacker: ?*server.Entity) void {
    if (attacker) |owner| if (owner != victim and owner.client != null and victim.client != null) c.DK_AwardExperience(owner, 0, 50 * (victim.client[0].ps.dk3Level + 1));
}

comptime {
    _ = @import("sword_rules.zig");
}
pub fn validProjectile(ent: *const server.Entity) bool {
    if (ent.dk.action < 0 or ent.dk.action >= c.DK_SWORD_SWINGS) return false;
    return ent.dk.uses >= 0 and ent.dk.uses < c.dk_swordSwings[@intCast(ent.dk.action)].hits;
}
pub const script_command = "s_daikatana";
pub const carry_between_episodes = true;
pub fn swordExperience(health: c_int) c_int {
    return @divTrunc(health, 20);
}
