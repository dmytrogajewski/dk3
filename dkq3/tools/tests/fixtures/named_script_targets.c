/* SPDX-License-Identifier: GPL-2.0-or-later */
#undef NDEBUG
#include <assert.h>
#include <strings.h>
#include "../../../../src/game/dk_scripts.c"
level_locals_t level;
gentity_t g_entities[MAX_GENTITIES];
static int calls[4];
int Q_stricmp(const char *a, const char *b) { return strcasecmp(a, b); }
int trap_Cvar_VariableIntegerValue(const char *name) { return 0; }
void G_Printf(const char *fmt, ...) {}
gentity_t *DK_FindEntity(unsigned int id) { return id == 10 ? &g_entities[0] : NULL; }
static void Used(gentity_t *target, gentity_t *source, gentity_t *activator) {
    assert(source == &g_entities[0] && activator == source);
    ++calls[target->s.number];
}
int main(void) {
    int i;
    level.num_entities = 4;
    for (i = 0; i < 4; ++i) { g_entities[i].inuse = qtrue; g_entities[i].s.number = i; }
    g_entities[0].dk.id = 10;
    for (i = 1; i < 4; ++i) g_entities[i].use = Used;
    g_entities[1].dk.uniqueid = "spawnsuper";
    g_entities[2].targetname = "killdeco3";
    g_entities[3].targetname = "killdeco3";
    g_entities[3].dk.uniqueid = "killdeco3";
    DK_FireNamed("spawnsuper", &g_entities[0], &g_entities[0]);
    assert(calls[1] == 1 && calls[2] == 0 && calls[3] == 0);
    DK_FireNamed("killdeco3", &g_entities[0], &g_entities[0]);
    assert(calls[2] == 1 && calls[3] == 1); /* Both relays, each once. */
    return 0;
}
