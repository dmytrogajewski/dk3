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

pub const id = c.DK_W_SUNFLARE;
pub const spec: profiles.Spec = .{ // sunflare
    .projectile = .{ .gravity = true },
    .visual = .{ .projectile_model = "models/e2/we_sunprj.dkm", .impact_sprite = "models/e2/we_fire.sp2" },
    .world_model = "models/e2/a_sflare.dkm",
    .animation = .{
        .view_model = "models/e2/w_sflare.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e2/we_sflareshoota.wav",
        .ready = "e2/we_sflareready.wav",
        .away = "e2/we_sflareaway.wav",
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

pub const identity = .{ .classname = "weapon_sunflare", .label = "Sunflare", .episode = 2, .interval = 700 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}

pub fn afterHit(hit: *server.Hit) void {
    hit.victim.dk.burnEnd = server.now() + 5000;
    hit.victim.dk.status |= 2;
}
pub fn contact(hit: server.Contact) void {
    hit.effect(@This());
    hit.apply(@This(), v.f(hit.ent.damage));
    server.stop(hit.ent, hit.hit.endpos);
    server.setState(hit.ent, .active);
    hit.ent.dk.combatNext = server.now() + 1;
    hit.ent.dk.combatEnd = server.now();
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.state(ent) == .flight) {
        _ = server.expired(@This(), ent);
        return;
    }
    if (server.now() >= ent.dk.expires) {
        server.free(ent);
        return;
    }
    if (server.now() < ent.dk.combatNext) return;
    const growth = @divTrunc(server.now() - ent.dk.combatEnd, 1000);
    const range = @max(60, @min(160, 60 + v.f(growth) * 10));
    for (server.entities()) |*target| {
        if (target.inuse == 0 or target.takedamage == 0 or target.health <= 0 or v.distance(target.r.currentOrigin, ent.r.currentOrigin) > range or c.CanDamage(target, &ent.r.currentOrigin) == 0) continue;
        server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = server.find(ent.dk.ownerId), .direction = v.zero, .point = target.r.currentOrigin, .amount = 3 * (v.f(ent.damage) + v.f(growth) * 0.25) });
    }
    ent.s.dk3Scale = range / 60;
    ent.dk.combatNext = server.now() + 500;
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
