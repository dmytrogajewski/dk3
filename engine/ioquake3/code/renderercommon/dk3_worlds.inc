/* SPDX-License-Identifier: GPL-2.0-or-later */
static dkRenderWorld_t *R_ResidentWorld(unsigned int handle) {
    unsigned int index = handle & 255;
    if (!index || index > DK3_RENDER_WORLDS) return NULL;
    if (!dkRenderWorlds[index - 1].status || dkRenderWorlds[index - 1].generation != (handle >> 8)) return NULL;
    return &dkRenderWorlds[index - 1];
}

static unsigned int R_WorldHandle(dkRenderWorld_t *world) {
    return (world->generation << 8) | (unsigned int)(world - dkRenderWorlds + 1);
}

/* Only map-owned state is copied. Images, compiled materials, ordinary models
 * and frame counters remain in the renderer's shared region resource registry. */
static void R_SaveWorld(dkRenderWorld_t *world) {
#define SAVE(field) world->field = tr.field
    SAVE(numLightmaps); SAVE(lightmaps); SAVE(sunShader);
    VectorCopy(tr.sunLight, world->sunLight);
    VectorCopy(tr.sunDirection, world->sunDirection);
    world->lightBlocks = dkLightBlocks;
    world->lightBlockCount = dkLightBlockCount;
#ifdef DK3_RENDER_GL2
    SAVE(lightmapSize); SAVE(fatLightmapCols); SAVE(fatLightmapRows);
    SAVE(deluxemaps); SAVE(worldDeluxeMapping); SAVE(sunShadows);
    SAVE(numCubemaps); SAVE(cubemaps); SAVE(sunShadowScale); SAVE(sunFlareShader);
    memcpy(world->autoExposureMinMax, tr.autoExposureMinMax, sizeof(world->autoExposureMinMax));
    VectorCopy(tr.toneMinAvgMaxLevel, world->toneMinAvgMaxLevel);
#endif
#undef SAVE
}

static void R_ApplyWorld(dkRenderWorld_t *world) {
    tr.world = world ? &world->world : NULL;
    tr.worldRegistration = world ? R_WorldHandle(world) : 0;
    tr.worldMapLoaded = world != NULL;
    tr.externalVisData = NULL; /* Each resident world owns its PVS bytes. */
    if (!world) return;
#define RESTORE(field) tr.field = world->field
    RESTORE(numLightmaps); RESTORE(lightmaps); RESTORE(sunShader);
    VectorCopy(world->sunLight, tr.sunLight);
    VectorCopy(world->sunDirection, tr.sunDirection);
    dkLightBlocks = world->lightBlocks;
    dkLightBlockCount = world->lightBlockCount;
    tr.viewCluster = -1;
#ifdef DK3_RENDER_GL2
    RESTORE(lightmapSize); RESTORE(fatLightmapCols); RESTORE(fatLightmapRows);
    RESTORE(deluxemaps); RESTORE(worldDeluxeMapping); RESTORE(sunShadows);
    RESTORE(numCubemaps); RESTORE(cubemaps); RESTORE(sunShadowScale); RESTORE(sunFlareShader);
    memcpy(tr.autoExposureMinMax, world->autoExposureMinMax, sizeof(tr.autoExposureMinMax));
    VectorCopy(world->toneMinAvgMaxLevel, tr.toneMinAvgMaxLevel);
    VectorClear(tr.lastCascadeSunDirection);
    {
        int i;
        for (i = 0; i < MAX_VISCOUNTS; ++i) tr.visClusters[i] = -2;
    }
#endif
#undef RESTORE
}

unsigned int RE_CurrentWorld(void) { return tr.worldRegistration; }

qboolean RE_SelectWorld(unsigned int handle) {
    dkRenderWorld_t *world = R_ResidentWorld(handle), *previous;
    if (!world || world->status != 2) return qfalse;
    if (handle == tr.worldRegistration) return qtrue;
    /* Backends access the selected world's fog/cubemap tables. Complete queued
     * scenes before replacing those tables, including when preparation polls. */
    R_IssuePendingRenderCommands();
    previous = R_ResidentWorld(tr.worldRegistration);
    if (previous) R_SaveWorld(previous);
    R_ApplyWorld(world);
    return qtrue;
}

static dkRenderWorld_t *R_ReserveWorld(const char *name) {
    unsigned int i;
    if (!name || strncmp(name, "maps/", 5) || !COM_CompareExtension(name, ".bsp") || strlen(name) >= MAX_QPATH) return NULL;
    for (i = 0; i < DK3_RENDER_WORLDS; ++i) {
        dkRenderWorld_t *world = &dkRenderWorlds[i];
        if (world->status || world->generation == 0x7fffff) continue;
        if (!world->generation) world->generation = 1;
        Q_strncpyz(world->name, name, sizeof(world->name));
        world->status = 1;
        return world;
    }
    return NULL;
}

