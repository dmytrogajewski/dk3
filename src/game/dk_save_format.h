/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef DK_SAVE_FORMAT_H
#define DK_SAVE_FORMAT_H

/* Portable record stream. All lengths, integers and IEEE floats are explicitly
   little endian; pointers and ABI-sized structures are never persisted. */
#define DK_SAVE_VERSION 1
#define DK_SAVE_LIMIT (256 * 1024 * 1024)
#define DK_SAVE_WORLD_LIMIT (32 * 1024 * 1024)
#define DK_SAVE_NAME 64
#define DK_SAVE_FIELDS 256
#define DK_SAVE_RECORDS 16384

typedef enum { DK_SAVE_INT = 1, DK_SAVE_FLOAT = 2, DK_SAVE_TEXT = 3, DK_SAVE_BYTES = 4 } dkSaveType_t;
typedef struct {
    byte *data;
    int capacity, length, recordStart, fields;
    unsigned int records;
    char error[160];
} dkSaveWriter_t;
typedef struct {
    const byte *data;
    int length, at, recordsLeft, recordEnd, fieldsLeft;
    char error[160];
} dkSaveReader_t;
typedef struct {
    char name[DK_SAVE_NAME];
    dkSaveType_t type;
    int count;
    const byte *data;
} dkSaveField_t;

qboolean DK_SaveBegin(dkSaveWriter_t *writer, byte *buffer, int capacity);
qboolean DK_SaveRecord(dkSaveWriter_t *writer, const char *kind, unsigned int id);
qboolean DK_SaveInts(dkSaveWriter_t *writer, const char *name, const int *values, int count);
qboolean DK_SaveFloats(dkSaveWriter_t *writer, const char *name, const float *values, int count);
qboolean DK_SaveText(dkSaveWriter_t *writer, const char *name, const char *value);
qboolean DK_SaveBytes(dkSaveWriter_t *writer, const char *name, const byte *data, int count);
int DK_SaveFinish(dkSaveWriter_t *writer);
qboolean DK_SaveOpen(dkSaveReader_t *reader, const byte *buffer, int length);
qboolean DK_SaveNextRecord(dkSaveReader_t *reader, char kind[DK_SAVE_NAME], unsigned int *id);
qboolean DK_SaveNextField(dkSaveReader_t *reader, dkSaveField_t *field);
int DK_SaveInt(const dkSaveField_t *field, int index);
float DK_SaveFloat(const dkSaveField_t *field, int index);
qboolean DK_SaveString(const dkSaveField_t *field, char *out, int capacity);
qboolean DK_SaveValidate(const byte *buffer, int length, char *error, int capacity);

#endif
