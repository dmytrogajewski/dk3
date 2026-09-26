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

const description = @import("../descriptions/stavros.zig");
pub const id = c.DK_W_STAVROS;
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
    return impact.scorch(context);
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
    ent.s.pos.trDelta = v.scale(ent.s.pos.trDelta, 0.05);
    ent.s.dk3Scale = 0.1;
    ent.dk.combatNext = server.now() + 100;
}

pub fn contact(hit: server.Contact) void {
    if (server.named(hit.ent, "dk3_meteor_fragment")) {
        hit.ent.dk.uses += 1;
        if (hit.ent.dk.uses < 2) {
            server.reflect(hit.ent, hit.hit, 1);
            return;
        }
    }
    hit.ent.s.origin2 = hit.hit.plane.normal;
    hit.effect(@This());
    hit.detonate(@This());
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.now() >= ent.dk.expires or server.find(ent.dk.ownerId) == null) {
        server.free(ent);
        return;
    }
    if (server.named(ent, "dk3_meteor_fragment") or server.now() < ent.dk.combatNext) return;
    ent.dk.combatNext = server.now() + 100;
    if (ent.s.dk3Scale < 1) {
        ent.s.dk3Scale = @min(1, ent.s.dk3Scale + 0.1);
        const speed = v.length(ent.s.pos.trDelta);
        if (speed < server.info(@This()).speed) server.steer(ent, v.scale(ent.s.pos.trDelta, if (speed < server.info(@This()).speed * 0.2) @as(f32, 1.75) else 2.5));
    }
}
pub fn afterExplosion(ent: *server.Entity) void {
    if (c.g_gametype.integer != c.GT_SINGLE_PLAYER or server.named(ent, "dk3_meteor_fragment")) return;
    const owner = server.find(ent.dk.ownerId) orelse return;
    const count: usize = @as(usize, 4) + @min(2, @as(usize, @intFromFloat(server.random(ent) * 3)));
    for (0..count) |_| {
        var angles: v.Vec = undefined;
        c.vectoangles(&ent.s.origin2, &angles);
        angles[0] += (server.random(ent) - 0.5) * 90;
        angles[1] += (server.random(ent) - 0.5) * 90;
        const direction = server.basis(angles).forward;
        const fragment = server.spawn(@This(), .{ .owner = owner, .start = ent.r.currentOrigin, .forward = direction });
        fragment.classname = @constCast("dk3_meteor_fragment");
        fragment.damage = 0;
        fragment.splashDamage = v.i(server.info(@This()).damage * 0.5);
        fragment.splashRadius = v.i(server.info(@This()).range * 0.5);
        fragment.s.pos.trType = c.TR_GRAVITY;
        fragment.s.pos.trDelta = v.scale(direction, server.info(@This()).speed * 0.75);
        fragment.dk.expires = server.now() + 6000;
        fragment.s.dk3Scale = 0.35;
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
pub fn drawProjectile(cent: *c.centity_t) void {
    render.model(@This(), cent);
}

pub fn modifyHit(hit: *server.Hit) void {
    if (hit.victim == hit.owner) hit.amount = 0;
}
