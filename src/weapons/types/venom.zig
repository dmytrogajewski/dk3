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

const description = @import("../descriptions/venom.zig");
pub const id = c.DK_W_VENOM;
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
    if (sequence == 128) cue.pose = pointer(spec.animation.alternate);
    return cue;
}
pub fn audioCue(context: AudioContext) d.AudioCue {
    var cue = basicAudio(spec);
    if (context.entity == context.local_entity and context.sequence == 128) {
        const interval = @max(c.dk_weapons[id].interval, 1);
        const variant: usize = @intCast(1 + (@divTrunc(context.fired, interval) & 1));
        cue.fire = pointer(spec.audio.variants[variant]);
    }
    return cue;
}
pub fn impactCue(context: impact.Context) impact.Cue {
    var cue = impact.none(context);
    cue.sound = if (context.kind == 1) "global/m_knifehitb.wav" else "e2/we_venomhit.wav";
    return cue;
}

pub const identity = description.identity;

pub fn fire(shot: server.Fire) void {
    if (shot.sequence() == 128) {
        var start = shot.owner.r.currentOrigin;
        start[2] += 4;
        const end = v.madd(start, 150, shot.forward);
        var hit: c.trace_t = undefined;
        c.trap_Trace(&hit, &start, &shot.owner.r.mins, &shot.owner.r.maxs, &end, shot.owner.s.number, c.MASK_SHOT);
        if (hit.entityNum >= c.ENTITYNUM_WORLD) return;
        const target = &c.g_entities[@intCast(hit.entityNum)];
        _ = server.impact(@This(), &hit, target.takedamage != 0);
        server.damage(@This(), .{ .victim = target, .inflictor = shot.owner, .owner = shot.owner, .direction = shot.forward, .point = hit.endpos, .amount = server.info(@This()).damage * 1.3, .inertial = true });
    } else {
        var launch = shot;
        var angles: v.Vec = undefined;
        c.vectoangles(&shot.forward, &angles);
        angles[0] -= 5;
        launch.forward = server.basis(angles).forward;
        const ent = server.spawn(@This(), launch);
        ent.r.mins = .{ -8, -8, -2 };
        ent.r.maxs = .{ 8, 8, 14 };
        ent.dk.expires = server.now() + 10000;
        server.link(ent);
    }
}
pub fn afterHit(hit: *server.Hit) void {
    const target = hit.victim;
    if (target.dk.poisonEnd > server.now()) return;
    target.dk.poisonDamage = server.info(@This()).damage * 0.1;
    target.dk.poisonInterval = 1000;
    target.dk.poisonEnd = server.now() + 5000;
    target.dk.poisonNext = server.now() + 1000;
    target.dk.status |= 1;
}
pub fn contact(hit: server.Contact) void {
    if (hit.victim().takedamage != 0) {
        server.damage(@This(), .{ .victim = hit.victim(), .inflictor = hit.ent, .owner = hit.owner(), .direction = v.zero, .point = hit.hit.endpos, .amount = server.info(@This()).damage, .inertial = true });
        server.free(hit.ent);
        return;
    }
    hit.effect(@This());
    server.reflect(hit.ent, hit.hit, 0.6);
    if (hit.hit.plane.normal[2] > 0.7 and v.length(hit.ent.s.pos.trDelta) < 60) {
        server.stop(hit.ent, v.madd(hit.hit.endpos, 1, hit.hit.plane.normal));
        server.setState(hit.ent, .stuck);
        hit.ent.dk.expires = server.now() + 5000;
        hit.ent.r.ownerNum = c.ENTITYNUM_NONE;
    }
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.now() >= ent.dk.expires or server.liquid(ent)) {
        server.free(ent);
        return;
    }
    if (server.state(ent) != .stuck) {
        var speed = server.velocity(ent);
        speed[2] -= 800 * 0.2 * v.f(server.tick_ms) / 1000;
        server.steer(ent, speed);
        return;
    }
    for (server.entities()) |*target| {
        if (target == ent or target.inuse == 0 or target.takedamage == 0) continue;
        var overlaps = true;
        for (0..3) |axis| if (target.r.absmin[axis] > ent.r.currentOrigin[axis] + ent.r.maxs[axis] or target.r.absmax[axis] < ent.r.currentOrigin[axis] + ent.r.mins[axis]) {
            overlaps = false;
        };
        if (!overlaps) continue;
        server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = server.find(ent.dk.ownerId), .direction = v.zero, .point = target.r.currentOrigin, .amount = server.info(@This()).damage, .inertial = true });
        server.free(ent);
        return;
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
    if (cent.currentState.dk3Effect == 0) @import("venom_client.zig").trail(cent);
}
