/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native bot decisions drive normal ioquake3 client commands and AAS routing. */
#include "g_local.h"
#include "dk_weapons.h"
#include "../botlib/botlib.h"
#include "../botlib/be_aas.h"
#include "../botlib/aasfile.h"
#include "../botlib/be_ai_goal.h"
#include "../botlib/be_ai_move.h"

typedef struct {
    unsigned int control, obstacle;
    int until;
    vec3_t origin;
} dkBotControl_t;

typedef struct {
    qboolean active;
    float skill;
    int goal, nextDecision, stuckSince, nextUse, nextReport, controlCount;
    int movement, lastMoveTime, teleportBit, routeArea;
    unsigned int teleportDetour;
    int detourUntil;
    qboolean routeFailed;
    qboolean avoidRight;
    vec3_t progressOrigin, recoveryDirection;
    int recoveryUntil, yieldUntil;
    unsigned int yieldFor;
    unsigned int progressGoal;
    dkBotControl_t controls[8];
    unsigned int random;
    /* Combat memory: the last seen opponent, who last hurt us, and the
       sampled aim error/strafe side that keep aiming and dodging human-like. */
    int enemy, enemySeen, enemyAcquired, hurtBy, hurtTime, lastHealth;
    int weapon, weaponUntil, aimUntil, aimTime, strafeUntil;
    float aimYaw, aimPitch;
    qboolean strafeRight;
} dkBot_t;
static dkBot_t bots[MAX_CLIENTS];
static int lastLibraryTime, populationTime;

void DK_InitBots(qboolean restart) {
    if (!restart) memset(bots, 0, sizeof(bots));
    lastLibraryTime = 0;
    /* Map startup runs frames before carried clients reconnect. Let that finish
       before counting slots, or the population controller creates duplicates. */
    populationTime = level.time + 1000;
    trap_Cvar_Register(NULL, "bot_minplayers", "0", CVAR_SERVERINFO);
}

qboolean DK_ConnectBot(int client) {
    char userinfo[MAX_INFO_STRING];
    dkBot_t *bot;
    if (client < 0 || client >= level.maxclients) return qfalse;
    bot = &bots[client];
    if (bot->movement) trap_BotFreeMoveState(bot->movement);
    memset(bot, 0, sizeof(*bot));
    trap_GetUserinfo(client, userinfo, sizeof(userinfo));
    bot->skill = Com_Clamp(1, 5, atof(Info_ValueForKey(userinfo, "skill")));
    bot->movement = trap_BotAllocMoveState();
    if (!bot->movement) return qfalse;
    bot->active = qtrue; bot->goal = -1; bot->enemy = bot->hurtBy = -1;
    bot->random = (client + 1) * 747796405u;
    return qtrue;
}

void DK_DisconnectBot(int client) {
    if (client >= 0 && client < MAX_CLIENTS) {
        if (bots[client].movement) trap_BotFreeMoveState(bots[client].movement);
        memset(&bots[client], 0, sizeof(bots[client]));
    }
}

static void AddBot(const char *name, float skill, const char *team) {
    char userinfo[MAX_INFO_STRING] = "";
    const char *error;
    int client;
    if (g_gametype.integer == GT_SINGLE_PLAYER) { G_Printf("dk3: multiplayer bots require a multiplayer game mode\n"); return; }
    client = trap_BotAllocateClient();
    if (client < 0) { G_Printf("dk3: no free client slot for a bot\n"); return; }
    Info_SetValueForKey(userinfo, "name", name);
    Info_SetValueForKey(userinfo, "rate", "25000");
    Info_SetValueForKey(userinfo, "snaps", "20");
    Info_SetValueForKey(userinfo, "skill", va("%.2f", Com_Clamp(1, 5, skill)));
    Info_SetValueForKey(userinfo, "model", "hiro");
    Info_SetValueForKey(userinfo, "teampref", *team ? team : "auto");
    Info_SetValueForKey(userinfo, "ip", "localhost");
    trap_SetUserinfo(client, userinfo);
    error = ClientConnect(client, qtrue, qtrue);
    if (error) { G_Printf("dk3: bot join refused: %s\n", error); trap_BotFreeClient(client); return; }
    ClientBegin(client);
}

void DK_AddBotCommand(void) {
    char name[64], skill[16], team[16];
    trap_Argv(1, name, sizeof(name)); trap_Argv(2, skill, sizeof(skill)); trap_Argv(3, team, sizeof(team));
    AddBot(*name ? name : "dk3 bot", *skill ? atof(skill) : 3, team);
}

static float Random(dkBot_t *bot) {
    bot->random ^= bot->random << 13; bot->random ^= bot->random >> 17; bot->random ^= bot->random << 5;
    return (bot->random & 65535) / 65535.0f;
}

static qboolean Visible(gentity_t *self, gentity_t *other) {
    vec3_t start, end;
    trace_t trace;
    VectorCopy(self->client->ps.origin, start); start[2] += self->client->ps.viewheight;
    if (other->r.bmodel) { VectorAdd(other->r.absmin, other->r.absmax, end); VectorScale(end, 0.5f, end); }
    else VectorCopy(other->r.currentOrigin, end);
    end[2] += other->client ? other->client->ps.viewheight * 0.7f : 0;
    trap_Trace(&trace, start, NULL, NULL, end, self->s.number, MASK_SHOT);
    return trace.fraction == 1 || trace.entityNum == other->s.number;
}

static qboolean Hostile(gentity_t *self, gentity_t *other) {
    return other != self && other->inuse && other->client && other->health > 0 &&
        other->client->sess.sessionTeam != TEAM_SPECTATOR && !OnSameTeam(self, other);
}

/* New opponents must be inside the view cone; the current opponent, a recent
   attacker and anyone close enough to be heard are tracked all around. */
static gentity_t *Enemy(gentity_t *self, dkBot_t *bot, int time) {
    gentity_t *best = NULL;
    float bestScore = 1e30f;
    vec3_t forward;
    int i;
    AngleVectors(self->client->ps.viewangles, forward, NULL, NULL);
    for (i = 0; i < level.maxclients; ++i) {
        gentity_t *other = &g_entities[i];
        vec3_t delta;
        float distance, score;
        qboolean current = i == bot->enemy && bot->enemySeen && time - bot->enemySeen < 1500;
        qboolean attacker = i == bot->hurtBy && bot->hurtTime && time - bot->hurtTime < 2000;
        if (!Hostile(self, other)) continue;
        VectorSubtract(other->r.currentOrigin, self->r.currentOrigin, delta);
        distance = VectorNormalize(delta);
        if (distance > 3000) continue;
        if (!current && !attacker && distance > 256 && DotProduct(forward, delta) < 0.35f) continue;
        if (!Visible(self, other)) continue;
        score = distance * (current ? 0.6f : 1) * (attacker ? 0.7f : 1) * (other->client->ps.dk3Objective ? 0.5f : 1);
        if (score < bestScore) { best = other; bestScore = score; }
    }
    if (best) {
        if (best->s.number != bot->enemy || !bot->enemySeen || time - bot->enemySeen > 1500) bot->enemyAcquired = time;
        bot->enemy = best->s.number; bot->enemySeen = time;
    } else if (!bot->enemySeen || time - bot->enemySeen > 1500) {
        /* Gunfire is audible through walls; remember the shooter as a chase
           target without granting sight of it. */
        float nearest = 1200;
        for (i = 0; i < level.maxclients; ++i) {
            gentity_t *other = &g_entities[i];
            float distance;
            if (!Hostile(self, other) || other->client->ps.weaponstate != WEAPON_FIRING) continue;
            distance = Distance(self->r.currentOrigin, other->r.currentOrigin);
            if (distance < nearest) {
                nearest = distance; bot->enemy = i;
                bot->enemySeen = time - 1500; bot->enemyAcquired = time;
            }
        }
    }
    return best;
}

static int GoalArea(gentity_t *self, gentity_t *target, vec3_t point);
static int TravelFlags(gentity_t *self);

static qboolean CanReturnFrom(gentity_t *self, int area, vec3_t point) {
    int from = trap_BotReachabilityArea(self->r.currentOrigin, self->s.number);
    return area && from && (area == from ||
        trap_AAS_AreaTravelTimeToGoalArea(area, point, from, TravelFlags(self)) > 0);
}

