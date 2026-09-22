/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_weapons.h"

#define DK_PROJECTILE_TICK 50
#define DK_POISON 1
#define DK_BURN 2
#define DK_FROZEN 4
#define DK_C4_ARM_TIME 1000
#define DK_C4_TRIGGER_RADIUS 150
#define DK_C4_BLAST_RADIUS 300
#define DK_C4_CHAIN_DELAY 100
#define DK_ION_LIQUID_RADIUS 64

enum { C4_FLYING, C4_ATTACHED, C4_DETONATING };

int DK_ModifyDamage(gentity_t *victim, gentity_t *attacker, int damage) {
    int status;
    if (!victim->client || !attacker || !attacker->classname) return damage;
    status = victim->client->ps.dk3Status;
    if (((status & 16) && !strcmp(attacker->classname, "monster_stavros")) ||
        ((status & 32) && !strcmp(attacker->classname, "monster_wyndrax")) ||
        ((status & 64) && !strcmp(attacker->classname, "monster_nharre"))) damage = (damage + 3) / 4;
    return damage;
}

static qboolean Hostile(gentity_t *owner, gentity_t *other) {
    if (!other->inuse || !other->takedamage || other->health <= 0 || other == owner) return qfalse;
    if (!owner) return qtrue;
    if (owner->client && other->client && OnSameTeam(owner, other)) return qfalse;
    if ((owner->client || DK_IsCompanion(owner)) && DK_IsCompanion(other)) return qfalse;
    if (DK_IsCompanion(owner) && other->client) return qfalse;
    if (owner->dk.actorKind && !DK_IsCompanion(owner))
        return other->client || DK_IsCompanion(other);
    return qtrue;
}

static gentity_t *Nearest(gentity_t *owner, const vec3_t from, float range) {
    gentity_t *best = NULL;
    int i;
    for (i = 0; i < level.num_entities; ++i) {
        gentity_t *other = &g_entities[i];
        float distance;
        if (!Hostile(owner, other)) continue;
        distance = Distance(from, other->r.currentOrigin);
        if (distance < range && CanDamage(other, from)) { best = other; range = distance; }
    }
    return best;
}

static void Beam(const vec3_t from, const vec3_t to, int weapon) {
    gentity_t *event = G_TempEntity(to, EV_DK3_BEAM);
    VectorCopy(from, event->s.origin2);
    event->s.weapon = weapon;
}

static void Impact(const trace_t *trace, int weapon, qboolean flesh) {
    gentity_t *event;
    if (trace->fraction == 1 || (trace->surfaceFlags & SURF_NOIMPACT)) return;
    event = G_TempEntity(trace->endpos, EV_DK3_IMPACT);
    event->s.weapon = weapon;
    event->s.eventParm = flesh ? 1 : (trace->contents & MASK_WATER) ? 2 : 0;
    event->s.otherEntityNum = trace->entityNum;
    VectorCopy(trace->plane.normal, event->s.origin2);
}

static void Damage(gentity_t *victim, gentity_t *inflictor, gentity_t *owner,
                   vec3_t direction, vec3_t point, float amount, int weapon) {
    int before;
    if (!victim || !victim->takedamage) return;
    before = victim->health;
    if (owner && owner->client) amount *= 1.0f + 0.1f * DK_Attribute(&owner->client->ps, 0, level.time);
    if (owner && DK_IsCompanion(owner)) amount *= 1.0f + 0.1f * owner->dk.attributes[0];
    if (weapon == DK_W_SWORD && owner && owner->client) {
        vec3_t forward, toward;
        AngleVectors(victim->s.angles, forward, NULL, NULL);
        VectorSubtract(owner->r.currentOrigin, victim->r.currentOrigin, toward);
        if (VectorNormalize(toward) && DotProduct(toward, forward) < -0.5f) amount *= 2;
        amount += 10 * (owner->client->ps.dk3SwordExperience / 1000);
    }
    G_Damage(victim, inflictor, owner, direction, point, (int)ceil(amount), 0, DK_WEAPON_MOD(weapon));
    if (victim->inuse && victim->health > 0 && victim->health < before &&
        (weapon == DK_W_VENOM || weapon == DK_W_SUNFLARE || weapon == DK_W_KINETICORE)) {
        victim->dk.status |= weapon == DK_W_VENOM ? DK_POISON : weapon == DK_W_SUNFLARE ? DK_BURN : DK_FROZEN;
        victim->dk.statusExpires = level.time + (weapon == DK_W_KINETICORE ? 1500 : 5000);
        victim->dk.statusOwnerId = owner ? owner->dk.id : 0;
        if (victim->client) victim->client->ps.dk3Status = (victim->client->ps.dk3Status & ~7) | victim->dk.status;
    }
}

