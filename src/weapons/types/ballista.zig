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
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_ballista", // ballista
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
    return impact.scorch(context);
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = .{ .classname = "weapon_ballista", .label = "Ballista", .episode = 3, .interval = 900 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}
pub fn contact(hit: server.Contact) void {
    if (hit.victim().takedamage != 0 and !server.visited(hit.ent, hit.victim())) {
        const target = hit.victim();
        server.remember(hit.ent, target);
        hit.apply(@This(), v.f(hit.ent.damage));
        hit.ent.r.ownerNum = target.s.number;
        hit.ent.s.pos.trBase = v.madd(hit.hit.endpos, 0.01, hit.ent.s.pos.trDelta);
        hit.ent.r.currentOrigin = hit.hit.endpos;
        hit.ent.s.pos.trTime = server.now();
        hit.ent.dk.actionTime = server.now() + @as(c_int, if (server.named(target, "monster_lycanthir") or server.named(target, "monster_buboid")) 250 else 1000);
        if (target.client != null) target.client[0].ps.velocity = v.scale(hit.ent.s.pos.trDelta, 0.4);
        return;
    }
    @import("../server/bolt.zig").stick(@This(), hit);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.stuck(ent) or server.expired(@This(), ent)) return;
    if (server.now() >= ent.dk.actionTime) return;
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