static gentity_t *Goal(gentity_t *self, dkBot_t *bot) {
    gentity_t *best = NULL;
    float bestScore = 0;
    int i;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *item = &g_entities[i];
        float benefit = 0, distance;
        int weapon;
        if (!item->inuse || !(item->r.contents & CONTENTS_TRIGGER) || item->s.eType != ET_DK3_ITEM) continue;
        weapon = DK_WeaponId(item->classname);
        if (weapon) benefit = DK_HasWeapon(&self->client->ps, weapon) ? 40 : 400;
        else if (!strncmp(item->classname, "item_health", 11) && self->health < self->client->ps.stats[STAT_MAX_HEALTH])
            benefit = 600 - self->health * 4;
        else if (strstr(item->classname, "armor") && self->client->ps.stats[STAT_ARMOR] < 100) benefit = 200;
        else if (!strncmp(item->classname, "ammo_", 5)) benefit = 60;
        if (benefit <= 0) continue;
        distance = Distance(self->r.currentOrigin, item->r.currentOrigin);
        /* Keep the current pickup unless another is clearly better, and spread
           bots over items instead of herding every one onto the same pickup. */
        if (i == bot->goal) benefit *= 1.5f;
        else {
            int other, claims = 0;
            for (other = 0; other < level.maxclients; ++other)
                if (other != self->s.number && bots[other].active && bots[other].goal == i) ++claims;
            benefit /= 1 + 0.75f * claims;
        }
        if (benefit / (distance + 100) > bestScore) {
            vec3_t approach;
            if (!CanReturnFrom(self, GoalArea(self, item, approach), approach)) continue;
            best = item; bestScore = benefit / (distance + 100);
        }
    }
    if (!best) {
        int start = MAX_CLIENTS + (int)(Random(bot) * (level.num_entities - MAX_CLIENTS));
        for (i = 0; i < level.num_entities - MAX_CLIENTS; ++i) {
            gentity_t *spot = &g_entities[MAX_CLIENTS + (start - MAX_CLIENTS + i) % (level.num_entities - MAX_CLIENTS)];
            if (spot->inuse && spot->classname && !strcmp(spot->classname, "info_player_deathmatch")) {
                vec3_t approach;
                if (CanReturnFrom(self, GoalArea(self, spot, approach), approach)) { best = spot; break; }
            }
        }
    }
    return best;
}

/* Every switch costs a drop and a raise, so keep the held weapon briefly and
   only change for a clearly better choice. */
static int Weapon(gentity_t *self, dkBot_t *bot, float distance, int time) {
    int i, selected = 0;
    float best = -1, current = DK_BotWeaponScore(self, bot->weapon, distance);
    if (current > 0 && time < bot->weaponUntil) return bot->weapon;
    for (i = 1; i < DK_WEAPON_COUNT; ++i) {
        float score = DK_BotWeaponScore(self, i, distance);
        if (score > best) { selected = i; best = score; }
    }
    if (current > 0 && best < current * 1.3f) selected = bot->weapon;
    if (selected != bot->weapon) bot->weaponUntil = time + 1500;
    bot->weapon = selected;
    return selected;
}

/* Aim with skill-scaled lead, sampled error and a limited turn rate. Returns
   the remaining angular error so firing can wait until the sight is on. */
static float Aim(gentity_t *self, dkBot_t *bot, gentity_t *enemy, int weapon, int time, vec3_t angles) {
    const dkWeaponInfo_t *info = &dk_weapons[weapon];
    vec3_t eye, target, delta;
    float dt = bot->aimTime ? Com_Clamp(0.01f, 0.1f, (time - bot->aimTime) * 0.001f) : 0.05f;
    float turn = (180 + 108 * bot->skill) * dt, error = 0, spread;
    int i;
    bot->aimTime = time;
    VectorCopy(self->client->ps.origin, eye); eye[2] += self->client->ps.viewheight;
    VectorCopy(enemy->r.currentOrigin, target); target[2] += enemy->client->ps.viewheight * 0.7f;
    if (weapon && info->speed > 0) {
        float flight = Distance(eye, target) / info->speed, lead = 0.3f + 0.14f * bot->skill;
        vec3_t velocity;
        VectorCopy(enemy->client->ps.velocity, velocity);
        if (enemy->client->ps.groundEntityNum != ENTITYNUM_NONE) velocity[2] = 0;
        VectorMA(target, flight * lead, velocity, target);
        if (DK_WeaponSplash(weapon) && enemy->client->ps.groundEntityNum != ENTITYNUM_NONE) {
            trace_t trace;
            vec3_t feet;
            VectorCopy(target, feet); feet[2] = enemy->r.currentOrigin[2] + enemy->r.mins[2] + 8;
            trap_Trace(&trace, eye, NULL, NULL, feet, self->s.number, MASK_SHOT);
            if (trace.fraction == 1 || trace.entityNum == enemy->s.number) VectorCopy(feet, target);
        }
    }
    if (time >= bot->aimUntil) {
        spread = (5.5f - bot->skill) * 1.0f;
        bot->aimYaw = (Random(bot) * 2 - 1) * spread;
        bot->aimPitch = (Random(bot) * 2 - 1) * spread * 0.5f;
        bot->aimUntil = time + 300 + (int)(Random(bot) * 400);
    }
    VectorSubtract(target, eye, delta);
    vectoangles(delta, angles);
    angles[YAW] += bot->aimYaw; angles[PITCH] += bot->aimPitch;
    for (i = 0; i < 2; ++i) {
        float difference = AngleSubtract(angles[i], self->client->ps.viewangles[i]);
        if (fabs(difference) - turn > error) error = fabs(difference) - turn;
        angles[i] = self->client->ps.viewangles[i] + Com_Clamp(-turn, turn, difference);
    }
    return error;
}

static void GoalOrigin(gentity_t *goal, vec3_t origin) {
    if (goal->r.bmodel) { VectorAdd(goal->r.absmin, goal->r.absmax, origin); VectorScale(origin, 0.5f, origin); }
    else VectorCopy(goal->r.currentOrigin, origin);
}

static qboolean UseNearby(gentity_t *self, dkBot_t *bot, gentity_t *target, int time) {
    vec3_t eye, point, direction;
    trace_t trace;
    if (!DK_CanUse(target) || time < bot->nextUse ||
        (target->dk.key && !DK_HasKey(self, target->dk.key)) ||
        (!strcmp(target->classname, "func_button") && target->moverState != MOVER_POS1)) return qfalse;
    VectorCopy(self->client->ps.origin, eye); eye[2] += self->client->ps.viewheight;
    /* Use the same 96-unit sight ray as the player's Use command. Large doors
       can be within reach even when their center is far from the player. */
    GoalOrigin(target, point);
    VectorSubtract(point, eye, direction);
    if (!VectorNormalize(direction)) return qfalse;
    VectorMA(eye, 96, direction, point);
    trap_Trace(&trace, eye, NULL, NULL, point, self->s.number, MASK_SHOT);
    if (trace.entityNum != target->s.number) return qfalse;
    target->use(target, self, self); bot->nextUse = time + 1000;
    return qtrue;
}


static qboolean Targets(gentity_t *source, gentity_t *destination) {
    int i;
    if (!destination->targetname) return qfalse;
    if (source->target && !strcmp(source->target, destination->targetname)) return qtrue;
    for (i = 0; i < 3; ++i) if (source->dk.targets[i] && !strcmp(source->dk.targets[i], destination->targetname)) return qtrue;
    return qfalse;
}

/* Search authored target edges backwards. Only physical switches become goals;
   relay/counter nodes are never activated remotely to bypass a puzzle. */
static gentity_t *ControlFor(gentity_t *self, gentity_t *obstacle) {
    int queue[MAX_GENTITIES], first = 0, count = 1, i;
    qboolean seen[MAX_GENTITIES];
    gentity_t *best = NULL;
    float nearest = 1e30f;
    memset(seen, 0, sizeof(seen));
    queue[0] = obstacle->s.number; seen[queue[0]] = qtrue;
    while (first < count) {
        gentity_t *destination = &g_entities[queue[first++]];
        for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
            gentity_t *source = &g_entities[i];
            vec3_t point;
            float distance;
            if (seen[i] || !source->inuse || !Targets(source, destination)) continue;
            seen[i] = qtrue;
            if (source->r.linked && source->r.bmodel && (source->touch || source->use) &&
                (!strcmp(source->classname, "func_button") || !strcmp(source->classname, "trigger_multiple") ||
                 !strcmp(source->classname, "trigger_once") || !strcmp(source->classname, "trigger_push"))) {
                if (source->dk.key && !DK_HasKey(self, source->dk.key)) continue;
                GoalOrigin(source, point); distance = Distance(self->r.currentOrigin, point);
                if (distance < nearest) { nearest = distance; best = source; }
            } else if (count < MAX_GENTITIES && (!strcmp(source->classname, "trigger_relay") ||
                       !strcmp(source->classname, "trigger_counter") || !strcmp(source->classname, "func_event_generator")))
                queue[count++] = i;
        }
    }
    return best;
}

