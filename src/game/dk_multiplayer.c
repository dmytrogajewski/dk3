/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native team objectives. Map entities own geometry and switches; these rules
   own flag/bomb state, scoring, possession, drops and simulation-time deadlines. */
#include "g_local.h"

#define DK_FLAG_RETURN_MS 60000
#define DK_BOMB_FUSE_MS 90000
#define DK_BOMB_PLANTED_MS 5000
#define DK_BOMB_RESPAWN_MS 10000

typedef enum { OBJ_HOME, OBJ_CARRIED, OBJ_DROPPED, OBJ_PLANTED, OBJ_RESETTING } objectiveState_t;
typedef struct {
    unsigned int entity, carrier;
    objectiveState_t state;
    vec3_t home, angles;
    int deadline, nextBeep, pickupAfter, nextHeartbeat, warned;
} objective_t;
static objective_t objectives[2];

qboolean DK_ObjectiveMode(void) {
    return g_gametype.integer == GT_CTF || g_gametype.integer == GT_DK3_DEATHTAG;
}

void DK_InitMultiplayer(void) { memset(objectives, 0, sizeof(objectives)); }

static qboolean Player(gentity_t *ent) {
    return ent && ent->inuse && ent->client && ent->client->pers.connected == CON_CONNECTED &&
        ent->health > 0 && (ent->client->sess.sessionTeam == TEAM_RED || ent->client->sess.sessionTeam == TEAM_BLUE);
}

static void Status(void) {
    char text[3];
    int i;
    for (i = 0; i < 2; ++i) text[i] = objectives[i].state == OBJ_HOME ? '0' : objectives[i].state == OBJ_CARRIED ? '1' : '2';
    text[2] = 0;
    trap_SetConfigstring(CS_FLAGSTATUS, text);
}

static void Sound(gentity_t *ent, const char *name) { G_AddEvent(ent, EV_GENERAL_SOUND, G_SoundIndex(name)); }

static void ClearCarrier(objective_t *objective) {
    gentity_t *carrier = DK_FindEntity(objective->carrier);
    if (carrier && carrier->client) {
        carrier->client->ps.dk3Objective = 0;
        carrier->client->ps.dk3ObjectiveUntil = 0;
    }
    objective->carrier = 0;
}

static void Place(objective_t *objective, const vec3_t origin, qboolean visible, qboolean touchable) {
    gentity_t *entity = DK_FindEntity(objective->entity);
    if (!entity) return;
    {
        gentity_t *carrier = DK_FindEntity(objective->carrier);
        entity->s.dk3Carrier = carrier && carrier->client ? carrier->s.number + 1 : 0;
    }
    G_SetOrigin(entity, origin);
    entity->r.contents = touchable ? CONTENTS_TRIGGER : 0;
    entity->r.svFlags = visible ? 0 : SVF_NOCLIENT;
    trap_LinkEntity(entity);
}

static void Reset(objective_t *objective) {
    ClearCarrier(objective);
    objective->state = OBJ_HOME;
    objective->deadline = objective->nextBeep = objective->pickupAfter = 0;
    objective->nextHeartbeat = objective->warned = 0;
    Place(objective, objective->home, qtrue, qtrue);
    Status();
}

static void Explode(objective_t *objective) {
    gentity_t *entity = DK_FindEntity(objective->entity), *effect;
    int i;
    if (!entity) return;
    ClearCarrier(objective);
    objective->state = OBJ_RESETTING;
    objective->deadline = level.time + DK_BOMB_RESPAWN_MS;
    Place(objective, entity->r.currentOrigin, qfalse, qfalse);
    effect = G_TempEntity(entity->r.currentOrigin, EV_DK3_BLAST);
    effect->r.svFlags |= SVF_BROADCAST;
    Sound(effect, "sounds/global/a_ames.wav");
    G_LogPrintf("DK3Objective: %d explode\n", entity->s.dk3Team);
    /* Bomb blast ignores team protection; each victim is its own damage source. */
    for (i = 0; i < level.maxclients; ++i) {
        gentity_t *victim = &g_entities[i];
        if (Player(victim) && Distance(victim->r.currentOrigin, entity->r.currentOrigin) < 400)
            G_Damage(victim, entity, victim, NULL, entity->r.currentOrigin, 1000,
                     DAMAGE_NO_PROTECTION | DAMAGE_NO_ARMOR, MOD_GRENADE_SPLASH);
    }
    Status();
}

