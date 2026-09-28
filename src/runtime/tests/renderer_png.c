/* SPDX-License-Identifier: GPL-2.0-or-later
 * Execute the renderer's actual PNG loader, including allocation cleanup. */
#ifdef NDEBUG
#error PNG contracts require assertions
#endif
#include <assert.h>
#include <pthread.h>
#include "../../../engine/ioquake3/code/renderercommon/tr_image_png.c"
static pthread_t owner;
static void checked_decode(const byte *bytes, int length, byte **pic, int *width, int *height, size_t maximum) {
    assert(!pthread_equal(owner, pthread_self()));
    R_DecodePNG(bytes, length, pic, width, height, maximum);
}
#define R_DecodePNG checked_decode
#include "../../../engine/ioquake3/code/renderercommon/tr_image_prepare.c"
#undef R_DecodePNG
#include "png_fixtures.h"
#include <sched.h>
#include <time.h>

refimport_t ri;
static const byte *source;
static int sourceSize, allocations;
static void *allocate(int size) {
    assert(pthread_equal(owner, pthread_self()));
    void *p = malloc(size);
    assert(p);
    ++allocations;
    return p;
}
static void release(void *p) { assert(pthread_equal(owner, pthread_self())); assert(p && allocations > 0); --allocations; free(p); }
static long read_file(const char *name, void **bytes) {
    assert(pthread_equal(owner, pthread_self()));
    *bytes = allocate(sourceSize);
    memcpy(*bytes, source, sourceSize);
    return sourceSize;
}
static void QDECL quiet(int level, const char *format, ...) {}
void QDECL Com_Error(int code, const char *format, ...) { abort(); }
struct fsReadJob_s { byte *bytes; int length; };
static int readers, reads, permit_read;
static struct fsReadJob_s *begin_read(const char *name, int maximum) {
    struct fsReadJob_s *job = allocate(sizeof(*job));
    job->bytes = allocate(sourceSize);
    memcpy(job->bytes, source, sourceSize);
    job->length = sourceSize;
    ++readers; ++reads;
    return job;
}
static int poll_read(struct fsReadJob_s *job, const void **bytes, int *length) {
    assert(pthread_equal(owner, pthread_self()));
    *bytes = permit_read ? job->bytes : NULL;
    *length = permit_read ? job->length : 0;
    return permit_read;
}
static void end_read(struct fsReadJob_s *job) {
    release(job->bytes); release(job); --readers;
}
static int await_batch(dkImageBatch_t *batch) {
    struct timespec start, now;
    int result;
    clock_gettime(CLOCK_MONOTONIC, &start);
    do {
        result = R_PollImageBatch(batch);
        clock_gettime(CLOCK_MONOTONIC, &now);
        assert(now.tv_sec - start.tv_sec < 5);
        if (!result) sched_yield();
    } while (!result);
    return result;
}
static void background(void) {
    dkImageBatch_t *a = R_CreateImageBatch(1), *b = R_CreateImageBatch(1);
    byte *pixels = NULL;
    int width, height;
    assert(a && b && R_QueuePNG(a, "cancel.png") && R_QueuePNG(b, "retained.png"));
    assert(R_QueuePNG(b, "retained.png") && !R_QueuePNG(b, "overflow.png"));
    source = rgba9_interlace1_png;
    sourceSize = sizeof(rgba9_interlace1_png);
    assert(!R_PollImageBatch(a) && !R_PollImageBatch(b) && readers == 2);
    assert(!R_PollImageBatch(a) && !R_PollImageBatch(b));
    R_FreeImageBatch(a); /* Cancel one owner while the other is still reading. */
    assert(readers == 1);
    permit_read = 1;
    assert(!R_PollImageBatch(b)); /* Real decode thread started; never inline. */
    assert(await_batch(b) == 1 && readers == 0);
    R_SelectImageBatch(b);
    sourceSize = 1; /* A sync re-read could not decode this; prepared data must win. */
    R_LoadPNG("retained.png", &pixels, &width, &height);
    assert(pixels && width == 9 && height == 9 && !memcmp(pixels, rgba9_interlace1_rgba, 9 * 9 * 4));
    release(pixels);
    R_FreeImageBatch(b);
    assert(!selectedBatch && !allocations && reads == 2);

    /* Cancel after dispatch: input/output cannot be freed before the worker. */
    a = R_CreateImageBatch(1);
    sourceSize = sizeof(rgba9_interlace1_png);
    assert(R_QueuePNG(a, "decoding.png"));
    assert(!R_PollImageBatch(a) && !R_PollImageBatch(a));
    R_FreeImageBatch(a);
    assert(!allocations && !readers);

    a = R_CreateImageBatch(1); b = R_CreateImageBatch(1);
    source = rgb_png; sourceSize = sizeof(rgb_png);
    assert(R_QueuePNG(a, "a.png") && !R_PollImageBatch(a));
    source = palette_png; sourceSize = sizeof(palette_png);
    assert(R_QueuePNG(b, "b.png") && !R_PollImageBatch(b));
    assert(!R_PollImageBatch(a) && !R_PollImageBatch(b));
    assert(await_batch(a) == 1 && await_batch(b) == 1);
    R_SelectImageBatch(a);
    R_LoadPNG("a.png", &pixels, &width, &height);
    assert(width == 3 && height == 2 && !memcmp(pixels, rgb_rgba, sizeof(rgb_rgba)));
    release(pixels);
    R_FreeImageBatch(a);
    R_SelectImageBatch(b);
    R_LoadPNG("b.png", &pixels, &width, &height);
    assert(width == 3 && height == 1 && !memcmp(pixels, palette_rgba, sizeof(palette_rgba)));
    release(pixels);
    R_FreeImageBatch(b);
    assert(!allocations && !readers);

    a = R_CreateImageBatch(1);
    a->bytes = DK3_MATERIAL_PIXEL_BUDGET - 1;
    assert(R_QueuePNG(a, "budget.png") && await_batch(a) == -1);
    R_FreeImageBatch(a);
    assert(!allocations && !readers);

    a = R_CreateImageBatch(1);
    sourceSize = 20;
    assert(R_QueuePNG(a, "truncated.png"));
    assert(await_batch(a) == -1);
    R_FreeImageBatch(a);
    assert(!allocations && !readers);
}
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
    owner = pthread_self();
    ri.Malloc = allocate;
    ri.Free = release;
    ri.FS_ReadFile = read_file;
    ri.FS_FreeFile = release;
    ri.Printf = quiet;
    ri.BeginBackgroundRead = begin_read;
    ri.PollBackgroundRead = poll_read;
    ri.EndBackgroundRead = end_read;
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
    background();
    puts("PNG loader: pixels, malformed streams, actual background decoding, interleaved owners, cancellation and budget failure pass");
    return 0;
}
