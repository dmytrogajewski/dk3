/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Original campaign/world integration using ioquake3 allocation, collision and services. */
#include "g_local.h"
#include "dk_effects.h"
#include "dk_save_schema.h"
#include "dk_game.h"
#include "dk_weapons.h"

#define DK_ACTIONS 256
#define DK_TARGET_DEPTH 64
#define DK_TRIGGER_WAIT 200
#define DK_TELEPORT_WAIT 500
#define DK_TELEPORT_RISE 64

typedef struct {
    int time;
    unsigned int owner;
    unsigned int activator;
} dkAction_t;

static dkAction_t actions[DK_ACTIONS];
typedef struct { char *target; int delay; } event_t;
static event_t events[4096];
static int eventCount;
static unsigned int nextId;
static int targetDepth;
static char mapName[MAX_QPATH];

static char *SpawnText(const char *key) {
    char *value;
    G_SpawnString(key, "", &value);
    return *value ? G_NewString(value) : NULL;
}

static qboolean Is(gentity_t *ent, const char *name) {
    return !Q_stricmp(ent->classname, name);
}

gentity_t *DK_FindEntity(unsigned int id) {
    int i;
    if (!id) return NULL;
    for (i = 0; i < level.num_entities; ++i)
        if (g_entities[i].inuse && g_entities[i].dk.id == id) return &g_entities[i];
    return NULL;
}

void DK_InitWorld(void) {
    memset(actions, 0, sizeof(actions));
    nextId = MAX_CLIENTS + 1;
    eventCount = 0;
    DK_LoadWeaponData();
    DK_LoadActors();
    DK_LoadDecor();
    DK_InitCinematics();
    DK_InitMultiplayer();
    DK_InitSaves();
    targetDepth = 0;
    trap_Cvar_VariableStringBuffer("mapname", mapName, sizeof(mapName));
    DK_LoadScripts(mapName);
    DK_LoadNavigation(mapName);
    G_Printf("dk3: native world %s; campaign implementation incomplete\n", mapName);
}

void DK_InitEntity(gentity_t *ent) {
    memset(&ent->dk, 0, sizeof(ent->dk));
    ent->dk.id = ent->s.number < MAX_CLIENTS ? ent->s.number + 1 : nextId++;
    ent->s.dk3Scale = ent->s.dk3Alpha = 1;
}

void DK_PrepareEntity(gentity_t *ent) {
    float delay;
    ent->dk.killtarget = SpawnText("killtarget");
    ent->dk.map = SpawnText("map");
    ent->dk.uniqueid = SpawnText("uniqueid");
    ent->dk.key = SpawnText("keyname");
    ent->dk.parentTarget = SpawnText("parenttarget");
    ent->dk.aiScript = SpawnText("aiscript");
    ent->dk.cineScript = SpawnText("cinescript");
    if (!ent->dk.cineScript && (Is(ent, "trigger_changelevel") || Is(ent, "target_changelevel")))
        ent->dk.cineScript = SpawnText("cinematic");
    ent->dk.cineKill = SpawnText("cinekill");
    ent->dk.cineTrigger = SpawnText("cinetrigger");
    ent->dk.deathTarget = SpawnText("deathtarget");
    ent->dk.deathSpawn = SpawnText("spawnname");
    ent->dk.pathTarget = SpawnText("path_target");
    if (!ent->dk.pathTarget) ent->dk.pathTarget = SpawnText("pathtarget");
    ent->dk.spawnClass = SpawnText("monsterclass");
    ent->dk.spawnId = SpawnText("muniqueid");
    ent->dk.targets[0] = SpawnText("target2");
    ent->dk.targets[1] = SpawnText("target3");
    ent->dk.targets[2] = SpawnText("target4");
    G_SpawnFloat("delay", "0", &delay);
    if (!(delay >= 0 && delay <= 3600))
        G_Error("dk3: %s entity %u: delay must be between 0 and 3600 seconds", mapName, ent->dk.id);
    ent->dk.delay = delay > 0 ? (int)(delay * 1000) : 0;
}

