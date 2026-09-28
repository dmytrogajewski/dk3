/* SPDX-License-Identifier: GPL-2.0-or-later */
struct fsReadJob_s {
    pthread_t thread;
    qfile_gut stream;
    qboolean zip;
    byte *bytes;
    int length;
    int cancelled, result; /* accessed with acquire/release atomics */
    qboolean finished; /* owner thread only */
};

static void *FS_BackgroundRead(void *argument) {
    fsReadJob_t *job = argument;
    int offset = 0, result = -1;
    while (offset < job->length && !__atomic_load_n(&job->cancelled, __ATOMIC_ACQUIRE)) {
        int wanted = job->length - offset, got;
        if (wanted > 65536) wanted = 65536;
        got = job->zip ? unzReadCurrentFile(job->stream.z, job->bytes + offset, wanted) :
            (int)fread(job->bytes + offset, 1, wanted, job->stream.o);
        if (got <= 0) break;
        offset += got;
    }
    if (offset == job->length && !__atomic_load_n(&job->cancelled, __ATOMIC_ACQUIRE)) result = 1;
    __atomic_store_n(&job->result, result, __ATOMIC_RELEASE);
    return NULL;
}

static void FS_FinishBackgroundRead(fsReadJob_t *job) {
    int result;
    if (job->finished) return;
    pthread_join(job->thread, NULL);
    result = __atomic_load_n(&job->result, __ATOMIC_ACQUIRE);
    /* Bundled minizip frees Z_Malloc blocks when closing a stream. The zone
     * allocator belongs to the engine thread. Workers only read/inflate;
     * completion, CRC validation and cancellation cleanup stay with the owner. */
    if (job->zip) {
        if (unzCloseCurrentFile(job->stream.z) != UNZ_OK) result = -1;
        if (unzClose(job->stream.z) != UNZ_OK) result = -1;
    } else if (fclose(job->stream.o)) result = -1;
    job->finished = qtrue;
    __atomic_store_n(&job->result, result, __ATOMIC_RELEASE);
}

fsReadJob_t *FS_BeginBackgroundRead(const char *qpath, int maximum) {
    fileHandle_t handle = 0;
    long length;
    fsReadJob_t *job;
    if (maximum <= 0) return NULL;
    length = FS_FOpenFileRead(qpath, &handle, qtrue);
    if (!handle) return NULL;
    if (length < 0 || length > maximum) { FS_FCloseFile(handle); return NULL; }
    job = calloc(1, sizeof(*job));
    if (!job) { FS_FCloseFile(handle); return NULL; }
    job->bytes = calloc(1, (size_t)length + 1);
    if (!job->bytes) { free(job); FS_FCloseFile(handle); return NULL; }
    job->length = length;
    job->stream = fsh[handle].handleFiles.file;
    job->zip = fsh[handle].zipFile;
    /* The unique stream's ownership passes to the worker. It survives a
     * search-path restart and cannot race another reader's ZIP cursor. */
    if (pthread_create(&job->thread, NULL, FS_BackgroundRead, job)) {
        free(job->bytes); free(job); FS_FCloseFile(handle); return NULL;
    }
    Com_Memset(&fsh[handle], 0, sizeof(fsh[handle]));
    return job;
}

int FS_PollBackgroundRead(fsReadJob_t *job, const void **bytes, int *length) {
    int result;
    *bytes = NULL;
    *length = 0;
    if (!job) return -1;
    result = __atomic_load_n(&job->result, __ATOMIC_ACQUIRE);
    if (result) {
        FS_FinishBackgroundRead(job);
        result = __atomic_load_n(&job->result, __ATOMIC_ACQUIRE);
    }
    if (result == 1) { *bytes = job->bytes; *length = job->length; }
    return result;
}

void FS_EndBackgroundRead(fsReadJob_t *job) {
    if (!job) return;
    __atomic_store_n(&job->cancelled, 1, __ATOMIC_RELEASE);
    FS_FinishBackgroundRead(job);
    free(job->bytes);
    free(job);
}

