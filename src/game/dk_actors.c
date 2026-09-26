/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_tables.h"
#include "../qcommon/qfiles.h"
#include "dk_weapons.h"
#include "dk_effects.h"
#include "../botlib/be_aas.h"

#define DK_ACTOR_DEFINITIONS 128
#define DK_ANIMATIONS 256
/* Think every server frame: a fixed 50 ms step ran slow whenever the
   server frame interval did not divide 50 ms (or exceeded it). */
#define DK_ACTOR_TICK (level.time - level.previousTime)
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
    int health, baseHealth, frames, animationCount;
    float mass, speed, walkSpeed, sightRange, attackDistance, fov, scale, yawRate, painChance;
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
static void GarrothSummon(gentity_t *actor, gentity_t *enemy);
static void TraceAttack(gentity_t *actor, const char *animation);

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
    info->baseHealth = DK_Number(row, "basehealth", info->health);
    info->mass = DK_Number(row, "mass", 200);
    info->speed = DK_Number(row, "run_speed", 120);
    info->walkSpeed = DK_Number(row, "walk_speed", info->speed * 0.5f);
    info->sightRange = DK_Number(row, "active_distance", 1200);
    info->attackDistance = DK_Number(row, "attack_distance", 600);
    info->fov = DK_Number(row, "fov", 180);
    {
        /* com_ChangeYaw steps angle_speed degrees once per 100 ms think;
           several spawn functions replace the table value. */
        static const struct { const char *classname; float yaw; } turns[] = {
            {"monster_wyndrax", 180}, {"monster_wizard", 180}, {"monster_thunderskeet", 180}, {"monster_stavros", 180},
            {"monster_rotworm", 180}, {"monster_lasergat", 10}, {"monster_labmonkey", 150}, {"monster_inmater", 180},
            {"hiro", 720}, {"monster_protopod", 90}, {"mikiko", 90}, {"superfly", 90}, {"mikikofly", 90},
            {"monster_deathsphere", 135}
        };
        float pitch, yaw = 20, roll;
        const char *value = DK_Field(row, "angle_speed");
        if (*value && sscanf(value, "%f %f %f", &pitch, &yaw, &roll) < 2) yaw = 20;
        for (i = 0; i < (int)ARRAY_LEN(turns); ++i) if (!strcmp(name, turns[i].classname)) yaw = turns[i].yaw;
        info->yawRate = Com_Clamp(10, 7200, yaw * 10);
    }
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
        if ((!strcmp(name, "monster_froginator") && i == 1) || strstr(name, "venom") || strstr(name, "rotworm") || strstr(name, "spider")) attack->weapon = DK_W_VENOM;
        else if (strstr(name, "rocket")) attack->weapon = DK_W_SIDEWINDER;
        else if (strstr(name, "stavros") || strstr(name, "dragon")) attack->weapon = DK_W_STAVROS;
        else if (strstr(name, "wyndrax")) attack->weapon = DK_W_WYNDRAX;
        else if (strstr(name, "nharre")) attack->weapon = DK_W_NIGHTMARE;
        else if (strstr(name, "cryotech")) attack->weapon = DK_W_KINETICORE;
        else if (strstr(name, "lasergat")) attack->weapon = DK_W_NOVABEAM;
        if (!strcmp(name, "monster_garroth")) attack->weapon = i == 0 ? DK_W_DISRUPTOR : i == 1 ? DK_W_STAVROS : DK_W_WYNDRAX;
        /* Boargun bullets and explosive BoarRockets. */
        if (!strcmp(name, "monster_battleboar")) attack->weapon = i == 1 ? DK_W_SIDEWINDER : DK_W_RIPGUN;
    }
    /* The psyclaw punch is a melee trace; its table speed is unused. */
    if (!strcmp(name, "monster_psyclaw")) info->attacks[0].speed = 0;
    /* The froginator punches anywhere inside its 80-unit spit cutoff. */
    if (!strcmp(name, "monster_froginator") && info->attacks[0].range < 80) info->attacks[0].range = 80;
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
                      !strcmp(name, "monster_prisoner") || !strcmp(name, "monster_prisonerb") || !strcmp(name, "monster_wisp") ||
                      !strcmp(name, "monster_surgeon");
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
        info->sightRange = 1200; info->fov = 180; info->yawRate = 200;
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
float DK_ActorMass(gentity_t *actor) { return actor->dk.actorKind > 0 ? Info(actor)->mass : 300; }

static unsigned int ActorRandom(gentity_t *actor) {
    actor->dk.actorRandom = actor->dk.actorRandom * 1664525u + 1013904223u;
    return actor->dk.actorRandom >> 8;
}

static float ActorFraction(gentity_t *actor) { return (ActorRandom(actor) & 0xffff) / 65536.0f; }

static void ActorSound(gentity_t *actor, const char *name, float volume, float minimum, float maximum) {
    gentity_t *event = G_TempEntity(actor->r.currentOrigin, EV_GENERAL_SOUND);
    event->s.eventParm = DK_SoundIndex(name);
    event->s.dk3SoundVolume = volume; event->s.dk3SoundMin = minimum; event->s.dk3SoundMax = maximum;
}

static int AnimationIndex(dkActorInfo_t *info, const char *name) {
    int i, selected = -1;
    for (i = 0; i < info->animationCount; ++i) {
        if (!Q_stricmp(info->animations[i].name, name)) return i;
        if (selected < 0 && !Q_stricmpn(info->animations[i].name, name, strlen(name))) selected = i;
    }
    return selected;
}

static qboolean Swimming(gentity_t *actor);

static void Animation(gentity_t *ent, const char *name, int state) {
    dkActorInfo_t *info = Info(ent);
    int selected = AnimationIndex(info, name);
    if (selected < 0 && !strcmp(name, "pain")) selected = AnimationIndex(info, "hit");
    if (!strcmp(name, "run") && !info->swimming && Swimming(ent) && AnimationIndex(info, "swim") >= 0) selected = AnimationIndex(info, "swim");
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
            qboolean sludge = !strcmp(actor->classname, "monster_sludgeminion");
            if (!strcmp(actor->classname, "monster_cryotech")) {
                /* Eight bursts sweep right to left across the spray clip. */
                static const vec3_t spray[8] = {
                    {27.28f, 17.30f, 11.96f}, {29.27f, 12.44f, 14.44f}, {30.87f, 6.15f, 16.48f}, {31.36f, 0.15f, 18.29f},
                    {30.82f, -5.34f, 19.59f}, {29.94f, -8.84f, 19.62f}, {29.48f, -11.23f, 17.42f}, {29.53f, -11.39f, 13.50f}};
                int burst = (frame - 9) / 2;
                if (!Q_stricmp(animation->name, "bambb") && frame >= 9 && !((frame - 9) & 1) && burst < 8) {
                    int damage = attack->damage;
                    if (attack->randomDamage > 0) damage += ActorRandom(actor) % (attack->randomDamage + 1);
                    DK_ActorStrike(actor, actor->enemy, attack->weapon, spray[burst],
                                   attack->speed, damage, attack->range, attack->spreadX, attack->spreadZ);
                }
                continue;
            }
            if (!strcmp(actor->classname, "monster_thunderskeet")) {
                /* THUNDERSKEET_Attack: green charge flares on model frames 22-24,
                   then globs on 27, 28, 31 and 32, the second pair on the sine phase. */
                int model = actor->dk.firstFrame + frame - 1;
                if (Q_stricmpn(animation->name, "atak", 4)) continue;
                if (model >= 22 && model <= 24) {
                    vec3_t toward, angles, forward, point;
                    VectorSubtract(actor->enemy->r.currentOrigin, actor->r.currentOrigin, toward);
                    vectoangles(toward, angles); angles[PITCH] -= 35; angles[YAW] += 2;
                    AngleVectors(angles, forward, NULL, NULL);
                    VectorMA(actor->r.currentOrigin, 40, forward, point); point[2] += 40;
                    DK_ZapFlare(point, "models/global/e_flgreen.sp2", 1, 600);
                }
                if (model == 27 || model == 28 || model == 31 || model == 32) {
                    int damage = attack->damage;
                    if (attack->randomDamage > 0) damage += ActorRandom(actor) % (attack->randomDamage + 1);
                    DK_DropToxicBomb(actor, actor->enemy, damage, model >= 31);
                }
                continue;
            }
            if (!strcmp(actor->classname, "monster_inmater") && !Q_stricmp(animation->name, "atakc")) {
                /* aThirdAttackInfo: six laser shots walking across the arm cannon. */
                static const int sweep[6] = {10, 14, 18, 22, 26, 36};
                static const vec3_t muzzle[6] = {{16, 5, 16}, {16, -3, 16}, {16, -11, 16},
                                                 {16, -19, 16}, {16, -27, 16}, {16, -18, 16}};
                int shot;
                attack = &info->attacks[1];
                for (shot = 0; shot < 6; ++shot) if (frame - 1 == sweep[shot]) {
                    int damage = attack->damage;
                    if (attack->randomDamage > 0) damage += ActorRandom(actor) % (attack->randomDamage + 1);
                    DK_ActorStrike(actor, actor->enemy, attack->weapon, muzzle[shot],
                                   attack->speed, damage, attack->range, attack->spreadX, attack->spreadZ);
                }
                continue;
            }
            for (event = 0; event < 2; ++event) {
                int strike = animation->strikes[event];
                if (sludge) {
                    if (Q_stricmpn(animation->name, "atak", 4)) break;
                    attack = &info->attacks[event];
                }
                if (!event && !strike) strike = (frames + 1) / 2;
                if (strike > frames) strike = frames;
                if (strike && frame == strike) {
                    int damage = attack->damage;
                    if (attack->randomDamage > 0) damage += ActorRandom(actor) % (attack->randomDamage + 1);
                    if (sludge) --actor->dk.abilityCharges;
                    if (!strcmp(actor->classname, "monster_garroth") && actor->dk.abilityState == 1) GarrothSummon(actor, actor->enemy);
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
    /* The wraith orb hides the player from monsters that have not yet seen them. */
    if (other->client && other->client->ps.powerups[PW_INVIS] > level.time && !actor->dk.lastSeenTime) return qfalse;
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
    /* Perception is occluded by architecture, not by other actors. A crowd
       below an aircraft must not permanently hide the player from its AI. */
    trap_Trace(&trace, from, NULL, NULL, to, actor->s.number,
               MASK_SOLID | CONTENTS_PLAYERCLIP | CONTENTS_MONSTERCLIP);
    return trace.entityNum == target->s.number || trace.fraction == 1;
}

/* Workers, the surgeon and prisoners run from a threat and cower. */
static qboolean Timid(gentity_t *actor) {
    const char *name = Info(actor)->classname;
    return strstr(name, "worker") || !strcmp(name, "monster_surgeon") ||
           !strcmp(name, "monster_prisoner") || !strcmp(name, "monster_prisonerb");
}

/* AI_EnemyAlert: monsters without an enemy inside the alerter's speak radius
   (default 15% of its active distance) join in when either side can see the
   other or the enemy. The wraith orb keeps the alarm from spreading. */
static void EnemyAlert(gentity_t *actor, gentity_t *enemy) {
    float speak = actor->dk.speakRange > 0 ? actor->dk.speakRange : Info(actor)->sightRange * 0.15f;
    int i;
    if (!enemy || !enemy->inuse || enemy->health <= 0 || (!enemy->client && !enemy->dk.actorKind)) return;
    if (enemy->client && enemy->client->ps.powerups[PW_INVIS] > level.time) return;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *other = &g_entities[i];
        dkActorInfo_t *info;
        if (other == actor || other == enemy || !other->inuse || !other->dk.actorKind || other->health <= 0 ||
            other->enemy || other->dk.ignorePlayer || other->dk.cinematicControlled) continue;
        info = Info(other);
        if (info->companion || (info->civilian && !Timid(other)) || info->turret) continue;
        if (!trap_InPVS(actor->r.currentOrigin, other->r.currentOrigin) &&
            !trap_InPVS(other->r.currentOrigin, enemy->r.currentOrigin)) continue;
        /* Civilians who witness violence panic even outside the short
           voice-alert radius. Architecture still occludes the witness. */
        if (Timid(other) && Distance(other->r.currentOrigin, actor->r.currentOrigin) < info->sightRange &&
            Visible(other, actor)) {
            other->enemy = enemy;
            other->dk.lastSeenTime = level.time;
            VectorCopy(enemy->r.currentOrigin, other->dk.lastSeenOrigin);
            continue;
        }
        if (Distance(other->r.currentOrigin, actor->r.currentOrigin) >= speak &&
            Distance(other->r.currentOrigin, enemy->r.currentOrigin) >= speak) continue;
        if (!Visible(actor, other) && !Visible(other, enemy)) continue;
        other->enemy = enemy;
        if (other->dk.sightRange < 4000) other->dk.sightRange = 4000;
        other->dk.lastSeenTime = level.time;
        VectorCopy(enemy->r.currentOrigin, other->dk.lastSeenOrigin);
    }
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
            /* AI_IsVisible: players need a yaw-only FOV of fov/2 or an XY distance under 256. */
            vec3_t toward;
            VectorSubtract(other->r.currentOrigin, actor->r.currentOrigin, toward);
            if (!pod && !Info(actor)->companion && other->client &&
                fabs(AngleSubtract(vectoyaw(toward), actor->s.angles[YAW])) > Info(actor)->fov * 0.5f &&
                sqrt(toward[0] * toward[0] + toward[1] * toward[1]) >= 256) continue;
            actor->enemy = other; nearest = distance;
        }
    }
    if (actor->enemy) {
        dkActorInfo_t *info = Info(actor);
        if (!previous && (!actor->dk.lastSeenTime || level.time - actor->dk.lastSeenTime > 10000)) {
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
    if (!Info(actor)->flying || actor->dk.groundedFlight || (actor->spawnflags & 64)) return qfalse;
    if (strcmp(actor->classname, "monster_chaingang")) return qtrue;
    VectorCopy(actor->r.currentOrigin, ceiling); ceiling[2] += 96;
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, ceiling, actor->s.number, MASK_SOLID);
    return trace.fraction == 1;
}

