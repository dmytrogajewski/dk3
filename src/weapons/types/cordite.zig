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

pub const id = c.DK_W_CORDITE;
pub const spec: profiles.Spec = .{
    .splash_hazard = true,
    .ammo_class = "ammo_cordite", // cordite
    .projectile = .{ .direct_scale = 0, .splash_scale = 1, .splash_radius = 150, .lifetime_ms = 3000 },
    .visual = .{ .projectile_model = "models/e4/we_ripgren.dkm", .blast_sound = "global/e_explode1.wav" },
    .world_model = "models/e4/a_cslug.dkm",
    .animation = .{
        .view_model = "models/e4/w_slugger.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shootb",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 250,
        .drop_ms = 250,
    },
    .audio = .{
        .fire = "e4/we_ripgunshootb.wav",
        .ready = "e4/we_ripgunready.wav",
        .away = "e4/we_ripgunaway.wav",
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
    return impact.scorch(context);
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = .{ .classname = "weapon_cordite", .label = "Cordite", .episode = 4, .interval = 2000 };

pub fn fire(shot: server.Fire) void {
    var launch = shot;
    var angles: v.Vec = undefined;
    c.vectoangles(&shot.forward, &angles);
    angles[0] -= 5;
    launch.forward = server.basis(angles).forward;
    _ = server.spawn(@This(), launch);
}

pub fn contact(hit: server.Contact) void {
    hit.effect(@This());
    if (hit.victim().client != null or hit.victim().dk.actorKind != 0) {
        hit.detonate(@This());
    } else {
        const owner_num = hit.ent.r.ownerNum;
        server.reflect(hit.ent, hit.hit, 0.6);
        hit.ent.r.ownerNum = owner_num;
        const sounds = [_][:0]const u8{ "e4/we_ripgunhita.wav", "e4/we_ripgunhitb.wav", "e4/we_ripgunhitc.wav", "e4/we_ripgunhitd.wav", "e4/we_ripgunhite.wav", "e4/we_ripgunhitf.wav" };
        server.sound(hit.ent, sounds[@min(5, @as(usize, @intFromFloat(server.random(hit.ent) * 6)))]);
    }
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.expired(@This(), ent)) return;
    if (ent.s.pos.trType == c.TR_LINEAR and server.now() - ent.s.time >= 380) {
        server.steer(ent, server.velocity(ent));
        ent.s.pos.trType = c.TR_GRAVITY;
    }
    const wet = server.liquid(ent);
    ent.waterlevel = @intFromBool(wet);
    ent.s.dk3EffectFlags = if (wet) c.DK_FX_BUBBLE else 0;
    if (wet) {
        var speed = server.velocity(ent);
        speed[0] *= 0.7071;
        speed[1] *= 0.7071;
        if (@abs(speed[2]) > 50) speed[2] *= 0.7071;
        server.steer(ent, speed);
    }
}

pub fn companionScore(score: f32, distance: f32, _: v.Vec, _: *server.Entity) f32 {
    return score * (if (distance < 180) @as(f32, 0.01) else 1);
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
    if (render.now() - cent.currentState.time < 300) {
        var angles: v.Vec = undefined;
        c.vectoangles(&cent.currentState.pos.trDelta, &angles);
        for (0..3) |index| {
            const age = v.f(render.now() - cent.currentState.time - @as(c_int, @intCast(index)) * 100) / 1000;
            if (age < 0 or age > 0.1) continue;
            var point: v.Vec = undefined;
            c.BG_EvaluateTrajectory(&cent.currentState.pos, cent.currentState.time + @as(c_int, @intCast(index)) * 100, &point);
            _ = render.sprite("models/e1/we_shotring.sp2", v.i(age * 50), point, angles, 0.1 + age * 5.5, 0.76 * (1 - age * 10), .{ 1, 0.8, 1 }, c.DK_SPRITE_ADDITIVE | c.DK_SPRITE_ORIENTED);
        }
    }
    render.model(@This(), cent);
}
