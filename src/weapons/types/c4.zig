// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
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

const description = @import("../descriptions/c4.zig");
pub const id = c.DK_W_C4;
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

const chain_range = 200;
const blast_range = 300;
const trigger_range = 150;
const sense_range = 300;
const max_deployed = 4;

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}
const ChargeState = enum(c_int) { flying, attached, detonating };
fn phase(ent: *server.Entity) ChargeState {
    return @enumFromInt(ent.dk.action);
}
/// Gold sets think = c4Explode at a delay; the earliest schedule wins.
fn schedule(ent: *server.Entity, delay: c_int) void {
    const at = server.now() + delay;
    if (phase(ent) == .detonating and ent.dk.combatNext <= at) return;
    ent.dk.action = @intFromEnum(ChargeState.detonating);
    ent.dk.combatNext = at;
    ent.takedamage = c.qfalse;
}
fn charge(ent: *const server.Entity) bool {
    return ent.inuse != 0 and ent.dk.projectile != 0 and ent.s.weapon == id and ent.s.eType == c.ET_DK3_MISSILE;
}
pub fn die(raw: [*c]server.Entity, inflictor: [*c]server.Entity, _: [*c]server.Entity, _: c_int, _: c_int) callconv(.c) void {
    // Another charge's blast is handled by the chain reaction.
    if (inflictor != null and charge(@ptrCast(inflictor))) return;
    schedule(@ptrCast(raw), 0);
}
pub fn initializeProjectile(ent: *server.Entity) void {
    ent.health = 5;
    ent.takedamage = c.qtrue;
    ent.die = die;
    ent.r.contents = c.CONTENTS_CORPSE;
    ent.r.mins = @splat(-8);
    ent.r.maxs = @splat(8);
    ent.dk.actionTime = server.now() + 50;
    ent.dk.nextUse = server.now();
}
pub fn restore(ent: *server.Entity) void {
    ent.die = die;
    if (ent.s.pos.trType == c.TR_STATIONARY) ent.r.ownerNum = c.ENTITYNUM_NONE;
}
fn deployed(owner_id: c_uint) c_int {
    var count: c_int = 0;
    for (server.entities()) |*ent| count += @intFromBool(charge(ent) and ent.dk.ownerId == owner_id);
    return count;
}
fn detonateAll(owner_id: c_uint, staggered: bool) c_int {
    var count: c_int = 0;
    for (server.entities()) |*ent| {
        if (!charge(ent) or ent.dk.ownerId != owner_id) continue;
        count += 1;
        schedule(ent, if (staggered) 200 * count else 0);
    }
    return count;
}
pub fn detonate(owner: *server.Entity) c_int {
    return detonateAll(owner.dk.id, false);
}
/// Gold c4Explode: every charge within 200 goes off 0.1 s apart and each
/// adds 10% to this blast; a stuck charge has no owner to spare.
fn blow(ent: *server.Entity) void {
    var count: c_int = 1;
    for (server.entities()) |*other| {
        if (other == ent or !charge(other) or v.distance(other.r.currentOrigin, ent.r.currentOrigin) > chain_range) continue;
        schedule(other, 100 * count);
        count += 1;
    }
    const owner = server.find(ent.dk.ownerId);
    const amount = v.f(ent.damage) * (1 + 0.1 * v.f(count));
    ent.takedamage = c.qfalse;
    c.trap_UnlinkEntity(ent);
    server.blast(ent.r.currentOrigin, id);
    _ = server.splash(@This(), .{ .point = ent.r.currentOrigin, .inflictor = ent, .attacker = owner, .halved = if (phase(ent) == .flying) owner else null, .amount = amount, .range = blast_range, .ignore = ent });
    server.free(ent);
}
pub fn contact(hit: server.Contact) void {
    const ent = hit.ent;
    const victim = hit.victim();
    ent.r.currentOrigin = v.madd(hit.hit.endpos, 1, hit.hit.plane.normal);
    if (victim.takedamage != 0 or victim.client != null or victim.dk.actorKind != 0) return blow(ent);
    const surface = hit.hit.surfaceFlags;
    const sound = if ((surface & c.SURF_METALSTEPS) != 0) "e1/we_c4metala.wav" else if ((surface & c.SURF_DK_WOOD) != 0) "e1/we_c4wooda.wav" else "e1/we_c4cona.wav";
    var angles: v.Vec = undefined;
    c.vectoangles(&ent.s.pos.trDelta, &angles);
    angles[2] = @mod(v.f(server.now() - ent.s.time) * 1.44, 360);
    ent.s.angles = angles;
    server.stop(ent, ent.r.currentOrigin);
    if (phase(ent) != .detonating) ent.dk.action = @intFromEnum(ChargeState.attached);
    ent.dk.actionTime = server.now() + 1000;
    ent.r.ownerNum = c.ENTITYNUM_NONE;
    if (victim.s.eType == c.ET_MOVER) ent.dk.parentId = victim.dk.id;
    c.G_AddEvent(ent, c.EV_GENERAL_SOUND, c.DK_SoundIndex(sound));
    server.link(ent);
}
fn beep(ent: *server.Entity) void {
    c.G_AddEvent(ent, c.EV_GENERAL_SOUND, c.DK_SoundIndex("e1/we_c4beepa.wav"));
}
pub fn projectileTick(ent: *server.Entity) void {
    const now = server.now();
    if (phase(ent) == .detonating) {
        if (now >= ent.dk.combatNext) blow(ent);
        return;
    }
    if (now < ent.dk.actionTime) return;
    ent.dk.actionTime = now + 100;
    if (phase(ent) == .flying) {
        var velocity = server.velocity(ent);
        velocity[0] += (server.random(ent) - 0.5) * 80;
        velocity[1] += (server.random(ent) - 0.5) * 80;
        velocity[2] += (server.random(ent) - 0.5) * 20;
        server.steer(ent, velocity);
    }
    if (now > ent.dk.expires or deployed(ent.dk.ownerId) > max_deployed) {
        if (now > ent.dk.expires or server.random(ent) <= 0.05) {
            _ = detonateAll(ent.dk.ownerId, true);
            return;
        }
        beep(ent);
    }
    if (phase(ent) != .attached) return;
    var nearest: f32 = 4096;
    for (server.entities()) |*target| {
        if (target.inuse == 0 or target.health <= 0 or (target.client == null and target.dk.actorKind == 0) or (target.client != null and target.client[0].sess.sessionTeam == c.TEAM_SPECTATOR)) continue;
        const distance = v.distance(ent.r.currentOrigin, target.r.currentOrigin);
        if (distance > sense_range or distance >= nearest or c.CanDamage(target, &ent.r.currentOrigin) == 0) continue;
        nearest = distance;
    }
    if (nearest < trigger_range) return blow(ent);
    if (nearest >= sense_range) return;
    if (ent.dk.nextUse + v.i(nearest * 2) < now) {
        beep(ent);
        ent.s.time2 = now;
        ent.dk.nextUse = now;
    }
}

