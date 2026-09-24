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

pub const id = c.DK_W_DISCUS;
pub const spec: profiles.Spec = .{ // discus
    .visual = .{ .projectile_model = "models/e2/we_discus.dkm", .spin = true },
    .world_model = "models/e2/a_discus.dkm",
    .animation = .{
        .view_model = "models/e2/w_discus.dkm",
        .ready = "readya",
        .away = "awaya",
        .fire = "shootb",
        .idle = .{ "amba", "ambb", null },
        .alternate = "shootc",
        .raise_ms = 400,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e2/we_discfire.wav",
        .ready = "e2/we_discreadya.wav",
        .away = "e2/we_discawaya.wav",
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

pub const identity = .{ .classname = "weapon_discus", .label = "Discus of Daedalus", .episode = 2, .interval = 650 };

pub fn fire(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}

fn caught(ent: *server.Entity, owner: *server.Entity) void {
    if (owner.client != null) owner.client[0].ps.ammo[id] += 1 else if (c.DK_IsCompanion(owner) != 0) owner.dk.ammunition[id] += 1;
    server.free(ent);
}
pub fn contact(hit: server.Contact) void {
    if (hit.owner()) |owner| {
        if (hit.victim() == owner) {
            caught(hit.ent, owner);
            return;
        }
    }
    hit.effect(@This());
    if (hit.victim().takedamage != 0) hit.apply(@This(), v.f(hit.ent.damage));
    hit.ent.dk.action = 1;
    server.reflect(hit.ent, hit.hit, 1);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.expired(@This(), ent)) return;
    const owner = server.find(ent.dk.ownerId) orelse return;
    if (ent.dk.action == 0 and server.now() - ent.s.time <= 500) return;
    const direction = v.sub(owner.r.currentOrigin, ent.r.currentOrigin);
    if (v.length(direction) < 32) {
        caught(ent, owner);
        return;
    }
    server.steer(ent, v.scale(v.normal(direction), server.info(@This()).speed));
    ent.r.ownerNum = c.ENTITYNUM_NONE;
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
