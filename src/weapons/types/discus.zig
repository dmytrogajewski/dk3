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
    .projectile = .{ .loop_sound = "e2/we_discshoota.wav" },
    .projectile_muzzle = true,
};
const melee_sequence = 128;
const flag_reflected = 1;
const flag_seek = 2;

/// Something within 100 units turns the throw into a free melee swing.
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    var eye = controller.ps.origin;
    eye[2] += v.f(controller.ps.viewheight);
    var forward: v.Vec = undefined;
    c.AngleVectors(&controller.ps.viewangles, &forward, null, null);
    const end = v.madd(eye, 100, forward);
    var hit: c.trace_t = undefined;
    controller.move.trace.?(&hit, &eye, null, null, &end, controller.ps.clientNum, c.MASK_SHOT);
    if (hit.fraction < 1) {
        result.cost = 0;
        result.sequence = melee_sequence + @mod(@divTrunc(controller.move.cmd.serverTime, 50), 2);
    }
    return result;
}
pub fn update(controller: anytype) void {
    controller.automatic(@This());
}

pub fn blastSound(_: c_int) [*c]const u8 {
    return pointer(spec.visual.blast_sound);
}

/// Frame 1 marks a melee strike, frame 2 a disc touch without damage.
pub fn impactCue(context: impact.Context) impact.Cue {
    var cue = impact.none(context);
    cue.sound = if (context.kind == 1) "global/m_knifehitb.wav" else "e2/we_dischit1.wav";
    if (context.frame == 1) {
        cue.sparks = if (context.kind == 1) 4 else 10;
        cue.spark_color = if (context.kind == 1) .{ 0.2, 0.4, 0.8 } else .{ 0.65, 0.65, 0.1 };
    } else if (context.frame == 2) {
        cue.sparks = 1;
        cue.spark_color = .{ 1, 1, 0.4 };
    }
    return cue;
}
pub fn impactMaterial(event: *server.Entity, _: *const c.trace_t, _: bool) void {
    event.s.frame = marker;
}
var marker: c_int = 0;
pub fn viewCue(sequence: c_int, _: c_int) d.ViewCue {
    var cue = basicView(spec);
    if (sequence == melee_sequence) cue.pose = "shootc" else if (sequence == melee_sequence + 1) cue.pose = "shootd";
    return cue;
}
pub fn audioCue(context: AudioContext) d.AudioCue {
    var cue = basicAudio(spec);
    if (context.entity == context.local_entity and context.sequence >= melee_sequence) cue.fire = "e2/we_discambb.wav";
    return cue;
}

pub const identity = .{ .classname = "weapon_discus", .label = "Discus of Daedalus", .episode = 2, .interval = 650 };

fn effect(hit: *const c.trace_t, flesh: bool, frame: c_int) void {
    marker = frame;
    _ = server.impact(@This(), hit, flesh);
    marker = 0;
}

fn melee(shot: server.Fire) void {
    var eye = shot.owner.r.currentOrigin;
    if (shot.owner.client != null) eye = shot.owner.client[0].ps.origin;
    eye[2] += if (shot.owner.client != null) v.f(shot.owner.client[0].ps.viewheight) else shot.owner.r.maxs[2] * 0.6;
    const hit = server.trace(eye, v.madd(eye, 120, shot.forward), shot.owner.s.number, c.MASK_SHOT);
    if (hit.fraction == 1) return;
    const victim = &c.g_entities[@intCast(hit.entityNum)];
    const damaged = hit.entityNum < c.ENTITYNUM_WORLD and victim.takedamage != 0;
    effect(&hit, damaged, 1);
    if (damaged) server.damage(@This(), .{ .victim = victim, .inflictor = shot.owner, .owner = shot.owner, .direction = shot.forward, .point = hit.endpos, .amount = server.info(@This()).damage });
}

