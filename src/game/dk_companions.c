/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_weapons.h"
#include "dk_save_schema.h"

static const char *travelNames[] = {"dk3_mikiko_travel", "dk3_superfly_travel"};
typedef struct { const char *name; size_t offset; } companionField_t;
#define CF(name, field) {name, offsetof(gentity_t, field)}
static const companionField_t fields[] = {
    CF("health", health), CF("maximum", dk.maxHealth), CF("armor", dk.armor),
    CF("weapon", s.weapon), CF("inventory", dk.inventory), CF("experience", dk.experience), CF("level", dk.actorLevel)
};
#undef CF

static int Identity(gentity_t *actor) { return strstr(actor->classname, "mikiko") && !strstr(actor->classname, "mikikofly") ? 0 : 1; }
static int *Value(gentity_t *actor, size_t offset) { return (int *)((byte *)actor + offset); }

static qboolean Integer(const char *text, int *out) {
    unsigned int value = 0;
    const char *p;
    if (!text || !*text) return qfalse;
    for (p = text; *p; ++p) {
        if (*p < '0' || *p > '9' || value > (2147483647u - (*p - '0')) / 10) return qfalse;
        value = value * 10 + *p - '0';
    }
    *out = value;
    return qtrue;
}

static qboolean ReadTravel(const char *text, gentity_t *actor) {
    char copy[2048], *cursor;
    int i, value;
    if (!*text) return qtrue;
    Q_strncpyz(copy, text, sizeof(copy)); cursor = copy;
    if (strcmp(COM_Parse(&cursor), "dk3_companion") || strcmp(COM_Parse(&cursor), "1")) return qfalse;
    for (i = 0; i < ARRAY_LEN(fields); ++i) {
        if (strcmp(COM_Parse(&cursor), fields[i].name) || !Integer(COM_Parse(&cursor), &value)) return qfalse;
        *Value(actor, fields[i].offset) = value;
    }
    if (strcmp(COM_Parse(&cursor), "ammo")) return qfalse;
    for (i = 0; i < MAX_WEAPONS; ++i)
        if (!Integer(COM_Parse(&cursor), &actor->dk.ammunition[i]) || actor->dk.ammunition[i] > 32767) return qfalse;
    if (strcmp(COM_Parse(&cursor), "attributes")) return qfalse;
    for (i = 0; i < 5; ++i)
        if (!Integer(COM_Parse(&cursor), &actor->dk.attributes[i]) || actor->dk.attributes[i] > 5) return qfalse;
    if (*COM_Parse(&cursor) || actor->health < 1 || actor->health > 10000 || actor->dk.maxHealth < 1 || actor->dk.maxHealth > 10000 ||
        actor->dk.armor > 10000 || actor->s.weapon < 1 || actor->s.weapon >= DK_WEAPON_COUNT ||
        !((unsigned int)actor->dk.inventory & (1u << actor->s.weapon)) || actor->dk.actorLevel < 1 || actor->dk.actorLevel > 25) return qfalse;
    return qtrue;
}

void DK_WriteCompanionTravel(void) {
    int i, j;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *actor = &g_entities[i];
        char text[2048], part[96];
        if (!actor->inuse || !DK_IsCompanion(actor) || actor->health <= 0 || actor->dk.cinematicOwned) continue;
        Q_strncpyz(text, "dk3_companion 1 ", sizeof(text));
        for (j = 0; j < ARRAY_LEN(fields); ++j) {
            Com_sprintf(part, sizeof(part), "%s %d ", fields[j].name, *Value(actor, fields[j].offset));
            Q_strcat(text, sizeof(text), part);
        }
        Q_strcat(text, sizeof(text), "ammo ");
        for (j = 0; j < MAX_WEAPONS; ++j) { Com_sprintf(part, sizeof(part), "%d ", actor->dk.ammunition[j]); Q_strcat(text, sizeof(text), part); }
        Q_strcat(text, sizeof(text), "attributes ");
        for (j = 0; j < 5; ++j) { Com_sprintf(part, sizeof(part), "%d ", actor->dk.attributes[j]); Q_strcat(text, sizeof(text), part); }
        trap_Cvar_Set(travelNames[Identity(actor)], text);
    }
}

