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

pub const id = c.DK_W_SHOCKWAVE;
pub const spec: profiles.Spec = .{
    .splash_hazard = true,
    .ammo_class = "ammo_shocksphere", // shockwave
    .ammo_pack = 1,
    .projectile = .{ .direct_scale = 3, .splash_scale = 0.75, .splash_radius = 300 },
    .visual = .{ .projectile_model = "models/e1/we_3dshock.dkm", .impact_sprite = "models/e1/we_shockexp.sp2", .blast_sound = "e1/we_shockwaveexp.wav", .color = .{ 1, 1, 1 }, .glow = false },
    .world_model = "models/e1/a_shokwv.dkm",
    .animation = .{
        .view_model = "models/e1/w_shockwave.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .raise_ms = 400,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e1/we_shockwaveshoota.wav",
        .ready = "e1/we_shockwaveready.wav",
        .away = "e1/we_shockwaveaway.wav",
        .hum = "e1/we_shockwaveamba.wav",
    },
    .projectile_muzzle = true,
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
    cue.sound = "global/e_explodeb.wav";
    cue.light_radius = 500;
    cue.light_color = .{ 0.2, 0.2, 1 };
    cue.light_ms = 550;
    return cue;
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = .{ .classname = "weapon_shockwave", .label = "Shockwave", .episode = 1, .interval = 2850 };

pub fn fire(shot: server.Fire) void {
    const pending = server.controller(@This(), shot.owner, shot.start, .arming, 3000);
    pending.dk.actionTime = server.now() + v.i(1600 / @import("../rules.zig").attackFactor(shot.boost()));
    pending.s.origin2 = shot.forward;
}
fn shove(source: *server.Entity, point: v.Vec, ring_wave: bool) void {
    for (server.entities()) |*target| {
        if (target.inuse == 0 or target == source or target.takedamage == 0 or target.health <= 0 or (target.client == null and target.dk.actorKind == 0) or target.dk.cinematicOwned != 0) continue;
        const center = v.scale(v.add(target.r.absmin, target.r.absmax), 0.5);
        const distance = v.distance(center, point);
        const grounded = target.s.groundEntityNum != c.ENTITYNUM_NONE or (target.client != null and target.client[0].ps.groundEntityNum != c.ENTITYNUM_NONE);
        if (!grounded) continue;
        var speed = if (target.client != null) target.client[0].ps.velocity else target.dk.actorVelocity;
        if (ring_wave) {
            if (distance * 0.7 > 350) continue;
            speed[0] += (server.random(source) - 0.5) * 200;
            speed[1] += (server.random(source) - 0.5) * 200;
        } else {
            if (distance > 1000) continue;
            var push_direction = v.normal(v.sub(target.r.currentOrigin, point));
            if (push_direction[2] < 0.4 and push_direction[2] > -0.1) push_direction[2] = 0.4;
            speed = v.scale(v.madd(speed, 2 * (1000 - distance), push_direction), 0.3);
        }
        if (target.client != null) {
            target.client[0].ps.velocity = speed;
            target.client[0].ps.groundEntityNum = c.ENTITYNUM_NONE;
        } else {
            target.dk.actorVelocity = speed;
            target.s.groundEntityNum = c.ENTITYNUM_NONE;
        }
    }
}
fn detonate(ent: *server.Entity) void {
    const first = server.ring(@This(), ent, 3000, 350);
    first.damage = v.i(server.info(@This()).damage);
    first.dk.uses = 0;
    const quake = server.controller(@This(), server.find(ent.dk.ownerId), ent.r.currentOrigin, .quake, 5500);
    quake.dk.combatNext = server.now();
    server.tremor(ent.r.currentOrigin, 500, 700, 5500);
    server.blast(ent.r.currentOrigin, id);
    server.free(ent);
}
pub fn contact(hit: server.Contact) void {
    const ent = hit.ent;
    if (hit.victim().takedamage != 0) {
        // The projectile already carries the threefold direct-hit multiplier.
        hit.apply(@This(), v.f(ent.damage));
        ent.r.currentOrigin = hit.hit.endpos;
        detonate(ent);
        return;
    }
    hit.effect(@This());
    _ = server.splash(@This(), .{ .point = hit.hit.endpos, .inflictor = ent, .attacker = hit.owner(), .halved = hit.owner(), .amount = server.info(@This()).damage * 0.75, .range = 300, .ignore = ent, .occlusion = false, .flags = c.DAMAGE_NO_KNOCKBACK });
    shove(ent, hit.hit.endpos, false);
    server.tremor(hit.hit.endpos, 1000, 500, 400);
    ent.dk.uses += 1;
    ent.dk.action = 6; // no further flight rings after a bounce
    if (ent.dk.uses > 5) {
        ent.r.currentOrigin = v.madd(hit.hit.endpos, 40, hit.hit.plane.normal);
        detonate(ent);
        return;
    }
    const owner_num = ent.r.ownerNum;
    server.reflect(ent, hit.hit, 0.75);
    ent.r.ownerNum = owner_num;
}
fn ringDamage(ent: *server.Entity) void {
    const age = server.now() - ent.s.time;
    const outer = 350 * @min(1, v.f(age) / 3000);
    const inner = @max(0, 350 * v.f(age - 100) / 3000 - 20);
    const owner = server.find(ent.dk.ownerId);
    for (server.entities()) |*target| {
        if (target.inuse == 0 or target.takedamage == 0 or target == ent) continue;
        const center = v.scale(v.add(target.r.absmin, target.r.absmax), 0.5);
        const distance = v.distance(center, ent.r.currentOrigin);
        if (distance < inner or distance > outer) continue;
        const fraction = (1000 - distance) / 1000;
        var amount = server.info(@This()).damage * fraction;
        if (target == owner) amount *= 0.5;
        if (c.trap_InPVS(&center, &ent.r.currentOrigin) == 0) amount *= 0.05 else if (c.CanDamage(target, &ent.r.currentOrigin) == 0) amount *= 0.9;
        const direction = v.normal(v.sub(target.r.currentOrigin, ent.r.currentOrigin));
        server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = owner, .direction = direction, .point = center, .amount = amount });
        if (target.inuse != 0) server.push(target, direction, 1500 * fraction);
    }
}
pub fn projectileTick(ent: *server.Entity) void {
    const phase = server.state(ent);
    if (phase == .arming) {
        const owner = server.find(ent.dk.ownerId) orelse {
            server.free(ent);
            return;
        };
        if (owner.health <= 0 or (owner.client != null and owner.client[0].ps.weapon != id)) {
            server.free(ent);
            return;
        }
        if (server.now() < ent.dk.actionTime) return;
        var shot: server.Fire = .{ .owner = owner, .start = ent.r.currentOrigin, .forward = ent.s.origin2 };
        if (owner.client != null) {
            const ps = &owner.client[0].ps;
            const axes = server.basis(ps.viewangles);
            var eye = ps.origin;
            eye[2] += v.f(ps.viewheight);
            shot.start = v.madd(eye, 12, axes.forward);
            shot.start[2] += 18 - c.DEFAULT_VIEWHEIGHT;
            shot.start = server.trace(eye, shot.start, owner.s.number, c.MASK_SHOT).endpos;
            const aim = server.trace(eye, v.madd(eye, 4000, axes.forward), owner.s.number, c.MASK_SHOT).endpos;
            const delta = v.sub(aim, shot.start);
            shot.forward = if (v.dot(delta, axes.forward) > 1) v.normal(delta) else axes.forward;
            ps.velocity = v.madd(ps.velocity, -200, axes.forward);
        }
        const orb = server.spawn(@This(), shot);
        orb.r.mins = @splat(-15);
        orb.r.maxs = @splat(15);
        orb.s.dk3Scale = 15;
        orb.dk.combatNext = server.now() + 100;
        server.link(orb);
        server.free(ent);
        return;
    }
    if (phase == .quake) {
        if (server.now() >= ent.dk.expires) {
            server.free(ent);
            return;
        }
        if (server.now() >= ent.dk.combatNext) {
            shove(ent, ent.r.currentOrigin, true);
            ent.dk.combatNext = server.now() + 100;
        }
        return;
    }
    if (phase == .ring) {
        if (ent.dk.combatCount == 0 and ent.dk.uses < 5 and server.now() >= ent.s.time + 500) {
            const next = server.ring(@This(), ent, 3000, 350);
            next.dk.uses = ent.dk.uses + 1;
            ent.dk.combatCount = 1;
        }
        if (server.now() >= ent.dk.combatNext) {
            ringDamage(ent);
            ent.dk.combatNext = server.now() + 100;
        }
        if (server.now() >= ent.dk.expires) server.free(ent);
        return;
    }
    if (server.find(ent.dk.ownerId) == null) {
        server.free(ent);
        return;
    }
    if (server.now() < ent.dk.combatNext) return;
    ent.dk.combatNext = server.now() + 100;
    var speed = server.velocity(ent);
    const wet = server.liquid(ent);
    if (wet) {
        if (v.length(speed) > 100) speed = v.scale(v.normal(speed), 100);
        ent.dk.uses = 6;
    }
    ent.waterlevel = @intFromBool(wet);
    ent.s.dk3EffectFlags = if (wet) c.DK_FX_BUBBLE else 0;
    if (v.length(speed) < 1) {
        detonate(ent);
        return;
    }
    if (ent.dk.action < 6 and v.distance(ent.r.currentOrigin, ent.dk.launchOrigin) > 75) {
        ent.dk.action += 1;
        ent.dk.launchOrigin = ent.r.currentOrigin;
        const event: *server.Entity = c.G_TempEntity(&ent.r.currentOrigin, c.EV_DK3_IMPACT);
        event.s.weapon = id;
        event.s.eventParm = 3;
        event.s.origin2 = v.normal(speed);
    } else speed[2] -= 50;
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
    if (cent.currentState.eventParm == 3) {
        var angles: v.Vec = undefined;
        c.vectoangles(&cent.currentState.origin2, &angles);
        flight_rings[flight_next] = .{ .start = render.now(), .point = cent.lerpOrigin, .angles = angles };
        flight_next = (flight_next + 1) % flight_rings.len;
        return;
    }
    render.impact(@This(), cent);
}

