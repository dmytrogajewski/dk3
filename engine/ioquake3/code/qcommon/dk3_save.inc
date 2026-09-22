/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included by files.c to keep the engine's home-state path private. */
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#define DK3_SAVE_MAX (256 * 1024 * 1024)

static qboolean DK3_SaveName(const char *slot) {
    const char *p;
    if (!slot || !*slot || strlen(slot) > 48) return qfalse;
    for (p = slot; *p; ++p) if (!((*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9') || *p == '_' || *p == '-'))
        return qfalse;
    return qtrue;
}

static int DK3_SaveDirectory(void) {
    char path[MAX_OSPATH];
    Q_strncpyz(path, FS_BuildOSPath(fs_homestatepath->string, fs_gamedir, "saves/"), sizeof(path));
    if (FS_CreatePath(path)) return -1;
    return open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
}

int FS_DK3SaveWrite(int version, const char *slot, const void *data, int length) {
    char current[64], temporary[80], previous[80], backup[96];
    int directory, output = -1, savedError = 0, result = -1, offset = 0;
    if (version != 1 || !DK3_SaveName(slot) || length < 1 || length > DK3_SAVE_MAX || !data) return -1;
    directory = DK3_SaveDirectory();
    if (directory < 0) return -1;
    Com_sprintf(current, sizeof(current), "%s.sav", slot);
    Com_sprintf(temporary, sizeof(temporary), "%s.pending", current);
    Com_sprintf(previous, sizeof(previous), "%s.previous", current);
    Com_sprintf(backup, sizeof(backup), "%s.pending", previous);
    output = openat(directory, temporary, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (output < 0) goto done;
    while (offset < length) {
        ssize_t written = write(output, (const byte *)data + offset, length - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) goto done;
        offset += written;
    }
    if (fsync(output)) goto done;
    if (close(output)) { output = -1; goto done; }
    output = -1;
    /* Retain the old inode before replacement. A failed write leaves the current
       save intact; a power interruption always leaves current or previous readable. */
    if (unlinkat(directory, backup, 0) && errno != ENOENT) goto done;
    if (!linkat(directory, current, directory, backup, 0)) {
        if (renameat(directory, backup, directory, previous)) goto done;
        if (fsync(directory)) goto done;
    } else if (errno != ENOENT) goto done;
    if (renameat(directory, temporary, directory, current)) goto done;
    if (fsync(directory)) goto done;
    result = length;
done:
    savedError = errno;
    if (output >= 0) close(output);
    if (result < 0) {
        unlinkat(directory, temporary, 0);
        Com_Printf("dk3 save %s: write failed: %s\n", slot, strerror(savedError));
    }
    close(directory);
    return result;
}

int FS_DK3SaveRead(int version, const char *slot, void *data, int capacity, qboolean previous) {
    char name[80];
    struct stat status;
    int directory, input, offset = 0, result = -1;
    if (version != 1 || !DK3_SaveName(slot) || capacity < 1 || capacity > DK3_SAVE_MAX || !data) return -1;
    directory = DK3_SaveDirectory();
    if (directory < 0) return -1;
    Com_sprintf(name, sizeof(name), "%s.sav%s", slot, previous ? ".previous" : "");
    input = openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    close(directory);
    if (input < 0) return -1;
    if (fstat(input, &status) || !S_ISREG(status.st_mode) || status.st_size < 1 || status.st_size > capacity) goto done;
    while (offset < status.st_size) {
        ssize_t readBytes = read(input, (byte *)data + offset, status.st_size - offset);
        if (readBytes < 0 && errno == EINTR) continue;
        if (readBytes <= 0) goto done;
        offset += readBytes;
    }
    result = offset;
done:
    close(input);
    return result;
}
