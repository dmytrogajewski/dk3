/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_save_schema.h"

#define CINE_SHOTS 256
#define CINE_SEGMENTS 8192
#define CINE_SOUNDS 4096
#define CINE_ACTORS 8192
#define CINE_TASKS 32768

typedef struct {
    float duration, fov[2], speed[2], color[2][4], position[12], angles[12];
    int fovFlags[2], speedFlags[2], colorFlags[2];
} segment_t;
typedef struct { char name[MAX_QPATH]; int loop, channel, played; float when; } sound_t;
typedef struct {
    int type, headFirst, headPoints;
    float when, attribute, duration;
    vec3_t destination, direction;
    char animation[32], use[32], sound[MAX_QPATH], uniqueId[64];
} task_t;
typedef struct {
    char name[MAX_QPATH], uniqueId[64];
    int first, count, cursor;
    float ready, headStart;
    int headTask;
    unsigned int entityId;
} cast_t;
typedef struct {
    float duration, pre, post, fov;
    int target, end, haveFov, sky, points, firstSegment, segments;
    int firstSound, sounds, firstActor, actors;
    char targetName[64], endName[64];
    vec3_t position, angles;
} shot_t;
typedef struct {
    shot_t shots[CINE_SHOTS];
    segment_t segments[CINE_SEGMENTS];
    sound_t sounds[CINE_SOUNDS];
    cast_t cast[CINE_ACTORS];
    task_t tasks[CINE_TASKS];
    int shotCount, segmentCount, soundCount, castCount, taskCount;
} cinematicData_t;
static cinematicData_t liveData, validationData;
static cinematicData_t *data = &liveData;
static char parseError[160];
static int active, shotIndex, lastTime, introStarted;
static float entityEndTime;
static float shotTime, playSpeed, currentFov, currentColor[4];
static float shotFov, shotColor[4];
static unsigned int triggerId, activatorId;
static unsigned int loopSounds[256];
static char cinematicName[MAX_QPATH], introName[MAX_QPATH], mapName[MAX_QPATH];
static char input[4 * 1024 * 1024 + 1];

static void Fail(const char *detail) {
    G_Error("dk3: map %s cinematic %s shot %d: %s", mapName, cinematicName, shotIndex, detail);
}

static void ParseError(const char *detail) {
    if (!*parseError) Q_strncpyz(parseError, detail, sizeof(parseError));
}

static void Text(char **cursor, char *out, int size) {
    char *token = COM_Parse(cursor);
    if (!*cursor || strlen(token) >= size) ParseError("missing or oversized field");
    Q_strncpyz(out, token, size);
}

static float ScalarBound(char **cursor, float bound) {
    char text[64], *p;
    float result;
    Text(cursor, text, sizeof(text));
    result = atof(text);
    if (!*text || Q_isnan(result) || fabs(result) > bound) { ParseError(va("invalid numeric field %.48s", text)); return 0; }
    for (p = text; *p; ++p) if (!((*p >= '0' && *p <= '9') || *p == '-' || *p == '+' || *p == '.' || *p == 'e' || *p == 'E'))
        ParseError("invalid numeric token");
    return result;
}

static float Scalar(char **cursor) { return ScalarBound(cursor, 10000000); }

static float TaskParameter(char **cursor, qboolean used) {
    /* The asset record reserves these fields for all task kinds; unused values
       include finite allocator-fill patterns. Only active operands have meaning. */
    float value = ScalarBound(cursor, used ? 10000000.0f : 3.402823466e38f);
    return used ? value : 0;
}

static int Count(char **cursor, int limit) {
    float number = Scalar(cursor);
    if (number < 0 || number > limit || (float)(int)number != number) { ParseError("array count exceeds limit"); return 0; }
    return (int)number;
}

static void Expect(char **cursor, const char *name) {
    char token[64];
    Text(cursor, token, sizeof(token));
    if (strcmp(token, name)) ParseError(va("expected %s, read %s", name, token));
}

static void Vector(char **cursor, float *value, int count) {
    int i;
    for (i = 0; i < count; ++i) value[i] = Scalar(cursor);
}