pub fn fire(shot: server.Fire) void {
    if (shot.sequence() >= melee_sequence) return melee(shot);
    const ent = server.spawn(@This(), shot);
    var eye = shot.owner.r.currentOrigin;
    if (shot.owner.client != null) {
        eye = shot.owner.client[0].ps.origin;
        eye[2] += v.f(shot.owner.client[0].ps.viewheight);
    }
    // Gold starts homing on the auto-aim target under the crosshair.
    const aim = server.trace(eye, v.madd(eye, 2000, shot.forward), shot.owner.s.number, c.MASK_SHOT);
    if (aim.entityNum < c.ENTITYNUM_WORLD and server.hostile(shot.owner, &c.g_entities[@intCast(aim.entityNum)]))
        ent.dk.destinationId = @bitCast(c.g_entities[@intCast(aim.entityNum)].dk.id);
}

pub fn initializeProjectile(ent: *server.Entity) void {
    ent.r.mins = .{ -8, -8, -4 };
    ent.r.maxs = .{ 8, 8, 4 };
    ent.dk.action = flag_seek;
    ent.dk.destinationId = 0;
    ent.dk.speedOverride = server.info(@This()).speed;
    ent.dk.expires = server.now() + 5000;
    ent.dk.actionTime = server.now() + 100;
    ent.dk.combatNext = 0;
}

fn caught(ent: *server.Entity, catcher: *server.Entity) void {
    const maximum = server.info(@This()).ammoMax;
    server.sound(catcher, "e2/we_disccatch.wav");
    if (catcher.client != null) {
        const ps = &catcher.client[0].ps;
        ps.dk3Inventory |= @as(c_int, 1) << id;
        ps.ammo[id] = @min(ps.ammo[id] + 1, if (maximum > 0) maximum else ps.ammo[id] + 1);
    } else if (c.DK_IsCompanion(catcher) != 0) {
        catcher.dk.ammunition[id] = @min(catcher.dk.ammunition[id] + 1, if (maximum > 0) maximum else catcher.dk.ammunition[id] + 1);
    }
    server.free(ent);
}

fn alive(ent: ?*server.Entity) bool {
    const target = ent orelse return false;
    return target.inuse != 0 and target.health > 0;
}

fn center(target: *server.Entity) v.Vec {
    return if (target.r.bmodel != 0) v.scale(v.add(target.r.absmin, target.r.absmax), 0.5) else target.r.currentOrigin;
}

fn launch(ent: *server.Entity, direction: v.Vec) void {
    server.steer(ent, v.scale(v.normal(direction), ent.dk.speedOverride));
}

/// Gold selectTarget(SELECT_TARGET_PATH): the visible candidate within 2000
/// units whose direction deviates least from the flight path.
fn pathTarget(ent: *server.Entity, owner: *server.Entity) ?*server.Entity {
    const path = v.normal(server.velocity(ent));
    var best: ?*server.Entity = null;
    var smallest: f32 = 9999;
    for (server.entities()) |*candidate| {
        if (candidate == ent or candidate == owner or candidate.inuse == 0 or candidate.takedamage == 0) continue;
        if (v.distance(candidate.r.currentOrigin, ent.r.currentOrigin) > 2000 or !server.hostile(owner, candidate)) continue;
        if (server.trace(ent.r.currentOrigin, candidate.r.currentOrigin, ent.s.number, c.MASK_SOLID).fraction < 1) continue;
        const deviation = v.sub(path, v.normal(v.sub(candidate.r.currentOrigin, ent.r.currentOrigin)));
        const x = @abs(deviation[0]);
        const y = @abs(deviation[1]);
        if (x < 0.25 and y < 0.25 and x + y < smallest) {
            smallest = x + y;
            best = candidate;
        }
    }
    return best;
}