static void FireTargets(gentity_t *ent, gentity_t *activator) {
    gentity_t *target;
    const char *name;
    int i;
    if (++targetDepth > DK_TARGET_DEPTH) {
        G_Printf("dk3: %s entity %u (%s): target cycle exceeded %d calls\n",
                 mapName, ent->dk.id, ent->classname, DK_TARGET_DEPTH);
        --targetDepth;
        return;
    }
    if (ent->dk.killtarget) {
        target = NULL;
        while ((target = G_Find(target, FOFS(targetname), ent->dk.killtarget)) != NULL) {
            if (target == ent) continue;
            G_FreeEntity(target);
        }
    }
    for (i = 0; i < 4 && ent->inuse; ++i) {
        name = i ? ent->dk.targets[i - 1] : ent->target;
        if (!name) continue;
        target = NULL;
        while ((target = G_Find(target, FOFS(targetname), name)) != NULL) {
            if (target != ent && target->use) target->use(target, ent, activator);
            if (!ent->inuse) break;
        }
    }
    --targetDepth;
}

void DK_UseTargets(gentity_t *ent, gentity_t *activator) {
    int i;
    if (!ent) return;
    if (ent->targetShaderName && ent->targetShaderNewName) {
        AddRemap(ent->targetShaderName, ent->targetShaderNewName, level.time * 0.001f);
        trap_SetConfigstring(CS_SHADERSTATE, BuildShaderStateConfig());
    }
    if (!ent->dk.delay) {
        FireTargets(ent, activator);
        return;
    }
    for (i = 0; i < DK_ACTIONS; ++i) if (!actions[i].owner) {
        actions[i].owner = ent->dk.id;
        actions[i].activator = activator ? activator->dk.id : 0;
        actions[i].time = level.time + ent->dk.delay;
        return;
    }
    G_Error("dk3: %s entity %u: delayed target queue exhausted", mapName, ent->dk.id);
}

void DK_RunWorld(void) {
    int i;
    if (DK_RestoringSave()) return;
    DK_RunMultiplayer();
    DK_RunMovers();
    DK_RunStatus();
    DK_RunItemEffects();
    DK_RunScripts();
    DK_RunMonitors();
    DK_RunCinematic();
    DK_RunSaves();
    DK_UpdateCompanionStatus();
    for (i = 0; i < DK_ACTIONS; ++i) if (actions[i].owner && actions[i].time <= level.time) {
        dkAction_t action = actions[i];
        gentity_t *owner = DK_FindEntity(action.owner);
        memset(&actions[i], 0, sizeof(actions[i]));
        if (owner) FireTargets(owner, DK_FindEntity(action.activator));
    }
    DK_RepairDisabledHazards(mapName);
}

static void InitBrush(gentity_t *ent, int contents, qboolean visible) {
    if (!ent->model || ent->model[0] != '*')
        G_Error("dk3: %s entity %u (%s): required brush model is missing",
                mapName, ent->dk.id, ent->classname);
    trap_SetBrushModel(ent, ent->model);
    ent->r.contents = contents;
    ent->r.svFlags = visible ? 0 : SVF_NOCLIENT;
    ent->s.eType = visible ? ET_MOVER : ET_GENERAL;
    G_SetOrigin(ent, ent->s.origin);
    trap_LinkEntity(ent);
}

static qboolean LivingPlayer(gentity_t *ent) {
    return ent && ent->client && ent->health > 0 && ent->client->sess.sessionTeam != TEAM_SPECTATOR;
}

static void TriggerUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (level.time < ent->dk.nextUse || (ent->count > 0 && ent->dk.uses >= ent->count)) return;
    if (ent->dk.key && !DK_HasKey(activator, ent->dk.key)) {
        if (activator && activator->client) trap_SendServerCommand(activator->s.number, "cp \"A key is required.\"");
        return;
    }
    ++ent->dk.uses;
    if (Is(ent, "trigger_secret")) {
        int i, found = 0, total = 0, episode = mapName[1] >= '1' && mapName[1] <= '4' ? mapName[1] - '0' : 1;
        for (i = MAX_CLIENTS; i < level.num_entities; ++i)
            if (g_entities[i].inuse && Is(&g_entities[i], "trigger_secret")) {
                ++total; if (g_entities[i].dk.uses) ++found;
            }
        trap_SendServerCommand(-1, va("cp \"Secret discovered (%d/%d).\"", found, total));
        if (activator) G_Sound(activator, CHAN_AUTO, DK_SoundIndex(va("e%d/e%d_secret.wav", episode, episode)));
    }
    ent->dk.nextUse = level.time + (ent->wait > 0 ? (int)(ent->wait * 1000) : DK_TRIGGER_WAIT);
    if (ent->message && LivingPlayer(activator))
        trap_SendServerCommand(activator->s.number, va("cp \"%s\"", ent->message));
    G_UseTargets(ent, activator);
}