static void ReadShot(char **cursor, shot_t *shot) {
    int i, j;
    Expect(cursor, "shot");
    shot->duration = Scalar(cursor); shot->pre = Scalar(cursor); shot->post = Scalar(cursor);
    shot->target = Count(cursor, 1); shot->end = Count(cursor, 1);
    shot->haveFov = Count(cursor, 1); shot->fov = Scalar(cursor); shot->sky = Count(cursor, 65535);
    Count(cursor, 2); Count(cursor, 2); /* Endpoint velocity modes are already baked into spline coefficients. */
    Text(cursor, shot->targetName, sizeof(shot->targetName));
    Text(cursor, shot->endName, sizeof(shot->endName));
    Expect(cursor, "camera");
    shot->points = Count(cursor, CINE_SEGMENTS);
    shot->firstSegment = data->segmentCount;
    shot->segments = Count(cursor, CINE_SEGMENTS - data->segmentCount);
    if (shot->segments < shot->points - 1) ParseError("camera curve is incomplete");
    Vector(cursor, shot->position, 3); Vector(cursor, shot->angles, 3);
    for (i = 0; i < shot->segments; ++i) {
        segment_t *segment = &data->segments[data->segmentCount++];
        Expect(cursor, "segment");
        segment->duration = Scalar(cursor);
        for (j = 0; j < 2; ++j) segment->fovFlags[j] = Count(cursor, 1);
        Vector(cursor, segment->fov, 2);
        for (j = 0; j < 2; ++j) segment->speedFlags[j] = Count(cursor, 1);
        Vector(cursor, segment->speed, 2);
        for (j = 0; j < 2; ++j) segment->colorFlags[j] = Count(cursor, 1);
        Vector(cursor, segment->color[0], 4); Vector(cursor, segment->color[1], 4);
        Vector(cursor, segment->position, 12); Vector(cursor, segment->angles, 12);
        if (segment->duration < 0) ParseError("negative curve duration");
    }
    Expect(cursor, "sounds");
    shot->firstSound = data->soundCount;
    shot->sounds = Count(cursor, CINE_SOUNDS - data->soundCount);
    for (i = 0; i < shot->sounds; ++i) {
        sound_t *sound = &data->sounds[data->soundCount++];
        Text(cursor, sound->name, sizeof(sound->name));
        sound->loop = Count(cursor, 1); sound->channel = Count(cursor, 255);
        sound->when = Scalar(cursor); sound->played = 0;
    }
    Expect(cursor, "entities");
    shot->firstActor = data->castCount;
    shot->actors = Count(cursor, CINE_ACTORS - data->castCount);
    for (i = 0; i < shot->actors; ++i) {
        cast_t *actor = &data->cast[data->castCount++];
        Text(cursor, actor->name, sizeof(actor->name));
        Text(cursor, actor->uniqueId, sizeof(actor->uniqueId));
        actor->first = data->taskCount; actor->count = Count(cursor, CINE_TASKS - data->taskCount);
        actor->cursor = 0; actor->ready = 0; actor->entityId = 0; actor->headTask = -1;
        for (j = 0; j < actor->count; ++j) {
            task_t *task = &data->tasks[data->taskCount++];
            int axis;
            task->type = Count(cursor, 20); task->when = Scalar(cursor);
            for (axis = 0; axis < 3; ++axis) task->destination[axis] = TaskParameter(cursor,
                task->type == 1 || task->type == 3 || task->type == 10 || task->type == 18);
            for (axis = 0; axis < 3; ++axis) task->direction[axis] = TaskParameter(cursor,
                task->type == 2 || task->type == 3 || task->type == 10 || task->type == 18);
            task->attribute = TaskParameter(cursor, task->type >= 6 && task->type <= 9);
            task->duration = TaskParameter(cursor, task->type == 17);
            Text(cursor, task->animation, sizeof(task->animation));
            Text(cursor, task->use, sizeof(task->use));
            Text(cursor, task->sound, sizeof(task->sound));
            Text(cursor, task->uniqueId, sizeof(task->uniqueId));
            if (task->type == 14) {
                int point;
                Expect(cursor, "head"); task->headPoints = Count(cursor, CINE_SEGMENTS - data->segmentCount);
                Vector(cursor, task->direction, 3); task->headFirst = data->segmentCount;
                for (point = 1; point < task->headPoints; ++point) {
                    segment_t *segment = &data->segments[data->segmentCount++];
                    segment->duration = 0.2f; Vector(cursor, segment->angles, 12);
                }
            }
        }
    }
}

void DK_InitCinematics(void) {
    active = introStarted = 0;
    memset(loopSounds, 0, sizeof(loopSounds));
    *introName = *cinematicName = 0;
    trap_Cvar_VariableStringBuffer("mapname", mapName, sizeof(mapName));
}

void DK_Worldspawn(void) {
    char *value;
    char styles[257];
    memset(styles, '*', 256); styles[256] = 0;
    trap_SetConfigstring(CS_DK3_LIGHTSTYLES, styles);
    trap_SetConfigstring(CS_DK3_SKY, "1");
    DK_WorldMusic();
    G_SpawnString("cinematic_intro", "", &value);
    Q_strncpyz(introName, value, sizeof(introName));
}

