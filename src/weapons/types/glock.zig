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

const description = @import("../descriptions/glock.zig");
pub const id = c.DK_W_GLOCK;
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

pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}
pub fn impactCue(context: impact.Context) impact.Cue {
    return impact.bullet(context);
}

pub const identity = description.identity;

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
    return description.isReloading(ps);
}
pub fn validPlayer(ps: *const c.playerState_t, _: c_int) bool {
    return ps.dk3GlockClip >= 0 and ps.dk3GlockClip <= 10;
}
