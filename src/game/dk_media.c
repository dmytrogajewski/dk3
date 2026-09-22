/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_tables.h"

static char currentMap[MAX_QPATH], mapMusic[MAX_QPATH];

static void SoundPath(const char *name, char *out, int capacity, qboolean music) {
    char normalized[MAX_QPATH];
    int i, length = 0;
    const char *prefix;
    /* Map epairs use both slash styles, leading separators and doubled
       separators. Normalize before recognizing the optional data/root prefix. */
    for (i = 0; name[i]; ++i) {
        char c = name[i] == '\\' ? '/' : name[i];
        if (c == '/' && (!length || normalized[length - 1] == '/')) continue;
        if (length == sizeof(normalized) - 1) G_Error("dk3: media path too long: %s", name);
        normalized[length++] = c;
    }
    normalized[length] = 0;
    name = normalized;
    if (!Q_stricmpn(name, "data/", 5)) name += 5;
    prefix = !Q_stricmpn(name, "music/", 6) || !Q_stricmpn(name, "sounds/", 7) ? "" : music ? "music/" : "sounds/";
    Com_sprintf(out, capacity, "%s%s", prefix, name);
    if (!*COM_GetExtension(out)) Q_strcat(out, capacity, music ? ".mp3" : ".wav");
    if (!Q_stricmp(COM_GetExtension(out), "mp3")) Q_strcat(out, capacity, ".ogg");
}

int DK_SoundIndex(const char *name) {
    char path[MAX_QPATH];
    if (!name || !*name) return 0;
    SoundPath(name, path, sizeof(path), qfalse);
    /* The supplied e1m2 entry cinematic omits the final l in this directory.
       Resolve only the known typo, and only when its actual asset is supplied. */
    if (!Q_stricmp(path, "sounds/globa/a_speedwhoosh.wav") &&
        trap_FS_FOpenFile(path, NULL, FS_READ) == 0 &&
        trap_FS_FOpenFile("sounds/global/a_speedwhoosh.wav", NULL, FS_READ) > 0) {
        G_Printf("dk3: media %s resolved to sounds/global/a_speedwhoosh.wav\n", path);
        Q_strncpyz(path, "sounds/global/a_speedwhoosh.wav", sizeof(path));
    }
    return G_SoundIndex(path);
}

void DK_SetMusic(const char *name) {
    char path[MAX_QPATH];
    if (!name || !*name) { trap_SetConfigstring(CS_MUSIC, ""); return; }
    SoundPath(name, path, sizeof(path), qtrue);
    trap_SetConfigstring(CS_MUSIC, va("%s %s", path, path));
}

static void MusicRow(const dkRecord_t *row) {
    if (!Q_stricmp(DK_Field(row, "mapname"), currentMap)) Q_strncpyz(mapMusic, DK_Field(row, "song"), sizeof(mapMusic));
}

void DK_WorldMusic(void) {
    char *override;
    trap_Cvar_VariableStringBuffer("mapname", currentMap, sizeof(currentMap)); mapMusic[0] = 0;
    DK_ReadTable("music", MusicRow);
    G_SpawnString("musictrack", "", &override);
    DK_SetMusic(*override ? override : mapMusic);
}

static unsigned int NextRandom(gentity_t *entity) {
    entity->dk.soundRandom = entity->dk.soundRandom * 1664525u + 1013904223u;
    return entity->dk.soundRandom;
}

static void Play(gentity_t *entity) {
    int index;
    if (!entity->dk.soundCount) return;
    index = entity->dk.soundIndices[NextRandom(entity) % entity->dk.soundCount];
    if (entity->spawnflags & 3 || !strcmp(entity->classname, "sound_ambient")) entity->s.loopSound = index;
    else G_AddEvent(entity, EV_GENERAL_SOUND, index);
}

static void SoundThink(gentity_t *entity) {
    if (!entity->dk.soundEnabled) return;
    Play(entity);
    if (entity->dk.soundDelay > 0) {
        int range = entity->dk.soundDelay - entity->dk.soundMinimum;
        entity->nextthink = level.time + entity->dk.soundMinimum + (range > 0 ? NextRandom(entity) % (range + 1) : 0) + 1;
    }
}

