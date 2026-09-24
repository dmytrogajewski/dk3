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

pub const id = c.DK_W_ZEUS;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_zeus", // zeus
    .ammo_pack = 1,
    .companion_pickup = false,
    .visual = .{ .color = .{ 0.2, 0.65, 1 } },
    .world_model = "models/e2/a_zeus.dkm",
    .animation = .{
        .view_model = "models/e2/w_zeuseye.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ null, null, null },
        .raise_ms = 750,
        .drop_ms = 500,
    },
    .audio = .{
        .fire = "e2/we_zeusshoot.wav",
        .ready = "e2/we_zeusready.wav",
        .away = "e2/we_zeusaway.wav",
    },
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

pub const identity = .{ .classname = "weapon_zeus", .label = "Eye of Zeus", .episode = 2, .interval = 8000 };
pub const controller_limit = 20;
fn eligible(owner: *server.Entity, target: *server.Entity) bool {
    if (!server.hostile(owner, target)) return false;
    if (target.client != null or c.DK_IsCompanion(target) != 0) return c.g_gametype.integer != c.GT_SINGLE_PLAYER;
    return target.dk.actorKind != 0;
}
fn closeEye(owner: *server.Entity) void {
    if (owner.client == null or owner.client[0].ps.weapon != id) return;
    owner.client[0].ps.dk3WeaponSequence = 128;
    owner.client[0].ps.weaponTime = 500;
}
pub fn fire(shot: server.Fire) void {
    const action = server.controller(@This(), shot.owner, shot.start, .arming, 8000);
    action.dk.actionTime = server.now() + 1750;
}
fn bolt(root: *server.Entity, source: *server.Entity, target: *server.Entity) void {
    if (root.dk.combatCount >= 20 or server.visited(root, target)) return;
    server.remember(root, target);
    root.dk.abilityCharges += 1;
    const ent = server.controller(@This(), server.find(root.dk.ownerId), source.r.currentOrigin, .beam, 700);
    ent.dk.weaponParentId = root.dk.id;
    ent.dk.action = @bitCast(source.dk.id);
    ent.dk.destinationId = @bitCast(target.dk.id);
    ent.s.eType = c.ET_DK3_MISSILE;
    ent.s.origin2 = target.r.currentOrigin;
    ent.r.svFlags = c.SVF_BROADCAST;
    ent.s.dk3Alpha = 0.6;
    const sounds = [_][:0]const u8{ "global/e_lightninga.wav", "global/e_lightningb.wav", "global/e_lightningc.wav" };
    server.sound(source, sounds[@min(2, @as(usize, @intFromFloat(server.random(root) * 3)))]);
    server.link(ent);
}
pub fn projectileTick(ent: *server.Entity) void {
    const owner = server.find(ent.dk.ownerId) orelse {
        server.free(ent);
        return;
    };
    const phase = server.state(ent);
    if (phase == .arming) {
        if (owner.health <= 0 or (owner.client != null and owner.client[0].ps.weapon != id)) {
            server.free(ent);
            return;
        }
        if (server.now() < ent.dk.actionTime) return;
        const angles = if (owner.client != null) owner.client[0].ps.viewangles else owner.s.angles;
        const yaw = angles[1] * 3.14159265 / 180;
        const forward: v.Vec = .{ @cos(yaw), @sin(yaw), 0 };
        var chosen: ?*server.Entity = null;
        for (server.entities()) |*target| {
            if (!eligible(owner, target)) continue;
            var delta = v.sub(target.r.currentOrigin, owner.r.currentOrigin);
            if (v.length(delta) > server.info(@This()).range or c.CanDamage(target, &owner.r.currentOrigin) == 0) continue;
            delta[2] = 0;
            if (v.dot(v.normal(delta), forward) < 0.70710678) continue;
            chosen = target;
            break;
        }
        if (chosen) |target| {
            server.setState(ent, .chain);
            bolt(ent, owner, target);
            if (server.liquid(owner)) server.radius(@This(), owner.r.currentOrigin, owner, server.info(@This()).damage * 2, 64, null);
        } else {
            if (c.g_gametype.integer == c.GT_SINGLE_PLAYER) {
                if (owner.client != null) owner.client[0].ps.ammo[id] = @min(server.info(@This()).ammoMax, owner.client[0].ps.ammo[id] + server.info(@This()).ammoCost);
            } else {
                server.sound(owner, "global/e_lightninga.wav");
                server.damage(@This(), .{ .victim = owner, .inflictor = owner, .owner = owner, .direction = v.zero, .point = owner.r.currentOrigin, .amount = server.info(@This()).damage * 0.5 });
            }
            closeEye(owner);
            server.free(ent);
        }
        return;
    }
    if (phase == .chain) {
        if (ent.dk.abilityCharges == 0 or server.now() >= ent.dk.expires) {
            closeEye(owner);
            server.free(ent);
        }
        return;
    }
    const root = server.find(ent.dk.weaponParentId) orelse {
        server.free(ent);
        return;
    };
    const target = server.find(ent.dk.destinationId);
    if (target == null or server.now() >= ent.dk.expires) {
        root.dk.abilityCharges = @max(0, root.dk.abilityCharges - 1);
        server.free(ent);
        return;
    }
    const victim = target.?;
    if (server.find(ent.dk.action)) |source| server.origin(ent, source.r.currentOrigin);
    ent.s.origin2 = victim.r.currentOrigin;
    server.link(ent);
    const age = server.now() - ent.s.time;
    if (ent.dk.uses == 0 and age >= 100) {
        ent.dk.uses = 1;
        const branches: usize = if (server.random(root) < 0.5) 2 else 1;
        for (0..branches) |_| {
            var best: ?*server.Entity = null;
            var distance = server.info(@This()).range * 0.25;
            for (server.entities()) |*candidate| {
                if (!eligible(owner, candidate) or server.visited(root, candidate) or c.CanDamage(candidate, &victim.r.currentOrigin) == 0) continue;
                const d2 = v.distance(candidate.r.currentOrigin, ent.r.currentOrigin);
                if (d2 < distance) {
                    distance = d2;
                    best = candidate;
                }
            }
            if (best) |next| bolt(root, victim, next);
        }
    }
    if (ent.dk.abilityState == 0 and age >= 200) {
        ent.dk.abilityState = 1;
        const count = root.dk.abilityState;
        const factor: f32 = if (count <= 5) 1 else if (count <= 10) 0.75 else if (count <= 15) 0.5 else 0.25;
        root.dk.abilityState += 1;
        server.damage(@This(), .{ .victim = victim, .inflictor = ent, .owner = owner, .direction = v.sub(victim.r.currentOrigin, ent.r.currentOrigin), .point = victim.r.currentOrigin, .amount = server.info(@This()).damage * factor });
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
    @import("../client/beam.zig").draw(cent, .{ .color = .{ 0.25, 0.45, 0.85 }, .core = .{ 0.5, 0.7, 1 }, .flare = "models/global/e_flblue.sp2", .flare_scale = 4 });
    render.light(cent.lerpOrigin, 180, .{ 0, 0, 1 });
}

pub fn viewAction(view: anytype, ps: *c.playerState_t, _: c_int, _: bool) bool {
    if (ps.dk3WeaponSequence != 128 or view.sequence == 128) return false;
    view.play("shootc", render.now(), 20);
    return true;
}