static void ObjectiveTouch(gentity_t *entity, gentity_t *player, trace_t *trace) {
    int index = entity->s.dk3Team - TEAM_RED;
    objective_t *objective;
    qboolean own;
    (void)trace;
    if (!Player(player) || index < 0 || index >= 2 || level.intermissiontime || level.warmupTime) return;
    objective = &objectives[index];
    if ((objective->state != OBJ_HOME && objective->state != OBJ_DROPPED) || level.time < objective->pickupAfter) return;
    own = player->client->sess.sessionTeam == entity->s.dk3Team;
    if (g_gametype.integer == GT_DK3_DEATHTAG) {
        if (!own) { if (objective->state == OBJ_DROPPED) Explode(objective); return; }
    } else if (own) {
        if (objective->state == OBJ_DROPPED) {
            Reset(objective); AddScore(player, player->r.currentOrigin, 1);
            G_LogPrintf("DK3Objective: %d return %d\n", entity->s.dk3Team, player->s.number);
            trap_SendServerCommand(-1, va("print \"%s flag returned.\n\"", TeamName(entity->s.dk3Team)));
        }
        return;
    }
    if (player->client->ps.dk3Objective) return;
    if (g_gametype.integer == GT_DK3_DEATHTAG && objective->state == OBJ_HOME)
        objective->deadline = level.time + DK_BOMB_FUSE_MS;
    if (g_gametype.integer == GT_CTF) objective->deadline = 0;
    objective->state = OBJ_CARRIED;
    objective->carrier = player->dk.id;
    player->client->ps.dk3Objective = index + 1;
    player->client->ps.dk3ObjectiveUntil = objective->deadline;
    Place(objective, player->r.currentOrigin, qtrue, qfalse);
    Sound(player, "sounds/global/a_hpick.wav");
    G_LogPrintf("DK3Objective: %d pickup %d\n", entity->s.dk3Team, player->s.number);
    trap_SendServerCommand(-1, va("print \"%s objective taken.\n\"", TeamName(entity->s.dk3Team)));
    Status();
}

void DK_DropObjective(gentity_t *player) {
    int index;
    objective_t *objective;
    vec3_t bottom;
    trace_t trace;
    gentity_t *entity;
    if (!player->client || !player->client->ps.dk3Objective) return;
    index = player->client->ps.dk3Objective - 1;
    if (index < 0 || index >= 2) return;
    objective = &objectives[index];
    if (objective->carrier != player->dk.id) return;
    entity = DK_FindEntity(objective->entity);
    ClearCarrier(objective);
    if (!entity) return;
    objective->state = OBJ_DROPPED;
    if (g_gametype.integer == GT_CTF) objective->deadline = level.time + DK_FLAG_RETURN_MS;
    objective->pickupAfter = level.time + 750;
    G_LogPrintf("DK3Objective: %d drop %d\n", entity->s.dk3Team, player->s.number);
    VectorCopy(player->r.currentOrigin, bottom); bottom[2] -= 512;
    trap_Trace(&trace, player->r.currentOrigin, entity->r.mins, entity->r.maxs, bottom, player->s.number, MASK_SOLID);
    Place(objective, trace.startsolid ? player->r.currentOrigin : trace.endpos, qtrue, qtrue);
    if (trap_PointContents(entity->r.currentOrigin, entity->s.number) & (CONTENTS_LAVA | CONTENTS_SLIME | CONTENTS_NODROP)) {
        if (g_gametype.integer == GT_CTF) Reset(objective); else Explode(objective);
    }
    Status();
}

static void Capture(gentity_t *zone, gentity_t *player, trace_t *trace) {
    int index, team, points;
    objective_t *objective;
    vec3_t center;
    (void)trace;
    if (!Player(player) || !player->client->ps.dk3Objective || level.warmupTime || level.intermissiontime) return;
    team = player->client->sess.sessionTeam;
    if ((zone->spawnflags & 3) == 1 && team != TEAM_RED) return;
    if ((zone->spawnflags & 3) == 2 && team != TEAM_BLUE) return;
    index = player->client->ps.dk3Objective - 1;
    if (index < 0 || index > 1) return;
    objective = &objectives[index];
    if (objective->state != OBJ_CARRIED || objective->carrier != player->dk.id) return;
    if (g_gametype.integer == GT_CTF && objectives[team - TEAM_RED].state != OBJ_HOME) return;
    ClearCarrier(objective);
    points = zone->count > 0 ? zone->count : 1;
    AddTeamScore(player->r.currentOrigin, team, points);
    AddScore(player, player->r.currentOrigin, points * 5);
    if (g_gametype.integer == GT_CTF) {
        int i;
        vec3_t home;
        VectorCopy(objectives[team - TEAM_RED].home, home);
        for (i = 0; i < level.maxclients; ++i) {
            gentity_t *mate = &g_entities[i];
            if (!mate->inuse || !mate->client || mate->client->pers.connected != CON_CONNECTED ||
                mate->client->sess.sessionTeam != team) continue;
            AddScore(mate, mate->r.currentOrigin, 5);
            if (mate != player && mate->health > 0 && CanDamage(mate, home)) AddScore(mate, mate->r.currentOrigin, 1);
        }
    }
    ++player->client->ps.persistant[PERS_CAPTURES];
    G_LogPrintf("DK3Capture: %d %d %d %d\n", player->s.number, team, points, level.teamScores[team]);
    if (g_gametype.integer == GT_CTF) Reset(objective);
    else {
        objective->state = OBJ_PLANTED;
        if (objective->deadline > level.time + DK_BOMB_PLANTED_MS) objective->deadline = level.time + DK_BOMB_PLANTED_MS;
        VectorAdd(zone->r.absmin, zone->r.absmax, center); VectorScale(center, 0.5f, center);
        Place(objective, center, qtrue, qfalse);
    }
    trap_SendServerCommand(-1, va("cp \"%s scores!\"", TeamName(team)));
    Sound(player, "sounds/global/bossdeath6.wav");
    G_UseTargets(zone, player);
    Status();
}