void DK_InitCompanionInventory(gentity_t *actor) {
    char map[MAX_QPATH], text[2048];
    int episode, weapon;
    gentity_t saved;
    trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
    episode = map[0] == 'e' && map[1] >= '1' && map[1] <= '4' ? map[1] - '0' : 1;
    weapon = DK_CompanionFirstWeapon(episode);
    actor->health = actor->dk.maxHealth = 100;
    actor->dk.actorLevel = 1;
    actor->s.weapon = weapon;
    actor->dk.inventory = 1u << weapon;
    actor->dk.ammunition[weapon] = dk_weapons[weapon].initialAmmo;
    actor->dk.companionEnabled = 1;
    trap_Cvar_VariableStringBuffer(travelNames[Identity(actor)], text, sizeof(text));
    if (!*text) return;
    saved = *actor;
    if (!ReadTravel(text, &saved)) { G_Printf("dk3: invalid companion transition for %s\n", actor->classname); return; }
    actor->health = saved.health; actor->dk.maxHealth = saved.dk.maxHealth; actor->dk.armor = saved.dk.armor;
    actor->dk.actorLevel = saved.dk.actorLevel; actor->dk.experience = saved.dk.experience;
    memcpy(actor->dk.attributes, saved.dk.attributes, sizeof(actor->dk.attributes));
    /* Episode changes replace the weapon set while retaining character progression. */
    if (dk_weapons[saved.s.weapon].episode == episode) {
        actor->s.weapon = saved.s.weapon; actor->dk.inventory = saved.dk.inventory;
        memcpy(actor->dk.ammunition, saved.dk.ammunition, sizeof(actor->dk.ammunition));
    }
}

static gentity_t *Companion(int identity) {
    int i;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i)
        if (g_entities[i].inuse && DK_IsCompanion(&g_entities[i]) && Identity(&g_entities[i]) == identity) return &g_entities[i];
    return NULL;
}

static gentity_t *Spawn(gentity_t *point, const char *name) {
    int identity = !strcmp(name, "mikiko") ? 0 : 1;
    gentity_t *actor = Companion(identity);
    vec3_t origin;
    if (actor) return actor;
    /* Gold spawn brushes use their upper world-space corner. They are
       script-only markers, not a request to spawn at the activator. */
    if (point->r.bmodel) VectorAdd(point->r.currentOrigin, point->r.maxs, origin);
    else VectorCopy(point->r.currentOrigin, origin);
    actor = G_Spawn(); actor->classname = G_NewString(name); actor->dk.uniqueid = G_NewString(identity ? "superfly" : "mikiko");
    VectorCopy(origin, actor->s.origin); VectorCopy(point->s.angles, actor->s.angles);
    if (!DK_SpawnActor(actor)) { G_FreeEntity(actor); G_Printf("dk3: companion definition %s is missing\n", name); return NULL; }
    {
        trace_t trace, path;
        vec3_t candidate;
        int attempt;
        for (attempt = 0; attempt < 17; ++attempt) {
            VectorCopy(origin, candidate);
            if (attempt) {
                float angle = ((attempt - 1) % 8) * M_PI / 4;
                float radius = attempt <= 8 ? 64 : 112;
                candidate[0] += radius * cos(angle); candidate[1] += radius * sin(angle); candidate[2] += 8;
            }
            trap_Trace(&trace, candidate, actor->r.mins, actor->r.maxs, candidate, actor->s.number, MASK_PLAYERSOLID);
            trap_Trace(&path, origin, NULL, NULL, candidate, actor->s.number, MASK_SOLID);
            if (!trace.startsolid && !trace.allsolid && path.fraction == 1) break;
        }
        if (attempt == 17) { G_Printf("dk3: companion %s start %u has no free spawn space\n", name, point->dk.id); G_FreeEntity(actor); return NULL; }
        G_SetOrigin(actor, candidate); trap_LinkEntity(actor);
    }
    actor->dk.companionOrder = (point->spawnflags & 1) ? 1 : 0;
    return actor;
}

qboolean DK_CompanionsReady(gentity_t *player, int flags) {
    int i;
    static int reminder;
    if (g_gametype.integer != GT_SINGLE_PLAYER || !flags) return qtrue;
    for (i = 0; i < 2; ++i) if (flags & (i ? 2 : 4)) {
        gentity_t *actor = Companion(i);
        trace_t trace;
        if (!actor && i == 0) {
            gentity_t *carrier = Companion(1);
            if (carrier && !strcmp(carrier->classname, "mikikofly")) actor = carrier;
        }
        if (actor && actor->health > 0 && Distance(actor->r.currentOrigin, player->r.currentOrigin) < 384) {
            trap_Trace(&trace, actor->r.currentOrigin, NULL, NULL, player->r.currentOrigin, actor->s.number, MASK_SOLID);
            if (trace.fraction == 1) continue;
        }
        if (level.time >= reminder || reminder > level.time + 2000) {
            trap_SendServerCommand(player->s.number, va("cp \"Bring %s here before continuing.\"", i ? "Superfly" : "Mikiko"));
            reminder = level.time + 2000;
        }
        return qfalse;
    }
    return qtrue;
}

