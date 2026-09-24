/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Supplied decoration tables describe models, bounds, animation and physical rules. */
#include "g_local.h"
#include "dk_tables.h"
#include "dk_effects.h"

#define DK_DECOR_LIMIT 768
typedef struct {
    char name[64], model[MAX_QPATH];
    int episode, health, movement, solid, explosive, frames;
    int first[5], last[5], loop[5];
    vec3_t mins, maxs;
} decorInfo_t;
static decorInfo_t definitions[DK_DECOR_LIMIT];
static int definitionCount, loadingEpisode;
static char decorMap[MAX_QPATH];

static int ModelFrames(decorInfo_t *info) {
    char path[MAX_QPATH], header[128], *cursor;
    fileHandle_t file;
    int length, i;
    if (info->frames) return info->frames;
    Com_sprintf(path, sizeof(path), "%s.anim", info->model);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 1) { if (file) trap_FS_FCloseFile(file); G_Error("dk3: decoration %s missing model metadata %s", info->name, path); }
    if (length >= sizeof(header)) length = sizeof(header) - 1;
    trap_FS_Read(header, length, file); trap_FS_FCloseFile(file); header[length] = 0; cursor = header;
    if (strcmp(COM_Parse(&cursor), "dk3_animation") || strcmp(COM_Parse(&cursor), "1"))
        G_Error("dk3: decoration %s invalid model metadata %s", info->name, path);
    info->frames = atoi(COM_Parse(&cursor));
    if (info->frames < 1 || info->frames > 65535) G_Error("dk3: decoration %s invalid frame count", info->name);
    for (i = 0; i < ARRAY_LEN(info->last); ++i) {
        if (info->last[i] == info->frames && info->first[i] < info->frames) {
            G_Printf("dk3: %s decoration %s sequence %d ends at frame count %d; using last frame %d\n",
                decorMap, info->name, i, info->frames, info->frames - 1);
            --info->last[i];
        }
    }
    return info->frames;
}

static int Movement(const char *name) {
    return !Q_stricmp(name, "toss") ? 1 : !Q_stricmp(name, "bounce") ? 2 : !Q_stricmp(name, "float") ? 3 : 0;
}

static void ReadDecor(const dkRecord_t *row) {
    decorInfo_t *info;
    int i;
    const char *name = DK_Field(row, "modelname"), *model = DK_Field(row, "pathname");
    if (!*name || !*model || definitionCount == DK_DECOR_LIMIT) G_Error("dk3: invalid decoration table record %s", name);
    info = &definitions[definitionCount++]; memset(info, 0, sizeof(*info));
    Q_strncpyz(info->name, name, sizeof(info->name)); Q_strncpyz(info->model, model, sizeof(info->model));
    info->episode = loadingEpisode; info->health = DK_Number(row, "hitpoints", 0);
    info->movement = Movement(DK_Field(row, "movetype")); info->solid = !Q_stricmp(DK_Field(row, "solidtype"), "bbox");
    info->explosive = DK_Number(row, "exploding", 0);
    for (i = 0; i < 3; ++i) {
        char key[16];
        Com_sprintf(key, sizeof(key), "min%c", 'x' + i); info->mins[i] = DK_Number(row, key, -16);
        Com_sprintf(key, sizeof(key), "max%c", 'x' + i); info->maxs[i] = DK_Number(row, key, 16);
        if (info->mins[i] > info->maxs[i]) G_Error("dk3: decoration %s has inverted bounds", name);
    }
    for (i = 0; i < 5; ++i) {
        char key[16], *end;
        const char *value;
        Com_sprintf(key, sizeof(key), "seq%d", i); value = DK_Field(row, key);
        if (!*value) continue;
        info->first[i] = strtol(value, &end, 10); info->last[i] = info->first[i];
        if (*end == '-' || *end == '~') { info->loop[i] = *end == '~'; info->last[i] = strtol(end + 1, &end, 10); }
        if (*end || info->first[i] < 0 || info->last[i] < info->first[i] || info->last[i] > 65535)
            G_Error("dk3: decoration %s has invalid sequence %s", name, value);
    }
}

void DK_LoadDecor(void) {
    definitionCount = 0;
    trap_Cvar_VariableStringBuffer("mapname", decorMap, sizeof(decorMap));
    for (loadingEpisode = 1; loadingEpisode <= 4; ++loadingEpisode) {
        char table[32]; Com_sprintf(table, sizeof(table), "e%ddecoinfo", loadingEpisode); DK_ReadTable(table, ReadDecor);
    }
}

