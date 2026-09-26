/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Resource identifiers, resolved exclusively from the user's converted assets. */
#include "g_local.h"
#include "dk_weapons.h"

#include "dk_inventory.h"

char *DK_ItemModel(const char *classname) {
    int weapon = DK_WeaponId(classname);
    char path[MAX_QPATH], map[MAX_QPATH];
    const char *model = DK_ItemModelName(classname);
    if (weapon) return G_NewString(DK_WeaponWorldModel(weapon));
    if (!Q_stricmp(classname, "item_health_25") || !Q_stricmp(classname, "item_health_50")) {
        int episode;
        trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
        episode = map[0] == 'e' && map[1] >= '1' && map[1] <= '4' ? map[1] - '0' : 1;
        Com_sprintf(path, sizeof(path), "models/e%d/a%d_hlth%s.dkm", episode, episode,
                    episode != 2 && !Q_stricmp(classname, "item_health_50") ? "2" : "");
        return G_NewString(path);
    }
    if (!model || !*model) {
        G_Printf("dk3: item %s: no supplied model binding\n", classname);
        return NULL;
    }
    Com_sprintf(path, sizeof(path), "models/%s.dkm", model);
    return G_NewString(path);
}
