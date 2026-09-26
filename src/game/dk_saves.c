/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Save orchestration stages portable records before scheduling any map replacement. */
#include "g_local.h"
#include "dk_save_schema.h"
#include "dk_weapons.h"

#define SAVE_STRINGS (4 * 1024 * 1024)
#define SAVE_PENDING "dk3-resume-internal"
#define SAVE_REVISION 6
#define SAVE_RESTART "dk3-restart-internal"
#define SAVE_PRE_ENVIRONMENT_REVISION 2
#define REF_COUNT 13

typedef struct { char *map, *assets; int revision, skill, player, entities; } metadata_t;
typedef struct { unsigned int id; int slot, refs[REF_COUNT]; qboolean entity, references; } identity_t;
typedef struct { int kind; unsigned int id; } recordKey_t;
typedef struct { int airOutTime; } environmentState_t;
static byte storage[DK_SAVE_LIMIT], mapBuffer[DK_SAVE_WORLD_LIMIT];
static byte *buffer = storage;
static qboolean archivingLevel;
static qboolean restartAvailable;
#define VISITED_LIST 2048
static qboolean WriteVisited(dkSaveWriter_t *writer, const char *current);
static char stringStorage[SAVE_STRINGS], failure[256];
static gentity_t staged[MAX_GENTITIES], baseline[MAX_GENTITIES];
static identity_t identities[MAX_GENTITIES];
static playerState_t stagedPlayer;
static environmentState_t stagedEnvironment;
static char *resources[CS_PLAYERS];
static dkSaveStrings_t strings;
static metadata_t metadata;
static int entityCount, snapshotLength;
static qboolean autosavePending, resumeWaiting;
static recordKey_t recordKeys[32768];
static const size_t referenceOffsets[] = {
    offsetof(gentity_t, parent), offsetof(gentity_t, nextTrain), offsetof(gentity_t, prevTrain),
    offsetof(gentity_t, target_ent), offsetof(gentity_t, chain), offsetof(gentity_t, enemy),
    offsetof(gentity_t, activator), offsetof(gentity_t, teamchain), offsetof(gentity_t, teammaster)
};
#define META(field, type) {#field, type, offsetof(metadata_t, field), 1, qfalse}
static const dkSaveMember_t metadataMembers[] = {
    META(map, DK_SAVE_TEXT), META(assets, DK_SAVE_TEXT), META(revision, DK_SAVE_INT),
    META(skill, DK_SAVE_INT), META(player, DK_SAVE_INT), META(entities, DK_SAVE_INT)
};
#undef META
static const dkSaveMember_t environmentMembers[] = {
    {"air_out_time", DK_SAVE_INT, offsetof(environmentState_t, airOutTime), 1, qtrue}
};

static qboolean Reject(const char *message) { Q_strncpyz(failure, message, sizeof(failure)); return qfalse; }

