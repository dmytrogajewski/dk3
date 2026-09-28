/* SPDX-License-Identifier: GPL-2.0-or-later
 * Read-only material image discovery. The existing shader compiler remains the
 * authority for flags, stages, animation, sky and invalid-material handling. */
qboolean R_QueueShaderImages(dkImageBatch_t *batch, const char *name) {
    static const char *sides[6] = {"rt", "bk", "lf", "ft", "up", "dn"};
    char stripped[MAX_QPATH], path[MAX_QPATH], prefix[MAX_QPATH];
    char *text, *token;
    int depth = 0, i;
    COM_StripExtension(name, stripped, sizeof(stripped));
    text = FindShaderInShaderText(stripped);
    if (!text) return R_PrepareImage(batch, name);
    while (*(token = COM_ParseExt(&text, qtrue))) {
        if (!strcmp(token, "{")) { ++depth; continue; }
        if (!strcmp(token, "}")) { if (--depth <= 0) break; continue; }
        if (depth == 2 && (!Q_stricmp(token, "map") || !Q_stricmp(token, "clampmap"))) {
            token = COM_ParseExt(&text, qfalse);
            if (!R_PrepareImage(batch, token)) return qfalse;
        } else if (depth == 2 && !Q_stricmp(token, "animMap")) {
            COM_ParseExt(&text, qfalse); /* animation rate */
            i = 0;
            while (*(token = COM_ParseExt(&text, qfalse)))
                if (i++ < MAX_IMAGE_ANIMATIONS && !R_PrepareImage(batch, token)) return qfalse;
        } else if (depth == 1 && !Q_stricmp(token, "skyparms")) {
            int box;
            for (box = 0; box < 2; ++box) {
                token = COM_ParseExt(&text, qfalse);
                Q_strncpyz(prefix, token, sizeof(prefix));
                if (prefix[0] && strcmp(prefix, "-")) for (i = 0; i < 6; ++i) {
                    Com_sprintf(path, sizeof(path), "%s_%s.tga", prefix, sides[i]);
                    if (!R_PrepareImage(batch, path)) return qfalse;
                }
                if (!box) COM_ParseExt(&text, qfalse); /* cloud height */
            }
        }
    }
    return qtrue;
}
