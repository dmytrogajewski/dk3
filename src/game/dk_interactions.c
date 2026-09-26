/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_weapons.h"
#include "dk_inventory.h"

static qboolean Is(gentity_t *entity, const char *name) { return !strcmp(entity->classname, name); }

static void Brush(gentity_t *entity, int contents, qboolean visible) {
    if (!entity->model || entity->model[0] != '*') G_Error("dk3: %s %u requires a brush", entity->classname, entity->dk.id);
    trap_SetBrushModel(entity, entity->model); entity->r.contents = contents;
    entity->r.svFlags = visible ? 0 : SVF_NOCLIENT;
    entity->s.eType = visible ? ET_MOVER : ET_GENERAL;
}

/* Authored Daikatana trigger volumes use bounds overlap, including brushes
   with zero collision contents. They are not solid geometry to trace against. */
qboolean DK_TriggerContact(const vec3_t mins, const vec3_t maxs, gentity_t *trigger) {
    int axis;
    if (!trigger->r.bmodel && (!trigger->classname || strncmp(trigger->classname, "trigger_", 8)))
        return trap_EntityContact(mins, maxs, trigger);
    for (axis = 0; axis < 3; ++axis)
        if (maxs[axis] + 1 < trigger->r.absmin[axis] || mins[axis] - 1 > trigger->r.absmax[axis])
            return qfalse;
    return qtrue;
}

/* e1m3b's laser buttons toggle a shared hurt field. The authored shutdown
   removes all three buttons but omits a reset for an already enabled field.
   Keep this correction scoped to that circuit, including older saved worlds. */
void DK_RepairDisabledHazards(const char *map) {
    gentity_t *hurt, *source;
    int i;
    static const char *names[] = {"laser1", "laser2", "laser3"};
    if (Q_stricmp(map, "e1m3b")) return;
    hurt = G_Find(NULL, FOFS(targetname), "laser_dam");
    if (!hurt || !Is(hurt, "trigger_hurt") || !hurt->r.contents) return;
    for (i = 0; i < ARRAY_LEN(names); ++i) {
        source = G_Find(NULL, FOFS(targetname), names[i]);
        if (source && Is(source, "func_button")) return;
    }
    hurt->r.contents = 0;
    trap_LinkEntity(hurt);
}

static void HurtUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    (void)other; (void)activator;
    if (!(entity->spawnflags & 1)) return;
    entity->r.contents = entity->r.contents ? 0 : CONTENTS_TRIGGER; trap_LinkEntity(entity);
}

static void HurtTouch(gentity_t *entity, gentity_t *other, trace_t *trace) {
    int list[MAX_GENTITIES], count, i;
    (void)trace;
    if (entity->targetname && !strcmp(entity->targetname, "laser_dam")) {
        char map[MAX_QPATH];
        trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
        DK_RepairDisabledHazards(map);
    }
    if (!(entity->r.contents & CONTENTS_TRIGGER)) return;
    if (!other->takedamage || other->health <= 0 || level.time < entity->dk.nextUse) return;
    entity->dk.nextUse = level.time + (int)(entity->wait * 1000);
    count = trap_EntitiesInBox(entity->r.absmin, entity->r.absmax, list, ARRAY_LEN(list));
    for (i = 0; i < count; ++i) {
        gentity_t *victim = &g_entities[list[i]];
        if (victim->inuse && victim->takedamage && victim->health > 0 &&
            DK_TriggerContact(victim->r.absmin, victim->r.absmax, entity))
            G_Damage(victim, entity, entity, NULL, NULL, entity->damage, DAMAGE_NO_KNOCKBACK, MOD_TRIGGER_HURT);
    }
    if (entity->noise_index) G_AddEvent(entity, EV_GENERAL_SOUND, entity->noise_index);
}

void DK_TouchActorTriggers(gentity_t *actor) {
    int list[MAX_GENTITIES], count, i;
    unsigned int id = actor->dk.id;
    trace_t trace;
    if (!actor->inuse || actor->health <= 0) return;
    memset(&trace, 0, sizeof(trace));
    count = trap_EntitiesInBox(actor->r.absmin, actor->r.absmax, list, ARRAY_LEN(list));
    for (i = 0; i < count; ++i) {
        gentity_t *trigger = &g_entities[list[i]];
        if (trigger->inuse && trigger->touch && (trigger->r.contents & CONTENTS_TRIGGER) &&
            DK_TriggerContact(actor->r.absmin, actor->r.absmax, trigger)) trigger->touch(trigger, actor, &trace);
        if (!actor->inuse || actor->dk.id != id || actor->health <= 0) return;
    }
}

