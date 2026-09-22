/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_tables.h"
#include "../qcommon/qfiles.h"
#include "dk_weapons.h"
#include "dk_effects.h"
#include "../botlib/be_aas.h"

#define DK_ACTOR_DEFINITIONS 128
#define DK_ANIMATIONS 256
#define DK_ACTOR_TICK 50
#define DK_STEP_HEIGHT 18
#define DK_POD_HATCH_RANGE 200
#define DK_POD_NOTICE_RANGE 512

typedef struct {
    char name[32], sounds[2][MAX_QPATH];
    int first, last, fps, soundFrames[2], strikes[2], weight, soundChance;
} dkAnimation_t;
typedef struct {
    int damage, randomDamage, weapon;
    float range, speed, spreadX, spreadZ;
    vec3_t offset;
} dkActorAttack_t;
typedef struct {
    char classname[64], model[MAX_QPATH], baseModel[MAX_QPATH];
    int health, frames, animationCount;
    float speed, walkSpeed, sightRange, fov, scale;
    dkActorAttack_t attacks[3];
    vec3_t mins, maxs, modelScale;
    float *frameBottoms;
    qboolean flying, swimming, turret, companion, civilian;
    dkAnimation_t animations[DK_ANIMATIONS];
    dkAnimation_t sightSounds[8];
    int sightSoundCount;
} dkActorInfo_t;
static dkActorInfo_t definitions[DK_ACTOR_DEFINITIONS];
static int definitionCount;

static const char *CinematicModelName(const char *classname) {
    if (!strcmp(classname, "cine_superfly")) return "super";
    if (!strcmp(classname, "cine_charon")) return "char";
    if (!strcmp(classname, "cine_gharroth")) return "ghar";
    if (!strcmp(classname, "cine_pgharroth")) return "pghar";
    if (!strcmp(classname, "cine_toshiro")) return "tosh";
    return classname + 5;
}

static void ChapterModel(const char *classname, const char *base, const char *map, char out[MAX_QPATH]) {
    char candidate[MAX_QPATH], metadata[MAX_QPATH];
    fileHandle_t file;
    int attempt, length;
    const char *name;
    Q_strncpyz(out, base, MAX_QPATH);
    if (strncmp(classname, "cine_", 5)) return;
    name = CinematicModelName(classname);
    for (attempt = 0; attempt < 3; ++attempt) {
        length = attempt ? strlen(map) : 4;
        if (attempt == 1 && strlen(map) <= 4) continue;
        if (attempt == 2) Com_sprintf(candidate, sizeof(candidate), "models/cinematic/c_%s.dkm", name);
        else Com_sprintf(candidate, sizeof(candidate), "models/cinematic/c_%s_%.*s.dkm", name, length, map);
        Com_sprintf(metadata, sizeof(metadata), "%s.anim", candidate);
        if (trap_FS_FOpenFile(metadata, &file, FS_READ) >= 0) {
            trap_FS_FCloseFile(file); Q_strncpyz(out, candidate, MAX_QPATH);
            return;
        }
    }
}

enum { ACTOR_IDLE, ACTOR_CHASE, ACTOR_ATTACK, ACTOR_PAIN, ACTOR_DEAD, ACTOR_WAIT, ACTOR_DOWN };

/* Collision at death follows the supplied final pose, rather than retaining
   the live actor's hull below a body whose mesh has folded upward. */
static void ReadFrameBounds(dkActorInfo_t *info) {
    md3Header_t header;
    md3Frame_t frame;
    fileHandle_t file;
    char path[MAX_QPATH];
    int length, count, offset, i;
    if (Q_stricmp(COM_GetExtension(info->model), "dkm")) return;
    Com_sprintf(path, sizeof(path), "%s.md3", info->model);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < sizeof(header)) {
        if (file) trap_FS_FCloseFile(file);
        G_Error("dk3: actor %s: missing model bounds %s", info->classname, path);
    }
    trap_FS_Read(&header, sizeof(header), file);
    count = LittleLong(header.numFrames); offset = LittleLong(header.ofsFrames);
    if (LittleLong(header.ident) != MD3_IDENT || count != info->frames ||
        offset < sizeof(header) || offset > length || count > (length - offset) / sizeof(frame))
        G_Error("dk3: actor %s: invalid frame bounds %s", info->classname, path);
    info->frameBottoms = G_Alloc(count * sizeof(float));
    trap_FS_Seek(file, offset, FS_SEEK_SET);
    for (i = 0; i < count; ++i) {
        trap_FS_Read(&frame, sizeof(frame), file);
        info->frameBottoms[i] = LittleFloat(frame.bounds[0][2]);
        if (Q_isnan(info->frameBottoms[i]) || fabs(info->frameBottoms[i]) > MAX_WORLD_COORD)
            G_Error("dk3: actor %s: invalid model frame %d", info->classname, i);
    }
    trap_FS_FCloseFile(file);
}

static void ReadAnimations(dkActorInfo_t *info, qboolean required) {
    char path[MAX_QPATH], buffer[32768], *cursor, *token;
    fileHandle_t file;
    int length;
    Com_sprintf(path, sizeof(path), "%s.anim", info->model);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 0 && !required) return;
    if (length <= 0 || length >= (int)sizeof(buffer)) {
        if (file) trap_FS_FCloseFile(file);
        G_Error("dk3: actor %s: missing or oversized %s", info->classname, path);
    }
    trap_FS_Read(buffer, length, file);
    trap_FS_FCloseFile(file);
    buffer[length] = 0;
    cursor = buffer;
    if (strcmp(COM_Parse(&cursor), "dk3_animation") || strcmp(COM_Parse(&cursor), "1"))
        G_Error("dk3: %s: unsupported animation format", path);
    info->frames = atoi(COM_Parse(&cursor));
    if (info->frames < 1 || info->frames > 65535) G_Error("dk3: %s: invalid frame count", path);
    while (*(token = COM_Parse(&cursor))) {
        dkAnimation_t *animation;
        if (info->animationCount == DK_ANIMATIONS) G_Error("dk3: %s: animation limit exceeded", path);
        animation = &info->animations[info->animationCount++];
        Q_strncpyz(animation->name, token, sizeof(animation->name));
        animation->weight = animation->soundChance = 100;
        animation->first = atoi(COM_Parse(&cursor));
        animation->last = atoi(COM_Parse(&cursor));
        animation->fps = atoi(COM_Parse(&cursor));
        if (!cursor || animation->first < 0 || animation->last < animation->first ||
            animation->last >= info->frames || animation->fps <= 0 || animation->fps > 100)
            G_Error("dk3: %s: invalid animation %s", path, animation->name);
    }
    if (!info->animationCount) {
        dkAnimation_t *animation = &info->animations[info->animationCount++];
        Q_strncpyz(animation->name, "amba", sizeof(animation->name));
        animation->first = 0; animation->last = info->frames - 1; animation->fps = 10;
        animation->weight = animation->soundChance = 100;
    }
    ReadFrameBounds(info);
}

static void ReadActor(const dkRecord_t *row) {
    const char *name = DK_Field(row, "classname");
    dkActorInfo_t *info;
    int i;
    if (definitionCount == DK_ACTOR_DEFINITIONS) G_Error("dk3: actor definition limit exceeded");
    info = &definitions[definitionCount++];
    Q_strncpyz(info->classname, name, sizeof(info->classname));
    Q_strncpyz(info->baseModel, DK_Field(row, "model_name"), sizeof(info->baseModel));
    {
        char map[MAX_QPATH];
        trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
        /* Supplied cinematic actors may have chapter-specific animation models,
           including c_priest_e3m1 and c_priest_e3m6. The generic table path can
           name an asset that was never shipped. */
        ChapterModel(name, info->baseModel, map, info->model);
    }
    info->health = DK_Number(row, "health", 100);
    info->speed = DK_Number(row, "run_speed", 120);
    info->walkSpeed = DK_Number(row, "walk_speed", info->speed * 0.5f);
    info->sightRange = DK_Number(row, "active_distance", 1200);
    info->fov = DK_Number(row, "fov", 180);
    VectorSet(info->modelScale, 1, 1, 1);
    {
        const char *value = DK_Field(row, "render_scale");
        if (*value && sscanf(value, "%f %f %f", &info->modelScale[0], &info->modelScale[1], &info->modelScale[2]) != 3)
            G_Error("dk3: actor %s: render_scale requires three axes", name);
        for (i = 0; i < 3; ++i) if (!(info->modelScale[i] > 0 && info->modelScale[i] <= 16))
            G_Error("dk3: actor %s: invalid render_scale axis %d", name, i);
    }
    info->scale = info->modelScale[0];
    if (info->sightRange < 64) info->sightRange = 1200;
    for (i = 0; i < 3; ++i) {
        dkActorAttack_t *attack = &info->attacks[i];
        char key[64];
        int axis;
#define ATTACK_FIELD(field, suffix, fallback) \
        Com_sprintf(key, sizeof(key), "weapon%d_" suffix, i + 1); attack->field = DK_Number(row, key, fallback)
        ATTACK_FIELD(damage, "base_damage", 0);
        ATTACK_FIELD(randomDamage, "random_damage", 0);
        ATTACK_FIELD(speed, "speed", 0);
        ATTACK_FIELD(range, "distance", 64);
        ATTACK_FIELD(spreadX, "spread_x", 0);
        ATTACK_FIELD(spreadZ, "spread_z", 0);
#undef ATTACK_FIELD
        for (axis = 0; axis < 3; ++axis) {
            Com_sprintf(key, sizeof(key), "weapon%d_offset_%c", i + 1, 'x' + axis);
            attack->offset[axis] = DK_Number(row, key, 0);
        }
        if (attack->range < 1) attack->range = 64;
        attack->weapon = attack->range > 160 ? DK_W_BOLTER : DK_W_DISRUPTOR;
        if (strstr(name, "venom") || strstr(name, "rotworm") || strstr(name, "spider")) attack->weapon = DK_W_VENOM;
        else if (strstr(name, "rocket")) attack->weapon = DK_W_SIDEWINDER;
        else if (strstr(name, "stavros") || strstr(name, "dragon")) attack->weapon = DK_W_STAVROS;
        else if (strstr(name, "wyndrax")) attack->weapon = DK_W_WYNDRAX;
        else if (strstr(name, "nharre")) attack->weapon = DK_W_NIGHTMARE;
        else if (strstr(name, "cryotech")) attack->weapon = DK_W_KINETICORE;
        else if (strstr(name, "lasergat")) attack->weapon = DK_W_NOVABEAM;
    }
    for (i = 0; i < 3; ++i) {
        char key[32];
        Com_sprintf(key, sizeof(key), "size_min_%c", 'x' + i);
        info->mins[i] = DK_Number(row, key, i == 2 ? -24 : -16);
        Com_sprintf(key, sizeof(key), "size_max_%c", 'x' + i);
        info->maxs[i] = DK_Number(row, key, i == 2 ? 32 : 16);
        if (info->mins[i] > info->maxs[i]) G_Error("dk3: actor %s: invalid bounds", name);
    }
    info->flying = strstr(name, "skeet") || strstr(name, "cambot") || strstr(name, "deathsphere") ||
                   strstr(name, "harpy") || strstr(name, "griffon") || strstr(name, "dragon") || strstr(name, "bat") || strstr(name, "wisp") || strstr(name, "firefly") || strstr(name, "seagull") || strstr(name, "ghost") || strstr(name, "chaingang");
    info->swimming = strstr(name, "fish") || strstr(name, "shark") || strstr(name, "squid") || strstr(name, "guppy");
    info->turret = strstr(name, "rockgat") || strstr(name, "lasergat");
    if (!strcmp(name, "monster_rockgat") && info->attacks[0].damage <= 0) {
        /* This map turret fires low-damage chaingun rounds. It is not a
           sidewinder launcher; its otherwise empty attack row needs defaults. */
        info->attacks[0].damage = 1;
        info->attacks[0].randomDamage = 1;
        info->attacks[0].speed = 0;
        info->attacks[0].range = 512;
        info->attacks[0].weapon = DK_W_RIPGUN;
    }
    info->companion = !strcmp(name, "mikiko") || !strcmp(name, "superfly") || !strcmp(name, "mikikofly");
    info->civilian = strstr(name, "worker") || (!strncmp(name, "e_", 2) && strcmp(name, "e_dopefish")) ||
                      !strncmp(name, "cine_", 5) || !strcmp(name, "hiro") || !strcmp(name, "monster_priest") ||
                      !strcmp(name, "monster_prisoner") || !strcmp(name, "monster_prisonerb") || !strcmp(name, "monster_wisp");
    if (!*name || !*info->model || info->health <= 0) G_Error("dk3: incomplete actor definition %s", name);
    ReadAnimations(info, qfalse);
}

