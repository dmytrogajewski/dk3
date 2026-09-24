/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Daikatana map semantics on ioquake3's trajectory and transactional pusher. */
#include "g_local.h"
#include "dk_effects.h"

void InitMover(gentity_t *ent);
static void BinaryUse(gentity_t *, gentity_t *, gentity_t *);
static void TrainUse(gentity_t *, gentity_t *, gentity_t *);
static void TrainLeave(gentity_t *);
static void TrainReached(gentity_t *);
static void TrainInit(gentity_t *);
static void SecretThink(gentity_t *);
static void TrainThink(gentity_t *ent) {
    if (!ent->dk.moverInitialized) TrainInit(ent);
    else if (ent->dk.moverArrival) TrainReached(ent);
    else TrainLeave(ent);
}

static int SpawnSound(const char *key) {
    char *value;
    G_SpawnString(key, "", &value);
    return DK_SoundIndex(value);
}

static trajectory_t *Motion(gentity_t *ent) { return ent->dk.moverAngular ? &ent->s.apos : &ent->s.pos; }

static void Stop(gentity_t *ent) {
    BG_EvaluateTrajectory(&ent->s.pos, level.time, ent->r.currentOrigin);
    BG_EvaluateTrajectory(&ent->s.apos, level.time, ent->r.currentAngles);
    VectorCopy(ent->r.currentOrigin, ent->s.pos.trBase);
    VectorCopy(ent->r.currentAngles, ent->s.apos.trBase);
    ent->s.pos.trType = ent->s.apos.trType = TR_STATIONARY;
    ent->s.loopSound = 0;
    trap_LinkEntity(ent);
}

static void MovementSound(gentity_t *ent, int sound) {
    qboolean loop = !strcmp(ent->classname, "func_plat") ||
        (ent->spawnflags & (ent->dk.moverAngular ? 2048 : 128));
    ent->s.loopSound = loop ? sound : 0;
    if (sound && !loop) G_AddEvent(ent, EV_GENERAL_SOUND, sound);
}

static void BinaryMove(gentity_t *ent, qboolean open, qboolean delayed) {
    gentity_t *part;
    int longest = 1;
    for (part = ent; part; part = part->teamchain) {
        vec3_t current, distance;
        BG_EvaluateTrajectory(Motion(part), level.time, current);
        VectorSubtract(open ? part->pos2 : part->pos1, current, distance);
        if (VectorLength(distance) * 1000 / part->speed > longest) longest = VectorLength(distance) * 1000 / part->speed;
    }
    for (part = ent; part; part = part->teamchain) {
        trajectory_t *motion = Motion(part);
        vec3_t current;
        int delay = delayed && !strncmp(part->classname, "func_door", 9) ? part->dk.delay : 0;
        BG_EvaluateTrajectory(motion, level.time, current);
        VectorCopy(current, motion->trBase);
        VectorSubtract(open ? part->pos2 : part->pos1, current, motion->trDelta);
        VectorScale(motion->trDelta, 1000.0f / longest, motion->trDelta);
        /* Native stop trajectories hold their base until trTime. Each door
           part retains its authored delay through snapshots and saves. */
        motion->trTime = level.time + delay; motion->trDuration = longest;
        motion->trType = part->dk.moverBounce ? TR_DK_BOUNCE_STOP : part->dk.moverAccel ? TR_DK_ACCEL_STOP : TR_LINEAR_STOP;
        part->dk.actionTime = delay ? motion->trTime : 0;
        part->moverState = open ? MOVER_1TO2 : MOVER_2TO1;
        part->nextthink = 0;
        if (!delay && (open ? part->sound1to2 : part->sound2to1))
            MovementSound(part, open ? part->sound1to2 : part->sound2to1);
    }
}

static void BinaryReturn(gentity_t *ent) { BinaryMove(ent, ent->moverState == MOVER_POS1, qfalse); }