static void PushUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    (void)other; (void)activator;
    if (!(entity->spawnflags & 2)) return;
    entity->r.contents = entity->r.contents ? 0 : CONTENTS_TRIGGER;
    entity->s.eType = entity->r.contents ? ET_PUSH_TRIGGER : ET_GENERAL;
    trap_LinkEntity(entity);
}

static void PushTouch(gentity_t *entity, gentity_t *other, trace_t *trace) {
    (void)trace;
    if (!other->client || other->health <= 0) return;
    if (entity->noise_index && other->client->ps.jumppad_ent != entity->s.number)
        G_Sound(other, CHAN_AUTO, entity->noise_index);
    BG_TouchJumpPad(&other->client->ps, &entity->s);
    if (entity->spawnflags & 1) { entity->r.contents = 0; entity->s.eType = ET_GENERAL; trap_UnlinkEntity(entity); }
}

static void PushAim(gentity_t *entity) {
    gentity_t *target = entity->target ? G_Find(NULL, FOFS(targetname), entity->target) : NULL;
    if (target) {
        vec3_t center, direction;
        float height, seconds;
        VectorAdd(entity->r.absmin, entity->r.absmax, center); VectorScale(center, 0.5f, center);
        VectorSubtract(target->r.currentOrigin, center, direction); height = direction[2];
        seconds = height > 0 ? sqrt(2 * height / g_gravity.value) : VectorLength(direction) / entity->speed;
        if (seconds < 0.1f) seconds = 0.1f;
        VectorScale(direction, 1 / seconds, entity->s.origin2); entity->s.origin2[2] += 0.5f * g_gravity.value * seconds;
    }
}

static void TimerThink(gentity_t *entity) {
    float variation;
    G_UseTargets(entity, DK_FindEntity(entity->dk.ownerId));
    if (!entity->inuse) return;
    if (entity->spawnflags & 2) { entity->dk.uses = 1; return; }
    entity->dk.soundRandom = entity->dk.soundRandom * 1664525u + 1013904223u;
    variation = ((entity->dk.soundRandom & 65535) / 32767.5f - 1) * entity->random;
    entity->nextthink = level.time + (int)(Com_Clamp(0.05f, 3600, entity->wait + variation) * 1000);
}

static void TimerUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (entity->dk.uses && (entity->spawnflags & 2)) return;
    entity->dk.ownerId = activator ? activator->dk.id : 0;
    if (entity->nextthink) entity->nextthink = 0;
    else entity->nextthink = level.time + 1;
}

static void InventoryUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    playerState_t *player;
    int weapon, i;
    (void)other;
    if (!activator || !activator->client || !entity->dk.mediaPath) return;
    player = &activator->client->ps; weapon = DK_WeaponId(entity->dk.mediaPath);
    if (!strcmp(entity->dk.mediaPath, "item_bomb")) player->dk3Quest &= ~1;
    else if (weapon) {
        player->dk3Inventory &= ~(1u << weapon); player->ammo[weapon] = 0;
        if (player->weapon == weapon) {
            player->weapon = 0;
            for (i = 1; i < DK_WEAPON_COUNT; ++i) if (DK_HasWeapon(player, i)) { player->weapon = i; break; }
        }
    } else {
        for (i = 0; i < DK_KEY_COUNT; ++i) if (!strcmp(dk_keyClasses[i], entity->dk.mediaPath)) break;
        if (i < DK_KEY_COUNT) player->dk3Keys &= ~(1u << i);
        else G_Printf("dk3: inventory trigger %u: unknown item %s\n", entity->dk.id, entity->dk.mediaPath);
    }
    G_UseTargets(entity, activator);
}

static void ConsoleUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    const char *command = entity->dk.mediaPath;
    (void)other;
    if (!activator || !activator->client || (entity->dk.uses && (entity->spawnflags & 1))) return;
    if (!strcmp(command, "disconnect")) trap_SendServerCommand(activator->s.number, "dk3_end");
    else if (!DK_ScriptWeaponCommand(activator, command))
        G_Printf("dk3: console trigger %u: unsupported operation %s\n", entity->dk.id, command);
    ++entity->dk.uses; G_UseTargets(entity, activator);
}

static void UseTouch(gentity_t *entity, gentity_t *other, trace_t *trace) {
    (void)trace;
    if (!other->client || other->health <= 0 || level.time < entity->dk.nextUse) return;
    entity->dk.nextUse = level.time + 500;
    if (entity->use) entity->use(entity, other, other);
}

