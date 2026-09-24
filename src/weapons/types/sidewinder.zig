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

pub const id = c.DK_W_SIDEWINDER;
pub const spec: profiles.Spec = .{
    .splash_hazard = true,
    .ammo_class = "ammo_rockets", // sidewinder
    .projectile = .{ .splash_scale = 1 },
    .visual = .{ .projectile_model = "models/e1/we_swrocket.dkm" },
    .world_model = "models/e1/a_swindr.dkm",
    .animation = .{
        .view_model = "models/e1/w_sidewinder.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e1/we_sidewindershoot.wav",
        .ready = "e1/we_sidewinderready.wav",
        .away = "e1/we_sidewinderaway.wav",
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

pub const identity = .{ .classname = "weapon_sidewinder", .label = "Sidewinder", .episode = 1, .interval = 850 };

pub fn fire(shot: server.Fire) void {
    const axes = server.directionBasis(shot.forward);
    for (0..2) |index| {
        const side = v.f(index) - 0.5;
        const ent = server.spawn(@This(), .{ .owner = shot.owner, .start = v.madd(shot.start, side * 12, axes.right), .forward = v.normal(v.madd(shot.forward, side * 0.06, axes.right)) });
        if (server.liquid(ent)) {
            ent.s.pos.trDelta = v.scale(ent.s.pos.trDelta, 1.0 / 3.0);
            ent.dk.abilityState = 1;
            ent.waterlevel = 1;
            ent.s.dk3EffectFlags = c.DK_FX_BUBBLE;
        }
    }
}
pub fn contact(hit: server.Contact) void {
    server.ballisticContact(@This(), hit);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.expired(@This(), ent)) return;
    const wet = server.liquid(ent);
    ent.waterlevel = @intFromBool(wet);
    ent.s.dk3EffectFlags = if (wet) c.DK_FX_BUBBLE else 0;
    if (ent.dk.abilityState == 0 and v.distance(ent.r.currentOrigin, ent.dk.launchOrigin) >= 400) {
        server.steer(ent, v.scale(ent.s.pos.trDelta, 2));
        ent.dk.abilityState = 1;
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
    render.model(@This(), cent);
}
