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

pub const id = c.DK_W_VENOM;
pub const spec: profiles.Spec = .{
    .companion_episode = 2,
    .ammo_class = "ammo_venomous", // venom
    .visual = .{ .projectile_model = "models/e2/we_3dvenom.dkm", .impact_sprite = "models/e2/we_vendis.sp2", .color = .{ 0.35, 1, 0.2 } },
    .world_model = "models/e2/a_venom.dkm",
    .animation = .{
        .view_model = "models/e2/w_venomous.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", null, null },
        .alternate = "melee",
        .raise_ms = 500,
        .drop_ms = 500,
    },
    .audio = .{
        .fire = "e2/we_venomshoota.wav",
        .ready = "e2/we_venomready.wav",
        .away = "e2/we_venomaway.wav",
        .variants = .{ "e2/we_venomshoota.wav", "e2/we_venomshootb.wav", "e2/we_venomshootc.wav" },
    },
    .projectile_muzzle = true,
};
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    if (biteContact(controller)) {
        result.cost = 0;
        result.sequence = 128;
    }
    return result;
}
pub fn update(controller: anytype) void {
    controller.automatic(@This());
}

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

pub fn viewCue(sequence: c_int, _: c_int) d.ViewCue {
    var cue = basicView(spec);
    if (sequence == 128) cue.pose = pointer(spec.animation.alternate);
    return cue;
}
pub fn audioCue(context: AudioContext) d.AudioCue {
    var cue = basicAudio(spec);
    if (context.entity == context.local_entity and context.sequence == 128) {
        const interval = @max(c.dk_weapons[id].interval, 1);
        const variant: usize = @intCast(1 + (@divTrunc(context.fired, interval) & 1));
        cue.fire = pointer(spec.audio.variants[variant]);
    }
    return cue;
}
pub fn impactCue(context: impact.Context) impact.Cue {
    return impact.none(context);
}

pub const identity = .{ .classname = "weapon_venomous", .label = "Venomous", .episode = 2, .interval = 330 };

pub fn fire(shot: server.Fire) void {
    if (shot.sequence() == 128) server.traceShot(@This(), shot, server.info(@This()).damage, 64) else _ = server.spawn(@This(), shot);
}
pub fn afterHit(hit: *server.Hit) void {
    const bite = hit.owner != null and hit.inflictor == hit.owner;
    const target = hit.victim;
    target.dk.poisonDamage = if (bite) 1 else if (hit.inflictor != null and hit.inflictor.?.dk.projectile != 0) hit.amount * 0.1 else 1;
    target.dk.poisonInterval = if (bite) 3000 else 1000;
    target.dk.poisonEnd = server.now() + (if (bite) @as(c_int, 15000) else v.i(server.info(@This()).lifetime * 1000));
    if (target.dk.poisonEnd <= server.now()) target.dk.poisonEnd = server.now() + 5000;
    target.dk.poisonNext = server.now() + target.dk.poisonInterval;
    target.dk.status |= 1;
}
pub fn contact(hit: server.Contact) void {
    server.ballisticContact(@This(), hit);
}
pub fn projectileTick(ent: *server.Entity) void {
    _ = server.expired(@This(), ent);
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
    if (cent.currentState.dk3Effect == 0) @import("venom_client.zig").trail(cent);
}

fn biteContact(self: anytype) bool {
    if (self.move.waterlevel > 1 or self.ps.ammo[c.DK_W_VENOM] < c.dk_weapons[c.DK_W_VENOM].ammoCost) return true;
    var eye = self.ps.origin;
    eye[2] += v.f(self.ps.viewheight);
    var forward: v.Vec = undefined;
    c.AngleVectors(&self.ps.viewangles, &forward, null, null);
    const end = v.madd(eye, 64, forward);
    var hit: c.trace_t = undefined;
    self.move.trace.?(&hit, &eye, null, null, &end, self.ps.clientNum, c.MASK_SHOT);
    return hit.fraction < 1;
}