static qboolean LoadData(const char *name) {
    char path[MAX_QPATH], *cursor;
    fileHandle_t file;
    int length, i;
    const char *p;
    for (p = name; *p; ++p) if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
        (*p >= '0' && *p <= '9') || *p == '_')) return qfalse;
    if (!*name || strlen(name) > 40) return qfalse;
    Com_sprintf(path, sizeof(path), "dk3/cinematics/%s.cfg", name); Q_strlwr(path);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length <= 0 || length >= sizeof(input)) {
        if (file) trap_FS_FCloseFile(file);
        G_Printf("dk3: map %s cinematic %s: missing or oversized %s\n", mapName, name, path);
        return qfalse;
    }
    trap_FS_Read(input, length, file); trap_FS_FCloseFile(file); input[length] = 0;
    cursor = input;
    data->segmentCount = data->soundCount = data->castCount = data->taskCount = 0;
    *parseError = 0;
    Expect(&cursor, "dk3_cinematic"); Expect(&cursor, "1");
    data->shotCount = Count(&cursor, CINE_SHOTS);
    for (i = 0; i < data->shotCount; ++i) ReadShot(&cursor, &data->shots[i]);
    if (*COM_Parse(&cursor)) ParseError("trailing program data");
    if (!data->shotCount || *parseError) return qfalse;
    return qtrue;
}

qboolean DK_StartCinematic(const char *name, gentity_t *trigger, gentity_t *activator) {
    if (active || g_gametype.integer != GT_SINGLE_PLAYER) return qfalse;
    if (g_entities[0].client) DK_StopMonitor(&g_entities[0], qtrue);
    data = &liveData;
    if (!LoadData(name)) {
        G_Printf("dk3: cinematic %s could not load: %s\n", name, parseError);
        return qfalse;
    }
    Q_strncpyz(cinematicName, name, sizeof(cinematicName));
    shotIndex = 0;
    shotTime = 0; entityEndTime = -1; playSpeed = 1; currentFov = 90;
    memset(currentColor, 0, sizeof(currentColor));
    memset(shotColor, 0, sizeof(shotColor));
    shotFov = 90;
    triggerId = trigger ? trigger->dk.id : 0;
    activatorId = activator ? activator->dk.id : 0;
    lastTime = level.time; active = 1;
    /* Gold freezes and makes the gameplay player nonsolid before playback. */
    if (g_entities[0].client) {
        gentity_t *player = &g_entities[0];
        player->client->ps.dk3CameraActive = 1;
        player->client->ps.pm_type = PM_FREEZE;
        player->client->ps.eFlags |= EF_NODRAW;
        VectorClear(player->client->ps.velocity);
        player->r.contents = 0;
        trap_LinkEntity(player);
    }
    return qtrue;
}

static gentity_t *CastEntity(cast_t *actor) {
    gentity_t *entity = DK_FindEntity(actor->entityId);
    int i;
    if (!entity) entity = DK_FindNamed(*actor->uniqueId ? actor->uniqueId : actor->name);
    if (!entity && !*actor->uniqueId) for (i = MAX_CLIENTS; i < level.num_entities; ++i)
        if (g_entities[i].inuse && g_entities[i].classname && !Q_stricmp(g_entities[i].classname, actor->name)) {
            entity = &g_entities[i]; break;
        }
    if (entity) { actor->entityId = entity->dk.id; entity->dk.cinematicControlled = 1; }
    return entity;
}

static gentity_t *TaskEntity(cast_t *actor, task_t *task) {
    const char *id = *task->uniqueId ? task->uniqueId : actor->uniqueId;
    gentity_t *entity = *id ? DK_FindNamed(id) : CastEntity(actor);
    int i;
    if (!entity && task->type != 18) {
        /* Some shipped records disagree about an actor's ID (intro's oka1 /
           osa1). Class fallback is safe only when there is one matching actor. */
        for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
            gentity_t *candidate = &g_entities[i];
            if (!candidate->inuse || !candidate->classname || Q_stricmp(candidate->classname, actor->name)) continue;
            if (entity) return NULL;
            entity = candidate;
        }
        if (entity && actor->entityId != entity->dk.id)
            G_Printf("dk3: map %s cinematic %s shot %d: cast %s ID %s resolved to sole class instance %u\n",
                mapName, cinematicName, shotIndex, actor->name, id, entity->dk.id);
    }
    if (entity) { actor->entityId = entity->dk.id; entity->dk.cinematicControlled = 1; }
    return entity;
}

