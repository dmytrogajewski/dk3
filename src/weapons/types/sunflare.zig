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

const description = @import("../descriptions/sunflare.zig");
pub const id = c.DK_W_SUNFLARE;
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
    return impact.none(context);
}
pub fn viewCue(_: c_int, _: c_int) d.ViewCue {
    return basicView(spec);
}
pub fn audioCue(_: AudioContext) d.AudioCue {
    return basicAudio(spec);
}

pub const identity = description.identity;

const flame_life_ms = 5000;
const linger_ms = 5000;

pub fn fire(shot: server.Fire) void {
    var angles: v.Vec = undefined;
    c.vectoangles(&shot.forward, &angles);
    angles[0] -= 22.5;
    var lob = shot;
    c.AngleVectors(&angles, &lob.forward, null, null);
    _ = server.spawn(@This(), lob);
}

pub fn initializeProjectile(ent: *server.Entity) void {
    ent.r.mins = .{ -12, -12, -18 };
    ent.r.maxs = .{ 12, 12, 18 };
    ent.s.dk3Scale = 2;
    ent.s.generic1 = 0;
    ent.s.apos.trType = c.TR_LINEAR;
    ent.s.apos.trTime = server.now();
    for (&ent.s.apos.trDelta) |*spin| spin.* = 90 + server.random(ent) * 60;
    // Gold has no flight timeout; this only reaps pots lost outside the map.
    ent.dk.expires = server.now() + 30000;
}

/// Gold sunflareExplode: the pot becomes an invisible flame source that
/// drops to the floor and starts burning on its next think.
fn ignite(ent: *server.Entity, point: v.Vec) void {
    server.blast(point, id);
    server.stop(ent, point);
    server.setState(ent, .active);
    ent.r.mins = .{ 0, 0, -18 };
    ent.r.maxs = .{ 0, 0, 18 };
    ent.clipmask = c.MASK_SOLID;
    ent.r.ownerNum = c.ENTITYNUM_NONE;
    ent.s.apos.trType = c.TR_STATIONARY;
    ent.dk.combatNext = server.now() + 100;
}

pub fn contact(hit: server.Contact) void {
    const ent = hit.ent;
    if (server.state(ent) == .active) {
        server.stop(ent, hit.hit.endpos);
        return;
    }
    const victim = hit.victim();
    if (victim.takedamage != 0) hit.apply(@This(), 5 * v.f(hit.ent.damage));
    ignite(ent, v.madd(hit.hit.endpos, 4, hit.hit.plane.normal));
}

/// Gold flame_damage: every damageable within range, no line-of-sight check,
/// the thrower included.
fn burn(ent: *server.Entity, count: c_int) void {
    const range = 60 + 10 * v.f(count);
    const amount = 3 * (v.f(ent.damage) + 0.25 * v.f(count));
    const owner = server.find(ent.dk.ownerId);
    for (server.entities()) |*target| {
        if (target == ent or target.inuse == 0 or target.takedamage == 0) continue;
        if (v.distance(target.r.currentOrigin, ent.r.currentOrigin) > range) continue;
        server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = owner, .direction = v.zero, .point = ent.r.currentOrigin, .amount = amount });
    }
}

pub fn projectileTick(ent: *server.Entity) void {
    const now = server.now();
    if (server.state(ent) != .active) {
        if (server.liquid(ent)) return ignite(ent, ent.r.currentOrigin);
        if (now >= ent.dk.expires) server.free(ent);
        return;
    }
    if (ent.s.generic1 == 0) {
        if (now < ent.dk.combatNext) return;
        burn(ent, 0);
        ent.s.generic1 = @intFromFloat(5 + 4.9 * server.random(ent));
        ent.s.time2 = now;
        ent.dk.expires = now + flame_life_ms;
        ent.dk.combatEnd = now + flame_life_ms + linger_ms;
        ent.dk.combatNext = now + 100;
        server.sound(ent, "e2/we_sflareexploded.wav");
        if (!server.liquid(ent)) {
            ent.s.pos.trType = c.TR_GRAVITY;
            server.steer(ent, v.zero);
        }
        return;
    }
    if (now >= ent.dk.combatEnd) return server.free(ent);
    if (now >= ent.dk.expires or now < ent.dk.combatNext) return;
    burn(ent, ent.s.generic1);
    ent.dk.combatNext = now + 300;
}

const render = @import("../client/render.zig");
const particles = @import("../client/particles.zig");
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

