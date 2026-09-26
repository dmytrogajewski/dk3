/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "dk_inventory.h"
#include <string.h>
const char *dk_keyClasses[DK_KEY_COUNT] = {
#define DK_KEY(classname, label) classname,
#include "../items/keys.def"
#undef DK_KEY
};
const char *dk_keyLabels[DK_KEY_COUNT] = {
#define DK_KEY(classname, label) label,
#include "../items/keys.def"
#undef DK_KEY
};

typedef struct { const char *classname, *model; } itemModel_t;
static const itemModel_t itemModels[] = {
#define DK_MODEL(classname, model) {classname, model},
#include "../items/models.def"
#undef DK_MODEL
};


const char *DK_ItemModelName(const char *classname) {
    unsigned int i;
    for (i = 0; i < sizeof(itemModels) / sizeof(itemModels[0]); ++i)
        if (!strcmp(classname, itemModels[i].classname)) return itemModels[i].model;
    return NULL;
}