static void EnvironmentUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    playerState_t *state;
    (void)other;
    if (!activator || !activator->client || activator->health <= 0) return;
    state = &activator->client->ps;
    if (state->dk3SoundEnvironment == entity->dk.environmentStyle &&
        state->dk3Reverb == entity->dk.environmentReverb && state->dk3SoundGain == entity->dk.environmentGain) return;
    state->dk3SoundEnvironment = entity->dk.environmentStyle;
    state->dk3Reverb = entity->dk.environmentReverb;
    state->dk3SoundGain = entity->dk.environmentGain;
    G_UseTargets(entity, activator);
}

static void EnvironmentTouch(gentity_t *entity, gentity_t *other, trace_t *trace) {
    (void)trace;
    if (level.time < entity->dk.nextUse) return;
    if (!other->client || other->health <= 0) return;
    entity->dk.nextUse = level.time + (int)(entity->wait * 1000);
    EnvironmentUse(entity, other, other);
}

static qboolean ToggleAllowed(gentity_t *entity, gentity_t *other) {
    if (!other->inuse || other->health <= 0) return qfalse;
    if (entity->spawnflags & 8) return DK_IsCompanion(other);
    if (other->client) return other->client->sess.sessionTeam != TEAM_SPECTATOR;
    return DK_IsCompanion(other) ? (entity->spawnflags & 4) != 0 : other->dk.actorKind && (entity->spawnflags & 2);
}

static void ToggleThink(gentity_t *entity) {
    int list[MAX_GENTITIES], count, i;
    gentity_t *occupant = NULL;
    count = trap_EntitiesInBox(entity->r.absmin, entity->r.absmax, list, ARRAY_LEN(list));
    for (i = 0; i < count; ++i) {
        gentity_t *other = &g_entities[list[i]];
        if (ToggleAllowed(entity, other) && DK_TriggerContact(other->r.absmin, other->r.absmax, entity)) { occupant = other; break; }
    }
    if (occupant && !entity->dk.action) { entity->dk.ownerId = occupant->dk.id; G_UseTargets(entity, occupant); }
    else if (!occupant && entity->dk.action && (entity->spawnflags & 1)) G_UseTargets(entity, DK_FindEntity(entity->dk.ownerId));
    entity->dk.action = occupant != NULL; entity->nextthink = level.time + 100;
}

qboolean DK_StopMonitor(gentity_t *player, qboolean force) {
    if (!player || !player->client || !player->dk.monitorId) return qfalse;
    if (!force && level.time < player->dk.monitorUnlock) return qtrue;
    player->dk.monitorId = 0; player->client->ps.dk3CameraActive = 0;
    player->client->ps.eFlags &= ~EF_NODRAW;
    return qtrue;
}

static void MonitorUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (!activator || !activator->client || activator->health <= 0 || activator->client->ps.dk3CameraActive) return;
    activator->dk.monitorId = entity->dk.id;
    activator->dk.monitorStart = level.time + entity->dk.delay;
    activator->dk.monitorUnlock = activator->dk.monitorStart + (int)(entity->wait * 1000);
    G_UseTargets(entity, activator);
}

void DK_RunMonitors(void) {
    int i;
    for (i = 0; i < level.maxclients; ++i) {
        gentity_t *player = &g_entities[i], *monitor, *camera, *target;
        playerState_t *state;
        vec3_t direction;
        if (!player->inuse || !player->client || !player->dk.monitorId || level.time < player->dk.monitorStart) continue;
        monitor = DK_FindEntity(player->dk.monitorId);
        camera = monitor && monitor->target ? G_Find(NULL, FOFS(targetname), monitor->target) : NULL;
        if (!camera) { DK_StopMonitor(player, qtrue); continue; }
        state = &player->client->ps; state->dk3CameraActive = 1; state->eFlags |= EF_NODRAW;
        VectorCopy(camera->r.currentOrigin, state->dk3CameraOrigin); VectorCopy(camera->s.angles, state->dk3CameraAngles);
        state->dk3CameraFov = monitor->dk.cameraFov;
        memset(state->dk3CameraBlend, 0, sizeof(state->dk3CameraBlend));
        target = camera->target ? G_Find(NULL, FOFS(targetname), camera->target) : NULL;
        if (target) { VectorSubtract(target->r.currentOrigin, camera->r.currentOrigin, direction); vectoangles(direction, state->dk3CameraAngles); }
    }
}

