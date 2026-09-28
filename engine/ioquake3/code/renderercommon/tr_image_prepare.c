/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "tr_common.h"
#include <pthread.h>
#include <time.h>

/* Each admitting world owns one material batch. Four world readers bound the
 * concurrent workers. Completed pixels live only until that material compiles. */
#define DK3_MATERIAL_PIXEL_BUDGET (128u * 1024u * 1024u)
typedef struct {
    char name[MAX_QPATH];
    byte *pixels;
    int width, height;
} dkPreparedImage_t;
struct dkImageBatch_s {
    int count, capacity, next, done, decodeMilliseconds;
    size_t bytes;
    struct fsReadJob_s *read;
    const void *input;
    int length;
    pthread_t thread;
    qboolean decoding, failed;
    dkPreparedImage_t images[];
};
static dkImageBatch_t *selectedBatch;

dkImageBatch_t *R_CreateImageBatch(int capacity) {
    dkImageBatch_t *batch;
    if (capacity <= 0 || capacity > 1024) return NULL;
    batch = calloc(1, sizeof(*batch) + capacity * sizeof(batch->images[0]));
    if (batch) batch->capacity = capacity;
    return batch;
}
qboolean R_QueuePNG(dkImageBatch_t *batch, const char *name) {
    int i;
    if (!batch || !name || !name[0] || strlen(name) >= MAX_QPATH) return qfalse;
    for (i = 0; i < batch->count; ++i)
        if (!strcmp(batch->images[i].name, name)) return qtrue;
    if (batch->count == batch->capacity || batch->read || batch->decoding) return qfalse;
    Q_strncpyz(batch->images[batch->count++].name, name, MAX_QPATH);
    return qtrue;
}
static void *R_DecodePreparedPNG(void *argument) {
    dkImageBatch_t *batch = argument;
    dkPreparedImage_t *image = &batch->images[batch->next];
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    R_DecodePNG(batch->input, batch->length, &image->pixels, &image->width, &image->height,
                DK3_MATERIAL_PIXEL_BUDGET - batch->bytes);
    clock_gettime(CLOCK_MONOTONIC, &end);
    batch->decodeMilliseconds = (int)((end.tv_sec - start.tv_sec) * 1000 + (end.tv_nsec - start.tv_nsec) / 1000000);
    __atomic_store_n(&batch->done, 1, __ATOMIC_RELEASE);
    return NULL;
}
int R_PollImageBatch(dkImageBatch_t *batch) {
    int result;
    if (!batch || batch->failed) return -1;
    if (batch->next == batch->count) return 1;
    if (batch->decoding) {
        dkPreparedImage_t *image;
        if (!__atomic_load_n(&batch->done, __ATOMIC_ACQUIRE)) return 0;
        pthread_join(batch->thread, NULL);
        batch->decoding = qfalse;
        ri.EndBackgroundRead(batch->read);
        batch->read = NULL;
        batch->input = NULL;
        image = &batch->images[batch->next];
        if (!image->pixels) goto failed;
        ri.Printf(PRINT_DEVELOPER, "dk3 prepared PNG: name=%s size=%dx%d worker_decode_ms=%d\n",
                  image->name, image->width, image->height, batch->decodeMilliseconds);
        batch->bytes += (size_t)image->width * image->height * 4;
        ++batch->next;
        return batch->next == batch->count ? 1 : 0;
    }
    if (!batch->read) {
        batch->read = ri.BeginBackgroundRead(batch->images[batch->next].name, 128 * 1024 * 1024);
        if (!batch->read) goto failed;
        return 0;
    }
    result = ri.PollBackgroundRead(batch->read, &batch->input, &batch->length);
    if (result < 0) goto failed;
    if (!result) return 0;
    __atomic_store_n(&batch->done, 0, __ATOMIC_RELAXED);
    if (pthread_create(&batch->thread, NULL, R_DecodePreparedPNG, batch)) goto failed;
    batch->decoding = qtrue;
    return 0;
failed:
    batch->failed = qtrue;
    ri.Printf(PRINT_WARNING, "Resident PNG preparation failed: %s (material pixel budget %u bytes)\n",
              batch->images[batch->next].name, DK3_MATERIAL_PIXEL_BUDGET);
    return -1;
}
void R_SelectImageBatch(dkImageBatch_t *batch) { selectedBatch = batch; }
qboolean R_TakePreparedPNG(const char *name, byte **pic, int *width, int *height) {
    int i;
    if (!selectedBatch || selectedBatch->next != selectedBatch->count || selectedBatch->failed) return qfalse;
    for (i = 0; i < selectedBatch->count; ++i) {
        dkPreparedImage_t *image = &selectedBatch->images[i];
        if (!strcmp(image->name, name) && image->pixels) {
            size_t size = (size_t)image->width * image->height * 4;
            *pic = ri.Malloc(size);
            memcpy(*pic, image->pixels, size);
            if (width) *width = image->width;
            if (height) *height = image->height;
            /* Keep this batch's pixels for aliases resolving to the same PNG. */
            return qtrue;
        }
    }
    return qfalse;
}
void R_FreeImageBatch(dkImageBatch_t *batch) {
    int i;
    if (!batch) return;
    if (selectedBatch == batch) selectedBatch = NULL;
    /* On cancellation, join before releasing immutable input or worker output. */
    if (batch->decoding) pthread_join(batch->thread, NULL);
    if (batch->read) ri.EndBackgroundRead(batch->read);
    for (i = 0; i < batch->count; ++i) free(batch->images[i].pixels);
    free(batch);
}
