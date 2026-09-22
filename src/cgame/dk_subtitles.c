/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "cg_local.h"
#include "../shared/dk_font.h"

static char subtitle[4096];
static int subtitleUntil;
static dkFont_t font;
static vmCvar_t enabled, size;
static qboolean registered;

static void Settings(void) {
    if (!registered) {
        trap_Cvar_Register(&enabled, "cg_subtitles", "1", CVAR_ARCHIVE);
        trap_Cvar_Register(&size, "cg_subtitleScale", "1", CVAR_ARCHIVE);
        registered = qtrue;
    }
    trap_Cvar_Update(&enabled); trap_Cvar_Update(&size);
}

void DK_SubtitleForSound(const char *sound) {
    char path[MAX_QPATH], name[MAX_QPATH], text[4096];
    const char *base = strrchr(sound, '/');
    fileHandle_t file;
    int length, i, used = 0;
    Settings();
    if (!enabled.integer) return;
    Q_strncpyz(name, base ? base + 1 : sound, sizeof(name)); length = strlen(name);
    if (length > 4 && !Q_stricmp(name + length - 4, ".ogg")) name[length - 4] = 0;
    if (strlen(name) + 15 >= sizeof(path)) return;
    Com_sprintf(path, sizeof(path), "subtitles/%s.txt", name);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length <= 0 || length >= sizeof(text)) { if (file) trap_FS_FCloseFile(file); return; }
    trap_FS_Read(text, length, file); trap_FS_FCloseFile(file); text[length] = 0;
    for (i = text[0] == '#'; i < length && used < sizeof(subtitle) - 1; ++i) {
        unsigned char c = text[i];
        if (c == '\r' || c == '\n' || c == '\t') c = ' ';
        if (c < 32 || (c == ' ' && (!used || subtitle[used - 1] == ' '))) continue;
        subtitle[used++] = c;
    }
    while (used && subtitle[used - 1] == ' ') --used;
    subtitle[used] = 0;
    subtitleUntil = cg.time + (int)Com_Clamp(2000, 14000, used * 65);
}

void DK_DrawSubtitles(void) {
    char wrapped[4200];
    float scale, glyphScale, width;
    int lines;
    const float color[4] = {1, 1, 0.88f, 1}, background[4] = {0, 0, 0, 0.8f};
    Settings();
    if (cg.time >= subtitleUntil || !*subtitle || !enabled.integer) return;
    if (!font.shader) DK_LoadFont(&font);
    scale = cgs.glconfig.vidHeight / 720.0f * Com_Clamp(0.7f, 2, size.value);
    glyphScale = scale * 16.0f / font.height;
    width = cgs.glconfig.vidWidth * 0.8f;
    lines = DK_WrapText(&font, subtitle, scale, width, wrapped, sizeof(wrapped));
    {
        float height = lines * (font.height + 3) * glyphScale;
        float x = cgs.glconfig.vidWidth * 0.1f, y = cgs.glconfig.vidHeight * 0.84f - height;
        trap_R_SetColor(background);
        trap_R_DrawStretchPic(x - 10 * scale, y - 6 * scale, width + 20 * scale, height + 12 * scale, 0, 0, 1, 1, trap_R_RegisterShader("white"));
        trap_R_SetColor(NULL);
        DK_Text(&font, x, y, scale, wrapped, color);
    }
}
