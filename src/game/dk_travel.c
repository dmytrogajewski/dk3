/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_weapons.h"

/* Named player records survive a map VM restart without serializing a C structure. */
typedef struct { const char *name; size_t offset; int maximumRemaining; } travelField_t;
#define FIELD(name, member) {name, offsetof(playerState_t, member), 0}
static const travelField_t fields[] = {
    FIELD("health", stats[STAT_HEALTH]), FIELD("armor", stats[STAT_ARMOR]),
    FIELD("maximum_health", stats[STAT_MAX_HEALTH]), FIELD("weapon", weapon),
    FIELD("inventory", dk3Inventory), FIELD("experience", dk3Experience),
    FIELD("level", dk3Level), FIELD("sword_experience", dk3SwordExperience),
    FIELD("episode", dk3Episode),
    FIELD("keys", dk3Keys), FIELD("quest", dk3Quest), FIELD("status", dk3Status),
    {"invincible", offsetof(playerState_t, dk3InvincibleUntil), 30000},
    {"environment", offsetof(playerState_t, dk3EnvUntil), 60000},
    {"invisible", offsetof(playerState_t, powerups[PW_INVIS]), 30000},
    {"gas_hands", offsetof(playerState_t, powerups[PW_DK3_GASHANDS]), DK_MAX_GASHANDS_TIME},
    FIELD("save_gems", dk3SaveGems), FIELD("attribute_points", dk3AttributePoints)
};
#undef FIELD

static int *Value(playerState_t *ps, size_t offset) { return (int *)((byte *)ps + offset); }

void DK_WriteTravel(gentity_t *player) {
    char text[4096], line[96];
    int i;
    playerState_t *ps = &player->client->ps;
    Q_strncpyz(text, "dk3_travel 1\n", sizeof(text));
    ps->stats[STAT_HEALTH] = player->health;
    for (i = 0; i < ARRAY_LEN(fields); ++i) {
        int value = *Value(ps, fields[i].offset);
        if (fields[i].maximumRemaining) value = value > level.time ? value - level.time : 0;
        if (!strcmp(fields[i].name, "status")) value &= ~7;
        Com_sprintf(line, sizeof(line), "%s %d\n", fields[i].name, value);
        Q_strcat(text, sizeof(text), line);
    }
    for (i = 0; i < MAX_WEAPONS; ++i) {
        Com_sprintf(line, sizeof(line), "ammo%d %d\n", i, ps->ammo[i]);
        Q_strcat(text, sizeof(text), line);
    }
    for (i = 0; i < 5; ++i) {
        Com_sprintf(line, sizeof(line), "attribute%d %d\n", i, ps->dk3Attributes[i]);
        Q_strcat(text, sizeof(text), line);
        Com_sprintf(line, sizeof(line), "boost%d %d\n", i, ps->dk3BoostUntil[i] > level.time ? ps->dk3BoostUntil[i] - level.time : 0);
        Q_strcat(text, sizeof(text), line);
    }
    trap_Cvar_Set("dk3_travel", text);
}

static qboolean Integer(const char *text, int *result) {
    unsigned int number = 0, maximum;
    qboolean negative = *text == '-';
    if (*text == '-' || *text == '+') ++text;
    if (!*text) return qfalse;
    maximum = negative ? 2147483648u : 2147483647u;
    for (; *text; ++text) {
        unsigned int digit = (unsigned int)(*text - '0');
        if (digit > 9 || number > (maximum - digit) / 10) return qfalse;
        number = number * 10 + digit;
    }
    *result = negative ? (int)(0u - number) : (int)number;
    return qtrue;
}