qboolean DK_ValidateDecorState(gentity_t *entity) {
    decorInfo_t *info;
    if (!entity->dk.decorKind || entity->dk.decorKind == -2) return qtrue;
    if (entity->dk.decorKind == -1)
        return (!strcmp(entity->classname, "misc_hosportal") || !strcmp(entity->classname, "misc_fountain") ||
                !strcmp(entity->classname, "misc_healthtree") || !strcmp(entity->classname, "misc_drugbox")) &&
            entity->dk.supply >= 0 && entity->dk.supply <= entity->dk.supplyMaximum &&
            entity->dk.supplyMaximum > 0 && entity->dk.supplyMaximum <= 100000 && entity->dk.recharge >= 0;
    if (entity->dk.decorKind < 1 || entity->dk.decorKind > definitionCount ||
        entity->dk.action < 0 || entity->dk.action >= 5 || entity->dk.objectMove < 0 || entity->dk.objectMove > 3) return qfalse;
    info = &definitions[entity->dk.decorKind - 1];
    return !strcmp(entity->classname, va("deco_e%d", info->episode)) && entity->model && !strcmp(entity->model, info->model) &&
        entity->dk.firstFrame >= 0 && entity->dk.lastFrame < ModelFrames(info) &&
        entity->dk.lastFrame >= entity->dk.firstFrame &&
        ((entity->dk.firstFrame == info->first[entity->dk.action] && entity->dk.lastFrame == info->last[entity->dk.action]) ||
         (entity->dk.firstFrame == entity->dk.lastFrame && !entity->dk.animationLoop));
}

static void Animate(gentity_t *entity, int sequence) {
    decorInfo_t *info = &definitions[entity->dk.decorKind - 1];
    int frames = ModelFrames(info);
    if (info->last[sequence] >= frames)
        G_Error("dk3: %s %u: decoration %s sequence %d exceeds %d model frames", decorMap,
            entity->dk.id, info->name, sequence, info->frames);
    entity->dk.action = sequence;
    entity->dk.firstFrame = info->first[sequence]; entity->dk.lastFrame = info->last[sequence];
    entity->dk.animationLoop = info->loop[sequence]; entity->dk.animationTime = level.time;
    entity->s.frame = entity->dk.firstFrame;
}

static void Use(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    int sequence = entity->dk.action + 1;
    decorInfo_t *info = &definitions[entity->dk.decorKind - 1];
    (void)other;
    if (sequence >= 5 || !info->last[sequence]) sequence = 0;
    Animate(entity, sequence); G_UseTargets(entity, activator);
}

static void Die(gentity_t *entity, gentity_t *inflictor, gentity_t *attacker, int damage, int mod) {
    unsigned int id = entity->dk.id;
    (void)inflictor; (void)damage; (void)mod;
    entity->takedamage = qfalse;
    if ((entity->spawnflags & 1) && entity->damage > 0) {
        G_TempEntity(entity->r.currentOrigin, EV_DK3_BLAST);
        G_RadiusDamage(entity->r.currentOrigin, attacker, entity->damage, 128, entity, MOD_UNKNOWN);
    }
    DK_DeathSpawn(entity);
    G_UseTargets(entity, attacker);
    if (entity->inuse && entity->dk.id == id) G_FreeEntity(entity);
}

static void Push(gentity_t *entity, gentity_t *other, trace_t *trace) {
    vec3_t direction;
    (void)trace;
    if (!(entity->spawnflags & 4) || !other->client || other->health <= 0 || entity->dk.parentId) return;
    VectorSubtract(entity->r.currentOrigin, other->r.currentOrigin, direction); direction[2] = 0;
    if (!VectorNormalize(direction)) return;
    VectorScale(direction, 80, entity->s.pos.trDelta); entity->s.pos.trDelta[2] = 20;
    VectorCopy(entity->r.currentOrigin, entity->s.pos.trBase);
    entity->s.pos.trTime = level.time; entity->s.pos.trType = TR_GRAVITY;
}

