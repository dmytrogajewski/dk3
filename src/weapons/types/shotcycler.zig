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

pub const id = c.DK_W_SHOTCYCLER;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_shells", // shotcycler
    .ammo_pack = 24,
    .world_model = "models/e1/a_shot.dkm",
    .animation = .{
        .view_model = "models/e1/w_shotcycler.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "ambc", null, null },
        .rate = 22,
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e1/we_shotcyclershoota.wav",
        .ready = "e1/we_shotcyclerready.wav",
        .away = "e1/we_shotcycleraway.wav",
        .finish = "e1/we_shotcyclershootb.wav",
        .idle = .{ "e1/we_shotcycleramba.wav", null, null },
    },
    .burst_shots = 6,
    .burst_recovery_ms = 1800,
    .projectile_muzzle = true,
};

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}
pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    var cue = basicView(spec);
    cue.poseStartOffsetMs = -90;
    cue.finishDelayMs = 42 * 45;
    return cue;
}
pub fn audioCue(context: AudioContext) d.AudioCue {
    const shells = [_][:0]const u8{ "e1/we_shotcyclershella.wav", "e1/we_shotcyclershellb.wav", "e1/we_shotcyclershellc.wav", "e1/we_shotcyclershelld.wav", "e1/we_shotcyclershelle.wav", "e1/we_shotcyclershellf.wav" };
    return .{ .fire = pointer(spec.audio.fire), .extra = pointer(shells[@intCast(@mod(@divTrunc(context.fired, 270), 6))]) };
}
pub fn impactCue(context: impact.Context) impact.Cue {
    var cue = impact.none(context);
    cue.mark = "dk3/fx/shotcycler-mark";
    cue.radius = 8;
    return cue;
}

pub const identity = .{ .classname = "weapon_shotcycler", .label = "Shotcycler-6", .episode = 1, .interval = 270 };

pub fn fire(shot: server.Fire) void {
    // Gold pellets reach the crosshair point plus 64 units, not the table range.
    var reach = server.info(@This()).range;
    var aimed = shot;
    if (shot.owner.client != null) {
        const ps = &shot.owner.client[0].ps;
        var eye = ps.origin;
        eye[2] += v.f(ps.viewheight);
        var forward: v.Vec = undefined;
        c.AngleVectors(&ps.viewangles, &forward, null, null);
        const aim = server.trace(eye, v.madd(eye, 4000, forward), shot.owner.s.number, c.MASK_SHOT);
        reach = v.distance(shot.start, aim.endpos) + 64;
        const delta = v.sub(aim.endpos, shot.start);
        if (v.dot(delta, forward) > 1) aimed.forward = v.normal(delta);
        // Gold weapon_kick, twice per shot.
        ps.velocity = v.madd(ps.velocity, -140, forward);
    }
    server.pelletBlast(@This(), aimed, .{
        .count = 10,
        .spread = 0.09,
        .scale = if (c.g_gametype.integer == c.GT_SINGLE_PLAYER) 0.75 else 1,
        .range = reach,
        .max_victims = 2,
        .last_impact_only = true,
        .inertial = true,
    });
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

pub fn muzzle(parent: *c.refEntity_t, fired: c_int) void {
    render.flash(parent, fired, .{ .model = "models/global/genflash.dkm", .scale = 3, .radius = 175, .offset = -2, .shader = "dk3/fx/shotcycler-flash" });
}
var finish_at: c_int = 0;
pub fn resetView() void {
    finish_at = 0;
}
pub fn startShotPose(view: anytype, ps: *c.playerState_t, fired: c_int, reset: bool) void {
    if (ps.dk3Burst == spec.burst_shots - 1 and (reset or view.shot != fired)) {
        const cue = viewCue(ps.dk3WeaponSequence, ps.dk3SwordExperience);
        view.play(spec.animation.fire, render.now() + cue.poseStartOffsetMs, cue.rate);
        finish_at = view.start + cue.finishDelayMs;
    }
}
pub fn viewFrame(view: anytype, _: *c.playerState_t, entity: *c.refEntity_t) void {
    if (finish_at != 0 and render.now() >= finish_at) {
        render.localSound(pointer(spec.audio.finish));
        finish_at = 0;
    }
    if (view.pose) |pose| {
        if (c.Q_stricmp(pose, spec.animation.fire) == 0) c.DK_ModelAnimationFrame(spec.animation.view_model, pose, v.f(render.now() - view.start) / 45, entity) else c.DK_ModelAnimationRate(spec.animation.view_model, pose, view.start, @intFromBool(view.isIdle()), view.rate, entity);
    }
}
pub fn eject(cent: *c.centity_t) void {
    if (c.cg_brassTime.integer <= 0) return;
    const shell: *c.localEntity_t = c.CG_AllocLocalEntity();
    const model = &shell.refEntity;
    var axes: [3]v.Vec = undefined;
    var origin: v.Vec = undefined;
    if (cent.currentState.number == c.cg.clientNum and c.cg.renderingThirdPerson == 0) {
        axes = c.cg.refdef.viewaxis;
        origin = v.madd(v.madd(v.madd(c.cg.refdef.vieworg, 25, axes[0]), -12, axes[1]), -8, axes[2]);
    } else {
        c.AnglesToAxis(&cent.lerpAngles, &axes);
        origin = v.madd(v.madd(cent.lerpOrigin, 16, axes[0]), -8, axes[1]);
        origin[2] += 20;
    }
    shell.leType = c.LE_FRAGMENT;
    shell.startTime = render.now();
    shell.endTime = render.now() + c.cg_brassTime.integer * 2;
    shell.pos.trType = c.TR_GRAVITY;
    shell.pos.trTime = render.now();
    shell.pos.trBase = origin;
    model.origin = origin;
    shell.pos.trDelta = v.add(v.sub(v.scale(axes[0], 45), v.scale(axes[1], 90)), v.scale(axes[2], 110));
    model.hModel = c.DK_RegisterModel("models/e1/we_shotshell.dkm");
    model.axis = render.identity;
    shell.bounceFactor = 0.3;
    shell.angles.trType = c.TR_LINEAR;
    shell.angles.trTime = render.now();
    shell.angles.trDelta = .{ 120, 170, 80 };
    shell.leFlags = c.LEF_TUMBLE;
    shell.leBounceSoundType = c.LEBS_NONE;
    shell.leMarkType = c.LEMT_NONE;
}