static void StopEffects(gentity_t *ent) {
    int i;
    for (i = 0; i < 2; ++i) {
        gentity_t *effect;
        vec3_t origin;
        if (!(i ? ent->dk.moverQuake : ent->dk.moverDust)) continue;
        effect = G_Spawn(); effect->classname = "dk3_mover_effect";
        effect->s.eType = ET_DK3_EFFECT;
        effect->s.dk3Effect = i ? DK_FX_QUAKE : DK_FX_PARTICLES;
        effect->s.dk3EffectFlags = DK_FX_ENABLED | (i ? 0 : DK_FX_SMOKE);
        effect->s.dk3EffectStart = level.time; effect->s.dk3EffectDuration = 1000;
        effect->s.dk3EffectRadius = i ? ent->dk.moverMass * 100 : 4;
        effect->s.dk3EffectSpeed = i ? 400 : 40; effect->s.dk3EffectRate = ent->dk.moverMass * 100 / 35;
        effect->s.dk3EffectSpread = 180; effect->s.dk3Alpha = 0.5f;
        VectorSet(effect->s.dk3EffectColor, 0.45f, 0.4f, 0.35f);
        VectorAdd(ent->r.absmin, ent->r.absmax, origin); VectorScale(origin, 0.5f, origin);
        G_SetOrigin(effect, origin); VectorMA(origin, 64, axisDefault[2], effect->s.dk3EffectEnd);
        effect->think = G_FreeEntity; effect->nextthink = level.time + 1000;
        trap_LinkEntity(effect);
    }
}

static void BinaryReached(gentity_t *ent) {
    qboolean opened = ent->moverState == MOVER_1TO2;
    Stop(ent);
    StopEffects(ent);
    ent->dk.actionTime = 0;
    ent->moverState = opened ? MOVER_POS2 : MOVER_POS1;
    if (!opened && ent->dk.maxHealth > 0) { ent->health = ent->dk.maxHealth; ent->takedamage = qtrue; }
    if (opened ? ent->soundPos2 : ent->soundPos1)
        G_AddEvent(ent, EV_GENERAL_SOUND, opened ? ent->soundPos2 : ent->soundPos1);
    if (!(ent->flags & FL_TEAMMEMBER) && ent->wait >= 0 && !(ent->spawnflags & (8 | 32)) &&
        (opened || (ent->spawnflags & 64))) {
        ent->think = BinaryReturn;
        ent->nextthink = level.time + (int)(ent->wait * 1000) + 1;
    }
    if (opened) G_UseTargets(ent, DK_FindEntity(ent->dk.ownerId));
}

static void BinaryUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (ent->flags & FL_TEAMMEMBER) { BinaryUse(ent->teammaster, other, activator); return; }
    if (ent->dk.key && !DK_HasKey(activator, ent->dk.key)) {
        if (activator && activator->client) trap_SendServerCommand(activator->s.number, "cp \"A key is required.\"");
        return;
    }
    ent->dk.ownerId = activator ? activator->dk.id : 0;
    if (ent->moverState == MOVER_1TO2) return;
    if (ent->moverState == MOVER_POS2 && !(ent->spawnflags & (8 | 32))) {
        if (ent->wait >= 0) ent->nextthink = level.time + (int)(ent->wait * 1000) + 1;
        return;
    }
    if (ent->dk.aiScript) DK_StartScript(ent->dk.aiScript, ent, activator, qfalse);
    if (ent->dk.cineScript) DK_StartCinematic(ent->dk.cineScript, ent, activator);
    BinaryMove(ent, ent->moverState != MOVER_POS2, qtrue);
}

static void MoverBlocked(gentity_t *ent, gentity_t *other) {
    static int nextReport[MAX_GENTITIES];
    if (!other || !other->inuse) return;
    /* Like ioquake3's Blocked_Door, clear remains that cannot be pushed.
       Living actors still take crush damage and can reverse a door. Actors
       temporarily down for resurrection retain positive health. */
    if (other->dk.actorKind && other->health <= 0) {
        G_TempEntity(other->r.currentOrigin, EV_ITEM_POP);
        G_FreeEntity(other);
        return;
    }
    if (trap_Cvar_VariableIntegerValue("developer") > 1 && level.time >= nextReport[ent->s.number]) {
        G_Printf("dk3 mover %u (%s) blocked by %u (%s), health %d contents %x at %.1f %.1f %.1f, force %d\n",
            ent->dk.id, ent->classname, other->dk.id, other->classname ? other->classname : "<unnamed>",
            other->health, other->r.contents, other->r.currentOrigin[0], other->r.currentOrigin[1],
            other->r.currentOrigin[2], ent->dk.forceMove);
        nextReport[ent->s.number] = level.time + 1000;
    }
    if (ent->damage > 0 && other->takedamage) G_Damage(other, ent, ent, NULL, NULL, ent->damage, 0, MOD_CRUSH);
    if (ent->dk.forceMove) return;
    if (ent->dk.moverKind == 1) BinaryMove(ent, ent->moverState == MOVER_2TO1, qfalse);
}