qboolean DK_SpawnMultiplayer(gentity_t *entity) {
    const char *name = entity->classname;
    int team = !strcmp(name, "item_flag_team1") ? TEAM_RED : !strcmp(name, "item_flag_team2") ? TEAM_BLUE : TEAM_FREE;
    if (!strcmp(name, "info_player_team1") || !strcmp(name, "info_player_team2")) {
        /* Team arenas are also offered for free-for-all. Reuse all authored
           team starts there so the ordinary ioquake3 spawn/telefrag rules work. */
        if (g_gametype.integer != GT_SINGLE_PLAYER && !DK_ObjectiveMode())
            entity->classname = "info_player_deathmatch";
        entity->r.svFlags |= SVF_NOCLIENT;
        G_SetOrigin(entity, entity->s.origin);
        return qtrue;
    }
    if (!team && strcmp(name, "trigger_capture")) return qfalse;
    if (!DK_ObjectiveMode()) { G_FreeEntity(entity); return qtrue; }
    if (team) {
        objective_t *objective = &objectives[team - TEAM_RED];
        char map[MAX_QPATH];
        if (objective->entity) G_Error("dk3: duplicate %s objective", TeamName(team));
        trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
        if (g_gametype.integer == GT_DK3_DEATHTAG) entity->model = "models/global/dt_bpack.dkm";
        else if (map[1] == '2') entity->model = G_NewString(va("models/e2/ctflag_%s.dkm", team == TEAM_RED ? "red" : "blue"));
        else if (map[1] == '3') entity->model = G_NewString(va("models/e3/e3ctflag_%s.dkm", team == TEAM_RED ? "red" : "blue"));
        else entity->model = "models/global/a_ctf_flag.dkm";
        entity->s.modelindex = G_ModelIndex(entity->model);
        entity->s.dk3Team = team;
        entity->s.eType = ET_DK3_ITEM;
        entity->touch = ObjectiveTouch;
        VectorSet(entity->r.mins, -16, -16, -16); VectorSet(entity->r.maxs, 16, 16, 24);
        objective->entity = entity->dk.id;
        VectorCopy(entity->s.origin, objective->home); VectorCopy(entity->s.angles, objective->angles);
        Reset(objective);
    } else {
        if (!entity->model || entity->model[0] != '*') G_Error("dk3: capture zone needs a brush model");
        G_SpawnInt("points", "1", &entity->count);
        if (entity->count < 1 || entity->count > 100) G_Error("dk3: capture points must be between 1 and 100");
        trap_SetBrushModel(entity, entity->model);
        entity->r.svFlags |= SVF_NOCLIENT;
        entity->r.contents = CONTENTS_TRIGGER;
        entity->touch = Capture;
        trap_LinkEntity(entity);
        VectorAdd(entity->r.absmin, entity->r.absmax, entity->s.origin);
        VectorScale(entity->s.origin, 0.5f, entity->s.origin);
    }
    return qtrue;
}

void DK_CheckMultiplayer(void) {
    int team;
    if (!DK_ObjectiveMode()) return;
    for (team = TEAM_RED; team <= TEAM_BLUE; ++team) {
        gentity_t *spawn = G_Find(NULL, FOFS(classname), team == TEAM_RED ? "info_player_team1" : "info_player_team2");
        if (!objectives[team - TEAM_RED].entity || !spawn)
            G_Error("dk3: map lacks %s objective or team spawn", TeamName(team));
    }
}

