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

pub const id = c.DK_W_SLUGGER;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_slugger", // slugger
    .world_model = "models/e4/a_slug.dkm",
    .animation = .{
        .view_model = "models/e4/w_slugger.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shootb",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 250,
        .drop_ms = 250,
    },
    .audio = .{
        .fire = "e4/we_ripgunshootc.wav",
        .ready = "e4/we_sluggerready.wav",
        .away = "e4/we_sluggeraway.wav",
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
    return impact.bullet(context);
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = .{ .classname = "weapon_slugger", .label = "Slugger", .episode = 4, .interval = 700 };

pub fn fire(shot: server.Fire) void {
    server.pellets(@This(), shot, 12, 0.07, 1);
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

pub fn muzzle(parent: *c.refEntity_t, fired: c_int) void {
    render.flash(parent, fired, .{ .model = "models/global/genflash.dkm", .scale = 2.3, .radius = 175, .shader = "dk3/fx/shotcycler-flash" });
}
pub const obsolete_pickup_model = "models/e4/wa_slug.dkm";
pub fn acquired(inventory: [*c]c_int, ammo: [*c]c_int) void {
    const paired = @import("cordite.zig");
    inventory[0] |= @as(c_int, 1) << paired.id;
    ammo[paired.id] = @min(c.dk_weapons[paired.id].ammoMax, ammo[paired.id] + c.dk_weapons[paired.id].initialAmmo);
}