static void TriggerTouch(gentity_t *ent, gentity_t *other, trace_t *trace) {
    (void)trace;
    if (ent->spawnflags & 1) return;
    if (LivingPlayer(other) || ((ent->spawnflags & 2) && other->dk.actorKind) ||
        ((ent->spawnflags & 4) && DK_IsCompanion(other))) TriggerUse(ent, other, other);
}

static qboolean SafeMap(const char *name) {
    const char *p;
    if (!name || !*name || strlen(name) >= MAX_QPATH) return qfalse;
    for (p = name; *p; ++p)
        if (!((*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9') || *p == '_')) return qfalse;
    return qtrue;
}

static void ChangeLevel(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    fileHandle_t handle;
    (void)other;
    if (!LivingPlayer(activator) || ent->dk.uses) return;
    if (ent->dk.key && !DK_HasKey(activator, ent->dk.key)) {
        if (level.time >= ent->dk.nextUse) {
            trap_SendServerCommand(activator->s.number, "cp \"A required item is missing.\"");
            ent->dk.nextUse = level.time + 1000;
        }
        return;
    }
    if (!DK_CompanionsReady(activator, ent->spawnflags & 6)) return;
    if (!SafeMap(ent->dk.map)) {
        G_Printf("dk3: %s entity %u: invalid exit map\n", mapName, ent->dk.id);
        return;
    }
    if (trap_FS_FOpenFile(va("maps/%s.bsp", ent->dk.map), &handle, FS_READ) < 0) {
        G_Printf("dk3: %s entity %u: missing maps/%s.bsp\n", mapName, ent->dk.id, ent->dk.map);
        return;
    }
    trap_FS_FCloseFile(handle);
    if (ent->dk.cineScript && !ent->dk.cinematicCompleted && DK_StartCinematic(ent->dk.cineScript, ent, activator)) {
        ent->dk.uses = 1;
        return;
    }
    if (!DK_ArchiveLevel(activator)) return;
    ent->dk.uses = 1;
    trap_Cvar_Set("dk3_entry", ent->target ? ent->target : "");
    DK_WriteCompanionTravel();
    DK_WriteTravel(activator);
    trap_SendConsoleCommand(EXEC_INSERT, va("map %s\n", ent->dk.map));
}

void DK_CinematicFinished(gentity_t *trigger, gentity_t *activator) {
    if (!trigger) return;
    trigger->dk.cinematicCompleted = 1;
    if (Is(trigger, "trigger_changelevel") || Is(trigger, "target_changelevel")) {
        trigger->dk.uses = 0;
        ChangeLevel(trigger, trigger, activator);
    }
}

static void ExitTouch(gentity_t *ent, gentity_t *other, trace_t *trace) {
    (void)trace;
    ChangeLevel(ent, other, other);
}

gentity_t *DK_SelectSpawn(vec3_t origin, vec3_t angles) {
    char entry[MAX_QPATH];
    gentity_t *spot = NULL, *first = NULL, *namedCoop = NULL;
    int i;
    if (g_gametype.integer != GT_SINGLE_PLAYER) return NULL;
    trap_Cvar_VariableStringBuffer("dk3_entry", entry, sizeof(entry));
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *candidate = &g_entities[i];
        if (!candidate->inuse || !candidate->classname) continue;
        if (!Q_stricmp(candidate->classname, "info_player_coop")) {
            if (!namedCoop && *entry && candidate->targetname && !Q_stricmp(candidate->targetname, entry)) namedCoop = candidate;
            continue;
        }
        if (Q_stricmp(candidate->classname, "info_player_start") &&
            Q_stricmp(candidate->classname, "info_player_deathmatch")) continue;
        if (!first) first = candidate;
        if ((*entry && candidate->targetname && !Q_stricmp(candidate->targetname, entry)) ||
            (!*entry && !candidate->targetname)) { spot = candidate; break; }
    }
    /* Some authored entry names exist only on the companion/coop markers; the
       nearby single-player marker instead has a cinematic actor name. Honor
       the exit's named landing rather than selecting an unrelated map entrance. */
    if (!spot) spot = namedCoop;
    if (!spot) {
        spot = first;
        if (*entry) G_Printf("dk3: %s: entry %s has no player landing; using the default spawn\n", mapName, entry);
    }
    if (spot) {
        VectorCopy(spot->s.origin, origin);
        origin[2] += 9;
        VectorCopy(spot->s.angles, angles);
    }
    return spot;
}

void DK_ClientSpawn(gentity_t *ent) {
    DK_InitEntity(ent);
    DK_StartingInventory(ent);
    if (g_gametype.integer == GT_SINGLE_PLAYER && !DK_ResumeSave(ent)) {
        if (DK_LoadRequested(ent)) return;
        DK_RestoreVisited(ent);
        DK_ReadTravel(ent);
        DK_StartCompanions(ent);
        trap_Cvar_Set("dk3_entry", "");
    }
}


enum { WALL_TRIGGER = 1, WALL_TOGGLE = 2, WALL_START_ON = 4, WALL_NOT_SOLID = 32, WALL_CTF_ONLY = 64 };

static void WallUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    qboolean visible;
    (void)other;
    if ((ent->dk.uses && !(ent->spawnflags & WALL_TOGGLE)) ||
        ((ent->spawnflags & WALL_CTF_ONLY) && g_gametype.integer != GT_CTF)) return;
    visible = (ent->r.svFlags & SVF_NOCLIENT) != 0;
    if (visible) ent->r.svFlags &= ~SVF_NOCLIENT;
    else ent->r.svFlags |= SVF_NOCLIENT;
    ent->r.contents = visible && !(ent->spawnflags & WALL_NOT_SOLID) ? CONTENTS_SOLID : 0;
    ++ent->dk.uses;
    trap_LinkEntity(ent);
    G_UseTargets(ent, activator);
}

static void BreakUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    vec3_t center;
    (void)other;
    if (ent->dk.uses) return;
    if ((ent->spawnflags & 1) && (ent->r.svFlags & SVF_NOCLIENT)) {
        ent->spawnflags &= ~1;
        ent->r.svFlags &= ~SVF_NOCLIENT;
        ent->r.contents = ent->spawnflags & 512 ? 0 : CONTENTS_SOLID;
        ent->takedamage = !ent->targetname;
        trap_LinkEntity(ent);
        return;
    }
    ent->dk.uses = 1;
    VectorAdd(ent->r.absmin, ent->r.absmax, center); VectorScale(center, 0.5f, center);
    if (!(ent->spawnflags & 64)) DK_WorldDebris(ent, ent->spawnflags & 8 ? DK_DEBRIS_STONE :
        ent->spawnflags & 16 ? DK_DEBRIS_WOOD : ent->spawnflags & 32 ? DK_DEBRIS_METAL : DK_DEBRIS_GLASS);
    ent->takedamage = qfalse;
    ent->r.contents = 0;
    ent->r.svFlags |= SVF_NOCLIENT;
    trap_UnlinkEntity(ent);
    if (ent->damage > 0) G_RadiusDamage(center, activator, ent->damage,
                                       ent->splashRadius > 0 ? ent->splashRadius : 160,
                                       ent, MOD_CRUSH);
    G_UseTargets(ent, activator);
}