static void ReadFrameEvents(const dkRecord_t *row) {
    const char *name = DK_Field(row, "classname"), *sequence = DK_Field(row, "animation");
    dkAnimation_t *animation = NULL;
    int i, j;
    for (i = 0; i < definitionCount; ++i) if (!strcmp(definitions[i].classname, name)) {
        for (j = 0; j < definitions[i].animationCount; ++j)
            if (!Q_stricmp(definitions[i].animations[j].name, sequence)) animation = &definitions[i].animations[j];
        /* Detection cues have no model frames. They are still authored sounds. */
        if (!animation && !Q_stricmpn(sequence, "sight", 5)) {
            if (definitions[i].sightSoundCount == ARRAY_LEN(definitions[i].sightSounds))
                G_Error("dk3: actor %s: too many sight cues", name);
            animation = &definitions[i].sightSounds[definitions[i].sightSoundCount++];
        }
        break;
    }
    /* Frame tables also contain optional sequences absent from some model revisions. */
    if (!animation) return;
    for (i = 0; i < 2; ++i) {
        char key[32];
        Com_sprintf(key, sizeof(key), "sound%d", i + 1);
        Q_strncpyz(animation->sounds[i], DK_Field(row, key), sizeof(animation->sounds[i]));
        Com_sprintf(key, sizeof(key), "frame%d", i + 1);
        animation->soundFrames[i] = DK_Number(row, key, 1);
        Com_sprintf(key, sizeof(key), "strike%d", i + 1);
        animation->strikes[i] = DK_Number(row, key, 0);
    }
    animation->weight = DK_Number(row, "weight", 100);
    animation->soundChance = DK_Number(row, "sound2_chance", 100);
}

static void ReadCinematicActors(void) {
    /* These identities are referenced by supplied programs but absent from the
       gameplay balance table. Keep their definition order fixed for saved IDs. */
    static const char *cast[] = {
        "cine_casseti", "cine_charon", "cine_fmg", "cine_gharroth", "cine_gusagi",
        "cine_inshiro", "cine_kage", "cine_mwguard", "cine_ninja", "cine_osaka",
        "cine_pgharroth", "cine_phiro", "cine_smikiko", "cine_tatsuo", "cine_toshiro", "cine_usagi"
    };
    char map[MAX_QPATH];
    int i, j;
    trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
    for (i = 0; i < ARRAY_LEN(cast); ++i) {
        dkActorInfo_t *info;
        for (j = 0; j < definitionCount; ++j) if (!strcmp(definitions[j].classname, cast[i])) break;
        if (j < definitionCount) continue;
        if (definitionCount == DK_ACTOR_DEFINITIONS) G_Error("dk3: cinematic actor definition limit exceeded");
        info = &definitions[definitionCount++];
        Q_strncpyz(info->classname, cast[i], sizeof(info->classname));
        Com_sprintf(info->baseModel, sizeof(info->baseModel), "models/cinematic/c_%s.dkm", CinematicModelName(cast[i]));
        ChapterModel(cast[i], info->baseModel, map, info->model);
        info->health = 100; info->scale = 1; VectorSet(info->modelScale, 1, 1, 1);
        info->speed = 240; info->walkSpeed = 120;
        info->sightRange = 1200; info->fov = 180;
        info->civilian = qtrue;
        VectorSet(info->mins, -16, -16, -24);
        VectorSet(info->maxs, 16, 16, 32);
        ReadAnimations(info, qfalse);
    }
}

void DK_LoadActors(void) {
    definitionCount = 0;
    memset(definitions, 0, sizeof(definitions));
    DK_ReadTable("aidata", ReadActor);
    ReadCinematicActors();
    DK_ReadTable("actor_events", ReadFrameEvents);
}

static dkActorInfo_t *Info(gentity_t *ent) { return &definitions[ent->dk.actorKind - 1]; }

static unsigned int ActorRandom(gentity_t *actor) {
    actor->dk.actorRandom = actor->dk.actorRandom * 1664525u + 1013904223u;
    return actor->dk.actorRandom >> 8;
}

static int AnimationIndex(dkActorInfo_t *info, const char *name) {
    int i, selected = -1;
    for (i = 0; i < info->animationCount; ++i) {
        if (!Q_stricmp(info->animations[i].name, name)) return i;
        if (selected < 0 && !Q_stricmpn(info->animations[i].name, name, strlen(name))) selected = i;
    }
    return selected;
}

static void Animation(gentity_t *ent, const char *name, int state) {
    dkActorInfo_t *info = Info(ent);
    int selected = AnimationIndex(info, name);
    if (selected < 0 && !strcmp(name, "pain")) selected = AnimationIndex(info, "hit");
    if (selected < 0 && !strcmp(name, "run")) selected = AnimationIndex(info, info->flying ? "fly" : info->swimming ? "swim" : "walk");
    if (selected < 0) selected = 0;
    if (ent->dk.action == state && ent->dk.animationTime && selected == ent->dk.animationIndex) return;
    ent->dk.action = state;
    ent->s.dk3RenderFlags &= ~DK3_RF_ANIM_REVERSE;
    ent->dk.animationIndex = selected;
    ent->dk.animationCursor = -1;
    ent->dk.animationTime = level.time;
    ent->dk.animationLoop = state != ACTOR_ATTACK && state != ACTOR_PAIN && state != ACTOR_DEAD && state != ACTOR_DOWN;
    ent->dk.firstFrame = info->animationCount ? info->animations[selected].first : 0;
    ent->dk.lastFrame = info->animationCount ? info->animations[selected].last : 0;
    ent->dk.animationRate = info->animationCount ? info->animations[selected].fps : 10;
    ent->s.frame = ent->dk.firstFrame;
}

static int AnimationDuration(gentity_t *actor) {
    return (actor->dk.lastFrame - actor->dk.firstFrame + 1) * 1000 / actor->dk.animationRate;
}

static void FrameEvents(gentity_t *actor) {
    dkActorInfo_t *info = Info(actor);
    dkAnimation_t *animation;
    int frames, elapsed, cursor, last, event;
    qboolean once;
    if (!info->animationCount) return;
    if (actor->dk.firstFrame == actor->dk.lastFrame) return;
    animation = &info->animations[actor->dk.animationIndex];
    frames = actor->dk.lastFrame - actor->dk.firstFrame + 1;
    elapsed = (level.time - actor->dk.animationTime) * actor->dk.animationRate / 1000;
    once = !actor->dk.animationLoop && (actor->dk.cinematicControlled || level.time >= actor->dk.scriptUntil);
    if (elapsed < 0) elapsed = 0;
    if (once && elapsed >= frames) elapsed = frames - 1;
    last = actor->dk.animationCursor;
    /* Bound catch-up after a large simulation step without replaying entire sound loops. */
    if (last < elapsed - frames) last = elapsed - frames;
    for (cursor = last + 1; cursor <= elapsed; ++cursor) {
        int pose = cursor % frames;
        int frame;
        if (actor->s.dk3RenderFlags & DK3_RF_ANIM_REVERSE) pose = frames - 1 - pose;
        frame = actor->dk.firstFrame + pose - animation->first + 1;
        for (event = 0; event < 2; ++event) {
            int soundFrame = animation->soundFrames[event];
            if (soundFrame > frames) soundFrame = frames;
            if (frame == soundFrame && *animation->sounds[event] &&
                (!event || (int)(ActorRandom(actor) % 100) < animation->soundChance))
                /* Separate events preserve simultaneous frame sounds. */
                G_Sound(actor, CHAN_AUTO, DK_SoundIndex(animation->sounds[event]));
        }
        if (actor->dk.action == ACTOR_ATTACK && !info->companion && !info->turret && actor->enemy && actor->enemy->inuse &&
            !actor->dk.cinematicControlled && level.time >= actor->dk.scriptUntil) {
            dkActorAttack_t *attack = &info->attacks[actor->dk.attackGroup];
            for (event = 0; event < 2; ++event) {
                int strike = animation->strikes[event];
                if (!event && !strike) strike = (frames + 1) / 2;
                if (strike > frames) strike = frames;
                if (strike && frame == strike) {
                    int damage = attack->damage;
                    if (attack->randomDamage > 0) damage += ActorRandom(actor) % (attack->randomDamage + 1);
                    if (!strcmp(actor->classname, "monster_thunderskeet")) DK_DropToxicBomb(actor, actor->enemy, damage);
                    else DK_ActorStrike(actor, actor->enemy, attack->weapon, attack->offset,
                                        attack->speed, damage, attack->range, attack->spreadX, attack->spreadZ);
                }
            }
        }
    }
    actor->dk.animationCursor = elapsed;
    actor->s.frame = actor->s.dk3RenderFlags & DK3_RF_ANIM_REVERSE ?
        actor->dk.lastFrame - elapsed % frames : actor->dk.firstFrame + elapsed % frames;
}

static qboolean Enemy(gentity_t *actor, gentity_t *other) {
    dkActorInfo_t *info = Info(actor);
    if (!other->inuse || other == actor || other->health <= 0 || !other->takedamage) return qfalse;
    if (other->dk.cinematicControlled || (other->client && other->client->ps.dk3CameraActive)) return qfalse;
    if (other->client && other->client->ps.powerups[PW_INVIS] > level.time &&
        other->client->ps.weaponstate != WEAPON_FIRING && Distance(actor->r.currentOrigin, other->r.currentOrigin) > 128) return qfalse;
    if (info->companion) return other->dk.actorKind && !Info(other)->companion && !Info(other)->civilian;
    if (info->civilian) return other == actor->enemy;
    return (other->client && other->client->sess.sessionTeam != TEAM_SPECTATOR) ||
           (other->dk.actorKind && Info(other)->companion);
}

static qboolean Visible(gentity_t *actor, gentity_t *target) {
    trace_t trace;
    vec3_t from, to;
    VectorCopy(actor->r.currentOrigin, from);
    from[2] += actor->r.maxs[2] * 0.6f;
    VectorCopy(target->r.currentOrigin, to);
    to[2] += target->r.maxs[2] * 0.5f;
    trap_Trace(&trace, from, NULL, NULL, to, actor->s.number, MASK_SHOT);
    return trace.entityNum == target->s.number || trace.fraction == 1;
}