static void Explode(gentity_t *projectile) {
    gentity_t *owner = DK_FindEntity(projectile->dk.ownerId);
    int weapon = projectile->s.weapon;
    projectile->takedamage = qfalse;
    trap_UnlinkEntity(projectile);
    G_TempEntity(projectile->r.currentOrigin, EV_DK3_BLAST)->s.weapon = weapon;
    if (projectile->splashDamage > 0)
        G_RadiusDamage(projectile->r.currentOrigin, owner, projectile->splashDamage,
                       projectile->splashRadius, projectile, DK_WEAPON_MOD(weapon));
    G_FreeEntity(projectile);
}

static void IonDischarge(gentity_t *projectile) {
    gentity_t *event = G_TempEntity(projectile->r.currentOrigin, EV_DK3_IMPACT);
    event->s.weapon = DK_W_ION;
    event->s.eventParm = 2;
    projectile->splashDamage = projectile->damage;
    projectile->splashRadius = DK_ION_LIQUID_RADIUS;
    Explode(projectile);
}

static void ArmDetonation(gentity_t *charge) {
    if (charge->dk.action == C4_DETONATING) return;
    charge->dk.action = C4_DETONATING;
    charge->dk.expires = level.time + DK_C4_CHAIN_DELAY;
    charge->takedamage = qfalse;
}

static void ChargeDie(gentity_t *charge, gentity_t *inflictor, gentity_t *attacker, int damage, int mod) {
    (void)inflictor; (void)attacker; (void)damage; (void)mod;
    ArmDetonation(charge);
}

int DK_DetonateCharges(gentity_t *owner) {
    int i, count = 0;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *charge = &g_entities[i];
        if (!charge->inuse || !charge->dk.projectile || charge->s.weapon != DK_W_C4 ||
            charge->dk.ownerId != owner->dk.id || charge->dk.action == C4_DETONATING) continue;
        ArmDetonation(charge);
        ++count;
    }
    return count;
}

static void ChargeThink(gentity_t *charge) {
    int i;
    float nearest = DK_C4_BLAST_RADIUS;
    if (charge->dk.action != C4_ATTACHED || level.time < charge->dk.actionTime) return;
    for (i = 0; i < level.num_entities; ++i) {
        gentity_t *actor = &g_entities[i];
        float distance;
        if (!actor->inuse || actor->health <= 0 || (!actor->client && !actor->dk.actorKind) ||
            (actor->client && actor->client->sess.sessionTeam == TEAM_SPECTATOR)) continue;
        distance = Distance(charge->r.currentOrigin, actor->r.currentOrigin);
        if (distance >= nearest || !CanDamage(actor, charge->r.currentOrigin)) continue;
        if (distance < DK_C4_TRIGGER_RADIUS) { Explode(charge); return; }
        nearest = distance;
    }
    if (level.time >= charge->dk.nextUse) {
        G_AddEvent(charge, EV_GENERAL_SOUND, DK_SoundIndex("e1/we_c4beepa.wav"));
        charge->dk.nextUse = level.time + (nearest < DK_C4_BLAST_RADIUS ? 350 : 1500);
    }
}