static void BreakDie(gentity_t *ent, gentity_t *inflictor, gentity_t *attacker, int damage, int mod) {
    (void)damage; (void)mod;
    BreakUse(ent, inflictor, attacker);
}

static void TeleportTouch(gentity_t *ent, gentity_t *other, trace_t *trace) {
    gentity_t *destination;
    vec3_t landing;
    trace_t space, path;
    int rise;
    (void)trace;
    if (!LivingPlayer(other) || other->dk.nextUse > level.time || !ent->target) return;
    destination = G_Find(NULL, FOFS(targetname), ent->target);
    if (!destination) {
        G_Printf("dk3: %s entity %u: teleport target %s missing\n", mapName, ent->dk.id, ent->target);
        return;
    }
    for (rise = 0; rise <= DK_TELEPORT_RISE; rise += 4) {
        VectorCopy(destination->s.origin, landing); landing[2] += 1 + rise;
        trap_Trace(&path, destination->s.origin, NULL, NULL, landing, other->s.number, MASK_SOLID);
        if (path.startsolid || path.fraction < 1) break;
        trap_Trace(&space, landing, other->r.mins, other->r.maxs, landing, other->s.number, MASK_SOLID);
        if (!space.startsolid && !space.allsolid) {
            landing[2] -= 1; /* TeleportPlayer adds the final one-unit offset. */
            TeleportPlayer(other, landing, destination->s.angles);
            other->dk.nextUse = level.time + DK_TELEPORT_WAIT;
            return;
        }
    }
    G_Printf("dk3: %s teleport %u: destination %s has no clear landing within %d units\n",
        mapName, ent->dk.id, ent->target, DK_TELEPORT_RISE);
    other->dk.nextUse = level.time + DK_TELEPORT_WAIT;
}