static void Acquire(gentity_t *actor) {
    int i;
    qboolean pod = !strcmp(actor->classname, "monster_protopod");
    float nearest = pod ? DK_POD_NOTICE_RANGE : actor->dk.sightRange;
    gentity_t *previous = actor->enemy;
    if (Info(actor)->civilian) {
        if (!previous || !Enemy(actor, previous)) actor->enemy = NULL;
        return;
    }
    actor->enemy = NULL;
    for (i = 0; i < level.num_entities; ++i) {
        gentity_t *other = &g_entities[i];
        float distance;
        if (!Enemy(actor, other)) continue;
        distance = Distance(actor->r.currentOrigin, other->r.currentOrigin);
        if (pod) {
            vec3_t delta;
            VectorSubtract(actor->r.currentOrigin, other->r.currentOrigin, delta);
            delta[2] = 0;
            distance = VectorLength(delta);
        }
        if (distance < nearest && Visible(actor, other)) {
            vec3_t forward, toward;
            float threshold = cos(Info(actor)->fov * (M_PI / 360.0f));
            AngleVectors(actor->s.angles, forward, NULL, NULL);
            VectorSubtract(other->r.currentOrigin, actor->r.currentOrigin, toward); VectorNormalize(toward);
            if (!pod && distance > 160 && !Info(actor)->companion && DotProduct(forward, toward) < threshold &&
                !(other->client && distance < 768 && other->client->ps.weaponstate == WEAPON_FIRING)) continue;
            actor->enemy = other; nearest = distance;
        }
    }
    if (actor->enemy) {
        dkActorInfo_t *info = Info(actor);
        if (!previous && (!actor->dk.lastSeenTime || level.time - actor->dk.lastSeenTime > 8000)) {
            int total = 0, choice, cue;
            for (cue = 0; cue < info->sightSoundCount; ++cue) total += info->sightSounds[cue].weight;
            if (total > 0) {
                choice = ActorRandom(actor) % total;
                for (cue = 0; cue < info->sightSoundCount; ++cue) {
                    choice -= info->sightSounds[cue].weight;
                    if (choice < 0) {
                        G_Sound(actor, CHAN_VOICE, DK_SoundIndex(info->sightSounds[cue].sounds[0]));
                        break;
                    }
                }
            }
        }
        actor->dk.lastSeenTime = level.time;
        VectorCopy(actor->enemy->r.currentOrigin, actor->dk.lastSeenOrigin);
    }
}

static qboolean Flying(gentity_t *actor) {
    trace_t trace;
    vec3_t ceiling;
    if (!Info(actor)->flying || (actor->spawnflags & 64)) return qfalse;
    if (strcmp(actor->classname, "monster_chaingang")) return qtrue;
    VectorCopy(actor->r.currentOrigin, ceiling); ceiling[2] += 96;
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, ceiling, actor->s.number, MASK_SOLID);
    return trace.fraction == 1;
}

/* Authored origins can leave a newly assigned hull slightly below a floor.
   Recover only upward through clear point space, within one normal step. */
static qboolean ClearActorHull(gentity_t *actor) {
    trace_t space, path;
    vec3_t candidate;
    int rise;
    trap_Trace(&space, actor->r.currentOrigin, actor->r.mins, actor->r.maxs,
               actor->r.currentOrigin, actor->s.number, MASK_PLAYERSOLID);
    if (!space.startsolid && !space.allsolid) return qtrue;
    for (rise = 1; rise <= DK_STEP_HEIGHT; ++rise) {
        VectorCopy(actor->r.currentOrigin, candidate); candidate[2] += rise;
        trap_Trace(&path, actor->r.currentOrigin, NULL, NULL, candidate, actor->s.number, MASK_SOLID);
        if (path.startsolid || path.fraction < 1) break;
        trap_Trace(&space, candidate, actor->r.mins, actor->r.maxs, candidate,
                   actor->s.number, MASK_PLAYERSOLID);
        if (!space.startsolid && !space.allsolid) {
            G_SetOrigin(actor, candidate); trap_LinkEntity(actor);
            VectorClear(actor->dk.actorVelocity);
            return qtrue;
        }
    }
    VectorClear(actor->dk.actorVelocity);
    if (!actor->dk.blockedSince) {
        G_Printf("dk3: actor %u (%s) obstructed at %.0f %.0f %.0f\n", actor->dk.id, actor->classname,
            actor->r.currentOrigin[0], actor->r.currentOrigin[1], actor->r.currentOrigin[2]);
        actor->dk.blockedSince = level.time;
    }
    return qfalse;
}

static void Physics(gentity_t *actor) {
    trace_t trace;
    vec3_t destination;
    float dt = DK_ACTOR_TICK / 1000.0f, impact;
    if (actor->dk.parentId || Info(actor)->turret ||
        (actor->health > 0 && (Flying(actor) || Info(actor)->swimming))) return;
    if (!ClearActorHull(actor)) return;
    VectorCopy(actor->r.currentOrigin, destination); destination[2] -= 2;
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, destination, actor->s.number, MASK_PLAYERSOLID);
    if (trace.fraction < 1 && trace.plane.normal[2] > 0.7f && actor->dk.actorVelocity[2] <= 0) {
        VectorClear(actor->dk.actorVelocity); actor->s.groundEntityNum = trace.entityNum;
        return;
    }
    actor->s.groundEntityNum = ENTITYNUM_NONE;
    VectorMA(actor->r.currentOrigin, dt, actor->dk.actorVelocity, destination);
    destination[2] -= 0.5f * g_gravity.value * dt * dt;
    actor->dk.actorVelocity[2] -= g_gravity.value * dt;
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, destination, actor->s.number, MASK_PLAYERSOLID);
    impact = -actor->dk.actorVelocity[2];
    if (trace.startsolid || trace.allsolid) { VectorClear(actor->dk.actorVelocity); return; }
    if (trace.fraction < 1) {
        if (trace.plane.normal[2] > 0.7f) {
            VectorClear(actor->dk.actorVelocity); actor->s.groundEntityNum = trace.entityNum;
        } else VectorMA(actor->dk.actorVelocity, -DotProduct(actor->dk.actorVelocity, trace.plane.normal),
                        trace.plane.normal, actor->dk.actorVelocity);
    }
    G_SetOrigin(actor, trace.endpos); trap_LinkEntity(actor);
    if (actor->health > 0 && actor->s.groundEntityNum != ENTITYNUM_NONE && impact > 600)
        G_Damage(actor, NULL, NULL, NULL, NULL, (impact - 600) * 0.1f, DAMAGE_NO_ARMOR, MOD_FALLING);
}

static void Move(gentity_t *actor, vec3_t goal, float speed) {
    dkActorInfo_t *info = Info(actor);
    vec3_t direction, end, raised, floor;
    trace_t move, ground;
    float step = speed * DK_ACTOR_TICK / 1000.0f * ((actor->dk.status & 4) ? 0.35f : 1);
    float distance;
    if (!ClearActorHull(actor)) return;
    VectorSubtract(goal, actor->r.currentOrigin, direction);
    if (!Flying(actor) && !info->swimming && !info->turret) direction[2] = 0;
    distance = VectorNormalize(direction);
    if (distance < step) step = distance;
    if ((actor->spawnflags & 128) || step <= 0 || actor->dk.actorVelocity[2] > 0) return;
    VectorMA(actor->r.currentOrigin, step, direction, end);
    if (info->swimming && !(trap_PointContents(end, actor->s.number) & CONTENTS_WATER)) {
        if (!actor->dk.blockedSince) actor->dk.blockedSince = level.time;
        return;
    }
    trap_Trace(&move, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, end, actor->s.number, MASK_PLAYERSOLID);
    if (move.fraction < 1 && !Flying(actor) && !info->swimming && !info->turret) {
        VectorCopy(actor->r.currentOrigin, raised); raised[2] += DK_STEP_HEIGHT;
        trap_Trace(&ground, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, raised, actor->s.number, MASK_PLAYERSOLID);
        if (ground.fraction == 1) {
            VectorMA(raised, step, direction, end);
            trap_Trace(&ground, raised, actor->r.mins, actor->r.maxs, end, actor->s.number, MASK_PLAYERSOLID);
            if (ground.fraction > move.fraction) move = ground;
        }
    }
    if (!Flying(actor) && !info->swimming && !info->turret) {
        VectorCopy(move.endpos, floor); floor[2] -= DK_STEP_HEIGHT + 24;
        trap_Trace(&ground, move.endpos, actor->r.mins, actor->r.maxs, floor, actor->s.number, MASK_PLAYERSOLID);
        /* Ground routes cannot cross a ledge just because the next area is reachable. */
        if (ground.fraction == 1) { if (!actor->dk.blockedSince) actor->dk.blockedSince = level.time; return; }
        VectorCopy(ground.endpos, move.endpos);
        actor->s.groundEntityNum = ground.entityNum;
    }
    if (Distance(actor->r.currentOrigin, move.endpos) < 0.5f) {
        if (!actor->dk.blockedSince) actor->dk.blockedSince = level.time;
    } else actor->dk.blockedSince = 0;
    G_SetOrigin(actor, move.endpos);
    if (!actor->dk.cinematicControlled || !actor->dk.turnActive)
        actor->s.angles[YAW] = vectoyaw(direction);
    VectorCopy(actor->s.angles, actor->r.currentAngles);
    trap_LinkEntity(actor);
}

static void PursuePosition(gentity_t *actor, const vec3_t position, int target) {
    vec3_t goal;
    trace_t trace;
    VectorCopy(position, goal);
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, goal, actor->s.number, MASK_PLAYERSOLID);
    if (trace.fraction < 1 && trace.entityNum != target &&
        !Flying(actor) && !Info(actor)->swimming && !Info(actor)->turret && trap_AAS_Initialized()) {
        int travel;
        DK_GroundWaypoint(actor, goal,
            TFL_WALK | TFL_CROUCH | TFL_BARRIERJUMP | TFL_ELEVATOR | TFL_WATER | TFL_AIR, goal, &travel);
    }
    if (Info(actor)->turret) {
        vec3_t waypoint;
        if (!DK_NavigationGoal(actor, goal, 8, target, waypoint)) return;
        VectorCopy(waypoint, goal);
    }
    if (Flying(actor) || Info(actor)->swimming) {
        vec3_t waypoint;
        if (DK_NavigationGoal(actor, goal, Flying(actor) ? 4 : 2, target, waypoint)) VectorCopy(waypoint, goal);
    }
    Move(actor, goal, Info(actor)->speed * (1 + actor->dk.attributes[2] * 0.1f));
    if (!Info(actor)->turret && actor->dk.blockedSince && level.time - actor->dk.blockedSince > 500) {
        vec3_t forward, side, alternative, before;
        int attempt;
        VectorSubtract(goal, actor->r.currentOrigin, forward); forward[2] = 0; VectorNormalize(forward);
        VectorSet(side, -forward[1], forward[0], 0);
        for (attempt = 0; attempt < 4; ++attempt) {
            VectorCopy(actor->r.currentOrigin, before);
            VectorMA(before, (attempt & 1) ? -72 : 72, side, alternative);
            VectorMA(alternative, attempt < 2 ? 24 : -48, forward, alternative);
            Move(actor, alternative, Info(actor)->speed);
            if (Distance(before, actor->r.currentOrigin) > 1) break;
        }
    }
    Animation(actor, actor->dk.movingAnimation ? actor->dk.movingAnimation : "run", ACTOR_CHASE);
}

static void Pursue(gentity_t *actor, gentity_t *target) {
    vec3_t goal;
    VectorCopy(target->r.currentOrigin, goal);
    if (Flying(actor)) goal[2] += target->r.maxs[2] * 0.5f;
    PursuePosition(actor, goal, target->s.number);
}