void DK_ReadTravel(gentity_t *player) {
    char text[4096], key[64], *cursor, *token;
    playerState_t state = player->client->ps;
    int i, value, index, field;
    qboolean valid = qtrue, seen[ARRAY_LEN(fields) + MAX_WEAPONS + 10];
    memset(seen, 0, sizeof(seen));
    trap_Cvar_VariableStringBuffer("dk3_travel", text, sizeof(text));
    if (!*text) return;
    trap_Cvar_Set("dk3_travel", "");
    cursor = text;
    if (strcmp(COM_Parse(&cursor), "dk3_travel") || strcmp(COM_Parse(&cursor), "1")) valid = qfalse;
    while (valid && *(token = COM_Parse(&cursor))) {
        Q_strncpyz(key, token, sizeof(key));
        token = COM_Parse(&cursor);
        if (!cursor || !*token) { valid = qfalse; break; }
        if (!Integer(token, &value)) { valid = qfalse; break; }
        field = -1;
        for (i = 0; i < ARRAY_LEN(fields); ++i) if (!strcmp(key, fields[i].name)) break;
        if (i < ARRAY_LEN(fields)) {
            field = i;
            if (fields[i].maximumRemaining) {
                if (value < 0 || value > fields[i].maximumRemaining || level.time > 2147483647 - value) { valid = qfalse; break; }
                value = value ? level.time + value : 0;
            }
            *Value(&state, fields[i].offset) = value;
        } else if (!strncmp(key, "ammo", 4) && Integer(key + 4, &index) && index >= 0 && index < MAX_WEAPONS) {
            state.ammo[index] = value; field = ARRAY_LEN(fields) + index;
        } else if (!strncmp(key, "attribute", 9) && Integer(key + 9, &index) && index >= 0 && index < 5) {
            state.dk3Attributes[index] = value; field = ARRAY_LEN(fields) + MAX_WEAPONS + index;
        } else if (!strncmp(key, "boost", 5) && Integer(key + 5, &index) && index >= 0 && index < 5 && value >= 0 && value <= 30000 &&
                   level.time <= 2147483647 - value) {
            state.dk3BoostUntil[index] = value ? level.time + value : 0; field = ARRAY_LEN(fields) + MAX_WEAPONS + 5 + index;
        }
        if (field < 0 || seen[field]) valid = qfalse;
        else seen[field] = qtrue;
    }
    for (i = 0; i < ARRAY_LEN(seen); ++i) if (!seen[i]) valid = qfalse;
    if (state.stats[STAT_HEALTH] < 1 || state.stats[STAT_HEALTH] > 10000 ||
        state.stats[STAT_ARMOR] < 0 || state.stats[STAT_ARMOR] > 10000 ||
        state.stats[STAT_MAX_HEALTH] < 1 || state.stats[STAT_MAX_HEALTH] > 10000 ||
        state.dk3Experience < 0 || state.dk3SwordExperience < 0 || state.dk3SaveGems < 0 || state.dk3AttributePoints < 0 ||
        (state.dk3Status & ~120) || (state.dk3Quest & ~1) || ((unsigned int)state.dk3Inventory >> DK_WEAPON_COUNT) ||
        state.dk3Level < 1 || state.dk3Level > 25 || state.dk3Episode < 1 || state.dk3Episode > 4 || !DK_HasWeapon(&state, state.weapon)) valid = qfalse;
    for (i = 0; i < 5; ++i) if (state.dk3Attributes[i] < 0 || state.dk3Attributes[i] > 5) valid = qfalse;
    for (i = 0; i < MAX_WEAPONS; ++i) if (state.ammo[i] < 0 || state.ammo[i] > 32767) valid = qfalse;
    if (!valid) { G_Printf("dk3: invalid campaign transition record; starting inventory retained\n"); return; }
    {
        char map[MAX_QPATH];
        trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
        if (map[0] == 'e' && map[1] >= '1' && map[1] <= '4' && map[1] - '0' != state.dk3Episode) {
            int sword = state.dk3Inventory & (1u << DK_W_SWORD);
            state.dk3Episode = map[1] - '0'; state.dk3Keys = state.dk3Quest = 0;
            state.dk3Inventory = player->client->ps.dk3Inventory | sword;
            state.weapon = player->client->ps.weapon;
            state.powerups[PW_DK3_GASHANDS] = 0;
            memcpy(state.ammo, player->client->ps.ammo, sizeof(state.ammo));
        }
    }
    player->client->ps = state;
    player->health = state.stats[STAT_HEALTH];
}

/* Named objects belong to the map's target chain. A button remains a physical
   control even when another event can press it. Touch triggers use their own
   collision path; the player's use ray must not invoke them. */
qboolean DK_CanUse(gentity_t *target) {
    if (!target || !target->inuse || !target->use || !target->classname ||
        !strncmp(target->classname, "trigger_", 8)) return qfalse;
    return !target->targetname || !*target->targetname || !strcmp(target->classname, "func_button");
}

qboolean DK_ClientCommand(gentity_t *player, const char *command) {
    const char *names[] = {"power", "attack", "speed", "acro", "vita"};
    char argument[64];
    int i;
    if (DK_SaveCommand(player, command)) return qtrue;
    if (DK_CompanionCommand(player, command)) return qtrue;
    if (!Q_stricmp(command, "cin_skip")) { if (!DK_StopMonitor(player, qfalse)) DK_SkipCinematic(); return qtrue; }
    if (!Q_stricmp(command, "detonate") || !Q_stricmp(command, "c4_detonate")) {
        if (player->health > 0 && player->client->sess.sessionTeam != TEAM_SPECTATOR &&
            !player->client->ps.dk3CameraActive)
            trap_SendServerCommand(player->s.number, va("print \"Detonating %d C4 charge(s).\n\"", DK_DetonateCharges(player)));
        return qtrue;
    }
    if (!Q_stricmp(command, "use")) {
        if (player->health <= 0 || player->client->sess.sessionTeam == TEAM_SPECTATOR) return qtrue;
        if (DK_StopMonitor(player, qfalse)) return qtrue;
        trace_t trace;
        vec3_t start, end, forward;
        VectorCopy(player->client->ps.origin, start); start[2] += player->client->ps.viewheight;
        AngleVectors(player->client->ps.viewangles, forward, NULL, NULL);
        VectorMA(start, 96, forward, end);
        trap_Trace(&trace, start, NULL, NULL, end, player->s.number, MASK_SHOT);
        if (trace.entityNum < ENTITYNUM_WORLD) {
            gentity_t *target = &g_entities[trace.entityNum];
            if (DK_CanUse(target)) target->use(target, player, player);
            else if (target->use && target->targetname && *target->targetname)
                trap_SendServerCommand(player->s.number, "cp \"This is operated elsewhere.\"");
        }
        return qtrue;
    }
    if (!Q_stricmp(command, "attribute")) {
        trap_Argv(1, argument, sizeof(argument));
        for (i = 0; i < ARRAY_LEN(names); ++i) if (!Q_stricmp(argument, names[i])) break;
        if (i == ARRAY_LEN(names)) {
            trap_SendServerCommand(player->s.number, "print \"Use attribute power, attack, speed, acro or vita.\n\"");
        } else if (player->client->ps.dk3AttributePoints > 0 && player->client->ps.dk3Attributes[i] < 5) {
            --player->client->ps.dk3AttributePoints;
            ++player->client->ps.dk3Attributes[i];
            trap_SendServerCommand(player->s.number, va("cp \"%s increased\"", names[i]));
        } else trap_SendServerCommand(player->s.number, "print \"No point available or attribute is at its limit.\n\"");
        return qtrue;
    }
    return qfalse;
}
