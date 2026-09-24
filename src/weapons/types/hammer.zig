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

pub const id = c.DK_W_HAMMER;
pub const spec: profiles.Spec = .{
    .bot_charge_ms = 900,
    .bot_range = 110,
    .start_episode = 2, // hammer
    .visual = .{},
    .world_model = "models/e2/a_hammer.dkm",
    .animation = .{
        .view_model = "models/e2/w_hammer.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .raise_ms = 300,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e2/we_hammerd.wav",
        .ready = "e2/we_hammerready.wav",
        .away = "e2/we_hammeraway.wav",
    },
};
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}
pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (controller.pressed()) {
        if (ps.dk3AttackHeld == 0) ps.dk3Charge = 0;
        ps.dk3Charge = @min(ps.dk3Charge + controller.msec, 1800);
        ps.dk3AttackHeld = 1;
        return;
    }
    if (ps.dk3AttackHeld == 0) return;
    ps.dk3AttackHeld = 0;
    if (ps.weaponTime <= 0) controller.fire(@This(), predictionShot(controller));
}

pub fn blastSound(entity: c_int) [*c]const u8 {
    const impacts = [_][:0]const u8{ "global/e_explodea.wav", "global/e_exploded.wav", "global/e_explodee.wav", "global/e_explodef.wav", "global/e_explodeg.wav", "global/e_explodel.wav", "global/e_explodem.wav" };
    return pointer(impacts[@intCast(@mod(entity, @as(c_int, impacts.len)))]);
}

pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}
pub fn impactCue(context: impact.Context) impact.Cue {
    return impact.none(context);
}