pub fn contact(hit: server.Contact) void {
    const ent = hit.ent;
    if (server.state(ent) == .active) return droppedContact(hit);
    const owner = hit.owner() orelse {
        server.free(ent);
        return;
    };
    const victim = hit.victim();
    if (victim == owner) return caught(ent, owner);
    const seeking = ent.dk.destinationId != 0 and (ent.dk.action & flag_seek) != 0;
    ent.dk.action = (ent.dk.action & ~@as(c_int, flag_seek)) | @as(c_int, if (seeking) 0 else flag_seek);
    ent.dk.destinationId = @bitCast(owner.dk.id);
    var home = false;
    if (victim.takedamage != 0 and ent.dk.combatNext == 0) {
        ent.dk.combatNext = 3;
        effect(hit.hit, victim.client != null or victim.dk.actorKind != 0, 0);
        const friendly = c.g_gametype.integer == c.GT_SINGLE_PLAYER and (ent.dk.action & flag_reflected) != 0 and victim.client != null;
        if (!friendly) hit.apply(@This(), v.f(ent.damage));
        if (victim.r.bmodel != 0 or victim.health <= 0) home = true;
    } else effect(hit.hit, false, 2);
    const normal = hit.hit.plane.normal;
    const forward = v.normal(server.velocity(ent));
    var direction = v.madd(forward, -2 * v.dot(forward, normal), normal);
    ent.r.currentOrigin = v.madd(hit.hit.endpos, 1, normal);
    if (home) {
        ent.dk.action |= flag_seek;
        direction = v.sub(owner.r.currentOrigin, ent.r.currentOrigin);
        ent.r.currentOrigin = v.madd(ent.r.currentOrigin, 15, v.normal(direction));
    } else if (victim.client != null or victim.dk.actorKind != 0) {
        // Go straight home unless the creature stands in the way; then
        // bounce off a jittered normal so it doesn't ping-pong.
        var block: c.trace_t = undefined;
        c.trap_Trace(&block, &ent.r.currentOrigin, &ent.r.mins, &ent.r.maxs, &owner.r.currentOrigin, ent.s.number, c.MASK_SHOT);
        if (block.entityNum == victim.s.number) {
            ent.dk.action &= ~@as(c_int, flag_seek);
            ent.dk.destinationId = 0;
            var jitter = normal;
            jitter[0] += (if (server.random(ent) < 0.5) @as(f32, 1) else -1) * (0.1 + 0.2 * server.random(ent));
            jitter[1] += (if (server.random(ent) < 0.5) @as(f32, 1) else -1) * (0.1 + 0.2 * server.random(ent));
            jitter = v.normal(jitter);
            direction = v.madd(forward, -2 * v.dot(forward, jitter), jitter);
        } else direction = v.sub(owner.r.currentOrigin, ent.r.currentOrigin);
    }
    ent.dk.action |= flag_reflected;
    ent.r.ownerNum = c.ENTITYNUM_NONE;
    launch(ent, direction);
}

pub fn projectileTick(ent: *server.Entity) void {
    if (server.state(ent) == .active) return droppedTick(ent);
    const owner = server.find(ent.dk.ownerId) orelse {
        server.free(ent);
        return;
    };
    if (server.now() < ent.dk.actionTime) return;
    ent.dk.actionTime = server.now() + 100;
    if (ent.dk.combatNext > 0) ent.dk.combatNext -= 1;
    const maximum = server.info(@This()).speed;
    if (server.liquid(ent)) {
        ent.dk.speedOverride *= 0.75;
        if (ent.dk.speedOverride < maximum / 8) return drop(ent, owner);
    } else if (ent.dk.speedOverride < maximum) ent.dk.speedOverride = @min(maximum, ent.dk.speedOverride * 1.25);
    if (server.now() >= ent.dk.expires or !alive(owner)) return drop(ent, owner);
    var direction = server.velocity(ent);
    if ((ent.dk.action & flag_reflected) != 0 and v.distance(ent.r.currentOrigin, owner.r.currentOrigin) < 100) return caught(ent, owner);
    const seeking = (ent.dk.action & flag_seek) != 0;
    var target = server.find(ent.dk.destinationId);
    if (target != null and target != owner and !alive(target)) {
        ent.dk.destinationId = 0;
        target = null;
    }
    if (target) |goal| {
        if (seeking) {
            if (goal == owner) {
                direction = v.sub(owner.r.currentOrigin, ent.r.currentOrigin);
                if (v.length(direction) < 100) return caught(ent, owner);
            } else {
                // Gold turnToTarget: blend the velocity toward the raw
                // offset to the target, so turning tightens up close.
                const velocity = server.velocity(ent);
                direction = v.sub(velocity, v.scale(v.sub(velocity, v.sub(center(goal), ent.r.currentOrigin)), 0.65));
            }
        }
    } else if (seeking) {
        if (pathTarget(ent, owner)) |found| ent.dk.destinationId = @bitCast(found.dk.id);
    }
    launch(ent, direction);
}