static void PushControl(gentity_t *self, dkBot_t *bot, gentity_t *control, gentity_t *obstacle, int time) {
    dkBotControl_t *task;
    int i;
    for (i = 0; i < bot->controlCount; ++i) if (bot->controls[i].control == control->dk.id) return;
    if (bot->controlCount == ARRAY_LEN(bot->controls)) return;
    task = &bot->controls[bot->controlCount++];
    task->control = control->dk.id; task->obstacle = obstacle->dk.id; task->until = time + 15000;
    VectorCopy(self->r.currentOrigin, task->origin);
    if (trap_Cvar_VariableIntegerValue("bot_report"))
        G_Printf("dk3 bot %d control push %u (%s) for %u (%s), depth %d\n", self->s.number,
            control->dk.id, control->classname, obstacle->dk.id, obstacle->classname, bot->controlCount);
}

static void RequestControl(gentity_t *self, dkBot_t *bot, gentity_t *control, gentity_t *obstacle, int time) {
    gentity_t *helper = NULL;
    vec3_t point;
    float nearest = 1e30f;
    int i, task;
    /* Remote timed gates need a teammate at the switch while the requester
       approaches the opening. Nested controls stay with the assigned operator. */
    GoalOrigin(control, point);
    for (i = 0; i < level.maxclients; ++i) {
        gentity_t *other = &g_entities[i];
        float distance;
        if (!bots[i].active || !other->inuse || other->health <= 0 || !OnSameTeam(self, other)) continue;
        for (task = 0; task < bots[i].controlCount; ++task)
            if (bots[i].controls[task].control == control->dk.id) return;
        if (bot->controlCount || Distance(self->r.currentOrigin, point) < 192 ||
            other == self || bots[i].controlCount || other->client->ps.dk3Objective) continue;
        distance = Distance(other->r.currentOrigin, point);
        if (distance < nearest) { nearest = distance; helper = other; }
    }
    if (helper) {
        if (trap_Cvar_VariableIntegerValue("bot_report"))
            G_Printf("dk3 bot %d requests switch %u from teammate %d\n", self->s.number, control->dk.id, helper->s.number);
        PushControl(helper, &bots[helper->s.number], control, obstacle, time);
    } else PushControl(self, bot, control, obstacle, time);
}

static gentity_t *CourseGoal(gentity_t *self, dkBot_t *bot, gentity_t *goal, int time) {
    gentity_t *control, *obstacle;
    while (bot->controlCount) {
        dkBotControl_t *task = &bot->controls[bot->controlCount - 1];
        control = DK_FindEntity(task->control); obstacle = DK_FindEntity(task->obstacle);
        if (control && obstacle && obstacle->moverState == MOVER_POS1 && control->r.linked) {
            if (Distance(self->r.currentOrigin, task->origin) >= 64) {
                task->until = time + 15000;
                VectorCopy(self->r.currentOrigin, task->origin);
            }
            if (time < task->until) return control;
        }
        if (trap_Cvar_VariableIntegerValue("bot_report"))
            G_Printf("dk3 bot %d control pop %u, depth %d (%s)\n", self->s.number, task->control,
                bot->controlCount, time >= task->until ? "stalled" : "obstacle changed");
        --bot->controlCount;
    }
    if (goal && bot->stuckSince && time - bot->stuckSince > 400) {
        vec3_t direction, point, end;
        trace_t trace;
        GoalOrigin(goal, point); VectorSubtract(point, self->r.currentOrigin, direction); VectorNormalize(direction);
        VectorMA(self->r.currentOrigin, 96, direction, end);
        trap_Trace(&trace, self->r.currentOrigin, self->r.mins, self->r.maxs, end, self->s.number, MASK_PLAYERSOLID);
        if (trace.entityNum < ENTITYNUM_WORLD && g_entities[trace.entityNum].s.eType == ET_MOVER) {
            obstacle = &g_entities[trace.entityNum];
            control = ControlFor(self, obstacle);
            if (control) {
                RequestControl(self, bot, control, obstacle, time);
                if (bot->controlCount) return DK_FindEntity(bot->controls[bot->controlCount - 1].control);
                return goal;
            }
            if (!obstacle->targetname) UseNearby(self, bot, obstacle, time);
        }
    }
    return goal;
}

static gentity_t *TeamGoal(gentity_t *self, gentity_t *objective) {
    int i, role = self->s.number % 3;
    if (!DK_ObjectiveMode() || self->client->ps.dk3Objective) return objective;
    if (role == 1) for (i = 0; i < level.maxclients; ++i) {
        gentity_t *carrier = &g_entities[i];
        if (carrier->inuse && carrier->client && carrier != self && carrier->health > 0 &&
            carrier->client->ps.dk3Objective && OnSameTeam(self, carrier)) return carrier;
    }
    if (g_gametype.integer == GT_CTF && role == 0) {
        int home = self->client->sess.sessionTeam - TEAM_RED + 1;
        for (i = 0; i < level.maxclients; ++i) {
            gentity_t *thief = &g_entities[i];
            if (thief->inuse && thief->client && thief->health > 0 && !OnSameTeam(self, thief) && thief->client->ps.dk3Objective == home)
                return thief;
        }
    }
    return objective;
}

/* Brush origins can be inside a wall or below the standing player hull. Find
   an actual nearby standing position from which the goal can be touched/used. */
static int TravelFlags(gentity_t *self) {
    return TFL_DEFAULT | (g_gametype.integer == GT_DK3_DEATHTAG && self->client->ps.dk3Objective ? TFL_LAVA | TFL_SLIME : 0);
}

static int GoalArea(gentity_t *self, gentity_t *target, vec3_t point) {
    vec3_t center, candidate, eye, nearest;
    trace_t trace;
    int from, area, cost, best = 0, bestCost = 0x7fffffff, side, height, axis;
    GoalOrigin(target, center);
    from = trap_BotReachabilityArea(self->r.currentOrigin, self->s.number);
    if (!from) return 0;
    for (side = -1; side < 4; ++side) for (height = 0; height < 3; ++height) {
        VectorCopy(center, candidate);
        candidate[2] += height == 1 ? 24 : height == 2 ? -24 : 0;
        if (side >= 0) {
            float clearance = target->r.bmodel ? 20 : 12;
            candidate[side / 2] = side & 1 ? target->r.absmax[side / 2] + clearance : target->r.absmin[side / 2] - clearance;
        }
        /* The goal point must actually lie in its selected area. Fuzzy area
           lookup can name a nearby platform while leaving the point over a
           pit; BotMoveInGoalArea then walks straight off that platform. */
        area = trap_AAS_PointAreaNum(candidate);
        if (!area || !trap_AAS_AreaReachability(area)) continue;
        cost = area == from ? 1 : trap_AAS_AreaTravelTimeToGoalArea(from, self->r.currentOrigin, area, TravelFlags(self));
        if (!cost) continue;
        trap_Trace(&trace, candidate, self->r.mins, self->r.maxs, candidate, self->s.number, MASK_SOLID);
        if ((trace.startsolid || trace.allsolid) &&
            (trace.entityNum >= ENTITYNUM_WORLD || g_entities[trace.entityNum].s.eType != ET_MOVER)) continue;
        VectorCopy(candidate, eye); eye[2] += self->client->ps.viewheight;
        for (axis = 0; axis < 3; ++axis) nearest[axis] = Com_Clamp(target->r.absmin[axis], target->r.absmax[axis], eye[axis]);
        trap_Trace(&trace, eye, NULL, NULL, nearest, self->s.number, MASK_SOLID);
        if (trace.fraction < 1 && trace.entityNum != target->s.number &&
            (trace.entityNum >= ENTITYNUM_WORLD || g_entities[trace.entityNum].s.eType != ET_MOVER)) continue;
        cost += Distance(candidate, center);
        if (cost < bestCost) { bestCost = cost; best = area; VectorCopy(candidate, point); }
    }
    return best;
}

