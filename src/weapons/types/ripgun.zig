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

const description = @import("../descriptions/ripgun.zig");
pub const id = c.DK_W_RIPGUN;
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
    return impact.bullet(context);
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = description.identity;
pub fn loopSound(player: *server.Entity) c_int {
    return if (player.health > 0 and player.client[0].ps.dk3AttackHeld != 0) c.DK_SoundIndex("e4/we_sluggerspin.wav") else 0;
}
pub fn viewAction(view: anytype, ps: *c.playerState_t, _: c_int, _: bool) bool {
    // Gold spins through the first 75% of shoota; there is no spup pose.
    if (ps.dk3Charge > 0) {
        if (view.pose == null or c.Q_stricmp(view.pose.?.ptr, "shoota") != 0) view.play("shoota", render.now(), 20);
        return true;
    }
    if (view.pose != null and c.Q_stricmp(view.pose.?.ptr, "shoota") == 0) {
        view.play("spdn", render.now(), 20);
        return true;
    }
    return false;
}
pub fn viewFrame(view: anytype, _: *c.playerState_t, entity: *c.refEntity_t) void {
    if (view.pose) |pose| c.DK_ModelAnimationRate(spec.animation.view_model, pose, view.start, @intFromBool(c.Q_stricmp(pose, "shoota") == 0 or view.isIdle()), view.rate, entity);
}

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
    render.flash(parent, fired, .{ .model = "models/global/genflash.dkm", .scale = 8, .radius = 175, .offset = -2, .shader = "dk3/fx/shotcycler-flash" });
}
pub const obsolete_pickup_model = "models/e4/wa_rip.dkm";