static int AttackGroup(gentity_t *actor, float distance) {
    dkActorInfo_t *info = Info(actor);
    int i, selected = -1, alternatives = 0;
    float range = 100000;
    if (info->turret) return distance <= actor->dk.attackRange ? 0 : -1;
    for (i = 0; i < 3; ++i) {
        if (info->attacks[i].damage <= 0 || distance > info->attacks[i].range) continue;
        if (!strcmp(actor->classname, "monster_wyndrax") && i == 1 && actor->dk.abilityCharges <= 0) continue;
        if (info->attacks[i].range < range) {
            selected = i; range = info->attacks[i].range; alternatives = 1;
        } else if (info->attacks[i].range == range && ActorRandom(actor) % ++alternatives == 0) selected = i;
    }
    return selected;
}

static void Attack(gentity_t *actor, int group) {
    dkActorInfo_t *info = Info(actor);
    vec3_t direction;
    char animation[32];
    gentity_t *target = actor->enemy;
    if (!target || level.time < actor->dk.actionTime) return;
    VectorSubtract(target->r.currentOrigin, actor->r.currentOrigin, direction);
    if (!actor->dk.cinematicControlled || !actor->dk.turnActive)
        actor->s.angles[YAW] = vectoyaw(direction);
    VectorCopy(actor->s.angles, actor->r.currentAngles);
    if (info->companion) {
        int interval = DK_FireCompanionWeapon(actor, target);
        Animation(actor, "atak", ACTOR_ATTACK);
        actor->dk.actionTime = level.time + (interval > 0 ? interval : 500);
        return;
    }
    if (info->turret) {
        dkActorAttack_t *attack = &info->attacks[0];
        int damage = actor->dk.attackDamage;
        if (actor->dk.attackRandomDamage > 0) damage += ActorRandom(actor) % (actor->dk.attackRandomDamage + 1);
        DK_ActorStrike(actor, target, attack->weapon, attack->offset, attack->speed,
                       damage, actor->dk.attackRange, attack->spreadX, attack->spreadZ);
        if (!strcmp(actor->classname, "monster_rockgat"))
            G_AddEvent(actor, EV_GENERAL_SOUND, DK_SoundIndex("e1/e_rockgatshootmultia.wav"));
        Animation(actor, "atak", ACTOR_ATTACK);
        actor->dk.actionTime = level.time + actor->dk.fireInterval;
        return;
    }
    actor->dk.attackGroup = group;
    if (!strcmp(actor->classname, "monster_wyndrax") && group == 1) --actor->dk.abilityCharges;
    Com_sprintf(animation, sizeof(animation), "atak%c", 'a' + group);
    if (AnimationIndex(info, animation) < 0) Q_strncpyz(animation, "atak", sizeof(animation));
    actor->dk.animationTime = 0;
    Animation(actor, animation, ACTOR_ATTACK);
    actor->dk.actionTime = level.time + AnimationDuration(actor) + 200;
}

/* A thunderskeet attacks on moving passes above its target. The local arc
   follows collision-tested waypoints and never pulls the aircraft to eye height. */
static void ThunderFlight(gentity_t *actor) {
    gentity_t *target = actor->enemy;
    vec3_t goal, ceiling, center, facing, before;
    trace_t trace;
    float phase, distance;
    if (!target) return;
    phase = level.time * 0.0008f + actor->dk.id;
    VectorCopy(target->r.currentOrigin, center); center[2] += target->r.maxs[2] + 280;
    VectorCopy(center, goal);
    goal[0] += cos(phase) * 240; goal[1] += sin(phase) * 240;
    VectorCopy(target->r.currentOrigin, ceiling); ceiling[2] += target->r.maxs[2] + 1;
    trap_Trace(&trace, ceiling, NULL, NULL, center, target->s.number, MASK_SOLID);
    if (trace.fraction < 1) goal[2] = trace.endpos[2] - actor->r.maxs[2] - 16;
    if (goal[2] < target->r.currentOrigin[2] + 96) {
        /* A low roof calls for another flight route, never a melee approach. */
        VectorCopy(actor->r.currentOrigin, goal);
        goal[0] += cos(phase) * 160; goal[1] += sin(phase) * 160;
    }
    VectorCopy(actor->r.currentOrigin, before);
    Move(actor, goal, Info(actor)->speed);
    if (Distance(before, actor->r.currentOrigin) < 1) {
        VectorCopy(before, goal); goal[2] += 64;
        Move(actor, goal, Info(actor)->speed);
    }
    VectorSubtract(target->r.currentOrigin, actor->r.currentOrigin, facing);
    actor->s.angles[YAW] = vectoyaw(facing);
    distance = VectorLength(facing);
    if (level.time >= actor->dk.actionTime) {
        if (actor->r.currentOrigin[2] > target->r.currentOrigin[2] + 96 &&
            distance <= Info(actor)->attacks[0].range && Visible(actor, target)) Attack(actor, 0);
        else Animation(actor, "fly", ACTOR_CHASE);
    }
}

qboolean DK_IsCompanion(gentity_t *ent) {
    return ent && ent->dk.actorKind && Info(ent)->companion;
}

void DK_ActorHold(gentity_t *actor) {
    if (!actor || !actor->dk.actorKind) return;
    actor->dk.firstFrame = actor->dk.lastFrame = actor->s.frame;
    actor->dk.animationLoop = qfalse;
    actor->dk.action = ACTOR_WAIT;
    actor->dk.scriptUntil = level.time;
}

int DK_ActorAnimate(gentity_t *actor, const char *name, float repeats) {
    dkActorInfo_t *info;
    int i, duration;
    if (!actor || !actor->dk.actorKind) return -1;
    info = Info(actor);
    for (i = 0; i < info->animationCount; ++i) if (!Q_stricmp(info->animations[i].name, name)) break;
    if (i == info->animationCount) {
        /* Cinematic programs request a neutral idle even for chapter models
           containing only authored action poses. Hold that pose until the
           next task instead of inventing a looping action animation. */
        if (actor->dk.cinematicControlled && (!strcmp(name, "amba") || !strcmp(name, "amb"))) {
            DK_ActorHold(actor);
            return 0;
        }
        return -1;
    }
    actor->dk.animationTime = 0;
    Animation(actor, name, ACTOR_IDLE);
    actor->dk.animationLoop = qfalse;
    duration = (int)((actor->dk.lastFrame - actor->dk.firstFrame + 1) * 1000.0f * repeats / actor->dk.animationRate);
    actor->dk.scriptUntil = level.time + duration;
    return duration;
}

qboolean DK_ActorState(gentity_t *actor, const char *state, const char *argument) {
    if (!actor || !actor->dk.actorKind) return qfalse;
    if (!Q_stricmp(state, "ignore_player")) { actor->dk.ignorePlayer = 1; actor->enemy = NULL; }
    else if (!Q_stricmp(state, "aggressive")) { actor->dk.ignorePlayer = 0; actor->dk.pathTarget = NULL; Acquire(actor); }
    else if (!Q_stricmp(state, "pathfollow") && *argument) actor->dk.pathTarget = G_NewString(argument);
    else return qfalse;
    return qtrue;
}

/* Yield only to a visible nearby player through traced, grounded movement. No warps
   or collision disabling: a locked door remains an obstacle for both participants. */
static qboolean Yield(gentity_t *actor) {
    gentity_t *player = &g_entities[0];
    vec3_t forward, right, relative, goal;
    float distance, ahead;
    int side;
    if (!player->client || player->health <= 0) return qfalse;
    VectorSubtract(actor->r.currentOrigin, player->r.currentOrigin, relative);
    distance = VectorLength(relative);
    if (distance > 100 || !Visible(actor, player)) return qfalse;
    AngleVectors(player->client->ps.viewangles, forward, right, NULL);
    ahead = DotProduct(relative, forward);
    if (ahead < 0 || fabs(DotProduct(relative, right)) > 40) return qfalse;
    for (side = 0; side < 2; ++side) {
        vec3_t before;
        VectorCopy(actor->r.currentOrigin, before);
        VectorMA(before, side ? -64 : 64, right, goal);
        Move(actor, goal, 160);
        if (Distance(before, actor->r.currentOrigin) > 1) { Animation(actor, "run", ACTOR_CHASE); return qtrue; }
    }
    return qfalse;
}

static void Hatch(gentity_t *actor) {
    if (actor->dk.abilityState) return;
    actor->dk.abilityState = 1;
    Animation(actor, "hatcha", ACTOR_WAIT);
    actor->dk.animationLoop = qfalse;
    actor->dk.abilityTime = level.time + AnimationDuration(actor);
}

/* Summoned actors use the same native lifecycle, collision and stable IDs as map actors. */
static gentity_t *Summon(gentity_t *owner, const char *classname, float height) {
    gentity_t *spawned = G_Spawn();
    trace_t trace;
    vec3_t origin, candidate;
    int attempt;
    VectorCopy(owner->r.currentOrigin, origin); origin[2] += height;
    spawned->classname = G_NewString(classname);
    VectorCopy(origin, spawned->s.origin);
    VectorCopy(owner->s.angles, spawned->s.angles);
    if (!DK_SpawnActor(spawned)) { G_FreeEntity(spawned); return NULL; }
    trap_UnlinkEntity(spawned);
    /* A player standing against an egg must not indefinitely occupy its only
       emergence point. Try nearby clear space without crossing solid geometry. */
    for (attempt = 0; attempt < 11; ++attempt) {
        VectorCopy(origin, candidate);
        if (attempt < 3) candidate[2] += attempt * 24;
        else {
            float angle = (attempt - 3) * M_PI / 4;
            candidate[0] += cos(angle) * 40; candidate[1] += sin(angle) * 40;
        }
        trap_Trace(&trace, owner->r.currentOrigin, NULL, NULL, candidate, owner->s.number, MASK_SOLID);
        if (trace.startsolid || trace.fraction < 1) continue;
        trap_Trace(&trace, candidate, spawned->r.mins, spawned->r.maxs, candidate, owner->s.number, MASK_PLAYERSOLID);
        if (!trace.startsolid && !trace.allsolid) break;
    }
    if (attempt == 11) { G_FreeEntity(spawned); return NULL; }
    G_SetOrigin(spawned, candidate);
    spawned->enemy = owner->enemy;
    spawned->dk.ownerId = owner->dk.id;
    if (spawned->enemy) {
        VectorCopy(spawned->enemy->r.currentOrigin, spawned->dk.lastSeenOrigin);
        spawned->dk.lastSeenTime = level.time;
    }
    trap_LinkEntity(spawned);
    return spawned;
}

static qboolean Resurrect(gentity_t *actor) {
    dkActorInfo_t *info = Info(actor);
    trace_t trace;
    if (actor->dk.action != ACTOR_DOWN) return qfalse;
    if (level.time < actor->dk.abilityTime) return qtrue;
    trap_Trace(&trace, actor->r.currentOrigin, info->mins, info->maxs, actor->r.currentOrigin, actor->s.number, MASK_PLAYERSOLID);
    if (trace.startsolid || trace.allsolid) { actor->dk.abilityTime = level.time + 500; return qtrue; }
    VectorCopy(info->mins, actor->r.mins); VectorCopy(info->maxs, actor->r.maxs);
    actor->health = actor->dk.maxHealth;
    actor->takedamage = qtrue; actor->r.contents = CONTENTS_BODY;
    actor->dk.abilityState = 0;
    Animation(actor, AnimationIndex(info, "rise") >= 0 ? "rise" : "amba", ACTOR_PAIN);
    actor->dk.actionTime = level.time + AnimationDuration(actor);
    trap_LinkEntity(actor);
    return qtrue;
}