static void BinaryTouch(gentity_t *ent, gentity_t *other, trace_t *trace) {
    (void)trace;
    if (other->health > 0 && (other->client || other->dk.actorKind) && ent->moverState != MOVER_1TO2)
        BinaryUse(ent, other, other);
}

static void RotateUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (ent->s.apos.trType == TR_LINEAR) Stop(ent);
    else {
        VectorCopy(ent->r.currentAngles, ent->s.apos.trBase);
        VectorScale(ent->movedir, ent->speed, ent->s.apos.trDelta);
        ent->s.apos.trTime = level.time; ent->s.apos.trType = TR_LINEAR;
    }
    G_UseTargets(ent, activator);
}

static void TrainReached(gentity_t *ent) {
    gentity_t *corner = DK_FindEntity(ent->dk.destinationId);
    Stop(ent);
    ent->dk.moverArrival = 0;
    if (!corner) { ent->dk.moverPaused = 1; return; }
    if (corner->dk.pathTarget) DK_FireNamed(corner->dk.pathTarget, ent, DK_FindEntity(ent->dk.ownerId));
    if (!ent->inuse) return;
    if (corner->dk.aiScript) DK_StartScript(corner->dk.aiScript, ent, DK_FindEntity(ent->dk.ownerId), qfalse);
    if (corner->dk.cineScript) DK_StartCinematic(corner->dk.cineScript, ent, DK_FindEntity(ent->dk.ownerId));
    ent->target = corner->target;
    ent->dk.moverPaused = (corner->spawnflags & 8) || corner->wait < 0 || corner->health > 0;
    if (corner->health > 0) { ent->health = ent->dk.maxHealth = corner->health; ent->takedamage = qtrue; }
    if (corner->soundPos1) G_AddEvent(ent, EV_GENERAL_SOUND, corner->soundPos1);
    if (!ent->dk.moverPaused && ent->target) {
        ent->think = TrainThink;
        ent->nextthink = level.time + (int)(corner->wait * 1000) + 1;
    }
}

static void TrainLeave(gentity_t *ent) {
    gentity_t *corner = ent->target ? G_Find(NULL, FOFS(targetname), ent->target) : NULL;
    gentity_t *previous = DK_FindEntity(ent->dk.destinationId);
    vec3_t delta;
    float speed;
    int duration, i;
    if (!corner || strcmp(corner->classname, "path_corner_train")) {
        G_Printf("dk3: train %u: missing path_corner_train %s\n", ent->dk.id, ent->target ? ent->target : "<end>");
        ent->dk.moverPaused = 1;
        return;
    }
    ent->dk.destinationId = corner->dk.id;
    ent->dk.moverPaused = 0;
    ent->takedamage = qfalse;
    VectorCopy(ent->r.currentOrigin, ent->s.pos.trBase);
    VectorSubtract(corner->s.origin, ent->r.currentOrigin, delta);
    speed = previous && previous->speed > 0 ? previous->speed : ent->speed;
    duration = VectorLength(delta) * 1000 / speed;
    if (previous) for (i = 0; i < 3; ++i)
        if (previous->dk.rotationRate[i] && fabs(previous->dk.rotationDelta[i]) * 1000 / fabs(previous->dk.rotationRate[i]) > duration)
            duration = fabs(previous->dk.rotationDelta[i]) * 1000 / fabs(previous->dk.rotationRate[i]);
    if (duration < 1) duration = 1;
    if (previous && (previous->spawnflags & 32)) {
        G_SetOrigin(ent, corner->s.origin); trap_LinkEntity(ent);
        ent->dk.moverArrival = 1; ent->think = TrainThink; ent->nextthink = level.time + 1;
        return;
    }
    VectorScale(delta, 1000.0f / duration, ent->s.pos.trDelta);
    ent->s.pos.trTime = level.time; ent->s.pos.trDuration = duration; ent->s.pos.trType = TR_LINEAR_STOP;
    ent->s.apos.trTime = level.time; ent->s.apos.trDuration = duration;
    VectorCopy(ent->r.currentAngles, ent->s.apos.trBase); VectorClear(ent->s.apos.trDelta);
    if (previous) {
        for (i = 0; i < 3; ++i) {
            int flag = i == ROLL ? 1 : i == PITCH ? 2 : 4;
            ent->s.apos.trDelta[i] = previous->spawnflags & flag ? previous->dk.rotationRate[i] :
                previous->dk.rotationDelta[i] * 1000 / duration;
        }
        ent->s.apos.trType = TR_LINEAR_STOP;
        ent->s.loopSound = previous->soundLoop;
        if (previous->sound1to2) G_AddEvent(ent, EV_GENERAL_SOUND, previous->sound1to2);
    }
}

