/* SPDX-License-Identifier: GPL-2.0-or-later
 * Per-map renderer state. Geometry/material allocations live for the region;
 * shutdown releases the region after pending draw commands have completed. */
#define DK3_RENDER_WORLDS 128
#define DK3_WORLD_INLINE_MODELS 512
typedef struct {
    world_t world;
    unsigned int generation;
    int admission;
    int surfaceNext, surfaceCounts[4];
    byte *allocationStart;
    float *hdrVertices;
    int status; /* 0 free, 1 reading, 2 ready, -1 failed */
    struct fsReadJob_s *read;
    char name[MAX_QPATH];
    qhandle_t inlineModels[DK3_WORLD_INLINE_MODELS];
    int inlineCount;
    int numLightmaps;
    image_t **lightmaps;
    void *lightBlocks;
    int lightBlockCount;
    vec3_t sunLight, sunDirection;
    shader_t *sunShader;
#ifdef DK3_RENDER_GL2
    int lightmapSize, fatLightmapCols, fatLightmapRows;
    image_t **deluxemaps;
    qboolean worldDeluxeMapping, sunShadows;
    int numCubemaps;
    cubemap_t *cubemaps;
    vec2_t autoExposureMinMax;
    vec3_t toneMinAvgMaxLevel;
    float sunShadowScale;
    shader_t *sunFlareShader;
#endif
} dkRenderWorld_t;
static dkRenderWorld_t dkRenderWorlds[DK3_RENDER_WORLDS];
static dkRenderWorld_t *dkLoadingWorld;
#define s_worldData (dkLoadingWorld->world)
