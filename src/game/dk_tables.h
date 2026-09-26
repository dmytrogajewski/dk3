/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef DK_TABLES_H
#define DK_TABLES_H

#define DK_TABLE_FIELDS 96
#define DK_TABLE_VALUE 256
typedef struct {
    int count;
    char keys[DK_TABLE_FIELDS][64];
    char values[DK_TABLE_FIELDS][DK_TABLE_VALUE];
} dkRecord_t;

void DK_ReadTable(const char *name, void (*consume)(const dkRecord_t *row));
const char *DK_Field(const dkRecord_t *row, const char *key);
float DK_Number(const dkRecord_t *row, const char *key, float fallback);

#endif