static void TrainInit(gentity_t *ent) {
    gentity_t *first = ent->target ? G_Find(NULL, FOFS(targetname), ent->target) : NULL;
    if (!ent->target) { ent->dk.moverInitialized = ent->dk.moverPaused = 1; return; }
    if (!first) { G_Printf("dk3: train %u has no start corner\n", ent->dk.id); return; }
    G_SetOrigin(ent, first->s.origin); trap_LinkEntity(ent);
    ent->dk.destinationId = first->dk.id;
    ent->target = first->target;
    ent->dk.moverInitialized = 1;
    ent->dk.moverPaused = ent->targetname && !(ent->spawnflags & 128);
    if (!ent->dk.moverPaused) TrainReached(ent);
}

static void TrainUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    ent->dk.ownerId = activator ? activator->dk.id : 0;
    if (!ent->dk.moverInitialized) TrainInit(ent);
    if (other && other != ent && other->dk.pathTarget) {
        ent->target = other->dk.pathTarget;
        Stop(ent); TrainLeave(ent);
    } else if (ent->s.pos.trType != TR_STATIONARY) {
        gentity_t *destination = DK_FindEntity(ent->dk.destinationId);
        Stop(ent);
        if (destination) ent->target = destination->targetname;
        ent->dk.moverPaused = 1; ent->nextthink = 0;
    } else TrainLeave(ent);
}

static void ElevatorUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    gentity_t *train = ent->target ? G_Find(NULL, FOFS(targetname), ent->target) : NULL;
    if (train && train->dk.moverKind == 3) TrainUse(train, other, activator);
}

static void SecretMove(gentity_t *entity, const vec3_t destination) {
    vec3_t delta;
    int duration;
    VectorSubtract(destination, entity->r.currentOrigin, delta);
    duration = VectorLength(delta) * 1000 / entity->speed;
    if (duration < 1) duration = 1;
    VectorCopy(entity->r.currentOrigin, entity->s.pos.trBase);
    VectorScale(delta, 1000.0f / duration, entity->s.pos.trDelta);
    entity->s.pos.trType = TR_LINEAR_STOP; entity->s.pos.trTime = level.time; entity->s.pos.trDuration = duration;
}

static void SecretReached(gentity_t *entity) {
    Stop(entity);
    if (entity->dk.action == 5) {
        entity->dk.action = 0; entity->health = entity->dk.maxHealth; entity->takedamage = entity->health > 0;
        if (entity->soundPos1) G_AddEvent(entity, EV_GENERAL_SOUND, entity->soundPos1);
        return;
    }
    if (entity->dk.action == 2) {
        G_UseTargets(entity, DK_FindEntity(entity->dk.ownerId));
        if (!entity->inuse) return;
        if (entity->soundPos2) G_AddEvent(entity, EV_GENERAL_SOUND, entity->soundPos2);
        if ((entity->spawnflags & 1) || entity->wait < 0) return;
        entity->nextthink = level.time + (int)(entity->wait * 1000) + 1;
    } else entity->nextthink = level.time + 1000;
    entity->think = SecretThink;
}