static int WaterLevel(gentity_t *actor) {
    vec3_t point;
    int level = 0;
    VectorCopy(actor->r.currentOrigin, point); point[2] += actor->r.mins[2] + 1;
    if (!(trap_PointContents(point, actor->s.number) & MASK_WATER)) return 0;
    ++level;
    point[2] = actor->r.currentOrigin[2] + (actor->r.mins[2] + actor->r.maxs[2]) * 0.5f;
    if (!(trap_PointContents(point, actor->s.number) & MASK_WATER)) return level;
    ++level;
    point[2] = actor->r.currentOrigin[2] + actor->r.maxs[2] - 2;
    return trap_PointContents(point, actor->s.number) & MASK_WATER ? 3 : level;
}

/* The crox and froginator switch to MOVETYPE_SWIM at waist depth. */
static qboolean Swimming(gentity_t *actor) {
    if (Info(actor)->swimming) return qtrue;
    if (strcmp(actor->classname, "monster_crox") && strcmp(actor->classname, "monster_froginator")) return qfalse;
    return WaterLevel(actor) >= 2;
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
        G_Printf("dk3: actor %u (%s) obstructed at %.0f %.0f %.0f hull %.0f %.0f %.0f .. %.0f %.0f %.0f\n", actor->dk.id,
            actor->classname, actor->r.currentOrigin[0], actor->r.currentOrigin[1], actor->r.currentOrigin[2],
            actor->r.mins[0], actor->r.mins[1], actor->r.mins[2], actor->r.maxs[0], actor->r.maxs[1], actor->r.maxs[2]);
        actor->dk.blockedSince = level.time;
    }
    return qfalse;
}

static void Physics(gentity_t *actor) {
    trace_t trace;
    vec3_t destination;
    float dt = DK_ACTOR_TICK / 1000.0f, impact;
    if (actor->dk.parentId || Info(actor)->turret ||
        (actor->health > 0 && (Flying(actor) || Swimming(actor)))) return;
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

/* Turns toward yaw at the actor's rate; returns the remaining difference. */
static float TurnToward(gentity_t *actor, float yaw) {
    float step = Info(actor)->yawRate * DK_ACTOR_TICK / 1000.0f;
    float delta = AngleSubtract(yaw, actor->s.angles[YAW]);
    if (actor->dk.cinematicControlled || fabs(delta) <= step) actor->s.angles[YAW] = AngleNormalize360(yaw);
    else actor->s.angles[YAW] = AngleNormalize360(actor->s.angles[YAW] + (delta < 0 ? -step : step));
    VectorCopy(actor->s.angles, actor->r.currentAngles);
    return fabs(AngleSubtract(yaw, actor->s.angles[YAW]));
}

static void Move(gentity_t *actor, vec3_t goal, float speed) {
    dkActorInfo_t *info = Info(actor);
    vec3_t direction, end, raised, floor;
    trace_t move, ground;
    float step = speed * DK_ACTOR_TICK / 1000.0f * (1 - 0.8f * actor->dk.freezeLevel);
    float distance;
    qboolean swim = Swimming(actor);
    /* FROG_Think damps horizontal swimming velocity by 0.55 each think. */
    if (swim && !info->swimming && !strcmp(actor->classname, "monster_froginator")) step *= 0.55f;
    if (!ClearActorHull(actor)) return;
    VectorSubtract(goal, actor->r.currentOrigin, direction);
    if (!Flying(actor) && !swim && !info->turret) direction[2] = 0;
    distance = VectorNormalize(direction);
    if (distance < step) step = distance;
    if ((actor->spawnflags & 128) || step <= 0 || actor->dk.actorVelocity[2] > 0) return;
    VectorMA(actor->r.currentOrigin, step, direction, end);
    if (info->swimming && !(trap_PointContents(end, actor->s.number) & CONTENTS_WATER)) {
        if (!actor->dk.blockedSince) actor->dk.blockedSince = level.time;
        return;
    }
    trap_Trace(&move, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, end, actor->s.number, MASK_PLAYERSOLID);
    if (move.fraction < 1 && !Flying(actor) && !swim && !info->turret) {
        VectorCopy(actor->r.currentOrigin, raised); raised[2] += DK_STEP_HEIGHT;
        trap_Trace(&ground, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, raised, actor->s.number, MASK_PLAYERSOLID);
        if (ground.fraction == 1) {
            VectorMA(raised, step, direction, end);
            trap_Trace(&ground, raised, actor->r.mins, actor->r.maxs, end, actor->s.number, MASK_PLAYERSOLID);
            if (ground.fraction > move.fraction) move = ground;
        }
    }
    if (!Flying(actor) && !swim && !info->turret) {
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
    if (!actor->dk.cinematicControlled || !actor->dk.turnActive) TurnToward(actor, vectoyaw(direction));
    trap_LinkEntity(actor);
}

static void PursueAt(gentity_t *actor, const vec3_t position, int target, float speed) {
    vec3_t goal;
    trace_t trace;
    VectorCopy(position, goal);
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, goal, actor->s.number, MASK_PLAYERSOLID);
    if (trace.fraction < 1 && trace.entityNum != target &&
        !Flying(actor) && !Swimming(actor) && !Info(actor)->turret && trap_AAS_Initialized()) {
        int travel;
        DK_GroundWaypoint(actor, goal,
            TFL_WALK | TFL_CROUCH | TFL_BARRIERJUMP | TFL_ELEVATOR | TFL_WATER | TFL_AIR, goal, &travel);
    }
    if (Info(actor)->turret) {
        vec3_t waypoint;
        if (!DK_NavigationGoal(actor, goal, 8, target, waypoint)) return;
        VectorCopy(waypoint, goal);
    }
    if (Flying(actor) || Swimming(actor)) {
        vec3_t waypoint;
        if (DK_NavigationGoal(actor, goal, Flying(actor) ? 4 : 2, target, waypoint)) VectorCopy(waypoint, goal);
    }
    Move(actor, goal, speed);
    if (!Info(actor)->turret && actor->dk.blockedSince && level.time - actor->dk.blockedSince > 500) {
        vec3_t forward, side, alternative, before;
        int attempt;
        VectorSubtract(goal, actor->r.currentOrigin, forward); forward[2] = 0; VectorNormalize(forward);
        VectorSet(side, -forward[1], forward[0], 0);
        for (attempt = 0; attempt < 4; ++attempt) {
            VectorCopy(actor->r.currentOrigin, before);
            VectorMA(before, (attempt & 1) ? -72 : 72, side, alternative);
            VectorMA(alternative, attempt < 2 ? 24 : -48, forward, alternative);
            Move(actor, alternative, speed);
            if (Distance(before, actor->r.currentOrigin) > 1) break;
        }
    }
    Animation(actor, actor->dk.movingAnimation ? actor->dk.movingAnimation : "run", ACTOR_CHASE);
}

static void PursuePosition(gentity_t *actor, const vec3_t position, int target) {
    PursueAt(actor, position, target, Info(actor)->speed * (1 + actor->dk.attributes[2] * 0.1f));
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
    if (!strcmp(actor->classname, "monster_psyclaw")) {
        /* Beyond 135 units it blasts, unless the target's view is already
           warped; then it closes in to punch. */
        qboolean warped = actor->enemy && actor->enemy->client && actor->enemy->client->ps.dk3PsyEnd > level.time;
        if (distance > 135 && !warped && info->attacks[1].damage > 0 && distance <= info->attacks[1].range) return 1;
        return distance <= 135 && distance <= info->attacks[0].range ? 0 : -1;
    }
    if (!strcmp(actor->classname, "monster_sludgeminion"))
        return info->attacks[0].damage > 0 && distance <= info->attacks[0].range ? 0 : -1;
    if (!strcmp(actor->classname, "monster_cryotech"))
        return info->attacks[1].damage > 0 && distance <= info->attacks[1].range ? 1 : -1;
    if (!strcmp(actor->classname, "monster_garroth"))
        return distance < 200 ? (distance < info->attacks[0].range ? 0 : -1) : distance <= 600 ? 1 : -1;
    if (!strcmp(actor->classname, "monster_battleboar")) {
        if (distance > 120 && distance <= info->attacks[1].range && ActorRandom(actor) % 100 >= 15) return 1;
        return distance <= info->attacks[0].range ? 0 : distance <= info->attacks[1].range ? 1 : -1;
    }
    if (!strcmp(actor->classname, "monster_froginator")) {
        vec3_t feet;
        VectorCopy(actor->r.currentOrigin, feet); feet[2] += actor->r.mins[2] + 1;
        if (distance <= 80) return 0;
        return distance <= info->attacks[1].range && !(trap_PointContents(feet, actor->s.number) & MASK_WATER) ? 1 : -1;
    }
    if (!strcmp(actor->classname, "monster_inmater")) {
        if (distance <= 128) return 0;
        if (distance > info->attacks[1].range) return -1;
        return ActorRandom(actor) % 4 ? 1 : 2;
    }
    if (!strcmp(actor->classname, "monster_venomvermin"))
        return distance <= 40 ? 0 : distance <= 192 && actor->s.groundEntityNum != ENTITYNUM_NONE ? 1 :
            distance <= info->attacks[2].range ? 2 : -1;
    if (!strcmp(actor->classname, "monster_ragemaster"))
        return distance <= info->attacks[0].range ? 0 : -1;
    for (i = 0; i < 3; ++i) {
        if (info->attacks[i].damage <= 0 || distance > info->attacks[i].range) continue;
        if (!strcmp(actor->classname, "monster_wyndrax") && i == 1 && actor->dk.abilityCharges <= 0) continue;
        if (info->attacks[i].range < range) {
            selected = i; range = info->attacks[i].range; alternatives = 1;
        } else if (info->attacks[i].range == range && ActorRandom(actor) % ++alternatives == 0) selected = i;
    }
    return selected;
}

static void TraceAttack(gentity_t *actor, const char *animation) {
    vec3_t feet;
    if (!trap_Cvar_VariableIntegerValue("dk3_actorTrace")) return;
    VectorCopy(actor->r.currentOrigin, feet); feet[2] += actor->r.mins[2] + 1;
    G_Printf("dk3: actor %u (%s) attack %s group %d charges %d distance %.0f%s\n", actor->dk.id, actor->classname,
        animation, actor->dk.attackGroup, actor->dk.abilityCharges,
        actor->enemy ? Distance(actor->r.currentOrigin, actor->enemy->r.currentOrigin) : 0,
        trap_PointContents(feet, actor->s.number) & MASK_WATER ? " in liquid" : "");
}

static qboolean StartEvade(gentity_t *actor);
static qboolean Evade(gentity_t *actor);

static void Attack(gentity_t *actor, int group) {
    dkActorInfo_t *info = Info(actor);
    vec3_t direction;
    char animation[32];
    gentity_t *target = actor->enemy;
    if (!target || level.time < actor->dk.actionTime) return;
    VectorSubtract(target->r.currentOrigin, actor->r.currentOrigin, direction);
    if (!actor->dk.cinematicControlled || !actor->dk.turnActive) {
        /* AI_IsFacingEnemy: no attack until within 5 degrees of the target. */
        qboolean lasergat = !strcmp(actor->classname, "monster_lasergat");
        if (TurnToward(actor, vectoyaw(direction)) > (lasergat || !strcmp(actor->classname, "monster_inmater") ? 1 : 5) &&
            !info->companion) {
            /* LASERGAT_Turn: servo whine every 0.4 s while it tracks. */
            if (lasergat && level.time % 400 < DK_ACTOR_TICK) ActorSound(actor, "e1/m_lazergatservo.wav", 0.35f, 356, 512);
            if (actor->dk.action != ACTOR_IDLE && !info->turret) Animation(actor, "amba", ACTOR_IDLE);
            return;
        }
    }
    if (!info->companion && !info->turret && !actor->dk.cinematicControlled && StartEvade(actor)) {
        Evade(actor);
        return;
    }
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
    if (!strcmp(actor->classname, "monster_sludgeminion")) {
        /* Out of sludge while standing in it, the minion scoops more before
           resuming its alternating left/right throws. */
        vec3_t feet;
        VectorCopy(actor->r.currentOrigin, feet); feet[2] += actor->r.mins[2] + 1;
        if ((actor->dk.abilityState || actor->dk.abilityCharges <= 0) && (trap_PointContents(feet, actor->s.number) & MASK_WATER) &&
            (!actor->dk.abilityState || actor->dk.abilityCharges < 3 + (int)(ActorRandom(actor) % 6))) {
            if (!actor->dk.abilityState) actor->dk.abilityCharges = actor->dk.abilityCharges < 0 ? 2 + ActorRandom(actor) % 8 : actor->dk.abilityCharges + 3;
            else actor->dk.abilityCharges += 2 + ActorRandom(actor) % 6;
            actor->dk.abilityState = 1;
            G_Sound(actor, CHAN_AUTO, DK_SoundIndex("e1/m_sludgegetmud.wav"));
            actor->dk.animationTime = 0;
            Animation(actor, "ambb", ACTOR_ATTACK); TraceAttack(actor, "ambb");
            actor->dk.actionTime = level.time + AnimationDuration(actor);
            return;
        }
        actor->dk.abilityState = 0;
        Q_strncpyz(animation, ActorRandom(actor) % 5 == 0 ? "atakb" : "ataka", sizeof(animation));
    } else if (!strcmp(actor->classname, "monster_garroth")) {
        /* Punch up close; otherwise, by a skill-scaled chance, cast the stave's
           meteor, a wisp or a Buboid summons, falling back by reach. */
        static const int chance[] = {30, 70, 85};
        float distance = Distance(actor->r.currentOrigin, target->r.currentOrigin);
        float stave = info->attacks[1].range, wisp = info->attacks[2].range;
        int skill = (int)Com_Clamp(0, 2, (trap_Cvar_VariableIntegerValue("g_spSkill") - 1) / 2), choice;
        actor->dk.abilityState = 0;
        if (distance < info->attacks[0].range) {
            actor->dk.attackGroup = 0; Q_strncpyz(animation, "atakc", sizeof(animation));
        } else if ((int)(ActorRandom(actor) % 100) < chance[skill]) {
            choice = ActorRandom(actor) % 3;
            if (choice == 1) group = distance <= stave ? 1 : distance <= wisp ? 2 : -1;
            else if (choice == 2) group = distance <= wisp ? 2 : distance <= stave ? 1 : -1;
            else group = distance <= stave ? -1 : 2;
            if (group < 0) { actor->dk.abilityState = 1; group = 1; }
            actor->dk.attackGroup = group; Q_strncpyz(animation, "ataka", sizeof(animation));
        } else {
            actor->dk.animationTime = 0;
            Animation(actor, "amba", ACTOR_WAIT); TraceAttack(actor, "amba");
            actor->dk.actionTime = level.time + AnimationDuration(actor);
            return;
        }
    } else if (!strcmp(actor->classname, "monster_cryotech")) {
        /* Its only weapon is the sweeping cryo spray, rested three seconds. */
        if (level.time < actor->dk.abilityTime) {
            Animation(actor, "amba", ACTOR_WAIT);
            actor->dk.actionTime = level.time + 100;
            return;
        }
        actor->dk.abilityTime = level.time + 3000;
        Q_strncpyz(animation, "bambb", sizeof(animation));
    } else if (!strcmp(actor->classname, "monster_psyclaw") || !strcmp(actor->classname, "monster_froginator"))
        Q_strncpyz(animation, group == 1 ? "ataka" : "atakb", sizeof(animation));
    else if (!strcmp(actor->classname, "monster_inmater"))
        Q_strncpyz(animation, group == 0 ? "atakb" : group == 1 ? "ataka" : "atakc", sizeof(animation));
    else if (!strcmp(actor->classname, "monster_ragemaster"))
        Q_strncpyz(animation, "atake", sizeof(animation));
    else if (!strcmp(actor->classname, "monster_crox")) {
        /* Surface bites are atakc/atakd; fully submerged, atakb/ataka. */
        qboolean third = ActorFraction(actor) < 0.666f;
        Q_strncpyz(animation, WaterLevel(actor) < 3 ? (third ? "atakc" : "atakd") : (third ? "atakb" : "ataka"), sizeof(animation));
    }
    else if (!strcmp(actor->classname, "monster_venomvermin")) {
        /* Gold asks for atakd mid-leap; the model lacks it, so the run clip plays. */
        Q_strncpyz(animation, group == 0 ? "ataka" : group == 1 ? "runa" : "atakc", sizeof(animation));
        if (group == 1) {
            vec3_t forward;
            AngleVectors(actor->s.angles, forward, NULL, NULL);
            VectorScale(forward, actor->dk.runSpeed * 1.5f, actor->dk.actorVelocity);
            actor->dk.actorVelocity[2] = 150;
            actor->s.groundEntityNum = ENTITYNUM_NONE;
        }
    } else if (!strcmp(actor->classname, "monster_mishimaguard")) {
        /* An eight-round pistol: reload when empty, change pose every four shots. */
        if (actor->dk.abilityCharges <= 0) {
            actor->dk.abilityCharges = 8;
            actor->dk.animationTime = 0;
            Animation(actor, "reload", ACTOR_WAIT); TraceAttack(actor, "reload");
            ActorSound(actor, "global/i_scammo.wav", 0.75f, 256, 512);
            actor->dk.actionTime = level.time + AnimationDuration(actor) + 500 + (int)(ActorFraction(actor) * 1000);
            return;
        }
        if (actor->dk.abilityCharges % 4 == 0) Com_sprintf(animation, sizeof(animation), "atak%c", 'a' + ActorRandom(actor) % 3);
        else Q_strncpyz(animation, "ataka", sizeof(animation));
        --actor->dk.abilityCharges;
    } else Com_sprintf(animation, sizeof(animation), "atak%c", 'a' + group);
    if (AnimationIndex(info, animation) < 0) Q_strncpyz(animation, "atak", sizeof(animation));
    actor->dk.animationTime = 0;
    Animation(actor, animation, ACTOR_ATTACK); TraceAttack(actor, actor->dk.abilityState == 1 &&
        !strcmp(actor->classname, "monster_garroth") ? "summon" : animation);
    actor->dk.actionTime = level.time + AnimationDuration(actor) + 200;
}

static float Room(gentity_t *actor, float reach) {
    trace_t trace;
    vec3_t end;
    VectorCopy(actor->r.currentOrigin, end); end[2] += reach;
    trap_Trace(&trace, actor->r.currentOrigin, NULL, NULL, end, actor->s.number, MASK_SOLID);
    return trace.fraction * fabs(reach);
}

/* thunderskeet.cpp: chase toward a point 96 units above the target, fire,
   then hover 2.75 s. Too low or out of sight, it hovers, rising at 64 units
   per second while there is headroom. abilityState is chase, hover, attack;
   abilityCharges marks a rising hover. */
enum { THUNDER_CHASE, THUNDER_HOVER, THUNDER_ATTACK };

static void ThunderHover(gentity_t *actor) {
    actor->dk.abilityState = THUNDER_HOVER; actor->dk.abilityTime = level.time + 2750;
    actor->dk.abilityCharges = Room(actor, 1024) > 128;
    Animation(actor, "flya", ACTOR_CHASE);
}

static void ThunderFlight(gentity_t *actor) {
    gentity_t *target = actor->enemy;
    vec3_t goal, facing;
    float distance;
    if (!target) return;
    VectorSubtract(target->r.currentOrigin, actor->r.currentOrigin, facing);
    distance = VectorLength(facing);
    if (actor->dk.abilityState == THUNDER_ATTACK || actor->dk.action == ACTOR_ATTACK) {
        actor->s.angles[YAW] = vectoyaw(facing); VectorCopy(actor->s.angles, actor->r.currentAngles);
        if (level.time < actor->dk.actionTime) return;
        ThunderHover(actor);
    }
    if (actor->dk.abilityState == THUNDER_HOVER) {
        TurnToward(actor, vectoyaw(facing));
        if (level.time < actor->dk.abilityTime) {
            if (actor->dk.abilityCharges || (distance < 128 && Room(actor, -1024) > 128)) {
                trace_t trace;
                vec3_t end;
                VectorCopy(actor->r.currentOrigin, end); end[2] += 64 * DK_ACTOR_TICK / 1000.0f;
                trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, end, actor->s.number, MASK_PLAYERSOLID);
                if (!trace.startsolid) { G_SetOrigin(actor, trace.endpos); trap_LinkEntity(actor); }
                if (trace.fraction < 1) actor->dk.abilityCharges = 0;
            }
            return;
        }
        actor->dk.abilityState = THUNDER_CHASE;
    }
    if (!Visible(actor, target) || (target->client && target->client->ps.powerups[PW_INVIS] > level.time) ||
        fabs(facing[2]) < 96) {
        ThunderHover(actor);
        return;
    }
    if (distance < Info(actor)->attackDistance) {
        if (level.time >= actor->dk.actionTime) {
            Attack(actor, 0);
            if (actor->dk.action == ACTOR_ATTACK) actor->dk.abilityState = THUNDER_ATTACK;
        }
        return;
    }
    VectorCopy(target->r.currentOrigin, goal); goal[2] += 96;
    PursuePosition(actor, goal, ENTITYNUM_NONE);
    Animation(actor, "flya", ACTOR_CHASE);
}