static qboolean Medusa(gentity_t *actor) {
    gentity_t *target = actor->enemy;
    vec3_t direction, forward;
    if (!target || !target->inuse || target->health <= 0) { actor->dk.abilityState = 0; actor->s.constantLight = 0; return qfalse; }
    if (!actor->dk.abilityState) {
        if (level.time < actor->dk.abilityTime || Distance(actor->r.currentOrigin, target->r.currentOrigin) < 128 ||
            Distance(actor->r.currentOrigin, target->r.currentOrigin) > 1250 || !Visible(actor, target)) return qfalse;
        actor->dk.abilityState = 1; actor->dk.abilityTime = level.time + 3000;
        Animation(actor, "atakd", ACTOR_WAIT);
        return qtrue;
    }
    VectorSubtract(target->r.currentOrigin, actor->r.currentOrigin, direction);
    actor->s.angles[YAW] = vectoyaw(direction); VectorCopy(actor->s.angles, actor->r.currentAngles);
    if (actor->dk.abilityState == 1 && level.time >= actor->dk.abilityTime) {
        actor->dk.abilityState = 2; actor->dk.abilityTime = level.time + 4000;
        actor->s.constantLight = 48 | (255 << 8) | (80 << 16) | (32 << 24);
        Animation(actor, "atake", ACTOR_WAIT);
    }
    if (actor->dk.abilityState == 2) {
        VectorScale(direction, -1, direction); VectorNormalize(direction);
        AngleVectors(target->client ? target->client->ps.viewangles : target->s.angles, forward, NULL, NULL);
        if (DotProduct(forward, direction) > 0.82f && Visible(actor, target)) {
            if (target->client) trap_SendServerCommand(target->s.number, "cp \"Medusa's gaze turned you to stone.\"");
            G_Damage(target, actor, actor, NULL, NULL, 100000, DAMAGE_NO_PROTECTION, MOD_UNKNOWN);
        }
        if (level.time >= actor->dk.abilityTime) {
            actor->dk.abilityState = 0; actor->dk.abilityTime = level.time + 10000;
            actor->s.constantLight = 0;
        }
    }
    return qtrue;
}

static qboolean RechargeWyndrax(gentity_t *actor) {
    gentity_t *wisp = NULL;
    float distance = 4096;
    int i;
    if (level.time < actor->dk.abilityTime) return qfalse;
    if (actor->dk.abilityCharges <= 0) {
        gentity_t *source = G_Find(NULL, FOFS(targetname), "wyndraxcharge");
        if (source) {
            vec3_t goal, start, end;
            trace_t floor;
            VectorCopy(source->r.currentOrigin, start); start[2] = actor->r.currentOrigin[2] + 64;
            VectorCopy(start, end); end[2] -= 1024;
            trap_Trace(&floor, start, actor->r.mins, actor->r.maxs, end, actor->s.number, MASK_SOLID);
            if (!floor.startsolid && floor.fraction < 1 && floor.plane.normal[2] > 0.7f) {
                VectorCopy(floor.endpos, goal);
                if (Distance(actor->r.currentOrigin, goal) > 64) { PursuePosition(actor, goal, ENTITYNUM_NONE); return qtrue; }
                trap_Trace(&floor, source->r.currentOrigin, NULL, NULL, actor->r.currentOrigin, source->s.number, MASK_SHOT);
                if (floor.fraction == 1 || floor.entityNum == actor->s.number) {
                    gentity_t *arc = G_TempEntity(actor->r.currentOrigin, EV_DK3_BEAM);
                    VectorCopy(source->r.currentOrigin, arc->s.origin2); arc->s.weapon = DK_W_WYNDRAX;
                    actor->dk.abilityCharges = 4;
                    actor->dk.abilityTime = level.time + 2000;
                    actor->dk.scriptUntil = level.time + 1000;
                    Animation(actor, "amba", ACTOR_WAIT);
                    return qtrue;
                }
            }
        }
    }
    if (actor->health >= actor->dk.maxHealth / 2) return qfalse;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *candidate = &g_entities[i];
        float next;
        if (!candidate->inuse || strcmp(candidate->classname, "monster_wisp")) continue;
        next = Distance(actor->r.currentOrigin, candidate->r.currentOrigin);
        if (next < distance) { wisp = candidate; distance = next; }
    }
    if (!wisp) { actor->dk.abilityTime = level.time + 3000; return qfalse; }
    if (distance > 96) { Pursue(actor, wisp); return qtrue; }
    if (Visible(actor, wisp)) {
        int amount = actor->dk.maxHealth / 5;
        actor->health += amount;
        if (actor->health > actor->dk.maxHealth) actor->health = actor->dk.maxHealth;
        G_FreeEntity(wisp);
        ++actor->dk.abilityCharges;
        actor->dk.abilityTime = level.time + 2000;
        Animation(actor, "amba", ACTOR_WAIT);
        actor->dk.scriptUntil = level.time + 1000;
    }
    return qtrue;
}

static qboolean Nharre(gentity_t *actor) {
    gentity_t *anchor = NULL, *selected = NULL;
    int choices = 0;
    if (!actor->enemy || level.time < actor->dk.abilityTime || (actor->spawnflags & 128)) return qfalse;
    /* The encounter authors explicitly designate legal teleport destinations. */
    while ((anchor = G_Find(anchor, FOFS(targetname), "nharre")) != NULL) {
        trace_t trace;
        vec3_t from, to;
        if (strcmp(anchor->classname, "info_teleport_destination") ||
            Distance(anchor->r.currentOrigin, actor->r.currentOrigin) < 128 ||
            Distance(anchor->r.currentOrigin, actor->enemy->r.currentOrigin) < 96) continue;
        trap_Trace(&trace, anchor->r.currentOrigin, actor->r.mins, actor->r.maxs,
                   anchor->r.currentOrigin, actor->s.number, MASK_PLAYERSOLID);
        if (trace.startsolid || trace.allsolid) continue;
        VectorCopy(anchor->r.currentOrigin, from); from[2] += actor->r.maxs[2] * 0.6f;
        VectorCopy(actor->enemy->r.currentOrigin, to); to[2] += actor->enemy->r.maxs[2] * 0.5f;
        trap_Trace(&trace, from, NULL, NULL, to, actor->s.number, MASK_SHOT);
        if (trace.fraction < 1 && trace.entityNum != actor->enemy->s.number) continue;
        if (ActorRandom(actor) % ++choices == 0) selected = anchor;
    }
    actor->dk.abilityTime = level.time + (actor->health < actor->dk.maxHealth / 2 ? 3500 : 6500);
    if (!selected) return qfalse;
    G_TempEntity(actor->r.currentOrigin, EV_DK3_BLAST)->s.weapon = DK_W_NIGHTMARE;
    G_SetOrigin(actor, selected->r.currentOrigin);
    VectorClear(actor->dk.actorVelocity);
    actor->s.eFlags ^= EF_TELEPORT_BIT;
    G_TempEntity(actor->r.currentOrigin, EV_DK3_BLAST)->s.weapon = DK_W_NIGHTMARE;
    trap_LinkEntity(actor);
    actor->dk.actionTime = level.time;
    Attack(actor, 0);
    return qtrue;
}

static qboolean Leap(gentity_t *actor) {
    vec3_t direction, ceiling;
    trace_t trace;
    float distance, seconds = 0.65f;
    if (!actor->enemy || actor->s.groundEntityNum == ENTITYNUM_NONE || level.time < actor->dk.abilityTime ||
        (actor->spawnflags & 128) || !Visible(actor, actor->enemy)) return qfalse;
    VectorSubtract(actor->enemy->r.currentOrigin, actor->r.currentOrigin, direction);
    distance = VectorLength(direction);
    if (distance < 128 || distance > 420 || fabs(direction[2]) > 96) return qfalse;
    VectorCopy(actor->r.currentOrigin, ceiling); ceiling[2] += 80;
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, ceiling, actor->s.number, MASK_PLAYERSOLID);
    if (trace.fraction < 1) return qfalse;
    VectorScale(direction, 1 / seconds, actor->dk.actorVelocity);
    actor->dk.actorVelocity[2] += 0.5f * g_gravity.value * seconds;
    actor->dk.abilityTime = level.time + 3500;
    actor->s.angles[YAW] = vectoyaw(direction);
    actor->s.groundEntityNum = ENTITYNUM_NONE;
    Animation(actor, "jump", ACTOR_WAIT);
    actor->dk.animationLoop = qfalse;
    actor->dk.abilityState = 1;
    return qtrue;
}

static void Idle(gentity_t *actor) {
    dkActorInfo_t *info = Info(actor);
    int i, total = 0, choice;
    if (actor->dk.action == ACTOR_IDLE && level.time - actor->dk.animationTime < AnimationDuration(actor)) return;
    for (i = 0; i < info->animationCount; ++i)
        if (!Q_stricmpn(info->animations[i].name, "amb", 3)) total += info->animations[i].weight;
    if (!total) { DK_ActorHold(actor); return; }
    choice = ActorRandom(actor) % total;
    for (i = 0; i < info->animationCount; ++i) {
        if (Q_stricmpn(info->animations[i].name, "amb", 3)) continue;
        if ((choice -= info->animations[i].weight) < 0) {
            actor->dk.animationTime = 0;
            Animation(actor, info->animations[i].name, ACTOR_IDLE);
            return;
        }
    }
}

static void Roam(gentity_t *actor) {
    dkActorInfo_t *info = Info(actor);
    if (!(actor->spawnflags & (1 | 4 | 8)) && !info->civilian) { Idle(actor); return; }
    if (actor->spawnflags & 128) { Idle(actor); return; }
    if (level.time >= actor->dk.roamUntil || Distance(actor->r.currentOrigin, actor->dk.roamGoal) < 16 || actor->dk.blockedSince) {
        float angle = (ActorRandom(actor) % 65536) * (2 * M_PI / 65536);
        VectorCopy(actor->r.currentOrigin, actor->dk.roamGoal);
        actor->dk.roamGoal[0] += cos(angle) * 128; actor->dk.roamGoal[1] += sin(angle) * 128;
        if (Flying(actor) || info->swimming) actor->dk.roamGoal[2] += (int)(ActorRandom(actor) % 97) - 48;
        actor->dk.roamUntil = level.time + 2500 + ActorRandom(actor) % 2500;
        actor->dk.blockedSince = 0;
    }
    Move(actor, actor->dk.roamGoal, info->walkSpeed > 0 ? info->walkSpeed : 35);
    Animation(actor, "walk", ACTOR_CHASE);
}

