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

const description = @import("../descriptions/gas_hands.zig");
pub const id = c.DK_W_GASHANDS;
comptime {
    if (id != description.id) @compileError("weapon transport ID mismatch");
}
pub const spec = description.spec;

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return description.predictionShot(controller);
}
pub fn update(controller: anytype) void {
    description.update(controller);
}
pub fn viewCue(sequence: c_int, _: c_int) d.ViewCue {
    var cue = basicView(spec);
    if ((sequence & 1) != 0) cue.pose = pointer(spec.animation.alternate);
    return cue;
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}
pub fn impactCue(context: impact.Context) impact.Cue {
    var cue = impact.none(context);
    cue.sound = "e1/we_gasclangc.wav";
    cue.sparks = 5;
    cue.spark_color = .{ 0.7, 0.7, 1 };
    cue.light_radius = 350;
    cue.light_color = .{ 0, 0, 1 };
    cue.light_ms = 150;
    return cue;
}

pub const identity = description.identity;

pub fn fire(shot: server.Fire) void {
    const action = server.controller(@This(), shot.owner, shot.start, .melee, 900);
    action.dk.actionTime = server.now() + v.i(400 / @import("../rules.zig").attackFactor(shot.boost()));
}
pub fn projectileTick(ent: *server.Entity) void {
    const owner = server.find(ent.dk.ownerId) orelse {
        server.free(ent);
        return;
    };
    if (owner.health <= 0 or (owner.client != null and owner.client[0].ps.weapon != id)) {
        server.free(ent);
        return;
    }
    if (server.now() < ent.dk.actionTime) return;
    var start = owner.r.currentOrigin;
    start[2] += if (owner.client != null and (owner.client[0].ps.pm_flags & c.PMF_DUCKED) != 0) -9 else 16;
    const axes = server.basis(if (owner.client != null) owner.client[0].ps.viewangles else owner.s.angles);
    const hit = server.trace(start, v.madd(start, server.info(@This()).range, axes.forward), owner.s.number, c.MASK_SHOT);
    if (hit.fraction < 1) {
        const target = &c.g_entities[@intCast(hit.entityNum)];
        _ = server.impact(@This(), &hit, target.takedamage != 0);
        server.damage(@This(), .{ .victim = target, .inflictor = owner, .owner = owner, .direction = axes.forward, .point = hit.endpos, .amount = server.info(@This()).damage, .inertial = true });
    }
    server.free(ent);
}