/* cambot.cpp: a camera that never attacks. It patrols path corners at walk
   speed until it sees a player, then turns red, sounds the alarm, alerts nearby
   monsters and tails that player for good, 72 to 192 units away. abilityState
   is 0 searching, 1 alerted, 2 alerted and dodging; abilityCharges marks a
   floor or ceiling clearance move toward moveGoal until abilityTime. */
enum { CAMBOT_SEARCHING, CAMBOT_ALERTED, CAMBOT_DODGING };
static const float cambotWave[12] = {0.017f, 0.515f, 0.874f, 0.999f, 0.857f, 0.484f,
                                     -0.017f, -0.515f, -0.874f, -0.999f, -0.857f, -0.484f};

/* CAMBOT_IsVisible: 60% up both hulls, within 75 degrees of its yaw, and clear
   from both sides of its body. */
static qboolean CambotSees(gentity_t *actor, gentity_t *target) {
    trace_t trace;
    vec3_t from, to, toward, side, point;
    float half = (actor->r.maxs[0] - actor->r.mins[0]) * 0.6f, yaw;
    int i;
    VectorCopy(actor->r.currentOrigin, from); from[2] += (actor->r.maxs[2] - actor->r.mins[2]) * 0.6f;
    VectorCopy(target->r.currentOrigin, to); to[2] += (target->r.maxs[2] - target->r.mins[2]) * 0.6f;
    if (!trap_InPVS(from, to)) return qfalse;
    trap_Trace(&trace, from, NULL, NULL, to, actor->s.number, MASK_SOLID);
    if (trace.fraction < 1) return qfalse;
    VectorSubtract(target->r.currentOrigin, actor->r.currentOrigin, toward);
    yaw = fabs(AngleSubtract(vectoyaw(toward), actor->s.angles[YAW]));
    if (yaw >= 75) return qfalse;
    toward[2] = 0; VectorNormalize(toward);
    VectorSet(side, -toward[1], toward[0], 0);
    for (i = 0; i < 2; ++i) {
        VectorMA(from, i ? -half : half, side, point);
        trap_Trace(&trace, point, NULL, NULL, to, actor->s.number, MASK_SOLID);
        if (trace.fraction < 1) return qfalse;
    }
    return qtrue;
}

/* CAMBOT_FoundPlayer: the alarm and the alert are sent once. The original
   compares the camera-to-player distance, not each monster's, against 1024. */
static void CambotFound(gentity_t *actor, gentity_t *enemy) {
    int i;
    actor->enemy = enemy; actor->dk.abilityState = CAMBOT_ALERTED; actor->dk.sightRange = 5000;
    actor->dk.lastSeenTime = level.time; VectorCopy(enemy->r.currentOrigin, actor->dk.lastSeenOrigin);
    ActorSound(actor, "e1/m_cambotalarm.wav", 0.85f, 128, 1000);
    if (Distance(actor->r.currentOrigin, enemy->r.currentOrigin) >= 1024) return;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *ally = &g_entities[i];
        if (ally == actor || !ally->inuse || !ally->dk.actorKind || ally->health <= 0 ||
            Info(ally)->civilian || Info(ally)->companion || !trap_InPVS(actor->r.currentOrigin, ally->r.currentOrigin)) continue;
        ally->enemy = enemy; ally->dk.lastSeenTime = level.time;
        VectorCopy(enemy->r.currentOrigin, ally->dk.lastSeenOrigin);
    }
}

static void CambotFace(gentity_t *actor, const vec3_t point, qboolean pitch) {
    vec3_t toward, angles;
    float step = 90 * DK_ACTOR_TICK / 1000.0f;
    int axis;
    VectorSubtract(point, actor->r.currentOrigin, toward);
    vectoangles(toward, angles);
    if (!pitch) angles[PITCH] = 0;
    for (axis = PITCH; axis <= YAW; ++axis) {
        float delta = AngleSubtract(angles[axis], actor->s.angles[axis]);
        actor->s.angles[axis] = AngleNormalize360(actor->s.angles[axis] + Com_Clamp(-step, step, delta));
    }
    actor->s.angles[ROLL] = 0;
    VectorCopy(actor->s.angles, actor->r.currentAngles);
}

/* Flight moves keep the camera's own facing rather than the travel yaw. */
static void CambotMove(gentity_t *actor, const vec3_t goal, float speed) {
    vec3_t angles;
    VectorCopy(actor->s.angles, angles);
    Move(actor, (float *)goal, speed);
    VectorCopy(angles, actor->s.angles); VectorCopy(angles, actor->r.currentAngles);
}

/* A player targets the camera when it sits under the crosshair; monsters when facing it. */
static qboolean CambotTargeted(gentity_t *actor, gentity_t *enemy) {
    vec3_t forward, toward;
    if (enemy->client) AngleVectors(enemy->client->ps.viewangles, forward, NULL, NULL);
    else AngleVectors(enemy->s.angles, forward, NULL, NULL);
    VectorSubtract(actor->r.currentOrigin, enemy->r.currentOrigin, toward);
    VectorNormalize(toward);
    return DotProduct(forward, toward) > (enemy->client ? 0.97f : 0.5f);
}

/* CAMBOT_FindBackAwayPointFromEnemy: straight back and a little up, else the
   clearer of the two sides 60 degrees off it. */
static qboolean CambotBackAway(gentity_t *actor, gentity_t *enemy, vec3_t point) {
    static const vec3_t mins = {-8, -8, -8}, maxs = {8, 8, 8};
    trace_t trace;
    vec3_t direction, sides[2], end;
    float clear[2], speed = Info(actor)->walkSpeed * 2 * 0.15f;
    int i;
    VectorSubtract(actor->r.currentOrigin, enemy->r.currentOrigin, direction);
    direction[2] = 0; VectorNormalize(direction);
    if (fabs(actor->r.currentOrigin[2] - enemy->r.currentOrigin[2]) < 72) direction[2] = 0.2f;
    VectorNormalize(direction);
    VectorMA(actor->r.currentOrigin, 72, direction, point);
    trap_Trace(&trace, actor->r.currentOrigin, mins, maxs, point, actor->s.number, MASK_SOLID);
    if (trace.fraction >= 1) return qtrue;
    for (i = 0; i < 2; ++i) {
        float angle = (i ? 60 : -60) * M_PI / 180;
        sides[i][0] = direction[0] * cos(angle) - direction[1] * sin(angle);
        sides[i][1] = direction[0] * sin(angle) + direction[1] * cos(angle);
        sides[i][2] = direction[2];
        VectorMA(actor->r.currentOrigin, 1024, sides[i], end);
        trap_Trace(&trace, actor->r.currentOrigin, mins, maxs, end, actor->s.number, MASK_SOLID);
        clear[i] = trace.fraction * 1024;
    }
    i = clear[0] >= 72 && (clear[1] < 72 || clear[0] >= clear[1]) ? 0 : clear[1] >= 72 ? 1 : -1;
    if (i < 0) return qfalse;
    VectorMA(actor->r.currentOrigin, speed, sides[i], point);
    return qtrue;
}

