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

const description = @import("../descriptions/silverclaw.zig");
pub const id = c.DK_W_SILVERCLAW;
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

pub fn viewCue(sequence: c_int, _: c_int) d.ViewCue {
    var cue = basicView(spec);
    const poses = [_][:0]const u8{ "shoota", "shootb", "shootc" };
    cue.pose = pointer(poses[@intCast(@mod(sequence, 3))]);
    return cue;
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return .{ .fire = null, .extra = null };
}
pub fn impactCue(context: impact.Context) impact.Cue {
    var cue = impact.none(context);
    cue.mark = "models/global/we_clwmark2.sp2/0@mark";
    cue.radius = 9;
    const yaw = [_]f32{ 220, 135, 0 };
    cue.orientation = yaw[@intCast(@mod(context.frame, 3))];
    cue.sound = if (context.kind == 1) "e3/we_sclawhit2.wav" else "e3/we_sclawhit1.wav";
    return cue;
}

pub const identity = description.identity;
pub fn fire(shot: server.Fire) void {
    const ent = server.controller(@This(), shot.owner, shot.start, .melee, 400);
    ent.dk.action = @mod(shot.sequence(), 3);
    ent.dk.combatNext = server.now() + 250;
}
pub fn projectileTick(ent: *server.Entity) void {
    const owner = server.find(ent.dk.ownerId) orelse {
        server.free(ent);
        return;
    };
    if (owner.health <= 0 or server.now() >= ent.dk.expires) {
        server.free(ent);
        return;
    }
    if (server.now() < ent.dk.combatNext) return;
    const sounds = [_][:0]const u8{ "e3/we_sclawshoota.wav", "e3/we_sclawshootb.wav", "e3/we_sclawshootc.wav" };
    const index: usize = @intCast(@mod(ent.dk.action, 3));
    server.sound(owner, sounds[index]);
    const forward = server.basis(if (owner.client != null) owner.client[0].ps.viewangles else owner.s.angles).forward;
    var start = owner.r.currentOrigin;
    start[2] += 12;
    if (owner.client != null and (owner.client[0].ps.pm_flags & c.PMF_DUCKED) != 0) start[2] -= 25;
    const range = server.info(@This()).range;
    const hit = server.trace(start, v.madd(start, if (range > 0) range else 64, forward), owner.s.number, c.MASK_SHOT);
    const target = &c.g_entities[@intCast(hit.entityNum)];
    if (server.impact(@This(), &hit, hit.entityNum < c.ENTITYNUM_WORLD and target.takedamage != 0)) |event| event.s.frame = @intCast(index);
    if (hit.entityNum < c.ENTITYNUM_WORLD and target.takedamage != 0) server.damage(@This(), .{ .victim = target, .inflictor = owner, .owner = owner, .direction = forward, .point = hit.endpos, .amount = if (target.health <= 0) 50 else v.f(ent.damage) });
    server.free(ent);
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
    if (cent.currentState.eventParm != 1) {
        var spark = cent.*;
        spark.currentState.eventParm = 1;
        @import("ion_client.zig").impact(&spark);
    }
}
pub fn drawProjectile(cent: *c.centity_t) void {
    render.model(@This(), cent);
}
pub const slays_revenants = true;
