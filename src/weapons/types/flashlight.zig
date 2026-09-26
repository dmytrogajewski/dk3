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

pub const id = c.DK_W_FLASHLIGHT;
pub const spec: profiles.Spec = .{
    .companion_pickup = false,
    .auto_select = false,
    .droppable = false, // flashlight
};
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}
pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (!controller.pressed()) {
        controller.release();
        return;
    }
    if (ps.dk3AttackHeld != 0) return;
    ps.dk3AttackHeld = 1;
    if (ps.weaponTime <= 0) controller.fire(@This(), predictionShot(controller));
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
    return impact.none(context);
}

pub const identity = .{ .classname = "weapon_flashlight", .label = "Flashlight", .episode = 0, .interval = 300 };

pub fn fire(shot: server.Fire) void {
    if (shot.owner.client != null) shot.owner.client[0].ps.dk3Status ^= 8;
}

pub fn companionScore(_: f32, _: f32, _: v.Vec, _: *server.Entity) f32 {
    return -1;
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
pub fn clientFrame() void {
    if ((c.cg.predictedPlayerState.dk3Status & 8) == 0 or c.cg.predictedPlayerState.stats[c.STAT_HEALTH] <= 0) return;
    const end = v.madd(c.cg.refdef.vieworg, 800, c.cg.refdef.viewaxis[0]);
    var hit: c.trace_t = undefined;
    c.CG_Trace(&hit, &c.cg.refdef.vieworg, null, null, &end, c.cg.clientNum, c.MASK_SOLID);
    render.light(v.madd(hit.endpos, -8, c.cg.refdef.viewaxis[0]), 180, .{ 1, 0.95, 0.8 });
}