/* AI_ComputeFlyAwayPoint: 250 units at a random bearing, shrinking by 35%
   while blocked, through a hull a quarter larger than the camera's. */
static qboolean CambotDodge(gentity_t *actor) {
    trace_t trace;
    vec3_t mins, maxs, point;
    float distance = 250, bearing = ActorFraction(actor) * 360, turn = ActorFraction(actor) > 0.5f ? 10 : -10;
    int i;
    VectorScale(actor->r.mins, 1.25f, mins); VectorScale(actor->r.maxs, 1.25f, maxs);
    for (; distance > 100; distance *= 0.65f) {
        for (i = 0; i < 36; ++i, bearing += turn) {
            float angle = bearing * M_PI / 180;
            VectorCopy(actor->r.currentOrigin, point);
            point[0] += cos(angle) * distance; point[1] += sin(angle) * distance;
            point[2] += (ActorFraction(actor) * 2 - 1) * distance * 0.5f;
            trap_Trace(&trace, actor->r.currentOrigin, mins, maxs, point, actor->s.number, MASK_SOLID | CONTENTS_BODY);
            if (trace.fraction >= 1) {
                VectorCopy(point, actor->dk.moveGoal);
                actor->dk.abilityState = CAMBOT_DODGING;
                return qtrue;
            }
        }
    }
    return qfalse;
}

static void CambotFollow(gentity_t *actor) {
    gentity_t *enemy = actor->enemy;
    float speed = Info(actor)->walkSpeed * 2, distance;
    vec3_t delta, point;
    if (!Visible(actor, enemy)) {
        actor->dk.abilityState = CAMBOT_ALERTED;
        PursueAt(actor, enemy->r.currentOrigin, enemy->s.number, Info(actor)->speed);
        CambotFace(actor, enemy->r.currentOrigin, qtrue);
        Animation(actor, "fly", ACTOR_CHASE);
        return;
    }
    actor->dk.lastSeenTime = level.time; VectorCopy(enemy->r.currentOrigin, actor->dk.lastSeenOrigin);
    CambotFace(actor, enemy->r.currentOrigin, qtrue);
    if (actor->dk.abilityState == CAMBOT_DODGING) {
        vec3_t before;
        VectorCopy(actor->r.currentOrigin, before);
        CambotMove(actor, actor->dk.moveGoal, speed);
        if (Distance(actor->r.currentOrigin, actor->dk.moveGoal) < 16 || Distance(before, actor->r.currentOrigin) < 0.5f)
            actor->dk.abilityState = CAMBOT_ALERTED;
        Animation(actor, "fly", ACTOR_CHASE);
        return;
    }
    VectorSubtract(enemy->r.currentOrigin, actor->r.currentOrigin, delta); delta[2] = 0;
    distance = VectorLength(delta);
    if (distance < 72) {
        trace_t trace;
        if (CambotBackAway(actor, enemy, point) && trap_InPVS(enemy->r.currentOrigin, point)) {
            trap_Trace(&trace, enemy->r.currentOrigin, NULL, NULL, point, enemy->s.number, MASK_SOLID);
            if (trace.fraction >= 1) { CambotMove(actor, point, speed); Animation(actor, "fly", ACTOR_CHASE); return; }
        }
    } else if (distance <= 192) {
        /* A quarter of the original's 100 ms decisions, at this 50 ms tick. */
        if (ActorFraction(actor) < 0.134f && CambotTargeted(actor, enemy) && CambotDodge(actor)) return;
    } else {
        VectorCopy(enemy->r.currentOrigin, point); point[2] += 72;
        CambotMove(actor, point, speed);
        Animation(actor, "fly", ACTOR_CHASE);
        return;
    }
    Animation(actor, "amba", ACTOR_IDLE);
}

static void CambotPatrol(gentity_t *actor) {
    gentity_t *corner = actor->dk.pathTarget ? DK_FindNamed(actor->dk.pathTarget) : NULL;
    vec3_t delta;
    if (!corner) {
        if (actor->dk.pathTarget)
            G_Printf("dk3: actor %u (%s): missing path corner %s\n", actor->dk.id, actor->classname, actor->dk.pathTarget);
        actor->dk.pathTarget = NULL;
        Animation(actor, "amba", ACTOR_IDLE);
        return;
    }
    VectorSubtract(corner->r.currentOrigin, actor->r.currentOrigin, delta);
    if (fabs(delta[2]) < 32 && sqrt(delta[0] * delta[0] + delta[1] * delta[1]) < 24) {
        actor->dk.pathTarget = corner->target;
        actor->dk.scriptUntil = level.time + (int)(corner->wait * 1000);
        if (corner->dk.aiScript) DK_StartScript(corner->dk.aiScript, actor, actor, qfalse);
        return;
    }
    PursueAt(actor, corner->r.currentOrigin, ENTITYNUM_NONE, Info(actor)->walkSpeed);
    CambotFace(actor, corner->r.currentOrigin, qfalse);
    Animation(actor, "fly", ACTOR_CHASE);
}

/* CAMBOT_Think: a 1.2 s sine bob of 15 units/s, the hover tone and random
   control chatter on that cycle, and 32 units of floor and ceiling clearance. */
static void CambotPresence(gentity_t *actor) {
    trace_t trace;
    vec3_t end;
    int phase = (level.time / 100) % 12;
    qboolean patrolling = actor->dk.abilityState == CAMBOT_SEARCHING && actor->dk.pathTarget;
    VectorCopy(actor->r.currentOrigin, end);
    end[2] += 15 * cambotWave[phase] * DK_ACTOR_TICK / 1000.0f;
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, end, actor->s.number, MASK_PLAYERSOLID);
    if (!trace.startsolid) { G_SetOrigin(actor, trace.endpos); trap_LinkEntity(actor); }
    if (level.time % 100 < DK_ACTOR_TICK) {
        if (phase == 1) {
            if (patrolling) ActorSound(actor, "global/e_roomtoned.wav", 0.65f, 256, 648);
            else ActorSound(actor, "global/e_roomtonee.wav", 0.75f, 256, 648);
        } else if (phase == 5 && ActorFraction(actor) > (actor->enemy && !Visible(actor, actor->enemy) ? 0.30f : 0.65f)) {
            ActorSound(actor, va("global/e_cntrltone%c.wav", 'a' + (int)(ActorFraction(actor) * 9)), 0.65f, 256, 648);
        }
    }
    if (actor->dk.abilityCharges) {
        CambotMove(actor, actor->dk.moveGoal, Info(actor)->walkSpeed * 2);
        if (level.time >= actor->dk.abilityTime || Distance(actor->r.currentOrigin, actor->dk.moveGoal) < 16)
            actor->dk.abilityCharges = 0;
        return;
    }
    VectorCopy(actor->r.currentOrigin, end); end[2] -= 300;
    trap_Trace(&trace, actor->r.currentOrigin, NULL, NULL, end, actor->s.number, MASK_PLAYERSOLID);
    if (trace.fraction * 300 < 32) {
        VectorCopy(actor->r.currentOrigin, actor->dk.moveGoal); actor->dk.moveGoal[2] += 96 + 128 * ActorFraction(actor);
    } else {
        VectorCopy(actor->r.currentOrigin, end); end[2] += 300;
        trap_Trace(&trace, actor->r.currentOrigin, NULL, NULL, end, actor->s.number, MASK_SOLID);
        if (trace.fraction * 300 >= 32) return;
        VectorCopy(actor->r.currentOrigin, actor->dk.moveGoal); actor->dk.moveGoal[2] -= 96 + 128 * ActorFraction(actor);
    }
    actor->dk.abilityCharges = 1; actor->dk.abilityTime = level.time + 3000;
}

static void CambotThink(gentity_t *actor) {
    int i;
    CambotPresence(actor);
    if (actor->dk.abilityCharges) return;
    if (actor->enemy && (!actor->enemy->inuse || actor->enemy->health <= 0)) {
        actor->enemy = NULL; actor->dk.abilityState = CAMBOT_SEARCHING;
    }
    if (actor->enemy && actor->dk.abilityState == CAMBOT_SEARCHING) CambotFound(actor, actor->enemy);
    if (!actor->enemy && !actor->dk.ignorePlayer) {
        for (i = 0; i < level.num_entities; ++i) {
            gentity_t *other = &g_entities[i];
            if ((other->client || DK_IsCompanion(other)) && Enemy(actor, other) &&
                Distance(actor->r.currentOrigin, other->r.currentOrigin) < actor->dk.sightRange && CambotSees(actor, other)) {
                CambotFound(actor, other);
                break;
            }
        }
    }
    if (actor->enemy) CambotFollow(actor);
    else CambotPatrol(actor);
    if (level.time % 1000 < DK_ACTOR_TICK && trap_Cvar_VariableIntegerValue("dk3_actorTrace")) {
        vec3_t delta;
        if (actor->enemy) VectorSubtract(actor->enemy->r.currentOrigin, actor->r.currentOrigin, delta);
        else VectorClear(delta);
        G_Printf("dk3: actor %u (%s) camera state %d path %s xy %.0f height %.0f\n", actor->dk.id, actor->classname,
            actor->dk.abilityState, actor->dk.pathTarget ? actor->dk.pathTarget : "-",
            sqrt(delta[0] * delta[0] + delta[1] * delta[1]), -delta[2]);
    }
}

static qboolean Targeted(gentity_t *actor, gentity_t *enemy);
static qboolean SideStepPoint(gentity_t *actor, float distance, vec3_t point);

/* AI_ComputeBestAwayYawPoint: the clearest of the yaw samples, favoring
   directions away from the enemy. */
static qboolean AwayPoint(gentity_t *actor, float distance, int resolution, qboolean pitch, vec3_t point) {
    float best = -100000, start = ActorFraction(actor) * 360;
    int i;
    for (i = 0; i < 360 / resolution; ++i) {
        trace_t trace;
        vec3_t angles, direction, goal, away;
        float score;
        VectorSet(angles, pitch ? (ActorFraction(actor) * 2 - 1) * 30 : 0, start + i * resolution, 0);
        AngleVectors(angles, direction, NULL, NULL);
        VectorMA(actor->r.currentOrigin, distance, direction, goal);
        trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, goal, actor->s.number, MASK_PLAYERSOLID);
        if (trace.startsolid || trace.fraction * distance < 48) continue;
        score = trace.fraction * distance;
        if (actor->enemy) {
            VectorSubtract(actor->r.currentOrigin, actor->enemy->r.currentOrigin, away); VectorNormalize(away);
            score += DotProduct(away, direction) * 128;
        }
        if (score > best) { best = score; VectorCopy(trace.endpos, point); }
    }
    return best > -100000;
}

/* deathsphere.cpp: a hovering orb that bobs, steams away from floors and
   ceilings, charges for 0.75 s, then fires its four muzzles on the ready frame
   and twice more four frames later. Aimed at, it darts off. abilityState is
   chase, charge, attack, or a short dart toward moveGoal until abilityTime. */
enum { SPHERE_CHASE, SPHERE_CHARGE, SPHERE_ATTACK, SPHERE_MOVE };

static void SphereDart(gentity_t *actor, const vec3_t goal) {
    VectorCopy(goal, actor->dk.moveGoal);
    actor->dk.abilityState = SPHERE_MOVE; actor->dk.abilityTime = level.time + 250;
    ActorSound(actor, "e1/m_dspheresteama.wav", 0.85f, 256, 512);
    TraceAttack(actor, "dart");
}

static qboolean SphereAvoid(gentity_t *actor) {
    vec3_t point;
    if (actor->dk.abilityState == SPHERE_MOVE || !AwayPoint(actor, 500, 20, qfalse, point)) return qfalse;
    SphereDart(actor, point);
    return qtrue;
}

static void SphereVolley(gentity_t *actor) {
    /* Gold muzzles are right, forward, up; strikes take forward, right, up. */
    static const vec3_t muzzles[4] = {{10.90f, 1.21f, 27.18f}, {11.05f, 23.99f, 9.38f},
                                      {11.05f, 0.77f, -7.40f}, {11.05f, -24.23f, 9.21f}};
    dkActorAttack_t *attack = &Info(actor)->attacks[0];
    int i;
    ActorSound(actor, "e1/m_dsphereatak.wav", 1, 256, 648);
    for (i = 0; i < 4; ++i) {
        int damage = attack->damage;
        if (attack->randomDamage > 0) damage += ActorRandom(actor) % (attack->randomDamage + 1);
        DK_ActorStrike(actor, actor->enemy, attack->weapon, muzzles[i], attack->speed, damage, attack->range, 0, 0);
    }
}

