// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../abi.zig").c;
const impact = @import("../impact.zig");
const shot_rules = @import("../shot.zig");
const d = @import("../definition.zig");
const AudioContext = d.AudioContext;
const pointer = d.pointer;
const basicView = d.basicView;
const basicAudio = d.basicAudio;
const v = @import("../vector.zig");
const server = @import("../server/combat.zig");

const description = @import("../descriptions/slugger.zig");
pub const id = c.DK_W_SLUGGER;
comptime {
    if (id != description.id) @compileError("weapon transport ID mismatch");
}
pub const spec = description.spec;
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return description.predictionShot(controller);
}
pub fn update(controller: anytype) void {
    description.update(controller);
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

pub const identity = description.identity;

pub fn fire(shot: server.Fire) void {
    server.pelletBlast(@This(), shot, .{ .count = 12, .spread = 0.07, .range = 4000, .last_impact_only = true });
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
    var owned: u32 = @bitCast(inventory[0]);
    @import("../inventory_rules.zig").grantPair(&owned, ammo[0..c.DK_WEAPON_COUNT], paired.id, c.dk_weapons[paired.id].ammoMax, c.dk_weapons[paired.id].initialAmmo);
    inventory[0] = @bitCast(owned);
}
