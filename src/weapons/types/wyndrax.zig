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

pub const id = c.DK_W_WYNDRAX;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_wisp", // wyndrax
    .visual = .{ .projectile_model = "models/e3/we_wisp.sp2", .color = .{ 0.35, 1, 0.2 } },
    .world_model = "models/e3/a_wyndrx.dkm",
    .animation = .{
        .view_model = "models/e3/w_wisp.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", null, null },
        .raise_ms = 600,
        .drop_ms = 400,
    },
    .audio = .{
        .fire = "e3/we_wwispshoota.wav",
        .ready = "e3/we_wwispready.wav",
        .away = "e3/we_wwispaway.wav",
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

pub const identity = .{ .classname = "weapon_wyndrax", .label = "Wyndrax's wisp", .episode = 3, .interval = 1000 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}

pub fn contact(hit: server.Contact) void {
    server.ballisticContact(@This(), hit);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.expired(@This(), ent)) return;
    const owner = server.find(ent.dk.ownerId);
    const target = server.nearest(owner, ent.r.currentOrigin, server.info(@This()).range, null) orelse return;
    const direction = v.normal(v.sub(target.r.currentOrigin, ent.r.currentOrigin));
    if (ent.dk.actionTime <= server.now()) {
        server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = owner, .direction = direction, .point = target.r.currentOrigin, .amount = v.f(ent.damage) });
        server.beam(ent.r.currentOrigin, target.r.currentOrigin, id);
        ent.dk.actionTime = server.now() + 200;
    }
    server.steer(ent, v.scale(direction, server.info(@This()).speed));
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