static void SecretThink(gentity_t *entity) {
    if (entity->dk.action == 1) { entity->dk.action = 2; SecretMove(entity, entity->dk.secretEnd); }
    else if (entity->dk.action == 2) { entity->dk.action = 4; SecretMove(entity, entity->pos2); }
    else if (entity->dk.action == 4) { entity->dk.action = 5; SecretMove(entity, entity->pos1); }
}

static void SecretUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    gentity_t *part;
    (void)other;
    if (entity->flags & FL_TEAMMEMBER) { SecretUse(entity->teammaster, other, activator); return; }
    if (entity->dk.action || (entity->dk.key && !DK_HasKey(activator, entity->dk.key))) return;
    for (part = entity; part; part = part->teamchain) {
        part->dk.ownerId = activator ? activator->dk.id : 0; part->dk.action = 1;
        part->takedamage = qfalse;
        SecretMove(part, part->pos2);
        if (part->sound1to2) G_AddEvent(part, EV_GENERAL_SOUND, part->sound1to2);
    }
}

qboolean DK_SpawnMover(gentity_t *ent) {
    const char *name = ent->classname;
    qboolean rotate = !strcmp(name, "func_door_rotate"), plat = !strcmp(name, "func_plat");
    qboolean button = !strcmp(name, "func_button");
    qboolean secret = !strcmp(name, "func_door_secret");
    float distance, lip;
    vec3_t delta, position;
    int i;
    if (!strcmp(name, "path_corner_train")) {
        const char *distanceKeys[] = {"y_distance", "z_distance", "x_distance"};
        const char *speedKeys[] = {"y_speed", "z_speed", "x_speed"};
        char *value;
        G_SpawnString("pathtarget", "", &value); if (*value) ent->dk.pathTarget = G_NewString(value);
        for (i = 0; i < 3; ++i) {
            G_SpawnFloat(distanceKeys[i], "0", &ent->dk.rotationDelta[i]);
            G_SpawnFloat(speedKeys[i], "0", &ent->dk.rotationRate[i]);
        }
        ent->soundLoop = SpawnSound("sound"); ent->sound1to2 = SpawnSound("sound_start"); ent->soundPos1 = SpawnSound("sound_stop");
        G_SetOrigin(ent, ent->s.origin); ent->r.svFlags |= SVF_NOCLIENT;
        return qtrue;
    }
    if (!strcmp(name, "trigger_elevator")) { ent->use = ElevatorUse; return qtrue; }
    if (!rotate && !plat && !button && !secret && strcmp(name, "func_door") && strcmp(name, "func_water") &&
        strcmp(name, "func_rotate") && strcmp(name, "func_train")) return qfalse;
    if ((!ent->model || ent->model[0] != '*') && (strcmp(name, "func_train") || ent->model))
        G_Error("dk3: %s %u lacks a brush model", name, ent->dk.id);
    if (ent->speed <= 0) ent->speed = button ? 40 : 100;
    G_SpawnFloat("wait", button ? "1" : "3", &ent->wait);
    G_SpawnFloat("lip", button ? "4" : "8", &lip);
    G_SpawnInt("dmg", "2", &ent->damage);
    G_SpawnInt("damage", va("%d", ent->damage), &ent->damage);
    G_SpawnInt("forcemove", "0", &ent->dk.forceMove);
    G_SpawnInt("boing", "0", &ent->dk.moverBounce);
    G_SpawnInt("accelerate", "0", &ent->dk.moverAccel);
    G_SpawnInt("dust", "0", &ent->dk.moverDust);
    G_SpawnInt("spawnquake", "0", &ent->dk.moverQuake);
    G_SpawnFloat("mass", "1", &ent->dk.moverMass);
    ent->dk.moverMass = Com_Clamp(0.1f, 100, ent->dk.moverMass);
    if ((!rotate && (ent->spawnflags & 512)) || (!strcmp(name, "func_train") && (ent->spawnflags & 64))) ent->dk.forceMove = 1;
    if (ent->model) trap_SetBrushModel(ent, ent->model);
    VectorCopy(ent->s.origin, position); VectorCopy(position, ent->pos1); VectorCopy(position, ent->pos2);
    ent->dk.moverKind = 1;
    if (secret) {
        vec3_t forward, right, up, size;
        float first = 0, second = 0;
        ent->dk.moverKind = 4;
        AngleVectors(ent->s.angles, forward, right, up);
        VectorSubtract(ent->r.maxs, ent->r.mins, size);
        for (i = 0; i < 3; ++i) {
            first += fabs((ent->spawnflags & 4 ? up : right)[i]) * size[i];
            second += fabs(forward[i]) * size[i];
        }
        VectorMA(ent->pos1, first * (ent->spawnflags & (2 | 4) ? -1 : 1), ent->spawnflags & 4 ? up : right, ent->pos2);
        VectorMA(ent->pos2, second, forward, ent->dk.secretEnd);
        VectorClear(ent->s.angles);
        if (!(ent->spawnflags & 8) && (!ent->targetname || (ent->spawnflags & 16)) && ent->health <= 0) ent->health = 1;
    } else if (rotate) {
        ent->dk.moverAngular = 1;
        VectorCopy(ent->s.angles, ent->pos1); VectorCopy(ent->pos1, ent->pos2);
        G_SpawnFloat("distance", "90", &distance);
        ent->pos2[ent->spawnflags & 128 ? ROLL : ent->spawnflags & 256 ? PITCH : YAW] += (ent->spawnflags & 2) ? -distance : distance;
    } else if (plat) {
        if (!G_SpawnFloat("height", "0", &distance)) distance = ent->r.maxs[2] - ent->r.mins[2] - lip;
        ent->pos1[2] -= distance;
    } else if (!strcmp(name, "func_train")) ent->dk.moverKind = 3;
    else if (!strcmp(name, "func_rotate")) {
        ent->dk.moverKind = 2;
        VectorClear(ent->movedir);
        ent->movedir[ent->spawnflags & 4 ? ROLL : ent->spawnflags & 8 ? PITCH : YAW] = ent->spawnflags & 2 ? -1 : 1;
    } else {
        G_SetMovedir(ent->s.angles, ent->movedir);
        for (i = 0; i < 3; ++i) delta[i] = fabs(ent->movedir[i]);
        VectorSubtract(ent->r.maxs, ent->r.mins, position);
        distance = DotProduct(delta, position) - lip;
        VectorMA(ent->pos1, distance, ent->movedir, ent->pos2);
    }
    if ((ent->spawnflags & 1) && ent->dk.moverKind == 1 && !button) {
        VectorCopy(ent->pos1, delta); VectorCopy(ent->pos2, ent->pos1); VectorCopy(delta, ent->pos2);
    }
    InitMover(ent);
    ent->r.contents = ent->model ? CONTENTS_SOLID : 0;
    if (!ent->model) ent->r.svFlags |= SVF_NOCLIENT;
    if (ent->dk.moverAngular) {
        G_SetOrigin(ent, ent->s.origin);
        VectorCopy(ent->pos1, ent->s.apos.trBase); VectorCopy(ent->pos1, ent->r.currentAngles);
        ent->s.apos.trType = TR_STATIONARY;
    }
    ent->sound1to2 = SpawnSound(button ? "sound_use" : plat ? "sound_up" : "sound_opening");
    ent->sound2to1 = SpawnSound(button ? "sound_return" : plat ? "sound_down" : "sound_closing");
    ent->soundPos2 = SpawnSound(plat ? "sound_top" : "sound_open_finish");
    ent->soundPos1 = SpawnSound(plat ? "sound_bottom" : "sound_close_finish");
    ent->soundLoop = 0;
    ent->dk.maxHealth = ent->health; ent->takedamage = ent->health > 0;
    DK_RestoreNativeMover(ent);
    if (ent->dk.moverKind == 3) { ent->think = TrainThink; ent->nextthink = level.time + FRAMETIME; }
    if (ent->dk.moverKind == 2 && (ent->spawnflags & 1)) RotateUse(ent, ent, ent);
    trap_LinkEntity(ent);
    return qtrue;
}