static qboolean SpherePresence(gentity_t *actor) {
    trace_t trace;
    vec3_t end;
    int phase = (level.time / 100) % 12;
    VectorCopy(actor->r.currentOrigin, end);
    end[2] += 15 * cambotWave[phase] * DK_ACTOR_TICK / 1000.0f;
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, end, actor->s.number, MASK_PLAYERSOLID);
    if (!trace.startsolid) { G_SetOrigin(actor, trace.endpos); trap_LinkEntity(actor); }
    actor->s.loopSound = DK_SoundIndex(actor->enemy ? "e1/m_dspherehovera.wav" : "e1/m_dspherehoverf.wav");
    if (actor->dk.abilityState == SPHERE_MOVE) {
        if (level.time < actor->dk.abilityTime && Distance(actor->r.currentOrigin, actor->dk.moveGoal) > 34) {
            float yaw = actor->s.angles[YAW];
            Move(actor, actor->dk.moveGoal, Info(actor)->speed);
            actor->s.angles[YAW] = yaw; VectorCopy(actor->s.angles, actor->r.currentAngles);
            Animation(actor, "flya", ACTOR_CHASE);
            return qtrue;
        }
        actor->dk.abilityState = SPHERE_CHASE;
    }
    if (actor->dk.abilityState != SPHERE_CHASE) return qfalse;
    VectorCopy(actor->r.currentOrigin, end); end[2] -= 300;
    trap_Trace(&trace, actor->r.currentOrigin, NULL, NULL, end, actor->s.number, MASK_SOLID);
    if (trace.fraction * 300 < 32) {
        VectorCopy(actor->r.currentOrigin, end); end[2] += 96 + 128 * ActorFraction(actor);
        SphereDart(actor, end);
        return qtrue;
    }
    VectorCopy(actor->r.currentOrigin, end); end[2] += 300;
    trap_Trace(&trace, actor->r.currentOrigin, NULL, NULL, end, actor->s.number, MASK_SOLID);
    if (trace.fraction * 300 < 32) {
        VectorCopy(actor->r.currentOrigin, end); end[2] -= 96 + 128 * ActorFraction(actor);
        SphereDart(actor, end);
        return qtrue;
    }
    return qfalse;
}

static void SphereThink(gentity_t *actor) {
    dkActorInfo_t *info = Info(actor);
    gentity_t *enemy = actor->enemy;
    vec3_t toward, ahead, forward;
    trace_t trace;
    int ataka = AnimationIndex(info, "ataka"), frame, strike;
    float facing;
    VectorSubtract(enemy->r.currentOrigin, actor->r.currentOrigin, toward);
    if (actor->dk.abilityState == SPHERE_CHASE) {
        if (VectorLength(toward) > info->attackDistance || !Visible(actor, enemy)) { Pursue(actor, enemy); return; }
        actor->dk.abilityState = SPHERE_CHARGE; actor->dk.abilityTime = level.time + 750;
        actor->dk.animationTime = 0; Animation(actor, "ready", ACTOR_WAIT); TraceAttack(actor, "ready");
        ActorSound(actor, "e1/m_dspherechargea.wav", 0.4f, 400, 512);
    }
    facing = TurnToward(actor, vectoyaw(toward));
    if (actor->dk.abilityState == SPHERE_CHARGE) {
        if (level.time < actor->dk.abilityTime) return;
        actor->dk.abilityState = SPHERE_ATTACK; actor->dk.abilityCharges = -1;
    }
    if (level.time % 100 < DK_ACTOR_TICK && Targeted(actor, enemy) && ActorFraction(actor) >= 0.5f && SphereAvoid(actor)) return;
    AngleVectors(actor->s.angles, forward, NULL, NULL);
    VectorMA(actor->r.currentOrigin, 64, forward, ahead);
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, ahead, actor->s.number, MASK_SOLID);
    if (trace.fraction < 1) {
        if (SideStepPoint(actor, 96, ahead)) SphereDart(actor, ahead);
        else actor->dk.abilityState = SPHERE_CHASE;
        return;
    }
    if (actor->dk.abilityCharges < 0) {
        /* deathsphere_set_attack_seq: within 2 degrees, or it avoids. */
        if (facing > 2) { if (!SphereAvoid(actor)) Animation(actor, "amba", ACTOR_WAIT); return; }
        actor->dk.abilityCharges = 0;
        actor->dk.animationTime = 0; Animation(actor, "ataka", ACTOR_WAIT); TraceAttack(actor, "ataka");
    }
    if (ataka < 0 || actor->dk.animationIndex != ataka) { actor->dk.abilityState = SPHERE_CHASE; return; }
    frame = actor->s.frame - actor->dk.firstFrame + 1;
    strike = info->animations[ataka].strikes[0];
    if (!strike) strike = (actor->dk.lastFrame - actor->dk.firstFrame + 2) / 2;
    if (actor->dk.abilityCharges == 0 && frame >= strike) { SphereVolley(actor); actor->dk.abilityCharges = 1; }
    if (actor->dk.abilityCharges == 1 && frame >= strike + 4) { SphereVolley(actor); actor->dk.abilityCharges = 2; }
    if (actor->dk.abilityCharges == 2 && frame >= strike + 5) { SphereVolley(actor); actor->dk.abilityCharges = 3; }
    if (level.time - actor->dk.animationTime >= AnimationDuration(actor)) actor->dk.abilityState = SPHERE_CHASE;
}

/* skeeter.cpp: fly to within 178 units, dart in at one and a half times run
   speed, punch through ataka, then fly 512 units away and repeat. */
enum { SKEET_CHASE, SKEET_DART, SKEET_ATTACK, SKEET_AWAY };

static void SkeeterThink(gentity_t *actor) {
    dkActorInfo_t *info = Info(actor);
    gentity_t *enemy = actor->enemy;
    vec3_t goal, toward;
    float distance = Distance(actor->r.currentOrigin, enemy->r.currentOrigin);
    VectorCopy(enemy->r.currentOrigin, goal); goal[2] += 24;
    VectorSubtract(goal, actor->r.currentOrigin, toward);
    switch (actor->dk.abilityState) {
    case SKEET_DART:
        if (distance - 32 > info->attackDistance && level.time < actor->dk.abilityTime && !actor->dk.blockedSince) {
            PursueAt(actor, goal, enemy->s.number, info->speed * 1.5f);
            return;
        }
        actor->dk.abilityState = SKEET_ATTACK;
        actor->dk.attackGroup = 0; actor->dk.animationTime = 0;
        TurnToward(actor, vectoyaw(toward));
        Animation(actor, "ataka", ACTOR_ATTACK); TraceAttack(actor, "ataka");
        actor->dk.actionTime = level.time + AnimationDuration(actor);
        return;
    case SKEET_ATTACK:
        TurnToward(actor, vectoyaw(toward));
        if (level.time < actor->dk.actionTime) return;
        if (!AwayPoint(actor, 512, 12, qtrue, actor->dk.moveGoal)) {
            VectorCopy(enemy->r.currentOrigin, actor->dk.moveGoal); actor->dk.moveGoal[2] += 178;
        }
        actor->dk.abilityState = SKEET_AWAY; actor->dk.abilityTime = level.time + 3000;
        TraceAttack(actor, "flyaway");
        /* fall through */
    case SKEET_AWAY:
        if (Distance(actor->r.currentOrigin, actor->dk.moveGoal) > 64 && level.time < actor->dk.abilityTime) {
            PursuePosition(actor, actor->dk.moveGoal, ENTITYNUM_NONE);
            return;
        }
        actor->dk.abilityState = SKEET_CHASE;
        /* fall through */
    default:
        if (!Visible(actor, enemy)) {
            if (level.time - actor->dk.lastSeenTime < 10000) PursuePosition(actor, actor->dk.lastSeenOrigin, ENTITYNUM_NONE);
            else actor->enemy = NULL;
            return;
        }
        actor->dk.lastSeenTime = level.time; VectorCopy(enemy->r.currentOrigin, actor->dk.lastSeenOrigin);
        if (distance >= 178) { PursuePosition(actor, goal, enemy->s.number); return; }
        actor->dk.abilityState = SKEET_DART; actor->dk.abilityTime = level.time + 3000; actor->dk.blockedSince = 0;
        PursueAt(actor, goal, enemy->s.number, info->speed * 1.5f);
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

/* Garroth conjures a Buboid 100 units from its enemy, on an open side. */
static void GarrothSummon(gentity_t *actor, gentity_t *enemy) {
    gentity_t *buboid;
    int attempt;
    if (!enemy || !enemy->inuse || !(buboid = Summon(actor, "monster_buboid", 0))) return;
    for (attempt = 0; attempt < 8; ++attempt) {
        vec3_t candidate;
        trace_t trace;
        float angle = (attempt + (ActorRandom(actor) & 7)) * M_PI / 4;
        VectorCopy(enemy->r.currentOrigin, candidate);
        candidate[0] += cos(angle) * 100; candidate[1] += sin(angle) * 100;
        trap_Trace(&trace, enemy->r.currentOrigin, NULL, NULL, candidate, enemy->s.number, MASK_SOLID);
        if (trace.startsolid || trace.fraction < 1) continue;
        trap_Trace(&trace, candidate, buboid->r.mins, buboid->r.maxs, candidate, buboid->s.number, MASK_PLAYERSOLID);
        if (trace.startsolid || trace.allsolid) continue;
        G_SetOrigin(buboid, candidate); trap_LinkEntity(buboid);
        break;
    }
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
            target->s.dk3RenderFlags |= DK3_RF_STONE;
            G_Damage(target, actor, actor, NULL, NULL, target->health + 1, DAMAGE_NO_PROTECTION, MOD_UNKNOWN);
            if (target->inuse) {
                target->takedamage = qfalse; VectorClear(target->dk.actorVelocity);
                target->s.dk3AnimationRate = 0; target->s.dk3Alpha = 1;
                if (target->client) { target->client->ps.dk3Status |= 128; VectorClear(target->client->ps.velocity); }
            }
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
        (actor->spawnflags & 128) || Swimming(actor) || !Visible(actor, actor->enemy)) return qfalse;
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
    if (!strcmp(actor->classname, "monster_froginator")) {
        ActorSound(actor, "e1/m_frogjumpa.wav", 0.85f, 256, 648);
        ActorSound(actor, "e1/m_frogamba.wav", 0.65f, 256, 648);
    }
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
        if (Flying(actor) || Swimming(actor)) actor->dk.roamGoal[2] += (int)(ActorRandom(actor) % 97) - 48;
        actor->dk.roamUntil = level.time + 2500 + ActorRandom(actor) % 2500;
        actor->dk.blockedSince = 0;
    }
    Move(actor, actor->dk.roamGoal, info->walkSpeed > 0 ? info->walkSpeed : 35);
    Animation(actor, "walk", ACTOR_CHASE);
}

/* The Buboid sinks into a smoky puddle, becoming untouchable until it rises again. */
static void BuboidMelt(gentity_t *actor) {
    actor->dk.abilityState = 3; actor->dk.combatEnd = level.time;
    actor->takedamage = qfalse; actor->r.contents = 0; actor->s.dk3Alpha = 0.8f;
    actor->s.dk3RenderFlags |= DK3_RF_MELT;
    actor->dk.animationTime = 0;
    Animation(actor, "atakc", ACTOR_WAIT); actor->dk.abilityTime = level.time + AnimationDuration(actor);
    trap_LinkEntity(actor); TraceAttack(actor, "melt");
}