pub fn companionScore(score: f32, distance: f32, _: v.Vec, _: *server.Entity) f32 {
    return score * (if (distance < 180) @as(f32, 0.01) else 1);
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
    const state = &cent.currentState;
    var entity = std.mem.zeroes(c.refEntity_t);
    entity.reType = c.RT_MODEL;
    entity.hModel = c.DK_RegisterModel(spec.visual.projectile_model);
    entity.origin = cent.lerpOrigin;
    var angles = state.angles;
    if (state.pos.trType != c.TR_STATIONARY) {
        c.vectoangles(&state.pos.trDelta, &angles);
        angles[2] = @mod(v.f(render.now() - state.time) * 1.44, 360);
    }
    c.AnglesToAxis(&angles, &entity.axis);
    entity.shaderRGBA = @splat(255);
    c.trap_R_AddRefEntityToScene(&entity);
    // Gold EF2_C4_BEEP: a red blink toward the viewer on each beep.
    if (state.time2 > 0 and render.now() >= state.time2 and render.now() - state.time2 < 100) {
        const toward = v.normal(v.sub(c.cg.refdef.vieworg, cent.lerpOrigin));
        const point = v.madd(cent.lerpOrigin, 6, toward);
        render.light(point, 100, .{ 1, 0, 0 });
        _ = render.sprite("models/global/e_sflred.sp2", 0, point, v.zero, 0.8, 0.9, render.white, c.DK_SPRITE_ADDITIVE);
    }
}
/// Gold c4Select: choosing the C4 while holding it presses the detonator.
pub var button_at: c_int = 0;
pub fn reselect() void {
    c.trap_SendClientCommand("detonate");
    button_at = render.now();
}
pub fn viewAction(view: anytype, _: *c.playerState_t, _: c_int, _: bool) bool {
    if (button_at == 0) return false;
    button_at = 0;
    view.play("btnpsh", render.now(), 20);
    return true;
}
pub fn validProjectile(ent: *const server.Entity) bool {
    return ent.dk.action >= 0 and ent.dk.action <= 2;
}
