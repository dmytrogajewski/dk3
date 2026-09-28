/* SPDX-License-Identifier: GPL-2.0-or-later
 * Uses each backend's existing format preference. This only prepares CPU PNG
 * pixels; material flags, image creation and GPU uploads still use R_LoadImage. */
qboolean R_PrepareImage(dkImageBatch_t *batch, const char *name) {
    char local[MAX_QPATH], candidate[MAX_QPATH];
    const char *ext;
    image_t *image;
    int i, original = -1;
    if (!name || !name[0] || name[0] == '$' || name[0] == '*') return qtrue;
    for (image = hashTable[generateHashValue(name)]; image; image = image->next)
        if (!strcmp(image->imgName, name)) return qtrue;
    Q_strncpyz(local, name, sizeof(local));
    ext = COM_GetExtension(name);
#ifdef DK3_IMAGE_GL2
    if (r_ext_compressed_textures->integer) {
        COM_StripExtension(name, candidate, sizeof(candidate));
        Q_strcat(candidate, sizeof(candidate), ".dds");
        if (ri.FS_ReadFile(candidate, NULL) >= 0) return qtrue;
    }
#endif
    if (*ext) {
        for (i = 0; i < numImageLoaders; ++i) {
            if (Q_stricmp(ext, imageLoaders[i].ext)) continue;
            if (ri.FS_ReadFile(name, NULL) >= 0)
                return Q_stricmp(ext, "png") ? qtrue : R_QueuePNG(batch, name);
            original = i;
            COM_StripExtension(name, local, sizeof(local));
            break;
        }
#ifdef DK3_IMAGE_GL2
        /* GL2 strips an explicit extension even without a matching loader. */
        COM_StripExtension(name, local, sizeof(local));
#endif
    }
    for (i = 0; i < numImageLoaders; ++i) {
        if (i == original) continue;
        Com_sprintf(candidate, sizeof(candidate), "%s.%s", local, imageLoaders[i].ext);
        if (ri.FS_ReadFile(candidate, NULL) >= 0)
            return Q_stricmp(imageLoaders[i].ext, "png") ? qtrue : R_QueuePNG(batch, candidate);
    }
    return qtrue;
}
