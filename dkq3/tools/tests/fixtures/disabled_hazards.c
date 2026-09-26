/* SPDX-License-Identifier: GPL-2.0-or-later */
#undef NDEBUG
#include <assert.h>
#include <strings.h>
#include "../../../../src/game/dk_interactions.c"
level_locals_t level;
gentity_t g_entities[MAX_GENTITIES];
static int links;
int Q_stricmp(const char *a, const char *b) { return strcasecmp(a, b); }
gentity_t *G_Find(gentity_t *from, int offset, const char *name) {
    int i = from ? (int)(from - g_entities) + 1 : 0;
    for (; i < level.num_entities; ++i) {
        char *value = *(char **)((char *)&g_entities[i] + offset);
        if (g_entities[i].inuse && value && !strcmp(value, name)) return &g_entities[i];
    }
    return NULL;
}
void trap_LinkEntity(gentity_t *entity) { ++links; }
int main(void) {
    int i;
    gentity_t *hurt = &g_entities[0];
    const char *names[] = {"laser_dam", "laser1", "laser2", "laser3", "other_hurt"};
    level.num_entities = 5;
    for (i = 0; i < 5; ++i) {
        g_entities[i].inuse = qtrue;
        g_entities[i].classname = i == 0 || i == 4 ? "trigger_hurt" : "func_button";
        g_entities[i].targetname = (char *)names[i];
        g_entities[i].r.contents = CONTENTS_TRIGGER;
    }
    for (i = 1; i <= 3; ++i) {
        DK_RepairDisabledHazards("e1m3b");
        assert(hurt->r.contents == CONTENTS_TRIGGER && links == 0);
        g_entities[i].inuse = qfalse;
    }
    DK_RepairDisabledHazards("e1m4a");
    assert(hurt->r.contents == CONTENTS_TRIGGER); /* No global hazard override. */
    DK_RepairDisabledHazards("e1m3b");
    assert(hurt->r.contents == 0 && links == 1);
    assert(g_entities[4].r.contents == CONTENTS_TRIGGER);
    DK_RepairDisabledHazards("e1m3b");
    assert(links == 1);
    hurt->r.contents = CONTENTS_TRIGGER; /* Legacy save after shutdown. */
    DK_RepairDisabledHazards("e1m3b");
    assert(hurt->r.contents == 0 && links == 2);
    return 0;
}
