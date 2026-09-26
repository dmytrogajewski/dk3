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

const description = @import("../descriptions/sidewinder.zig");
pub const id = c.DK_W_SIDEWINDER;
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
    return impact.scorch(context);
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = description.identity;

pub fn fire(shot: server.Fire) void {
    var launch = shot;
    if (shot.owner.client != null) {
        const ps = &shot.owner.client[0].ps;
        const axes = server.basis(ps.viewangles);
        var eye = ps.origin;
        eye[2] += v.f(ps.viewheight);
        const offset: v.Vec = if (shot.sequence() == 0) .{ 10, 10, 9 } else .{ 10, 8, 11 };
        launch.start = v.madd(v.madd(eye, offset[0], axes.right), offset[1], axes.forward);
        launch.start[2] += offset[2] - c.DEFAULT_VIEWHEIGHT;
        launch.start = server.trace(eye, launch.start, shot.owner.s.number, c.MASK_SHOT).endpos;
        const aim = server.trace(eye, v.madd(eye, 4000, axes.forward), shot.owner.s.number, c.MASK_SHOT).endpos;
        const delta = v.sub(aim, launch.start);
        launch.forward = if (v.dot(delta, axes.forward) > 1) v.normal(delta) else axes.forward;
        ps.velocity = v.madd(ps.velocity, -90, axes.forward);
    }
    const ent = server.spawn(@This(), launch);
    ent.r.mins = @splat(-2);
    ent.r.maxs = @splat(2);
    ent.s.dk3Scale = 1.5;
    ent.s.angles[2] = if (shot.sequence() == 0) 90 else 0;
    if (server.liquid(ent)) {
        ent.s.pos.trDelta = v.scale(ent.s.pos.trDelta, 1.0 / 3.0);
        ent.dk.abilityState = 1;
        ent.waterlevel = 1;
        ent.s.dk3EffectFlags = c.DK_FX_BUBBLE;
    }
    server.link(ent);
}
pub fn modifyHit(hit: *server.Hit) void {
    if (hit.victim == hit.owner and (hit.flags & c.DAMAGE_RADIUS) != 0) hit.amount *= 0.8;
}
pub fn contact(hit: server.Contact) void {
    server.ballisticContact(@This(), hit);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.expired(@This(), ent)) return;
    const wet = server.liquid(ent);
    ent.waterlevel = @intFromBool(wet);
    ent.s.dk3EffectFlags = if (wet) c.DK_FX_BUBBLE else 0;
    if (ent.dk.abilityState == 0 and v.distance(ent.r.currentOrigin, ent.dk.launchOrigin) >= 400) {
        server.steer(ent, v.scale(ent.s.pos.trDelta, 2));
        ent.dk.abilityState = 1;
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
    render.model(@This(), cent);
    render.light(cent.lerpOrigin, 200, spec.visual.color);
}
pub fn startShotPose(view: anytype, ps: *c.playerState_t, fired: c_int, reset: bool) void {
    if (ps.dk3WeaponSequence == 0 and (reset or view.shot != fired)) view.play(spec.animation.fire, render.now(), spec.animation.rate);
}