void DK_StartCompanions(gentity_t *player) {
    const char *points[] = {"info_mikiko_start", "info_superfly_start", "info_mikikofly_start"};
    const char *names[] = {"mikiko", "superfly", "mikikofly"};
    char entry[MAX_QPATH];
    int i;
    if (g_gametype.integer != GT_SINGLE_PLAYER || player->s.number != 0) return;
    trap_Cvar_VariableStringBuffer("dk3_entry", entry, sizeof(entry));
    for (i = 0; i < ARRAY_LEN(points); ++i) {
        gentity_t *point = NULL, *best = NULL;
        float nearest = 1e30f;
        while ((point = G_Find(point, FOFS(classname), points[i]))) {
            float distance = Distance(point->s.origin, player->r.currentOrigin);
            if (*entry && point->targetname && !strcmp(point->targetname, entry)) { best = point; break; }
            if (distance < nearest) { nearest = distance; best = point; }
        }
        if (best) Spawn(best, names[i]);
    }
}

static void Trigger(gentity_t *ent, gentity_t *other, gentity_t *activator) {
    int i;
    (void)other;
    if (!activator || !activator->client || activator->health <= 0 || level.time < ent->dk.nextUse) return;
    if (ent->dk.uses && !(ent->spawnflags & 4)) return;
    if (strstr(ent->classname, "_spawn")) {
        gentity_t *point = ent->target ? G_Find(NULL, FOFS(targetname), ent->target) : ent;
        if (point) Spawn(point, strstr(ent->classname, "mikiko") ? "mikiko" : "superfly");
    } else for (i = 0; i < 2; ++i) {
        gentity_t *actor = Companion(i);
        vec3_t destination;
        if (!actor || actor->health <= 0 || (ent->dk.companionName &&
            Q_stricmp(ent->dk.companionName, i ? "superfly" : "mikiko"))) continue;
        if (!strcmp(ent->classname, "trigger_sidekick")) {
            actor->dk.companionEnabled = ent->dk.triggerToggle;
            actor->dk.companionOrder = ent->dk.triggerToggle ? 0 : 1;
            continue;
        }
        if (!strcmp(ent->classname, "trigger_sidekick_stop")) {
            actor->dk.moveActive = 0;
            actor->dk.pathTarget = NULL;
            actor->dk.pickupId = 0;
            actor->dk.companionOrder = 1;
            continue;
        }
        VectorCopy(ent->dk.triggerDestination, destination);
        if (ent->target) {
            gentity_t *target = G_Find(NULL, FOFS(targetname), ent->target);
            if (!target) { G_Printf("dk3: sidekick trigger %u lacks target %s\n", ent->dk.id, ent->target); continue; }
            VectorCopy(target->s.origin, destination);
        }
        if (!strcmp(ent->classname, "trigger_sidekick_teleport")) {
            trace_t trace, path;
            vec3_t candidate;
            int attempt;
            for (attempt = 0; attempt < 9; ++attempt) {
                VectorCopy(destination, candidate);
                if (attempt) { float angle = (attempt - 1) * M_PI / 4; candidate[0] += 56 * cos(angle); candidate[1] += 56 * sin(angle); }
                trap_Trace(&trace, candidate, actor->r.mins, actor->r.maxs, candidate, actor->s.number, MASK_PLAYERSOLID);
                trap_Trace(&path, destination, NULL, NULL, candidate, actor->s.number, MASK_SOLID);
                if (!trace.startsolid && !trace.allsolid && path.fraction == 1) break;
            }
            if (attempt == 9) { G_Printf("dk3: sidekick trigger %u destination is blocked\n", ent->dk.id); continue; }
            G_SetOrigin(actor, candidate); trap_LinkEntity(actor);
            actor->dk.moveActive = 0;
            actor->dk.companionOrder = (ent->spawnflags & 2) ? 0 : 1;
        } else {
            DK_ActorMoveTo(actor, destination);
            actor->dk.companionOrder = 1;
        }
        if (ent->dk.triggerAnimation) DK_ActorAnimate(actor, ent->dk.triggerAnimation, 1);
    }
    ++ent->dk.uses;
    ent->dk.nextUse = level.time + (int)((ent->wait > 0 ? ent->wait : 1) * 1000);
    if (ent->noise_index) G_Sound(activator, CHAN_VOICE, ent->noise_index);
    if (ent->message) trap_SendServerCommand(activator->s.number, va("cp \"%s\"", ent->message));
    G_UseTargets(ent, activator);
}