static void Stop(gentity_t *ent, const vec3_t point) {
    G_SetOrigin(ent, point);
    ent->s.pos.trType = TR_STATIONARY;
    VectorClear(ent->s.pos.trDelta);
}

static void Reflect(gentity_t *ent, trace_t *trace, float retention) {
    vec3_t velocity;
    float along;
    BG_EvaluateTrajectoryDelta(&ent->s.pos, level.time, velocity);
    along = DotProduct(velocity, trace->plane.normal);
    VectorMA(velocity, -2 * along, trace->plane.normal, ent->s.pos.trDelta);
    VectorScale(ent->s.pos.trDelta, retention, ent->s.pos.trDelta);
    VectorMA(trace->endpos, 1, trace->plane.normal, ent->s.pos.trBase);
    VectorCopy(ent->s.pos.trBase, ent->r.currentOrigin);
    ent->s.pos.trTime = level.time;
    ent->r.ownerNum = ENTITYNUM_NONE;
}

static void ToxicBombImpact(gentity_t *ent, trace_t *trace) {
    gentity_t *owner = DK_FindEntity(ent->dk.ownerId);
    vec3_t point;
    VectorMA(trace->endpos, 2, trace->plane.normal, point);
    if (trace->entityNum < ENTITYNUM_WORLD && g_entities[trace->entityNum].takedamage)
        Damage(&g_entities[trace->entityNum], ent, owner, ent->s.pos.trDelta, point, ent->damage, DK_W_VENOM);
    Stop(ent, point);
    ent->classname = "dk3_toxic_cloud";
    ent->s.dk3Scale = 2.5f; ent->s.dk3Alpha = 0.45f;
    ent->dk.action = 1; ent->dk.actionTime = level.time + 500;
    ent->dk.expires = level.time + 5000;
    ent->clipmask = 0; ent->r.contents = 0;
    trap_LinkEntity(ent);
}

void DK_ProjectileImpact(gentity_t *ent, trace_t *trace) {
    gentity_t *owner = DK_FindEntity(ent->dk.ownerId);
    gentity_t *victim = &g_entities[trace->entityNum];
    int weapon = ent->s.weapon;
    float amount = ent->damage;
    if (weapon == DK_W_ION && (trace->contents & MASK_WATER)) {
        IonDischarge(ent);
        return;
    }
    if (trace->surfaceFlags & SURF_NOIMPACT) { G_FreeEntity(ent); return; }
    if (!strcmp(ent->classname, "dk3_toxic_bomb")) { ToxicBombImpact(ent, trace); return; }
    if (weapon == DK_W_C4) {
        vec3_t point;
        VectorMA(trace->endpos, 1, trace->plane.normal, point);
        VectorCopy(point, ent->r.currentOrigin);
        if (victim->takedamage) { Explode(ent); return; }
        Stop(ent, point);
        if (ent->dk.action != C4_DETONATING) ent->dk.action = C4_ATTACHED;
        ent->dk.actionTime = level.time + DK_C4_ARM_TIME;
        ent->r.ownerNum = ENTITYNUM_NONE;
        if (victim->s.eType == ET_MOVER) ent->dk.parentId = victim->dk.id;
        G_AddEvent(ent, EV_GENERAL_SOUND, DK_SoundIndex("e1/we_c4cona.wav"));
        trap_LinkEntity(ent);
        return;
    }
    if (weapon == DK_W_DISCUS && victim == owner) {
        if (owner && owner->client) owner->client->ps.ammo[weapon]++;
        else if (owner && DK_IsCompanion(owner)) owner->dk.ammunition[weapon]++;
        G_FreeEntity(ent);
        return;
    }
    Impact(trace, weapon, victim->takedamage);
    if (victim->takedamage) {
        if (weapon == DK_W_ION && victim == owner) amount *= 0.5f;
        if (weapon == DK_W_KINETICORE)
            amount = 2 + amount * Com_Clamp(0, 1, (ent->dk.expires - level.time) / (float)(ent->dk.expires - ent->s.time));
        Damage(victim, ent, owner, ent->s.pos.trDelta, trace->endpos, amount, weapon);
        if (weapon == DK_W_DISCUS) {
            ent->dk.action = 1;
            ent->r.ownerNum = victim->s.number;
            Reflect(ent, trace, 1);
            return;
        }
    } else if (weapon == DK_W_ION || weapon == DK_W_KINETICORE || weapon == DK_W_SHOCKWAVE ||
               weapon == DK_W_DISCUS || weapon == DK_W_CORDITE) {
        if (weapon == DK_W_ION && ++ent->dk.uses >= 3) {
            VectorCopy(trace->endpos, ent->r.currentOrigin);
            Explode(ent);
            return;
        }
        Reflect(ent, trace, weapon == DK_W_CORDITE ? 0.6f : weapon == DK_W_ION ? 1.25f : 1.0f);
        if (weapon == DK_W_DISCUS) ent->dk.action = 1;
        return;
    }
    VectorCopy(trace->endpos, ent->r.currentOrigin);
    if (weapon == DK_W_SUNFLARE || weapon == DK_W_METAMASER) {
        Stop(ent, trace->endpos);
        ent->dk.action = 1;
        return;
    }
    Explode(ent);
}