const render = @import("../client/render.zig");
pub fn drawView(ps: *c.playerState_t) void {
    @import("../client/view.zig").draw(@This(), ps);
}
pub fn drawWorld(_: *c.refEntity_t, _: *c.centity_t) void {}
pub fn fireSound(cent: *c.centity_t) void {
    render.fired(@This(), cent);
}
pub fn drawImpact(cent: *c.centity_t) void {
    render.impact(@This(), cent);
}
pub fn drawProjectile(cent: *c.centity_t) void {
    render.model(@This(), cent);
}
var last_puff: [c.MAX_CLIENTS]c_int = @splat(0);
pub fn heldEffect(parent: *c.refEntity_t, client: c_int) void {
    if (client < 0 or client >= c.MAX_CLIENTS) return;
    const time = &last_puff[@intCast(client)];
    if (time.* > render.now()) time.* = 0;
    if (render.now() - time.* < 100) return;
    time.* = render.now();
    if ((c.CG_PointContents(&parent.origin, client) & c.MASK_WATER) != 0) return;
    var random = @import("../client/particles.zig").seed(client, time.*);
    if (random.next() >= 0.3) return;
    const side: f32 = if ((@divTrunc(render.now(), 100) + client) & 1 != 0) 1 else -1;
    const origin = v.madd(v.madd(v.madd(parent.origin, 18, parent.axis[0]), side * 6, parent.axis[1]), -6, parent.axis[2]);
    for (0..10) |_| {
        const gray = 0.1 + random.next() * 0.2;
        const velocity: v.Vec = .{ (random.next() - 0.5) * 4, (random.next() - 0.5) * 4, random.next() * 4 };
        _ = c.CG_SmokePuff(&origin, &velocity, 4, gray, gray, gray, 1, 650, render.now(), 0, 0, c.cgs.media.smokePuffShader);
    }
}
pub fn pickup(player: *server.Entity) ?bool {
    if (c.g_gametype.integer != c.GT_SINGLE_PLAYER) return null;
    const ps = &player.client[0].ps;
    var duration = v.i(@max(0, @min(c.DK_MAX_GASHANDS_TIME / 1000, server.info(@This()).lifetime)) * 1000);
    const remaining = @max(0, ps.powerups[c.PW_DK3_GASHANDS] - server.now());
    if (duration <= 0) c.G_Error("dk3: weapon_gashands requires a positive supplied lifetime");
    if (remaining >= c.DK_MAX_GASHANDS_TIME) return false;
    duration = @min(duration, c.DK_MAX_GASHANDS_TIME - remaining);
    ps.powerups[c.PW_DK3_GASHANDS] = server.now() + remaining + duration;
    ps.dk3Inventory |= @as(c_int, 1) << id;
    ps.weapon = id;
    ps.weaponstate = c.WEAPON_RAISING;
    ps.weaponTime = spec.animation.raise_ms;
    c.G_AddEvent(player, c.EV_GENERAL_SOUND, c.DK_SoundIndex("e1/we_gasstart.wav"));
    c.trap_SendServerCommand(player.s.number, c.va(@constCast("dk3_weapon %d"), @as(c_int, id)));
    return true;
}
pub fn inventoryTick(player: *server.Entity) void {
    if (c.g_gametype.integer != c.GT_SINGLE_PLAYER) return;
    const ps = &player.client[0].ps;
    if (c.DK_HasWeapon(ps, id) == 0) return;
    if (player.health <= 0) {
        c.DK_ExpireGasHands(ps);
        return;
    }
    if ((ps.weapon != id or ps.dk3CameraActive != 0 or ps.pm_type == c.PM_INTERMISSION) and ps.powerups[c.PW_DK3_GASHANDS] > 0) ps.powerups[c.PW_DK3_GASHANDS] += c.level.time - c.level.previousTime;
    if (ps.powerups[c.PW_DK3_GASHANDS] > server.now()) return;
    c.DK_ExpireGasHands(ps);
    c.G_AddEvent(player, c.EV_GENERAL_SOUND, c.DK_SoundIndex("e1/we_gasstopa.wav"));
    c.trap_SendServerCommand(player.s.number, c.va(@constCast("dk3_weapon %d"), ps.weapon));
    c.trap_SendServerCommand(player.s.number, "print \"Gas Hands has expired.\n\"");
}
pub fn loopSound(player: *server.Entity) c_int {
    const ps = &player.client[0].ps;
    return if (player.health > 0 and ps.weaponstate != c.WEAPON_RAISING and ps.pm_type == c.PM_NORMAL and ps.dk3CameraActive == 0 and c.DK_HasWeapon(ps, id) != 0) c.DK_SoundIndex("e1/we_gasloopa.wav") else 0;
}

pub fn inventoryPrediction(controller: anytype) void {
    if (controller.ps.weapon == id and controller.ps.dk3CameraActive == 0 and controller.ps.powerups[c.PW_DK3_GASHANDS] > 0 and controller.ps.powerups[c.PW_DK3_GASHANDS] <= controller.move.cmd.serverTime) c.DK_ExpireGasHands(controller.ps);
}
pub fn validPlayer(ps: *const c.playerState_t, time: c_int) bool {
    return ps.powerups[c.PW_DK3_GASHANDS] == 0 or (c.DK_HasWeapon(ps, id) != 0 and @as(i64, ps.powerups[c.PW_DK3_GASHANDS]) - time <= c.DK_MAX_GASHANDS_TIME);
}
pub fn inventoryText(ps: *const c.playerState_t, time: c_int, buffer: [*c]u8, size: c_int) void {
    _ = c.Com_sprintf(buffer, size, "%ds", @divTrunc(ps.powerups[c.PW_DK3_GASHANDS] - time + 999, 1000));
}

pub export fn DK_ExpireGasHands(ps: *c.playerState_t) callconv(.c) void {
    ps.powerups[c.PW_DK3_GASHANDS] = 0;
    @import("../controller.zig").expireGas(ps);
}
pub fn hudValue(ps: *const c.playerState_t, time: c_int) c_int {
    return @divTrunc(ps.powerups[c.PW_DK3_GASHANDS] - time + 999, 1000);
}
pub fn changeEpisode(ps: *c.playerState_t) void {
    ps.powerups[c.PW_DK3_GASHANDS] = 0;
}
