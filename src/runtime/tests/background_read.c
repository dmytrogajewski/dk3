/* SPDX-License-Identifier: GPL-2.0-or-later
 * Actual async reader and bundled minizip; allocation ownership is asserted. */
#include "q_shared.h"
#include "qcommon.h"
#include "unzip.h"
#include <pthread.h>
#include <unistd.h>
#include <sched.h>
#include "background_zip_fixture.h"
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "background read line %d: %s\n", __LINE__, #x); abort(); } } while (0)
static pthread_t owner;
static int allocations;
#undef Z_Malloc
void *Z_Malloc(int size) { void *p; CHECK(pthread_equal(owner, pthread_self())); p = calloc(1, size); CHECK(p); ++allocations; return p; }
void *Z_MallocDebug(int size, char *label, char *file, int line) { (void)label; (void)file; (void)line; return Z_Malloc(size); }
void Z_Free(void *p) { CHECK(pthread_equal(owner, pthread_self())); if (p) { --allocations; free(p); } }
typedef union { FILE *o; unzFile z; } qfile_gut;
static struct { struct { qfile_gut file; } handleFiles; qboolean zipFile; } fsh[2];
long FS_FOpenFileRead(const char *name, fileHandle_t *handle, qboolean unique) {
    unz_file_info info;
    CHECK(unique && !fsh[1].handleFiles.file.z);
    *handle = 0;
    fsh[1].handleFiles.file.z = unzOpen(name);
    if (!fsh[1].handleFiles.file.z) return -1;
    CHECK(unzGoToFirstFile(fsh[1].handleFiles.file.z) == UNZ_OK);
    CHECK(unzGetCurrentFileInfo(fsh[1].handleFiles.file.z, &info, NULL, 0, NULL, 0, NULL, 0) == UNZ_OK);
    CHECK(unzOpenCurrentFile(fsh[1].handleFiles.file.z) == UNZ_OK);
    fsh[1].zipFile = qtrue; *handle = 1;
    return info.uncompressed_size;
}
void FS_FCloseFile(fileHandle_t handle) { CHECK(handle == 1); unzClose(fsh[1].handleFiles.file.z); memset(&fsh[1], 0, sizeof(fsh[1])); }
#ifndef BACKGROUND_IMPLEMENTATION
#define BACKGROUND_IMPLEMENTATION "../../../engine/ioquake3/code/qcommon/fs_background.inc"
#endif
#include BACKGROUND_IMPLEMENTATION
static void fixture(const char *path, qboolean corrupt) {
    unsigned char bytes[sizeof(zip_bytes)]; FILE *f;
    memcpy(bytes, zip_bytes, sizeof(bytes));
    if (corrupt) { bytes[14] ^= 1; bytes[FIXTURE_CENTRAL + 16] ^= 1; }
    f = fopen(path, "wb"); CHECK(f); CHECK(fwrite(bytes, 1, sizeof(bytes), f) == sizeof(bytes)); CHECK(!fclose(f));
}
static int poll(fsReadJob_t *job) {
    const void *bytes; int size, status, spins;
    for (spins = 0; spins < 1000000; ++spins) {
        status = FS_PollBackgroundRead(job, &bytes, &size);
        if (status) {
            if (status > 0) { CHECK(size == FIXTURE_LENGTH); CHECK(!memcmp(bytes, "Independent background ZIP reader fixture.\n", 42)); }
            else CHECK(!bytes && !size);
            return status;
        }
        sched_yield();
    }
    CHECK(0); return 0;
}
int main(void) {
    char path[] = "/tmp/dk3-read-contract-XXXXXX";
    fsReadJob_t *jobs[4]; int fd, i;
    owner = pthread_self(); fd = mkstemp(path); CHECK(fd >= 0); close(fd);
    fixture(path, qfalse);
    for (i = 0; i < 4; ++i) { jobs[i] = FS_BeginBackgroundRead(path, FIXTURE_LENGTH); CHECK(jobs[i]); }
    for (i = 3; i >= 0; --i) { CHECK(poll(jobs[i]) == 1); CHECK(poll(jobs[i]) == 1); FS_EndBackgroundRead(jobs[i]); }
    CHECK(!allocations);
    for (i = 0; i < 32; ++i) { jobs[0] = FS_BeginBackgroundRead(path, FIXTURE_LENGTH); CHECK(jobs[0]); FS_EndBackgroundRead(jobs[0]); }
    CHECK(!allocations);
    CHECK(!FS_BeginBackgroundRead(path, FIXTURE_LENGTH - 1)); CHECK(!allocations);
    fixture(path, qtrue);
    jobs[0] = FS_BeginBackgroundRead(path, FIXTURE_LENGTH); CHECK(jobs[0]); CHECK(poll(jobs[0]) == -1); FS_EndBackgroundRead(jobs[0]);
    CHECK(!allocations); unlink(path);
    puts("background ZIP reads: owner-thread cleanup, concurrent completion, repeat polls, cancellation, size rejection and CRC failure passed");
    return 0;
}