/* Buboids will not walk onto, or rise beside a target standing on, holy ground. */
static qboolean HolyGround(gentity_t *ent, const vec3_t point, float depth) {
    trace_t trace;
    vec3_t end;
    VectorCopy(point, end); end[2] -= depth;
    trap_Trace(&trace, point, NULL, NULL, end, ent->s.number, MASK_SOLID);
    return trace.fraction < 1 && (trace.surfaceFlags & SURF_DK_HOLY);
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
    if (!strcmp(name, "monster_griffon") && target) {
        if (!actor->dk.groundedFlight && Distance(actor->r.currentOrigin, target->r.currentOrigin) < 350) {
            vec3_t floor;
            trace_t trace;
            VectorCopy(actor->r.currentOrigin, floor); floor[2] -= 512;
            trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, floor, actor->s.number, MASK_SOLID);
            if (!trace.startsolid && trace.fraction < 1 && trace.plane.normal[2] > 0.7f) {
                if (Distance(trace.endpos, actor->r.currentOrigin) > 12) { Move(actor, trace.endpos, actor->dk.walkSpeed); Animation(actor, "hovera", ACTOR_CHASE); return qtrue; }
                actor->dk.groundedFlight = 1; Animation(actor, "drop", ACTOR_PAIN);
                actor->dk.actionTime = level.time + AnimationDuration(actor);
                G_Sound(actor, CHAN_AUTO, DK_SoundIndex("e2/m_griffondrop.wav")); return qtrue;
            }
        } else if (actor->dk.groundedFlight && Distance(actor->r.currentOrigin, target->r.currentOrigin) > 600) {
            actor->dk.groundedFlight = 0; actor->dk.actorVelocity[2] = 180;
        }
    }
    if (!strcmp(name, "monster_buboid") && actor->dk.abilityState >= 3) {
        float elapsed = (level.time - actor->dk.combatEnd) / 1000.0f;
        if (actor->dk.abilityState == 3) {
            actor->s.dk3Alpha = elapsed < 0.3f ? 0.8f - 2.5f * elapsed : 0.05f;
            if (level.time >= actor->dk.abilityTime) {
                actor->s.eFlags |= EF_NODRAW; actor->s.dk3RenderFlags &= ~DK3_RF_MELT; actor->dk.abilityState = 4;
                actor->dk.abilityTime = level.time + 3000 + ActorRandom(actor) % 4 * 1000;
                TraceAttack(actor, "hidden");
            }
        } else if (actor->dk.abilityState == 4 && level.time >= actor->dk.abilityTime) {
            /* Resurface beside a grounded enemy, on the first clear side found. */
            int attempt;
            qboolean placed = qfalse;
            gentity_t *enemy = actor->enemy;
            vec3_t mins, maxs, feet;
            if (enemy && enemy->inuse) {
                VectorCopy(enemy->r.currentOrigin, feet); feet[2] += enemy->r.mins[2] + 1;
                if (HolyGround(actor, feet, 8)) { actor->dk.abilityTime = level.time + 3000; return qtrue; }
            }
            VectorScale(actor->r.mins, 1.35f, mins); VectorScale(actor->r.maxs, 1.35f, maxs);
            for (attempt = 0; enemy && enemy->inuse && enemy->health > 0 && attempt < 8 && !placed; ++attempt) {
                vec3_t from, to, bottom;
                trace_t side, floor;
                float angle = attempt * M_PI / 4;
                if (enemy->client ? enemy->client->ps.groundEntityNum == ENTITYNUM_NONE : enemy->s.groundEntityNum == ENTITYNUM_NONE) break;
                VectorCopy(enemy->r.currentOrigin, from); from[0] += cos(angle) * 32; from[1] += sin(angle) * 32;
                VectorCopy(enemy->r.currentOrigin, to); to[0] += cos(angle) * 64; to[1] += sin(angle) * 64;
                /* The widened hull stands on the enemy's floor, not below it. */
                from[2] += enemy->r.mins[2] - mins[2] + 1; to[2] = from[2];
                trap_Trace(&side, from, mins, maxs, to, enemy->s.number, MASK_PLAYERSOLID);
                if (side.startsolid || side.fraction < 1) continue;
                to[2] += 32; VectorCopy(to, bottom); bottom[2] -= 160;
                trap_Trace(&floor, to, actor->r.mins, actor->r.maxs, bottom, actor->s.number, MASK_PLAYERSOLID);
                if (floor.startsolid || floor.fraction == 1 || floor.plane.normal[2] < 0.7f) continue;
                G_SetOrigin(actor, floor.endpos); placed = qtrue;
            }
            if (!placed) actor->dk.abilityTime = level.time + 1000;
            else {
                vec3_t direction;
                VectorSubtract(enemy->r.currentOrigin, actor->r.currentOrigin, direction);
                actor->s.angles[YAW] = vectoyaw(direction); VectorCopy(actor->s.angles, actor->r.currentAngles);
                actor->s.eFlags &= ~EF_NODRAW; actor->s.dk3RenderFlags |= DK3_RF_MELT; actor->dk.abilityState = 5;
                actor->dk.animationTime = 0;
                Animation(actor, "atakd", ACTOR_WAIT); actor->dk.abilityTime = level.time + AnimationDuration(actor);
                actor->dk.combatEnd = level.time; actor->s.dk3Alpha = 0.05f;
                actor->r.contents = CONTENTS_BODY; trap_LinkEntity(actor); TraceAttack(actor, "resurface");
            }
        } else if (actor->dk.abilityState == 5) {
            actor->s.dk3Alpha = elapsed < 0.95f ? 0.05f + elapsed : 1;
            if (level.time >= actor->dk.abilityTime) {
                actor->dk.abilityState = 0; actor->s.dk3RenderFlags &= ~DK3_RF_MELT;
                actor->s.dk3Alpha = 1; actor->takedamage = qtrue; TraceAttack(actor, "unmelted");
            }
        }
        return qtrue;
    }
    if (!strcmp(name, "monster_buboid") && target && !actor->dk.abilityState && actor->dk.action != ACTOR_DOWN) {
        vec3_t forward, ahead;
        AngleVectors(actor->s.angles, forward, NULL, NULL);
        VectorMA(actor->r.currentOrigin, 36, forward, ahead);
        if ((Distance(actor->r.currentOrigin, target->r.currentOrigin) > 300 && !Visible(actor, target)) ||
            HolyGround(actor, ahead, 200)) {
            BuboidMelt(actor); return qtrue;
        }
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
    if (!strcmp(name, "monster_kage")) {
        int skill = (int)Com_Clamp(0, 2, (trap_Cvar_VariableIntegerValue("g_spSkill") - 1) / 2);
        const float limits[] = {0.25f, 0.5f, 0.75f};
        const int gains[] = {1, 5, 10}, intervals[] = {2000, 1500, 1000};
        if (!actor->dk.abilityState && actor->dk.abilityCharges > 0 && level.time >= actor->dk.combatEnd &&
            actor->health < actor->dk.maxHealth * limits[skill]) {
            actor->dk.abilityState = 1; actor->dk.combatNext = level.time + 1000;
            Animation(actor, "atake", ACTOR_WAIT); actor->dk.animationLoop = qtrue;
            actor->s.loopSound = DK_SoundIndex("e4/m_kage_ghost_am.wav");
        }
        if (actor->dk.abilityState == 1) {
            actor->s.constantLight = 120 | (100 << 8) | (255 << 16) | (40 << 24);
            if (level.time >= actor->dk.combatNext) { actor->health += gains[skill]; actor->dk.combatNext = level.time + intervals[skill]; }
            if (actor->health >= actor->dk.maxHealth * limits[skill]) {
                --actor->dk.abilityCharges; actor->dk.abilityState = 0; actor->s.loopSound = actor->s.constantLight = 0;
                actor->dk.combatEnd = level.time + (skill == 0 ? 15000 : skill == 1 ? 7500 : 4500);
            }
            return qtrue;
        }
    }
    if (!strcmp(name, "monster_kage") && target && level.time >= actor->dk.abilityTime && Visible(actor, target)) {
        Summon(actor, "monster_ghost", actor->r.maxs[2] + 32);
        actor->dk.abilityTime = level.time + 6000;
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

enum { EVADE_SIDESTEP = 1, EVADE_STRAFE, EVADE_DODGE, EVADE_COVER, EVADE_PEEK };

/* AI_IsEnemyTargetingMe: a player's crosshair is on the actor; other
   enemies are facing it within five degrees. */
static qboolean Targeted(gentity_t *actor, gentity_t *enemy) {
    vec3_t forward, toward, angles;
    VectorSubtract(actor->r.currentOrigin, enemy->r.currentOrigin, toward);
    if (enemy->client) {
        vec3_t eye;
        VectorCopy(enemy->client->ps.origin, eye); eye[2] += enemy->client->ps.viewheight;
        VectorSubtract(actor->r.currentOrigin, eye, toward); VectorNormalize(toward);
        AngleVectors(enemy->client->ps.viewangles, forward, NULL, NULL);
        return DotProduct(forward, toward) > 0.97f;
    }
    VectorCopy(enemy->s.angles, angles);
    return fabs(AngleSubtract(vectoyaw(toward), angles[YAW])) < 5;
}

/* AI_ComputeSideStepPoint. */
static qboolean SideStepPoint(gentity_t *actor, float distance, vec3_t point) {
    gentity_t *enemy = actor->enemy;
    trace_t trace;
    vec3_t side, bottom;
    float yaw = actor->s.angles[YAW] * M_PI / 180;
    if (Flying(actor) || Swimming(actor)) {
        vec3_t away, angles, direction;
        static const float yaws[] = {45, -45, 45, -45, 45, -45}, pitches[] = {0, 0, -10, -10, 25, 25};
        int choice = ActorRandom(actor) % 6;
        VectorSubtract(actor->r.currentOrigin, enemy->r.currentOrigin, away);
        vectoangles(away, angles);
        angles[PITCH] += pitches[choice] - 40; angles[YAW] += yaws[choice];
        AngleVectors(angles, direction, NULL, NULL);
        VectorMA(enemy->r.currentOrigin, Info(actor)->attackDistance * 0.5f, direction, point);
        trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, point, actor->s.number, MASK_PLAYERSOLID);
        VectorCopy(trace.endpos, point);
        return !trace.startsolid && Distance(point, actor->r.currentOrigin) > 16;
    }
    distance -= 44;
    VectorSet(side, -sin(yaw), cos(yaw), 0);
    if (ActorRandom(actor) & 1) VectorNegate(side, side);
    VectorMA(actor->r.currentOrigin, distance, side, point);
    trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, point, actor->s.number, MASK_PLAYERSOLID);
    if (trace.fraction < 1) {
        VectorNegate(side, side);
        VectorMA(actor->r.currentOrigin, distance, side, point);
        trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, point, actor->s.number, MASK_PLAYERSOLID);
        if (trace.fraction * distance < 24) return qfalse;
    }
    VectorCopy(trace.endpos, point);
    VectorCopy(point, bottom); bottom[2] -= DK_STEP_HEIGHT + 24;
    trap_Trace(&trace, point, actor->r.mins, actor->r.maxs, bottom, actor->s.number, MASK_PLAYERSOLID);
    return trace.fraction < 1;
}

/* AI_DoEvasiveAction as called from each monster's attack start. */
static qboolean StartEvade(gentity_t *actor) {
    static const struct { const char *classname; float chance; qboolean targeted; } evaders[] = {
        {"monster_venomvermin", 0.25f, qtrue}, {"monster_centurion", 0.25f, qtrue}, {"monster_whiteprisoner", 0.3f, qtrue},
        {"monster_blackprisoner", 0.3f, qtrue}, {"monster_rocketdude", 0.8f, qtrue}, {"monster_fletcher", 0.3f, qtrue},
        {"monster_femgang", 0.5f, qtrue}, {"monster_lycanthir", 0.2f, qfalse}, {"monster_knight2", 0.75f, qfalse}
    };
    dkActorInfo_t *info = Info(actor);
    qboolean ranged = qfalse;
    float distance;
    int i, kind, duration;
    for (i = 0; i < (int)ARRAY_LEN(evaders); ++i) if (!strcmp(info->classname, evaders[i].classname)) break;
    if (i == (int)ARRAY_LEN(evaders) || (actor->spawnflags & 128) || !actor->enemy) return qfalse;
    if (evaders[i].targeted && !Targeted(actor, actor->enemy)) return qfalse;
    if (ActorFraction(actor) >= evaders[i].chance) return qfalse;
    for (i = 0; i < 3; ++i) if (info->attacks[i].damage > 0 && info->attacks[i].range > 160) ranged = qtrue;
    if (ranged) {
        if ((actor->spawnflags & 32) || ActorFraction(actor) < 0.5f) kind = ActorFraction(actor) > 0.5f ? EVADE_STRAFE : EVADE_SIDESTEP;
        else kind = EVADE_DODGE;
        duration = 2000;
    } else { kind = ActorFraction(actor) < 0.5f ? EVADE_SIDESTEP : EVADE_STRAFE; duration = 500; }
    distance = kind == EVADE_DODGE ? 128 : kind == EVADE_SIDESTEP ? 96 : 80;
    if (!SideStepPoint(actor, distance, actor->dk.evadeGoal)) return qfalse;
    actor->dk.evadeKind = kind; actor->dk.evadeUntil = level.time + duration;
    TraceAttack(actor, kind == EVADE_DODGE ? "dodge" : kind == EVADE_STRAFE ? "strafe" : "sidestep");
    return qtrue;
}

static qboolean Evade(gentity_t *actor) {
    gentity_t *enemy = actor->enemy;
    vec3_t delta, toward;
    float yaw = actor->s.angles[YAW];
    if (!enemy || level.time >= actor->dk.evadeUntil || actor->dk.evadeKind >= EVADE_COVER) {
        if (actor->dk.evadeKind < EVADE_COVER) actor->dk.evadeUntil = 0;
        return qfalse;
    }
    VectorSubtract(actor->dk.evadeGoal, actor->r.currentOrigin, delta);
    if (sqrt(delta[0] * delta[0] + delta[1] * delta[1]) < 16 && fabs(delta[2]) < 32) { actor->dk.evadeUntil = 0; return qfalse; }
    Move(actor, actor->dk.evadeGoal, actor->dk.runSpeed);
    if (actor->dk.blockedSince) { actor->dk.evadeUntil = 0; return qfalse; }
    if (actor->dk.evadeKind == EVADE_STRAFE) {
        /* Strafing keeps facing the enemy while moving sideways. */
        actor->s.angles[YAW] = yaw;
        VectorSubtract(enemy->r.currentOrigin, actor->r.currentOrigin, toward);
        TurnToward(actor, vectoyaw(toward));
    }
    Animation(actor, "run", ACTOR_CHASE);
    return qtrue;
}

/* AI_TakeCover for SPAWN_TAKECOVER gunmen: fire when fully exposed, then
   run to a spot out of the enemy's sight and wait to peek again. */
static qboolean CoverPoint(gentity_t *actor, vec3_t point) {
    gentity_t *enemy = actor->enemy;
    static const float reach[] = {96, 160, 256};
    float best = 100000;
    int ring, step;
    vec3_t eye;
    VectorCopy(enemy->r.currentOrigin, eye); eye[2] += enemy->client ? enemy->client->ps.viewheight : enemy->r.maxs[2] * 0.6f;
    for (ring = 0; ring < 3; ++ring) for (step = 0; step < 16; ++step) {
        trace_t trace, floor, sight;
        vec3_t goal, bottom, head;
        float angle = step * M_PI / 8;
        VectorCopy(actor->r.currentOrigin, goal);
        goal[0] += cos(angle) * reach[ring]; goal[1] += sin(angle) * reach[ring];
        trap_Trace(&trace, actor->r.currentOrigin, actor->r.mins, actor->r.maxs, goal, actor->s.number, MASK_PLAYERSOLID);
        if (trace.startsolid || Distance(trace.endpos, actor->r.currentOrigin) < 48) continue;
        VectorCopy(trace.endpos, bottom); bottom[2] -= DK_STEP_HEIGHT + 24;
        trap_Trace(&floor, trace.endpos, actor->r.mins, actor->r.maxs, bottom, actor->s.number, MASK_PLAYERSOLID);
        if (floor.fraction == 1) continue;
        VectorCopy(trace.endpos, head); head[2] += actor->r.maxs[2] * 0.6f;
        trap_Trace(&sight, eye, NULL, NULL, head, enemy->s.number, MASK_SOLID);
        if (sight.fraction == 1) continue;
        if (Distance(trace.endpos, actor->r.currentOrigin) < best) { best = Distance(trace.endpos, actor->r.currentOrigin); VectorCopy(trace.endpos, point); }
    }
    return best < 100000;
}