static void Think(gentity_t *entity) {
    int frames = entity->dk.lastFrame - entity->dk.firstFrame + 1;
    if (entity->dk.parentId && !DK_FindEntity(entity->dk.parentId)) {
        entity->dk.parentId = 0;
        G_SetOrigin(entity, entity->r.currentOrigin);
        if (entity->dk.objectMove == 1 || entity->dk.objectMove == 2) {
            entity->s.pos.trType = TR_GRAVITY;
            entity->s.pos.trTime = level.time;
        }
    }
    if (frames > 1) {
        int frame = (level.time - entity->dk.animationTime) / 100;
        entity->s.frame = entity->dk.firstFrame + (entity->dk.animationLoop ? frame % frames : frame < frames ? frame : frames - 1);
    }
    if (!entity->dk.parentId) {
        BG_EvaluateTrajectory(&entity->s.apos, level.time, entity->r.currentAngles);
        if (entity->s.pos.trType != TR_STATIONARY) {
            vec3_t destination, velocity;
            trace_t trace;
            BG_EvaluateTrajectory(&entity->s.pos, level.time, destination);
            trap_Trace(&trace, entity->r.currentOrigin, entity->r.mins, entity->r.maxs, destination, entity->s.number, MASK_SOLID);
            if (trace.fraction < 1) {
                BG_EvaluateTrajectoryDelta(&entity->s.pos, level.time, velocity);
                VectorMA(velocity, -2 * DotProduct(velocity, trace.plane.normal), trace.plane.normal, velocity);
                VectorScale(velocity, entity->dk.objectMove == 2 ? 0.5f : 0.1f, entity->s.pos.trDelta);
                VectorCopy(trace.endpos, entity->s.pos.trBase); entity->s.pos.trTime = level.time;
                if (trace.startsolid || (trace.plane.normal[2] > 0.7f && VectorLength(entity->s.pos.trDelta) < 40)) {
                    entity->s.pos.trType = TR_STATIONARY; VectorClear(entity->s.pos.trDelta); entity->s.groundEntityNum = trace.entityNum;
                }
            }
            VectorCopy(trace.endpos, entity->r.currentOrigin);
        }
        trap_LinkEntity(entity);
    }
    entity->nextthink = level.time + 100;
}

static int HealingMaximum(gentity_t *user) {
    return !user || user->health <= 0 ? 0 : user->client ? user->client->ps.stats[STAT_MAX_HEALTH] :
        DK_IsCompanion(user) ? user->dk.maxHealth : 0;
}

static void GrantHealth(gentity_t *user, int amount) {
    user->health += amount;
    if (user->health > HealingMaximum(user)) user->health = HealingMaximum(user);
    if (user->client) user->client->ps.stats[STAT_HEALTH] = user->health;
}

static void HealingStop(gentity_t *entity) {
    entity->dk.healingUser = 0; entity->s.loopSound = 0; entity->s.dk3Effect = 0;
    entity->dk.rechargeTime = level.time + entity->dk.recharge;
    G_Sound(entity, CHAN_AUTO, DK_SoundIndex("global/h_use_done.wav"));
}

static void Recharge(gentity_t *entity) {
    qboolean tree = strstr(entity->classname, "healthtree") != NULL;
    qboolean box = strstr(entity->classname, "drugbox") != NULL;
    gentity_t *user = DK_FindEntity(entity->dk.healingUser);
    entity->nextthink = level.time + 100;
    if (box) {
        if (entity->dk.action == 1) entity->s.frame = (int)Com_Clamp(1, 29, (level.time - entity->dk.animationTime) / 50);
        if (entity->dk.supply <= 0) {
            entity->s.dk3Alpha = Com_Clamp(0, 1, (entity->dk.expires - level.time) / 2000.0f);
            if (level.time >= entity->dk.expires) G_FreeEntity(entity);
        }
        return;
    }
    if (entity->dk.healingUser) {
        vec3_t forward, toward;
        qboolean facing = qtrue;
        if (user && user->client) {
            AngleVectors(user->client->ps.viewangles, forward, NULL, NULL);
            VectorSubtract(entity->r.currentOrigin, user->r.currentOrigin, toward); VectorNormalize(toward);
            facing = DotProduct(forward, toward) > 0.3f;
        }
        if (!user || user->health >= HealingMaximum(user) || Distance(user->r.currentOrigin, entity->r.currentOrigin) > 64 ||
            !facing || entity->dk.supply <= 0) HealingStop(entity);
        else if (level.time >= entity->dk.nextUse) {
            GrantHealth(user, 1); --entity->dk.supply; entity->dk.nextUse = level.time + 200;
            entity->s.frame = entity->dk.supply > 0;
        }
        return;
    }
    if (entity->dk.recharge > 0 && entity->dk.supply < entity->dk.supplyMaximum && entity->dk.rechargeTime <= level.time) {
        ++entity->dk.supply; entity->dk.rechargeTime = level.time + entity->dk.recharge;
        entity->s.frame = tree ? entity->dk.supplyMaximum - entity->dk.supply : entity->dk.supply == entity->dk.supplyMaximum;
        if (tree || entity->dk.supply == entity->dk.supplyMaximum)
            G_Sound(entity, CHAN_AUTO, DK_SoundIndex(tree ? "e1/t_regen.wav" : "global/h_recharged.wav"));
    }
}