void DK_RestoreNativeMover(gentity_t *ent) {
    if (!strcmp(ent->classname, "trigger_elevator")) { ent->use = ElevatorUse; return; }
    if (!ent->dk.moverKind) return;
    ent->blocked = MoverBlocked;
    if (ent->dk.moverKind == 1) {
        ent->use = BinaryUse; ent->reached = BinaryReached; ent->think = BinaryReturn;
        if (!strcmp(ent->classname, "func_button") && (ent->spawnflags & 1)) ent->touch = BinaryTouch;
    } else if (ent->dk.moverKind == 2) ent->use = RotateUse;
    else if (ent->dk.moverKind == 4) { ent->use = SecretUse; ent->reached = SecretReached; ent->think = SecretThink; }
    else {
        ent->use = TrainUse; ent->reached = TrainReached;
        ent->think = TrainThink;
    }
}

void DK_RunMovers(void) {
    int i, j;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *ent = &g_entities[i];
        vec3_t mins, maxs;
        int list[MAX_GENTITIES], count;
        qboolean plat;
        if (ent->inuse && ent->dk.moverKind == 1 && ent->dk.actionTime && ent->dk.actionTime <= level.time) {
            int sound = ent->moverState == MOVER_1TO2 ? ent->sound1to2 : ent->sound2to1;
            ent->dk.actionTime = 0;
            MovementSound(ent, sound);
        }
        if (!ent->inuse || ent->dk.moverKind != 1 || (ent->flags & FL_TEAMMEMBER) ||
            ent->moverState == MOVER_1TO2 || ent->dk.key || ent->health > 0 ||
            (ent->targetname && *ent->targetname)) continue;
        plat = !strcmp(ent->classname, "func_plat");
        if (!plat && !(ent->spawnflags & 16)) continue;
        VectorCopy(ent->r.absmin, mins); VectorCopy(ent->r.absmax, maxs);
        for (j = 0; j < 3; ++j) { mins[j] -= 48; maxs[j] += 48; }
        count = trap_EntitiesInBox(mins, maxs, list, ARRAY_LEN(list));
        for (j = 0; j < count; ++j) {
            gentity_t *other = &g_entities[list[j]];
            if ((other->client || other->dk.actorKind) && other->health > 0) {
                if (other->client && other->client->sess.sessionTeam == TEAM_SPECTATOR) continue;
                // A lift starts after boarding and waits for riders at its stop.
                // Door proximity also includes people approaching or waiting below;
                // using it for lifts sends the platform away before they can board.
                if (plat && (other->client ? other->client->ps.groundEntityNum : other->s.groundEntityNum)
                    != ent->s.number) continue;
                BinaryUse(ent, other, other); break;
            }
        }
    }
}

