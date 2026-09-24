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

pub const id = c.DK_W_BALLISTA;
pub const splash_occlusion = false;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_ballista", // ballista
    .projectile = .{ .splash_scale = 0.5, .splash_radius = 128 },
    .visual = .{ .projectile_model = "models/e3/we_balprj.dkm" },
    .world_model = "models/e3/a_bal.dkm",
    .animation = .{
        .view_model = "models/e3/w_bal.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .raise_ms = 300,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e3/we_ballistafirea.wav",
        .ready = "e3/we_ballistaready.wav",
        .away = "e3/we_ballistaaway.wav",
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

pub const identity = .{ .classname = "weapon_ballista", .label = "Ballista", .episode = 3, .interval = 2050 };

pub fn fire(shot: server.Fire) void {
    server.schedule(@This(), shot, 150);
}
pub fn launch(shot: server.Fire) void {
    const ent = server.spawn(@This(), shot);
    ent.s.dk3Scale = 6;
    ent.r.mins = .{ -4, -4, -2 };
    ent.r.maxs = .{ 4, 4, 2 };
    if (server.liquid(shot.owner)) ent.s.pos.trDelta = v.scale(ent.s.pos.trDelta, 0.5);
    if (shot.owner.client != null) shot.owner.client[0].ps.velocity = v.madd(shot.owner.client[0].ps.velocity, -400, shot.forward);
    const sounds = [_][:0]const u8{ "e3/we_ballistaflybya.wav", "e3/we_ballistaflybyb.wav", "e3/we_ballistaflybyc.wav" };
    ent.s.loopSound = c.DK_SoundIndex(sounds[@min(2, @as(usize, @intFromFloat(server.random(ent) * 3)))]);
    server.link(ent);
}
pub fn contact(hit: server.Contact) void {
    if (hit.ent.dk.combatCount > 0) {
        if (hit.victim().client != null or hit.victim().dk.actorKind != 0) {
            hit.detonate(@This());
            return;
        }
        if (@abs(hit.hit.plane.normal[2]) > 0.1 or v.dot(v.scale(v.normal(server.velocity(hit.ent)), -1), hit.hit.plane.normal) < 0.85) {
            hit.detonate(@This());
            return;
        }
        server.stop(hit.ent, hit.hit.endpos);
        server.setState(hit.ent, .stuck);
        hit.ent.dk.actionTime = server.now() + 2000;
        hit.ent.dk.combatNext = server.now() + 100;
        return;
    }
    if (hit.victim().takedamage != 0 and (hit.victim().client != null or hit.victim().dk.actorKind != 0)) {
        const target = hit.victim();
        hit.apply(@This(), v.f(hit.ent.damage));
        const offset = v.sub(hit.hit.endpos, target.r.currentOrigin);
        var axes: usize = 0;
        for (0..3) |axis| axes += @intFromBool(@abs(offset[axis]) <= (target.r.maxs[axis] - target.r.mins[axis]) * 0.35);
        if (axes < 2) {
            hit.ent.clipmask = 0;
            hit.ent.r.ownerNum = target.s.number;
            return;
        }
        server.remember(hit.ent, target);
        hit.ent.r.ownerNum = target.s.number;
        hit.ent.s.pos.trBase = v.madd(hit.hit.endpos, 0.01, hit.ent.s.pos.trDelta);
        hit.ent.r.currentOrigin = hit.hit.endpos;
        hit.ent.s.pos.trTime = server.now();
        const mass = c.DK_ActorMass(target);
        hit.ent.dk.actionTime = server.now() + @as(c_int, if (server.named(target, "monster_lycanthir") or server.named(target, "monster_buboid")) 250 else if (mass >= 200) v.i(300000 / mass) else 1000);
        if (server.named(target, "monster_lycanthir")) hit.ent.dk.uses += 50;
        if (target.client != null) target.client[0].ps.velocity = v.scale(hit.ent.s.pos.trDelta, 0.4);
        return;
    }
    hit.detonate(@This());
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.scheduled(@This(), ent)) return;
    if (server.now() >= ent.dk.expires) {
        server.free(ent);
        return;
    }
    if (ent.dk.combatCount == 0) return;
    if (server.now() >= ent.dk.actionTime) {
        if (server.state(ent) == .stuck or ent.dk.uses >= 1) {
            server.explode(@This(), ent);
            return;
        }
        ent.dk.uses += 1;
        ent.dk.combatCount = 0;
        ent.r.ownerNum = if (server.find(ent.dk.ownerId)) |owner| owner.s.number else c.ENTITYNUM_NONE;
        return;
    }
    if (server.state(ent) == .stuck and c.g_gametype.integer == c.GT_SINGLE_PLAYER and server.now() >= ent.dk.combatNext) {
        if (server.find(ent.dk.combatTargets[0])) |target| server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = server.find(ent.dk.ownerId), .direction = v.zero, .point = target.r.currentOrigin, .amount = 1 });
        ent.dk.combatNext = server.now() + 100;
    }
    const count: usize = @intCast(@max(0, @min(ent.dk.combatCount, ent.dk.combatTargets.len)));
    for (ent.dk.combatTargets[0..count]) |target_id| {
        const target = server.find(target_id) orelse continue;
        if (target.health <= 0 or (target.client == null and target.dk.actorKind == 0)) continue;
        var goal = ent.r.currentOrigin;
        goal[2] -= (target.r.mins[2] + target.r.maxs[2]) * 0.5;
        var hit: c.trace_t = undefined;
        c.trap_Trace(&hit, &target.r.currentOrigin, &target.r.mins, &target.r.maxs, &goal, target.s.number, c.MASK_SOLID);
        if (target.client != null) {
            target.client[0].ps.origin = hit.endpos;
            target.client[0].ps.velocity = v.zero;
        }
        server.origin(target, hit.endpos);
        server.link(target);
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
}
