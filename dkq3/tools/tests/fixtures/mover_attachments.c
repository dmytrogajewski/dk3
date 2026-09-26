/* SPDX-License-Identifier: GPL-2.0-or-later */
#undef NDEBUG
#include <assert.h>
#include "../../../../src/game/dk_attachments.c"

level_locals_t level;
gentity_t g_entities[MAX_GENTITIES];
static gentity_t baseline[MAX_GENTITIES];
gentity_t *DK_FindEntity(unsigned int id) {
    int i;
    for (i = 0; id && i < level.num_entities; ++i)
        if (g_entities[i].inuse && g_entities[i].dk.id == id) return &g_entities[i];
    return NULL;
}
void trap_LinkEntity(gentity_t *entity) { entity->r.linked = qtrue; }
void G_Printf(const char *fmt, ...) {}
void G_SetOrigin(gentity_t *entity, vec3_t origin) {
    VectorCopy(origin, entity->r.currentOrigin);
    VectorCopy(origin, entity->s.origin);
    VectorCopy(origin, entity->s.pos.trBase);
    entity->s.pos.trType = TR_STATIONARY;
}

int main(void) {
    gentity_t *root = &g_entities[MAX_CLIENTS], *child = root + 1, *nested = root + 2;
    vec3_t first = {-1980, 472, 112}, next = {-1980, 536, 52};
    int i;
    level.num_entities = MAX_CLIENTS + 3;
    for (i = 0; i < 3; ++i) { root[i].inuse = qtrue; root[i].dk.id = i + 1; }
    root->dk.moverKind = 3; root->dk.moverInitialized = root->dk.moverPaused = 1;
    root->dk.destinationId = 100;
    VectorSet(root->pos1, -2032, 544, 32); G_SetOrigin(root, root->pos1);
    VectorSet(child->pos1, -2032, 528, 8); G_SetOrigin(child, child->pos1);
    child->dk.parentId = root->dk.id;
    nested->dk.parentId = child->dk.id;
    VectorSet(nested->s.origin, -2032, 528, 20); G_SetOrigin(nested, nested->s.origin);
    nested->dk.moverAngular = 1; VectorSet(nested->pos1, 0, 90, 0);
    DK_TeleportAssembly(root, first);
    assert(child->r.currentOrigin[0] == -1980 && child->r.currentOrigin[1] == 456 && child->r.currentOrigin[2] == 88);
    assert(nested->r.currentOrigin[2] == 100 && nested->pos1[1] == 90);
    assert(child->s.pos.trBase[2] == 88 && child->r.linked);
    memcpy(baseline, g_entities, sizeof(baseline));
    /* Old save contains a moved root but children left at their authored origin. */
    { vec3_t wrong = {-2032, 528, 8}; G_SetOrigin(child, wrong); }
    DK_RepairSavedAttachments(baseline, level.num_entities);
    assert(child->r.currentOrigin[2] == 88 && root->dk.assemblyVersion == 1);
    DK_RepairSavedAttachments(baseline, level.num_entities);
    assert(child->r.currentOrigin[2] == 88);
    DK_TeleportAssembly(root, next);
    assert(child->r.currentOrigin[1] == 520 && child->r.currentOrigin[2] == 28);
    assert(nested->r.currentOrigin[1] == 520 && nested->r.currentOrigin[2] == 40);
    assert(root->pos1[0] == -2032); /* Keep the authored train anchor. */
    return 0;
}