static float InitMove(gentity_t *self, dkBot_t *bot, int time) {
    bot_initmove_t move;
    memset(&move, 0, sizeof(move));
    VectorCopy(self->client->ps.origin, move.origin);
    VectorCopy(self->client->ps.velocity, move.velocity);
    VectorCopy(self->client->ps.viewangles, move.viewangles);
    move.viewoffset[2] = self->client->ps.viewheight;
    move.client = move.entitynum = self->s.number;
    move.thinktime = bot->lastMoveTime ? Com_Clamp(0.01f, 0.2f, (time - bot->lastMoveTime) * 0.001f) : 0.05f;
    move.presencetype = self->client->ps.pm_flags & PMF_DUCKED ? PRESENCE_CROUCH : PRESENCE_NORMAL;
    if (self->client->ps.groundEntityNum != ENTITYNUM_NONE) move.or_moveflags |= MFL_ONGROUND;
    if (self->client->ps.pm_flags & PMF_TIME_WATERJUMP) move.or_moveflags |= MFL_WATERJUMP;
    if ((self->client->ps.eFlags & EF_TELEPORT_BIT) != bot->teleportBit) move.or_moveflags |= MFL_TELEPORTED;
    bot->teleportBit = self->client->ps.eFlags & EF_TELEPORT_BIT;
    bot->lastMoveTime = time;
    trap_EA_ResetInput(self->s.number);
    trap_BotInitMoveState(bot->movement, &move);
    return move.thinktime;
}

static qboolean Navigate(gentity_t *self, dkBot_t *bot, gentity_t *target, int time,
                         bot_input_t *input, bot_moveresult_t *result) {
    bot_goal_t goal;
    float thinktime;
    if (!trap_AAS_Initialized()) return qfalse;
    memset(&goal, 0, sizeof(goal));
    thinktime = InitMove(self, bot, time);
    goal.areanum = GoalArea(self, target, goal.origin);
    bot->routeArea = goal.areanum;
    if (!goal.areanum) return qfalse;
    /* Keep the collision-checked approach in its area. Item approaches overlap
       the trigger with the player hull; replacing this point by an unchecked
       item origin can undo the route's safe final approach. */
    goal.entitynum = target->s.number; goal.number = target->s.number;
    VectorSubtract(target->r.absmin, goal.origin, goal.mins);
    VectorSubtract(target->r.absmax, goal.origin, goal.maxs);
    trap_BotMoveToGoal(result, bot->movement, &goal, TravelFlags(self));
    trap_EA_GetInput(self->s.number, thinktime, input);
    /* Botlib can return without a reachability while airborne, with neither
       failure nor movement. Keep ordinary local steering in that case; only
       an explicit mover wait should suppress input indefinitely. */
    return !result->failure && (input->speed > 0 || input->actionflags || result->blocked ||
        result->traveltype || (result->flags & MOVERESULT_WAITING));
}

/* Unrouted motion must obey botlib's ledge/hazard prediction too. Steering
   straight at an unreachable pickup walked bots into an AAS region with no
   return path on e1dt1. Retain a safe local direction briefly to avoid wobbling. */
static qboolean RecoveryHazard(gentity_t *self, const vec3_t origin) {
    vec3_t mins, maxs;
    int entities[MAX_GENTITIES], count, i;
    if (trap_PointContents(origin, self->s.number) & (CONTENTS_LAVA | CONTENTS_SLIME)) return qtrue;
    VectorAdd(origin, self->r.mins, mins); VectorAdd(origin, self->r.maxs, maxs);
    count = trap_EntitiesInBox(mins, maxs, entities, ARRAY_LEN(entities));
    for (i = 0; i < count; ++i) {
        gentity_t *touch = &g_entities[entities[i]];
        if (touch->inuse && touch->r.linked && (touch->r.contents & CONTENTS_TRIGGER) &&
            touch->classname && !strcmp(touch->classname, "trigger_hurt") && DK_TriggerContact(mins, maxs, touch)) return qtrue;
    }
    return qfalse;
}

static qboolean GroundedStep(gentity_t *self, const vec3_t point,
                            const vec3_t direction, vec3_t landing) {
    vec3_t raised, end, floor;
    trace_t trace;
    int rise;
    /* Try the ordinary slide before the step-up, as player movement does.
       Requiring overhead clearance for every flat step traps a bot when
       a teammate stands on its head or the passage has a low ceiling. */
    for (rise = 0; rise <= 18; rise += 18) {
        VectorCopy(point, raised); raised[2] += rise;
        if (rise) {
            trap_Trace(&trace, point, self->r.mins, self->r.maxs, raised, self->s.number, MASK_PLAYERSOLID);
            if (trace.startsolid || trace.fraction < 1) continue;
        }
        VectorMA(raised, 16, direction, end);
        trap_Trace(&trace, raised, self->r.mins, self->r.maxs, end, self->s.number, MASK_PLAYERSOLID);
        if (trace.startsolid || trace.fraction < 1) continue;
        VectorCopy(end, floor); floor[2] -= rise + 18;
        trap_Trace(&trace, end, self->r.mins, self->r.maxs, floor, self->s.number, MASK_PLAYERSOLID);
        if (trace.startsolid || trace.fraction == 1 || trace.plane.normal[2] < 0.7f) continue;
        VectorCopy(trace.endpos, landing); landing[2] += 0.125f;
        if (!RecoveryHazard(self, landing)) return qtrue;
    }
    return qfalse;
}

/* AAS can exclude physically walkable floor near bevels and moving brushes.
   Its predictor can also reject every direction while two players obstruct
   each other. Validate a short, fully supported hull path to a real area;
   normal user commands still perform the movement. */
static qboolean GroundedRecovery(gentity_t *self, const vec3_t toward,
                                 qboolean allowRouted, bot_input_t *input) {
    static const float offsets[] = {0, 45, -45, 90, -90, 135, -135, 180};
    vec3_t point, landing, direction, best;
    float yaw = vectoyaw(toward), bestDistance = 129;
    int side, step, from = trap_AAS_PointAreaNum(self->r.currentOrigin);
    if ((!allowRouted && from) || self->waterlevel > 1 ||
        self->client->ps.groundEntityNum == ENTITYNUM_NONE) return qfalse;
    for (side = 0; side < ARRAY_LEN(offsets); ++side) {
        float angle = (yaw + offsets[side]) * M_PI / 180.0f;
        VectorSet(direction, cos(angle), sin(angle), 0);
        VectorCopy(self->r.currentOrigin, point);
        for (step = 1; step <= 8 && step * 16 < bestDistance; ++step) {
            int area;
            if (!GroundedStep(self, point, direction, landing)) break;
            VectorCopy(landing, point);
            area = trap_AAS_PointAreaNum(point);
            if (area && trap_AAS_AreaReachability(area) && (!allowRouted || step >= 3) &&
                (!from || area == from ||
                 (trap_AAS_AreaTravelTimeToGoalArea(from, self->r.currentOrigin, area, TravelFlags(self)) &&
                  trap_AAS_AreaTravelTimeToGoalArea(area, point, from, TravelFlags(self))))) {
                bestDistance = step * 16; VectorCopy(direction, best);
                break;
            }
        }
    }
    if (bestDistance > 128) return qfalse;
    memset(input, 0, sizeof(*input));
    VectorCopy(best, input->dir); input->speed = 120;
    return qtrue;
}

