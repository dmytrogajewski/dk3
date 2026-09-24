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

pub const id = c.DK_W_NOVABEAM;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_novabeam", // novabeam
    .visual = .{ .impact_sprite = "models/e4/we_novahit.sp2" },
    .world_model = "models/e4/a_nova.dkm",
    .animation = .{
        .view_model = "models/e4/w_novabeam.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .alternate = "shootb",
        .raise_ms = 500,
        .drop_ms = 450,
    },
    .audio = .{
        .fire = "e4/we_novafirea.wav",
        .ready = "e4/we_novaready.wav",
        .away = "e4/we_novaaway.wav",
        .finish = "e4/we_novafireb.wav",
    },
};
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.duration_ms = c.DK_NovaLifetime(controller.boost()) + 200;
    if (controller.ps.ammo[id] >= c.dk_weapons[id].ammoCost) result.cost = 0;
    return result;
}
pub fn update(controller: anytype) void {
    controller.automatic(@This());
}

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}
pub fn impactCue(context: impact.Context) impact.Cue {
    return impact.none(context);
}

pub const identity = .{ .classname = "weapon_novabeam", .label = "Novabeam", .episode = 4, .interval = 80 };
pub fn fire(shot: server.Fire) void {
    const boost = shot.boost();
    const lifetime = c.DK_NovaLifetime(boost);
    const ent = server.controller(@This(), shot.owner, shot.start, .beam, lifetime + 500);
    ent.dk.delay = lifetime;
    ent.dk.uses = boost;
    ent.speed = server.info(@This()).damage;
    ent.dk.combatEnd = server.now() + lifetime;
    ent.dk.combatNext = server.now() + 200;
}
pub fn projectileTick(ent: *server.Entity) void {
    const owner = server.find(ent.dk.ownerId) orelse {
        server.free(ent);
        return;
    };
    if (owner.client == null or owner.health <= 0 or owner.client[0].ps.weapon != id or server.now() >= ent.dk.expires) {
        server.free(ent);
        return;
    }
    if (server.now() < ent.dk.combatNext) return;
    const ps = &owner.client[0].ps;
    ent.dk.combatNext = server.now() + 100;
    ps.ammo[id] = @max(0, ps.ammo[id] - server.info(@This()).ammoCost);
    if (ent.dk.action != 0) {
        ps.dk3WeaponSequence = c.DK_NOVA_RETRACT;
        server.sound(owner, spec.audio.finish.?);
        server.free(ent);
        return;
    }
    const left = v.f(ent.dk.combatEnd - server.now() + 100) / v.f(@max(1, ent.dk.delay));
    const share = @max(0.2, v.f(ent.dk.uses) * 0.1);
    const amount = ent.speed * share;
    ent.speed -= amount;
    if (left <= 0.5 or ps.ammo[id] <= 0) {
        ent.dk.action = 1;
        ent.r.svFlags |= c.SVF_NOCLIENT;
        server.link(ent);
        return;
    }
    const axes = server.basis(ps.viewangles);
    var eye = owner.r.currentOrigin;
    eye[2] += v.f(ps.viewheight);
    const start = v.madd(v.madd(v.madd(eye, 14, axes.forward), 6, axes.right), -6, axes.up);
    const range = server.info(@This()).range;
    const hit = server.trace(start, v.madd(start, if (range > 0) range else 2000, axes.forward), owner.s.number, c.MASK_SHOT);
    if (hit.entityNum < c.ENTITYNUM_WORLD) server.damage(@This(), .{ .victim = &c.g_entities[@intCast(hit.entityNum)], .inflictor = ent, .owner = owner, .direction = axes.forward, .point = hit.endpos, .amount = amount });
    server.origin(ent, start);
    ent.s.origin2 = hit.endpos;
    ent.s.eType = c.ET_DK3_MISSILE;
    ent.s.dk3Effect = c.DK_FX_NOVABEAM;
    ent.s.otherEntityNum = owner.s.number;
    ent.s.dk3Alpha = @min(1, left + 0.1);
    ent.r.svFlags &= ~@as(c_int, c.SVF_NOCLIENT);
    ent.r.svFlags |= c.SVF_BROADCAST;
    server.link(ent);
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
pub fn viewAction(view: anytype, ps: *c.playerState_t, _: c_int, _: bool) bool {
    if (ps.dk3WeaponSequence != c.DK_NOVA_RETRACT or view.sequence == c.DK_NOVA_RETRACT) return false;
    view.play(spec.animation.alternate.?, render.now(), 20);
    return true;
}
pub fn drawProjectile(cent: *c.centity_t) void {
    if (cent.currentState.dk3Effect == c.DK_FX_NOVABEAM) @import("../client/beam.zig").draw(cent, .{ .color = .{ 1, 0.45, 0.12 }, .core = .{ 1, 0.85, 0.6 }, .flare = "models/global/e_florange.sp2", .flare_scale = 0.3, .muzzle = true }) else render.model(@This(), cent);
}

pub fn validPlayer(ps: *const c.playerState_t, _: c_int) bool {
    return ps.dk3NovaSpent >= 0 and ps.dk3NovaSpent <= 2000;
}

pub export fn DK_NovaLifetime(boost: c_int) callconv(.c) c_int {
    const lifetime = if (c.dk_weapons[id].lifetime > 0) c.dk_weapons[id].lifetime * 1000 else 2000;
    if (boost <= 0) return v.i(lifetime);
    return @intFromFloat(lifetime / (@as(f32, @floatFromInt(boost + 1)) * 0.5));
}
