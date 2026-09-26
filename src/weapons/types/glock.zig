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

pub const id = c.DK_W_GLOCK;
pub const spec: profiles.Spec = .{
    .companion_episode = 4,
    .start_episode = 4,
    .ammo_class = "ammo_bullets", // glock
    .world_model = "models/e4/a_glock.dkm",
    .animation = .{
        .view_model = "models/e4/w_glock.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 300,
        .drop_ms = 250,
    },
    .audio = .{
        .fire = "e4/we_glockshootb.wav",
        .ready = "e4/we_glockready.wav",
        .away = "e4/we_glockaway.wav",
        .reload = "e4/we_glockreload.wav",
    },
};
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.consume_clip = true;
    return result;
}
pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (ps.weaponstate == c.WEAPON_DROPPING and ps.dk3WeaponSequence == c.DK_GLOCK_RELOAD_SEQUENCE) {
        if (ps.weaponTime > 0) return;
        ps.dk3GlockClip = @min(ps.ammo[c.DK_W_GLOCK], 10);
        ps.dk3WeaponSequence = 0;
        ps.weaponstate = c.WEAPON_READY;
    }
    if (!controller.pressed() and ps.dk3Burst == 0) {
        controller.release();
        return;
    }
    ps.dk3AttackHeld = @intFromBool(controller.pressed());
    if (ps.weaponTime > 0) return;
    const next = predictionShot(controller);
    if (ps.dk3GlockClip <= 0 and (next.cost == 0 or ps.ammo[id] >= next.cost)) {
        ps.weaponstate = c.WEAPON_DROPPING;
        ps.weaponTime = 1650;
        ps.dk3WeaponSequence = c.DK_GLOCK_RELOAD_SEQUENCE;
        return;
    }
    controller.fire(@This(), next);
    if (ps.dk3GlockClip == 0 and ps.ammo[id] > 0) {
        ps.weaponstate = c.WEAPON_DROPPING;
        ps.weaponTime = 1650;
        ps.dk3WeaponSequence = c.DK_GLOCK_RELOAD_SEQUENCE;
    }
}

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}
pub fn impactCue(context: impact.Context) impact.Cue {
    return impact.bullet(context);
}

pub const identity = .{ .classname = "weapon_glock", .label = "Glock", .episode = 4, .interval = 500 };

pub fn fire(shot: server.Fire) void {
    server.traceShot(@This(), shot, server.info(@This()).damage, server.info(@This()).range);
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
    render.flash(parent, fired, .{ .model = "models/global/we_mflash.dkm", .sequence = "amba", .shader = "dk3/fx/glock-flash" });
}
pub fn dropPose(view: anytype, ps: *c.playerState_t) void {
    const reload = ps.dk3WeaponSequence == c.DK_GLOCK_RELOAD_SEQUENCE;
    view.play(if (reload) "reload" else spec.animation.away, render.now(), 20);
    render.localSound(pointer(if (reload) spec.audio.reload else spec.audio.away));
}
pub fn initializePlayer(ps: *c.playerState_t) void {
    ps.dk3GlockClip = 10;
}

pub fn isReloading(ps: *const c.playerState_t) bool {
    return ps.weaponstate == c.WEAPON_DROPPING and ps.dk3WeaponSequence == c.DK_GLOCK_RELOAD_SEQUENCE;
}
pub fn validPlayer(ps: *const c.playerState_t, _: c_int) bool {
    return ps.dk3GlockClip >= 0 and ps.dk3GlockClip <= 10;
}
