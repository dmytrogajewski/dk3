/* SPDX-License-Identifier: GPL-2.0-or-later
 * Exercise the actual engine collision loader, not a second implementation. */
#include "q_shared.h"
#include "qcommon.h"

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "collision worlds: line %d: %s\n", __LINE__, #condition); exit(1); } } while (0)

void QDECL Com_Printf(const char *format, ...) { (void)format; }
void QDECL Com_DPrintf(const char *format, ...) { (void)format; }
void QDECL Com_Error(int code, const char *format, ...) {
    va_list args;
    (void)code;
    va_start(args, format); vfprintf(stderr, format, args); va_end(args);
    exit(2);
}
#undef Z_Malloc
void *Z_Malloc(int size) { void *p = calloc(1, size ? size : 1); CHECK(p); return p; }
void *Z_MallocDebug(int size, char *label, char *file, int line) {
    (void)label; (void)file; (void)line; return Z_Malloc(size);
}
void Z_Free(void *p) { free(p); }
void BotDrawDebugPolygons(void (*drawPoly)(int, int, float *), int value) { (void)drawPoly; (void)value; }
cvar_t *Cvar_Get(const char *name, const char *value, int flags) {
    static cvar_t disabled, enabled = { .integer = 1, .value = 1 };
    (void)name; (void)flags;
    return atoi(value) ? &enabled : &disabled;
}
long FS_ReadFile(const char *name, void **bytes) { (void)name; *bytes = NULL; return -1; }
void FS_FreeFile(void *bytes) { free(bytes); }
fsReadJob_t *FS_BeginBackgroundRead(const char *path, int maximum) { (void)path; (void)maximum; return NULL; }
int FS_PollBackgroundRead(fsReadJob_t *job, const void **bytes, int *length) { (void)job; *bytes = NULL; *length = 0; return -1; }
void FS_EndBackgroundRead(fsReadJob_t *job) { CHECK(!job); }

static int append(byte *bytes, int *at, int lump, const void *data, int length) {
    dheader_t *header = (dheader_t *)bytes;
    header->lumps[lump].fileofs = *at;
    header->lumps[lump].filelen = length;
    if (length) memcpy(bytes + *at, data, length);
    *at += (length + 3) & ~3;
    return *at;
}

static int fixture(byte *bytes, float height, const char *message) {
    int i, at = sizeof(dheader_t), leafBrush = 0;
    dheader_t *header = (dheader_t *)bytes;
    dshader_t shader = { .contentFlags = CONTENTS_SOLID };
    dplane_t planes[6] = {0};
    dnode_t node = { .children = {-1, -1} };
    dleaf_t leaf = { .numLeafBrushes = 1 };
    dbrush_t brush = { .numSides = 6 };
    dbrushside_t sides[6] = {0};
    dmodel_t models[2] = {0};
    memset(bytes, 0, 4096);
    header->ident = BSP_IDENT;
    header->version = BSP_VERSION;
    for (i = 0; i < 6; ++i) {
        planes[i].normal[i / 2] = i & 1 ? 1 : -1;
        planes[i].dist = i < 4 ? 32 : (i == 4 ? 32 - height : height);
        sides[i].planeNum = i;
    }
    for (i = 0; i < 2; ++i) {
        VectorSet(models[i].mins, -32, -32, height - 32);
        VectorSet(models[i].maxs, 32, 32, height);
        models[i].numBrushes = 1;
    }
    append(bytes, &at, LUMP_ENTITIES, message, strlen(message) + 1);
    append(bytes, &at, LUMP_SHADERS, &shader, sizeof(shader));
    append(bytes, &at, LUMP_PLANES, planes, sizeof(planes));
    append(bytes, &at, LUMP_NODES, &node, sizeof(node));
    append(bytes, &at, LUMP_LEAFS, &leaf, sizeof(leaf));
    append(bytes, &at, LUMP_LEAFBRUSHES, &leafBrush, sizeof(leafBrush));
    append(bytes, &at, LUMP_MODELS, models, sizeof(models));
    append(bytes, &at, LUMP_BRUSHES, &brush, sizeof(brush));
    append(bytes, &at, LUMP_BRUSHSIDES, sides, sizeof(sides));
    return at;
}

static void hit(unsigned int world, int model, float height) {
    trace_t trace;
    vec3_t start = {0, 0, 100}, end = {0, 0, -100}, zero = {0};
    CHECK(CM_SelectWorld(world));
    CM_BoxTrace(&trace, start, end, zero, zero, model, CONTENTS_SOLID, qfalse);
    CHECK(!trace.startsolid && trace.fraction > 0 && trace.fraction < 1);
    CHECK(fabs(trace.endpos[2] - height - 0.125f) < 0.001f);
}

int main(void) {
    byte bytes[4096];
    unsigned int base = CM_CurrentWorld(), a, b, replacement;
    int length = fixture(bytes, 0, "world a");
    a = CM_LoadWorldBytes("maps/a.bsp", bytes, length);
    CHECK(a && CM_CurrentWorld() == base);
    CHECK(CM_WorldBytes(a) > 0);
    length = fixture(bytes, 50, "world b");
    b = CM_LoadWorldBytes("maps/b.bsp", bytes, length);
    CHECK(b && b != a && CM_CurrentWorld() == base);
    hit(a, 0, 0); hit(b, 0, 50); hit(a, 1, 0); hit(b, 1, 50);
    CHECK(!strcmp(CM_EntityString(), "world b"));
    CHECK(!CM_ReleaseWorld(b)); /* selected world is pinned */
    CHECK(CM_SelectWorld(base));
    CHECK(CM_ReleaseWorld(a));
    CHECK(!CM_SelectWorld(a) && CM_PollWorld(a) == -1 && !CM_WorldBytes(a));
    replacement = CM_LoadWorldBytes("maps/a.bsp", bytes, length);
    CHECK(replacement && replacement != a && !CM_SelectWorld(a));
    ((dheader_t *)bytes)->lumps[LUMP_PLANES].filelen = 100000;
    CHECK(!CM_LoadWorldBytes("maps/bad.bsp", bytes, length));
    hit(b, 0, 50);
    CM_ClearMap();
    CHECK(!CM_SelectWorld(b) && !CM_SelectWorld(replacement) && !CM_SelectWorld(base));
    CHECK(CM_CurrentWorld() != base);
    CM_ClearMap();
    puts("collision worlds: isolated geometry, inline models, pinned ownership, stale handles and malformed-header rejection passed");
    return 0;
}
