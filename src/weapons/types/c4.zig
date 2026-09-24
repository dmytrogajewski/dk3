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

pub const id = c.DK_W_C4;
pub const spec: profiles.Spec = .{
    .splash_hazard = true,
    .ammo_class = "ammo_c4", // c4
    .projectile = .{ .gravity = true, .splash_scale = 1, .splash_radius = 300 },
    .visual = .{ .projectile_model = "models/e1/we_c4prj.dkm" },
    .world_model = "models/e1/a_c4.dkm",
    .animation = .{
        .view_model = "models/e1/w_c4.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e1/we_c4shoota.wav",
        .ready = "e1/we_c4ready.wav",
        .away = "e1/we_c4away.wav",
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

pub const identity = .{ .classname = "weapon_c4", .label = "C4 Vizatergo", .episode = 1, .interval = 600 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}
const ChargeState = enum(c_int) { flying, attached, detonating };
fn phase(ent: *server.Entity) ChargeState {
    return @enumFromInt(ent.dk.action);
}
fn arm(ent: *server.Entity) void {
    if (phase(ent) == .detonating) return;
    ent.dk.action = @intFromEnum(ChargeState.detonating);
    ent.dk.expires = server.now() + 100;
    ent.takedamage = c.qfalse;
}
pub fn die(ent: [*c]server.Entity, _: [*c]server.Entity, _: [*c]server.Entity, _: c_int, _: c_int) callconv(.c) void {
    arm(@ptrCast(ent));
}
pub fn initializeProjectile(ent: *server.Entity) void {
    ent.health = 5;
    ent.takedamage = c.qtrue;
    ent.die = die;
    ent.r.contents = c.CONTENTS_CORPSE;
    ent.r.mins = @splat(-8);
    ent.r.maxs = @splat(8);
}
pub fn restore(ent: *server.Entity) void {
    ent.die = die;
    if (ent.s.pos.trType == c.TR_STATIONARY) ent.r.ownerNum = c.ENTITYNUM_NONE;
}
pub fn detonate(owner: *server.Entity) c_int {
    var count: c_int = 0;
    for (server.entities()) |*ent| {
        if (ent.inuse == 0 or ent.dk.projectile == 0 or ent.s.weapon != id or ent.dk.ownerId != owner.dk.id or phase(ent) == .detonating) continue;
        arm(ent);
        count += 1;
    }
    return count;
}
pub fn contact(hit: server.Contact) void {
    const point = v.madd(hit.hit.endpos, 1, hit.hit.plane.normal);
    hit.ent.r.currentOrigin = point;
    if (hit.victim().takedamage != 0) {
        server.explode(@This(), hit.ent);
        return;
    }
    server.stop(hit.ent, point);
    if (phase(hit.ent) != .detonating) hit.ent.dk.action = @intFromEnum(ChargeState.attached);
    hit.ent.dk.actionTime = server.now() + 1000;
    hit.ent.r.ownerNum = c.ENTITYNUM_NONE;
    if (hit.victim().s.eType == c.ET_MOVER) hit.ent.dk.parentId = hit.victim().dk.id;
    c.G_AddEvent(hit.ent, c.EV_GENERAL_SOUND, c.DK_SoundIndex("e1/we_c4cona.wav"));
    server.link(hit.ent);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.expired(@This(), ent)) return;
    if (phase(ent) != .attached or server.now() < ent.dk.actionTime) return;
    var nearest: f32 = 300;
    for (server.entities()) |*target| {
        if (target.inuse == 0 or target.health <= 0 or (target.client == null and target.dk.actorKind == 0) or (target.client != null and target.client[0].sess.sessionTeam == c.TEAM_SPECTATOR)) continue;
        const distance = v.distance(ent.r.currentOrigin, target.r.currentOrigin);
        if (distance >= nearest or c.CanDamage(target, &ent.r.currentOrigin) == 0) continue;
        if (distance < 150) {
            server.explode(@This(), ent);
            return;
        }
        nearest = distance;
    }
    if (server.now() >= ent.dk.nextUse) {
        c.G_AddEvent(ent, c.EV_GENERAL_SOUND, c.DK_SoundIndex("e1/we_c4beepa.wav"));
        ent.dk.nextUse = server.now() + @as(c_int, if (nearest < 300) 350 else 1500);
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
pub fn validProjectile(ent: *const server.Entity) bool {
    return ent.dk.action >= 0 and ent.dk.action <= 2;
}