static qboolean SpecialActor(gentity_t *actor) {
    const char *name = actor->classname;
    gentity_t *target = actor->enemy;
    if ((!strcmp(name, "monster_froginator") || !strcmp(name, "monster_psyclaw") ||
         !strcmp(name, "monster_spider") || !strcmp(name, "monster_smallspider") || !strcmp(name, "monster_lycanthir"))) {
        if (actor->dk.abilityState == 1) {
            if (actor->s.groundEntityNum == ENTITYNUM_NONE) return qtrue;
            actor->dk.abilityState = 0;
            if (!strcmp(name, "monster_froginator"))
                G_Sound(actor, CHAN_VOICE, DK_SoundIndex("e1/m_frogambb.wav"));
        } else if (Leap(actor)) return qtrue;
    }
    if (!strcmp(name, "monster_medusa")) return Medusa(actor);
    if (!strcmp(name, "monster_wyndrax") && RechargeWyndrax(actor)) return qtrue;
    if (!strcmp(name, "monster_nharre") && Nharre(actor)) return qtrue;
    if (!strcmp(name, "monster_protopod")) {
        if (!actor->dk.abilityState && target && Visible(actor, target) && !(target->client && target->client->noclip)) {
            vec3_t delta;
            VectorSubtract(actor->r.currentOrigin, target->r.currentOrigin, delta); delta[2] = 0;
            if (VectorLength(delta) <= DK_POD_HATCH_RANGE ||
                (VectorLength(delta) <= DK_POD_NOTICE_RANGE && ActorRandom(actor) % 100 < 5)) {
                actor->dk.abilityState = 3;
                actor->dk.abilityTime = level.time + 500 + ActorRandom(actor) % 3001;
            }
        }
        if (actor->dk.abilityState == 3 && level.time >= actor->dk.abilityTime) {
            actor->dk.abilityState = 0;
            Hatch(actor);
        }
        if (actor->dk.abilityState == 1 && level.time >= actor->dk.abilityTime) {
            if (Summon(actor, "monster_slaughterskeet", actor->r.maxs[2] + 28)) {
                actor->dk.abilityState = 2;
                actor->health = 1;
                actor->dk.firstFrame = actor->dk.lastFrame;
                actor->s.frame = actor->dk.lastFrame;
                VectorSet(actor->r.mins, -8, -8, -2);
                VectorSet(actor->r.maxs, 8, 8, 2);
                trap_LinkEntity(actor);
                G_UseTargets(actor, target);
            } else actor->dk.abilityTime = level.time + 500;
        }
        return qtrue;
    }
    if (!strcmp(name, "monster_ghost")) {
        if (level.time >= actor->dk.abilityTime) { G_FreeEntity(actor); return qtrue; }
        if (target && Distance(actor->r.currentOrigin, target->r.currentOrigin) < 72 && Visible(actor, target)) {
            dkActorAttack_t *attack = &Info(actor)->attacks[0];
            DK_ActorStrike(actor, target, DK_W_SWORD, attack->offset, 0, attack->damage, 96, 0, 0);
            G_FreeEntity(actor); return qtrue;
        }
    }
    if (!strcmp(name, "monster_kage") && target && level.time >= actor->dk.abilityTime && Visible(actor, target)) {
        Summon(actor, "monster_ghost", actor->r.maxs[2] + 32);
        actor->dk.abilityTime = level.time + 6000;
    }
    if (!strcmp(name, "monster_cambot") && target && level.time >= actor->dk.abilityTime) {
        int i;
        for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
            gentity_t *ally = &g_entities[i];
            if (ally == actor || !ally->inuse || !ally->dk.actorKind || ally->health <= 0 ||
                Info(ally)->civilian || Info(ally)->companion || Distance(actor->r.currentOrigin, ally->r.currentOrigin) > 1200 ||
                !Visible(actor, ally)) continue;
            ally->enemy = target; ally->dk.lastSeenTime = level.time;
            VectorCopy(target->r.currentOrigin, ally->dk.lastSeenOrigin);
        }
        actor->dk.abilityTime = level.time + 3000;
    }
    return qfalse;
}

static void ActorUse(gentity_t *actor, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (!strcmp(actor->classname, "monster_protopod")) Hatch(actor);
    else if (!strcmp(actor->classname, "monster_rockgat") && (actor->spawnflags & 1))
        actor->dk.turretEnabled = !actor->dk.turretEnabled;
    else DK_UseActorScript(actor, activator);
}

enum { TURRET_CLOSED, TURRET_RAISING, TURRET_OPEN, TURRET_LOWERING };

static void TurretTransition(gentity_t *actor, qboolean raising) {
    actor->dk.animationTime = 0;
    Animation(actor, "up", ACTOR_WAIT);
    actor->dk.firstFrame = 0;
    actor->dk.lastFrame = actor->dk.turretFrames;
    actor->dk.animationLoop = qfalse;
    if (!raising) actor->s.dk3RenderFlags |= DK3_RF_ANIM_REVERSE;
    actor->dk.abilityState = raising ? TURRET_RAISING : TURRET_LOWERING;
    actor->dk.actionTime = level.time + AnimationDuration(actor);
    G_Sound(actor, CHAN_BODY, actor->dk.soundIndices[raising ? 1 : 2]);
}

static void RockgatThink(gentity_t *actor) {
    int i;
    float nearest = actor->dk.attackRange;
    gentity_t *target = NULL;
    vec3_t direction;
    if (actor->dk.abilityState == TURRET_RAISING || actor->dk.abilityState == TURRET_LOWERING) {
        if (level.time < actor->dk.actionTime) return;
        actor->dk.abilityState = actor->dk.abilityState == TURRET_RAISING ? TURRET_OPEN : TURRET_CLOSED;
        actor->dk.firstFrame = actor->dk.lastFrame = actor->dk.abilityState == TURRET_OPEN ? actor->dk.turretFrames : 0;
        actor->s.frame = actor->dk.firstFrame;
        actor->s.dk3RenderFlags &= ~DK3_RF_ANIM_REVERSE;
    }
    if (!(actor->spawnflags & 1) || actor->dk.turretEnabled) for (i = 0; i < level.num_entities; ++i) {
        gentity_t *candidate = &g_entities[i];
        float distance;
        if (!Enemy(actor, candidate)) continue;
        distance = Distance(actor->r.currentOrigin, candidate->r.currentOrigin);
        if (distance < nearest) { nearest = distance; target = candidate; }
    }
    actor->enemy = target;
    if (actor->dk.abilityState == TURRET_CLOSED) {
        if (target || actor->dk.turretEnabled) TurretTransition(actor, qtrue);
        return;
    }
    if (!target) {
        if (!actor->dk.turretEnabled) TurretTransition(actor, qfalse);
        return;
    }
    VectorSubtract(target->r.currentOrigin, actor->r.currentOrigin, direction);
    actor->s.angles[YAW] = vectoyaw(direction);
    VectorCopy(actor->s.angles, actor->r.currentAngles);
    if (level.time < actor->dk.actionTime || !Visible(actor, target)) return;
    VectorNormalize(direction);
    if (direction[2] >= 0.35f) return;
    {
        dkActorAttack_t *attack = &Info(actor)->attacks[0];
        int damage = actor->dk.attackDamage;
        if (actor->dk.attackRandomDamage) damage += ActorRandom(actor) % (actor->dk.attackRandomDamage + 1);
        DK_ActorStrike(actor, target, attack->weapon, attack->offset, attack->speed,
            damage, actor->dk.attackRange, attack->spreadX, attack->spreadZ);
        if (level.time >= actor->dk.abilityTime) {
            G_Sound(actor, CHAN_WEAPON, actor->dk.soundIndices[0]);
            actor->dk.abilityTime = level.time + 220;
        }
        actor->dk.actionTime = level.time + actor->dk.fireInterval + ActorRandom(actor) % 31;
    }
}

void DK_ActorMoveTo(gentity_t *actor, const vec3_t goal) {
    VectorCopy(goal, actor->dk.moveGoal);
    actor->dk.moveActive = 1;
}

static void ActorThink(gentity_t *actor) {
    dkActorInfo_t *info = Info(actor);
    unsigned int id = actor->dk.id;
    if (fabs(actor->r.currentOrigin[0]) > MAX_WORLD_COORD ||
        fabs(actor->r.currentOrigin[1]) > MAX_WORLD_COORD || fabs(actor->r.currentOrigin[2]) > MAX_WORLD_COORD) {
        G_Printf("dk3: actor %u (%s) left world bounds at %.0f %.0f %.0f\n", actor->dk.id, actor->classname,
            actor->r.currentOrigin[0], actor->r.currentOrigin[1], actor->r.currentOrigin[2]);
        if (actor->health > 0) G_Damage(actor, NULL, NULL, NULL, NULL, 100000, DAMAGE_NO_PROTECTION, MOD_TRIGGER_HURT);
        if (actor->inuse && actor->dk.id == id) G_FreeEntity(actor);
        return;
    }
    FrameEvents(actor);
    if (!actor->inuse || actor->dk.id != id) return;
    actor->nextthink = level.time + DK_ACTOR_TICK;
    Physics(actor);
    if (!actor->inuse || actor->dk.id != id) return;
    DK_TouchActorTriggers(actor);
    if (!actor->inuse || actor->dk.id != id) return;
    if (Resurrect(actor) || actor->health <= 0 || (!actor->dk.cinematicControlled && level.time < actor->dk.scriptUntil)) return;
    if (actor->dk.turnActive) {
        int axis, turning = 0;
        for (axis = 0; axis < 3; ++axis) {
            float delta = AngleSubtract(actor->dk.turnGoal[axis], actor->s.angles[axis]);
            float step = actor->dk.yawSpeed * DK_ACTOR_TICK / 1000.0f;
            if (fabs(delta) > step) { delta = delta < 0 ? -step : step; turning = 1; }
            actor->s.angles[axis] = AngleNormalize360(actor->s.angles[axis] + delta);
        }
        VectorCopy(actor->s.angles, actor->r.currentAngles);
        actor->dk.turnActive = turning;
    }
    if (actor->dk.moveActive) {
        float speed = actor->dk.speedOverride > 0 ? actor->dk.speedOverride : info->speed;
        if (Distance(actor->r.currentOrigin, actor->dk.moveGoal) < 8) actor->dk.moveActive = 0;
        else {
            Move(actor, actor->dk.moveGoal, speed);
            Animation(actor, actor->dk.movingAnimation ? actor->dk.movingAnimation : "run", ACTOR_CHASE);
            return;
        }
    }
    if (actor->dk.cinematicControlled) return;
    if (!strcmp(actor->classname, "monster_rockgat")) { RockgatThink(actor); return; }
    if (actor->dk.abilityState == 1 && (!strcmp(actor->classname, "monster_froginator") ||
        !strcmp(actor->classname, "monster_psyclaw") || !strcmp(actor->classname, "monster_spider") ||
        !strcmp(actor->classname, "monster_smallspider") || !strcmp(actor->classname, "monster_lycanthir"))) {
        if (SpecialActor(actor)) return;
    }
    /* Patrol routes do not suppress perception. Scripted moves have already
       been handled above; an alerted patrol resumes its route after combat. */
    if (actor->enemy && !Enemy(actor, actor->enemy)) actor->enemy = NULL;
    if (!actor->enemy && !actor->dk.ignorePlayer && !info->companion) Acquire(actor);
    if (actor->dk.pathTarget && !actor->enemy) {
        gentity_t *corner = DK_FindNamed(actor->dk.pathTarget);
        if (!corner) {
            G_Printf("dk3: actor %u (%s): missing path corner %s\n", actor->dk.id, actor->classname, actor->dk.pathTarget);
            actor->dk.pathTarget = NULL;
        } else if (Distance(actor->r.currentOrigin, corner->r.currentOrigin) < 24) {
            actor->dk.pathTarget = corner->target;
            actor->dk.scriptUntil = level.time + (int)(corner->wait * 1000);
            if (corner->dk.aiScript) DK_StartScript(corner->dk.aiScript, actor, actor, qfalse);
        } else { Pursue(actor, corner); return; }
    }
    if (info->companion && Yield(actor)) return;
    if (info->companion && !actor->dk.companionEnabled) { Animation(actor, "amba", ACTOR_IDLE); return; }
    if (actor->dk.ignorePlayer) { Animation(actor, "amba", ACTOR_IDLE); return; }
    if ((actor->dk.abilityState && (!strcmp(actor->classname, "monster_medusa") ||
         !strcmp(actor->classname, "monster_protopod"))) ||
        (!strcmp(actor->classname, "monster_ghost") && level.time >= actor->dk.abilityTime)) {
        if (SpecialActor(actor)) return;
    }
    if ((actor->dk.action == ACTOR_PAIN || actor->dk.action == ACTOR_ATTACK) && level.time < actor->dk.actionTime &&
        strcmp(actor->classname, "monster_thunderskeet")) return;
    if (actor->enemy && !Enemy(actor, actor->enemy)) actor->enemy = NULL;
    if (!strcmp(actor->classname, "monster_thunderskeet")) {
        if (!actor->enemy) Acquire(actor);
        if (actor->enemy) { ThunderFlight(actor); return; }
    }
    if (actor->enemy && Visible(actor, actor->enemy)) {
        actor->dk.lastSeenTime = level.time;
        VectorCopy(actor->enemy->r.currentOrigin, actor->dk.lastSeenOrigin);
    } else if (actor->enemy && level.time - actor->dk.lastSeenTime < 8000) {
        if (!info->companion || actor->dk.companionOrder != 1)
            PursuePosition(actor, actor->dk.lastSeenOrigin, ENTITYNUM_NONE);
        return;
    } else Acquire(actor);
    if (SpecialActor(actor)) return;
    if (actor->enemy) {
        float distance = Distance(actor->r.currentOrigin, actor->enemy->r.currentOrigin);
        int group = info->companion ? (distance <= 1200 ? 0 : -1) : AttackGroup(actor, distance);
        if (group >= 0 && Visible(actor, actor->enemy)) Attack(actor, group);
        else if ((!info->companion || actor->dk.companionOrder != 1) && !(actor->spawnflags & 32)) Pursue(actor, actor->enemy);
    } else if (info->companion) {
        gentity_t *player = &g_entities[0];
        gentity_t *item = DK_FindEntity(actor->dk.pickupId);
        if (actor->dk.companionOrder != 1) {
            if (!item || !DK_CompanionItemValue(actor, item)) {
                int i;
                float best = 0;
                actor->dk.pickupId = 0; item = NULL;
                if (level.time >= actor->dk.pickupRetry) for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
                    gentity_t *candidate = &g_entities[i];
                    float distance = Distance(actor->r.currentOrigin, candidate->r.currentOrigin);
                    float value = DK_CompanionItemValue(actor, candidate) / (distance + 64);
                    if (distance < 384 && value > best && Visible(actor, candidate)) { best = value; item = candidate; }
                }
                if (item) actor->dk.pickupId = item->dk.id;
                actor->dk.pickupRetry = level.time + 1000;
            }
            if (item) {
                if (Distance(actor->r.currentOrigin, item->r.currentOrigin) < 48) {
                    DK_CompanionPickup(actor, item); actor->dk.pickupId = 0;
                    if (actor->dk.companionOrder == 3) actor->dk.companionOrder = 0;
                } else Pursue(actor, item);
                return;
            }
        }
        if (actor->dk.companionOrder != 1 && player->client && player->health > 0 && Distance(actor->r.currentOrigin, player->r.currentOrigin) > 100)
            Pursue(actor, player);
        else Animation(actor, "amba", ACTOR_IDLE);
    } else Roam(actor);
}