static void ScriptThink(gentity_t *ent) {
    if (ent->dk.cineScript) DK_StartCinematic(ent->dk.cineScript, ent, DK_FindEntity(ent->dk.ownerId));
    if (ent->dk.aiScript) DK_StartScript(ent->dk.aiScript, ent, DK_FindEntity(ent->dk.ownerId), qfalse);
    FireTargets(ent, DK_FindEntity(ent->dk.ownerId));
}

static void ScriptUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (level.time < ent->dk.nextUse || (ent->dk.uses && !(ent->spawnflags & 1))) return;
    if (ent->dk.key && !DK_HasKey(activator, ent->dk.key)) {
        if (LivingPlayer(activator) && level.time >= ent->pain_debounce_time) {
            trap_SendServerCommand(activator->s.number, va("cp \"Required item: %s\"", ent->dk.key));
            ent->pain_debounce_time = level.time + 2000;
        }
        return;
    }
    if (activator && activator->client && !DK_CompanionsReady(activator, (ent->spawnflags >> 1) & 6)) return;
    ent->dk.ownerId = activator ? activator->dk.id : 0;
    ent->dk.nextUse = level.time + (int)((ent->wait > 0 ? ent->wait : 2) * 1000);
    ++ent->dk.uses;
    ent->think = ScriptThink;
    if (ent->dk.cineScript && ent->dk.delay <= 0) {
        ent->nextthink = 0;
        ScriptThink(ent);
    } else ent->nextthink = level.time + (ent->dk.delay > 0 ? ent->dk.delay : 1);
}

static void ScriptTouch(gentity_t *ent, gentity_t *other, trace_t *trace) {
    (void)trace;
    if (!(ent->spawnflags & 2) && LivingPlayer(other)) ScriptUse(ent, other, other);
}

static void SpawnMonster(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    gentity_t *actor;
    (void)other;
    if (!ent->dk.spawnClass || (ent->count > 0 && ent->dk.uses >= ent->count)) return;
    if (ent->dk.spawnId && DK_FindNamed(ent->dk.spawnId)) {
        G_Printf("dk3: %s entity %u: spawn identifier %s is already alive\n", mapName, ent->dk.id, ent->dk.spawnId);
        return;
    }
    actor = G_Spawn();
    actor->classname = ent->dk.spawnClass;
    actor->dk.uniqueid = ent->dk.spawnId;
    actor->dk.deathTarget = ent->dk.deathTarget;
    actor->dk.deathSpawn = ent->dk.deathSpawn;
    actor->spawnflags = ent->spawnflags;
    VectorCopy(ent->s.origin, actor->s.origin);
    VectorCopy(ent->s.angles, actor->s.angles);
    if (!DK_SpawnActor(actor)) {
        G_Printf("dk3: %s entity %u: unknown spawn class %s\n", mapName, ent->dk.id, ent->dk.spawnClass);
        G_FreeEntity(actor);
        return;
    }
    ++ent->dk.uses;
    G_UseTargets(ent, activator);
}