static void ProjectileThink(gentity_t *ent) {
    gentity_t *owner = DK_FindEntity(ent->dk.ownerId), *target;
    int weapon = ent->s.weapon;
    if (!strcmp(ent->classname, "dk3_toxic_bomb") || !strcmp(ent->classname, "dk3_toxic_cloud")) {
        if (level.time >= ent->dk.expires) { G_FreeEntity(ent); return; }
        if (ent->dk.action == 1 && level.time >= ent->dk.actionTime) {
            int i;
            for (i = 0; i < level.num_entities; ++i) {
                gentity_t *victim = &g_entities[i];
                if (!Hostile(owner, victim) || Distance(victim->r.currentOrigin, ent->r.currentOrigin) > 96 ||
                    !CanDamage(victim, ent->r.currentOrigin)) continue;
                Damage(victim, ent, owner, vec3_origin, victim->r.currentOrigin, 2, DK_W_VENOM);
            }
            ent->dk.actionTime = level.time + 500;
        }
        ent->nextthink = level.time + DK_PROJECTILE_TICK;
        return;
    }
    if (level.time >= ent->dk.expires || !owner) { Explode(ent); return; }
    if (weapon == DK_W_ION && (trap_PointContents(ent->r.currentOrigin, ent->s.number) & MASK_WATER)) {
        IonDischarge(ent);
        return;
    }
    if (weapon == DK_W_C4) {
        ent->nextthink = level.time + DK_PROJECTILE_TICK;
        ChargeThink(ent);
        return;
    }
    if (weapon == DK_W_DISCUS && (ent->dk.action || level.time - ent->s.time > 500)) {
        vec3_t direction;
        VectorSubtract(owner->r.currentOrigin, ent->r.currentOrigin, direction);
        if (VectorLength(direction) < 32) {
            if (owner->client) owner->client->ps.ammo[weapon]++;
            else if (DK_IsCompanion(owner)) owner->dk.ammunition[weapon]++;
            G_FreeEntity(ent);
            return;
        }
        VectorNormalize(direction);
        VectorScale(direction, dk_weapons[weapon].speed, ent->s.pos.trDelta);
        VectorCopy(ent->r.currentOrigin, ent->s.pos.trBase);
        ent->s.pos.trTime = level.time;
        ent->r.ownerNum = ENTITYNUM_NONE;
    }
    if (weapon == DK_W_WYNDRAX || weapon == DK_W_METAMASER || weapon == DK_W_NIGHTMARE ||
        weapon == DK_W_SUNFLARE) {
        float range = weapon == DK_W_SUNFLARE ? 110 : dk_weapons[weapon].range;
        target = Nearest(owner, ent->r.currentOrigin, range);
        if (target && ent->dk.actionTime <= level.time) {
            vec3_t direction;
            VectorSubtract(target->r.currentOrigin, ent->r.currentOrigin, direction);
            VectorNormalize(direction);
            Damage(target, ent, owner, direction, target->r.currentOrigin,
                   weapon == DK_W_SUNFLARE ? ent->damage * 3 : ent->damage,
                   weapon);
            Beam(ent->r.currentOrigin, target->r.currentOrigin, weapon);
            ent->dk.actionTime = level.time + (weapon == DK_W_NIGHTMARE ? 2000 : 200);
            if (weapon == DK_W_NIGHTMARE) { Explode(ent); return; }
        }
        if (target && weapon == DK_W_WYNDRAX) {
            vec3_t direction;
            VectorSubtract(target->r.currentOrigin, ent->r.currentOrigin, direction);
            VectorNormalize(direction);
            VectorScale(direction, dk_weapons[weapon].speed, ent->s.pos.trDelta);
            VectorCopy(ent->r.currentOrigin, ent->s.pos.trBase);
            ent->s.pos.trTime = level.time;
        }
    }
    ent->nextthink = level.time + DK_PROJECTILE_TICK;
}