static qboolean LocalMove(gentity_t *self, dkBot_t *bot, const vec3_t toward,
                          int time, bot_input_t *input) {
    static const float offsets[] = {0, 45, -45, 90, -90, 135, -135, 180};
    vec3_t direction;
    float yaw = vectoyaw(toward);
    int attempt;
    if (self->client->ps.groundEntityNum == ENTITYNUM_NONE && self->waterlevel < 2) return qfalse;
    if (GroundedRecovery(self, toward, qfalse, input)) return qtrue;
    for (attempt = -1; attempt < ARRAY_LEN(offsets); ++attempt) {
        trap_EA_ResetInput(self->s.number);
        if (attempt < 0) {
            if (time >= bot->recoveryUntil) continue;
            VectorCopy(bot->recoveryDirection, direction);
        } else {
            float angle = (yaw + offsets[attempt] * (bot->avoidRight ? -1 : 1)) * M_PI / 180.0f;
            VectorSet(direction, cos(angle), sin(angle), 0);
        }
        if (trap_BotMoveInDirection(bot->movement, direction, 240, MOVE_WALK)) {
            trap_EA_GetInput(self->s.number, 0.05f, input);
            if (!input->speed && !input->actionflags) continue;
            VectorCopy(direction, bot->recoveryDirection);
            if (attempt >= 0) bot->recoveryUntil = time + 500;
            return qtrue;
        }
    }
    if (GroundedRecovery(self, toward, qtrue, input)) {
        if (trap_Cvar_VariableIntegerValue("bot_report") > 1 && time >= bot->nextReport)
            G_Printf("dk3 bot %d uses a supported local recovery at %.0f %.0f %.0f\n",
                self->s.number, self->r.currentOrigin[0], self->r.currentOrigin[1], self->r.currentOrigin[2]);
        return qtrue;
    }
    memset(input, 0, sizeof(*input));
    /* Explicitly stand when no safe direction is available. */
    return qtrue;
}

static qboolean LeavePlatform(gentity_t *self, gentity_t *platform, int goalArea, bot_input_t *input) {
    vec3_t edge, bottom, best;
    trace_t trace;
    float bestCost = 1e30f;
    int side;
    if (!goalArea) return qfalse;
    /* AAS omits moving brushes. A short compiled ledge drop can therefore end
       inside a raised lift. Find a real, unobstructed edge and safe landing. */
    for (side = 0; side < 4; ++side) {
        int axis = side / 2, area, cost, contents;
        VectorCopy(self->r.currentOrigin, edge);
        edge[axis] = side & 1 ? platform->r.absmax[axis] - self->r.mins[axis] + 4 :
                               platform->r.absmin[axis] - self->r.maxs[axis] - 4;
        if (Distance(edge, self->r.currentOrigin) > 192) continue;
        trap_Trace(&trace, self->r.currentOrigin, self->r.mins, self->r.maxs, edge, self->s.number, MASK_PLAYERSOLID);
        if (trap_Cvar_VariableIntegerValue("bot_report") > 1 && level.time >= bots[self->s.number].nextReport)
            G_Printf("dk3 bot %d platform edge %d (%.0f %.0f %.0f): horizontal %.3f solid %d entity %d\n",
                self->s.number, side, edge[0], edge[1], edge[2], trace.fraction, trace.startsolid, trace.entityNum);
        if (trace.startsolid || trace.fraction < 1) continue;
        VectorCopy(edge, bottom); bottom[2] -= 128;
        trap_Trace(&trace, edge, self->r.mins, self->r.maxs, bottom, self->s.number, MASK_PLAYERSOLID);
        if (trap_Cvar_VariableIntegerValue("bot_report") > 1 && level.time >= bots[self->s.number].nextReport)
            G_Printf("dk3 bot %d platform edge %d: landing %.3f solid %d entity %d at %.0f %.0f %.0f\n",
                self->s.number, side, trace.fraction, trace.startsolid, trace.entityNum, trace.endpos[0], trace.endpos[1], trace.endpos[2]);
        if (trace.startsolid || trace.fraction == 1 || trace.entityNum == platform->s.number || trace.plane.normal[2] < 0.7f ||
            trace.endpos[2] > self->r.currentOrigin[2] - 24) continue;
        contents = trap_PointContents(trace.endpos, self->s.number);
        if ((contents & (CONTENTS_LAVA | CONTENTS_SLIME)) &&
            !(g_gametype.integer == GT_DK3_DEATHTAG && self->client->ps.dk3Objective)) continue;
        area = trap_BotReachabilityArea(trace.endpos, ENTITYNUM_NONE);
        cost = area == goalArea ? 1 : area ? trap_AAS_AreaTravelTimeToGoalArea(area, trace.endpos, goalArea, TravelFlags(self)) : 0;
        if (trap_Cvar_VariableIntegerValue("bot_report") > 1 && level.time >= bots[self->s.number].nextReport)
            G_Printf("dk3 bot %d platform edge %d: route %d -> %d cost %d\n", self->s.number, side, area, goalArea, cost);
        if (!cost) continue;
        cost += Distance(self->r.currentOrigin, edge);
        if (cost < bestCost) { bestCost = cost; VectorCopy(edge, best); }
    }
    if (bestCost == 1e30f) return qfalse;
    VectorSubtract(best, self->r.currentOrigin, input->dir);
    VectorNormalize(input->dir); input->speed = 200; input->actionflags = 0;
    return qtrue;
}

static qboolean TeleportApproach(gentity_t *self, gentity_t *teleport, vec3_t point, qboolean *jump) {
    vec3_t start, end, sample, floor;
    trace_t trace;
    int i, steps;
    GoalOrigin(teleport, point);
    if (Distance(self->r.currentOrigin, point) > 512 ||
        self->r.currentOrigin[2] + self->r.maxs[2] < teleport->r.absmin[2] ||
        self->r.currentOrigin[2] + self->r.mins[2] > teleport->r.absmax[2]) return qfalse;
    point[2] = self->r.currentOrigin[2];
    trap_Trace(&trace, self->r.currentOrigin, self->r.mins, self->r.maxs, point, self->s.number, MASK_PLAYERSOLID);
    *jump = trace.fraction < 1;
    VectorCopy(self->r.currentOrigin, start); start[2] += 24;
    VectorCopy(point, end); end[2] += 24;
    trap_Trace(&trace, self->r.currentOrigin, self->r.mins, self->r.maxs, start, self->s.number, MASK_PLAYERSOLID);
    if (trace.startsolid || trace.fraction < 1) return qfalse;
    trap_Trace(&trace, start, self->r.mins, self->r.maxs, end, self->s.number, MASK_PLAYERSOLID);
    if (trace.startsolid || trace.fraction < 1) return qfalse;
    steps = (int)(Distance(start, end) / 24) + 1;
    for (i = 1; i <= steps; ++i) {
        VectorSubtract(end, start, sample); VectorMA(start, (float)i / steps, sample, sample);
        VectorCopy(sample, floor); floor[2] -= 72;
        trap_Trace(&trace, sample, self->r.mins, self->r.maxs, floor, self->s.number, MASK_PLAYERSOLID);
        if (trace.startsolid || trace.fraction == 1 || trace.plane.normal[2] < 0.7f) return qfalse;
        if (trap_PointContents(trace.endpos, self->s.number) & (CONTENTS_LAVA | CONTENTS_SLIME)) return qfalse;
    }
    return qtrue;
}

static gentity_t *TeleportDetour(gentity_t *self, gentity_t *goal) {
    gentity_t *best = NULL;
    vec3_t point;
    int i, goalArea = GoalArea(self, goal, point), bestCost = 0x7fffffff;
    if (!goalArea) return NULL;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *teleport = &g_entities[i], *landing;
        int rise, area, cost;
        qboolean jump;
        trace_t trace;
        vec3_t destination;
        if (!teleport->inuse || !teleport->r.linked || !(teleport->r.contents & CONTENTS_TRIGGER) ||
            strcmp(teleport->classname, "trigger_teleport") || !teleport->target || !TeleportApproach(self, teleport, point, &jump)) continue;
        landing = G_Find(NULL, FOFS(targetname), teleport->target);
        if (!landing) continue;
        for (rise = 0; rise <= 64; rise += 4) {
            VectorCopy(landing->r.currentOrigin, destination); destination[2] += 1 + rise;
            trap_Trace(&trace, destination, self->r.mins, self->r.maxs, destination, self->s.number, MASK_PLAYERSOLID);
            if (!trace.startsolid && !trace.allsolid) break;
        }
        if (rise > 64) continue;
        area = trap_BotReachabilityArea(destination, ENTITYNUM_NONE);
        cost = area == goalArea ? 1 : area ? trap_AAS_AreaTravelTimeToGoalArea(area, destination, goalArea, TravelFlags(self)) : 0;
        if (!cost) continue;
        cost += Distance(self->r.currentOrigin, point) * 100 / 320;
        if (cost < bestCost) { bestCost = cost; best = teleport; }
    }
    return best;
}