static void EventsThink(gentity_t *ent) {
    while (ent->dk.eventCursor < ent->dk.eventCount) {
        event_t *event = &events[ent->dk.eventFirst + ent->dk.eventCursor];
        if (ent->dk.eventStart + event->delay > level.time) {
            ent->nextthink = ent->dk.eventStart + event->delay;
            return;
        }
        ++ent->dk.eventCursor;
        DK_FireNamed(event->target, ent, DK_FindEntity(ent->dk.ownerId));
        if (!ent->inuse) return;
    }
    ent->dk.eventStart = 0;
    ent->dk.nextUse = level.time + (ent->wait > 0 ? (int)(ent->wait * 1000) : DK_TRIGGER_WAIT);
}

static void EventsUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    if (other && (LivingPlayer(other) || other->dk.actorKind)) activator = other;
    if (!LivingPlayer(activator) && !((ent->spawnflags & 4) && activator && activator->dk.actorKind && activator->health > 0)) return;
    if (ent->dk.eventStart || level.time < ent->dk.nextUse || ((ent->spawnflags & 1) && ent->dk.uses)) return;
    ent->dk.eventStart = level.time ? level.time : 1;
    ent->dk.eventCursor = 0;
    ent->dk.ownerId = activator ? activator->dk.id : 0;
    ++ent->dk.uses;
    if (ent->noise_index) G_Sound(ent, CHAN_AUTO, ent->noise_index);
    if (trap_Cvar_VariableIntegerValue("developer"))
        G_Printf("dk3 event %s id%u (%s): activated by %u (%s), %d actions\n", mapName, ent->dk.id,
            ent->targetname ? ent->targetname : "unnamed", activator->dk.id, activator->classname, ent->dk.eventCount);
    ent->think = EventsThink;
    ent->nextthink = level.time + 1;
}

static void EventsTouch(gentity_t *ent, gentity_t *other, trace_t *trace) {
    (void)trace;
    if ((ent->spawnflags & 2) && (LivingPlayer(other) || ((ent->spawnflags & 4) && other->dk.actorKind)))
        EventsUse(ent, other, other);
}

static void SpawnEvents(gentity_t *ent) {
    const char *reserved[] = {"classname", "model", "origin", "angle", "angles", "targetname", "spawnflags",
                             "wait", "sound", "volume", "health", "delay", "_color", "min", "max"};
    int i, j, k;
    ent->dk.eventFirst = eventCount;
    for (i = 0; i < level.numSpawnVars; ++i) {
        const char *name = level.spawnVars[i][0], *value = level.spawnVars[i][1], *p = value;
        float seconds;
        event_t event;
        for (j = 0; j < ARRAY_LEN(reserved); ++j) if (!Q_stricmp(name, reserved[j])) break;
        if (j < ARRAY_LEN(reserved)) continue;
        if (*p == '+') ++p;
        if (!*p) continue;
        while ((*p >= '0' && *p <= '9') || *p == '.') ++p;
        if (*p) { G_Printf("dk3: %s event %u: invalid delay %s=%s\n", mapName, ent->dk.id, name, value); continue; }
        seconds = atof(value);
        if (Q_isnan(seconds) || seconds < 0 || seconds > 3600 || eventCount == ARRAY_LEN(events))
            G_Error("dk3: %s event %u: invalid delay or event limit", mapName, ent->dk.id);
        event.target = G_NewString(name); event.delay = (int)(seconds * 1000);
        k = eventCount++;
        while (k > ent->dk.eventFirst && events[k - 1].delay > event.delay) { events[k] = events[k - 1]; --k; }
        events[k] = event;
        ++ent->dk.eventCount;
    }
    ent->use = EventsUse;
    {
        char *sound;
        G_SpawnString("sound", "", &sound);
        ent->noise_index = DK_SoundIndex(sound);
    }
    if (ent->model) {
        InitBrush(ent, ent->spawnflags & 2 ? CONTENTS_TRIGGER : 0, qfalse);
        if (ent->spawnflags & 2) ent->touch = EventsTouch;
    }
}

static void CounterUse(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (ent->dk.uses >= ent->count) return;
    if (++ent->dk.uses == ent->count) G_UseTargets(ent, activator);
}

static void ChangeTarget(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    gentity_t *target = NULL;
    (void)other; (void)activator;
    if (!ent->target) return;
    while ((target = G_Find(target, FOFS(targetname), ent->target)) != NULL) target->target = ent->dk.pathTarget;
}

