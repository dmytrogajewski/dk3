// SPDX-License-Identifier: GPL-2.0-or-later
//! Engine mechanisms. Concrete weapons own policy and their action lifecycles.
const std = @import("std");
pub const c = @import("../abi.zig").c;
pub const v = @import("../vector.zig");
pub const Entity = c.gentity_t;
pub const tick_ms = 50;
pub const State = enum(c_int) { flight, stuck, arming, active, dying, ring, chain, nightmare, melee, quake, beam };
pub fn now() c_int {
    return c.level.time;
}
pub fn entities() []Entity {
    return c.g_entities[0..@intCast(c.level.num_entities)];
}
pub fn find(id: anytype) ?*Entity {
    return c.DK_FindEntity(@as(c_uint, @bitCast(id)));
}
pub fn info(comptime W: type) *c.dkWeaponInfo_t {
    return &c.dk_weapons[W.id];
}
pub fn named(ent: *const Entity, name: [:0]const u8) bool {
    return ent.classname != null and c.Q_stricmp(ent.classname, name) == 0;
}
pub fn state(ent: *const Entity) State {
    return std.enums.fromInt(State, ent.dk.combatState) orelse .flight;
}
pub fn setState(ent: *Entity, value: State) void {
    ent.dk.combatState = @intFromEnum(value);
}
pub fn free(ent: *Entity) void {
    c.G_FreeEntity(ent);
}
pub fn link(ent: *Entity) void {
    c.trap_LinkEntity(ent);
}
pub fn origin(ent: *Entity, point: v.Vec) void {
    c.G_SetOrigin(ent, @constCast(&point));
}
pub fn sound(ent: *Entity, name: [:0]const u8) void {
    c.G_Sound(ent, c.CHAN_AUTO, c.DK_SoundIndex(name));
}
pub fn liquid(ent: *const Entity) bool {
    return (c.trap_PointContents(&ent.r.currentOrigin, ent.s.number) & c.MASK_WATER) != 0;
}
pub fn random(ent: *Entity) f32 {
    ent.dk.actorRandom = ent.dk.actorRandom *% 1664525 +% 1013904223;
    return v.f(ent.dk.actorRandom >> 8) / 16777216;
}
pub fn hostile(owner: ?*Entity, target: *Entity) bool {
    if (target.inuse == 0 or target.takedamage == 0 or target.health <= 0 or target == owner) return false;
    const who = owner orelse return true;
    if (who.client != null and target.client != null and c.OnSameTeam(who, target) != 0) return false;
    const companion = c.DK_IsCompanion(who) != 0;
    if ((who.client != null or companion) and c.DK_IsCompanion(target) != 0) return false;
    if (companion and target.client != null) return false;
    if (who.dk.actorKind != 0 and !companion) return target.client != null or c.DK_IsCompanion(target) != 0;
    return true;
}
pub fn visited(ent: *const Entity, target: *const Entity) bool {
    const count: usize = @intCast(std.math.clamp(ent.dk.combatCount, 0, ent.dk.combatTargets.len));
    for (ent.dk.combatTargets[0..count]) |id| if (@as(c_uint, @bitCast(id)) == target.dk.id) return true;
    return false;
}
pub fn remember(ent: *Entity, target: *const Entity) void {
    if (ent.dk.combatCount < 0 or ent.dk.combatCount >= ent.dk.combatTargets.len) return;
    ent.dk.combatTargets[@intCast(ent.dk.combatCount)] = @bitCast(target.dk.id);
    ent.dk.combatCount += 1;
}
pub fn nearest(owner: ?*Entity, point: v.Vec, range: f32, exclude: ?*Entity) ?*Entity {
    var best: ?*Entity = null;
    var search_range = range;
    for (entities()) |*target| {
        if (!hostile(owner, target)) continue;
        if (exclude) |ent| {
            if (visited(ent, target)) continue;
        }
        const distance = v.distance(point, target.r.currentOrigin);
        if (distance < search_range and c.CanDamage(target, @constCast(&point)) != 0) {
            best = target;
            search_range = distance;
        }
    }
    return best;
}
pub const Basis = struct { forward: v.Vec, right: v.Vec, up: v.Vec };
pub fn basis(angles: v.Vec) Basis {
    var result: Basis = undefined;
    c.AngleVectors(&angles, &result.forward, &result.right, &result.up);
    return result;
}
pub fn directionBasis(direction: v.Vec) Basis {
    var angles: v.Vec = undefined;
    c.vectoangles(&direction, &angles);
    return basis(angles);
}
pub fn trace(start: v.Vec, end: v.Vec, skip: c_int, mask: c_int) c.trace_t {
    var hit: c.trace_t = undefined;
    c.trap_Trace(&hit, &start, null, null, &end, skip, mask);
    return hit;
}
pub fn beam(start: v.Vec, end: v.Vec, weapon: c_int) void {
    const event: *Entity = c.G_TempEntity(@constCast(&end), c.EV_DK3_BEAM);
    event.s.origin2 = start;
    event.s.weapon = weapon;
}
pub fn blast(point: v.Vec, weapon: c_int) void {
    const event: *Entity = c.G_TempEntity(@constCast(&point), c.EV_DK3_BLAST);
    event.s.weapon = weapon;
}
pub fn impact(comptime W: type, hit: *const c.trace_t, flesh: bool) ?*Entity {
    if (hit.fraction == 1 or (hit.surfaceFlags & c.SURF_NOIMPACT) != 0) return null;
    const event: *Entity = c.G_TempEntity(@constCast(&hit.endpos), c.EV_DK3_IMPACT);
    event.s.weapon = W.id;
    event.s.eventParm = if (flesh) 1 else if ((hit.contents & c.MASK_WATER) != 0) 2 else 0;
    event.s.otherEntityNum = hit.entityNum;
    event.s.origin2 = hit.plane.normal;
    if (@hasDecl(W, "impactMaterial")) W.impactMaterial(event, hit, flesh);
    return event;
}
pub const Hit = struct {
    victim: *Entity,
    inflictor: ?*Entity,
    owner: ?*Entity,
    direction: v.Vec,
    point: v.Vec,
    amount: f32,
};
pub fn damage(comptime W: type, hit_value: Hit) void {
    var hit = hit_value;
    if (hit.victim.takedamage == 0) return;
    if (hit.owner) |owner| {
        if (owner.client != null) hit.amount *= 1 + 0.1 * v.f(c.DK_Attribute(&owner.client[0].ps, 0, now())) else if (c.DK_IsCompanion(owner) != 0) hit.amount *= 1 + 0.1 * v.f(owner.dk.attributes[0]);
    }
    if (@hasDecl(W, "modifyHit")) W.modifyHit(&hit);
    if (hit.amount <= 0) return;
    if (c.trap_Cvar_VariableIntegerValue("dk3_weaponTrace") != 0) c.G_Printf("dk3 weapon: damage %d target %d amount %.3f time %d\n", @as(c_int, W.id), hit.victim.s.number, @as(f64, hit.amount), now());
    const before = hit.victim.health;
    c.G_Damage(hit.victim, hit.inflictor, hit.owner, &hit.direction, &hit.point, v.i(@ceil(hit.amount)), 0, c.DK_WEAPON_MOD(W.id));
    if (hit.victim.inuse != 0 and hit.victim.health > 0 and hit.victim.health < before) {
        if (@hasDecl(W, "afterHit")) W.afterHit(&hit);
        hit.victim.dk.statusOwnerId = if (hit.owner) |owner| owner.dk.id else 0;
        if (hit.victim.client != null) hit.victim.client[0].ps.dk3Status = (hit.victim.client[0].ps.dk3Status & ~@as(c_int, 7)) | hit.victim.dk.status;
    }
}
pub fn radius(comptime W: type, point: v.Vec, owner: ?*Entity, amount: f32, range: f32, ignore: ?*Entity) void {
    _ = c.G_RadiusDamage(@constCast(&point), owner, amount, range, ignore, c.DK_WEAPON_MOD(W.id));
}
pub const Fire = struct {
    owner: *Entity,
    start: v.Vec,
    forward: v.Vec,
    charge_ms: c_int = 0,
    pub fn sequence(self: Fire) c_int {
        return if (self.owner.client != null) self.owner.client[0].ps.dk3WeaponSequence else 0;
    }
    pub fn boost(self: Fire) c_int {
        return if (self.owner.client != null) c.DK_Attribute(&self.owner.client[0].ps, 1, now()) else 0;
    }
};
pub fn traceShot(comptime W: type, shot: Fire, amount: f32, range: f32) void {
    const hit = trace(shot.start, v.madd(shot.start, range, shot.forward), shot.owner.s.number, c.MASK_SHOT);
    const victim = &c.g_entities[@intCast(hit.entityNum)];
    _ = impact(W, &hit, victim.takedamage != 0);
    if (hit.entityNum < c.ENTITYNUM_WORLD) damage(W, .{ .victim = victim, .inflictor = shot.owner, .owner = shot.owner, .direction = shot.forward, .point = hit.endpos, .amount = amount });
    if (range > 150) beam(shot.start, hit.endpos, W.id);
}
pub fn pellets(comptime W: type, shot: Fire, count: usize, spread: f32, scale: f32) void {
    const axes = directionBasis(shot.forward);
    var targets: [12]c_int = undefined;
    var hits: [12]usize = @splat(0);
    var points: [12]v.Vec = undefined;
    var used: usize = 0;
    for (0..count) |_| {
        const x = (random(shot.owner) * 2 - 1) * spread;
        const y = (random(shot.owner) * 2 - 1) * spread;
        const direction = v.normal(v.madd(v.madd(shot.forward, x, axes.right), y, axes.up));
        const hit = trace(shot.start, v.madd(shot.start, info(W).range, direction), shot.owner.s.number, c.MASK_SHOT);
        _ = impact(W, &hit, hit.entityNum < c.ENTITYNUM_WORLD and c.g_entities[@intCast(hit.entityNum)].takedamage != 0);
        if (hit.entityNum >= c.ENTITYNUM_WORLD) continue;
        var index: usize = 0;
        while (index < used and targets[index] != hit.entityNum) : (index += 1) {}
        if (index == used) {
            targets[index] = hit.entityNum;
            points[index] = hit.endpos;
            used += 1;
        }
        hits[index] += 1;
    }
    for (0..used) |index| damage(W, .{ .victim = &c.g_entities[@intCast(targets[index])], .inflictor = shot.owner, .owner = shot.owner, .direction = shot.forward, .point = points[index], .amount = info(W).damage * scale * v.f(hits[index]) / v.f(count) });
}
pub fn controller(comptime W: type, owner: ?*Entity, point: v.Vec, phase: State, lifetime: c_int) *Entity {
    const ent: *Entity = c.G_Spawn();
    ent.classname = @constCast("dk3_weapon_controller");
    ent.s.eType = c.ET_GENERAL;
    ent.s.weapon = W.id;
    ent.s.time = now();
    ent.r.svFlags |= c.SVF_NOCLIENT;
    ent.dk.ownerId = if (owner) |who| who.dk.id else 0;
    ent.dk.projectile = 1;
    setState(ent, phase);
    ent.dk.expires = now() + lifetime;
    ent.damage = v.i(info(W).damage);
    ent.think = @import("entry.zig").projectileThink;
    ent.nextthink = now() + tick_ms;
    origin(ent, point);
    return ent;
}
pub fn spawn(comptime W: type, shot: Fire) *Entity {
    const rules = W.spec.projectile;
    const data = info(W);
    const ent = controller(W, shot.owner, shot.start, .flight, if (rules.lifetime_ms > 0) @intCast(rules.lifetime_ms) else v.i((if (data.lifetime > 0) data.lifetime else 5) * 1000));
    ent.classname = c.G_NewString(data.classname);
    ent.s.eType = c.ET_DK3_MISSILE;
    if (rules.loop_sound) |name| ent.s.loopSound = c.DK_SoundIndex(name);
    ent.r.svFlags = c.SVF_USE_CURRENT_ORIGIN;
    ent.r.ownerNum = shot.owner.s.number;
    ent.parent = shot.owner;
    ent.dk.launchOrigin = shot.start;
    ent.clipmask = c.MASK_SHOT | (if (rules.water_collision) @as(c_int, c.MASK_WATER) else 0);
    ent.damage = v.i(data.damage * rules.direct_scale);
    ent.splashDamage = v.i(data.damage * rules.splash_scale);
    ent.splashRadius = v.i(rules.splash_radius);
    ent.s.pos.trType = if (rules.gravity) c.TR_GRAVITY else c.TR_LINEAR;
    ent.s.pos.trTime = now();
    ent.s.pos.trBase = shot.start;
    ent.s.pos.trDelta = v.scale(shot.forward, if (data.speed > 0) data.speed else 400);
    if (rules.action_delay_ms > 0) ent.dk.actionTime = now() + @as(c_int, @intCast(rules.action_delay_ms));
    if (@hasDecl(W, "initializeProjectile")) W.initializeProjectile(ent);
    link(ent);
    return ent;
}
pub fn explode(comptime W: type, ent: *Entity) void {
    ent.takedamage = c.qfalse;
    c.trap_UnlinkEntity(ent);
    blast(ent.r.currentOrigin, W.id);
    if (ent.splashDamage > 0) radius(W, ent.r.currentOrigin, find(ent.dk.ownerId), v.f(ent.splashDamage), v.f(ent.splashRadius), ent);
    if (@hasDecl(W, "afterExplosion")) W.afterExplosion(ent);
    free(ent);
}
pub fn stop(ent: *Entity, point: v.Vec) void {
    origin(ent, point);
    ent.s.pos.trType = c.TR_STATIONARY;
    ent.s.pos.trDelta = v.zero;
}
pub fn velocity(ent: *Entity) v.Vec {
    var result: v.Vec = undefined;
    c.BG_EvaluateTrajectoryDelta(&ent.s.pos, now(), &result);
    return result;
}
pub fn steer(ent: *Entity, speed: v.Vec) void {
    ent.s.pos.trDelta = speed;
    ent.s.pos.trBase = ent.r.currentOrigin;
    ent.s.pos.trTime = now();
}
pub fn reflect(ent: *Entity, hit: *const c.trace_t, retention: f32) void {
    const speed = velocity(ent);
    ent.r.currentOrigin = v.madd(hit.endpos, 1, hit.plane.normal);
    steer(ent, v.scale(v.madd(speed, -2 * v.dot(speed, hit.plane.normal), hit.plane.normal), retention));
    ent.r.ownerNum = c.ENTITYNUM_NONE;
}
pub const Contact = struct {
    ent: *Entity,
    hit: *const c.trace_t,
    pub fn owner(self: Contact) ?*Entity {
        return find(self.ent.dk.ownerId);
    }
    pub fn victim(self: Contact) *Entity {
        return &c.g_entities[@intCast(self.hit.entityNum)];
    }
    pub fn apply(self: Contact, comptime W: type, amount: f32) void {
        damage(W, .{ .victim = self.victim(), .inflictor = self.ent, .owner = self.owner(), .direction = self.ent.s.pos.trDelta, .point = self.hit.endpos, .amount = amount });
    }
    pub fn effect(self: Contact, comptime W: type) void {
        _ = impact(W, self.hit, self.victim().takedamage != 0);
    }
    pub fn detonate(self: Contact, comptime W: type) void {
        self.ent.r.currentOrigin = self.hit.endpos;
        explode(W, self.ent);
    }
};
pub fn ballisticContact(comptime W: type, contact: Contact) void {
    contact.effect(W);
    contact.apply(W, v.f(contact.ent.damage));
    contact.detonate(W);
}
pub fn expired(comptime W: type, ent: *Entity) bool {
    if (now() >= ent.dk.expires or find(ent.dk.ownerId) == null) {
        explode(W, ent);
        return true;
    }
    return false;
}
pub fn stuck(ent: *Entity) bool {
    if (state(ent) != .stuck) return false;
    if (find(ent.dk.destinationId)) |target| {
        origin(ent, target.r.currentOrigin);
        link(ent);
    }
    ent.s.dk3Alpha = std.math.clamp(v.f(ent.dk.expires - now()) / 1000, 0, 1);
    if (now() >= ent.dk.expires) free(ent);
    return true;
}
pub fn ring(comptime W: type, source: *Entity, lifetime: c_int, range: f32) *Entity {
    const ent = controller(W, find(source.dk.ownerId), source.r.currentOrigin, .ring, lifetime);
    ent.splashRadius = v.i(range);
    ent.damage = source.damage;
    ent.s.eType = c.ET_DK3_MISSILE;
    ent.r.svFlags &= ~@as(c_int, c.SVF_NOCLIENT);
    ent.s.dk3Effect = c.DK_FX_WEAPON_RING;
    ent.s.dk3EffectRadius = range;
    ent.s.dk3EffectDuration = lifetime;
    ent.dk.parentId = source.dk.id;
    link(ent);
    return ent;
}
pub fn ringTick(comptime W: type, ent: *Entity, attenuate: bool) void {
    const age = std.math.clamp(v.f(now() - ent.s.time) / v.f(@max(1, ent.dk.expires - ent.s.time)), 0, 1);
    const range = v.f(ent.splashRadius) * age;
    const owner = find(ent.dk.ownerId);
    for (entities(), 0..) |*target, index| {
        const mask = @as(c_uint, 1) << @as(u5, @intCast(index % 32));
        if (target.inuse == 0 or target.takedamage == 0 or target.health <= 0 or (ent.dk.combatHitBits[index / 32] & mask) != 0) continue;
        const distance = v.distance(target.r.currentOrigin, ent.r.currentOrigin);
        if (distance > range or c.CanDamage(target, &ent.r.currentOrigin) == 0) continue;
        ent.dk.combatHitBits[index / 32] |= mask;
        damage(W, .{ .victim = target, .inflictor = ent, .owner = owner, .direction = v.normal(v.sub(target.r.currentOrigin, ent.r.currentOrigin)), .point = target.r.currentOrigin, .amount = v.f(ent.damage) * (if (target == owner) @as(f32, 0.5) else 1) * (if (attenuate) (1000 - distance) / 1000 else 1) });
    }
    if (now() >= ent.dk.expires) free(ent);
}
pub fn push(target: *Entity, direction_value: v.Vec, magnitude: f32) void {
    var direction = direction_value;
    if (direction[2] < 0.4 and direction[2] > -0.1) direction[2] = 0.4;
    if (target.client != null) {
        target.client[0].ps.velocity = v.madd(target.client[0].ps.velocity, magnitude, direction);
        target.client[0].ps.groundEntityNum = c.ENTITYNUM_NONE;
    } else if (target.dk.actorKind != 0 and target.dk.cinematicOwned == 0) {
        target.dk.actorVelocity = v.madd(target.dk.actorVelocity, magnitude, direction);
        target.s.groundEntityNum = c.ENTITYNUM_NONE;
    }
}
pub fn tremor(point: v.Vec, range: f32, strength: f32, duration: c_int) void {
    const ent: *Entity = c.G_Spawn();
    ent.classname = @constCast("dk3_mover_effect");
    ent.s.eType = c.ET_DK3_EFFECT;
    ent.s.dk3Effect = c.DK_FX_QUAKE;
    ent.s.dk3EffectFlags = c.DK_FX_ENABLED;
    ent.s.dk3EffectStart = now();
    ent.s.dk3EffectDuration = duration;
    ent.s.dk3EffectRadius = range;
    ent.s.dk3EffectSpeed = strength;
    ent.r.svFlags |= c.SVF_BROADCAST;
    origin(ent, point);
    ent.think = c.G_FreeEntity;
    ent.nextthink = now() + duration;
    link(ent);
}