/* Circle-strafe at a weapon-appropriate distance. Botlib validates each
   direction against ledges and hazards; a refused side flips the strafe. */
static qboolean CombatMove(gentity_t *self, dkBot_t *bot, gentity_t *enemy, int weapon, int time, bot_input_t *input) {
    vec3_t toward, side, direction;
    float distance, approach = 0, strafe = 1;
    int attempt;
    if (!trap_AAS_Initialized() || self->waterlevel > 1) return qfalse;
    VectorSubtract(enemy->r.currentOrigin, self->r.currentOrigin, toward); toward[2] = 0;
    distance = VectorNormalize(toward);
    if (weapon && dk_weapons[weapon].speed <= 0 && DK_BotWeaponRange(weapon) < 256) {
        /* Melee closes straight in, weaving only slightly. */
        approach = distance > DK_BotWeaponRange(weapon) * 0.6f ? 1 : 0;
        strafe = distance > 256 ? 0.35f : 0.6f;
    } else {
        float ideal = DK_WeaponSplash(weapon) ? 480 : 320;
        if (distance > ideal + 160) approach = 0.8f;
        else if (distance < ideal - 120) approach = -0.8f;
    }
    if (time >= bot->strafeUntil) {
        if (Random(bot) < 0.6f) bot->strafeRight = !bot->strafeRight;
        bot->strafeUntil = time + 400 + (int)(Random(bot) * 900);
    }
    InitMove(self, bot, time);
    for (attempt = 0; attempt < 2; ++attempt) {
        VectorSet(side, -toward[1], toward[0], 0);
        if (bot->strafeRight) VectorNegate(side, side);
        VectorScale(side, strafe, side);
        VectorMA(side, approach, toward, direction);
        VectorNormalize(direction);
        trap_EA_ResetInput(self->s.number);
        if (trap_BotMoveInDirection(bot->movement, direction, 400, MOVE_WALK)) {
            trap_EA_GetInput(self->s.number, 0.05f, input);
            if (bot->skill >= 3 && self->client->ps.groundEntityNum != ENTITYNUM_NONE && Random(bot) < 0.004f * bot->skill)
                input->actionflags |= ACTION_JUMP;
            return input->speed > 0 || input->actionflags;
        }
        bot->strafeRight = !bot->strafeRight;
    }
    return qfalse;
}