unsigned int RE_RequestWorld(const char *name) {
    dkRenderWorld_t *world;
    unsigned int i, reading = 0;
    if (!name || !name[0]) return 0;
    for (i = 0; i < DK3_RENDER_WORLDS; ++i) {
        if (dkRenderWorlds[i].status && !strcmp(dkRenderWorlds[i].name, name)) return R_WorldHandle(&dkRenderWorlds[i]);
        if (dkRenderWorlds[i].read) ++reading;
    }
    if (reading >= 4 || !(world = R_ReserveWorld(name))) return 0;
    world->read = ri.BeginBackgroundRead(name, 128 * 1024 * 1024);
    if (!world->read) world->status = -1;
    return R_WorldHandle(world);
}

static qboolean R_WorldHeader(const void *bytes, int length) {
    dheader_t header;
    int i;
    if (!bytes || length < sizeof(header)) return qfalse;
    memcpy(&header, bytes, sizeof(header));
    if (LittleLong(header.ident) != BSP_IDENT || LittleLong(header.version) != BSP_VERSION) return qfalse;
    for (i = 0; i < HEADER_LUMPS; ++i) {
        int start = LittleLong(header.lumps[i].fileofs), size = LittleLong(header.lumps[i].filelen);
        if (start < 0 || size < 0 || start > length || size > length - start) return qfalse;
    }
    return qtrue;
}

static qboolean R_AdmitWorld(dkRenderWorld_t *world, void *bytes, int length) {
    dkRenderWorld_t *previous = R_ResidentWorld(tr.worldRegistration);
    qboolean done;
    R_IssuePendingRenderCommands();
    if (previous) R_SaveWorld(previous);
    R_ApplyWorld(world);
    dkLoadingWorld = world;
    done = R_DecodeWorldMap(world->name, bytes, length);
    R_SaveWorld(world);
    if (done) world->status = 2;
    dkLoadingWorld = NULL;
    fileBase = NULL;
    R_ApplyWorld(previous);
    return done;
}

int RE_PollWorld(unsigned int handle) {
    dkRenderWorld_t *world = R_ResidentWorld(handle);
    const void *bytes;
    int length, result;
    if (!world || world->status == -1) return -1;
    if (world->status == 2) return 1;
    if (!world->read) return -1;
    result = ri.PollBackgroundRead(world->read, &bytes, &length);
    if (!result) return 0;
    if (result == 1 && (world->admission || R_WorldHeader(bytes, length))) {
        if (!R_AdmitWorld(world, (void *)bytes, length)) return 0;
    } else world->status = -1;
    ri.EndBackgroundRead(world->read);
    world->read = NULL;
    return world->status == 2 ? 1 : -1;
}

void RE_LoadWorldMap(const char *name) {
    dkRenderWorld_t *world;
    void *bytes = NULL;
    int length;
    if (tr.worldMapLoaded) ri.Error(ERR_DROP, "World already selected; use resident selection");
    if (!(world = R_ReserveWorld(name))) ri.Error(ERR_DROP, "Cannot reserve render world %s", name);
    length = ri.FS_ReadFile(name, &bytes);
    if (!R_WorldHeader(bytes, length)) {
        if (bytes) ri.FS_FreeFile(bytes);
        ri.Error(ERR_DROP, "Invalid render world %s", name);
    }
    while (!R_AdmitWorld(world, bytes, length)) {}
    ri.FS_FreeFile(bytes);
    RE_SelectWorld(R_WorldHandle(world));
}

qhandle_t R_WorldInlineModel(const char *name) {
    dkRenderWorld_t *world = R_ResidentWorld(tr.worldRegistration);
    char *end;
    long index;
    if (!world || world->status != 2 || !name || name[0] != '*') return 0;
    index = strtol(name + 1, &end, 10);
    if (end == name + 1 || *end || index < 0 || index >= world->inlineCount) return 0;
    return world->inlineModels[index];
}

void R_ClearResidentWorlds(void) {
    unsigned int i;
    if (tr.registered) R_IssuePendingRenderCommands();
    for (i = 0; i < DK3_RENDER_WORLDS; ++i) {
        dkRenderWorld_t *world = &dkRenderWorlds[i];
        unsigned int generation = world->generation;
        if (world->read) ri.EndBackgroundRead(world->read);
        if (world->hdrVertices) ri.Free(world->hdrVertices);
        memset(world, 0, sizeof(*world));
        world->generation = generation < 0x7fffff ? generation + 1 : generation;
    }
    dkLoadingWorld = NULL;
    dkLightBlocks = NULL;
    dkLightBlockCount = 0;
    R_ApplyWorld(NULL);
}