static void Task(cast_t *actor, task_t *task) {
    gentity_t *entity = TaskEntity(actor, task), *target;
    int duration;
    if (task->type == 18 && !entity) {
        entity = G_Spawn(); entity->classname = G_NewString(actor->name);
        entity->dk.uniqueid = G_NewString(*task->uniqueId ? task->uniqueId : actor->uniqueId);
        VectorCopy(task->destination, entity->s.origin);
        VectorCopy(task->direction, entity->s.angles);
        if (!DK_SpawnActor(entity)) { G_FreeEntity(entity); Fail(va("unsupported cast actor %s", actor->name)); }
        entity->dk.cinematicOwned = entity->dk.cinematicControlled = 1;
        DK_ActorHold(entity);
        actor->entityId = entity->dk.id;
    }
    if (task->type == 18 && entity) {
        G_SetOrigin(entity, task->destination);
        VectorCopy(task->direction, entity->s.angles);
        trap_LinkEntity(entity);
    }
    if (task->type == 0 || task->type == 18) return;
    if (task->type == 13) { DK_FireNamed(task->use, entity, DK_FindEntity(activatorId)); return; }
    if (!entity) { Fail(va("task %d requires missing actor %s (%s)", task->type, actor->name, actor->uniqueId)); return; }
    switch (task->type) {
        case 1: case 3: DK_ActorMoveTo(entity, task->destination);
            if (task->type == 3) { VectorCopy(task->direction, entity->dk.turnGoal); entity->dk.turnActive = 1; }
            break;
        case 2: VectorCopy(task->direction, entity->dk.turnGoal); entity->dk.turnActive = 1; break;
        case 4:
            entity->dk.savedSpeed = entity->dk.runSpeed;
            entity->dk.savedWalkSpeed = entity->dk.walkSpeed;
            entity->dk.savedYawSpeed = entity->dk.yawSpeed;
            break;
        case 5:
            entity->dk.runSpeed = entity->dk.savedSpeed;
            entity->dk.walkSpeed = entity->dk.savedWalkSpeed;
            entity->dk.yawSpeed = entity->dk.savedYawSpeed;
            break;
        case 6: entity->dk.runSpeed = Com_Clamp(1, 2000, task->attribute); break;
        case 7: entity->dk.walkSpeed = Com_Clamp(1, 2000, task->attribute); break;
        case 8: entity->dk.yawSpeed = Com_Clamp(1, 3600, task->attribute); break;
        case 9: actor->ready = shotTime + task->attribute; break;
        case 10:
            G_SetOrigin(entity, task->destination);
            VectorCopy(task->direction, entity->s.angles); trap_LinkEntity(entity); break;
        case 11: entity->dk.movingAnimation = "runa"; entity->dk.speedOverride = entity->dk.runSpeed; break;
        case 12: entity->dk.movingAnimation = "walka"; entity->dk.speedOverride = entity->dk.walkSpeed; break;
        case 14:
            actor->headTask = (int)(task - data->tasks); actor->headStart = shotTime;
            actor->ready = shotTime + task->headPoints * 0.2f;
            break;
        case 15: case 16:
            if (!*task->animation) { DK_ActorHold(entity); break; }
            duration = DK_ActorAnimate(entity, task->animation, 1);
            if (duration < 0) {
                G_Printf("dk3: map %s cinematic %s shot %d actor %s (%s) task %d: model %s lacks animation %s; holding pose\n",
                    mapName, cinematicName, shotIndex, actor->name, actor->uniqueId, task->type, entity->model, task->animation);
                DK_ActorHold(entity);
                break;
            }
            if (task->type == 15) actor->ready = shotTime + duration / 1000.0f;
            else entity->dk.animationLoop = qtrue;
            break;
        case 17:
            G_Sound(entity, CHAN_VOICE, DK_SoundIndex(task->sound));
            actor->ready = shotTime + task->duration; break;
        case 19: G_FreeEntity(entity); actor->entityId = 0; break;
        case 20: entity->dk.moveActive = 0; entity->enemy = NULL; entity->dk.pathTarget = NULL; break;
        default: Fail(va("unsupported task %d", task->type));
    }
    target = DK_FindEntity(actor->entityId);
    if (target) VectorCopy(target->s.angles, target->r.currentAngles);
}

static float Blend(float start, float end, float fraction) { return start + (end - start) * fraction; }