static void Think(int client, int time) {
    gentity_t *self = &g_entities[client], *enemy, *goal, *objective;
    dkBot_t *bot = &bots[client];
    usercmd_t command;
    bot_input_t input;
    bot_moveresult_t movement;
    vec3_t destination, direction, angles, travel, forward, right;
    int i, weapon;
    float moveScale = 127;
    qboolean routed, yielding = qfalse, pickup, fighting;
    char message[MAX_STRING_CHARS];
    /* Bots have no network client to acknowledge reliable server commands.
       Consume announcements/config updates through the engine's bot service. */
    while (trap_BotGetServerCommand(client, message, sizeof(message))) {}
    memset(&command, 0, sizeof(command)); command.serverTime = time;
    memset(&input, 0, sizeof(input)); memset(&movement, 0, sizeof(movement));
    command.weapon = self->client->ps.weapon;
    if (self->health <= 0) {
        trap_BotResetMoveState(bot->movement); bot->lastMoveTime = 0;
        bot->controlCount = 0; bot->teleportDetour = 0; bot->routeFailed = qfalse;
        command.buttons = BUTTON_ATTACK; trap_BotUserCommand(client, &command); return;
    }
    if (self->client->sess.sessionTeam == TEAM_SPECTATOR) return;
    if (self->dk.monitorId) {
        unsigned int monitor = self->dk.monitorId;
        DK_StopMonitor(self, qfalse);
        if (!self->dk.monitorId && trap_Cvar_VariableIntegerValue("bot_report"))
            G_Printf("dk3 bot %d dismissed monitor %u after its authored wait\n", client, monitor);
        trap_BotUserCommand(client, &command);
        return;
    }
    if (self->health < bot->lastHealth && self->client->lasthurt_client >= 0 &&
        self->client->lasthurt_client < level.maxclients && self->client->lasthurt_client != client) {
        bot->hurtBy = self->client->lasthurt_client; bot->hurtTime = time;
    }
    bot->lastHealth = self->health;
    enemy = Enemy(self, bot, time);
    objective = TeamGoal(self, DK_ObjectiveGoal(self));
    goal = bot->goal >= 0 && bot->goal < level.num_entities ? &g_entities[bot->goal] : NULL;
    if (!goal || !goal->inuse || !(goal->r.contents & CONTENTS_TRIGGER) || time >= bot->nextDecision ||
        Distance(goal->r.currentOrigin, self->r.currentOrigin) < 32) {
        goal = Goal(self, bot); bot->goal = goal ? goal->s.number : -1; bot->nextDecision = time + 1000;
    }
    /* A nearby pickup is worth grabbing mid-fight; so is any health when hurt,
       and any gun while only a melee weapon is in hand. */
    pickup = goal && goal->s.eType == ET_DK3_ITEM && (Distance(goal->r.currentOrigin, self->r.currentOrigin) < 400 ||
        (self->health < 40 && !strncmp(goal->classname, "item_health", 11)) ||
        (DK_WeaponId(goal->classname) && !DK_HasWeapon(&self->client->ps, DK_WeaponId(goal->classname)) && bot->weapon && dk_weapons[bot->weapon].speed <= 0 &&
         DK_BotWeaponRange(bot->weapon) < 256 && Distance(goal->r.currentOrigin, self->r.currentOrigin) < 1200));
    if (objective && (self->client->ps.dk3Objective || self->health > 40)) goal = objective, pickup = qfalse;
    else if (!enemy && !pickup && self->health >= 50 && bot->enemySeen && time - bot->enemySeen < 4000 &&
             bot->enemy >= 0 && Hostile(self, &g_entities[bot->enemy])) goal = &g_entities[bot->enemy];
    else if (!enemy && !objective && self->health >= 80 && (!bot->enemySeen || time - bot->enemySeen > 8000) &&
             (!goal || !strcmp(goal->classname, "info_player_deathmatch") || !strncmp(goal->classname, "ammo_", 5) ||
              (DK_WeaponId(goal->classname) && DK_HasWeapon(&self->client->ps, DK_WeaponId(goal->classname))))) {
        /* Stocked and idle: head for the nearest opponent to find a fight. */
        float nearest = 1e30f;
        for (i = 0; i < level.maxclients; ++i) {
            gentity_t *other = &g_entities[i];
            if (Hostile(self, other) && Distance(self->r.currentOrigin, other->r.currentOrigin) < nearest) {
                nearest = Distance(self->r.currentOrigin, other->r.currentOrigin); goal = other;
            }
        }
    }
    if (!goal) goal = enemy;
    fighting = enemy && !pickup && !self->client->ps.dk3Objective && (!objective || goal != objective || goal == enemy);
    weapon = enemy ? Weapon(self, bot, Distance(enemy->r.currentOrigin, self->r.currentOrigin), time) :
        Weapon(self, bot, 400, time);
    if (fighting) goal = enemy;
    if (bot->teleportDetour && (time >= bot->detourUntil ||
        (self->client->ps.eFlags & EF_TELEPORT_BIT) != bot->teleportBit)) bot->teleportDetour = 0;
    if (!bot->teleportDetour && bot->routeFailed && objective && self->client->ps.dk3Objective) {
        gentity_t *detour = TeleportDetour(self, objective);
        if (detour) {
            bot->teleportDetour = detour->dk.id; bot->detourUntil = time + 10000; bot->controlCount = 0;
            if (trap_Cvar_VariableIntegerValue("bot_report"))
                G_Printf("dk3 bot %d takes reachable teleporter %u around a failed route\n", client, detour->dk.id);
        }
    }
    if (bot->teleportDetour) goal = DK_FindEntity(bot->teleportDetour);
    goal = CourseGoal(self, bot, goal, time);
    if (!goal) { trap_BotUserCommand(client, &command); return; }
    GoalOrigin(goal, destination);
    VectorSubtract(destination, self->r.currentOrigin, travel);
    travel[2] = 0; VectorNormalize(travel);
    routed = fighting ? CombatMove(self, bot, enemy, weapon, time, &input) :
        goal != enemy && Navigate(self, bot, goal, time, &input, &movement);
    if (bot->teleportDetour && goal->dk.id == bot->teleportDetour) {
        vec3_t point;
        qboolean jump;
        if (TeleportApproach(self, goal, point, &jump)) {
            VectorSubtract(point, self->r.currentOrigin, input.dir); VectorNormalize(input.dir);
            input.speed = 320; input.actionflags = jump && Distance(point, self->r.currentOrigin) < 80 ? ACTION_JUMP : 0;
            memset(&movement, 0, sizeof(movement)); routed = qtrue;
        } else bot->teleportDetour = 0;
    }
    bot->routeFailed = !routed;
    if (routed && movement.blocked && movement.blockentity >= 0 && movement.blockentity < level.maxclients) {
        gentity_t *blocker = &g_entities[movement.blockentity];
        dkBot_t *other = &bots[movement.blockentity];
        if (blocker != self && other->active && OnSameTeam(self, blocker) &&
            !blocker->client->ps.dk3Objective && (self->client->ps.dk3Objective || client < blocker->s.number)) {
            if (other->yieldFor != self->dk.id || time >= other->yieldUntil) other->recoveryUntil = 0;
            other->yieldFor = self->dk.id; other->yieldUntil = time + 1000;
        }
    }
    if (!routed && LocalMove(self, bot, travel, time, &input)) routed = qtrue;
    if (routed && movement.blocked && movement.blockentity >= MAX_CLIENTS && movement.blockentity < level.num_entities) {
        gentity_t *obstacle = &g_entities[movement.blockentity];
        gentity_t *control = obstacle->s.eType == ET_MOVER ? ControlFor(self, obstacle) : NULL;
        if (control && obstacle->moverState == MOVER_POS1) {
            RequestControl(self, bot, control, obstacle, time);
        } else if (!control && (obstacle->targetname || !UseNearby(self, bot, obstacle, time))) {
            /* ioquake3 BotAIBlocked's local avoidance: ask botlib to validate
               a sideways walk before emitting movement, then alternate sides. */
            vec3_t side, up = {0, 0, 1};
            CrossProduct(VectorLengthSquared(input.dir) > 0 ? input.dir : travel, up, side);
            if (VectorNormalize(side) > 0) {
                if (bot->avoidRight) VectorNegate(side, side);
                trap_EA_ResetInput(client);
                if (!trap_BotMoveInDirection(bot->movement, side, 200, MOVE_WALK)) {
                    bot->avoidRight = !bot->avoidRight;
                    VectorNegate(side, side);
                    trap_BotMoveInDirection(bot->movement, side, 200, MOVE_WALK);
                }
                trap_EA_GetInput(client, 0.05f, &input);
            }
        }
    }
    /* A compiled drop beside a lift can land on its raised platform. The
       physical switch must lower it before the bot can follow that drop. */
    if ((movement.failure || movement.traveltype == TRAVEL_WALKOFFLEDGE) &&
        self->client->ps.groundEntityNum >= MAX_CLIENTS && self->client->ps.groundEntityNum < level.num_entities) {
        gentity_t *platform = &g_entities[self->client->ps.groundEntityNum];
        if (platform->dk.moverKind == 1 && !platform->dk.moverAngular && platform->moverState == MOVER_POS1 &&
            platform->pos2[2] < platform->pos1[2] - 32 && destination[2] < self->r.currentOrigin[2] - 48) {
            if (LeavePlatform(self, platform, bot->routeArea, &input)) {
                routed = qtrue;
                memset(&movement, 0, sizeof(movement)); movement.traveltype = TRAVEL_WALKOFFLEDGE;
            } else {
                gentity_t *control = ControlFor(self, platform);
                if (control) RequestControl(self, bot, control, platform, time);
            }
        }
    }
    if (time < bot->yieldUntil) {
        gentity_t *requester = DK_FindEntity(bot->yieldFor);
        if (requester && requester->health > 0 && OnSameTeam(self, requester) &&
            Distance(requester->r.currentOrigin, self->r.currentOrigin) < 160) {
            vec3_t separation, side;
            VectorSubtract(self->r.currentOrigin, requester->r.currentOrigin, separation);
            VectorSet(side, -separation[1], separation[0], 0);
            if (VectorNormalize(side)) {
                bot_input_t recovery;
                memset(&recovery, 0, sizeof(recovery));
                LocalMove(self, bot, side, time, &recovery);
                if (recovery.speed || recovery.actionflags) {
                    input = recovery;
                    routed = yielding = qtrue;
                    memset(&movement, 0, sizeof(movement));
                }
            }
        }
    }
    if (routed) {
        VectorCopy(input.dir, travel);
        moveScale = Com_Clamp(0, 127, input.speed * 127 / 400);
    }
    VectorCopy(travel, direction);
    vectoangles(direction, angles);
    if (routed && (movement.flags & (MOVERESULT_MOVEMENTVIEW | MOVERESULT_SWIMVIEW | MOVERESULT_MOVEMENTVIEWSET)))
        VectorCopy(movement.ideal_viewangles, angles);
    if (weapon) command.weapon = weapon;
    if (enemy) {
        float distance = Distance(enemy->r.currentOrigin, self->r.currentOrigin);
        float error = Aim(self, bot, enemy, weapon, time, angles);
        qboolean ready = weapon && self->client->ps.weapon == weapon &&
            time - bot->enemyAcquired >= 900 - 150 * bot->skill &&
            error < (distance < 200 ? 30 : 10) &&
            (dk_weapons[weapon].speed > 0 || DK_BotWeaponRange(weapon) <= 0 || distance <= DK_BotWeaponRange(weapon) * 1.1f);
        if (DK_BotWeaponAttack(&self->client->ps, weapon, ready)) command.buttons |= BUTTON_ATTACK;
        if (trap_Cvar_VariableIntegerValue("bot_report") > 2)
            G_Printf("dk3 bot %d aim error %.1f distance %.0f range %.0f speed %.0f acquired %d\n", client, error, distance,
                DK_BotWeaponRange(weapon), dk_weapons[weapon].speed, time - bot->enemyAcquired);
    } else bot->aimTime = 0;
    {
        vec3_t moveAngles = {0, 0, 0};
        float f, r, u, maximum;
        /* ioquake3 BotInputToUserCommand: retain the independent vertical
           movement component, and ignore aim pitch for horizontal travel. */
        moveAngles[YAW] = angles[YAW];
        if (travel[2]) moveAngles[PITCH] = angles[PITCH];
        AngleVectors(moveAngles, forward, right, NULL);
        f = DotProduct(travel, forward); r = DotProduct(travel, right);
        u = fabs(forward[2]) * travel[2];
        maximum = fabs(f);
        if (fabs(r) > maximum) maximum = fabs(r);
        if (fabs(u) > maximum) maximum = fabs(u);
        if (maximum > 0) {
            command.forwardmove = Com_Clamp(-127, 127, f * moveScale / maximum);
            command.rightmove = Com_Clamp(-127, 127, r * moveScale / maximum);
            command.upmove = Com_Clamp(-127, 127, u * moveScale / maximum);
        }
    }
    if (routed) {
        if (input.actionflags & ACTION_MOVEFORWARD) command.forwardmove = 127;
        if (input.actionflags & ACTION_MOVEBACK) command.forwardmove = -127;
        if (input.actionflags & ACTION_MOVELEFT) command.rightmove = -127;
        if (input.actionflags & ACTION_MOVERIGHT) command.rightmove = 127;
        if (input.actionflags & (ACTION_JUMP | ACTION_DELAYEDJUMP | ACTION_MOVEUP)) command.upmove = 127;
        else if (input.actionflags & (ACTION_CROUCH | ACTION_MOVEDOWN)) command.upmove = -127;
        if (input.actionflags & ACTION_WALK) command.buttons |= BUTTON_WALKING;
    }
    if (goal == enemy && !routed) {
        command.forwardmove = Distance(enemy->r.currentOrigin, self->r.currentOrigin) > 300 ? 100 : 0;
        command.rightmove = bot->strafeRight ? 72 : -72;
    }
    UseNearby(self, bot, goal, time);
    if (!yielding && goal->client && OnSameTeam(self, goal) && Distance(self->r.currentOrigin, goal->r.currentOrigin) < 128)
        command.forwardmove = command.rightmove = 0;
    for (i = 0; i < 3; ++i) command.angles[i] = ANGLE2SHORT(angles[i]) - self->client->ps.delta_angles[i];
    if (fighting || bot->progressGoal != goal->dk.id || Distance(self->r.currentOrigin, bot->progressOrigin) >= 48 ||
        Distance(self->r.currentOrigin, destination) < 96 || (movement.flags & MOVERESULT_WAITING)) {
        VectorCopy(self->r.currentOrigin, bot->progressOrigin);
        bot->progressGoal = goal->dk.id; bot->stuckSince = 0;
    } else {
        /* Measure progress over a region, not one frame. Oscillation and a
           zero-direction botlib result previously hid indefinite stalls. */
        if (!bot->stuckSince) bot->stuckSince = time;
        /* Do not replace a planned jump with a sideways walk just as the
           bot reaches its takeoff point after a slow barrier approach. */
        if (time - bot->stuckSince > 1000 && !yielding && command.upmove <= 0 &&
            !(movement.flags & MOVERESULT_WAITING)) {
            bot_input_t recovery;
            if (LocalMove(self, bot, travel, time, &recovery)) {
                vec3_t flatAngles = {0, angles[YAW], 0}, recoveryForward, recoveryRight;
                AngleVectors(flatAngles, recoveryForward, recoveryRight, NULL);
                command.forwardmove = Com_Clamp(-127, 127, DotProduct(recovery.dir, recoveryForward) * recovery.speed * 127 / 400);
                command.rightmove = Com_Clamp(-127, 127, DotProduct(recovery.dir, recoveryRight) * recovery.speed * 127 / 400);
                command.upmove = recovery.actionflags & (ACTION_JUMP | ACTION_MOVEUP) ? 127 :
                    recovery.actionflags & (ACTION_CROUCH | ACTION_MOVEDOWN) ? -127 : 0;
            }
        }
        if (time - bot->stuckSince > 3000) {
            /* Walking links expire after five seconds in botlib. Resetting
               its state here restarted that deadline and erased failed-link
               history before another route could be selected. */
            bot->nextDecision = 0; bot->stuckSince = 0;
            bot->avoidRight = !bot->avoidRight;
        }
    }
    /* Routed swimming already supplies its pitch and vertical action. Forcing
       ascent here prevents a carrier from following submerged passages. */
    if (self->waterlevel > 1 && !routed) command.upmove = 127;
    if (trap_Cvar_VariableIntegerValue("bot_report") && time >= bot->nextReport) {
        G_Printf("dk3 bot %d team %d health %d position %.0f %.0f %.0f area %d goal %u (%s) destination %.0f %.0f %.0f commands %d %d %d stuck %d route %d goalarea %d failure %d travel %d blocked %d entity %d\n",
            client, self->client->sess.sessionTeam, self->health,
            self->r.currentOrigin[0], self->r.currentOrigin[1], self->r.currentOrigin[2],
            trap_AAS_PointAreaNum(self->r.currentOrigin), goal->dk.id, goal->classname,
            destination[0], destination[1], destination[2], command.forwardmove, command.rightmove, command.upmove,
            bot->stuckSince ? time - bot->stuckSince : 0, !bot->routeFailed, bot->routeArea, movement.failure, movement.traveltype,
            movement.blocked, movement.blockentity);
        bot->nextReport = time + 5000;
        G_Printf("dk3 bot %d combat enemy %d seen %d weapon %d/%d fighting %d attack %d\n", client,
            enemy ? enemy->s.number : -1, bot->enemySeen ? time - bot->enemySeen : -1, weapon,
            self->client->ps.weapon, fighting, (command.buttons & BUTTON_ATTACK) != 0);
        if (trap_Cvar_VariableIntegerValue("bot_report") > 1 && time < bot->yieldUntil)
            G_Printf("dk3 bot yield %d requester %u active %d input %.0f direction %.2f %.2f %.2f ground %d\n",
                client, bot->yieldFor, yielding, input.speed, input.dir[0], input.dir[1], input.dir[2],
                self->client->ps.groundEntityNum);
        if (trap_Cvar_VariableIntegerValue("bot_report") > 1 && bot->routeFailed) {
            trace_t body;
            trap_Trace(&body, self->client->ps.origin, self->r.mins, self->r.maxs,
                       self->client->ps.origin, client, MASK_PLAYERSOLID);
            G_Printf("dk3 bot body %d ground %d velocity %.1f %.1f %.1f solid %d/%d entity %d flags %d\n",
                client, self->client->ps.groundEntityNum, self->client->ps.velocity[0],
                self->client->ps.velocity[1], self->client->ps.velocity[2], body.startsolid, body.allsolid,
                body.entityNum, self->client->ps.pm_flags);
        }
        if (movement.traveltype == TRAVEL_SWIM)
            G_Printf("dk3 bot swim %d water %d direction %.3f %.3f %.3f view %.1f %.1f actual %.1f %.1f velocity %.1f %.1f %.1f\n",
                client, self->waterlevel, input.dir[0], input.dir[1], input.dir[2], angles[PITCH], angles[YAW],
                self->client->ps.viewangles[PITCH], self->client->ps.viewangles[YAW],
                self->client->ps.velocity[0], self->client->ps.velocity[1], self->client->ps.velocity[2]);
        if (movement.blocked && movement.blockentity >= MAX_CLIENTS && movement.blockentity < level.num_entities) {
            gentity_t *blocker = &g_entities[movement.blockentity];
            G_Printf("dk3 bot blocker %d class %s model %s targetname %s mover %d bounds %.0f %.0f %.0f / %.0f %.0f %.0f\n",
                movement.blockentity, blocker->classname, blocker->model ? blocker->model : "",
                blocker->targetname ? blocker->targetname : "", blocker->moverState,
                blocker->r.absmin[0], blocker->r.absmin[1], blocker->r.absmin[2],
                blocker->r.absmax[0], blocker->r.absmax[1], blocker->r.absmax[2]);
        }
    }
    trap_BotUserCommand(client, &command);
}