static qboolean Name(const char *name, int maximum) {
    const char *p;
    if (!name || !*name || strlen(name) > maximum) return qfalse;
    for (p = name; *p; ++p) if (!((*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9') || *p == '_' || *p == '-')) return qfalse;
    return qtrue;
}

static qboolean File(const char *path) {
    fileHandle_t file;
    int size = trap_FS_FOpenFile(path, &file, FS_READ);
    if (file) trap_FS_FCloseFile(file);
    return size > 0;
}

static qboolean AssetIdentity(char out[128]) {
    fileHandle_t file;
    int size = trap_FS_FOpenFile("dk3/asset-id.cfg", &file, FS_READ);
    if (size < 1 || size >= 128) { if (file) trap_FS_FCloseFile(file); return qfalse; }
    trap_FS_Read(out, size, file); trap_FS_FCloseFile(file); out[size] = 0;
    return qtrue;
}

static qboolean SaveEntity(const gentity_t *ent) {
    return ent->inuse && ent->dk.id && !ent->freeAfterEvent && ent->s.eType < ET_EVENTS;
}

static int EntityReference(gentity_t *ent) {
    if (ent == &g_entities[ENTITYNUM_WORLD]) return -1;
    return ent && SaveEntity(ent) ? ent->dk.id : 0;
}

static int SlotReference(int slot) {
    if (slot == ENTITYNUM_WORLD) return -1;
    if (slot == ENTITYNUM_NONE) return -2;
    return slot >= 0 && slot < level.num_entities ? EntityReference(&g_entities[slot]) : 0;
}

qboolean DK_SaveReferenceExists(unsigned int id) {
    int i;
    if (!id) return qtrue;
    for (i = 0; i < entityCount; ++i) if (identities[i].id == id) return qtrue;
    return qfalse;
}

static int Slot(unsigned int id) {
    int i;
    if ((int)id == -1) return ENTITYNUM_WORLD;
    if (!id || (int)id == -2) return ENTITYNUM_NONE;
    for (i = 0; i < entityCount; ++i) if (identities[i].id == id) return identities[i].slot;
    return ENTITYNUM_NONE;
}

static gentity_t *Reference(int id) {
    int slot = Slot(id);
    return slot == ENTITYNUM_NONE ? NULL : &g_entities[slot];
}

static qboolean ResourceSlot(int index) {
    return index == CS_DK3_LIGHTSTYLES || index == CS_DK3_SKY || index == CS_MUSIC || index == CS_SHADERSTATE || (index >= CS_MODELS && index < CS_PLAYERS);
}

static qboolean WriteSnapshot(gentity_t *player) {
    dkSaveWriter_t writer;
    char map[MAX_QPATH], assets[128], value[MAX_STRING_CHARS];
    metadata_t header;
    environmentState_t environment;
    int i, j;
    memset(&header, 0, sizeof(header));
    trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
    if (!AssetIdentity(assets)) return Reject("asset generation identity is missing; rebuild the data package");
    header.map = map; header.assets = assets; header.revision = SAVE_REVISION;
    header.skill = trap_Cvar_VariableIntegerValue("g_spSkill"); header.player = player->dk.id;
    for (i = 0; i < level.num_entities; ++i) if (SaveEntity(&g_entities[i])) ++header.entities;
    if (!DK_SaveBegin(&writer, buffer, archivingLevel ? DK_SAVE_WORLD_LIMIT : sizeof(storage)) || !DK_SaveRecord(&writer, "campaign", 0) ||
        !DK_SaveObject(&writer, &header, metadataMembers, ARRAY_LEN(metadataMembers))) return Reject(writer.error);
    for (i = 0; i < level.num_entities; ++i) {
        gentity_t *ent = &g_entities[i];
        if (!SaveEntity(ent)) continue;
        {
            gentity_t saved = *ent;
            if (!DK_FindEntity(saved.dk.ownerId)) saved.dk.ownerId = 0;
            if (!DK_FindEntity(saved.dk.destinationId)) saved.dk.destinationId = 0;
            if (!DK_FindEntity(saved.dk.statusOwnerId)) saved.dk.statusOwnerId = 0;
            if (!DK_FindEntity(saved.dk.monitorId)) saved.dk.monitorId = 0;
            if (!DK_FindEntity(saved.dk.healingUser)) saved.dk.healingUser = 0;
            if (!DK_FindEntity(saved.dk.parentId)) saved.dk.parentId = 0;
            if (!DK_FindEntity(saved.dk.weaponParentId)) saved.dk.weaponParentId = 0;
            if (!DK_FindEntity(saved.dk.pickupId)) saved.dk.pickupId = 0;
            if (!DK_SaveRecord(&writer, "entity", ent->dk.id) ||
                !DK_SaveObject(&writer, &saved, dk_entityMembers, dk_entityMemberCount)) return Reject(writer.error);
        }
    }
    for (i = 0; i < level.num_entities; ++i) {
        gentity_t *ent = &g_entities[i];
        int refs[REF_COUNT];
        if (!SaveEntity(ent)) continue;
        for (j = 0; j < ARRAY_LEN(referenceOffsets); ++j)
            refs[j] = EntityReference(*(gentity_t **)((byte *)ent + referenceOffsets[j]));
        refs[9] = SlotReference(ent->s.groundEntityNum);
        refs[10] = SlotReference(ent->r.ownerNum);
        refs[11] = SlotReference(ent->s.otherEntityNum);
        refs[12] = SlotReference(ent->s.otherEntityNum2);
        if (!DK_SaveRecord(&writer, "references", ent->dk.id) || !DK_SaveInts(&writer, "entities", refs, REF_COUNT)) return Reject(writer.error);
    }
    player->client->ps.stats[STAT_HEALTH] = player->health;
    if (!DK_SaveRecord(&writer, "player", player->dk.id) ||
        !DK_SaveObject(&writer, &player->client->ps, dk_playerMembers, dk_playerMemberCount)) return Reject(writer.error);
    environment.airOutTime = player->client->airOutTime;
    if (!DK_SaveRecord(&writer, "player_environment", player->dk.id) ||
        !DK_SaveObject(&writer, &environment, environmentMembers, ARRAY_LEN(environmentMembers))) return Reject(writer.error);
    for (i = 0; i < CS_PLAYERS; ++i) if (ResourceSlot(i)) {
        trap_GetConfigstring(i, value, sizeof(value));
        if (*value && (!DK_SaveRecord(&writer, "resource", i) || !DK_SaveText(&writer, "path", value))) return Reject(writer.error);
    }
    if (!DK_WriteCompanionState(&writer) || !DK_WriteWorldState(&writer) || !DK_WriteScriptState(&writer) || !DK_WriteCinematicState(&writer)) return Reject(writer.error);
    if (!archivingLevel && !WriteVisited(&writer, map)) return qfalse;
    snapshotLength = DK_SaveFinish(&writer);
    return snapshotLength > 0 ? qtrue : Reject(writer.error);
}

static void Skip(dkSaveReader_t *reader) { dkSaveField_t field; while (DK_SaveNextField(reader, &field)) {} }

static int Kind(const char *name) {
    const char *kinds[] = {"campaign", "entity", "references", "player", "resource", "world", "world_action",
                          "script_state", "script_job", "cinema", "cinema_cast", "cinema_sound", "world_event", "companion_travel", "player_environment", "visited_level"};
    int i;
    for (i = 0; i < ARRAY_LEN(kinds); ++i) if (!strcmp(kinds[i], name)) return i + 1;
    return 0;
}

static qboolean NewRecord(int kind, unsigned int id) {
    unsigned int hash = (id * 2654435761u + kind * 97u) & (ARRAY_LEN(recordKeys) - 1);
    while (recordKeys[hash].kind) {
        if (recordKeys[hash].kind == kind && recordKeys[hash].id == id) return qfalse;
        hash = (hash + 1) & (ARRAY_LEN(recordKeys) - 1);
    }
    recordKeys[hash].kind = kind; recordKeys[hash].id = id;
    return qtrue;
}

static qboolean EntityValues(gentity_t *ent, unsigned int id) {
    int i;
    if (!id || id > 0x7ffffffeu || !ent->classname || !*ent->classname ||
        ent->s.number < 0 || ent->s.number >= ENTITYNUM_MAX_NORMAL ||
        (ent->s.number < MAX_CLIENTS && (id != (unsigned int)metadata.player || ent->s.number != 0)) ||
        (ent->s.number >= MAX_CLIENTS && id <= MAX_CLIENTS) ||
        ent->s.eType < 0 || ent->s.eType >= ET_EVENTS || ent->dk.moverKind < 0 || ent->dk.moverKind > 4 ||
        ent->s.pos.trType < TR_STATIONARY || ent->s.pos.trType > TR_DK_BOUNCE_STOP ||
        ent->s.apos.trType < TR_STATIONARY || ent->s.apos.trType > TR_DK_BOUNCE_STOP ||
        ent->s.pos.trDuration < 0 || ent->s.apos.trDuration < 0 ||
        (ent->dk.moverKind && (ent->speed < 1 || ent->speed > 100000)) ||
        ent->dk.delay < 0 || ent->dk.delay > 3600000 ||
        ent->dk.projectile < 0 || ent->dk.projectile >= DK_WEAPON_COUNT ||
        ent->dk.eventFirst < 0 || ent->dk.eventCount < 0 || ent->dk.eventFirst > 4096 - ent->dk.eventCount ||
        ent->dk.eventCursor < 0 || ent->dk.eventCursor > ent->dk.eventCount ||
        ent->s.modelindex < 0 || ent->s.modelindex >= MAX_MODELS || ent->s.modelindex2 < 0 || ent->s.modelindex2 >= MAX_MODELS ||
        ent->s.loopSound < 0 || ent->s.loopSound >= MAX_SOUNDS || ent->s.dk3Carrier < 0 || ent->s.dk3Carrier > MAX_CLIENTS || !DK_ValidateActorState(ent, metadata.map) ||
        !DK_ValidateDecorState(ent) || !DK_ValidateWorldEffect(ent) || !DK_ValidateWeaponEntity(ent) ||
        ent->dk.combatState < 0 || ent->dk.combatState > 10 || ent->dk.combatCount < 0 ||
        ent->dk.combatCount > DK_WeaponControllerLimit(ent->s.weapon) ||
        ent->dk.monsterAttack < 0 || ent->dk.monsterAttack > 3 || ent->dk.lightStyle < 0 || ent->dk.lightStyle >= 256 ||
        ent->dk.freezeLevel < 0 || ent->dk.freezeLevel > 1 || ent->dk.poisonDamage < 0 || ent->dk.poisonDamage > 10000 ||
        ent->dk.armorAbsorption < 0 || ent->dk.armorAbsorption > 100 ||
        ent->dk.environmentStyle < 0 || ent->dk.environmentStyle > 4 ||
        ent->dk.environmentReverb < 0 || ent->dk.environmentReverb > 1 ||
        ent->dk.environmentGain < 0 || ent->dk.environmentGain > 1 ||
        ent->dk.soundCount < 0 || ent->dk.soundCount > ARRAY_LEN(ent->dk.soundIndices) ||
        ent->dk.soundEnabled < 0 || ent->dk.soundEnabled > 1 || ent->dk.soundDelay < 0 || ent->dk.soundMinimum < 0 ||
        ent->s.dk3Scale < 0 || ent->s.dk3Scale > 100 || ent->s.dk3Alpha < 0 || ent->s.dk3Alpha > 1 ||
        ent->s.dk3SoundVolume < 0 || ent->s.dk3SoundVolume > 1 || ent->s.dk3SoundMin < 0 ||
        ent->s.dk3SoundMax < 0 || ent->s.dk3SoundMax > 65536 || (ent->s.dk3SoundFlags & ~1) ||
        (ent->s.dk3SoundMax && ent->s.dk3SoundMin >= ent->s.dk3SoundMax) ||
        (ent->s.dk3RenderFlags & ~(3 | DK3_RF_ANIM_REVERSE | DK3_RF_STONE | DK3_RF_FROZEN | DK3_RF_MELT)) || (ent->dk.monitorId && (ent->dk.cameraFov < 0 || ent->dk.cameraFov > 160)) ||
        (ent->dk.moverKind == 4 && (ent->dk.action < 0 || ent->dk.action > 5))) return qfalse;
    for (i = 0; i < ent->dk.soundCount; ++i)
        if (ent->dk.soundIndices[i] < 1 || ent->dk.soundIndices[i] >= MAX_SOUNDS) return qfalse;
    for (i = 0; i < 3; ++i) if (ent->r.mins[i] > ent->r.maxs[i] || fabs(ent->r.currentOrigin[i]) > 1000000 ||
        ent->r.maxs[i] - ent->r.mins[i] > 100000) return qfalse;
    return qtrue;
}

static qboolean ValidateWorld(int length, qboolean allowVisited) {
    dkSaveReader_t reader;
    dkSaveField_t field;
    char kind[DK_SAVE_NAME], assets[128];
    unsigned int id;
    int i, j, companionRecords = 0, eventRecords = 0, playerRecords = 0, worldRecords = 0, scriptRecords = 0, cinemaRecords = 0, castRecords = 0, soundRecords = 0, jobRecords = 0;
    int environmentRecords = 0;
    qboolean slots[MAX_GENTITIES];
    if (!DK_SaveValidate(buffer, length, failure, sizeof(failure))) return qfalse;
    memset(staged, 0, sizeof(staged)); memset(identities, 0, sizeof(identities)); memset(slots, 0, sizeof(slots));
    memset(resources, 0, sizeof(resources)); memset(recordKeys, 0, sizeof(recordKeys));
    memset(&metadata, 0, sizeof(metadata)); memset(&stagedPlayer, 0, sizeof(stagedPlayer));
    memset(&stagedEnvironment, 0, sizeof(stagedEnvironment));
    strings.bytes = stringStorage; strings.capacity = sizeof(stringStorage); strings.used = 0; entityCount = 0;
    DK_SaveOpen(&reader, buffer, length);
    if (!DK_SaveNextRecord(&reader, kind, &id) || strcmp(kind, "campaign") || id ||
        !DK_ReadObject(&reader, &metadata, metadataMembers, ARRAY_LEN(metadataMembers), &strings)) return Reject("invalid campaign record");
    NewRecord(1, 0);
    if (metadata.revision != SAVE_REVISION)
        return Reject(va("save gameplay revision %d is incompatible with revision %d", metadata.revision, SAVE_REVISION));
    if (metadata.player != 1 || metadata.entities < 1 || metadata.entities >= ENTITYNUM_MAX_NORMAL ||
        metadata.skill < 1 || metadata.skill > 5 || !Name(metadata.map, 40)) return Reject("incompatible campaign or map identifier");
    if (!AssetIdentity(assets) || !metadata.assets || strcmp(assets, metadata.assets)) return Reject("save uses a different asset generation");
    if (!File(va("maps/%s.bsp", metadata.map))) return Reject("saved map package is missing");
    if (!DK_PrepareScriptValidation(metadata.map)) return Reject("saved map action program is invalid");
    while (DK_SaveNextRecord(&reader, kind, &id)) {
        int type = Kind(kind);
        if (!type || type == 1 || (type == 16 && (!allowVisited || metadata.revision < 4)) || !NewRecord(type, id)) return Reject("unknown or duplicate save record");
        if (type == 2) {
            gentity_t entity;
            memset(&entity, 0, sizeof(entity));
            if (entityCount >= metadata.entities || !DK_ReadObject(&reader, &entity, dk_entityMembers, dk_entityMemberCount, &strings) ||
                !EntityValues(&entity, id) || slots[entity.s.number])
                return Reject(va("map %s entity %u (%s): %s", metadata.map, id, entity.classname ? entity.classname : "<missing>",
                    *reader.error ? reader.error : "invalid or duplicate entity state"));
            slots[entity.s.number] = qtrue;
            identities[entityCount].id = id; identities[entityCount].slot = entity.s.number;
            identities[entityCount++].entity = qtrue;
            entity.dk.id = id; staged[entity.s.number] = entity;
        } else if (type == 4) {
            if (id != metadata.player || ++playerRecords != 1 || !DK_ReadObject(&reader, &stagedPlayer, dk_playerMembers, dk_playerMemberCount, &strings))
                return Reject("invalid player state");
        } else if (type == 5) {
            if (!ResourceSlot(id) || !DK_SaveNextField(&reader, &field) || strcmp(field.name, "path") || field.type != DK_SAVE_TEXT ||
                !field.count || field.count >= MAX_STRING_CHARS || reader.fieldsLeft || strings.used + field.count + 1 > strings.capacity)
                return Reject("invalid resource binding");
            resources[id] = strings.bytes + strings.used; strings.used += field.count + 1;
            DK_SaveString(&field, resources[id], field.count + 1);
        } else if (type == 15) {
            if (metadata.revision < 3 || id != metadata.player || ++environmentRecords != 1 ||
                !DK_ReadObject(&reader, &stagedEnvironment, environmentMembers, ARRAY_LEN(environmentMembers), &strings) ||
                !stagedEnvironment.airOutTime || (long long)stagedEnvironment.airOutTime - level.time < -1000 ||
                (long long)stagedEnvironment.airOutTime - level.time > 12000)
                return Reject("invalid player air deadline");
        } else Skip(&reader);
    }
    if (*reader.error || entityCount != metadata.entities || playerRecords != 1 || !slots[0]) return Reject("incomplete saved world");
    if (metadata.revision >= 3 && environmentRecords != 1) return Reject("missing player environment state");
    /* Revision 2 did not record air. Keep its documented development-save
       behavior; every newly written snapshot carries the actual deadline. */
    if (metadata.revision == SAVE_PRE_ENVIRONMENT_REVISION) stagedEnvironment.airOutTime = level.time + 12000;
    if (stagedPlayer.stats[STAT_HEALTH] < 1 || stagedPlayer.stats[STAT_HEALTH] > 10000 ||
        stagedPlayer.stats[STAT_ARMOR] < 0 || stagedPlayer.stats[STAT_ARMOR] > 10000 || stagedPlayer.dk3Level < 1 || stagedPlayer.dk3Level > 25 ||
        stagedPlayer.pm_type < PM_NORMAL || stagedPlayer.pm_type > PM_FREEZE ||
        !DK_HasWeapon(&stagedPlayer, stagedPlayer.weapon) || stagedPlayer.dk3Objective ||
        stagedPlayer.dk3Episode < 1 || stagedPlayer.dk3Episode > 4 || stagedPlayer.dk3AttributePoints < 0 ||
        stagedPlayer.dk3Experience < 0 || stagedPlayer.dk3SwordExperience < 0 || (stagedPlayer.dk3Quest & ~1) ||
        stagedPlayer.dk3ArmorAbsorption < 0 || stagedPlayer.dk3ArmorAbsorption > 100 ||
        !DK_ValidWeaponPlayer(&stagedPlayer, level.time) ||
        stagedPlayer.dk3FreezeLevel < 0 || stagedPlayer.dk3FreezeLevel > 1 ||
        stagedPlayer.dk3SoundEnvironment < 0 || stagedPlayer.dk3SoundEnvironment > 4 ||
        stagedPlayer.dk3Reverb < 0 || stagedPlayer.dk3Reverb > 1 ||
        stagedPlayer.dk3SoundGain < 0 || stagedPlayer.dk3SoundGain > 1) return Reject("player state is outside supported limits");
    for (i = 0; i < MAX_WEAPONS; ++i) if (stagedPlayer.ammo[i] < 0 || stagedPlayer.ammo[i] > 32767) return Reject("invalid saved ammunition");
    for (i = 0; i < 5; ++i) if (stagedPlayer.dk3Attributes[i] < 0 || stagedPlayer.dk3Attributes[i] > 5) return Reject("invalid saved attribute");
    DK_SaveOpen(&reader, buffer, length);
    while (DK_SaveNextRecord(&reader, kind, &id)) {
        if (!strcmp(kind, "references")) {
            for (i = 0; i < entityCount && identities[i].id != id; ++i) {}
            if (i == entityCount || !DK_SaveNextField(&reader, &field) || strcmp(field.name, "entities") ||
                field.type != DK_SAVE_INT || field.count != REF_COUNT || reader.fieldsLeft) return Reject("invalid entity references");
            for (j = 0; j < REF_COUNT; ++j) {
                int reference = DK_SaveInt(&field, j);
                if (reference != -1 && !(j >= 9 && reference == -2) && !DK_SaveReferenceExists(reference)) return Reject("dangling entity reference");
                identities[i].refs[j] = reference;
            }
            identities[i].references = qtrue;
        } else if (!strcmp(kind, "world") || !strcmp(kind, "world_action") || !strcmp(kind, "world_event")) {
            if (!strcmp(kind, "world")) ++worldRecords;
            if (!strcmp(kind, "world_event") && id != ++eventRecords) return Reject("nonsequential event definitions");
            if (!worldRecords || !DK_ReadWorldState(&reader, kind, id, qfalse)) return Reject("invalid world scheduler state");
        } else if (!strcmp(kind, "script_state") || !strcmp(kind, "script_job")) {
            if (!strcmp(kind, "script_state")) ++scriptRecords; else ++jobRecords;
            if (!scriptRecords || jobRecords > 128 || !DK_ReadScriptState(&reader, kind, id, qfalse)) return Reject("invalid action program state");
        } else if (!strcmp(kind, "cinema") || !strcmp(kind, "cinema_cast") || !strcmp(kind, "cinema_sound")) {
            if (!strcmp(kind, "cinema")) ++cinemaRecords;
            if (!strcmp(kind, "cinema_cast")) ++castRecords;
            if (!strcmp(kind, "cinema_sound")) ++soundRecords;
            if (!cinemaRecords || !DK_ReadCinematicState(&reader, kind, id, qfalse)) return Reject("invalid cinematic state");
        } else if (!strcmp(kind, "companion_travel")) {
            ++companionRecords;
            if (!DK_ReadCompanionState(&reader, id, qfalse)) return Reject("invalid companion campaign state");
        } else Skip(&reader);
    }
    if (*reader.error || companionRecords != 2 || worldRecords != 1 || scriptRecords != 1 || cinemaRecords != 1 ||
        !DK_CinematicSaveCounts(castRecords, soundRecords)) return Reject("incomplete subsystem state");
    for (i = 0; i < entityCount; ++i) {
        gentity_t *ent = &staged[identities[i].slot];
        unsigned int parent = ent->dk.parentId;
        int hops = 0;
        while (parent) {
            int index;
            for (index = 0; index < entityCount && identities[index].id != parent; ++index) {}
            if (index == entityCount || ++hops >= entityCount || parent == ent->dk.id)
                return Reject("missing or cyclic mover parent");
            if (staged[identities[index].slot].s.eType != ET_MOVER) return Reject("attachment parent is not a mover");
            parent = staged[identities[index].slot].dk.parentId;
        }
        if (ent->dk.eventFirst > eventRecords - ent->dk.eventCount || !identities[i].references || !DK_SaveReferenceExists(ent->dk.ownerId) ||
            !DK_SaveReferenceExists(ent->dk.weaponParentId) ||
            !DK_SaveReferenceExists(ent->dk.destinationId) || !DK_SaveReferenceExists(ent->dk.statusOwnerId) || !DK_SaveReferenceExists(ent->dk.pickupId) || !DK_SaveReferenceExists(ent->dk.parentId) || !DK_SaveReferenceExists(ent->dk.monitorId) || !DK_SaveReferenceExists(ent->dk.healingUser)) return Reject("dangling gameplay reference");
        if ((!ent->r.bmodel && ent->s.modelindex && !resources[CS_MODELS + ent->s.modelindex]) ||
            (ent->s.modelindex2 && !resources[CS_MODELS + ent->s.modelindex2]) ||
            (ent->s.loopSound && !resources[CS_SOUNDS + ent->s.loopSound])) return Reject("missing model or sound binding");
        for (j = 0; j < ent->dk.soundCount; ++j)
            if (!resources[CS_SOUNDS + ent->dk.soundIndices[j]]) return Reject("missing speaker sound binding");
    }
    return qtrue;
}

static qboolean Visited(const char *list, const char *map) {
    char *cursor = (char *)list;
    const char *name;
    while (*(name = COM_Parse(&cursor))) if (!strcmp(name, map)) return qtrue;
    return qfalse;
}

static qboolean AddVisited(char list[VISITED_LIST], const char *map) {
    if (Visited(list, map)) return qfalse;
    if (strlen(list) + strlen(map) + 2 >= VISITED_LIST) return qfalse;
    Q_strcat(list, VISITED_LIST, map); Q_strcat(list, VISITED_LIST, " ");
    return qtrue;
}

static const char *MapSlot(int bank, const char *map) { return va("dk3-m%d-%s", bank, map); }

static qboolean ReadVisited(dkSaveReader_t *reader, char map[41], dkSaveField_t *data) {
    dkSaveField_t field;
    return DK_SaveNextField(reader, &field) && !strcmp(field.name, "map") &&
        DK_SaveString(&field, map, 41) && Name(map, 40) &&
        DK_SaveNextField(reader, data) && !strcmp(data->name, "snapshot") &&
        data->type == DK_SAVE_BYTES && data->count > 0 && data->count <= DK_SAVE_WORLD_LIMIT && !reader->fieldsLeft;
}

static qboolean WriteVisited(dkSaveWriter_t *writer, const char *current) {
    char list[VISITED_LIST], *cursor, map[41];
    int length, id = 0, bank = trap_Cvar_VariableIntegerValue("dk3_levelBank") & 1;
    trap_Cvar_VariableStringBuffer("dk3_visited", list, sizeof(list)); cursor = list;
    for (;;) {
        Q_strncpyz(map, COM_Parse(&cursor), sizeof(map));
        if (!*map) break;
        if (!strcmp(map, current)) continue;
        if (!Name(map, 40)) return Reject("invalid visited map identifier");
        length = trap_DK3SaveRead(1, MapSlot(bank, map), mapBuffer, sizeof(mapBuffer), qfalse);
        if (length < 0) return Reject(va("visited map %s is unavailable; running world retained", map));
        if (!DK_SaveRecord(writer, "visited_level", ++id) || !DK_SaveText(writer, "map", map) ||
            !DK_SaveBytes(writer, "snapshot", mapBuffer, length)) return Reject(writer->error);
    }
    return qtrue;
}

static qboolean ValidateSnapshot(int length) {
    dkSaveReader_t reader;
    dkSaveField_t data;
    char kind[DK_SAVE_NAME], map[41], current[41], list[VISITED_LIST] = "";
    unsigned int id, count = 0;
    if (!DK_SaveValidate(buffer, length, failure, sizeof(failure))) return qfalse;
    /* Validate nested worlds first, then restage the active world. No live entity
       or archive index changes until every world has passed semantic validation. */
    if (!ValidateWorld(length, qtrue)) return qfalse;
    Q_strncpyz(current, metadata.map, sizeof(current));
    DK_SaveOpen(&reader, buffer, length);
    while (DK_SaveNextRecord(&reader, kind, &id)) {
        if (!strcmp(kind, "visited_level")) {
            byte *outer = buffer;
            qboolean valid;
            if (id != ++count || count > 128 || !ReadVisited(&reader, map, &data) ||
                !strcmp(map, current) || !AddVisited(list, map)) return Reject("invalid or duplicate visited world");
            buffer = (byte *)data.data;
            valid = ValidateWorld(data.count, qfalse);
            if (valid && strcmp(metadata.map, map)) valid = Reject("visited world map identifier mismatch");
            buffer = outer;
            if (!valid) return qfalse;
        } else Skip(&reader);
    }
    return ValidateWorld(length, qtrue);
}

static qboolean StageVisited(int length) {
    dkSaveReader_t reader;
    dkSaveField_t data;
    char kind[DK_SAVE_NAME], map[41], list[VISITED_LIST] = "";
    unsigned int id;
    int bank = (trap_Cvar_VariableIntegerValue("dk3_levelBank") ^ 1) & 1;
    DK_SaveOpen(&reader, buffer, length);
    while (DK_SaveNextRecord(&reader, kind, &id)) {
        if (!strcmp(kind, "visited_level")) {
            if (!ReadVisited(&reader, map, &data) || !AddVisited(list, map) ||
                trap_DK3SaveWrite(1, MapSlot(bank, map), data.data, data.count) != data.count)
                return Reject("could not stage visited worlds; running campaign retained");
        } else Skip(&reader);
    }
    if (*reader.error) return Reject(reader.error);
    trap_Cvar_Set("dk3_visited", list);
    trap_Cvar_Set("dk3_levelBank", va("%d", bank));
    return qtrue;
}

qboolean DK_ArchiveLevel(gentity_t *player) {
    char map[41], list[VISITED_LIST];
    qboolean written;
    if (g_gametype.integer != GT_SINGLE_PLAYER) return qtrue;
    trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
    trap_Cvar_VariableStringBuffer("dk3_visited", list, sizeof(list));
    if (!Name(map, 40) || (!Visited(list, map) && !AddVisited(list, map))) return qfalse;
    archivingLevel = qtrue;
    written = WriteSnapshot(player) && ValidateWorld(snapshotLength, qfalse);
    archivingLevel = qfalse;
    if (written) written = trap_DK3SaveWrite(1, MapSlot(trap_Cvar_VariableIntegerValue("dk3_levelBank") & 1, map),
        buffer, snapshotLength) == snapshotLength;
    if (!written) {
        trap_SendServerCommand(player->s.number, va("print \"Cannot leave %s: %s\n\"", map, *failure ? failure : "world storage failed"));
        return qfalse;
    }
    trap_Cvar_Set("dk3_visited", list);
    G_Printf("dk3: archived visited world %s\n", map);
    return qtrue;
}

static void RestoreCallbacks(gentity_t *ent) {
    if (ent->client) { ent->die = player_die; return; }
    if (ent->s.eType == ET_DK3_EFFECT || ent->dk.decorKind == -2) { DK_RestoreWorldEffect(ent); return; }
    if (ent->dk.actorKind) DK_RestoreActor(ent);
    else if (ent->dk.decorKind) DK_RestoreDecor(ent);
    else if (ent->dk.projectile) DK_RestoreProjectile(ent);
    else if (ent->s.eType == ET_DK3_ITEM) DK_RestoreItem(ent);
    DK_RestoreMover(ent);
    DK_RestoreWorldCallbacks(ent);
    DK_RestoreMedia(ent);
    DK_RestoreInteraction(ent);
}

static void ApplySnapshot(gentity_t *player) {
    dkSaveReader_t reader;
    char kind[DK_SAVE_NAME];
    unsigned int id;
    int i, j, originalCount = level.num_entities;
    memcpy(baseline, g_entities, sizeof(baseline));
    for (i = 0; i < level.num_entities; ++i) if (g_entities[i].inuse) trap_UnlinkEntity(&g_entities[i]);
    for (i = MAX_CLIENTS; i < ENTITYNUM_MAX_NORMAL; ++i) memset(&g_entities[i], 0, sizeof(g_entities[i]));
    level.num_entities = MAX_CLIENTS;
    for (i = 0; i < entityCount; ++i) {
        identity_t *identity = &identities[i];
        gentity_t *ent = &g_entities[identity->slot], *source = &staged[identity->slot];
        if (identity->slot >= MAX_CLIENTS) {
            for (j = MAX_CLIENTS; j < originalCount; ++j)
                if (baseline[j].inuse && baseline[j].dk.id == identity->id && baseline[j].classname &&
                    !strcmp(baseline[j].classname, source->classname)) { *ent = baseline[j]; break; }
        }
        DK_ApplyObject(ent, source, dk_entityMembers, dk_entityMemberCount);
        ent->inuse = qtrue; ent->dk.id = identity->id; ent->s.number = identity->slot;
        ent->r.linked = qfalse;
        ent->s.event = 0; ent->eventTime = 0;
        if (level.num_entities <= identity->slot) level.num_entities = identity->slot + 1;
        for (j = 0; j < ARRAY_LEN(referenceOffsets); ++j) *(gentity_t **)((byte *)ent + referenceOffsets[j]) = Reference(identity->refs[j]);
        ent->s.groundEntityNum = Slot(identity->refs[9]); ent->r.ownerNum = Slot(identity->refs[10]);
        ent->s.otherEntityNum = Slot(identity->refs[11]); ent->s.otherEntityNum2 = Slot(identity->refs[12]);
        RestoreCallbacks(ent);
    }
    for (i = 0; i < CS_PLAYERS; ++i) if (ResourceSlot(i)) trap_SetConfigstring(i, resources[i] ? resources[i] : "");
    DK_ApplyObject(&player->client->ps, &stagedPlayer, dk_playerMembers, dk_playerMemberCount);
    player->client->ps.clientNum = player->s.number;
    player->client->ps.commandTime = level.time;
    player->client->ps.groundEntityNum = player->s.groundEntityNum;
    player->client->ps.eventSequence = player->client->ps.externalEvent = 0;
    player->client->ps.eFlags ^= EF_TELEPORT_BIT;
    player->client->airOutTime = stagedEnvironment.airOutTime;
    player->client->pers.maxHealth = player->client->ps.stats[STAT_MAX_HEALTH];
    SetClientViewAngle(player, stagedPlayer.viewangles);
    trap_LocateGameData(g_entities, level.num_entities, sizeof(gentity_t), &level.clients[0].ps, sizeof(gclient_t));
    for (i = 0; i < entityCount; ++i) if (staged[identities[i].slot].r.linked) trap_LinkEntity(&g_entities[identities[i].slot]);
    DK_SaveOpen(&reader, buffer, snapshotLength);
    while (DK_SaveNextRecord(&reader, kind, &id)) {
        qboolean ok = qtrue;
        if (!strcmp(kind, "world") || !strcmp(kind, "world_action") || !strcmp(kind, "world_event")) ok = DK_ReadWorldState(&reader, kind, id, qtrue);
        else if (!strncmp(kind, "script_", 7)) ok = DK_ReadScriptState(&reader, kind, id, qtrue);
        else if (!strcmp(kind, "companion_travel")) ok = DK_ReadCompanionState(&reader, id, qtrue);
        else if (!strncmp(kind, "cinema", 6)) ok = DK_ReadCinematicState(&reader, kind, id, qtrue);
        else Skip(&reader);
        if (!ok) G_Error("dk3: validated save could not restore %s %u", kind, id);
    }
    for (i = 0; i < entityCount; ++i) DK_AdoptEntityId(&g_entities[identities[i].slot], identities[i].id);
}

qboolean DK_RestoreVisited(gentity_t *player) {
    char map[41], list[VISITED_LIST], travel[2][2048], pending[4096];
    static const char *names[] = {"dk3_mikiko_travel", "dk3_superfly_travel"};
    gentity_t arrival = *player;
    playerState_t arrivalState = player->client->ps;
    int i;
    trap_Cvar_VariableStringBuffer("dk3_travel", pending, sizeof(pending));
    if (!*pending) return qfalse;
    trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
    trap_Cvar_VariableStringBuffer("dk3_visited", list, sizeof(list));
    if (!Visited(list, map)) return qfalse;
    snapshotLength = trap_DK3SaveRead(1, MapSlot(trap_Cvar_VariableIntegerValue("dk3_levelBank") & 1, map),
        buffer, DK_SAVE_WORLD_LIMIT, qfalse);
    if (snapshotLength < 0 || !ValidateWorld(snapshotLength, qfalse) || strcmp(metadata.map, map))
        G_Error("dk3: cannot restore visited map %s: %s", map, snapshotLength < 0 ? "archive unavailable" : failure);
    for (i = 0; i < 2; ++i) trap_Cvar_VariableStringBuffer(names[i], travel[i], sizeof(travel[i]));
    ApplySnapshot(player);
    /* Enter through the authored landing with the incoming inventory. The old
       player and companions in the archived world must not replace travelers. */
    *player = arrival; player->client->ps = arrivalState;
    SetClientViewAngle(player, arrivalState.viewangles);
    trap_LinkEntity(player);
    for (i = MAX_CLIENTS; i < level.num_entities; ++i)
        if (g_entities[i].inuse && DK_IsCompanion(&g_entities[i]) && !g_entities[i].dk.cinematicOwned)
            G_FreeEntity(&g_entities[i]);
    for (i = 0; i < 2; ++i) trap_Cvar_Set(names[i], travel[i]);
    G_Printf("dk3: restored visited world %s at its arrival landing\n", map);
    return qtrue;
}

qboolean DK_RestoringSave(void) { return trap_Cvar_VariableIntegerValue("dk3_resume") != 0; }

qboolean DK_ResumeSave(gentity_t *player) {
    if (player->s.number != 0 || !DK_RestoringSave()) return qfalse;
    snapshotLength = trap_DK3SaveRead(1, SAVE_PENDING, buffer, sizeof(storage), qfalse);
    if (snapshotLength < 0 || !ValidateSnapshot(snapshotLength)) {
        trap_Cvar_Set("dk3_resume", "0");
        trap_Cvar_Set("dk3_menuResume", "0");
        G_Error("dk3: pending save restore failed: %s", snapshotLength < 0 ? "staged file unavailable" : failure);
        return qfalse;
    }
    if (trap_Cvar_VariableIntegerValue("dk3_menuResume")) {
        trap_Cvar_Set("dk3_menuResume", "0");
        if (!StageVisited(snapshotLength)) G_Error("dk3: could not restore visited worlds: %s", failure);
    }
    if (!trap_DK3HoldWorld(1, qtrue)) G_Error("dk3: restore requires one local client and world-hold interface v1");
    ApplySnapshot(player);
    restartAvailable = trap_DK3SaveWrite(1, SAVE_RESTART, buffer, snapshotLength) == snapshotLength;
    if (!restartAvailable) G_Printf("dk3: restored game could not establish its death checkpoint\n");
    resumeWaiting = qtrue;
    autosavePending = qfalse;
    trap_Cvar_Set("dk3_resume", "0");
    trap_SendServerCommand(player->s.number, "print \"Save restored.\n\"");
    trap_SendServerCommand(player->s.number, "dk3_restore_ready");
    return qtrue;
}

static qboolean LoadSlot(gentity_t *player, const char *slot, qboolean previous) {
    int length;
    *failure = 0;
    length = trap_DK3SaveRead(1, slot, buffer, sizeof(storage), previous);
    if (length < 0) Reject("save slot is missing or unreadable; try load <slot> previous for recovery");
    else if (ValidateSnapshot(length)) {
        if (trap_DK3SaveWrite(1, SAVE_PENDING, buffer, length) != length) Reject("could not stage validated save; running world retained");
        else if (StageVisited(length)) {
            trap_Cvar_Set("dk3_resume", "1"); trap_Cvar_Set("dk3_travel", ""); trap_Cvar_Set("dk3_entry", "");
            trap_Cvar_Set("g_spSkill", va("%d", metadata.skill));
            trap_SendConsoleCommand(EXEC_INSERT, va("map %s\n", metadata.map));
            return qtrue;
        }
    }
    if (*failure) trap_SendServerCommand(player->s.number, va("print \"Load refused: %s\n\"", failure));
    return qfalse;
}

void DK_InitSaves(void) {
    char incoming[4096];
    trap_Cvar_VariableStringBuffer("dk3_travel", incoming, sizeof(incoming));
    if (!*incoming && !DK_RestoringSave()) trap_Cvar_Set("dk3_visited", "");
    archivingLevel = qfalse;
    restartAvailable = qfalse;
    trap_Cvar_Register(NULL, "dk3_unlimitedSaves", "1", CVAR_ARCHIVE);
    trap_Cvar_Register(NULL, "dk3_autosave", "1", CVAR_ARCHIVE);
    autosavePending = !DK_RestoringSave();
    resumeWaiting = qfalse;
}

qboolean DK_LoadRequested(gentity_t *player) {
    char slot[64];
    qboolean previous;
    trap_Cvar_VariableStringBuffer("dk3_loadRequest", slot, sizeof(slot));
    if (!*slot) return qfalse;
    trap_Cvar_Set("dk3_loadRequest", "");
    previous = trap_Cvar_VariableIntegerValue("dk3_loadPrevious") != 0;
    trap_Cvar_Set("dk3_loadPrevious", "0");
    autosavePending = qfalse;
    if (!Name(slot, 48) || !strncmp(slot, "dk3-", 4)) return qfalse;
    return LoadSlot(player, slot, previous);
}

void DK_RunSaves(void) {
    gentity_t *player = &g_entities[0];
    if (!autosavePending || g_gametype.integer != GT_SINGLE_PLAYER || !player->client ||
        player->client->pers.connected != CON_CONNECTED || player->health <= 0 || level.time - level.startTime < 250) return;
    autosavePending = qfalse;
    *failure = 0;
    if (!WriteSnapshot(player) || !ValidateSnapshot(snapshotLength)) {
        G_Printf("dk3: entry autosave failed: %s\n", *failure ? failure : "storage write failed");
        return;
    }
    /* A death checkpoint is distinct from the optional user-visible autosave. */
    restartAvailable = trap_DK3SaveWrite(1, SAVE_RESTART, buffer, snapshotLength) == snapshotLength;
    if (!restartAvailable) G_Printf("dk3: entry death checkpoint write failed\n");
    if (trap_Cvar_VariableIntegerValue("dk3_autosave") &&
        trap_DK3SaveWrite(1, "autosave", buffer, snapshotLength) != snapshotLength)
        G_Printf("dk3: entry autosave write failed\n");
}

qboolean DK_RestartAfterDeath(gentity_t *player) {
    if (g_gametype.integer != GT_SINGLE_PLAYER || player->s.number != 0) return qfalse;
    player->client->respawnTime = level.time + 5000;
    if (DK_RestoringSave() || resumeWaiting) return qtrue;
    if (!restartAvailable || !LoadSlot(player, SAVE_RESTART, qfalse))
        trap_SendServerCommand(player->s.number,
            "cp \"The death checkpoint is unavailable. Load a saved game or start a new game.\"");
    return qtrue;
}

static void SavePresentation(gentity_t *player, const char *slot) {
    char text[1024], map[MAX_QPATH];
    int i, total = 0, found = 0, living = 0, dead = 0, companionHealth[2] = {0, 0};
    trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *ent = &g_entities[i];
        if (!ent->inuse || !ent->classname) continue;
        if (!strcmp(ent->classname, "trigger_secret")) { ++total; if (ent->dk.uses) ++found; }
        if (DK_IsCompanion(ent)) companionHealth[strstr(ent->classname, "mikiko") ? 0 : 1] = ent->health;
        else if (ent->dk.actorKind) { if (ent->health > 0) ++living; else ++dead; }
    }
    Com_sprintf(text, sizeof(text), "dk3_save_info 1\nmap %s\nepisode %d\nhealth %d\narmor %d\nlevel %d\n"
        "mikiko %d\nsuperfly %d\nsecrets %d %d\nactors %d %d\nseconds %d\n",
        map, player->client->ps.dk3Episode, player->health, player->client->ps.stats[STAT_ARMOR],
        player->client->ps.dk3Level - 1, companionHealth[0], companionHealth[1], found, total, dead, living,
        (level.time - level.startTime) / 1000);
    if (trap_DK3SaveWrite(2, slot, text, strlen(text)) != strlen(text)) G_Printf("dk3: save %s metadata write failed\n", slot);
    trap_SendServerCommand(player->s.number, va("dk3_savepreview %s", slot));
}

qboolean DK_SaveCommand(gentity_t *player, const char *command) {
    char slot[64], option[32];
    qboolean writing = !Q_stricmp(command, "save"), reading = !Q_stricmp(command, "load");
    if (!Q_stricmp(command, "dk3_restore_ready")) {
        if (player->s.number == 0 && resumeWaiting) {
            resumeWaiting = qfalse;
            trap_DK3HoldWorld(1, qfalse);
            G_Printf("dk3: restored client ready at simulation time %d\n", level.time);
        }
        return qtrue;
    }
    if (!writing && !reading) return qfalse;
    if (g_gametype.integer != GT_SINGLE_PLAYER || player->s.number != 0 || DK_RestoringSave() || resumeWaiting) {
        trap_SendServerCommand(player->s.number, "print \"Saves are available in a local single-player campaign.\n\""); return qtrue;
    }
    trap_Argv(1, slot, sizeof(slot)); trap_Argv(2, option, sizeof(option));
    if (!*slot) Q_strncpyz(slot, "quick", sizeof(slot));
    if (!Name(slot, 48) || !strncmp(slot, "dk3-", 4) || (*option && (writing || strcmp(option, "previous")))) {
        trap_SendServerCommand(player->s.number, "print \"Use save <slot>, load <slot>, or load <slot> previous. Slots use lowercase letters, digits, _ and -.\n\""); return qtrue;
    }
    *failure = 0;
    if (writing) {
        qboolean spendGem = !trap_Cvar_VariableIntegerValue("dk3_unlimitedSaves");
        if (player->health <= 0) Reject("cannot save a dead player");
        else if (spendGem && player->client->ps.dk3SaveGems < 1) Reject("a save gem is required");
        else {
            if (spendGem) --player->client->ps.dk3SaveGems;
            if (WriteSnapshot(player) && ValidateSnapshot(snapshotLength)) {
                if (trap_DK3SaveWrite(1, slot, buffer, snapshotLength) != snapshotLength) Reject("atomic save write failed; existing save retained");
                else {
                    SavePresentation(player, slot);
                    restartAvailable = trap_DK3SaveWrite(1, SAVE_RESTART, buffer, snapshotLength) == snapshotLength;
                    if (!restartAvailable) G_Printf("dk3: game saved, but death checkpoint write failed\n");
                }
            }
            if (*failure && spendGem) ++player->client->ps.dk3SaveGems;
        }
        trap_SendServerCommand(player->s.number, va("print \"%s\n\"", *failure ? failure : "Game saved."));
        return qtrue;
    }
    LoadSlot(player, slot, *option != 0);
    return qtrue;
}
