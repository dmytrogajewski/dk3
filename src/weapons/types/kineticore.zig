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

const description = @import("../descriptions/kineticore.zig");
pub const id = c.DK_W_KINETICORE;
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
    var cue = impact.none(context);
    cue.sound = "e4/we_kcorehita.wav";
    return cue;
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = description.identity;

pub fn fire(shot: server.Fire) void {
    const ent = server.spawn(@This(), shot);
    ent.s.pos.trDelta = v.scale(ent.s.pos.trDelta, 0.25);
    ent.dk.combatNext = server.now() + 100;
    const sounds = [_][:0]const u8{ "e4/we_kcoreflybya.wav", "e4/we_kcoreflybyb.wav", "e4/we_kcoreflybyc.wav" };
    ent.s.loopSound = c.DK_SoundIndex(sounds[@min(2, @as(usize, @intFromFloat(server.random(ent) * 3)))]);
    if (shot.owner.client != null) shot.owner.client[0].ps.velocity = v.madd(shot.owner.client[0].ps.velocity, -90, shot.forward);
}

pub fn afterHit(hit: *server.Hit) void {
    hit.victim.dk.freezeLevel = @min(1, hit.victim.dk.freezeLevel + 0.2);
    hit.victim.dk.status |= 4;
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.expired(@This(), ent)) return;
    if (server.now() >= ent.dk.combatNext and v.length(ent.s.pos.trDelta) < server.info(@This()).speed) {
        server.steer(ent, v.scale(v.normal(ent.s.pos.trDelta), @min(server.info(@This()).speed, v.length(ent.s.pos.trDelta) * 2)));
        ent.dk.combatNext = server.now() + 100;
    }
}
pub fn contact(hit: server.Contact) void {
    hit.effect(@This());
    if (hit.victim().takedamage != 0) {
        const remaining = @max(0, @min(1, v.f(hit.ent.dk.expires - server.now()) / v.f(@max(1, hit.ent.dk.expires - hit.ent.s.time))));
        var amount = 2 + v.f(hit.ent.damage) * remaining;
        if (hit.victim() == hit.owner()) amount *= 0.5;
        hit.apply(@This(), @max(5, amount));
        hit.detonate(@This());
    } else server.reflect(hit.ent, hit.hit, 1);
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
