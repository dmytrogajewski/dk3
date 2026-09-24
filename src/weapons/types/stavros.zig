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

pub const id = c.DK_W_STAVROS;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_stavros", // stavros
    .projectile = .{ .splash_scale = 1 },
    .visual = .{ .projectile_model = "models/e3/we_fball.dkm" },
    .world_model = "models/e3/a_stav.dkm",
    .animation = .{
        .view_model = "models/e3/w_stavros.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 300,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e3/we_stavefire.wav",
        .ready = "e3/we_staveready.wav",
        .away = "e3/we_staveaway.wav",
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

pub const identity = .{ .classname = "weapon_stavros", .label = "Stavros staff", .episode = 3, .interval = 850 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}

pub fn contact(hit: server.Contact) void {
    if (server.named(hit.ent, "dk3_meteor_fragment") and hit.victim().takedamage == 0) {
        hit.ent.dk.uses += 1;
        if (hit.ent.dk.uses < 3) {
            server.reflect(hit.ent, hit.hit, 0.55);
            return;
        }
    }
    server.ballisticContact(@This(), hit);
}
pub fn projectileTick(ent: *server.Entity) void {
    _ = server.expired(@This(), ent);
}
pub fn afterExplosion(ent: *server.Entity) void {
    if (c.g_gametype.integer != c.GT_SINGLE_PLAYER or server.named(ent, "dk3_meteor_fragment")) return;
    const owner = server.find(ent.dk.ownerId) orelse return;
    for (0..5) |index| {
        const angle = v.f(index) * 2 * 3.14159265 / 5;
        const direction = v.normal(.{ @cos(angle), @sin(angle), 0.6 });
        const fragment = server.spawn(@This(), .{ .owner = owner, .start = ent.r.currentOrigin, .forward = direction });
        fragment.classname = @constCast("dk3_meteor_fragment");
        fragment.damage = @divTrunc(ent.damage, 3);
        fragment.splashDamage = fragment.damage;
        fragment.splashRadius = 80;
        fragment.s.pos.trType = c.TR_GRAVITY;
        fragment.s.pos.trDelta = v.scale(direction, 240);
        fragment.dk.expires = server.now() + 2500;
        fragment.s.dk3Scale = 0.35;
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