const FlightRing = struct { start: c_int = 0, point: v.Vec = v.zero, angles: v.Vec = v.zero };
var flight_rings: [32]FlightRing = @splat(.{});
var flight_next: usize = 0;
pub fn resetClient() void {
    flight_rings = @splat(.{});
    flight_next = 0;
}
pub fn clientFrame() void {
    for (flight_rings) |ring| {
        const age = render.now() - ring.start;
        if (ring.start == 0 or age < 0 or age >= 500) continue;
        const fraction = v.f(age) / 500;
        _ = render.sprite("models/global/we_shotring.sp2", 0, ring.point, ring.angles, 0.96 + (0.01 - 0.96) * fraction, 1 - fraction, .{ 0.25, 0.25, 1 }, c.DK_SPRITE_ORIENTED);
        render.light(ring.point, 200 * (1 - fraction), .{ 0.25, 0.25, 1 });
    }
}

pub fn muzzle(parent: *c.refEntity_t, fired: c_int) void {
    render.flash(parent, fired + 1600, .{ .model = "models/e1/we_mfswave.sp2", .scale = 0.285, .color = .{ 1, 1, 1 }, .sprite_model = true });
}
pub fn drawProjectile(cent: *c.centity_t) void {
    if (cent.currentState.dk3Effect != c.DK_FX_WEAPON_RING) {
        render.model(@This(), cent);
        return;
    }
    const age = v.f(render.now() - cent.currentState.time) / 1000;
    const fraction = @max(0, @min(1, age * 1000 / v.f(@max(1, cent.currentState.dk3EffectDuration))));
    var seed = @as(u32, @bitCast(cent.currentState.number)) *% 7919 +% @as(u32, @bitCast(cent.currentState.time));
    var angles: v.Vec = undefined;
    for (&angles, 0..) |*axis, index| {
        seed = seed *% 1103515245 +% 12345;
        const start = v.f((seed >> 16) & 0x7fff) / 16383.5 - 1;
        seed = seed *% 1103515245 +% 12345;
        const speed = 70 + (v.f((seed >> 16) & 0x7fff) / 16383.5 - 1) * 270;
        axis.* = (if (index < 2) start * 90 else 0) + speed * age;
    }
    _ = render.sprite("models/e1/we_shockring.sp2", 0, cent.lerpOrigin, angles, 1 + 13 * fraction, 0.2, render.white, c.DK_SPRITE_ORIENTED);
}
pub fn blastEffect(_: *c.centity_t, effect: anytype) void {
    effect.scale = 1.5;
    effect.light = false;
}