static void Heal(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    qboolean tree = strstr(entity->classname, "healthtree") != NULL;
    qboolean box = strstr(entity->classname, "drugbox") != NULL;
    (void)other;
    if (!activator || !HealingMaximum(activator) || level.time < entity->dk.nextUse || entity->dk.supply <= 0) return;
    if (box && !entity->dk.action) {
        entity->dk.action = 1; entity->dk.animationTime = level.time; entity->dk.nextUse = level.time + 1500;
        G_Sound(entity, CHAN_AUTO, DK_SoundIndex("global/e_doorsqk.wav")); return;
    }
    if (activator->health >= HealingMaximum(activator)) return;
    if (tree || box) {
        GrantHealth(activator, 10); --entity->dk.supply;
        if (tree) {
            entity->s.frame = entity->dk.supplyMaximum - entity->dk.supply;
            entity->dk.nextUse = level.time + 1000;
            G_Sound(entity, CHAN_AUTO, DK_SoundIndex((entity->dk.supply & 1) ? "e1/t_use1.wav" : "e1/t_use2.wav"));
        } else {
            static const char *sounds[] = {"e1/m_dspheresteama.wav", "artifacts/antidoteuse.wav", "e1/we_dgloveamba.wav"};
            static const int delays[] = {1250, 2250, 1750};
            int stage = (int)Com_Clamp(0, 2, 2 - entity->dk.supply);
            entity->dk.action = 2; entity->s.frame = 30 + stage;
            entity->dk.nextUse = level.time + delays[stage];
            G_Sound(entity, CHAN_AUTO, DK_SoundIndex(sounds[stage]));
            if (!entity->dk.supply) entity->dk.expires = level.time + 2000;
        }
        G_UseTargets(entity, activator);
    } else if (!entity->dk.healingUser) {
        entity->dk.healingUser = activator->dk.id;
        entity->dk.nextUse = level.time + 200;
        entity->s.loopSound = DK_SoundIndex("global/h_hfx.wav");
        entity->s.dk3Effect = DK_FX_PARTICLES; entity->s.dk3EffectFlags = DK_FX_ENABLED;
        entity->s.dk3EffectRate = 20; entity->s.dk3EffectSpeed = 24; entity->s.dk3EffectRadius = 1;
        VectorSet(entity->s.dk3EffectColor, 0.2f, 0.7f, 1); VectorSet(entity->s.dk3EffectGravity, 0, 0, -60);
        if (!strcmp(entity->classname, "misc_fountain")) entity->s.loopSound = DK_SoundIndex("global/e_pondwaterb.wav");
        G_Sound(entity, CHAN_AUTO, DK_SoundIndex("global/h_use.wav"));
        G_UseTargets(entity, activator);
    }
}

static void HealTouch(gentity_t *entity, gentity_t *other, trace_t *trace) { (void)trace; Heal(entity, other, other); }

void DK_RestoreDecor(gentity_t *entity) {
    if (entity->dk.parentId && entity->s.pos.trType == TR_GRAVITY) {
        G_SetOrigin(entity, entity->r.currentOrigin);
        VectorClear(entity->s.pos.trDelta);
    }
    if (entity->dk.decorKind > 0) { entity->think = Think; entity->die = Die; entity->use = Use; entity->touch = Push; }
    else if (entity->dk.decorKind == -1) { entity->think = Recharge; entity->use = Heal; entity->touch = HealTouch; }
}