static gentity_t *Projectile(gentity_t *owner, int weapon, const vec3_t start, vec3_t direction) {
    dkWeaponInfo_t *info = &dk_weapons[weapon];
    gentity_t *ent = G_Spawn();
    float lifetime = info->lifetime > 0 ? info->lifetime : 5;
    ent->classname = G_NewString(info->classname);
    ent->s.eType = ET_DK3_MISSILE;
    ent->s.weapon = weapon;
    if (weapon == DK_W_ION) ent->s.loopSound = DK_SoundIndex("e1/we_ionflyby.wav");
    ent->s.time = level.time;
    ent->r.svFlags = SVF_USE_CURRENT_ORIGIN;
    ent->r.ownerNum = owner->s.number;
    ent->parent = owner;
    ent->dk.ownerId = owner->dk.id;
    ent->dk.projectile = 1;
    ent->dk.expires = level.time + (int)(lifetime * 1000);
    ent->clipmask = MASK_SHOT;
    if (weapon == DK_W_ION) ent->clipmask |= MASK_WATER;
    ent->damage = info->damage;
    ent->splashDamage = 0;
    ent->splashRadius = 128;
    ent->think = ProjectileThink;
    ent->nextthink = level.time + DK_PROJECTILE_TICK;
    ent->s.pos.trType = weapon == DK_W_C4 || weapon == DK_W_CORDITE || weapon == DK_W_SUNFLARE ? TR_GRAVITY : TR_LINEAR;
    ent->s.pos.trTime = level.time;
    VectorCopy(start, ent->s.pos.trBase);
    VectorCopy(start, ent->r.currentOrigin);
    VectorScale(direction, info->speed > 0 ? info->speed : 400, ent->s.pos.trDelta);
    if (weapon == DK_W_SIDEWINDER || weapon == DK_W_TRIDENT || weapon == DK_W_C4 ||
        weapon == DK_W_STAVROS || weapon == DK_W_BALLISTA || weapon == DK_W_CORDITE)
        ent->splashDamage = weapon == DK_W_BALLISTA ? info->damage * 0.5f : info->damage;
    if (weapon == DK_W_SHOCKWAVE) {
        ent->damage *= 3;
        ent->splashDamage = info->damage * 0.75f;
        ent->splashRadius = 300;
    }
    if (weapon == DK_W_C4) {
        ent->splashRadius = DK_C4_BLAST_RADIUS;
        ent->health = 5;
        ent->takedamage = qtrue;
        ent->die = ChargeDie;
        ent->r.contents = CONTENTS_CORPSE;
        VectorSet(ent->r.mins, -8, -8, -8);
        VectorSet(ent->r.maxs, 8, 8, 8);
    }
    if (weapon == DK_W_NIGHTMARE || weapon == DK_W_METAMASER) {
        ent->dk.actionTime = level.time + (weapon == DK_W_NIGHTMARE ? 800 : 300);
        ent->dk.expires = level.time + (weapon == DK_W_NIGHTMARE ? 3000 : 15000);
    }
    trap_LinkEntity(ent);
    return ent;
}

