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

pub const id = c.DK_W_DISRUPTOR;
pub const spec: profiles.Spec = .{
    .inventory_view_model = true,
    .start_episode = 1, // disruptor
    .world_model = "models/e1/a_tazer.dkm",
    .animation = .{
        .view_model = "models/e1/w_tglove.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 700,
        .drop_ms = 700,
    },
    .audio = .{
        .fire = "e1/we_dgloveshoota.wav",
        .ready = "e1/we_dgloveready.wav",
        .away = "e1/we_dgloveaway.wav",
    },
};
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}
pub fn update(controller: anytype) void {
    controller.automatic(@This());
}

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

pub fn impactCue(context: impact.Context) impact.Cue {
    var cue = impact.none(context);
    cue.mark = "models/global/we_dispunch.sp2/0@mark";
    cue.radius = 8;
    cue.sound = if (context.kind == 1) "e1/we_dglovehita.wav" else "e1/we_dglovehitc.wav";
    return cue;
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = .{ .classname = "weapon_disruptor", .label = "Disruptor", .episode = 1, .interval = 600 };

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