qboolean DK_SpawnEntity(gentity_t *ent) {
    if (DK_SpawnWorldEffect(ent) || DK_SpawnCompanionEntity(ent) || DK_SpawnMover(ent) || DK_SpawnMultiplayer(ent) || DK_SpawnItem(ent) || DK_SpawnActor(ent) || DK_SpawnDecor(ent) || DK_SpawnMedia(ent) || DK_SpawnInteraction(ent)) return qtrue;
    if (Is(ent, "trigger_script")) {
        ent->use = ScriptUse;
        if (ent->model) { InitBrush(ent, CONTENTS_TRIGGER, qfalse); ent->touch = ScriptTouch; }
    } else if (Is(ent, "func_event_generator")) {
        SpawnEvents(ent);
    } else if (Is(ent, "target_monster_spawn")) {
        ent->use = SpawnMonster; ent->r.svFlags |= SVF_NOCLIENT;
        G_SetOrigin(ent, ent->s.origin);
    } else if (Is(ent, "trigger_counter")) {
        ent->use = CounterUse;
        if (ent->count <= 0) ent->count = 2;
    } else if (Is(ent, "trigger_changetarget")) {
        ent->dk.pathTarget = SpawnText("newtarget");
        ent->use = ChangeTarget;
    } else if (Is(ent, "trigger_changelevel") || Is(ent, "target_changelevel")) {
        ent->use = ChangeLevel;
        if (ent->model) { ent->touch = ExitTouch; InitBrush(ent, CONTENTS_TRIGGER, qfalse); }
    } else if (Is(ent, "trigger_once") || Is(ent, "trigger_multiple") ||
               Is(ent, "trigger_secret") || Is(ent, "trigger_relay")) {
        if (Is(ent, "trigger_once") || Is(ent, "trigger_secret")) ent->count = 1;
        ent->use = TriggerUse;
        if (ent->model) { ent->touch = TriggerTouch; InitBrush(ent, CONTENTS_TRIGGER, qfalse); }
    } else if (Is(ent, "func_explosive") || Is(ent, "func_breakable")) {
        InitBrush(ent, CONTENTS_SOLID, qtrue);
        ent->use = BreakUse;
        ent->die = BreakDie;
        ent->takedamage = !ent->targetname;
        if (ent->health <= 0) ent->health = 100;
        if (ent->spawnflags & 512) ent->r.contents = 0;
        if (ent->spawnflags & 1) {
            ent->r.contents = 0; ent->r.svFlags |= SVF_NOCLIENT; ent->takedamage = qfalse;
        }
        trap_LinkEntity(ent);
    } else if (Is(ent, "func_wall")) {
        InitBrush(ent, CONTENTS_SOLID, qtrue);
        ent->use = WallUse;
        /* Toggle walls are dormant until activated unless START_ON is set.
           Visibility cannot be inferred from collision: visible nonsolid
           scenery uses the same activation path. */
        if (ent->spawnflags & WALL_NOT_SOLID) ent->r.contents = 0;
        if (((ent->spawnflags & (WALL_TRIGGER | WALL_TOGGLE)) && !(ent->spawnflags & WALL_START_ON)) ||
            ((ent->spawnflags & WALL_CTF_ONLY) && g_gametype.integer != GT_CTF)) {
            ent->r.contents = 0; ent->r.svFlags |= SVF_NOCLIENT;
        }
        trap_LinkEntity(ent);
    } else if (Is(ent, "trigger_teleport")) {
        InitBrush(ent, CONTENTS_TRIGGER, qfalse);
        ent->touch = TeleportTouch;
    } else if (Is(ent, "info_not_null") || Is(ent, "info_teleport_destination") ||
               Is(ent, "monster_path_corner") || Is(ent, "info_aiscript") || Is(ent, "info_player_coop")) {
        ent->r.svFlags |= SVF_NOCLIENT;
        G_SetOrigin(ent, ent->s.origin);
    } else if (Is(ent, "light_spot")) {
        /* Authored illumination is baked into the converted map lightmaps. */
        G_FreeEntity(ent);
    } else if (Is(ent, "func_areaportal") || Is(ent, "func_areaportalass")) {
        ent->r.svFlags |= SVF_NOCLIENT;
        /* The converted BSP currently has one area; there is no portal to close. */
    } else {
        return qfalse;
    }
    return qtrue;
}