void DK_DropToxicBomb(gentity_t *owner, gentity_t *target, int damage) {
    gentity_t *bomb;
    vec3_t start, direction, destination;
    trace_t trace;
    float fall, distance;
    VectorCopy(owner->r.currentOrigin, start); start[2] -= 40;
    trap_Trace(&trace, owner->r.currentOrigin, NULL, NULL, start, owner->s.number, MASK_SOLID);
    VectorCopy(trace.endpos, start);
    VectorCopy(target->r.currentOrigin, destination);
    fall = sqrt(2 * Com_Clamp(32, 2048, start[2] - destination[2]) / Com_Clamp(1, 10000, g_gravity.value));
    if (target->client) VectorMA(destination, fall, target->client->ps.velocity, destination);
    VectorSubtract(destination, start, direction); direction[2] = 0;
    distance = VectorNormalize(direction);
    bomb = Projectile(owner, DK_W_VENOM, start, direction);
    bomb->classname = "dk3_toxic_bomb";
    bomb->model = "models/global/e_flyellow.sp2"; bomb->s.modelindex = G_ModelIndex(bomb->model);
    bomb->s.dk3Scale = 1.4f; bomb->s.dk3Alpha = 0.65f; bomb->s.dk3RenderFlags = 2;
    bomb->damage = damage; bomb->splashDamage = 0;
    bomb->dk.expires = level.time + 15000;
    bomb->s.pos.trType = TR_GRAVITY;
    VectorScale(direction, Com_Clamp(0, 300, distance / fall), bomb->s.pos.trDelta);
    bomb->s.pos.trDelta[2] = -80;
    VectorSet(bomb->r.mins, -1, -1, -1); VectorSet(bomb->r.maxs, 1, 1, 1);
    trap_LinkEntity(bomb);
}

void DK_ActorStrike(gentity_t *owner, gentity_t *target, int weapon, const vec3_t offset,
                   float speed, int damage, float range, float spreadX, float spreadZ) {
    vec3_t start, direction, end, forward, right, up;
    trace_t trace;
    int axis;
    if (!target || !target->inuse || target->health <= 0 || damage <= 0) return;
    AngleVectors(owner->s.angles, forward, right, up);
    for (axis = 0; axis < 3; ++axis)
        start[axis] = owner->r.currentOrigin[axis] + offset[0] * forward[axis] + offset[1] * right[axis] + offset[2] * up[axis];
    if (VectorLengthSquared(offset) < 1) start[2] += owner->r.maxs[2] * 0.6f;
    trap_Trace(&trace, owner->r.currentOrigin, NULL, NULL, start, owner->s.number, MASK_SHOT);
    VectorCopy(trace.endpos, start);
    VectorCopy(target->r.currentOrigin, end); end[2] += (target->r.mins[2] + target->r.maxs[2]) * 0.5f;
    VectorSubtract(end, start, direction);
    VectorNormalize(direction);
    for (axis = 0; axis < 2; ++axis) {
        float spread;
        owner->dk.actorRandom = owner->dk.actorRandom * 1664525u + 1013904223u;
        spread = ((owner->dk.actorRandom >> 8) / 16777215.0f * 2 - 1) * (axis ? spreadZ : spreadX) / 8192.0f;
        VectorMA(direction, spread, axis ? up : right, direction);
    }
    VectorNormalize(direction);
    if (speed > 0) {
        gentity_t *projectile = Projectile(owner, weapon, start, direction);
        projectile->classname = "dk3_actor_projectile";
        projectile->damage = damage;
        projectile->splashDamage = weapon == DK_W_SIDEWINDER || weapon == DK_W_STAVROS ? damage / 2 : 0;
        projectile->dk.expires = level.time + 8000;
        projectile->s.pos.trType = TR_LINEAR;
        VectorScale(direction, speed, projectile->s.pos.trDelta);
    } else {
        VectorMA(start, range, direction, end);
        trap_Trace(&trace, start, NULL, NULL, end, owner->s.number, MASK_SHOT);
        if (trace.entityNum < ENTITYNUM_WORLD)
            Damage(&g_entities[trace.entityNum], owner, owner, direction, trace.endpos, damage, weapon);
        if (range > 160) Beam(start, trace.endpos, weapon);
    }
}