static void Pain(gentity_t *actor, gentity_t *attacker, int damage) {
    (void)damage;
    if (!strcmp(actor->classname, "monster_rockgat") || !strcmp(actor->classname, "monster_protopod")) return;
    if (attacker && attacker != actor) {
        actor->enemy = attacker;
        actor->dk.lastSeenTime = level.time;
        VectorCopy(attacker->r.currentOrigin, actor->dk.lastSeenOrigin);
    }
    if (actor->dk.action == ACTOR_DOWN || level.time < actor->pain_debounce_time) return;
    actor->pain_debounce_time = level.time + 1000;
    Animation(actor, "pain", ACTOR_PAIN);
    actor->dk.actionTime = level.time + AnimationDuration(actor);
}

static void Die(gentity_t *actor, gentity_t *inflictor, gentity_t *attacker, int damage, int mod) {
    unsigned int id = actor->dk.id;
    int weapon = inflictor && inflictor->dk.projectile ? inflictor->s.weapon :
        attacker && attacker->client ? attacker->client->ps.weapon : attacker ? attacker->s.weapon : 0;
    qboolean lycan = !strcmp(actor->classname, "monster_lycanthir");
    qboolean buboid = !strcmp(actor->classname, "monster_buboid");
    qboolean robotic = strstr(actor->classname, "skeet") || strstr(actor->classname, "cambot") ||
        strstr(actor->classname, "deathsphere") || strstr(actor->classname, "rockgat") || strstr(actor->classname, "lasergat") ||
        !strcmp(actor->classname, "monster_protopod");
    qboolean gib = robotic || damage >= actor->dk.maxHealth || actor->health < -actor->dk.maxHealth / 2;
    (void)mod;
    if (actor->dk.action == ACTOR_DEAD) {
        if (actor->health < -actor->dk.maxHealth / 2) {
            DK_WorldDebris(actor, DK_DEBRIS_FLESH);
            G_FreeEntity(actor);
        }
        return;
    }
    if ((lycan && weapon != DK_W_SILVERCLAW) ||
        (buboid && weapon != DK_W_SILVERCLAW && damage < actor->dk.maxHealth / 2)) {
        actor->health = 1;
        if (actor->dk.action != ACTOR_DOWN) {
            Animation(actor, "die", ACTOR_DOWN);
            actor->dk.abilityTime = level.time + (lycan ? 7000 : 10000);
            actor->r.contents = CONTENTS_CORPSE;
            actor->r.maxs[2] = actor->r.mins[2] + 12;
            trap_LinkEntity(actor);
        }
        return;
    }
    actor->s.constantLight = 0;
    Animation(actor, "die", ACTOR_DEAD);
    actor->takedamage = qtrue;
    actor->r.contents = CONTENTS_CORPSE;
    if (Info(actor)->frameBottoms)
        actor->r.mins[2] = Info(actor)->frameBottoms[actor->dk.lastFrame] *
            Info(actor)->modelScale[2] * actor->s.dk3Scale / Info(actor)->scale;
    actor->r.maxs[2] = actor->r.mins[2] + 12;
    trap_LinkEntity(actor);
    DK_AwardExperience(attacker, Info(actor)->health, weapon == DK_W_SWORD);
    DK_DeathSpawn(actor);
    DK_FireNamed(actor->dk.deathTarget, actor, attacker);
    if (!actor->inuse || actor->dk.id != id) return;
    G_UseTargets(actor, attacker);
    if (actor->inuse && actor->dk.id == id && gib && !Info(actor)->companion) {
        DK_WorldDebris(actor, robotic ? DK_DEBRIS_METAL : DK_DEBRIS_FLESH);
        G_AddEvent(actor, EV_GENERAL_SOUND, DK_SoundIndex("global/m_gibexpa.wav"));
        actor->s.modelindex = 0; actor->r.contents = 0; actor->takedamage = qfalse;
        actor->freeAfterEvent = qtrue; trap_LinkEntity(actor);
    }
    if (actor->inuse && actor->dk.id == id && Info(actor)->companion && !actor->dk.cinematicOwned && g_gametype.integer == GT_SINGLE_PLAYER) {
        gentity_t *player = &g_entities[0];
        trap_SendServerCommand(0, "cp \"A companion has died. Load a save to continue.\"");
        if (player->inuse && player->health > 0)
            G_Damage(player, actor, player, NULL, NULL, 100000, DAMAGE_NO_PROTECTION, MOD_SUICIDE);
    }
}

qboolean DK_SpawnActor(gentity_t *actor) {
    const char *name = actor->classname;
    int i;
    if (!strcmp(name, "monster_superfly")) name = "superfly";
    if (!strcmp(name, "fish_goldfish")) name = "e_goldfish";
    if (!strcmp(name, "fish_grayfish")) name = "e_greyfish";
    if (!strcmp(name, "fish_guppy1")) name = "e_guppy";
    if (!strcmp(name, "fish_guppy2")) name = "e_guppy2";
    if (!strcmp(name, "fish_dopefish")) name = "e_dopefish";
    for (i = 0; i < definitionCount; ++i) if (!strcmp(definitions[i].classname, name)) break;
    if (i == definitionCount) return qfalse;
    if (!definitions[i].frames) ReadAnimations(&definitions[i], qtrue);
    actor->dk.actorKind = i + 1;
    actor->dk.ignorePlayer = (actor->spawnflags & 16) != 0;
    actor->dk.runSpeed = definitions[i].speed;
    actor->dk.walkSpeed = definitions[i].walkSpeed;
    actor->dk.actorRandom = actor->dk.id * 2654435761u;
    actor->dk.yawSpeed = 180;
    actor->dk.sightRange = definitions[i].sightRange;
    if (level.spawning) G_SpawnFloat("sight", va("%g", actor->dk.sightRange), &actor->dk.sightRange);
    if (!(actor->dk.sightRange > 0 && actor->dk.sightRange <= 131072))
        G_Error("dk3: actor %u (%s): sight must be between 0 and 131072", actor->dk.id, name);
    if (definitions[i].turret) {
        float interval = !strcmp(name, "monster_rockgat") ? 0.13f : 0.2f;
        actor->dk.attackRange = 512;
        actor->dk.attackDamage = definitions[i].attacks[0].damage;
        actor->dk.attackRandomDamage = definitions[i].attacks[0].randomDamage;
        if (level.spawning) {
            G_SpawnFloat("range", "512", &actor->dk.attackRange);
            G_SpawnFloat("fire_rate", va("%g", interval), &interval);
            G_SpawnInt("basedmg", va("%d", actor->dk.attackDamage), &actor->dk.attackDamage);
            G_SpawnInt("rnddmg", va("%d", actor->dk.attackRandomDamage), &actor->dk.attackRandomDamage);
        }
        if (!(interval >= 0.05f && interval <= 3600) ||
            !(actor->dk.attackRange > 0 && actor->dk.attackRange <= 131072) ||
            actor->dk.attackDamage < 0 || actor->dk.attackDamage > 65535 ||
            actor->dk.attackRandomDamage < 0 || actor->dk.attackRandomDamage > 65535)
            G_Error("dk3: actor %u (%s): invalid range, fire_rate, basedmg or rnddmg", actor->dk.id, name);
        actor->dk.fireInterval = interval * 1000;
    }
    if ((actor->spawnflags & 2) && actor->target) actor->dk.pathTarget = actor->target;
    actor->health = actor->health > 0 ? actor->health : definitions[i].health;
    actor->dk.maxHealth = actor->health;
    if (!strcmp(name, "monster_ghost")) actor->dk.abilityTime = level.time + 15000;
    if (!strcmp(name, "monster_wyndrax")) actor->dk.abilityCharges = 4;
    if (definitions[i].companion) DK_InitCompanionInventory(actor);
    actor->s.dk3Scale = definitions[i].scale;
    if (level.spawning) {
        float multiplier;
        G_SpawnFloat("scale", "1", &multiplier);
        if (!(multiplier > 0 && multiplier <= 16)) G_Error("dk3: actor %u: invalid map scale", actor->dk.id);
        actor->s.dk3Scale *= multiplier;
    }
    actor->takedamage = qtrue;
    actor->s.eType = ET_GENERAL;
    actor->model = G_NewString(definitions[i].model);
    actor->s.modelindex = G_ModelIndex(actor->model);
    if (!Q_stricmp(COM_GetExtension(actor->model), "sp2")) actor->s.dk3RenderFlags |= 2;
    actor->r.contents = !strcmp(name, "monster_wisp") ? 0 : CONTENTS_BODY;
    if (!strcmp(name, "monster_wisp")) actor->takedamage = qfalse;
    actor->clipmask = MASK_PLAYERSOLID;
    VectorCopy(definitions[i].mins, actor->r.mins);
    VectorCopy(definitions[i].maxs, actor->r.maxs);
    G_SetOrigin(actor, actor->s.origin);
    actor->pain = Pain; actor->die = Die; actor->think = ActorThink;
    actor->use = ActorUse;
    actor->nextthink = level.time + DK_ACTOR_TICK;
    Animation(actor, "amba", ACTOR_IDLE);
    if (!strcmp(name, "monster_rockgat")) {
        static const char *keys[] = {"sound", "sound_up", "sound_down"};
        static const char *defaults[] = {"e1/e_rockgatshootmultia.wav", "doors/e1/lift3start.wav", "doors/e1/lift3stop.wav"};
        int sound;
        actor->dk.turretFrames = definitions[i].frames - 1;
        if (level.spawning) {
            G_SpawnInt("height", va("%d", actor->dk.turretFrames), &actor->dk.turretFrames);
            G_SpawnInt("frames", va("%d", actor->dk.turretFrames), &actor->dk.turretFrames);
        }
        if (actor->dk.turretFrames < 0 || actor->dk.turretFrames >= definitions[i].frames)
            G_Error("dk3: turret %u: lift frames exceed supplied model", actor->dk.id);
        for (sound = 0; sound < 3; ++sound) {
            char *path = (char *)defaults[sound];
            if (level.spawning) G_SpawnString(keys[sound], defaults[sound], &path);
            actor->dk.soundIndices[sound] = DK_SoundIndex(path);
        }
        actor->dk.soundCount = 3;
        actor->dk.firstFrame = actor->dk.lastFrame = actor->s.frame = 0;
        actor->dk.animationLoop = qfalse;
    }
    trap_LinkEntity(actor);
    return qtrue;
}