/// Out of time or drowned: fall as a pickup and fly home once the owner is
/// in sight. Bots simply catch it.
fn drop(ent: *server.Entity, owner: *server.Entity) void {
    if (alive(owner) and (owner.r.svFlags & c.SVF_BOT) != 0) return caught(ent, owner);
    server.setState(ent, .active);
    ent.dk.destinationId = @bitCast(owner.dk.id);
    ent.s.loopSound = 0;
    ent.clipmask = c.MASK_SOLID;
    ent.r.ownerNum = c.ENTITYNUM_NONE;
    ent.s.pos.trType = c.TR_GRAVITY;
    server.steer(ent, .{ 0, 0, 60 });
    ent.dk.actionTime = server.now() + 100;
}

fn droppedContact(hit: server.Contact) void {
    const victim = hit.victim();
    if (victim.client != null and victim.health > 0) return caught(hit.ent, victim);
    const normal = hit.hit.plane.normal;
    const speed = server.velocity(hit.ent);
    const bounce = v.scale(v.madd(speed, -2 * v.dot(speed, normal), normal), 0.6);
    if (normal[2] > 0.7 and v.length(bounce) < 40) {
        server.stop(hit.ent, v.madd(hit.hit.endpos, 1, normal));
        return;
    }
    hit.ent.r.currentOrigin = v.madd(hit.hit.endpos, 1, normal);
    server.steer(hit.ent, bounce);
}

fn droppedTick(ent: *server.Entity) void {
    const owner = server.find(ent.dk.ownerId);
    if (!alive(owner)) {
        server.free(ent);
        return;
    }
    const player = owner.?;
    for (c.g_entities[0..@intCast(c.level.maxclients)]) |*toucher| {
        if (toucher.inuse == 0 or toucher.client == null or toucher.health <= 0) continue;
        if (v.distance(toucher.r.currentOrigin, ent.r.currentOrigin) < 40) return caught(ent, toucher);
    }
    if (server.now() < ent.dk.actionTime) return;
    ent.dk.actionTime = server.now() + 100;
    var eye = player.r.currentOrigin;
    eye[2] += player.r.maxs[2] * 0.6;
    if (server.trace(ent.r.currentOrigin, eye, ent.s.number, c.MASK_SOLID).fraction < 1) return;
    server.setState(ent, .flight);
    ent.dk.action = flag_seek | flag_reflected;
    ent.dk.speedOverride = server.info(@This()).speed;
    ent.dk.expires = server.now() + 5000;
    ent.clipmask = c.MASK_SHOT;
    ent.s.loopSound = c.DK_SoundIndex("e2/we_discshoota.wav");
    ent.s.pos.trType = c.TR_LINEAR;
    launch(ent, v.sub(player.r.currentOrigin, ent.r.currentOrigin));
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
    if (cent.currentState.loopSound == 0) return;
    // Gold CL_DiscusSparkles: short-lived white puffs shed backwards.
    const p = @import("../client/particles.zig");
    if (cent.trailTime > render.now() or cent.trailTime < render.now() - 100) cent.trailTime = render.now() - 33;
    while (cent.trailTime <= render.now() - 33) {
        cent.trailTime += 33;
        var random = p.seed(cent.currentState.number, cent.trailTime);
        const back = v.scale(v.normal(cent.currentState.pos.trDelta), -1);
        for (0..4) |_| {
            var angles: v.Vec = undefined;
            c.vectoangles(&back, &angles);
            angles[0] += (random.next() - 0.5) * 15;
            angles[1] += (random.next() - 0.5) * 15;
            var velocity: v.Vec = undefined;
            c.AngleVectors(&angles, &velocity, null, null);
            p.add(.{ .start = render.now(), .end = render.now() + 150, .origin = cent.lerpOrigin, .velocity = v.scale(velocity, 120), .radius = 3 * (0.55 + 0.25 * random.next()), .alpha = 0.4, .shader = c.trap_R_RegisterShader("dk3/particle/smoke") });
        }
    }
}