gentity_t *DK_TeamSpawn(int team, vec3_t origin, vec3_t angles) {
    gentity_t *spot = NULL, *chosen = NULL, *fallback = NULL;
    int count = 0;
    if (team != TEAM_RED && team != TEAM_BLUE) return NULL;
    while ((spot = G_Find(spot, FOFS(classname), team == TEAM_RED ? "info_player_team1" : "info_player_team2"))) {
        if (!fallback) fallback = spot;
        if (!SpotWouldTelefrag(spot) && rand() % ++count == 0) chosen = spot;
    }
    if (!chosen) chosen = fallback;
    if (chosen) { VectorCopy(chosen->s.origin, origin); origin[2] += 9; VectorCopy(chosen->s.angles, angles); }
    return chosen;
}

void DK_RunMultiplayer(void) {
    int i;
    if (!DK_ObjectiveMode()) return;
    for (i = 0; i < 2; ++i) {
        objective_t *objective = &objectives[i];
        gentity_t *entity = DK_FindEntity(objective->entity), *carrier = DK_FindEntity(objective->carrier);
        if (!entity) continue;
        if (objective->state == OBJ_CARRIED) {
            if (!Player(carrier)) { if (carrier) DK_DropObjective(carrier); else Reset(objective); continue; }
            {
                vec3_t origin, forward;
                AngleVectors(carrier->client->ps.viewangles, forward, NULL, NULL);
                VectorMA(carrier->r.currentOrigin, -14, forward, origin); origin[2] += 12;
                Place(objective, origin, qtrue, qfalse);
            }
        }
        if (g_gametype.integer == GT_DK3_DEATHTAG && objective->state == OBJ_CARRIED && carrier) {
            int left = objective->deadline - level.time;
            if (left <= 10000 && !objective->warned) {
                trap_SendServerCommand(carrier->s.number, "cp \"Bomb timer: ten seconds remaining!\"");
                objective->warned = 1;
            }
            if (left <= 10000 && level.time >= objective->nextHeartbeat) {
                G_Sound(carrier, CHAN_ITEM, DK_SoundIndex("artifacts/goldensoulwait.wav"));
                objective->nextHeartbeat = objective->nextBeep = level.time + 1000;
            }
            if (left <= 0) trap_SendServerCommand(carrier->s.number, "cp \"Bomb timer expired!\"");
        }
        if (objective->deadline && level.time >= objective->deadline) {
            if (g_gametype.integer == GT_CTF || objective->state == OBJ_RESETTING) Reset(objective);
            else Explode(objective);
        } else if (g_gametype.integer == GT_DK3_DEATHTAG && objective->deadline > 0 &&
                   objective->deadline - level.time <= 10000 && objective->state != OBJ_RESETTING && level.time >= objective->nextBeep) {
            Sound(entity, "sounds/global/a_ames.wav"); objective->nextBeep = level.time + 1000;
        }
    }
}

gentity_t *DK_ObjectiveGoal(gentity_t *player) {
    int i, team = player->client->sess.sessionTeam;
    objective_t *objective;
    gentity_t *goal = NULL, *zone = NULL;
    float distance = 1e30f;
    if (!DK_ObjectiveMode() || team < TEAM_RED || team > TEAM_BLUE) return NULL;
    if (player->client->ps.dk3Objective) {
        if (g_gametype.integer == GT_CTF && objectives[team - TEAM_RED].state != OBJ_HOME) {
            objective = &objectives[team - TEAM_RED];
            return DK_FindEntity(objective->carrier ? objective->carrier : objective->entity);
        }
        while ((zone = G_Find(zone, FOFS(classname), "trigger_capture"))) {
            float candidate;
            if (((zone->spawnflags & 3) == 1 && team != TEAM_RED) || ((zone->spawnflags & 3) == 2 && team != TEAM_BLUE)) continue;
            candidate = Distance(player->r.currentOrigin, zone->s.origin);
            if (candidate < distance) { goal = zone; distance = candidate; }
        }
        return goal;
    }
    i = g_gametype.integer == GT_CTF ? OtherTeam(team) - TEAM_RED : team - TEAM_RED;
    objective = &objectives[i];
    if (objective->state == OBJ_CARRIED) return DK_FindEntity(objective->carrier);
    if (objective->state == OBJ_HOME || objective->state == OBJ_DROPPED) return DK_FindEntity(objective->entity);
    return NULL;
}

qboolean DK_ObjectiveProtects(gentity_t *player, int mod) {
    return g_gametype.integer == GT_DK3_DEATHTAG && player->client && player->client->ps.dk3Objective &&
        (mod == MOD_WATER || mod == MOD_SLIME || mod == MOD_LAVA || mod == MOD_FALLING);
}