static void TraceShot(gentity_t *owner, int weapon, vec3_t start, vec3_t direction, float damage, float range) {
    trace_t hit;
    vec3_t end;
    VectorMA(start, range, direction, end);
    trap_Trace(&hit, start, NULL, NULL, end, owner->s.number, MASK_SHOT);
    Impact(&hit, weapon, hit.entityNum < ENTITYNUM_WORLD && g_entities[hit.entityNum].takedamage);
    if (hit.entityNum < ENTITYNUM_WORLD)
        Damage(&g_entities[hit.entityNum], owner, owner, direction, hit.endpos, damage, weapon);
    if (range > 150) Beam(start, hit.endpos, weapon);
}

static void Fire(gentity_t *owner, int weapon, vec3_t start, vec3_t forward, int chargeTime) {
    int i;
    dkWeaponInfo_t *info;
    vec3_t right, up, direction, angles;
    if (weapon <= 0 || weapon >= DK_WEAPON_COUNT) return;
    info = &dk_weapons[weapon];
    vectoangles(forward, angles);
    AngleVectors(angles, NULL, right, up);
    switch (weapon) {
        case DK_W_DISRUPTOR: case DK_W_GASHANDS: case DK_W_SILVERCLAW: case DK_W_SWORD:
            TraceShot(owner, weapon, start, forward, info->damage, info->range); break;
        case DK_W_HAMMER: {
            float charge = Com_Clamp(0.15f, 1, chargeTime / 1800.0f);
            G_RadiusDamage(owner->r.currentOrigin, owner, info->damage * charge, info->range, owner, DK_WEAPON_MOD(weapon));
            G_TempEntity(start, EV_DK3_BLAST)->s.weapon = weapon;
            break;
        }
        case DK_W_GLOCK: case DK_W_RIPGUN:
            TraceShot(owner, weapon, start, forward, info->damage, info->range); break;
        case DK_W_NOVABEAM:
            TraceShot(owner, weapon, start, forward, info->damage * info->interval / 1000.0f, info->range); break;
        case DK_W_SHOTCYCLER: case DK_W_SLUGGER:
            for (i = 0; i < 10; ++i) {
                float angle = i * 2.39996323f;
                float radius = 0.012f * sqrt((float)i);
                VectorCopy(forward, direction);
                VectorMA(direction, cos(angle) * radius, right, direction);
                VectorMA(direction, sin(angle) * radius, up, direction);
                VectorNormalize(direction);
                TraceShot(owner, weapon, start, direction, info->damage / 10, info->range);
            }
            break;
        case DK_W_ZEUS: {
            gentity_t *target = Nearest(owner, start, info->range);
            if (target) {
                VectorSubtract(target->r.currentOrigin, start, direction);
                VectorNormalize(direction);
                Damage(target, owner, owner, direction, target->r.currentOrigin, info->damage, weapon);
                Beam(start, target->r.currentOrigin, weapon);
            }
            break;
        }
        case DK_W_SIDEWINDER: case DK_W_TRIDENT:
            for (i = 0; i < (weapon == DK_W_TRIDENT ? 3 : 2); ++i) {
                VectorMA(forward, (i - (weapon == DK_W_TRIDENT ? 1 : 0.5f)) * 0.025f, right, direction);
                VectorNormalize(direction);
                Projectile(owner, weapon, start, direction);
            }
            break;
        case DK_W_FLASHLIGHT:
            if (owner->client) owner->client->ps.dk3Status ^= 8;
            break;
        default: Projectile(owner, weapon, start, forward); break;
    }
}

