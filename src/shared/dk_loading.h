/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Shared presentation for UI connection and cgame resource registration. */
#ifndef DK_LOADING_H
#define DK_LOADING_H
static qhandle_t DK_LoadingImage(const char *path) {
    fileHandle_t file;
    int length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (file) trap_FS_FCloseFile(file);
    return length >= 18 ? trap_R_RegisterShaderNoMip(path) : 0;
}

static void DK_LoadingScreen(const char *map, const char *authored, int progress, int width, int height) {
    char screen[32], path[MAX_QPATH], previous[MAX_QPATH];
    float scale = height / 480.0f, left, top;
    const float black[4] = {0, 0, 0, 1};
    qhandle_t image;
    int i, blocks = Com_Clamp(0, 36, progress * 36 / 100.0f);
    if (width <= 0 || height <= 0) return;
    if (width / 640.0f < scale) scale = width / 640.0f;
    left = (width - 640 * scale) / 2; top = (height - 480 * scale) / 2;
    Q_strncpyz(screen, "con", sizeof(screen));
    trap_Cvar_VariableStringBuffer("dk3_previousMap", previous, sizeof(previous));
    if (strlen(map) >= 5 && map[0] == 'e' && map[2] == 'm' && map[strlen(map) - 1] == 'a' &&
        (strlen(previous) != strlen(map) || Q_stricmpn(previous, map, strlen(map) - 1))) {
        if (authored && *authored) Q_strncpyz(screen, authored, sizeof(screen));
        else { Q_strncpyz(screen, map, sizeof(screen)); screen[strlen(screen) - 1] = 0; }
    }
    if (!DK_LoadingImage(va("pics/loadscreens/%s_0.tga", screen))) Q_strncpyz(screen, "gen", sizeof(screen));
    trap_R_SetColor(black);
    trap_R_DrawStretchPic(0, 0, width, height, 0, 0, 1, 1, trap_R_RegisterShaderNoMip("white"));
    trap_R_SetColor(NULL);
    for (i = 0; i < 6; ++i) {
        float tileWidth = i % 3 == 2 ? 128 : 256;
        Com_sprintf(path, sizeof(path), "pics/loadscreens/%s_%d.tga", screen, i);
        image = DK_LoadingImage(path);
        /* The supplied rows overlap by 32 pixels; the lower row begins at 224. */
        if (image) trap_R_DrawStretchPic(left + i % 3 * 256 * scale, top + i / 3 * 224 * scale,
            tileWidth * scale, 256 * scale, 0, 0, 1, 1, image);
    }
    image = DK_LoadingImage("pics/loadbar.tga");
    if (image) trap_R_DrawStretchPic(left + 383 * scale, top + 357 * scale, 256 * scale, 64 * scale, 0, 0, 1, 1, image);
    image = DK_LoadingImage("pics/loadblock.tga");
    if (image) for (i = 0; i < blocks; ++i)
        trap_R_DrawStretchPic(left + (451 + i * 5) * scale, top + 382 * scale, 8 * scale, 16 * scale, 0, 0, 1, 1, image);
}
#endif