static void Camera(shot_t *shot, vec3_t position, vec3_t angles) {
    float time = shotTime - shot->pre;
    int i, axis;
    VectorCopy(shot->position, position); VectorCopy(shot->angles, angles);
    currentFov = shotFov;
    memcpy(currentColor, shotColor, sizeof(currentColor));
    playSpeed = 1;
    if (shot->haveFov) currentFov = shot->fov;
    for (i = 0; i < shot->points - 1; ++i) {
        segment_t *segment = &data->segments[shot->firstSegment + i];
        float t = Com_Clamp(0, segment->duration, time);
        float fraction = segment->duration > 0 ? t / segment->duration : 1;
        for (axis = 0; axis < 3; ++axis) {
            const float *p = &segment->position[axis * 4], *a = &segment->angles[axis * 4];
            position[axis] = ((p[0] * t + p[1]) * t + p[2]) * t + p[3];
            angles[axis] = ((a[0] * t + a[1]) * t + a[2]) * t + a[3];
        }
        if (segment->fovFlags[0]) currentFov = segment->fov[0];
        if (segment->fovFlags[1]) currentFov = Blend(currentFov, segment->fov[1], fraction);
        if (segment->speedFlags[0]) playSpeed = segment->speed[0];
        if (segment->speedFlags[1]) playSpeed = Blend(playSpeed, segment->speed[1], fraction);
        for (axis = 0; axis < 4; ++axis) {
            if (segment->colorFlags[0]) currentColor[axis] = segment->color[0][axis] / 255;
            if (segment->colorFlags[1]) currentColor[axis] = Blend(currentColor[axis], segment->color[1][axis] / 255, fraction);
        }
        if (time <= segment->duration) break;
        time -= segment->duration;
    }
    if (shot->target) {
        gentity_t *target = DK_FindNamed(shot->targetName);
        if (target) { vec3_t direction; VectorSubtract(target->r.currentOrigin, position, direction); vectoangles(direction, angles); }
    }
}

void DK_StopCinematic(qboolean completed) {
    int i, triggerCount = 0;
    unsigned int targets[MAX_GENTITIES], finishedTrigger = triggerId, finishedActivator = activatorId;
    char finishedName[MAX_QPATH];
    if (!active) return;
    Q_strncpyz(finishedName, cinematicName, sizeof(finishedName));
    active = 0;
    for (i = 0; i < ARRAY_LEN(loopSounds); ++i) {
        gentity_t *sound = DK_FindEntity(loopSounds[i]);
        if (sound) G_FreeEntity(sound);
        loopSounds[i] = 0;
    }
    for (i = 0; i < level.num_entities; ++i) {
        gentity_t *entity = &g_entities[i];
        if (!entity->inuse) continue;
        if (entity->client) {
            entity->client->ps.dk3CameraActive = 0;
            entity->client->ps.eFlags &= ~EF_NODRAW;
            entity->r.contents = entity->health > 0 ? CONTENTS_BODY : CONTENTS_CORPSE;
            trap_LinkEntity(entity);
        }
        if (entity->dk.cinematicControlled) {
            entity->dk.cinematicControlled = 0;
            entity->dk.moveActive = entity->dk.turnActive = 0;
        }
        if (entity->dk.cinematicOwned || (completed && entity->dk.cineKill && !Q_stricmp(entity->dk.cineKill, finishedName))) {
            G_FreeEntity(entity); continue;
        }
        if (completed && entity->dk.cineTrigger && !Q_stricmp(entity->dk.cineTrigger, finishedName) && entity->use)
            targets[triggerCount++] = entity->dk.id;
    }
    G_Printf("dk3: map %s cinematic %s: %s\n", mapName, finishedName, completed ? "completed" : "stopped");
    for (i = 0; i < triggerCount; ++i) {
        gentity_t *entity = DK_FindEntity(targets[i]);
        if (entity && entity->use) entity->use(entity, DK_FindEntity(finishedTrigger), DK_FindEntity(finishedActivator));
    }
    if (completed) DK_CinematicFinished(DK_FindEntity(finishedTrigger), DK_FindEntity(finishedActivator));
}