void DK_SetupMovers(void) {
    int i, j, axis;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *master = &g_entities[i], *last;
        qboolean changed;
        if (!master->inuse || master->dk.moverKind != 1 || (master->flags & FL_TEAMMEMBER) ||
            (master->spawnflags & 4) || strncmp(master->classname, "func_door", 9)) continue;
        master->teammaster = master;
        do {
            changed = qfalse;
            for (j = i + 1; j < level.num_entities; ++j) {
                gentity_t *candidate = &g_entities[j], *part;
                qboolean touching = qfalse;
                if (!candidate->inuse || candidate->dk.moverKind != 1 || candidate->team || (candidate->flags & FL_TEAMMEMBER) ||
                    (candidate->spawnflags & 4) || strncmp(candidate->classname, "func_door", 9) ||
                    (!!master->targetname != !!candidate->targetname) ||
                    (master->targetname && strcmp(master->targetname, candidate->targetname))) continue;
                for (part = master; part; part = part->teamchain) {
                    for (axis = 0; axis < 3; ++axis)
                        if (part->r.absmin[axis] > candidate->r.absmax[axis] + 1 || part->r.absmax[axis] < candidate->r.absmin[axis] - 1) break;
                    if (axis == 3) { touching = qtrue; break; }
                }
                if (!touching) continue;
                for (last = master; last->teamchain; last = last->teamchain) {}
                last->teamchain = candidate; candidate->teammaster = master; candidate->flags |= FL_TEAMMEMBER;
                changed = qtrue;
            }
        } while (changed);
    }
}
