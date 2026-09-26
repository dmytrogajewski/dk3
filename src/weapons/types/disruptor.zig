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
    .equipped = false,
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
        .idle = .{ "e1/we_dgloveamba.wav", "e1/we_dgloveambb.wav", null },
    },
};
/// Gold picks shoota (12 frames) or shootb (10 frames) at random; the next
/// punch waits for the animation plus 0.1 s.
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    const seed: u32 = @bitCast(controller.move.cmd.serverTime);
    result.sequence = @intCast(((seed *% 1103515245 +% 12345) >> 16) & 1);
    result.duration_ms = controller.scaled(if (result.sequence == 0) 600 else 500) + 100;
    return result;
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
    if (context.frame == 1) {
        cue.sparks = 5;
        cue.spark_color = .{ 0.5, 0.5, 1 };
        cue.light_radius = 350;
        cue.light_color = .{ 0, 0, 1 };
        cue.light_ms = 150;
    }
    return cue;
}
var marker: c_int = 0;
pub fn impactMaterial(event: *server.Entity, _: *const c.trace_t, _: bool) void {
    event.s.frame = marker;
}
pub fn viewCue(sequence: c_int, _: c_int) d.ViewCue {
    var cue = basicView(spec);
    if (sequence == 1) cue.pose = "shootb";
    return cue;
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = .{ .classname = "weapon_disruptor", .label = "Disruptor", .episode = 1, .interval = 650 };

pub fn fire(shot: server.Fire) void {
    const owner = shot.owner;
    var start = shot.start;
    if (owner.client != null) {
        start = owner.client[0].ps.origin;
        start[2] += if ((owner.client[0].ps.pm_flags & c.PMF_DUCKED) != 0) -4 else 21;
    }
    const hit = server.trace(start, v.madd(start, server.info(@This()).range, shot.forward), owner.s.number, c.MASK_SHOT);
    if (hit.fraction == 1) return;
    const victim = &c.g_entities[@intCast(hit.entityNum)];
    const damaged = hit.entityNum < c.ENTITYNUM_WORLD and victim.takedamage != 0;
    marker = @intFromBool(damaged or v.distance(hit.endpos, owner.r.currentOrigin) < 40);
    _ = server.impact(@This(), &hit, damaged);
    marker = 0;
    if (!damaged) return;
    var amount = server.info(@This()).damage;
    if (c.g_gametype.integer == c.GT_SINGLE_PLAYER) amount *= 0.5;
    server.damage(@This(), .{ .victim = victim, .inflictor = owner, .owner = owner, .direction = shot.forward, .point = hit.endpos, .amount = amount, .inertial = true });
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