int DK_BotFrame(int time) {
    int i;
    if (time - lastLibraryTime >= 50) {
        trap_BotLibStartFrame(time / 1000.0f);
        lastLibraryTime = time;
        for (i = 0; i < level.num_entities; ++i) {
            gentity_t *entity = &g_entities[i];
            bot_entitystate_t state;
            if (!entity->inuse || !entity->r.linked || entity->s.eType >= ET_EVENTS || entity->s.eType == ET_DK3_MISSILE || entity->s.eType == ET_DK3_EFFECT) {
                trap_BotLibUpdateEntity(i, NULL); continue;
            }
            memset(&state, 0, sizeof(state));
            VectorCopy(entity->r.currentOrigin, state.origin); VectorCopy(entity->r.currentAngles, state.angles);
            VectorCopy(entity->r.mins, state.mins); VectorCopy(entity->r.maxs, state.maxs);
            state.type = entity->s.eType; state.flags = entity->s.eFlags;
            state.solid = !(entity->r.contents & (CONTENTS_SOLID | CONTENTS_BODY)) ? SOLID_NOT : entity->r.bmodel ? SOLID_BSP : SOLID_BBOX;
            state.modelindex = entity->s.modelindex;
            trap_BotLibUpdateEntity(i, &state);
        }
    }
    if (trap_Cvar_VariableIntegerValue("bot_pause")) return qtrue;
    for (i = 0; i < level.maxclients; ++i)
        if (bots[i].active && g_entities[i].client && g_entities[i].client->pers.connected == CON_CONNECTED) Think(i, time);
    if (g_gametype.integer != GT_SINGLE_PLAYER && time >= populationTime) {
        int present = 0, removable = -1, desired = trap_Cvar_VariableIntegerValue("bot_minplayers");
        for (i = 0; i < level.maxclients; ++i) if (level.clients[i].pers.connected != CON_DISCONNECTED) {
            ++present;
            if (bots[i].active) removable = i;
        }
        if (desired > present && present < level.maxclients) AddBot(va("dk3 bot %d", present + 1), Com_Clamp(1, 5, trap_Cvar_VariableIntegerValue("g_spSkill")), "");
        if (desired > 0 && present > desired && removable >= 0) trap_DropClient(removable, "Bot population reduced");
        populationTime = time + 1000;
    }
    return qtrue;
}