pub const identity = .{ .classname = "weapon_hammer", .label = "Hammer of Hephaestus", .episode = 2, .interval = 700 };
fn strike(shot: server.Fire) void {
    const data = server.info(@This());
    const charge = @max(0.15, @min(1, v.f(shot.charge_ms) / 1800));
    const range = if (data.range > 0) data.range else 128;
    server.traceShot(@This(), shot, data.damage * charge, 64);
    if (charge >= 1 and shot.owner.s.groundEntityNum != c.ENTITYNUM_NONE) {
        c.G_Damage(shot.owner, shot.owner, shot.owner, null, null, 20, c.DAMAGE_NO_ARMOR, c.DK_WEAPON_MOD(id));
        for (server.entities()) |*target| {
            if (target.inuse == 0 or target.takedamage == 0 or target == shot.owner) continue;
            const center = v.scale(v.add(target.r.absmin, target.r.absmax), 0.5);
            const delta = v.sub(center, shot.owner.r.currentOrigin);
            if (v.length(delta) > range) continue;
            const sight = server.trace(shot.start, center, shot.owner.s.number, c.MASK_SOLID);
            if (sight.fraction < 1 and sight.entityNum != target.s.number) continue;
            server.damage(@This(), .{ .victim = target, .inflictor = shot.owner, .owner = shot.owner, .direction = delta, .point = center, .amount = data.damage });
        }
        if (shot.owner.client != null) shot.owner.client[0].ps.velocity[2] += 450;
        _ = server.controller(@This(), shot.owner, shot.owner.r.currentOrigin, .quake, 3000);
    } else server.radius(@This(), shot.owner.r.currentOrigin, shot.owner, data.damage * charge, range, shot.owner);
    server.blast(shot.start, id);
}
pub fn fire(shot: server.Fire) void {
    const action = server.controller(@This(), shot.owner, shot.start, .melee, 500);
    action.dk.action = shot.charge_ms;
    action.dk.combatNext = server.now() + v.i((24 - chargeFrame(shot.charge_ms)) * 25);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.state(ent) == .melee) {
        const owner = server.find(ent.dk.ownerId) orelse {
            server.free(ent);
            return;
        };
        if (owner.health <= 0 or (owner.client != null and owner.client[0].ps.weapon != id)) {
            server.free(ent);
            return;
        }
        if (server.now() < ent.dk.combatNext) return;
        var start = owner.r.currentOrigin;
        start[2] += if (owner.client != null) v.f(owner.client[0].ps.viewheight) else 24;
        const axes = server.basis(if (owner.client != null) owner.client[0].ps.viewangles else owner.s.angles);
        strike(.{ .owner = owner, .start = start, .forward = axes.forward, .charge_ms = ent.dk.action });
        server.free(ent);
        return;
    }
    if (server.state(ent) == .ring) {
        server.ringTick(@This(), ent, false);
        return;
    }
    if (server.now() >= ent.dk.expires) {
        server.free(ent);
        return;
    }
    if (server.now() >= ent.dk.combatNext) {
        const owner = server.find(ent.dk.ownerId);
        server.radius(@This(), ent.r.currentOrigin, owner, v.f(ent.damage) * 0.25, 512, owner);
        _ = server.ring(@This(), ent, 700, 512);
        ent.dk.combatNext = server.now() + 500;
    }
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
fn chargeFrame(charge_ms: c_int) f32 {
    return @max(0, @min(18, 18 * v.f(charge_ms) / 1800));
}
var release_frame: f32 = 0;
var next_charge_sound: c_int = 0;
pub fn resetView() void {
    next_charge_sound = 0;
    release_frame = 0;
}
pub fn viewAction(view: anytype, ps: *c.playerState_t, _: c_int, _: bool) bool {
    if (ps.dk3AttackHeld == 0 or ps.dk3Charge <= 0) return false;
    view.pose = spec.animation.fire;
    view.idle_at = render.now() + 5000;
    if (render.now() >= next_charge_sound) {
        render.localSound("e2/we_hammerr.wav");
        next_charge_sound = render.now() + 500;
    }
    return true;
}
pub fn startShotPose(view: anytype, ps: *c.playerState_t, _: c_int, _: bool) void {
    release_frame = chargeFrame(ps.dk3Charge);
    view.play(spec.animation.fire, render.now(), 40);
    view.end = render.now() + v.i((31 - release_frame) * 25);
    view.idle_at = view.end + 5000;
}
pub fn viewFrame(view: anytype, ps: *c.playerState_t, entity: *c.refEntity_t) void {
    if (ps.dk3AttackHeld != 0 and ps.dk3Charge > 0) c.DK_ModelAnimationFrame(spec.animation.view_model, spec.animation.fire, chargeFrame(ps.dk3Charge), entity) else if (view.pose) |pose| {
        if (c.Q_stricmp(pose, spec.animation.fire) == 0) c.DK_ModelAnimationFrame(spec.animation.view_model, spec.animation.fire, release_frame + v.f(render.now() - view.start) * 0.04, entity) else c.DK_ModelAnimationRate(spec.animation.view_model, pose, view.start, @intFromBool(view.isIdle()), view.rate, entity);
    }
}
pub fn drawProjectile(cent: *c.centity_t) void {
    if (cent.currentState.dk3Effect != c.DK_FX_WEAPON_RING) {
        render.model(@This(), cent);
        return;
    }
    const fraction = @max(0, @min(1, v.f(render.now() - cent.currentState.time) / v.f(@max(1, cent.currentState.dk3EffectDuration))));
    _ = render.sprite("models/e1/we_shockring.sp2", 0, cent.lerpOrigin, .{ 90, 0, 0 }, cent.currentState.dk3EffectRadius * fraction / 32, 1 - fraction, spec.visual.color, c.DK_SPRITE_ADDITIVE | c.DK_SPRITE_ORIENTED);
}
pub fn validPlayer(ps: *const c.playerState_t, _: c_int) bool {
    return ps.dk3Charge >= 0 and ps.dk3Charge <= 1800;
}
pub fn validProjectile(ent: *const server.Entity) bool {
    return ent.dk.combatState != @intFromEnum(server.State.melee) or (ent.dk.action >= 0 and ent.dk.action <= 1800);
}