qboolean DK_SpawnDecor(gentity_t *entity) {
    char *value;
    int i, frame, sequence;
    float scale;
    if (!strncmp(entity->classname, "deco_e", 6)) {
        decorInfo_t *info;
        int episode = entity->classname[6] - '0';
        for (i = 0; i < definitionCount; ++i)
            if (definitions[i].episode == episode && entity->model && !Q_stricmp(definitions[i].name, entity->model)) break;
        if (i == definitionCount) G_Error("dk3: %s %u: decoration %s missing from supplied table", entity->classname, entity->dk.id, entity->model ? entity->model : "<unset>");
        info = &definitions[i]; entity->dk.decorKind = i + 1;
        entity->model = G_NewString(info->model); entity->health = entity->health > 0 ? entity->health : info->health;
        if (info->explosive) entity->spawnflags |= 1;
        entity->takedamage = entity->health > 0 && !(entity->spawnflags & 2);
        G_SpawnInt("damage", "15", &entity->damage);
        entity->dk.objectMove = info->movement;
        G_SpawnString("movetype", "", &value); if (*value) entity->dk.objectMove = Movement(value);
        G_SpawnFloat("scale", "1", &scale); entity->s.dk3Scale = Com_Clamp(0.01f, 100, scale);
        G_SpawnFloat("alpha", "1", &entity->s.dk3Alpha);
        VectorScale(info->mins, entity->s.dk3Scale, entity->r.mins); VectorScale(info->maxs, entity->s.dk3Scale, entity->r.maxs);
        entity->r.contents = info->solid ? CONTENTS_SOLID : 0;
        G_SpawnInt("animseq", "0", &sequence); Animate(entity, Com_Clamp(0, 4, sequence));
        if (G_SpawnInt("frame", "0", &frame)) {
            if (frame < 0 || frame >= info->frames) {
                G_Printf("dk3: %s entity %u %s: authored frame %d outside 0..%d; using nearest valid frame\n",
                    decorMap, entity->dk.id, info->model, frame, info->frames - 1);
                frame = (int)Com_Clamp(0, info->frames - 1, frame);
            }
            entity->s.frame = entity->dk.firstFrame = entity->dk.lastFrame = frame;
            entity->dk.animationLoop = qfalse;
        }
        if (entity->spawnflags & 128) {
            G_SpawnFloat("x_speed", "0", &entity->s.apos.trDelta[ROLL]);
            G_SpawnFloat("y_speed", "0", &entity->s.apos.trDelta[PITCH]);
            G_SpawnFloat("z_speed", "90", &entity->s.apos.trDelta[YAW]); entity->s.apos.trType = TR_LINEAR;
        }
    } else if (!strcmp(entity->classname, "misc_hosportal") || !strcmp(entity->classname, "misc_fountain") ||
               !strcmp(entity->classname, "misc_healthtree") || !strcmp(entity->classname, "misc_drugbox")) {
        float recharge;
        const char *model = !strcmp(entity->classname, "misc_hosportal") ? "models/e1/hosportal2.dkm" :
            !strcmp(entity->classname, "misc_fountain") ? "models/e2/a2_hlthfnt.dkm" :
            !strcmp(entity->classname, "misc_healthtree") ? "models/e1/healthtree.dkm" : "models/e4/a4_dbox.dkm";
        entity->dk.decorKind = -1; entity->model = G_NewString(model);
        G_SpawnInt("max_fruit", strstr(entity->classname, "healthtree") ? "5" : strstr(entity->classname, "drugbox") ? "3" : "100", &entity->dk.supplyMaximum);
        G_SpawnInt("max_juice", va("%d", entity->dk.supplyMaximum), &entity->dk.supplyMaximum);
        entity->dk.supply = entity->dk.supplyMaximum;
        G_SpawnFloat("recharge_rate", strstr(entity->classname, "drugbox") ? "0" : strstr(entity->classname, "healthtree") ?
            (g_gametype.integer == GT_SINGLE_PLAYER ? "0" : "30") : "0.1", &recharge);
        entity->dk.recharge = Com_Clamp(0, 3600, recharge) * 1000;
        entity->s.dk3Alpha = 1;
        entity->s.frame = !strcmp(entity->classname, "misc_hosportal") || !strcmp(entity->classname, "misc_fountain");
        entity->dk.rechargeTime = level.time + entity->dk.recharge;
        VectorSet(entity->r.mins, -16, -16, -24); VectorSet(entity->r.maxs, 16, 16, 32); entity->r.contents = CONTENTS_SOLID;
    } else return qfalse;
    entity->s.eType = ET_GENERAL; entity->s.modelindex = G_ModelIndex(entity->model);
    G_SetOrigin(entity, entity->s.origin);
    VectorCopy(entity->s.angles, entity->s.apos.trBase); VectorCopy(entity->s.angles, entity->r.currentAngles); entity->s.apos.trTime = level.time;
    if (entity->dk.objectMove == 1 || entity->dk.objectMove == 2) entity->s.pos.trType = TR_GRAVITY;
    DK_RestoreDecor(entity); entity->nextthink = level.time + 100; trap_LinkEntity(entity);
    return qtrue;
}
