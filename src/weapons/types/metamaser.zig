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
const std = @import("std");
var supplied_charges: c_int = 120;
var supplied_health: c_int = 1000;
var supplied_lifetime: c_int = 60000;

/// Values are validated by the shared supplied-data parser before publication.
pub fn readValues(values: @import("../values.zig").Values) void {
    supplied_charges = values.cube_charges;
    supplied_health = values.cube_health;
    supplied_lifetime = values.cube_lifetime_ms;
}

const description = @import("../descriptions/metamaser.zig");
pub const id = c.DK_W_METAMASER;
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

pub fn fire(shot: server.Fire) void {
    server.schedule(@This(), shot, 300);
}
pub fn launch(shot: server.Fire) void {
    _ = server.spawn(@This(), shot);
}
// Cube state is decoded at the persistence boundary; behavior uses named fields.
const Lock = struct { target: c_uint = 0, until: c_int = 0, next_damage: c_int = 0, next_sound: c_int = 0 };
// The generic target slots are raw integers in saves. Anchor packed deadlines
// to s.time, whose save member is already rebased to the restored simulation.
fn unpackDeadline(value: c_int, ent: *server.Entity) c_int {
    if (ent.dk.combatTargets[31] == 0) return value;
    return if (value == std.math.minInt(c_int)) 0 else value +| ent.s.time;
}
fn packDeadline(value: c_int, ent: *server.Entity) c_int {
    return if (value == 0) std.math.minInt(c_int) else value -| ent.s.time;
}
const Cube = struct {
    locks: [4]Lock = @splat(.{}),
    pause_until: c_int = 0,
    pain_threshold: c_int = 0,
    next_beep: c_int = 0,
    lasers: [4]c_uint = @splat(0),
    pending_lasers: c_int = 0,
    next_laser: c_int = 0,
    fn read(ent: *server.Entity) Cube {
        var value: Cube = .{};
        const slots = ent.dk.combatTargets;
        for (&value.locks, 0..) |*lock, index| lock.* = .{ .target = @bitCast(slots[index]), .until = unpackDeadline(slots[4 + index], ent), .next_damage = unpackDeadline(slots[8 + index], ent), .next_sound = unpackDeadline(slots[12 + index], ent) };
        value.pause_until = unpackDeadline(slots[16], ent);
        value.pain_threshold = slots[17];
        value.next_beep = unpackDeadline(slots[18], ent);
        for (&value.lasers, 0..) |*laser_id, index| laser_id.* = @bitCast(slots[20 + index]);
        value.pending_lasers = slots[24];
        value.next_laser = unpackDeadline(slots[25], ent);
        return value;
    }
    fn write(value: Cube, ent: *server.Entity) void {
        const slots = &ent.dk.combatTargets;
        for (value.locks, 0..) |lock, index| {
            slots[index] = @bitCast(lock.target);
            slots[4 + index] = packDeadline(lock.until, ent);
            slots[8 + index] = packDeadline(lock.next_damage, ent);
            slots[12 + index] = packDeadline(lock.next_sound, ent);
        }
        slots[16] = packDeadline(value.pause_until, ent);
        slots[17] = value.pain_threshold;
        slots[18] = packDeadline(value.next_beep, ent);
        for (value.lasers, 0..) |laser_id, index| slots[20 + index] = @bitCast(laser_id);
        slots[24] = value.pending_lasers;
        slots[25] = packDeadline(value.next_laser, ent);
        slots[31] = 1;
    }
};
fn isCube(ent: *server.Entity) bool {
    return ent.inuse != 0 and ent.dk.projectile != 0 and ent.s.weapon == id and server.named(ent, identity.classname);
}
fn targetable(ent: *server.Entity, target: *server.Entity) bool {
    return target.inuse != 0 and target != ent and target.takedamage != 0 and target.health > 0 and (target.client != null or target.dk.actorKind != 0) and target.dk.cinematicOwned == 0;
}
fn beginDeath(ent: *server.Entity) void {
    if (server.state(ent) == .dying) return;
    ent.dk.combatCount = @max(0, ent.dk.combatCount);
    ent.takedamage = c.qfalse;
    server.setState(ent, .dying);
    ent.dk.expires = server.now() + 5000;
    ent.dk.combatNext = server.now();
    ent.nextthink = server.now() + server.tick_ms;
}
pub fn die(ent: [*c]server.Entity, _: [*c]server.Entity, _: [*c]server.Entity, _: c_int, _: c_int) callconv(.c) void {
    beginDeath(@ptrCast(ent));
}
pub fn pain(raw: [*c]server.Entity, _: [*c]server.Entity, _: c_int) callconv(.c) void {
    const ent: *server.Entity = @ptrCast(raw);
    const phase = server.state(ent);
    if (phase != .arming and phase != .active) return;
    if (server.now() >= ent.dk.expires or (phase == .active and ent.dk.combatCount <= 0)) {
        beginDeath(ent);
        return;
    }
    var cube = Cube.read(ent);
    if (ent.health > cube.pain_threshold) return;
    cube.pain_threshold = ent.health - 300;
    cube.pause_until = server.now() + 1500;
    cube.write(ent);
}
pub fn initializeProjectile(ent: *server.Entity) void {
    ent.health = supplied_health;
    ent.dk.expires = server.now() + supplied_lifetime;
    ent.s.pos.trDelta = v.scale(v.normal(ent.s.pos.trDelta), 800);
    ent.takedamage = c.qtrue;
    ent.die = die;
    ent.pain = pain;
    ent.s.pos.trType = c.TR_GRAVITY;
    ent.s.dk3Scale = 8;
    ent.clipmask = c.MASK_SOLID;
    ent.r.contents = c.CONTENTS_CORPSE;
    ent.r.mins = .{ -6, -6, 0 };
    ent.r.maxs = .{ 6, 6, 12 };
}
pub fn restore(ent: *server.Entity) void {
    ent.die = die;
    ent.pain = pain;
    if (isCube(ent) and server.state(ent) != .flight and ent.dk.combatTargets[31] == 0) {
        // Legacy saves stored absolute deadlines without their clock origin.
        // Keep health/charges/phase and re-acquire locks on the restored clock.
        var cube = Cube.read(ent);
        cube.locks = @splat(.{});
        cube.pause_until = 0;
        cube.next_beep = server.now();
        cube.next_laser = server.now();
        cube.write(ent);
    }
}
fn settle(ent: *server.Entity) void {
    ent.dk.combatTargets = @splat(0);
    ent.dk.combatCount = 0;
    server.setState(ent, .arming);
    ent.dk.combatNext = server.now() + 3000;
    var cube: Cube = .{};
    cube.pain_threshold = 700;
    cube.write(ent);
}
pub fn contact(hit: server.Contact) void {
    const speed = server.velocity(hit.ent);
    const slide = v.madd(speed, -v.dot(speed, hit.hit.plane.normal), hit.hit.plane.normal);
    if (hit.hit.plane.normal[2] > 0.7 or v.length(slide) < 10) {
        server.stop(hit.ent, hit.hit.endpos);
        if (server.state(hit.ent) != .dying) settle(hit.ent);
    } else {
        hit.ent.r.currentOrigin = v.madd(hit.hit.endpos, 1, hit.hit.plane.normal);
        server.steer(hit.ent, slide);
        hit.ent.r.ownerNum = c.ENTITYNUM_NONE;
    }
    server.link(hit.ent);
}
fn laser(ent: *server.Entity, cube: *Cube, index: usize) void {
    server.sound(ent, if (server.random(ent) < 0.5) "e4/we_metamalzapa.wav" else "e4/we_metamalzapb.wav");
    var direction: v.Vec = undefined;
    var hit: c.trace_t = undefined;
    var found = false;
    if (server.random(ent) < 0.025) for (server.entities()) |*target| {
        if (target.inuse == 0 or target == ent or target.takedamage == 0 or c.CanDamage(target, &ent.r.currentOrigin) == 0) continue;
        direction = v.sub(target.r.currentOrigin, ent.r.currentOrigin);
        hit = server.trace(ent.r.currentOrigin, v.add(target.r.currentOrigin, direction), ent.s.number, c.MASK_SHOT);
        found = hit.entityNum < c.ENTITYNUM_WORLD and c.g_entities[@intCast(hit.entityNum)].takedamage != 0;
        if (found) break;
    };
    if (!found) {
        direction = server.basis(.{ -90 + 180 * (server.random(ent) - 0.5), 360 * (server.random(ent) - 0.5), 0 }).forward;
        hit = server.trace(ent.r.currentOrigin, v.madd(ent.r.currentOrigin, 4000, direction), ent.s.number, c.MASK_SHOT);
    }
    direction = v.normal(direction);
    const owner = server.find(ent.dk.ownerId);
    if (hit.entityNum < c.ENTITYNUM_WORLD and c.g_entities[@intCast(hit.entityNum)].takedamage != 0) {
        const target = &c.g_entities[@intCast(hit.entityNum)];
        server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = owner, .direction = direction, .point = hit.endpos, .amount = v.f(ent.damage) });
        server.push(target, direction, 750);
    }
    if (server.find(cube.lasers[index])) |previous| {
        if (server.state(previous) == .beam) server.free(previous);
    }
    const effect = server.controller(@This(), owner, ent.r.currentOrigin, .beam, ent.dk.expires - server.now());
    effect.s.eType = c.ET_DK3_MISSILE;
    effect.s.dk3Effect = c.DK_FX_NOVABEAM;
    effect.s.dk3Alpha = 1;
    effect.s.otherEntityNum = c.ENTITYNUM_NONE;
    effect.s.origin2 = hit.endpos;
    effect.r.svFlags &= ~@as(c_int, c.SVF_NOCLIENT);
    server.link(effect);
    cube.lasers[index] = effect.dk.id;
}
fn ringTick(ent: *server.Entity) void {
    const outer = v.f(ent.splashRadius) * @max(0, @min(1, v.f(server.now() - ent.s.time) / v.f(@max(1, ent.dk.expires - ent.s.time))));
    const source = server.find(ent.dk.weaponParentId);
    const owner = server.find(ent.dk.ownerId);
    for (server.entities()) |*target| {
        if (target.inuse == 0 or target.takedamage == 0 or target == source or @abs(target.r.currentOrigin[2] - ent.r.currentOrigin[2]) >= 64) continue;
        const distance = v.distance(target.r.currentOrigin, ent.r.currentOrigin);
        if (distance <= outer - 25 or distance >= outer or c.CanDamage(target, &ent.r.currentOrigin) == 0) continue;
        var amount = v.f(ent.damage) * (v.f(ent.splashRadius) - distance) / v.f(ent.splashRadius);
        if (target == owner) amount *= 0.5;
        if (isCube(target)) amount = 32000;
        var direction = v.normal(v.sub(target.r.currentOrigin, ent.r.currentOrigin));
        if (direction[2] < 0.4 and direction[2] > -0.1) direction[2] = 0.4;
        server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = owner, .direction = direction, .point = target.r.currentOrigin, .amount = amount });
        server.push(target, direction, 50 * amount);
    }
    if (server.now() >= ent.dk.expires) server.free(ent);
}
pub fn projectileTick(ent: *server.Entity) void {
    if (server.scheduled(@This(), ent)) return;
    const phase = server.state(ent);
    if (phase == .ring) {
        ringTick(ent);
        return;
    }
    if (phase == .beam) {
        if (server.now() >= ent.dk.expires) server.free(ent);
        return;
    }
    if (phase == .flight) {
        _ = server.expired(@This(), ent);
        return;
    }
    var cube = Cube.read(ent);
    if (phase == .dying) {
        if (server.now() >= ent.dk.expires) {
            for (cube.lasers) |laser_id| if (server.find(laser_id)) |effect| {
                if (server.state(effect) == .beam) server.free(effect);
            };
            server.free(ent);
            return;
        }
        if (server.now() >= ent.dk.combatNext) {
            _ = server.ring(@This(), ent, 2000, 425);
            cube.pending_lasers = 4;
            cube.next_laser = server.now() + 100;
            ent.dk.combatNext = server.now() + 250 + v.i(750 * server.random(ent));
        }
        if (cube.pending_lasers > 0 and server.now() >= cube.next_laser) {
            cube.pending_lasers -= 1;
            laser(ent, &cube, @intCast(cube.pending_lasers));
            cube.next_laser = server.now() + 100;
        }
        cube.write(ent);
        return;
    }
    var cube_count: usize = 0;
    for (server.entities()) |*other| {
        if (isCube(other)) cube_count += 1;
    }
    if (server.now() >= ent.dk.expires or cube_count >= 3 or (phase == .active and ent.dk.combatCount <= 0)) {
        beginDeath(ent);
        return;
    }
    if (phase == .arming) {
        if (server.now() >= cube.next_beep) {
            server.sound(ent, "e1/we_c4beepa.wav");
            cube.next_beep = server.now() + 500;
        }
        if (server.now() >= ent.dk.combatNext) {
            server.setState(ent, .active);
            ent.dk.combatCount = supplied_charges;
        }
        cube.write(ent);
        return;
    }
    if (server.now() < cube.pause_until or server.now() < ent.dk.combatNext) return;
    ent.dk.combatNext = server.now() + 100;
    var found: [12]*server.Entity = undefined;
    var count: usize = 0;
    const range = server.info(@This()).range;
    for (server.entities()) |*target| {
        if (count == found.len) break;
        if (targetable(ent, target) and v.distance(target.r.currentOrigin, ent.r.currentOrigin) <= (if (range > 0) range else 512) and c.CanDamage(target, &ent.r.currentOrigin) != 0) {
            found[count] = target;
            count += 1;
        }
    }
    for (&cube.locks) |*lock| {
        if (lock.target == 0) continue;
        var present = false;
        for (found[0..count]) |target| {
            if (target.dk.id == lock.target) present = true;
        }
        if (!present or server.now() >= lock.until) lock.target = 0;
    }
    if (count > 0) for (&cube.locks) |*lock| {
        if (lock.target != 0) continue;
        const target = found[@min(count - 1, @as(usize, @intFromFloat(server.random(ent) * v.f(count))))];
        var duplicate = false;
        for (cube.locks) |other| {
            if (other.target == target.dk.id) duplicate = true;
        }
        if (duplicate) continue;
        lock.* = .{ .target = target.dk.id, .until = server.now() + 500 + v.i(500 * server.random(ent)), .next_damage = server.now(), .next_sound = server.now() };
    };
    const owner = server.find(ent.dk.ownerId);
    for (&cube.locks) |*lock| {
        const target = server.find(lock.target) orelse continue;
        const hit = server.trace(ent.r.currentOrigin, target.r.currentOrigin, ent.s.number, c.MASK_SHOT);
        if (hit.entityNum != target.s.number) continue;
        server.beam(ent.r.currentOrigin, target.r.currentOrigin, id);
        if (server.now() >= lock.next_sound) {
            server.sound(ent, if (server.random(ent) < 0.5) "e4/we_metamaszapa.wav" else "e4/we_metamaszapb.wav");
            lock.next_sound = server.now() + 1000;
        }
        if (server.now() < lock.next_damage) continue;
        ent.dk.combatCount -= 1;
        server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = owner, .direction = v.zero, .point = target.r.currentOrigin, .amount = v.f(ent.damage) });
        if (target.health <= 0) server.damage(@This(), .{ .victim = target, .inflictor = ent, .owner = owner, .direction = v.zero, .point = target.r.currentOrigin, .amount = 1000 });
        lock.next_damage = lock.until + 1;
        if (ent.dk.combatCount < 0) {
            cube.write(ent);
            beginDeath(ent);
            return;
        }
    }
    cube.write(ent);
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
    if (cent.currentState.dk3Effect == c.DK_FX_NOVABEAM) {
        @import("../client/beam.zig").draw(cent, .{ .color = .{ 0.35, 0.55, 1 }, .core = .{ 0.75, 0.85, 1 }, .flare = "models/global/e_flblue.sp2", .flare_scale = 0.5 });
        return;
    }
    if (cent.currentState.dk3Effect == c.DK_FX_WEAPON_RING) {
        const age = v.f(render.now() - cent.currentState.time) / 1000;
        const fraction = @max(0, @min(1, age * 1000 / v.f(@max(1, cent.currentState.dk3EffectDuration))));
        for (0..3) |index| _ = render.sprite("models/e1/we_shockring.sp2", 0, cent.lerpOrigin, .{ 90, age * 50 * (1 - v.f(index)), 0 }, 1.1 - v.f(index) * 0.1 + (16.4 - v.f(index) * 0.4) * fraction, 1, render.white, c.DK_SPRITE_ORIENTED);
        return;
    }
    render.model(@This(), cent);
}
pub const controller_limit = 120;
pub fn validProjectile(ent: *const server.Entity) bool {
    return ent.dk.combatTargets[24] >= 0 and ent.dk.combatTargets[24] <= 4 and ent.dk.combatTargets[31] >= 0 and ent.dk.combatTargets[31] <= 1;
}