/// Gold EF2_SUNFLARE_FLAME: the pot burns while held, out between the throw
/// and the end of the throw animation, and never under water.
pub fn heldEffect(parent: *c.refEntity_t, number: c_int) void {
    const cent = if (number == c.cg.predictedPlayerState.clientNum) &c.cg.predictedPlayerEntity else &c.cg_entities[@intCast(number)];
    if (render.now() - cent.muzzleFlashTime < c.dk_weapons[id].interval) return;
    const point = render.muzzlePoint(parent);
    if ((c.CG_PointContents(&point, -1) & c.MASK_WATER) != 0) return;
    const first_person = (parent.renderfx & c.RF_FIRST_PERSON) != 0;
    var angles: v.Vec = undefined;
    c.vectoangles(&parent.axis[0], &angles);
    const flame = if (first_person) point else v.add(point, .{ 0, 0, 3.5 });
    _ = render.sprite("models/global/e_fireb.sp2", @mod(@divTrunc(render.now(), 100), 7), flame, angles, if (first_person) 0.1 else 0.3, 1, .{ 1, 1, 1 }, c.DK_SPRITE_ADDITIVE);
    render.light(flame, 160 + 10 * @as(f32, @floatFromInt(@mod(render.now(), 7))) / 7, .{ 0.7, 0.3, 0 });
}

pub fn blastEffect(cent: *c.centity_t, _: anytype) void {
    var random = particles.seed(cent.currentState.number, render.now());
    smoke(cent.lerpOrigin, 6, &random);
}

fn smoke(origin: v.Vec, count: usize, random: *particles.Random) void {
    for (0..count) |_| {
        const velocity: v.Vec = .{ (random.next() * 2 - 1) * 20, (random.next() * 2 - 1) * 20, 20 + random.next() * 30 };
        particles.add(.{ .start = render.now(), .end = render.now() + 1200, .origin = origin, .velocity = velocity, .radius = 6 + random.next() * 6, .color = .{ 0.2, 0.2, 0.2 }, .alpha = 0.4, .shader = c.trap_R_RegisterShader("dk3/particle/smoke") });
    }
}

/// Gold TEF_SUNFLARE_FX: a ring of floor-hugging flames plus a big centre
/// flame; they shrink for about 3.3 s, then fade out.
fn flames(cent: *c.centity_t) void {
    const state = &cent.currentState;
    const count: usize = @intCast(@max(0, @min(9, state.generic1)));
    const ticks = v.f(render.now() - state.time2) / 50;
    const scale = @max(1, 2 - 0.015 * ticks);
    const alpha = 0.6 - 0.015 * @max(0, ticks - 66.7);
    if (alpha < 0.05) return;
    const underwater = (c.CG_PointContents(&cent.lerpOrigin, -1) & c.MASK_WATER) != 0;
    const spread = 50 + 10 * (v.f(count) - 5);
    var random = particles.seed(state.number, state.time2);
    const sprite = "models/global/e2_firea.sp2";
    const frame = @divTrunc(render.now() - state.time2, 50);
    for (0..count + 1) |index| {
        var point = cent.lerpOrigin;
        var size = scale;
        const phase: c_int = @intFromFloat(random.next() * 16);
        const yaw = random.next() * 90;
        if (index < count) {
            point[0] += (random.next() * 2 - 1) * spread;
            point[1] += (random.next() * 2 - 1) * spread;
            if (!underwater) {
                var ground: c.trace_t = undefined;
                const top = v.add(point, .{ 0, 0, 50 });
                const bottom = v.add(point, .{ 0, 0, -100 });
                c.CG_Trace(&ground, &top, null, null, &bottom, state.number, c.MASK_SOLID);
                point[2] = ground.endpos[2];
            }
        } else size = 2.5 * scale;
        for ([_]f32{ 0, 90 }) |turn| _ = render.sprite(sprite, frame + phase, point, .{ 0, yaw + turn, 0 }, size, alpha, .{ 1, 1, 1 }, c.DK_SPRITE_ORIENTED | c.DK_SPRITE_ADDITIVE);
        if (index == count) continue;
        render.light(point, 150 + 50 * random.next(), .{ 0.8, 0.4, 0.2 });
        if (!underwater) _ = render.sprite("models/global/e_sflorange.sp2", 0, v.add(point, .{ 0, 0, 1 }), .{ -90, 0, 0 }, 1.5 * size, alpha + 0.2, .{ 1, 1, 1 }, c.DK_SPRITE_ORIENTED | c.DK_SPRITE_ADDITIVE);
    }
    if (!underwater and cent.trailTime < render.now() - 100) {
        cent.trailTime = render.now();
        var puff = particles.seed(state.number, render.now());
        smoke(v.add(cent.lerpOrigin, .{ (puff.next() * 2 - 1) * spread, (puff.next() * 2 - 1) * spread, 0 }), 1, &puff);
    }
}

pub fn drawProjectile(cent: *c.centity_t) void {
    const state = &cent.currentState;
    if (state.generic1 > 0) return flames(cent);
    if (state.pos.trType == c.TR_STATIONARY or state.apos.trType == c.TR_STATIONARY) return;
    render.model(@This(), cent);
    if (cent.trailTime < render.now() - 40) {
        cent.trailTime = render.now();
        var random = particles.seed(state.number, render.now());
        smoke(cent.lerpOrigin, 1, &random);
    }
}
