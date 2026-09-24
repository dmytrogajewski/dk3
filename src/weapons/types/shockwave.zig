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
    .projectile = .{ .direct_scale = 3, .splash_scale = 0.75, .splash_radius = 300 },
    .visual = .{ .projectile_model = "models/e1/we_3dshock.dkm", .impact_sprite = "models/e1/we_shockexp.sp2" },
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
    return impact.none(context);
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = .{ .classname = "weapon_shockwave", .label = "Shockwave", .episode = 1, .interval = 1000 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
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
            if (target.client == null) speed[2] = 60;
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
pub fn contact(hit: server.Contact) void {
    const struck = hit.victim().takedamage != 0;
    hit.effect(@This());
    server.radius(@This(), hit.hit.endpos, hit.owner(), v.f(hit.ent.splashDamage), 300, hit.ent);
    if (struck) hit.apply(@This(), v.f(hit.ent.damage) * 3) else {
        shove(hit.ent, hit.hit.endpos, false);
        server.tremor(hit.hit.endpos, 1000, 500, 400);
    }
    hit.ent.dk.uses += 1;
    if (hit.ent.dk.uses > 5 or struck) {
        hit.ent.r.currentOrigin = hit.hit.endpos;
        if (!struck) server.tremor(hit.hit.endpos, 500, 700, 3000);
        _ = server.ring(@This(), hit.ent, 3000, 350);
        hit.detonate(@This());
        return;
    }
    server.reflect(hit.ent, hit.hit, 1);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.state(ent) == .ring) {
        if (server.now() < ent.dk.expires and server.now() >= ent.dk.combatNext) {
            shove(ent, ent.r.currentOrigin, true);
            ent.dk.combatNext = server.now() + 100;
        }
        if (ent.dk.combatCount == 0 and ent.dk.uses < 5 and server.now() >= ent.s.time + 500) {
            const next = server.ring(@This(), ent, 3000, 350);
            next.dk.uses = ent.dk.uses + 1;
            ent.dk.combatCount = 1;
        }
        server.ringTick(@This(), ent, true);
        return;
    }
    if (server.expired(@This(), ent)) return;
    const wet = server.liquid(ent);
    if (@intFromBool(wet) != ent.waterlevel) {
        var speed = v.scale(server.velocity(ent), if (wet) @as(f32, 0.5) else 2);
        if (wet) {
            speed = v.scale(v.normal(speed), 100);
            ent.dk.uses = 6;
        }
        server.steer(ent, speed);
        ent.waterlevel = @intFromBool(wet);
        ent.s.dk3EffectFlags = if (wet) c.DK_FX_BUBBLE else 0;
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

pub fn muzzle(parent: *c.refEntity_t, fired: c_int) void {
    render.flash(parent, fired, .{ .model = "models/e1/we_mfswave.sp2", .scale = 0.285, .color = .{ 1, 1, 1 }, .sprite_model = true });
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
    _ = render.sprite("models/e1/we_shockring.sp2", 0, cent.lerpOrigin, angles, 1 + 13 * fraction, 1, render.white, c.DK_SPRITE_ORIENTED);
}
pub fn blastEffect(_: *c.centity_t, effect: anytype) void {
    effect.scale = 2;
}