void DK_RunCinematic(void) {
    shot_t *shot;
    vec3_t position, angles;
    int i, allDone = 1, namedDone = 0;
    if (!introStarted && g_entities[0].client && g_entities[0].client->pers.connected == CON_CONNECTED) {
        introStarted = 1;
        if (*introName) DK_StartCinematic(introName, NULL, &g_entities[0]);
    }
    if (!active) return;
    shotTime += (level.time - lastTime) * Com_Clamp(0.01f, 8, playSpeed) / 1000.0f;
    lastTime = level.time; shot = &data->shots[shotIndex];
    if (shot->sky >= 1 && shot->sky <= 5) {
        char sky[8];
        trap_GetConfigstring(CS_DK3_SKY, sky, sizeof(sky));
        if (atoi(sky) != shot->sky) trap_SetConfigstring(CS_DK3_SKY, va("%d", shot->sky));
    }
    for (i = 0; i < shot->sounds; ++i) {
        sound_t *sound = &data->sounds[shot->firstSound + i];
        if (!sound->played && sound->when <= shotTime) {
            gentity_t *previous = DK_FindEntity(loopSounds[sound->channel]);
            if (previous) G_FreeEntity(previous);
            loopSounds[sound->channel] = 0;
            if (sound->loop) {
                gentity_t *emitter = G_Spawn();
                emitter->classname = "dk3_cinematic_sound";
                G_SetOrigin(emitter, g_entities[0].r.currentOrigin);
                emitter->s.loopSound = DK_SoundIndex(sound->name);
                emitter->r.svFlags |= SVF_BROADCAST;
                trap_LinkEntity(emitter);
                loopSounds[sound->channel] = emitter->dk.id;
            } else {
                gentity_t *event = G_TempEntity(g_entities[0].r.currentOrigin, EV_GLOBAL_SOUND);
                event->s.eventParm = DK_SoundIndex(sound->name); event->r.svFlags |= SVF_BROADCAST;
            }
            sound->played = 1;
        }
    }
    for (i = 0; i < shot->actors; ++i) {
        cast_t *actor = &data->cast[shot->firstActor + i];
        gentity_t *entity = CastEntity(actor);
        if (entity && actor->headTask >= 0) {
            task_t *head = &data->tasks[actor->headTask];
            float elapsed = shotTime - actor->headStart;
            int part = (int)(elapsed / 0.2f), axis;
            VectorCopy(head->direction, entity->s.angles);
            if (head->headPoints > 1) {
                float t;
                segment_t *segment;
                if (part >= head->headPoints - 1) { part = head->headPoints - 2; t = 0.2f; }
                else t = elapsed - part * 0.2f;
                segment = &data->segments[head->headFirst + part];
                for (axis = 0; axis < 3; ++axis) {
                    float *curve = &segment->angles[axis * 4];
                    entity->s.angles[axis] = ((curve[0] * t + curve[1]) * t + curve[2]) * t + curve[3];
                }
            }
            VectorCopy(entity->s.angles, entity->r.currentAngles);
            if (shotTime >= actor->ready) actor->headTask = -1;
        }
        while (actor->cursor < actor->count && actor->ready <= shotTime && (!entity || (!entity->dk.moveActive && !entity->dk.turnActive))) {
            task_t *task = &data->tasks[actor->first + actor->cursor];
            if (task->when >= 0 && task->when > shotTime) break;
            ++actor->cursor; Task(actor, task); entity = CastEntity(actor);
        }
        {
            int done = actor->cursor == actor->count && actor->ready <= shotTime &&
                (!entity || (!entity->dk.moveActive && !entity->dk.turnActive));
            if (!done) allDone = 0;
            if (done && (!Q_stricmp(shot->endName, actor->name) || !Q_stricmp(shot->endName, actor->uniqueId))) namedDone = 1;
        }
    }
    Camera(shot, position, angles);
    for (i = 0; i < level.maxclients; ++i) if (g_entities[i].inuse && g_entities[i].client) {
        playerState_t *ps = &g_entities[i].client->ps;
        ps->dk3CameraActive = 1; ps->pm_type = PM_FREEZE; ps->eFlags |= EF_NODRAW;
        VectorCopy(position, ps->dk3CameraOrigin); VectorCopy(angles, ps->dk3CameraAngles);
        ps->dk3CameraFov = currentFov; memcpy(ps->dk3CameraBlend, currentColor, sizeof(currentColor));
    }
    if (shot->end && entityEndTime < 0 && (*shot->endName ? namedDone : allDone)) entityEndTime = shotTime;
    if (shot->end ? (entityEndTime >= 0 && shotTime >= entityEndTime + shot->post) :
        shotTime >= shot->pre + shot->duration + shot->post) {
        if (++shotIndex == data->shotCount) DK_StopCinematic(qtrue);
        else {
            shotTime = 0; entityEndTime = -1; playSpeed = 1;
            shotFov = currentFov;
            memcpy(shotColor, currentColor, sizeof(shotColor));
        }
    }
}

