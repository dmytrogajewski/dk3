/* SPDX-License-Identifier: GPL-2.0-or-later
 * Execute the renderer's actual PNG loader, including allocation cleanup. */
#ifdef NDEBUG
#error PNG contracts require assertions
#endif
#include <assert.h>
#include "../../../engine/ioquake3/code/renderercommon/tr_image_png.c"
#include "png_fixtures.h"

refimport_t ri;
static const byte *source;
static int sourceSize, allocations;
static void *allocate(int size) {
    void *p = malloc(size);
    assert(p);
    ++allocations;
    return p;
}
static void release(void *p) { assert(p && allocations > 0); --allocations; free(p); }
static long read_file(const char *name, void **bytes) {
    *bytes = allocate(sourceSize);
    memcpy(*bytes, source, sourceSize);
    return sourceSize;
}
static void QDECL quiet(int level, const char *format, ...) {}
static void check(const byte *bytes, int length, const byte *expected, int w, int h) {
    byte *pixels = NULL;
    int width = -1, height = -1;
    source = bytes;
    sourceSize = length;
    R_LoadPNG("synthetic.png", &pixels, &width, &height);
    if (expected) {
        assert(pixels && width == w && height == h);
        assert(!memcmp(pixels, expected, w * h * 4));
        release(pixels);
    } else assert(!pixels && !width && !height);
    assert(!allocations);
}
int main(void) {
    int i, offset;
    byte corrupt[2048];
    ri.Malloc = allocate;
    ri.Free = release;
    ri.FS_ReadFile = read_file;
    ri.FS_FreeFile = release;
    ri.Printf = quiet;
    for (i = 0; i < ARRAY_LEN(fixtures); ++i) {
        check(fixtures[i].png, fixtures[i].size, fixtures[i].rgba, fixtures[i].width, fixtures[i].height);
        for (offset = 1; offset < fixtures[i].size - 12; ++offset)
            check(fixtures[i].png, offset, NULL, 0, 0);
    }
    /* Last nonempty IDAT ends immediately before IEND. Damage Adler-32. */
    memcpy(corrupt, rgb_png, sizeof(rgb_png));
    corrupt[sizeof(rgb_png) - 12 - 5] ^= 1;
    check(corrupt, sizeof(rgb_png), NULL, 0, 0);
    /* A well-formed deflate stream with an incompatible IHDR is rejected. */
    memcpy(corrupt, rgb_png, sizeof(rgb_png));
    corrupt[19] = 4;
    check(corrupt, sizeof(rgb_png), NULL, 0, 0);
    memcpy(corrupt, rgb_png, sizeof(rgb_png));
    corrupt[19] = 2;
    check(corrupt, sizeof(rgb_png), NULL, 0, 0);
    /* Oversized palette must not overwrite the fixed 256-entry palette. */
    memcpy(corrupt, palette_png, sizeof(palette_png));
    corrupt[35] = 3;
    corrupt[36] = 3;
    check(corrupt, sizeof(palette_png), NULL, 0, 0);
    puts("PNG loader: formats, filters, Adam7, empty IDAT, malformed streams and cleanup pass");
    return 0;
}
