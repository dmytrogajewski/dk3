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
    .visual = .{ .color = .{ 0.2, 0.65, 1 } },
    .world_model = "models/e2/a_zeus.dkm",
    .animation = .{
        .view_model = "models/e2/w_zeuseye.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 750,
        .drop_ms = 500,
    },
    .audio = .{
        .fire = "e2/we_zeusshoota.wav",
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

pub const identity = .{ .classname = "weapon_zeus", .label = "Eye of Zeus", .episode = 2, .interval = 1200 };
pub fn fire(shot: server.Fire) void {
    if ((c.trap_PointContents(&shot.start, shot.owner.s.number) & c.MASK_WATER) != 0) {
        server.radius(@This(), shot.start, shot.owner, server.info(@This()).damage * 2, 64, null);
        server.blast(shot.start, id);
    }
    _ = server.controller(@This(), shot.owner, shot.start, .chain, 3000);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.now() < ent.dk.combatNext) return;
    const owner = server.find(ent.dk.ownerId);
    const target = server.nearest(owner, ent.r.currentOrigin, server.info(@This()).range, ent);
    if (target == null or ent.dk.combatCount >= 16 or server.now() >= ent.dk.expires) {
        server.free(ent);
        return;
    }
    const victim = target.?;
    const direction = v.normal(v.sub(victim.r.currentOrigin, ent.r.currentOrigin));
    server.beam(ent.r.currentOrigin, victim.r.currentOrigin, id);
    const factor: f32 = switch (ent.dk.combatCount) {
        0 => 1,
        1 => 0.75,
        2 => 0.5,
        else => 0.25,
    };
    server.damage(@This(), .{ .victim = victim, .inflictor = ent, .owner = owner, .direction = direction, .point = victim.r.currentOrigin, .amount = v.f(ent.damage) * factor });
    server.remember(ent, victim);
    server.origin(ent, victim.r.currentOrigin);
    ent.dk.combatNext = server.now() + 150;
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