void DK_FireWeapon(gentity_t *owner) {
    vec3_t start, forward;
    AngleVectors(owner->client->ps.viewangles, forward, NULL, NULL);
    VectorCopy(owner->client->ps.origin, start); start[2] += owner->client->ps.viewheight;
    VectorMA(start, 8, forward, start);
    Fire(owner, owner->client->ps.weapon, start, forward, owner->client->ps.dk3Charge);
}

int DK_FireCompanionWeapon(gentity_t *owner, gentity_t *target) {
    vec3_t start, direction;
    float distance = Distance(owner->r.currentOrigin, target->r.currentOrigin), best = -1;
    int i, weapon = 0;
    VectorCopy(owner->r.currentOrigin, start); start[2] += owner->r.maxs[2] * 0.6f;
    for (i = 1; i < DK_WEAPON_COUNT; ++i) {
        float score;
        dkWeaponInfo_t *info = &dk_weapons[i];
        if (!((unsigned int)owner->dk.inventory & (1u << i)) || i == DK_W_FLASHLIGHT ||
            (i == DK_W_ION && (trap_PointContents(start, owner->s.number) & MASK_WATER)) ||
            (info->ammoCost && owner->dk.ammunition[i] < info->ammoCost) ||
            (info->speed <= 0 && distance > info->range)) continue;
        score = info->damage / (info->interval + 1.0f);
        if (distance < 180 && (i == DK_W_C4 || i == DK_W_SIDEWINDER || i == DK_W_TRIDENT || i == DK_W_CORDITE)) score *= 0.01f;
        if (score > best) { best = score; weapon = i; }
    }
    if (!weapon) return 0;
    owner->s.weapon = weapon;
    owner->dk.ammunition[weapon] -= dk_weapons[weapon].ammoCost;
    VectorSubtract(target->r.currentOrigin, start, direction); direction[2] += target->r.maxs[2] * 0.5f;
    VectorNormalize(direction);
    Fire(owner, weapon, start, direction, 1800);
    return dk_weapons[weapon].interval;
}

void DK_RunStatus(void) {
    int i;
    for (i = 0; i < level.num_entities; ++i) {
        gentity_t *ent = &g_entities[i];
        if (!ent->inuse || !ent->dk.status) continue;
        if (level.time >= ent->dk.statusExpires || ent->health <= 0) ent->dk.status = 0;
        else if ((ent->dk.status & (DK_POISON | DK_BURN)) && level.time >= ent->dk.statusTick) {
            gentity_t *owner = DK_FindEntity(ent->dk.statusOwnerId);
            int weapon = ent->dk.status & DK_BURN ? DK_W_SUNFLARE : DK_W_VENOM;
            G_Damage(ent, owner, owner, NULL, NULL, ent->dk.status & DK_BURN ? 6 : 3, DAMAGE_NO_KNOCKBACK, DK_WEAPON_MOD(weapon));
            ent->dk.statusTick = level.time + 1000;
        }
        if (ent->client) ent->client->ps.dk3Status = (ent->client->ps.dk3Status & ~7) | ent->dk.status;
    }
}

void DK_RestoreProjectile(gentity_t *ent) {
    ent->think = ProjectileThink;
    if (ent->s.weapon == DK_W_ION) ent->clipmask |= MASK_WATER;
    if (ent->s.weapon == DK_W_C4) ent->die = ChargeDie;
    if (ent->s.pos.trType == TR_STATIONARY && ent->s.weapon == DK_W_C4)
        ent->r.ownerNum = ENTITYNUM_NONE;
    else ent->r.ownerNum = ent->parent ? ent->parent->s.number : ENTITYNUM_NONE;
}