void DK_SkipCinematic(void) {
    int i;
    if (!active) return;
    for (; shotIndex < data->shotCount; ++shotIndex) {
        shot_t *shot = &data->shots[shotIndex];
        float end = shot->pre + shot->duration + shot->post;
        /* Advance pending actor queues in their authored order. Executing all
           records blindly also executes commands beyond the cut: intro shot 80
           contains removals at 5.5 seconds in a 2.8-second shot. */
        for (;;) {
            cast_t *next = NULL;
            gentity_t *entity;
            float when = 1e30f;
            for (i = 0; i < shot->actors; ++i) {
                cast_t *actor = &data->cast[shot->firstActor + i];
                task_t *task;
                float ready;
                if (actor->cursor == actor->count) continue;
                task = &data->tasks[actor->first + actor->cursor];
                ready = MAX(shotTime, MAX(actor->ready, task->when));
                if (ready < when && (shot->end || ready <= end + 0.001f)) { next = actor; when = ready; }
            }
            if (!next) break;
            shotTime = when;
            Task(next, &data->tasks[next->first + next->cursor++]);
            entity = DK_FindEntity(next->entityId);
            if (entity && entity->dk.moveActive) {
                G_SetOrigin(entity, entity->dk.moveGoal); entity->dk.moveActive = 0; trap_LinkEntity(entity);
            }
            if (entity && entity->dk.turnActive) {
                VectorCopy(entity->dk.turnGoal, entity->s.angles);
                VectorCopy(entity->s.angles, entity->r.currentAngles); entity->dk.turnActive = 0;
            }
        }
        shotTime = 0;
    }
    DK_StopCinematic(qtrue);
}

typedef struct {
    char *name;
    int active, intro, shot, trigger, activator;
    float entityEnd, elapsed, speed, fov, color[4], baseFov, baseColor[4];
    int loops[256];
} savedCinema_t;
#define CIN_FIELD(field, type, count) {#field, type, offsetof(savedCinema_t, field), count, qfalse}
static const dkSaveMember_t cinemaMembers[] = {
    CIN_FIELD(name, DK_SAVE_TEXT, 1), CIN_FIELD(active, DK_SAVE_INT, 1), CIN_FIELD(intro, DK_SAVE_INT, 1),
    CIN_FIELD(shot, DK_SAVE_INT, 1), CIN_FIELD(trigger, DK_SAVE_INT, 1), CIN_FIELD(activator, DK_SAVE_INT, 1),
    {"entity_end", DK_SAVE_FLOAT, offsetof(savedCinema_t, entityEnd), 1, qfalse},
    CIN_FIELD(elapsed, DK_SAVE_FLOAT, 1), CIN_FIELD(speed, DK_SAVE_FLOAT, 1), CIN_FIELD(fov, DK_SAVE_FLOAT, 1),
    CIN_FIELD(color, DK_SAVE_FLOAT, 4), {"base_fov", DK_SAVE_FLOAT, offsetof(savedCinema_t, baseFov), 1, qfalse}, {"base_color", DK_SAVE_FLOAT, offsetof(savedCinema_t, baseColor), 4, qfalse},
    {"loops_0", DK_SAVE_INT, offsetof(savedCinema_t, loops[0]), 64, qfalse}, {"loops_64", DK_SAVE_INT, offsetof(savedCinema_t, loops[64]), 64, qfalse},
    {"loops_128", DK_SAVE_INT, offsetof(savedCinema_t, loops[128]), 64, qfalse}, {"loops_192", DK_SAVE_INT, offsetof(savedCinema_t, loops[192]), 64, qfalse}
};
#undef CIN_FIELD
static const dkSaveMember_t castMembers[] = {
    {"head_task", DK_SAVE_INT, offsetof(cast_t, headTask), 1, qfalse},
    {"head_start", DK_SAVE_FLOAT, offsetof(cast_t, headStart), 1, qfalse},
    {"cursor", DK_SAVE_INT, offsetof(cast_t, cursor), 1, qfalse},
    {"ready", DK_SAVE_FLOAT, offsetof(cast_t, ready), 1, qfalse},
    {"entity", DK_SAVE_INT, offsetof(cast_t, entityId), 1, qfalse}
};

qboolean DK_WriteCinematicState(dkSaveWriter_t *writer) {
    savedCinema_t saved;
    int i;
    memset(&saved, 0, sizeof(saved));
    saved.name = active ? cinematicName : NULL;
    saved.active = active; saved.intro = introStarted; saved.shot = active ? shotIndex : 0;
    saved.trigger = DK_FindEntity(triggerId) ? triggerId : 0; saved.activator = DK_FindEntity(activatorId) ? activatorId : 0;
    saved.entityEnd = entityEndTime; saved.elapsed = shotTime; saved.speed = playSpeed; saved.fov = currentFov; saved.baseFov = shotFov;
    memcpy(saved.color, currentColor, sizeof(saved.color)); memcpy(saved.baseColor, shotColor, sizeof(saved.baseColor));
    for (i = 0; i < 256; ++i) saved.loops[i] = DK_FindEntity(loopSounds[i]) ? loopSounds[i] : 0;
    if (!DK_SaveRecord(writer, "cinema", 0) || !DK_SaveObject(writer, &saved, cinemaMembers, ARRAY_LEN(cinemaMembers))) return qfalse;
    if (!active) return qtrue;
    for (i = 0; i < data->castCount; ++i) {
        cast_t state = data->cast[i];
        if (!DK_FindEntity(state.entityId)) state.entityId = 0;
        if (!DK_SaveRecord(writer, "cinema_cast", i + 1) || !DK_SaveObject(writer, &state, castMembers, ARRAY_LEN(castMembers))) return qfalse;
    }
    for (i = 0; i < data->soundCount; ++i)
        if (!DK_SaveRecord(writer, "cinema_sound", i + 1) || !DK_SaveInts(writer, "played", &data->sounds[i].played, 1)) return qfalse;
    return qtrue;
}

