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

pub const id = c.DK_W_TRIDENT;
pub const spec: profiles.Spec = .{
    .protects_water = true,
    .ammo_class = "ammo_tritips", // trident
    .projectile = .{ .splash_scale = 1 },
    .visual = .{ .projectile_model = "models/e2/we_tritip.dkm" },
    .world_model = "models/e2/a_tri.dkm",
    .animation = .{
        .view_model = "models/e2/w_trident.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", "ambb", "ambc" },
        .raise_ms = 600,
        .drop_ms = 600,
    },
    .audio = .{
        .fire = "e2/we_tridentfirea.wav",
        .ready = "e2/we_tridentready.wav",
        .away = "e2/we_tridentaway.wav",
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

pub const identity = .{ .classname = "weapon_trident", .label = "Trident of Poseidon", .episode = 2, .interval = 450 };

pub fn fire(shot: server.Fire) void {
    const axes = server.directionBasis(shot.forward);
    var tips: [3]*server.Entity = undefined;
    for (&tips, 0..) |*tip, index| {
        const side = v.f(index) - 1;
        tip.* = server.spawn(@This(), .{ .owner = shot.owner, .start = v.madd(shot.start, side * 12, axes.right), .forward = v.normal(v.madd(shot.forward, side * 0.06, axes.right)) });
    }
    tips[0].dk.destinationId = @bitCast(tips[1].dk.id);
    tips[2].dk.destinationId = @bitCast(tips[1].dk.id);
    tips[1].dk.combatTargets[0] = @bitCast(tips[0].dk.id);
    tips[1].dk.combatTargets[1] = @bitCast(tips[2].dk.id);
}
pub fn contact(hit: server.Contact) void {
    hit.effect(@This());
    var amount = v.f(hit.ent.damage);
    if ((c.trap_PointContents(&hit.hit.endpos, hit.ent.s.number) & c.MASK_WATER) != 0) amount *= 2;
    if (hit.ent.dk.abilityState != 0) amount *= 2;
    hit.apply(@This(), amount);
    hit.detonate(@This());
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.expired(@This(), ent)) return;
    if (ent.dk.destinationId == 0 or server.now() - ent.s.time < 150) return;
    const middle = server.find(ent.dk.destinationId) orelse {
        ent.dk.destinationId = 0;
        return;
    };
    if (v.distance(ent.r.currentOrigin, middle.r.currentOrigin) < 24) {
        middle.dk.abilityCharges += 1;
        if (middle.dk.abilityCharges == 2) {
            middle.dk.abilityState = 1;
            middle.s.dk3Scale = 2;
        }
        server.free(ent);
        return;
    }
    const goal = v.madd(middle.r.currentOrigin, 0.05, middle.s.pos.trDelta);
    server.steer(ent, v.scale(v.normal(v.sub(goal, ent.r.currentOrigin)), server.info(@This()).speed * 1.2));
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
