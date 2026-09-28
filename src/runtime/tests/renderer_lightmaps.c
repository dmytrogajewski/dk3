/* SPDX-License-Identifier: GPL-2.0-or-later
 * Actual renderer lightmap admission with a bounded fake GPU/clock. No engine
 * or game assets run here. Interleaved owners must resume their own uploads.
 */
#ifdef NDEBUG
#error Lightmap contracts require assertions
#endif
#include <assert.h>
#include <sys/mman.h>
#include <unistd.h>
#ifdef DK3_TEST_GL2
#include "../../../engine/ioquake3/code/renderergl2/tr_bsp.c"
#else
#include "../../../engine/ioquake3/code/renderergl1/tr_bsp.c"
#endif

trGlobals_t tr;
refimport_t ri;
glconfig_t glConfig;
int qglesMajorVersion, qglesMinorVersion;
static cvar_t zero, merge;
cvar_t *r_mapOverBrightBits = &zero, *r_lightmap = &zero, *r_vertexLight = &zero;
#ifdef DK3_TEST_GL2
cvar_t *r_mergeLightmaps = &merge, *r_hdr = &zero;
#endif
static int clock_ms, uploads, creates, expected_byte;
static image_t images[64];
static void *allocations[64];
static int allocated;

static void *allocate(int size, ha_pref pref) {
    void *result = calloc(1, size ? size : 1);
    assert(result && allocated < ARRAY_LEN(allocations));
    allocations[allocated++] = result;
    return result;
}
static void *scratch(int size) { return malloc(size); }
#ifdef HUNK_DEBUG
static void *allocate_debug(int size, ha_pref pref, char *label, char *file, int line) { return allocate(size, pref); }
#endif
static int milliseconds(void) { return clock_ms; }
static void QDECL fail(int level, const char *format, ...) Q_NO_RETURN;
static void QDECL fail(int level, const char *format, ...) { abort(); }
static void QDECL quiet(int level, const char *format, ...) {}
void QDECL Com_Printf(const char *format, ...) {}
void R_IssuePendingRenderCommands(void) {}

static void pixels(byte *pic, int width, int height) {
    int i;
    assert(pic && width == 128 && height == 128);
    for (i = 0; i < width * height; ++i) {
        assert(pic[i * 4] == expected_byte && pic[i * 4 + 1] == expected_byte);
        assert(pic[i * 4 + 2] == expected_byte && pic[i * 4 + 3] == 255);
    }
    ++uploads;
}
image_t *R_CreateImage(const char *name, byte *pic, int width, int height,
                     imgType_t type, imgFlags_t flags, int internalFormat) {
    assert(creates < ARRAY_LEN(images));
    if (pic) pixels(pic, width, height);
    clock_ms += 5; /* One real upload is indivisible; the next must yield. */
    return &images[creates++];
}
#ifdef DK3_TEST_GL2
void R_UpdateSubImage(image_t *image, byte *pic, int x, int y, int width, int height, GLenum format) {
    assert(image >= images && image < images + creates);
    pixels(pic, width, height);
    clock_ms += 5;
}
#endif

static qboolean advance(dkRenderWorld_t *owner, byte *bytes, int count, int color, qboolean deluxe) {
    lump_t lump = { 0, count * 128 * 128 * 3 };
    qboolean done;
    R_ApplyWorld(owner);
    dkLoadingWorld = owner;
    fileBase = bytes;
    expected_byte = color;
#ifdef DK3_TEST_GL2
    {
        dsurface_t surface;
        lump_t surfaces = { lump.filelen, sizeof(surface) };
        memset(&surface, 0, sizeof(surface));
        surface.lightmapNum = deluxe ? 0 : 1;
        memcpy(bytes + lump.filelen, &surface, sizeof(surface));
        done = R_LoadLightmaps(&lump, &surfaces);
    }
#else
    done = R_LoadLightmaps(&lump);
#endif
    R_SaveWorld(owner);
    return done;
}

int main(void) {
    byte first[3 * 128 * 128 * 3 + sizeof(dsurface_t)];
    byte second[2 * 128 * 128 * 3 + sizeof(dsurface_t)];
    dkRenderWorld_t *a = &dkRenderWorlds[0], *b = &dkRenderWorlds[1];
    int calls = 0, i;
    qboolean done_a = qfalse, done_b = qfalse;
#ifdef HUNK_DEBUG
    ri.Hunk_AllocDebug = allocate_debug;
#else
    ri.Hunk_Alloc = allocate;
#endif
    ri.Malloc = scratch; ri.Free = free;
    ri.Milliseconds = milliseconds; ri.Error = fail; ri.Printf = quiet;
    glConfig.maxTextureSize = 2048;
    a->generation = b->generation = 1;
    memset(first, 11, sizeof(first)); memset(second, 37, sizeof(second));
    while (!done_a || !done_b) {
        assert(++calls < 12);
        if (!done_a) done_a = advance(a, first, 3, 11, qfalse);
        if (!done_b) done_b = advance(b, second, 2, 37, qfalse);
    }
    assert(calls == 3 && uploads == 5 && creates == 5);
    assert(a->lightmapNext == 3 && b->lightmapNext == 2);
    assert(a->lightmaps != b->lightmaps && a->lightmaps[0] != b->lightmaps[0]);
#ifdef DK3_TEST_GL2
    {
        byte deluxe[4 * 128 * 128 * 3 + sizeof(dsurface_t)];
        dkRenderWorld_t *c = &dkRenderWorlds[2];
        c->generation = 1; merge.integer = 1; calls = 0;
        memset(deluxe, 23, sizeof(deluxe));
        do { assert(++calls < 12); } while (!advance(c, deluxe, 4, 23, qtrue));
        assert(calls == 3 && c->lightmapPages == 1 && c->lightmapNext == 2);
        assert(creates == 7 && uploads == 9); /* Paired RGB + direction tiles. */
        assert(c->lightmaps[0] != c->deluxemaps[0]);
    }
#else
    {
        /* A guard page catches the historical extra-lightmap read and the
         * final RGB pixel's nonexistent alpha byte. */
        size_t size = 128 * 128 * 3, page = (size_t)sysconf(_SC_PAGESIZE);
        byte *guarded = mmap(NULL, size + page, PROT_READ | PROT_WRITE,
                             MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        dkRenderWorld_t *c = &dkRenderWorlds[2];
        assert(guarded != MAP_FAILED && size % page == 0);
        assert(mprotect(guarded + size, page, PROT_NONE) == 0);
        memset(guarded, 19, size); c->generation = 1;
        assert(!advance(c, guarded, 1, 19, qfalse));
        assert(advance(c, guarded, 1, 19, qfalse));
        assert(c->lightmapNext == 2 && creates == 7 && uploads == 7);
        assert(munmap(guarded, size + page) == 0);
    }
#endif
    for (i = 0; i < allocated; ++i) free(allocations[i]);
    puts("renderer lightmap admission contracts passed");
    return 0;
}