static void SoundUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (entity->spawnflags & 3 || !strcmp(entity->classname, "sound_ambient") || entity->dk.soundDelay) {
        entity->dk.soundEnabled = !entity->dk.soundEnabled;
        if (entity->dk.soundEnabled) SoundThink(entity);
        else { entity->s.loopSound = 0; entity->nextthink = 0; }
    } else Play(entity);
    G_UseTargets(entity, activator);
}

static void MusicUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    (void)other;
    if (!activator || !activator->client || entity->dk.uses) return;
    DK_SetMusic(entity->dk.mediaPath); ++entity->dk.uses; G_UseTargets(entity, activator);
}

static void MusicTouch(gentity_t *entity, gentity_t *other, trace_t *trace) { (void)trace; MusicUse(entity, other, other); }

void DK_RestoreMedia(gentity_t *entity) {
    if (!strcmp(entity->classname, "trigger_changemusic")) { entity->use = MusicUse; entity->touch = MusicTouch; }
    else if (!strcmp(entity->classname, "sound_ambient") || !strcmp(entity->classname, "target_speaker")) {
        entity->use = SoundUse; entity->think = SoundThink;
    }
}

qboolean DK_SpawnMedia(gentity_t *entity) {
    char *value;
    int i;
    float delay, minimum;
    if (!strcmp(entity->classname, "trigger_changemusic")) {
        G_SpawnString("path", "", &value); entity->dk.mediaPath = G_NewString(value);
        if (!*value) G_Printf("dk3: music trigger %u has no path\n", entity->dk.id);
        entity->r.svFlags |= SVF_NOCLIENT;
        if (entity->model) { trap_SetBrushModel(entity, entity->model); entity->r.contents = CONTENTS_TRIGGER; }
    } else if (!strcmp(entity->classname, "sound_ambient") || !strcmp(entity->classname, "target_speaker")) {
        G_SpawnString("sound", "", &value);
        if (!*value) G_SpawnString("noise", "", &value);
        if (*value) entity->dk.soundIndices[entity->dk.soundCount++] = DK_SoundIndex(value);
        for (i = 1; i <= 6; ++i) {
            G_SpawnString(va("sound%d", i), "", &value);
            if (*value) entity->dk.soundIndices[entity->dk.soundCount++] = DK_SoundIndex(value);
        }
        G_SpawnFloat("delay", "0", &delay); G_SpawnFloat("mindelay", va("%f", delay), &minimum);
        entity->dk.soundDelay = Com_Clamp(0, 3600, delay) * 1000;
        entity->dk.soundMinimum = Com_Clamp(0, delay > 0 ? delay : 0, minimum) * 1000;
        entity->dk.delay = 0; /* Speaker delay controls playback, not its outgoing target scheduler. */
        entity->dk.soundRandom = entity->dk.id * 747796405u;
        G_SpawnFloat("volume", "1", &entity->s.dk3SoundVolume);
        G_SpawnFloat("min", "80", &entity->s.dk3SoundMin);
        G_SpawnFloat("max", "1000", &entity->s.dk3SoundMax);
        entity->s.dk3SoundVolume = Com_Clamp(0, 1, entity->s.dk3SoundVolume);
        entity->s.dk3SoundMin = Com_Clamp(0, 65535, entity->s.dk3SoundMin);
        entity->s.dk3SoundMax = Com_Clamp(entity->s.dk3SoundMin + 1, 65536, entity->s.dk3SoundMax);
        entity->s.dk3SoundFlags = (entity->spawnflags & 8) ? 1 : 0;
        entity->dk.soundEnabled = !(entity->spawnflags & (2 | 16));
        entity->s.eType = ET_GENERAL;
        if (entity->dk.soundEnabled && ((entity->spawnflags & 1) || entity->dk.soundDelay || !strcmp(entity->classname, "sound_ambient")))
            entity->nextthink = level.time + 1;
        if (!entity->dk.soundCount) G_Printf("dk3: speaker %u has no sound binding\n", entity->dk.id);
    } else return qfalse;
    G_SetOrigin(entity, entity->s.origin); DK_RestoreMedia(entity); trap_LinkEntity(entity);
    return qtrue;
}
