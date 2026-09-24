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

pub const id = c.DK_W_ION;
pub const spec: profiles.Spec = .{
    .companion_episode = 1,
    .ammo_class = "ammo_ionpack", // ion
    .projectile = .{ .water_collision = true, .loop_sound = "e1/we_ionflyby.wav" },
    .visual = .{ .projectile_model = "models/e1/we_ionbl.dkm", .impact_sprite = "models/e1/we_ionexpl.sp2", .blast_sound = "e1/we_ionhit.wav", .color = .{ 0, 0.8, 0 } },
    .world_model = "models/e1/a_ion.dkm",
    .animation = .{
        .view_model = "models/e1/w_ionblaster.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 300,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e1/we_ionshootb.wav",
        .ready = "e1/we_ionready.wav",
        .away = "e1/we_ionaway.wav",
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
    const sounds = [_][:0]const u8{ "global/e_electronsprka.wav", "global/e_electronsprke.wav", "global/e_electronsprkg.wav", "global/e_electronsprkh.wav" };
    var cue = impact.none(context);
    cue.sound = if (context.kind == 1) "e1/we_ionexplodea.wav" else if (context.kind == 2)
        "e1/we_ionwaterhita.wav"
    else
        pointer(sounds[@intCast(context.entity & 3)]);
    return cue;
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = .{ .classname = "weapon_ionblaster", .label = "Ion blaster", .episode = 1, .interval = 500 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}

pub fn discharge(ent: *server.Entity) void {
    const event: *server.Entity = c.G_TempEntity(&ent.r.currentOrigin, c.EV_DK3_IMPACT);
    event.s.weapon = id;
    event.s.eventParm = 2;
    c.vectoangles(&ent.s.pos.trDelta, &event.s.angles);
    event.s.origin2 = v.scale(v.normal(ent.s.pos.trDelta), -1);
    ent.splashDamage = ent.damage;
    ent.splashRadius = 64;
    server.explode(@This(), ent);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.expired(@This(), ent)) return;
    if (server.liquid(ent)) discharge(ent);
}
pub fn contact(hit: server.Contact) void {
    if ((hit.hit.contents & c.MASK_WATER) != 0) {
        discharge(hit.ent);
        return;
    }
    hit.effect(@This());
    if (hit.victim().takedamage != 0) {
        hit.apply(@This(), v.f(hit.ent.damage) * (if (hit.victim() == hit.owner()) @as(f32, 0.5) else 1));
        hit.detonate(@This());
    } else {
        hit.ent.dk.uses += 1;
        if (hit.ent.dk.uses >= 3) hit.detonate(@This()) else server.reflect(hit.ent, hit.hit, 1.25);
    }
}

pub fn companionScore(score: f32, _: f32, start: v.Vec, owner: *server.Entity) f32 {
    return if ((c.trap_PointContents(&start, owner.s.number) & c.MASK_WATER) != 0) -1 else score;
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
    if (cent.currentState.eventParm == 0 or cent.currentState.eventParm == 2) @import("ion_client.zig").impact(cent);
}

pub fn muzzle(parent: *c.refEntity_t, fired: c_int) void {
    render.flash(parent, fired, .{ .model = "models/global/genflashg.dkm", .scale = 3, .alpha = 0.4, .color = .{ 0, 1, 0 }, .offset = -2, .shader = "dk3/fx/ion-flash" });
}
pub fn drawProjectile(cent: *c.centity_t) void {
    @import("ion_client.zig").draw(cent);
}
pub fn clientFrame() void {
    @import("ion_client.zig").frame();
}
pub fn resetClient() void {
    @import("ion_client.zig").reset();
}
pub const blast_frame_ms = 50;
pub fn blastEffect(cent: *c.centity_t, effect: anytype) void {
    var burst = cent.*;
    burst.currentState.eventParm = 1;
    @import("ion_client.zig").impact(&burst);
    effect.end = render.now() + 250;
    effect.scale = 0.25 + v.f(cent.currentState.number & 255) / 1020;
    effect.alpha = 0.1;
}

pub fn botUsable(owner: *server.Entity) bool {
    return owner.waterlevel != 3;
}
