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

pub const id = c.DK_W_BOLTER;
pub const spec: profiles.Spec = .{
    .companion_episode = 3,
    .ammo_class = "ammo_bolts", // bolter
    .visual = .{ .projectile_model = "models/e3/we_bolt.dkm" },
    .world_model = "models/e3/a_bolter.dkm",
    .animation = .{
        .view_model = "models/e3/w_bolter.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 400,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e3/we_bolterfire.wav",
        .ready = "e3/we_bolterready.wav",
        .away = "e3/we_bolteraway.wav",
    },
    .projectile_muzzle = true,
};
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.sequence = (controller.ps.dk3WeaponSequence ^ 1) & 1;
    result.cost = if (result.sequence == 1 and controller.ps.ammo[id] > 0) 0 else 1;
    return result;
}
pub fn update(controller: anytype) void {
    controller.automatic(@This());
}

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

pub fn impactCue(context: impact.Context) impact.Cue {
    var cue = impact.none(context);
    cue.sound = switch (context.kind) {
        1 => null,
        3 => "e3/we_bolterhitmetal.wav",
        4 => "e3/we_bolterhitwood.wav",
        else => "e3/we_bolterhit.wav",
    };
    return cue;
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = .{ .classname = "weapon_bolter", .label = "Bolter", .episode = 3, .interval = 600 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}
pub fn impactMaterial(event: *server.Entity, hit: *const c.trace_t, flesh: bool) void {
    if (flesh) return;
    if ((hit.surfaceFlags & c.SURF_METALSTEPS) != 0) event.s.eventParm = 3;
    if ((hit.surfaceFlags & c.SURF_DK_WOOD) != 0) event.s.eventParm = 4;
}
pub fn contact(hit: server.Contact) void {
    if (hit.victim().takedamage != 0 and !server.visited(hit.ent, hit.victim())) {
        server.remember(hit.ent, hit.victim());
        hit.apply(@This(), v.f(hit.ent.damage));
        server.free(hit.ent);
        return;
    }
    @import("../server/bolt.zig").stick(@This(), hit);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.stuck(ent) or server.expired(@This(), ent)) return;
    const wet = server.liquid(ent);
    if (ent.waterlevel != @intFromBool(wet)) {
        var speed = server.velocity(ent);
        if (wet) speed = v.scale(speed, 0.5) else if (v.length(speed) > 1000) {
            speed = v.scale(v.normal(speed), 1000);
        }
        server.steer(ent, speed);
        // The reference names a Q2 sound absent from the supplied DK corpus.
        if (c.trap_FS_FOpenFile("sounds/shared/bloop4.wav", null, c.FS_READ) > 0) server.sound(ent, "shared/bloop4.wav");
        ent.waterlevel = @intFromBool(wet);
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
    if (cent.currentState.eventParm == 3) {
        var spark = cent.*;
        spark.currentState.eventParm = 1;
        @import("ion_client.zig").impact(&spark);
    }
}
pub fn drawProjectile(cent: *c.centity_t) void {
    render.model(@This(), cent);
}
