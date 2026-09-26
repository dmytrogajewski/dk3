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

const description = @import("../descriptions/wyndrax.zig");
pub const id = c.DK_W_WYNDRAX;
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
    return impact.none(context);
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = description.identity;

pub fn fire(shot: server.Fire) void {
    server.schedule(@This(), shot, 500);
}
pub fn launch(shot: server.Fire) void {
    const ent = server.spawn(@This(), shot);
    ent.clipmask = 0;
    ent.s.dk3Scale = 2;
    ent.s.pos.trDelta = v.scale(shot.forward, 500 + server.random(ent) * 500);
}
pub fn contact(_: server.Contact) void {}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.scheduled(@This(), ent)) return;
    const owner = server.find(ent.dk.ownerId);
    if (owner == null or owner.?.health <= 0) ent.dk.expires = @min(ent.dk.expires, server.now());
    if (server.now() >= ent.dk.expires + 2000) {
        server.sound(ent, "e3/we_wwispaway.wav");
        server.free(ent);
        return;
    }
    if (server.now() >= ent.dk.expires) ent.s.dk3Alpha = @max(0.01, 1 - v.f(server.now() - ent.dk.expires) / 2000);
    if (server.now() < ent.dk.combatNext) return;
    ent.dk.combatNext = server.now() + 100;
    for (ent.dk.combatTargets[0..4]) |*target_id| {
        if (server.find(target_id.*)) |target| {
            if (!server.creatureTarget(owner, target) or v.distance(target.r.currentOrigin, ent.r.currentOrigin) > 300 or server.random(ent) < 0.1) target_id.* = 0;
        } else target_id.* = 0;
        if (target_id.* == 0) {
            for (server.entities()) |*candidate| {
                if (!server.creatureTarget(owner, candidate) or v.distance(candidate.r.currentOrigin, ent.r.currentOrigin) > 300 or c.CanDamage(candidate, &ent.r.currentOrigin) == 0) continue;
                var used = false;
                for (ent.dk.combatTargets[0..4]) |other| if (@as(c_uint, @bitCast(other)) == candidate.dk.id) {
                    used = true;
                };
                if (!used) {
                    target_id.* = @bitCast(candidate.dk.id);
                    break;
                }
            }
        }
        const target = server.find(target_id.*) orelse continue;
        if (v.distance(target.r.currentOrigin, ent.r.currentOrigin) > 250 or c.CanDamage(target, &ent.r.currentOrigin) == 0) continue;
        server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = owner, .direction = v.zero, .point = target.r.currentOrigin, .amount = server.info(@This()).damage * 0.5, .inertial = true });
        server.beam(ent.r.currentOrigin, target.r.currentOrigin, id);
    }
    var speed = ent.s.pos.trDelta;
    var nearest: ?*server.Entity = null;
    var best: f32 = 65536;
    for (server.entities()) |*candidate| {
        const distance = v.distance(ent.r.currentOrigin, candidate.r.currentOrigin);
        if (server.creatureTarget(owner, candidate) and distance < best and c.CanDamage(candidate, &ent.r.currentOrigin) != 0) {
            nearest = candidate;
            best = distance;
        }
    }
    if (nearest) |target| {
        const delta = v.sub(target.r.currentOrigin, ent.r.currentOrigin);
        const distance = v.length(delta);
        speed = v.scale(v.normal(delta), if (distance < 64) @as(f32, -150) else 150);
        if (distance >= 64 and distance <= 100) {
            speed[0] = 0;
            speed[1] = 0;
        }
    } else speed = v.scale(v.normal(speed), 150);
    for (&speed) |*axis| axis.* += (server.random(ent) - 0.5) * 60;
    server.steer(ent, speed);
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
    render.light(cent.lerpOrigin, 120, spec.visual.color);
}