qboolean DK_CompanionCommand(gentity_t *player, const char *command) {
    char operation[64], selection[32];
    gentity_t *target = NULL;
    int i, affected = 0;
    if (Q_stricmp(command, "companion")) return qfalse;
    trap_Argv(1, operation, sizeof(operation)); trap_Argv(2, selection, sizeof(selection));
    if ((strcmp(operation, "follow") && strcmp(operation, "wait") && strcmp(operation, "attack") && strcmp(operation, "pickup")) ||
        (*selection && strcmp(selection, "all") && strcmp(selection, "mikiko") && strcmp(selection, "superfly"))) {
        trap_SendServerCommand(player->s.number, "print \"Use companion <follow|wait|attack|pickup> [mikiko|superfly|all].\n\"");
        return qtrue;
    }
    if (!strcmp(operation, "attack") || !strcmp(operation, "pickup")) {
        vec3_t start, end, forward, mins, maxs;
        trace_t trace;
        VectorCopy(player->client->ps.origin, start); start[2] += player->client->ps.viewheight;
        AngleVectors(player->client->ps.viewangles, forward, NULL, NULL); VectorMA(start, 2048, forward, end);
        trap_Trace(&trace, start, NULL, NULL, end, player->s.number, MASK_SHOT);
        if (trace.entityNum < ENTITYNUM_WORLD) target = &g_entities[trace.entityNum];
        if (!strcmp(operation, "pickup")) {
            int list[MAX_GENTITIES], count, j;
            float nearest = 96;
            target = NULL;
            for (j = 0; j < 3; ++j) { mins[j] = trace.endpos[j] - 96; maxs[j] = trace.endpos[j] + 96; }
            count = trap_EntitiesInBox(mins, maxs, list, ARRAY_LEN(list));
            for (j = 0; j < count; ++j) {
                gentity_t *candidate = &g_entities[list[j]];
                float distance = Distance(candidate->r.currentOrigin, trace.endpos);
                if (candidate->s.eType == ET_DK3_ITEM && distance < nearest) { target = candidate; nearest = distance; }
            }
        }
    }
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *actor = &g_entities[i];
        qboolean mikiko;
        if (!actor->inuse || !DK_IsCompanion(actor) || actor->health <= 0 || !actor->dk.companionEnabled) continue;
        mikiko = strstr(actor->classname, "mikiko") && !strstr(actor->classname, "mikikofly");
        if (!strcmp(selection, "mikiko") && !mikiko) continue;
        if (!strcmp(selection, "superfly") && mikiko) continue;
        if (!strcmp(operation, "pickup")) {
            if (!target || !DK_CompanionItemValue(actor, target)) continue;
            actor->dk.pickupId = target->dk.id; actor->dk.companionOrder = 3;
        } else if (!strcmp(operation, "attack")) {
            if (target && Enemy(actor, target)) actor->enemy = target; else Acquire(actor);
            actor->dk.companionOrder = 2;
        } else {
            actor->dk.companionOrder = !strcmp(operation, "wait") ? 1 : 0;
            actor->dk.pickupId = 0;
        }
        Animation(actor, "amba", ACTOR_IDLE);
        ++affected;
    }
    trap_SendServerCommand(player->s.number, va("cp \"%d companion(s): %s\"", affected, operation));
    return qtrue;
}

qboolean DK_ValidateActorState(gentity_t *actor, const char *savedMap) {
    const char *name = actor->classname;
    dkActorInfo_t *info;
    static dkActorInfo_t variant;
    char model[MAX_QPATH];
    if (!actor->dk.actorKind) return qtrue;
    if (actor->dk.actorKind < 1 || actor->dk.actorKind > definitionCount) return qfalse;
    if (!strcmp(name, "monster_superfly")) name = "superfly";
    if (!strcmp(name, "fish_goldfish")) name = "e_goldfish";
    if (!strcmp(name, "fish_grayfish")) name = "e_greyfish";
    if (!strcmp(name, "fish_guppy1")) name = "e_guppy";
    if (!strcmp(name, "fish_guppy2")) name = "e_guppy2";
    if (!strcmp(name, "fish_dopefish")) name = "e_dopefish";
    info = Info(actor);
    if (!(actor->dk.sightRange > 0 && actor->dk.sightRange <= 131072)) return qfalse;
    if (info->turret && (!(actor->dk.attackRange > 0 && actor->dk.attackRange <= 131072) ||
        actor->dk.fireInterval < 50 || actor->dk.fireInterval > 3600000 ||
        actor->dk.attackDamage < 0 || actor->dk.attackDamage > 65535 ||
        actor->dk.attackRandomDamage < 0 || actor->dk.attackRandomDamage > 65535)) return qfalse;
    ChapterModel(info->classname, info->baseModel, savedMap, model);
    if (!actor->model || Q_stricmp(actor->model, model)) return qfalse;
    if (Q_stricmp(model, info->model)) {
        if (strcmp(variant.model, model)) {
            variant = *info;
            Q_strncpyz(variant.model, model, sizeof(variant.model));
            variant.frames = variant.animationCount = 0;
            ReadAnimations(&variant, qfalse);
        }
        info = &variant;
    }
    if (info->companion) {
        int i;
        if (actor->dk.maxHealth < 1 || actor->dk.maxHealth > 10000 || actor->dk.armor < 0 || actor->dk.armor > 10000 ||
            actor->dk.actorLevel < 1 || actor->dk.actorLevel > 25 || actor->dk.companionOrder < 0 || actor->dk.companionOrder > 3 ||
            actor->s.weapon < 1 || actor->s.weapon >= DK_WEAPON_COUNT) return qfalse;
        for (i = 0; i < MAX_WEAPONS; ++i) if (actor->dk.ammunition[i] < 0 || actor->dk.ammunition[i] > 32767) return qfalse;
        for (i = 0; i < 5; ++i) if (actor->dk.attributes[i] < 0 || actor->dk.attributes[i] > 5) return qfalse;
    }
    return !strcmp(info->classname, name) && actor->dk.attackGroup >= 0 && actor->dk.attackGroup < 3 &&
        actor->dk.action >= ACTOR_IDLE && actor->dk.action <= ACTOR_DOWN && actor->dk.abilityState >= 0 && actor->dk.abilityState <= 3 && actor->dk.animationCursor >= -1 &&
        actor->dk.turretFrames >= 0 && actor->dk.turretFrames < info->frames &&
        actor->dk.turretEnabled >= 0 && actor->dk.turretEnabled <= 1 &&
        actor->dk.animationIndex >= 0 && actor->dk.animationIndex < (info->animationCount ? info->animationCount : 1) &&
        actor->dk.firstFrame >= 0 && actor->dk.lastFrame < info->frames &&
        actor->dk.lastFrame >= actor->dk.firstFrame && actor->dk.animationRate > 0 && actor->dk.animationRate <= 100;
}

void DK_RestoreActor(gentity_t *actor) {
    actor->pain = Pain; actor->die = Die; actor->think = ActorThink; actor->use = ActorUse;
}

/* Camera-bot searchlight is actor presentation, described with the same
   explicit cone used by authored spotlights. Its state follows simulation time. */
static void CameraLight(gentity_t *actor) {
    vec3_t direction, angles, end;
    trace_t trace;
    float sweep = fmod((level.time - actor->dk.animationTime) * 0.08f, 218.0f);
    actor->s.dk3Effect = DK_FX_SPOTLIGHT;
    actor->s.dk3EffectFlags = actor->health > 0 && !actor->dk.cinematicControlled ? DK_FX_ENABLED : 0;
    actor->s.dk3EffectRadius = 2;
    VectorSet(actor->s.dk3EffectColor, 0.6f, 0.6f, 0.1f);
    if (actor->enemy && actor->enemy->health > 0) {
        VectorSubtract(actor->enemy->r.currentOrigin, actor->r.currentOrigin, direction);
        VectorNormalize(direction);
        VectorSet(actor->s.dk3EffectColor, 0.8f, 0.1f, 0.1f);
    } else {
        VectorCopy(actor->s.angles, angles); angles[PITCH] = 45;
        angles[YAW] += -45 + (sweep <= 109 ? sweep : 218 - sweep);
        AngleVectors(angles, direction, NULL, NULL);
    }
    VectorMA(actor->r.currentOrigin, 600, direction, end);
    trap_Trace(&trace, actor->r.currentOrigin, NULL, NULL, end, actor->s.number, MASK_SOLID);
    VectorCopy(trace.endpos, actor->s.dk3EffectEnd);
}

/* Rebuild presentation from authoritative, saved actor state after every world
   frame. The client interpolates motion and animates between authored frames. */
void DK_PublishActors(void) {
    int i, axis;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *actor = &g_entities[i];
        dkActorInfo_t *info;
        if (!actor->inuse || !actor->dk.actorKind) continue;
        info = Info(actor);
        if (!strcmp(actor->classname, "monster_cambot")) CameraLight(actor);
        actor->s.pos.trType = actor->s.apos.trType = TR_INTERPOLATE;
        VectorCopy(actor->r.currentOrigin, actor->s.pos.trBase);
        VectorCopy(actor->s.angles, actor->s.apos.trBase);
        VectorCopy(actor->s.angles, actor->r.currentAngles);
        for (axis = 0; axis < 3; ++axis)
            actor->s.dk3ModelScale[axis] = info->modelScale[axis] * actor->s.dk3Scale / info->scale;
        actor->s.dk3AnimationStart = actor->dk.animationTime;
        actor->s.dk3AnimationFirst = actor->dk.firstFrame;
        actor->s.dk3AnimationLast = actor->dk.lastFrame;
        actor->s.dk3AnimationRate = actor->dk.animationRate;
        actor->s.dk3AnimationLoop = actor->dk.animationLoop;
    }
}