static qboolean TakeCover(gentity_t *actor, int group) {
    static const char *types[] = {"monster_mishimaguard", "monster_thief", "monster_dwarf", "monster_fletcher", "monster_rocketdude",
                                  "monster_sealgirl", "monster_sealcommando", "monster_sealcaptain", "monster_rocketmp"};
    gentity_t *enemy = actor->enemy;
    qboolean visible;
    int i;
    for (i = 0; i < (int)ARRAY_LEN(types); ++i) if (!strcmp(Info(actor)->classname, types[i])) break;
    if (i == (int)ARRAY_LEN(types) || !(actor->spawnflags & 0x200) || !enemy) return qfalse;
    visible = Visible(actor, enemy);
    if (actor->dk.evadeKind == EVADE_COVER && level.time < actor->dk.evadeUntil) {
        if (Distance(actor->r.currentOrigin, actor->dk.evadeGoal) > 16 && !actor->dk.blockedSince) {
            Move(actor, actor->dk.evadeGoal, actor->dk.runSpeed); Animation(actor, "run", ACTOR_CHASE); return qtrue;
        }
        actor->dk.evadeUntil = 0;
    }
    if (actor->dk.evadeKind == EVADE_PEEK && level.time < actor->dk.evadeUntil && !visible) { Pursue(actor, enemy); return qtrue; }
    if (visible && level.time >= actor->dk.coverTime && group >= 0) {
        actor->dk.evadeKind = 0; actor->dk.evadeUntil = 0;
        Attack(actor, group);
        if (actor->dk.action == ACTOR_ATTACK) actor->dk.coverTime = level.time + 2000;
        return qtrue;
    }
    if (visible && CoverPoint(actor, actor->dk.evadeGoal)) {
        actor->dk.evadeKind = EVADE_COVER; actor->dk.evadeUntil = level.time + 3000; TraceAttack(actor, "cover");
        Move(actor, actor->dk.evadeGoal, actor->dk.runSpeed); Animation(actor, "run", ACTOR_CHASE);
        return qtrue;
    }
    if (!visible && ActorRandom(actor) % 160 == 0) {
        actor->dk.evadeKind = EVADE_PEEK; actor->dk.evadeUntil = level.time + 3000; TraceAttack(actor, "peek");
        return qtrue;
    }
    if (visible && group >= 0) return qfalse;
    Animation(actor, "amba", ACTOR_IDLE);
    return qtrue;
}

/* Gold's runaway goal: flee the threat, then cower in gamba/gambc. */
static void Cower(gentity_t *actor) {
    gentity_t *threat = actor->enemy;
    dkActorInfo_t *info = Info(actor);
    float distance;
    if (!threat || !threat->inuse || threat->health <= 0) { actor->dk.abilityState = 0; actor->enemy = NULL; return; }
    distance = Distance(actor->r.currentOrigin, threat->r.currentOrigin);
    if (level.time >= actor->dk.abilityTime) {
        if (distance < 512 && Visible(actor, threat)) {
            actor->dk.abilityState = 1; actor->dk.abilityTime = level.time + 10000;
        } else { actor->dk.abilityState = 0; actor->enemy = NULL; return; }
    }
    if (actor->dk.abilityState == 1) {
        vec3_t away, goal, before;
        VectorSubtract(actor->r.currentOrigin, threat->r.currentOrigin, away); away[2] = 0;
        if (VectorNormalize(away) < 1) AngleVectors(actor->s.angles, away, NULL, NULL);
        VectorMA(actor->r.currentOrigin, 96, away, goal);
        VectorCopy(actor->r.currentOrigin, before);
        if (distance < 512) Move(actor, goal, actor->dk.runSpeed);
        if (distance >= 512 || Distance(before, actor->r.currentOrigin) < 1) {
            actor->dk.abilityState = 2; TraceAttack(actor, "cower");
            if (!strcmp(actor->classname, "monster_fatworker") && ActorFraction(actor) < 0.75f)
                ActorSound(actor, "e1/fart4.wav", 1, 256, 648);
        } else { Animation(actor, "run", ACTOR_CHASE); return; }
    }
    {
        const char *pose = AnimationIndex(info, "gamba") >= 0 ? "gamba" : "amba";
        if (actor->dk.action != ACTOR_IDLE || level.time - actor->dk.animationTime >= AnimationDuration(actor)) {
            if (AnimationIndex(info, "gambc") >= 0 && ActorRandom(actor) & 1) pose = "gambc";
            actor->dk.animationTime = 0;
            Animation(actor, pose, ACTOR_IDLE);
        }
    }
}