void DK_AdoptEntityId(gentity_t *ent, unsigned int id) {
    ent->dk.id = id;
    if (nextId <= id) nextId = id + 1;
}

qboolean DK_WriteWorldState(dkSaveWriter_t *writer) {
    static const dkSaveMember_t members[] = {
        {"due", DK_SAVE_INT, offsetof(dkAction_t, time), 1, qtrue},
        {"owner", DK_SAVE_INT, offsetof(dkAction_t, owner), 1, qfalse},
        {"activator", DK_SAVE_INT, offsetof(dkAction_t, activator), 1, qfalse}
    };
    int i;
    if (!DK_SaveRecord(writer, "world", 0) || !DK_SaveInts(writer, "next_id", (const int *)&nextId, 1)) return qfalse;
    for (i = 0; i < eventCount; ++i)
        if (!DK_SaveRecord(writer, "world_event", i + 1) || !DK_SaveText(writer, "target", events[i].target) ||
            !DK_SaveInts(writer, "delay", &events[i].delay, 1)) return qfalse;
    for (i = 0; i < DK_ACTIONS; ++i) if (actions[i].owner && DK_FindEntity(actions[i].owner)) {
        dkAction_t action = actions[i];
        if (!DK_FindEntity(action.activator)) action.activator = 0;
        if (!DK_SaveRecord(writer, "world_action", i + 1) ||
            !DK_SaveObject(writer, &action, members, ARRAY_LEN(members))) return qfalse;
    }
    return qtrue;
}

qboolean DK_ReadWorldState(dkSaveReader_t *reader, const char *kind, unsigned int id, qboolean apply) {
    static const dkSaveMember_t members[] = {
        {"due", DK_SAVE_INT, offsetof(dkAction_t, time), 1, qtrue},
        {"owner", DK_SAVE_INT, offsetof(dkAction_t, owner), 1, qfalse},
        {"activator", DK_SAVE_INT, offsetof(dkAction_t, activator), 1, qfalse}
    };
    if (!strcmp(kind, "world")) {
        dkSaveField_t field;
        if (id || !DK_SaveNextField(reader, &field) || strcmp(field.name, "next_id") ||
            field.type != DK_SAVE_INT || field.count != 1 || DK_SaveInt(&field, 0) <= MAX_CLIENTS || reader->fieldsLeft)
            return qfalse;
        if (apply) { nextId = DK_SaveInt(&field, 0); eventCount = 0; memset(actions, 0, sizeof(actions)); }
        return qtrue;
    }
    if (!strcmp(kind, "world_event")) {
        dkSaveField_t field;
        char target[256];
        int delay;
        if (!id || id > ARRAY_LEN(events) || !DK_SaveNextField(reader, &field) || strcmp(field.name, "target") ||
            !DK_SaveString(&field, target, sizeof(target)) || !*target || !DK_SaveNextField(reader, &field) ||
            strcmp(field.name, "delay") || field.type != DK_SAVE_INT || field.count != 1 || reader->fieldsLeft) return qfalse;
        delay = DK_SaveInt(&field, 0);
        if (delay < 0 || delay > 3600000) return qfalse;
        if (apply) {
            if (id != eventCount + 1) return qfalse;
            events[eventCount].target = G_NewString(target); events[eventCount++].delay = delay;
        }
        return qtrue;
    }
    if (!strcmp(kind, "world_action")) {
        dkAction_t action;
        if (!id || id > DK_ACTIONS || !DK_ReadObject(reader, &action, members, ARRAY_LEN(members), NULL) || !action.owner ||
            !DK_SaveReferenceExists(action.owner) || !DK_SaveReferenceExists(action.activator))
            return qfalse;
        if (apply) actions[id - 1] = action;
        return qtrue;
    }
    return qfalse;
}

void DK_RestoreWorldCallbacks(gentity_t *ent) {
    if (Is(ent, "func_event_generator")) { ent->think = EventsThink; ent->use = EventsUse; }
    else if (Is(ent, "trigger_script")) { ent->think = ScriptThink; ent->use = ScriptUse; }
    else if (Is(ent, "func_explosive") || Is(ent, "func_breakable")) { ent->die = BreakDie; ent->use = BreakUse; }
    else if (Is(ent, "func_wall")) ent->use = WallUse;
}