void DK_RestoreInteraction(gentity_t *entity) {
    if (Is(entity, "trigger_hurt")) { entity->use = HurtUse; entity->touch = HurtTouch; }
    else if (Is(entity, "trigger_push")) { entity->use = PushUse; entity->touch = PushTouch; entity->think = PushAim; }
    else if (Is(entity, "func_timer")) { entity->use = TimerUse; entity->think = TimerThink; }
    else if (Is(entity, "trigger_remove_inventory_item")) { entity->use = InventoryUse; entity->touch = UseTouch; }
    else if (Is(entity, "trigger_console")) { entity->use = ConsoleUse; entity->touch = UseTouch; }
    else if (Is(entity, "trigger_change_sfx")) { entity->use = EnvironmentUse; entity->touch = EnvironmentTouch; }
    else if (Is(entity, "trigger_toggle")) entity->think = ToggleThink;
    else if (Is(entity, "func_monitor")) entity->use = MonitorUse;
}

qboolean DK_SpawnInteraction(gentity_t *entity) {
    char *value;
    if (Is(entity, "info_camera") || Is(entity, "target_attractor")) {
        entity->r.svFlags |= SVF_NOCLIENT;
        if (Is(entity, "target_attractor")) G_SpawnInt("triggerindex", "0", &entity->count);
    }
    else if (Is(entity, "trigger_hurt")) {
        Brush(entity, (entity->spawnflags & 3) == 3 ? 0 : CONTENTS_TRIGGER, qfalse);
        G_SpawnInt("dmg", "5", &entity->damage); G_SpawnInt("damage", va("%d", entity->damage), &entity->damage);
        G_SpawnFloat("wait", "0.5", &entity->wait); if (entity->wait < 0.05f) entity->wait = 0.05f;
    } else if (Is(entity, "trigger_push")) {
        Brush(entity, entity->spawnflags & 4 ? 0 : CONTENTS_TRIGGER, qfalse);
        entity->s.eType = entity->r.contents ? ET_PUSH_TRIGGER : ET_GENERAL; entity->r.svFlags &= ~SVF_NOCLIENT;
        if (entity->speed <= 0) entity->speed = 1000;
        G_SetMovedir(entity->s.angles, entity->movedir); VectorScale(entity->movedir, entity->speed * 10, entity->s.origin2);
        entity->nextthink = level.time + FRAMETIME;
    } else if (Is(entity, "func_timer")) {
        entity->r.svFlags |= SVF_NOCLIENT; if (entity->wait < 0.05f) entity->wait = 1;
        entity->dk.soundRandom = entity->dk.id * 747796405u;
        if (entity->spawnflags & 1) entity->nextthink = level.time + (int)(entity->wait * 1000);
    } else if (Is(entity, "trigger_remove_inventory_item") || Is(entity, "trigger_console")) {
        G_SpawnString(Is(entity, "trigger_console") ? "command" : "item", "", &value);
        if (!*value && entity->message) value = entity->message;
        entity->dk.mediaPath = G_NewString(value); Brush(entity, CONTENTS_TRIGGER, qfalse);
    } else if (Is(entity, "trigger_change_sfx")) {
        float volume;
        G_SpawnInt("fxstyle", "0", &entity->dk.environmentStyle);
        G_SpawnFloat("reverb", entity->dk.environmentStyle ? "0.35" : "0", &entity->dk.environmentReverb);
        G_SpawnFloat("volume", "100", &volume); entity->dk.environmentGain = Com_Clamp(0, 1, volume / 100);
        entity->dk.environmentReverb = Com_Clamp(0, 1, entity->dk.environmentReverb);
        if (entity->dk.environmentStyle < 0 || entity->dk.environmentStyle > 4)
            G_Error("dk3: trigger_change_sfx %u: unsupported fxstyle %d", entity->dk.id, entity->dk.environmentStyle);
        G_SpawnFloat("wait", "0.2", &entity->wait); entity->wait = Com_Clamp(0, 3600, entity->wait);
        Brush(entity, CONTENTS_TRIGGER, qfalse);
    } else if (Is(entity, "trigger_toggle")) { Brush(entity, CONTENTS_TRIGGER, qfalse); entity->nextthink = level.time + 100; }
    else if (Is(entity, "func_monitor")) {
        Brush(entity, CONTENTS_SOLID, qtrue);
        G_SpawnFloat("fov", "90", &entity->dk.cameraFov); entity->dk.cameraFov = Com_Clamp(20, 160, entity->dk.cameraFov);
    } else return qfalse;
    G_SpawnString("sound", "", &value); if (*value) entity->noise_index = DK_SoundIndex(value);
    G_SetOrigin(entity, entity->s.origin); DK_RestoreInteraction(entity); trap_LinkEntity(entity);
    return qtrue;
}