static void ActorThink(gentity_t *actor) {
    dkActorInfo_t *info = Info(actor);
    unsigned int id = actor->dk.id;
    if (actor->health > 0 && actor->dk.weaponHoldUntil > level.time) {
        VectorClear(actor->dk.actorVelocity);
        actor->nextthink = level.time + 1;
        return;
    }
    if (fabs(actor->r.currentOrigin[0]) > MAX_WORLD_COORD ||
        fabs(actor->r.currentOrigin[1]) > MAX_WORLD_COORD || fabs(actor->r.currentOrigin[2]) > MAX_WORLD_COORD) {
        G_Printf("dk3: actor %u (%s) left world bounds at %.0f %.0f %.0f\n", actor->dk.id, actor->classname,
            actor->r.currentOrigin[0], actor->r.currentOrigin[1], actor->r.currentOrigin[2]);
        if (actor->health > 0) G_Damage(actor, NULL, NULL, NULL, NULL, 100000, DAMAGE_NO_PROTECTION, MOD_TRIGGER_HURT);
        if (actor->inuse && actor->dk.id == id) G_FreeEntity(actor);
        return;
    }
    if (actor->s.dk3RenderFlags & DK3_RF_STONE) { actor->nextthink = level.time + 1; return; }
    FrameEvents(actor);
    if (!actor->inuse || actor->dk.id != id) return;
    actor->nextthink = level.time + 1;
    Physics(actor);
    if (!actor->inuse || actor->dk.id != id) return;
    DK_TouchActorTriggers(actor);
    if (!actor->inuse || actor->dk.id != id) return;
    if (actor->health <= 0 && actor->dk.action == ACTOR_DEAD && !Info(actor)->companion &&
        !actor->dk.cinematicControlled && !actor->dk.cinematicOwned && strncmp(actor->classname, "cine_", 5) &&
        level.time >= actor->dk.animationTime + AnimationDuration(actor) + 3000) {
        /* AI_ThinkFade: alpha x0.92 per 100 ms, removed below 0.1. */
        actor->s.dk3Alpha *= powf(0.92f, DK_ACTOR_TICK / 100.0f);
        if (actor->s.dk3Alpha < 0.1f) { G_FreeEntity(actor); return; }
    }
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
        return;
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
    if (!strcmp(actor->classname, "monster_cambot")) { CambotThink(actor); return; }
    if (actor->dk.abilityState == 1 && (!strcmp(actor->classname, "monster_froginator") ||
        !strcmp(actor->classname, "monster_psyclaw") || !strcmp(actor->classname, "monster_spider") ||
        !strcmp(actor->classname, "monster_smallspider") || !strcmp(actor->classname, "monster_lycanthir"))) {
        if (SpecialActor(actor)) return;
    }
    /* Patrol routes do not suppress perception. Scripted moves have already
       been handled above; an alerted patrol resumes its route after combat. */
    if (info->companion && actor->dk.companionOrder == 4) {
        gentity_t *threat = actor->enemy;
        if (threat && threat->inuse && Distance(actor->r.currentOrigin, threat->r.currentOrigin) < 256) {
            vec3_t away, goal;
            VectorSubtract(actor->r.currentOrigin, threat->r.currentOrigin, away); away[2] = 0; VectorNormalize(away);
            VectorMA(actor->r.currentOrigin, 96, away, goal); Move(actor, goal, actor->dk.walkSpeed);
        } else { actor->enemy = NULL; Animation(actor, "amba", ACTOR_IDLE); }
        return;
    }
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
    if (Timid(actor)) {
        if (actor->enemy) {
            if (!actor->dk.abilityState) { actor->dk.abilityState = 1; actor->dk.abilityTime = level.time + 10000; TraceAttack(actor, "flee"); }
            Cower(actor);
        }
        else { actor->dk.abilityState = 0; Roam(actor); }
        return;
    }
    if (!strcmp(actor->classname, "monster_thunderskeet")) {
        if (!actor->enemy) Acquire(actor);
        if (actor->enemy) { ThunderFlight(actor); return; }
    }
    if (!strcmp(actor->classname, "monster_deathsphere")) {
        if (SpherePresence(actor)) return;
        if (!actor->enemy) Acquire(actor);
        if (actor->enemy) { SphereThink(actor); return; }
        actor->dk.abilityState = SPHERE_CHASE;
    }
    if (!strcmp(actor->classname, "monster_crox") && actor->dk.action == ACTOR_CHASE && Swimming(actor) &&
        level.time % 2000 < DK_ACTOR_TICK)
        ActorSound(actor, va("hiro/swim%d.wav", 1 + (int)(ActorRandom(actor) % 3)), 0.85f, 256, 648);
    if (!strcmp(actor->classname, "monster_slaughterskeet")) {
        if (!actor->enemy) Acquire(actor);
        if (actor->enemy) { SkeeterThink(actor); return; }
        actor->dk.abilityState = SKEET_CHASE;
    }
    if (actor->enemy && Visible(actor, actor->enemy)) {
        actor->dk.lastSeenTime = level.time;
        VectorCopy(actor->enemy->r.currentOrigin, actor->dk.lastSeenOrigin);
        if (!info->companion && level.time % 10000 < DK_ACTOR_TICK) EnemyAlert(actor, actor->enemy);
    } else if (actor->enemy && level.time - actor->dk.lastSeenTime < 10000) {
        if (!info->companion || actor->dk.companionOrder != 1)
            PursuePosition(actor, actor->dk.lastSeenOrigin, ENTITYNUM_NONE);
        return;
    } else Acquire(actor);
    if (SpecialActor(actor)) return;
    if (actor->enemy && actor->dk.evadeUntil && Evade(actor)) return;
    if (actor->enemy) {
        float distance = Distance(actor->r.currentOrigin, actor->enemy->r.currentOrigin);
        int group = info->companion ? (distance <= 1200 ? 0 : -1) : AttackGroup(actor, distance);
        if (!info->companion && TakeCover(actor, group)) return;
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

/* Spawn-time pain_chance and ai_generic_pain_handler heavy-hit limits;
   unlisted monsters keep AI_InitHook's 75 and no heavy-hit roll. */
static qboolean PainRoll(gentity_t *actor, int damage) {
    static const struct { const char *classname; int chance, limit; } table[] = {
        {"monster_battleboar", 25, 0}, {"monster_blackprisoner", 10, 35}, {"monster_centurion", 30, 0},
        {"monster_cerberus", 10, 0}, {"monster_crox", 20, 0}, {"monster_cryotech", 25, 35}, {"monster_deathsphere", 10, 0},
        {"monster_dwarf", 20, 15}, {"monster_femgang", 20, 35}, {"monster_ferryman", 20, 0}, {"monster_fletcher", 20, 25},
        {"monster_froginator", 20, 0}, {"monster_garroth", 5, 0}, {"monster_griffon", 10, 0}, {"monster_harpy", 10, 25},
        {"monster_inmater", 5, 0}, {"monster_kage", 2, 0}, {"monster_knight1", 5, 35}, {"monster_knight2", 5, 35},
        {"monster_labmonkey", 20, 35}, {"monster_lycanthir", 15, 35}, {"monster_medusa", 1, 0}, {"monster_mikiko", 10, 35},
        {"monster_nharre", 1, 35}, {"monster_piperat", 10, 0}, {"monster_plague_rat", 25, 35}, {"monster_priest", 20, 0},
        {"monster_protopod", 0, 0}, {"monster_psyclaw", 15, 35}, {"monster_ragemaster", 5, 65}, {"monster_rocketdude", 10, 50},
        {"monster_rocketmp", 20, 25}, {"monster_sealcommando", 20, 45}, {"monster_sdiver", 20, 0}, {"monster_sealdiver", 20, 0},
        {"monster_sealcaptain", 20, 35}, {"monster_sealgirl", 20, 35}, {"monster_shark", 100, 25}, {"monster_sludgeminion", 5, 45},
        {"monster_stavros", 1, 35}, {"monster_thief", 30, 35}, {"monster_thunderskeet", 10, 0}, {"monster_uzigang", 20, 50},
        {"monster_venomvermin", 50, 35}, {"monster_whiteprisoner", 20, 40}, {"monster_wyndrax", 5, 0},
        {"monster_mishimaguard", 75, 35}, {"monster_smallspider", 75, 15}, {"monster_column", 20, 0}, {"hiro", 10, 0}
    };
    int i, chance = 75, limit = 0;
    if (Info(actor)->companion || damage <= 0) return qfalse;
    for (i = 0; i < (int)ARRAY_LEN(table); ++i)
        if (!strcmp(Info(actor)->classname, table[i].classname)) { chance = table[i].chance; limit = table[i].limit; break; }
    if ((int)(ActorFraction(actor) * 99.9f) < chance) return qtrue;
    return limit > 0 && damage >= limit && (int)(ActorFraction(actor) * 99.9f) < chance;
}

static void Pain(gentity_t *actor, gentity_t *attacker, int damage) {
    if (!strcmp(actor->classname, "monster_rockgat") || !strcmp(actor->classname, "monster_protopod")) return;
    if (!strcmp(actor->classname, "monster_kage") && actor->dk.abilityState == 1) {
        if (actor->health < actor->dk.maxHealth * 0.2f) actor->health = actor->dk.maxHealth * 0.25f + damage;
        else actor->health += damage * 1.05f;
        if (level.time >= actor->pain_debounce_time) {
            G_Sound(actor, CHAN_AUTO, DK_SoundIndex("e4/ykeypickup.wav"));
            G_TempEntity(actor->r.currentOrigin, EV_DK3_BLAST)->s.weapon = DK_W_ZEUS;
            actor->pain_debounce_time = level.time + 1000;
        }
        return;
    }
    if (attacker && attacker != actor &&
        !(attacker->dk.actorKind && attacker->dk.actorKind == actor->dk.actorKind && !Info(actor)->companion)) {
        qboolean player = attacker->client || (attacker->dk.actorKind && Info(attacker)->companion);
        if (player && !Info(actor)->companion) {
            actor->dk.ignorePlayer = 0;
            actor->dk.sightRange = 5000;
        }
        actor->enemy = attacker;
        actor->dk.lastSeenTime = level.time;
        VectorCopy(attacker->r.currentOrigin, actor->dk.lastSeenOrigin);
        if (attacker->client || attacker->dk.actorKind) EnemyAlert(actor, attacker);
        if (Timid(actor) && actor->health > 0) {
            actor->dk.abilityState = 1;
            actor->dk.abilityTime = level.time + (strcmp(actor->classname, "monster_surgeon") ? 10000 : 15000);
            TraceAttack(actor, "flee");
        }
    }
    if (actor->dk.action == ACTOR_DOWN || level.time < actor->pain_debounce_time) return;
    if (!strcmp(actor->classname, "monster_buboid") && !actor->dk.abilityState && damage > 0 && actor->health > 0 &&
        actor->enemy && Distance(actor->r.currentOrigin, actor->enemy->r.currentOrigin) > 250 && ActorRandom(actor) % 100 < 75) {
        BuboidMelt(actor); return;
    }
    if (!PainRoll(actor, damage)) return;
    Animation(actor, "pain", ACTOR_PAIN);
    actor->dk.actionTime = level.time + AnimationDuration(actor);
    actor->pain_debounce_time = actor->dk.actionTime;
    actor->dk.evadeUntil = 0;
}

/* Fragtypes each Gold monster sets at spawn; rockgat bursts itself on death. */
static int Fragtype(gentity_t *actor) {
    enum { N = DK_FRAG_NOBLOOD, R = DK_FRAG_ROBOTIC, A = DK_FRAG_ALWAYSGIB };
    static const struct { const char *classname; int fragtype; } table[] = {
        {"monster_cambot", R | N | A}, {"monster_deathsphere", R | N | A}, {"monster_lasergat", R | N | A},
        {"monster_protopod", R | N | A}, {"monster_thunderskeet", R | N | A}, {"monster_slaughterskeet", R | N | A},
        {"monster_rockgat", R | N | A}, {"monster_battleboar", R | N}, {"monster_crox", R | N},
        {"monster_venomvermin", R | N}, {"monster_ragemaster", R | N}, {"monster_inmater", R | N},
        {"monster_sludgeminion", R | N}, {"monster_froginator", R | N}, {"monster_fatworker", A},
        {"monster_dragon", A}, {"monster_harpy", A}, {"monster_griffon", A}, {"monster_lycanthir", A},
        {"e_dopefish", A}, {"e_guppy", A}, {"e_guppy2", A}, {"e_greyfish", A}, {"e_goldfish", A}, {"e_seagull", A},
        {"monster_ghost", DK_FRAG_NEVERGIB | N}, {"monster_garroth", DK_FRAG_NEVERGIB},
        {"monster_column", DK_FRAG_NEVERGIB | N | R}, {"monster_skeleton", DK_FRAG_BONE | N}
    };
    int i, fragtype = 0;
    for (i = 0; i < (int)ARRAY_LEN(table); ++i)
        if (!strcmp(Info(actor)->classname, table[i].classname)) { fragtype = table[i].fragtype; break; }
    if (actor->spawnflags & 0x400) fragtype |= DK_FRAG_ALWAYSGIB;
    return fragtype;
}

/* AI_GibLimit against the definition's base health, not the scaled current one. */
static qboolean GibLimit(gentity_t *actor, int fragtype, int damage) {
    float base = Info(actor)->baseHealth > 0 ? Info(actor)->baseHealth : actor->dk.maxHealth;
    if (fragtype & DK_FRAG_NEVERGIB) return qfalse;
    return (fragtype & DK_FRAG_ALWAYSGIB) || damage >= 0.3f * base || actor->health < -0.5f * base;
}

static void Die(gentity_t *actor, gentity_t *inflictor, gentity_t *attacker, int damage, int mod) {
    unsigned int id = actor->dk.id;
    int weapon = inflictor && inflictor->dk.projectile ? inflictor->s.weapon :
        attacker && attacker->client ? attacker->client->ps.weapon : attacker ? attacker->s.weapon : 0;
    qboolean lycan = !strcmp(actor->classname, "monster_lycanthir");
    qboolean buboid = !strcmp(actor->classname, "monster_buboid");
    int fragtype = Fragtype(actor);
    qboolean gib = GibLimit(actor, fragtype, damage);
    vec3_t mins, maxs;
    (void)mod;
    VectorCopy(actor->r.mins, mins); VectorCopy(actor->r.maxs, maxs);
    if (actor->dk.action == ACTOR_DEAD) {
        if (gib && !(actor->s.dk3RenderFlags & DK3_RF_STONE) && !Info(actor)->companion) {
            DK_ActorGib(actor, attacker, mins, maxs, fragtype, Info(actor)->mass, damage);
            G_FreeEntity(actor);
        }
        return;
    }
    if (!(actor->s.dk3RenderFlags & DK3_RF_STONE) && ((lycan && !DK_WeaponSlaysRevenants(weapon)) ||
        (buboid && !DK_WeaponSlaysRevenants(weapon) && damage < actor->dk.maxHealth / 2))) {
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
    if (attacker && attacker != actor && !Info(actor)->companion) EnemyAlert(actor, attacker);
    if (actor->s.dk3RenderFlags & DK3_RF_STONE) { actor->dk.action = ACTOR_DEAD; gib = qfalse; }
    else if (strstr(actor->classname, "skeleton") && attacker) {
        vec3_t forward, toward;
        const char *pose;
        float dot;
        AngleVectors(actor->s.angles, forward, NULL, NULL);
        VectorSubtract(attacker->r.currentOrigin, actor->r.currentOrigin, toward); VectorNormalize(toward);
        dot = DotProduct(forward, toward); pose = dot > 0.5f ? "diea" : dot < -0.5f ? "died" : "dieb";
        Animation(actor, AnimationIndex(Info(actor), pose) >= 0 ? pose : "die", ACTOR_DEAD);
    } else Animation(actor, "die", ACTOR_DEAD);
    actor->takedamage = qtrue;
    actor->r.contents = CONTENTS_CORPSE;
    if (Info(actor)->frameBottoms)
        actor->r.mins[2] = Info(actor)->frameBottoms[actor->dk.lastFrame] *
            Info(actor)->modelScale[2] * actor->s.dk3Scale / Info(actor)->scale;
    actor->r.maxs[2] = actor->r.mins[2] + 12;
    trap_LinkEntity(actor);
    {
        char map[MAX_QPATH];
        int episode;
        trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
        episode = map[0] == 'e' && map[1] >= '1' && map[1] <= '4' ? map[1] - '0' : 1;
        DK_AwardExperience(attacker, Info(actor)->health * episode / 10, DK_WeaponSwordExperience(weapon, Info(actor)->health));
    }
    DK_DeathSpawn(actor);
    DK_FireNamed(actor->dk.deathTarget, actor, attacker);
    if (!actor->inuse || actor->dk.id != id) return;
    G_UseTargets(actor, attacker);
    if (actor->inuse && actor->dk.id == id && gib && !Info(actor)->companion) {
        DK_ActorGib(actor, attacker, mins, maxs, fragtype, Info(actor)->mass, damage);
        G_FreeEntity(actor);
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
    actor->dk.speakRange = 0;
    if (level.spawning) G_SpawnFloat("speak", "0", &actor->dk.speakRange);
    if (!(actor->dk.speakRange >= 0 && actor->dk.speakRange <= 131072))
        G_Error("dk3: actor %u (%s): speak must be between 0 and 131072", actor->dk.id, name);
    if (!strcmp(name, "monster_mishimaguard")) actor->dk.abilityCharges = 8;
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
    if (!strcmp(name, "monster_kage")) {
        int skill = (int)Com_Clamp(0, 2, (trap_Cvar_VariableIntegerValue("g_spSkill") - 1) / 2);
        actor->dk.abilityCharges = skill == 0 ? 2 : skill == 1 ? 5 : 10;
    }
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
    actor->nextthink = level.time + 1;
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

static void CommandVoice(gentity_t *actor, const char *code) {
    qboolean mikiko = strstr(actor->classname, "mikiko") && !strstr(actor->classname, "mikikofly");
    const char *path = va("sounds/voices/%s/cmd_%s_%s_01.mp3.ogg", mikiko ? "mikiko" : "superfly", mikiko ? "mi" : "su", code);
    if (trap_FS_FOpenFile(path, NULL, FS_READ) > 0) G_Sound(actor, CHAN_VOICE, G_SoundIndex(path));
    else G_Printf("dk3: companion %u: missing command voice %s\n", actor->dk.id, path);
}

/* Developer cheat: `spawnactor <classname> [distance]` places an actor ahead of the player. */
qboolean DK_SpawnActorCommand(gentity_t *player, const char *command) {
    char classname[64], distance[16];
    vec3_t forward, origin, angles;
    gentity_t *actor;
    trace_t trace;
    if (Q_stricmp(command, "spawnactor")) return qfalse;
    if (!trap_Cvar_VariableIntegerValue("sv_cheats")) {
        trap_SendServerCommand(player->s.number, "print \"Cheats are not enabled on this server.\n\"");
        return qtrue;
    }
    trap_Argv(1, classname, sizeof(classname)); trap_Argv(2, distance, sizeof(distance));
    VectorSet(angles, 0, player->client->ps.viewangles[YAW], 0);
    AngleVectors(angles, forward, NULL, NULL);
    VectorMA(player->r.currentOrigin, *distance ? atof(distance) : 160, forward, origin);
    trap_Trace(&trace, player->r.currentOrigin, NULL, NULL, origin, player->s.number, MASK_SOLID);
    VectorCopy(trace.endpos, origin); origin[2] += 16;
    actor = G_Spawn();
    actor->classname = G_NewString(classname);
    VectorCopy(origin, actor->s.origin);
    angles[YAW] += 180; VectorCopy(angles, actor->s.angles);
    if (!DK_SpawnActor(actor)) {
        G_FreeEntity(actor);
        trap_SendServerCommand(player->s.number, va("print \"Unknown actor %s.\n\"", classname));
        return qtrue;
    }
    trap_SendServerCommand(player->s.number, va("print \"Spawned %s as entity %d.\n\"", classname, actor->s.number));
    return qtrue;
}

qboolean DK_CompanionCommand(gentity_t *player, const char *command) {
    char operation[64], selection[32];
    gentity_t *target = NULL;
    int i, affected = 0;
    if (Q_stricmp(command, "companion")) return qfalse;
    trap_Argv(1, operation, sizeof(operation)); trap_Argv(2, selection, sizeof(selection));
    if ((strcmp(operation, "follow") && strcmp(operation, "wait") && strcmp(operation, "attack") && strcmp(operation, "pickup") && strcmp(operation, "noattack") && strcmp(operation, "backoff")) ||
        (*selection && strcmp(selection, "all") && strcmp(selection, "mikiko") && strcmp(selection, "superfly"))) {
        trap_SendServerCommand(player->s.number, "print \"Use companion <follow|wait|attack|pickup|noattack|backoff> [mikiko|superfly|all].\n\"");
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
            if (!target || !DK_CompanionItemValue(actor, target)) { CommandVoice(actor, "no"); continue; }
            actor->dk.pickupId = target->dk.id; actor->dk.companionOrder = 3;
        } else if (!strcmp(operation, "attack")) {
            if (target && Enemy(actor, target)) actor->enemy = target; else Acquire(actor);
            actor->dk.companionOrder = 2;
        } else {
            actor->dk.companionOrder = !strcmp(operation, "wait") ? 1 : (!strcmp(operation, "noattack") || !strcmp(operation, "backoff")) ? 4 : 0;
            actor->dk.pickupId = 0;
        }
        CommandVoice(actor, actor->dk.companionOrder == 4 ? "ba" : actor->dk.companionOrder == 3 ? "pu" :
            actor->dk.companionOrder == 2 ? "at" : actor->dk.companionOrder == 1 ? "st" : "co");
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
    if (!(actor->dk.speakRange >= 0 && actor->dk.speakRange <= 131072)) return qfalse;
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
            actor->dk.actorLevel < 1 || actor->dk.actorLevel > 25 || actor->dk.companionOrder < 0 || actor->dk.companionOrder > 4 ||
            actor->s.weapon < 1 || actor->s.weapon >= DK_WEAPON_COUNT) return qfalse;
        for (i = 0; i < MAX_WEAPONS; ++i) if (actor->dk.ammunition[i] < 0 || actor->dk.ammunition[i] > 32767) return qfalse;
        for (i = 0; i < 5; ++i) if (actor->dk.attributes[i] < 0 || actor->dk.attributes[i] > 5) return qfalse;
    }
    return !strcmp(info->classname, name) && actor->dk.attackGroup >= 0 && actor->dk.attackGroup < 3 &&
        actor->dk.action >= ACTOR_IDLE && actor->dk.action <= ACTOR_DOWN && actor->dk.abilityState >= 0 && actor->dk.abilityState <= (!strcmp(actor->classname, "monster_buboid") ? 5 : 3) && actor->dk.animationCursor >= -1 &&
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
    if (actor->enemy && actor->enemy->health > 0 && actor->dk.abilityState != CAMBOT_SEARCHING) {
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
        actor->s.dk3AnimationRate = actor->s.dk3RenderFlags & DK3_RF_STONE ? 0 : actor->dk.animationRate;
        actor->s.dk3AnimationLoop = actor->dk.animationLoop;
    }
}