void DK_RestoreCompanionEntity(gentity_t *ent) {
    if (!strcmp(ent->classname, "trigger_superfly_spawn") || !strcmp(ent->classname, "trigger_mikiko_spawn")) {
        ent->touch = NULL;
        ent->use = Trigger;
        ent->r.contents = 0;
        ent->r.svFlags |= SVF_NOCLIENT;
    }
}

static void Touch(gentity_t *ent, gentity_t *other, trace_t *trace) { (void)trace; Trigger(ent, other, other); }

qboolean DK_SpawnCompanionEntity(gentity_t *ent) {
    const char *name = ent->classname;
    char *text;
    if (!strcmp(name, "info_mikiko_start") || !strcmp(name, "info_superfly_start") || !strcmp(name, "info_mikikofly_start")) {
        G_SetOrigin(ent, ent->s.origin); ent->r.svFlags |= SVF_NOCLIENT; return qtrue;
    }
    if (strncmp(name, "trigger_sidekick", 16) && strcmp(name, "trigger_superfly_spawn") && strcmp(name, "trigger_mikiko_spawn")) return qfalse;
    G_SpawnString("sidekick", "", &text); if (*text) ent->dk.companionName = G_NewString(text);
    G_SpawnString("animation", "", &text); if (*text) ent->dk.triggerAnimation = G_NewString(text);
    G_SpawnInt("toggle", "1", &ent->dk.triggerToggle);
    G_SpawnFloat("x", "0", &ent->dk.triggerDestination[0]);
    G_SpawnFloat("y", "0", &ent->dk.triggerDestination[1]);
    G_SpawnFloat("z", "0", &ent->dk.triggerDestination[2]);
    G_SpawnString("sound", "", &text);
    if (*text) ent->noise_index = G_SoundIndex(va("%s%s%s", !Q_stricmpn(text, "sounds/", 7) ? "" : "sounds/", text, strstr(text, ".mp3") ? ".ogg" : ""));
    ent->use = Trigger;
    if (ent->model) {
        trap_SetBrushModel(ent, ent->model); ent->touch = Touch;
        ent->r.contents = CONTENTS_TRIGGER; ent->r.svFlags |= SVF_NOCLIENT;
        DK_RestoreCompanionEntity(ent); trap_LinkEntity(ent);
    }
    return qtrue;
}

qboolean DK_WriteCompanionState(dkSaveWriter_t *writer) {
    int i;
    char text[2048];
    DK_WriteCompanionTravel();
    for (i = 0; i < 2; ++i) {
        trap_Cvar_VariableStringBuffer(travelNames[i], text, sizeof(text));
        if (!DK_SaveRecord(writer, "companion_travel", i + 1) || !DK_SaveText(writer, "state", text)) return qfalse;
    }
    return qtrue;
}

qboolean DK_ReadCompanionState(dkSaveReader_t *reader, unsigned int id, qboolean apply) {
    dkSaveField_t field;
    gentity_t probe;
    char text[2048];
    memset(&probe, 0, sizeof(probe));
    if (id < 1 || id > 2 || !DK_SaveNextField(reader, &field) || strcmp(field.name, "state") ||
        !DK_SaveString(&field, text, sizeof(text)) || reader->fieldsLeft || !ReadTravel(text, &probe)) return qfalse;
    if (apply) trap_Cvar_Set(travelNames[id - 1], text);
    return qtrue;
}

void DK_UpdateCompanionStatus(void) {
    char status[256] = "", part[128], previous[256];
    int i;
    for (i = 0; i < 2; ++i) {
        gentity_t *actor = Companion(i);
        if (!actor || actor->dk.cinematicOwned) continue;
        Com_sprintf(part, sizeof(part), "%s %d %d %d %d %d ", i ? "Superfly" : "Mikiko",
                    actor->health, actor->dk.armor, actor->s.weapon,
                    actor->s.weapon > 0 && actor->s.weapon < MAX_WEAPONS ? actor->dk.ammunition[actor->s.weapon] : 0,
                    actor->dk.companionOrder);
        Q_strcat(status, sizeof(status), part);
    }
    trap_GetConfigstring(CS_DK3_COMPANIONS, previous, sizeof(previous));
    if (strcmp(status, previous)) trap_SetConfigstring(CS_DK3_COMPANIONS, status);
}
