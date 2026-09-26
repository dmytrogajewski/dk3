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
    .ammo_pack = 30,
    .projectile = .{ .direct_scale = 0, .splash_scale = 1, .splash_radius = 100 },
    .visual = .{ .projectile_model = "models/e2/we_tritip.dkm", .color = .{ 0.4, 0.4, 0.9 }, .blast_sound = "global/e_wexplodee.wav", .glow = false },
    .world_model = "models/e2/a_tri.dkm",
    .animation = .{
        .view_model = "models/e2/w_trident.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", null, null },
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
    var result = shot_rules.standard(controller);
    result.cost = @max(1, @min(3, controller.ps.ammo[id]));
    result.sequence = result.cost;
    return result;
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

pub const identity = .{ .classname = "weapon_trident", .label = "Trident of Poseidon", .episode = 2, .interval = 750 };

pub fn fire(shot: server.Fire) void {
    const count: usize = @intCast(@max(1, @min(3, shot.sequence())));
    var tips: [3]?*server.Entity = @splat(null);
    const offsets = [_]v.Vec{ .{ 0, 30, 18 }, .{ -14, 30, 12 }, .{ 14, 30, 12 } };
    for (0..count) |index| {
        var launch = shot;
        if (shot.owner.client != null) {
            const ps = &shot.owner.client[0].ps;
            const axes = server.basis(ps.viewangles);
            var eye = ps.origin;
            eye[2] += v.f(ps.viewheight);
            const offset = offsets[index];
            launch.start = v.madd(v.madd(eye, offset[0], axes.right), offset[1], axes.forward);
            launch.start[2] += offset[2] - c.DEFAULT_VIEWHEIGHT;
            launch.start = server.trace(eye, launch.start, shot.owner.s.number, c.MASK_SHOT).endpos;
            const aim = server.trace(eye, v.madd(eye, 2000, axes.forward), shot.owner.s.number, c.MASK_SHOT).endpos;
            const delta = v.sub(aim, launch.start);
            launch.forward = if (v.dot(delta, axes.forward) > 1) v.normal(delta) else axes.forward;
            ps.velocity = v.madd(ps.velocity, -50, axes.forward);
        }
        const tip = server.spawn(@This(), launch);
        tip.s.dk3Scale = 3;
        tips[index] = tip;
    }
    const middle = tips[0].?;
    if (tips[1]) |left| {
        middle.dk.combatTargets[0] = @bitCast(left.dk.id);
        left.dk.destinationId = @bitCast(middle.dk.id);
    }
    if (tips[2]) |right| {
        middle.dk.combatTargets[1] = @bitCast(right.dk.id);
        right.dk.destinationId = @bitCast(middle.dk.id);
    }
}
pub fn modifyHit(hit: *server.Hit) void {
    if (server.named(hit.victim, "monster_medusa")) hit.amount = 0;
    if (hit.victim == hit.owner and (hit.flags & c.DAMAGE_RADIUS) != 0) hit.amount *= 0.65;
}
pub fn contact(hit: server.Contact) void {
    const wet = (c.trap_PointContents(&hit.hit.endpos, hit.ent.s.number) & c.MASK_WATER) != 0;
    hit.ent.splashDamage = v.i(server.info(@This()).damage * (if (wet) @as(f32, 2) else 1) * (if (hit.ent.dk.abilityState != 0) @as(f32, 10) else 1));
    hit.detonate(@This());
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.find(ent.dk.ownerId) == null) {
        server.free(ent);
        return;
    }
    ent.s.dk3Scale = 3 * (if (server.liquid(ent)) @as(f32, 2) else 1) * (if (ent.dk.abilityState != 0) @as(f32, 2) else 1);
    if (ent.dk.destinationId != 0 or ent.dk.abilityState != 0 or server.now() < ent.dk.combatNext) return;
    ent.dk.combatNext = server.now() + 100;
    const left = server.find(ent.dk.combatTargets[0]) orelse return;
    const right = server.find(ent.dk.combatTargets[1]) orelse return;
    // Stable IDs avoid binding to a newly spawned projectile in a reused slot.
    if (@as(c_uint, @bitCast(left.dk.destinationId)) != ent.dk.id or @as(c_uint, @bitCast(right.dk.destinationId)) != ent.dk.id) return;
    const age = server.now() - ent.s.time;
    if (age >= 360) {
        server.free(left);
        server.free(right);
        ent.dk.abilityState = 1;
        ent.s.dk3Scale *= 2;
        server.radius(@This(), ent.r.currentOrigin, server.find(ent.dk.ownerId), server.info(@This()).damage, 128, ent);
        server.sound(ent, if (server.random(ent) < 0.5) "global/e_lightningb.wav" else "global/e_lightningc.wav");
        server.blast(ent.r.currentOrigin, id);
        return;
    }
    const axes = server.directionBasis(ent.s.pos.trDelta);
    const lateral: f32 = if (age < 180) 200 else -200;
    server.steer(left, v.madd(ent.s.pos.trDelta, -lateral, axes.right));
    server.steer(right, v.madd(ent.s.pos.trDelta, lateral, axes.right));
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
    render.light(cent.lerpOrigin, 100, spec.visual.color);
}

pub fn muzzle(parent: *c.refEntity_t, fired: c_int) void {
    render.flash(parent, fired, .{ .model = "models/e2/we_mftrdnt.sp2", .scale = 0.15, .color = .{ 0.8, 0.8, 1 }, .sprite_model = true });
}
