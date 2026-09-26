/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef DK_SAVE_SCHEMA_H
#define DK_SAVE_SCHEMA_H
#include "dk_save_format.h"

typedef struct {
    const char *name;
    dkSaveType_t type;
    size_t offset;
    int count;
    qboolean time;
    /* Added after release: older saves omit it and it reads as zero. */
    qboolean optional;
} dkSaveMember_t;
typedef struct { char *bytes; int capacity, used; } dkSaveStrings_t;
extern const dkSaveMember_t dk_entityMembers[];
extern const int dk_entityMemberCount;
extern const dkSaveMember_t dk_playerMembers[];
extern const int dk_playerMemberCount;
qboolean DK_SaveObject(dkSaveWriter_t *writer, const void *object, const dkSaveMember_t *members, int count);
qboolean DK_ReadObject(dkSaveReader_t *reader, void *object, const dkSaveMember_t *members, int count,
                       dkSaveStrings_t *strings);
void DK_ApplyObject(void *destination, const void *source, const dkSaveMember_t *members, int count);
qboolean DK_WriteWorldState(dkSaveWriter_t *writer);
qboolean DK_ReadWorldState(dkSaveReader_t *reader, const char *kind, unsigned int id, qboolean apply);
qboolean DK_WriteScriptState(dkSaveWriter_t *writer);
qboolean DK_ReadScriptState(dkSaveReader_t *reader, const char *kind, unsigned int id, qboolean apply);
qboolean DK_PrepareScriptValidation(const char *map);
qboolean DK_WriteCinematicState(dkSaveWriter_t *writer);
qboolean DK_ReadCinematicState(dkSaveReader_t *reader, const char *kind, unsigned int id, qboolean apply);
qboolean DK_CinematicSaveCounts(int actors, int sounds);
qboolean DK_WriteCompanionState(dkSaveWriter_t *writer);
qboolean DK_ReadCompanionState(dkSaveReader_t *reader, unsigned int id, qboolean apply);
#endif