qboolean DK_ReadCinematicState(dkSaveReader_t *reader, const char *kind, unsigned int id, qboolean apply) {
    if (!strcmp(kind, "cinema")) {
        savedCinema_t saved;
        char storage[256];
        dkSaveStrings_t strings = {storage, sizeof(storage), 0};
        int i;
        memset(&saved, 0, sizeof(saved));
        if (id || !DK_ReadObject(reader, &saved, cinemaMembers, ARRAY_LEN(cinemaMembers), &strings) ||
            saved.active < 0 || saved.active > 1 || saved.intro < 0 || saved.intro > 1 ||
            !DK_SaveReferenceExists(saved.trigger) || !DK_SaveReferenceExists(saved.activator)) return qfalse;
        for (i = 0; i < 256; ++i) if (!DK_SaveReferenceExists(saved.loops[i])) return qfalse;
        if (saved.active) {
            qboolean loaded;
            data = apply ? &liveData : &validationData;
            loaded = saved.name && LoadData(saved.name);
            data = &liveData;
            if (!loaded || saved.shot < 0 || saved.shot >= (apply ? liveData.shotCount : validationData.shotCount) ||
                saved.elapsed < 0 || saved.elapsed > 86400 || saved.speed < 0 || saved.speed > 100 ||
                saved.fov < 1 || saved.fov > 180 || saved.baseFov < 1 || saved.baseFov > 180) return qfalse;
        } else if (!apply) memset(&validationData, 0, sizeof(validationData));
        if (apply) {
            active = saved.active; introStarted = saved.intro; shotIndex = saved.shot;
            Q_strncpyz(cinematicName, saved.name ? saved.name : "", sizeof(cinematicName));
            entityEndTime = saved.entityEnd; shotTime = saved.elapsed; playSpeed = saved.speed; currentFov = saved.fov; shotFov = saved.baseFov;
            memcpy(currentColor, saved.color, sizeof(currentColor)); memcpy(shotColor, saved.baseColor, sizeof(shotColor));
            triggerId = saved.trigger; activatorId = saved.activator;
            memcpy(loopSounds, saved.loops, sizeof(loopSounds)); lastTime = level.time;
        }
        return qtrue;
    }
    if (!strcmp(kind, "cinema_cast")) {
        cinematicData_t *context = apply ? &liveData : &validationData;
        cast_t state;
        memset(&state, 0, sizeof(state)); state.headTask = -1;
        if (!id || id > context->castCount || !DK_ReadObject(reader, &state, castMembers, ARRAY_LEN(castMembers), NULL) ||
            state.headTask < -1 || state.headTask >= context->taskCount ||
            (state.headTask >= 0 && context->tasks[state.headTask].type != 14) ||
            state.cursor < 0 || state.cursor > context->cast[id - 1].count || state.ready < 0 || state.ready > 86400 ||
            !DK_SaveReferenceExists(state.entityId)) return qfalse;
        if (apply) {
            context->cast[id - 1].headTask = state.headTask;
            context->cast[id - 1].headStart = state.headStart;
            context->cast[id - 1].cursor = state.cursor;
            context->cast[id - 1].ready = state.ready;
            context->cast[id - 1].entityId = state.entityId;
        }
        return qtrue;
    }
    if (!strcmp(kind, "cinema_sound")) {
        cinematicData_t *context = apply ? &liveData : &validationData;
        dkSaveField_t field;
        if (!id || id > context->soundCount || !DK_SaveNextField(reader, &field) || strcmp(field.name, "played") ||
            field.type != DK_SAVE_INT || field.count != 1 || reader->fieldsLeft || DK_SaveInt(&field, 0) < 0 || DK_SaveInt(&field, 0) > 1) return qfalse;
        if (apply) context->sounds[id - 1].played = DK_SaveInt(&field, 0);
        return qtrue;
    }
    return qfalse;
}

qboolean DK_CinematicSaveCounts(int actors, int soundStates) {
    return actors == validationData.castCount && soundStates == validationData.soundCount;
}
