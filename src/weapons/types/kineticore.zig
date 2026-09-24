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

pub const id = c.DK_W_KINETICORE;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_kineticore", // kineticore
    .visual = .{ .projectile_model = "models/e4/we_kcoreshot.sp2", .impact_sprite = "models/e4/we_kcorehitb.sp2", .color = .{ 0.2, 0.65, 1 } },
    .world_model = "models/e4/a_kcore.dkm",
    .animation = .{
        .view_model = "models/e4/w_kcore.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", "ambc" },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e4/we_kcoreshoota.wav",
        .ready = "e4/we_kcoreready.wav",
        .away = "e4/we_kcoreaway.wav",
    },
    .burst_shots = 5,
    .burst_recovery_ms = 1000,
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

pub const identity = .{ .classname = "weapon_kineticore", .label = "Kineticore", .episode = 4, .interval = 100 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}

pub fn afterHit(hit: *server.Hit) void {
    hit.victim.dk.freezeLevel = @min(1, hit.victim.dk.freezeLevel + 0.2);
    hit.victim.dk.status |= 4;
}
pub fn projectileTick(ent: *server.Entity) void {
    _ = server.expired(@This(), ent);
}
pub fn contact(hit: server.Contact) void {
    hit.effect(@This());
    if (hit.victim().takedamage != 0) {
        const remaining = @max(0, @min(1, v.f(hit.ent.dk.expires - server.now()) / v.f(@max(1, hit.ent.dk.expires - hit.ent.s.time))));
        hit.apply(@This(), 2 + v.f(hit.ent.damage) * remaining);
        hit.detonate(@This());
    } else server.reflect(hit.ent, hit.hit, 1);
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
