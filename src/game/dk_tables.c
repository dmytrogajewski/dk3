/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef CGAME
#include "cg_local.h"
#define TableError CG_Error
#define TablePrint CG_Printf
#else
#include "g_local.h"
#define TableError G_Error
#define TablePrint G_Printf
#endif
#include "dk_tables.h"

#define DK_TABLE_BYTES (4 * 1024 * 1024)
static char input[DK_TABLE_BYTES + 1];
static dkRecord_t record;

void DK_ReadTable(const char *name, void (*consume)(const dkRecord_t *row)) {
    char path[MAX_QPATH], *cursor, *token;
    fileHandle_t file;
    int length, row = 0;
    Com_sprintf(path, sizeof(path), "dk3/tables/%s.cfg", name);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length <= 0 || length > DK_TABLE_BYTES) {
        if (file) trap_FS_FCloseFile(file);
        TableError("dk3: required table %s missing, empty or too large; rebuild assets", path);
    }
    trap_FS_Read(input, length, file);
    trap_FS_FCloseFile(file);
    input[length] = 0;
    cursor = input;
    if (strcmp(COM_Parse(&cursor), "dk3_table") || strcmp(COM_Parse(&cursor), "1"))
        TableError("dk3: %s: unsupported table header", path);
    while (*(token = COM_Parse(&cursor))) {
        if (strcmp(token, "{")) TableError("dk3: %s row %d: expected record", path, row + 1);
        record.count = 0;
        ++row;
        for (;;) {
            int field = record.count;
            token = COM_Parse(&cursor);
            if (!cursor) TableError("dk3: %s row %d: unfinished record", path, row);
            if (!strcmp(token, "}")) break;
            if (field == DK_TABLE_FIELDS || strlen(token) >= sizeof(record.keys[0]))
                TableError("dk3: %s row %d: field limit exceeded", path, row);
            Q_strncpyz(record.keys[field], token, sizeof(record.keys[0]));
            token = COM_Parse(&cursor);
            if (!cursor || strlen(token) >= sizeof(record.values[0]))
                TableError("dk3: %s row %d key %s: value missing or too long", path, row, record.keys[field]);
            Q_strncpyz(record.values[field], token, sizeof(record.values[0]));
            ++record.count;
        }
        consume(&record);
    }
    TablePrint("dk3: %s: %d records\n", path, row);
}

const char *DK_Field(const dkRecord_t *row, const char *key) {
    int i;
    for (i = 0; i < row->count; ++i) if (!strcmp(key, row->keys[i])) return row->values[i];
    return "";
}

float DK_Number(const dkRecord_t *row, const char *key, float fallback) {
    const char *value = DK_Field(row, key), *p = value;
    float number;
    qboolean digit = qfalse;
    if (!*p) return fallback;
    if (*p == '+' || *p == '-') ++p;
    while (*p >= '0' && *p <= '9') { digit = qtrue; ++p; }
    if (*p == '.') {
        ++p;
        while (*p >= '0' && *p <= '9') { digit = qtrue; ++p; }
    }
    if (*p == 'e' || *p == 'E') {
        ++p;
        if (*p == '+' || *p == '-') ++p;
        if (*p < '0' || *p > '9') digit = qfalse;
        while (*p >= '0' && *p <= '9') ++p;
    }
    number = atof(value);
    if (!digit || *p || Q_isnan(number) || number < -10000000 || number > 10000000)
        TableError("dk3: table class %s key %s: invalid number %s", DK_Field(row, "classname"), key, value);
    return number;
}
