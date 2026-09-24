/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "cg_local.h"
#include "dk_effects.h"
#include "../shared/dk_font.h"

static dkFont_t font, statFont, numbers, redNumbers;
static vmCvar_t hudScale;

void DK_DrawCenterMessage(void) {
    char wrapped[2048], *line, *next;
    float scale, lineHeight, y, width;
    float *color;
    int lines;
    if (!cg.centerPrintTime || !*cg.centerPrint) return;
    color = CG_FadeColor(cg.centerPrintTime, 1000 * cg_centertime.value);
    if (!color) return;
    if (!font.shader) DK_LoadFont(&font);
    scale = cgs.glconfig.vidHeight / 720.0f * Com_Clamp(0.75f, 1.5f, hudScale.value);
    width = cgs.glconfig.vidWidth * 0.85f;
    lines = DK_WrapText(&font, cg.centerPrint, scale, width, wrapped, sizeof(wrapped));
    lineHeight = (font.height + 3) * scale * 16.0f / font.height;
    y = cg.centerPrintY * cgs.glconfig.vidHeight / SCREEN_HEIGHT - lines * lineHeight * 0.5f;
    for (line = wrapped; line; line = next) {
        next = strchr(line, '\n');
        if (next) *next++ = 0;
        DK_Text(&font, (cgs.glconfig.vidWidth - DK_TextWidth(&font, line, scale)) * 0.5f, y, scale, line, color);
        y += lineHeight;
    }
}

static void HudPicture(float x, float y, float w, float h, const char *name, float alpha) {
    float color[4] = {1, 1, 1, alpha};
    trap_R_SetColor(color);
    trap_R_DrawStretchPic(x, y, w, h, 0, 0, 1, 1,
        trap_R_RegisterShaderNoMip(va("pics/statusbar/%s.tga", name)));
    trap_R_SetColor(NULL);
}

static void StatusBar(const playerState_t *ps, float scale) {
    static const int plates[] = {-158, 98, 226};
    static const char *const art[] = {"bottom_1", "bottom_3", "bottom_4"};
    static const char *const icons[] = {"armoricon", "healthicon", "ammoicon", "explevicon"};
    static const char *const labels[] = {"ARMOR", "HEALTH", "AMMO", "LEVEL"};
    static const int iconX[] = {-144, -54, 98, 196}, iconY[] = {-64, -67, -66, -64};
    static const int labelX[] = {-122, -40, 126, 212}, valueX[] = {-162, -71, 82, 172};
    const float white[4] = {1, 1, 1, 1};
    int weapon = ps->weapon, i, values[4], face;
    float center = cgs.glconfig.vidWidth * 0.5f, base = cgs.glconfig.vidHeight;
    char text[32];
    if (!statFont.shader) {
        DK_LoadNamedFont(&statFont, "statbar_font");
        DK_LoadNamedFont(&numbers, "mainnums"); DK_LoadNamedFont(&redNumbers, "mainnumsred");
    }
    for (i = 0; i < 3; ++i)
        HudPicture(center + (plates[i] - 64) * scale, base - 128 * scale, 128 * scale, 128 * scale, art[i], 0.7f);
    face = ps->stats[STAT_HEALTH] <= 0 ? 7 : (int)Com_Clamp(0, 6, (100 - ps->stats[STAT_HEALTH]) / 15);
    HudPicture(center - 94 * scale, base - 128 * scale, 128 * scale, 128 * scale,
        va("bottom_2_0%c", 'a' + face), 0.7f);
    values[0] = ps->stats[STAT_ARMOR]; values[1] = ps->stats[STAT_HEALTH] > 0 ? ps->stats[STAT_HEALTH] : 0;
    values[2] = DK_WeaponHudValue(ps, cg.time);
    values[3] = cgs.gametype == GT_SINGLE_PLAYER ? ps->dk3Level - 1 : ps->persistant[PERS_SCORE];
    for (i = 0; i < 4; ++i) {
        const dkFont_t *digits = values[i] >= 0 && values[i] <= (i < 2 ? 25 : i == 2 ? 5 : -1) ? &redNumbers : &numbers;
        const char *icon = i == 3 && cgs.gametype != GT_SINGLE_PLAYER ? "fragicon" : icons[i];
        HudPicture(center + (iconX[i] - 64) * scale, base + iconY[i] * scale, 64 * scale, 64 * scale, icon, 0.7f);
        DK_Text(&statFont, center + (labelX[i] - 64) * scale, base - 22 * scale,
            scale * statFont.height / 16.0f, i == 3 && cgs.gametype != GT_SINGLE_PLAYER ? "FRAGS" : labels[i], white);
        if (values[i] < 0 && i != 3) Q_strncpyz(text, "--", sizeof(text));
        else Com_sprintf(text, sizeof(text), "%d", values[i]);
        /* Keep the units column fixed when a value gains more digits. */
        DK_Text(digits, center + valueX[i] * scale -
            (DK_TextWidth(digits, text, scale * digits->height / 16.0f) -
             DK_TextWidth(digits, "0", scale * digits->height / 16.0f)), base - 35 * scale,
            scale * digits->height / 16.0f, text, white);
    }
    if (ps->dk3AttributePoints > 0) {
        HudPicture(center + 204 * scale, base - 90 * scale, 32 * scale, 32 * scale, "selec_skill", 1);
        Com_sprintf(text, sizeof(text), "+%d", ps->dk3AttributePoints);
        DK_Text(&statFont, center + 226 * scale, base - 82 * scale, scale * 0.75f, text, white);
    }
}


static void CompanionBars(float x, float bottom, float scale) {
    char status[256], name[32], *cursor, *token;
    const float ink[4] = {0.6f, 1, 0.4f, 1};
    const float bars[2][4] = {{0.15f, 0.8f, 0.1f, 0.9f}, {0.4f, 0.65f, 1, 0.9f}};
    Q_strncpyz(status, CG_ConfigString(CS_DK3_COMPANIONS), sizeof(status)); cursor = status;
    while (*(token = COM_Parse(&cursor))) {
        int health, armor, weapon, ammo, order, side, meter;
        float left;
        char text[48];
        Q_strncpyz(name, token, sizeof(name));
        health = atoi(COM_Parse(&cursor)); armor = atoi(COM_Parse(&cursor));
        weapon = atoi(COM_Parse(&cursor)); ammo = atoi(COM_Parse(&cursor)); order = atoi(COM_Parse(&cursor));
        if (!cursor) break;
        side = !Q_stricmp(name, "Superfly");
        left = x + (side ? 290 : -350) * scale;
        HudPicture(left, bottom - 128 * scale, 128 * scale, 128 * scale, side ? "superfly" : "mikiko", 0.7f);
        for (meter = 0; meter < 2; ++meter) {
            int value = meter ? armor : health;
            float height = Com_Clamp(0, 1, value / 100.0f) * 45 * scale;
            trap_R_SetColor(bars[meter]);
            trap_R_DrawStretchPic(left + ((side ? 25 : 85) + meter * 8) * scale,
                bottom - 45 * scale - height, 5 * scale, height, 0, 0, 1, 1, cgs.media.whiteShader);
        }
        trap_R_SetColor(NULL);
        Com_sprintf(text, sizeof(text), "%d / %d", health > 0 ? health : 0, armor);
        DK_Text(&statFont, left + 16 * scale, bottom - 26 * scale, scale * 0.65f, text, ink);
        Q_strncpyz(text, health <= 0 ? "Fallen" : order == 1 ? "Wait" : order == 2 ? "Attack" : order == 3 ? "Pickup" : "Follow", sizeof(text));
        DK_Text(&statFont, left + 24 * scale, bottom - 120 * scale, scale * 0.65f, text, ink);
        if (weapon > 0 && weapon < DK_WEAPON_COUNT && dk_weapons[weapon].ammoMax) {
            int tier = (int)Com_Clamp(1, 4, ceil(ammo * 4.0f / dk_weapons[weapon].ammoMax));
            HudPicture(left + (side ? 1 : 100) * scale, bottom - 128 * scale, 32 * scale, 32 * scale,
                ammo > 0 ? va("ammo%d", tier) : "ammo", 0.85f);
        }
    }
}



#include "../shared/dk_loading.h"
static int loadingProgress, loadingBlocks;

void DK_LoadingProgress(int progress) {
    int blocks;
    if (!progress) { loadingProgress = loadingBlocks = 0; }
    loadingProgress = progress;
    blocks = progress * 36 / 100;
    trap_Cvar_Set("dk3_loadingProgress", va("%d", progress));
    if (blocks > loadingBlocks) {
        trap_S_StartLocalSound(trap_S_RegisterSound("sounds/menus/button_002.wav", qfalse), CHAN_LOCAL_SOUND);
        loadingBlocks = blocks;
    }
    trap_UpdateScreen();
    trap_DK3UpdateSound();
}

void DK_DrawLoading(void) {
    DK_LoadingScreen(Info_ValueForKey(CG_ConfigString(CS_SERVERINFO), "mapname"),
        CG_ConfigString(CS_DK3_LOADSCREEN), loadingProgress, cgs.glconfig.vidWidth, cgs.glconfig.vidHeight);
}

qhandle_t DK_RegisterModel(const char *name) {
    char path[MAX_QPATH];
    int length = strlen(name);
    qhandle_t model;
    if (!Q_stricmp(COM_GetExtension(name), "sp2")) return 0;
    if (length < 4 || Q_stricmp(name + length - 4, ".dkm")) return trap_R_RegisterModel(name);
    if (length + 4 >= (int)sizeof(path)) {
        CG_Printf("dk3: model path exceeds engine limit: %s\n", name);
        return 0;
    }
    Com_sprintf(path, sizeof(path), "%s.md3", name);
    model = trap_R_RegisterModel(path);
    if (model) return model;
    Com_sprintf(path, sizeof(path), "%s.iqm", name);
    return trap_R_RegisterModel(path);
}

void DK_RegisterSounds(void) {
    int i, material;
    static const char *steps[] = {"p_stp", "p_stp", "p_stp", "p_stpmt", "p_stp", "p_stpmt", "p_stppu"};
    for (material = 0; material < ARRAY_LEN(steps); ++material)
        for (i = 0; i < 4; ++i)
            cgs.media.footsteps[material][i] = trap_S_RegisterSound(va("sounds/global/%s%d.wav", steps[material], i + 1), qfalse);
#define SOUND(field, path) cgs.media.field = trap_S_RegisterSound("sounds/" path ".wav", qfalse)
    SOUND(selectSound, "global/inventory_update");
    SOUND(useNothingSound, "global/b_denied1");
    SOUND(deniedSound, "global/b_denied1");
    SOUND(teleInSound, "global/e_teleportend");
    SOUND(teleOutSound, "global/e_teleportstart");
    SOUND(respawnSound, "global/new_respawn1");
    SOUND(noAmmoSound, "global/we_noammo");
    SOUND(talkSound, "global/inventory_update");
    SOUND(landSound, "hiro/land1");
    SOUND(watrInSound, "global/p_stppu1");
    SOUND(watrOutSound, "hiro/exitwater");
    SOUND(watrUnSound, "hiro/breathe");
    SOUND(hitSound, "global/bullethitflesh");
    SOUND(hitSoundHighArmor, "global/e_ricocheta");
    SOUND(hitSoundLowArmor, "global/e_ricochetb");
    SOUND(gibSound, "global/m_gibexpa");
    SOUND(gibBounce1Sound, "global/m_gibbonea");
    SOUND(gibBounce2Sound, "global/m_gibboneb");
    SOUND(gibBounce3Sound, "global/m_gibbonec");
    SOUND(sfx_ric1, "global/e_ricocheta");
    SOUND(sfx_ric2, "global/e_ricochetb");
    SOUND(sfx_ric3, "global/e_ricochetc");
#undef SOUND
    for (i = 1; i < MAX_SOUNDS; ++i) {
        const char *name = CG_ConfigString(CS_SOUNDS + i);
        if (!*name) break;
        if (!(i % 8)) DK_LoadingProgress(10 + i * 25 / MAX_SOUNDS);
        if (*name != '*') cgs.gameSounds[i] = trap_S_RegisterSound(name, qfalse);
    }
}

static char skyOriginal[MAX_QPATH], skyNames[5][MAX_QPATH];
static int skyIndex;
void DK_UpdateSky(void) {
    int index = (int)Com_Clamp(1, 5, atoi(CG_ConfigString(CS_DK3_SKY))) - 1;
    if (*skyOriginal && index != skyIndex) {
        trap_R_RegisterShader(skyNames[index]);
        trap_R_RemapShader(skyOriginal, skyNames[index], "0");
        skyIndex = index;
    }
}
static void LoadSky(void) {
    char path[MAX_QPATH], text[512], *cursor;
    fileHandle_t file;
    int length, version, i;
    *skyOriginal = 0; skyIndex = -1;
    Com_sprintf(path, sizeof(path), "dk3/skies/%s.cfg", Info_ValueForKey(CG_ConfigString(CS_SERVERINFO), "mapname"));
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 0) return;
    if (length < 1 || length >= sizeof(text)) { if (file) trap_FS_FCloseFile(file); CG_Error("dk3: invalid sky metadata %s", path); }
    trap_FS_Read(text, length, file); trap_FS_FCloseFile(file); text[length] = 0; cursor = text;
    if (strcmp(COM_Parse(&cursor), "dk3_sky")) CG_Error("dk3: invalid sky metadata %s", path);
    version = atoi(COM_Parse(&cursor));
    if (version != 1 && version != 2) CG_Error("dk3: unsupported sky metadata %s", path);
    Q_strncpyz(skyOriginal, COM_Parse(&cursor), sizeof(skyOriginal));
    for (i = 0; i < 5; ++i) {
        Q_strncpyz(skyNames[i], version == 1 && i ? skyNames[0] : COM_Parse(&cursor), MAX_QPATH);
        if (!*skyNames[i]) CG_Error("dk3: missing sky selection %d in %s", i + 1, path);
    }
    if (!*skyOriginal || *COM_Parse(&cursor)) CG_Error("dk3: invalid sky binding %s", path);
    DK_UpdateSky();
}

void DK_RegisterGraphics(void) {
    int i, axis;
    memset(&cg.refdef, 0, sizeof(cg.refdef));
    trap_R_ClearScene();
    CG_LoadingString(cgs.mapname);
    DK_LoadingProgress(40);
    trap_R_LoadWorldMap(cgs.mapname);
    LoadSky();
    DK_LoadingProgress(50);
    cgs.media.smokePuffShader = trap_R_RegisterShader("dk3/fx/smoke");
    cgs.media.smokePuffRageProShader = cgs.media.shotgunSmokePuffShader = cgs.media.smokePuffShader;
    cgs.media.waterBubbleShader = trap_R_RegisterShader("dk3/fx/glow");
    cgs.media.bloodTrailShader = cgs.media.bloodExplosionShader = trap_R_RegisterShader("models/global/we_blood.sp2/0");
    cgs.media.bloodMarkShader = cgs.media.bloodExplosionShader;
    cgs.media.viewBloodShader = cgs.media.bloodExplosionShader;
    cgs.media.tracerShader = trap_R_RegisterShader("dk3/fx/beam");
    cgs.media.invisShader = trap_R_RegisterShader("dk3/fx/cloak");
    cgs.media.shadowMarkShader = trap_R_RegisterShader("projectionShadow");
    for (i = 0; i < NUM_CROSSHAIRS; ++i)
        cgs.media.crosshairShader[i] = trap_R_RegisterShaderNoMip(i % 4 ?
            va("pics/crosshair/ch_center%d.tga", i % 4 + 1) : "pics/crosshair/ch_center.tga");
#define GIB(field, name) cgs.media.field = DK_RegisterModel("models/global/e_gib" name ".dkm")
    GIB(gibAbdomen, "torso"); GIB(gibArm, "arm"); GIB(gibChest, "chest");
    GIB(gibFist, "hand"); GIB(gibFoot, "foot"); GIB(gibForearm, "arm");
    GIB(gibIntestine, "misc"); GIB(gibLeg, "leg"); GIB(gibSkull, "head"); GIB(gibBrain, "chunk");
#undef GIB
    cgs.numInlineModels = trap_CM_NumInlineModels();
    if (cgs.numInlineModels > MAX_MODELS) CG_Error("dk3: map exceeds inline-model capacity");
    for (i = 1; i < cgs.numInlineModels; ++i) {
        vec3_t mins, maxs;
        cgs.inlineDrawModel[i] = trap_R_RegisterModel(va("*%d", i));
        trap_R_ModelBounds(cgs.inlineDrawModel[i], mins, maxs);
        for (axis = 0; axis < 3; ++axis) cgs.inlineModelMidpoints[i][axis] = (mins[axis] + maxs[axis]) * 0.5f;
    }
    for (i = 1; i < MAX_MODELS; ++i) {
        const char *name = CG_ConfigString(CS_MODELS + i);
        if (!*name) break;
        cgs.gameModels[i] = DK_RegisterModel(name);
        if (!(i % 4)) DK_LoadingProgress(50 + i * 40 / MAX_MODELS);
    }
    CG_ClearParticles();
}

void DK_DrawScores(void) {
    const float white[4] = {0.9f, 0.94f, 1, 1}, red[4] = {1, 0.4f, 0.3f, 1}, blue[4] = {0.35f, 0.65f, 1, 1};
    const float background[4] = {0.02f, 0.03f, 0.04f, 0.92f};
    float scale = cgs.glconfig.vidHeight / 720.0f, left = cgs.glconfig.vidWidth * 0.1f, y = 90 * scale;
    int i, rows = (int)((cgs.glconfig.vidHeight - y - 60 * scale) / (28 * scale)) - 2;
    char text[160];
    if (!font.shader) DK_LoadFont(&font);
    trap_R_SetColor(background);
    trap_R_DrawStretchPic(left - 16 * scale, y - 20 * scale, cgs.glconfig.vidWidth * 0.8f + 32 * scale,
                          cgs.glconfig.vidHeight - y - 30 * scale, 0, 0, 1, 1, cgs.media.whiteShader);
    trap_R_SetColor(NULL);
    if (cgs.gametype == GT_SINGLE_PLAYER) {
        DK_Text(&font, left, y, scale, cg.snap->ps.stats[STAT_HEALTH] <= 0 ?
            "You died. Load a save from the menu or press your quick-load key." : "Campaign status", white);
        return;
    }
    DK_Text(&font, left, y, scale, "Player                         Score     Ping", white); y += 38 * scale;
    for (i = 0; i < cg.numScores && i < rows; ++i) {
        score_t *score = &cg.scores[i];
        clientInfo_t *client;
        const float *color;
        if (score->client < 0 || score->client >= MAX_CLIENTS) continue;
        client = &cgs.clientinfo[score->client];
        color = client->team == TEAM_RED ? red : client->team == TEAM_BLUE ? blue : white;
        Com_sprintf(text, sizeof(text), "%.28s", client->name);
        DK_Text(&font, left, y, scale, text, color);
        Com_sprintf(text, sizeof(text), "%d", score->score);
        DK_Text(&font, left + 350 * scale, y, scale, text, color);
        Com_sprintf(text, sizeof(text), "%d", score->ping);
        DK_Text(&font, left + 465 * scale, y, scale, text, color);
        y += 28 * scale;
    }
}

void DK_DrawHud(void) {
    float scale = cgs.glconfig.vidHeight / 480.0f;
    if (!hudScale.handle) trap_Cvar_Register(&hudScale, "cg_hudScale", "1", CVAR_ARCHIVE);
    trap_Cvar_Update(&hudScale);
    scale *= Com_Clamp(0.75f, 1.5f, hudScale.value);
    if (scale > cgs.glconfig.vidWidth / 640.0f) scale = cgs.glconfig.vidWidth / 640.0f;
    float textColor[4] = {0.9f, 0.94f, 1.0f, 1.0f};
    char text[128];
    if (cg.predictedPlayerState.dk3CameraActive) {
        const float black[4] = {0, 0, 0, 1};
        qhandle_t white = trap_R_RegisterShader("white");
        float bar = cgs.glconfig.vidHeight * 0.10f;
        trap_R_SetColor(cg.predictedPlayerState.dk3CameraBlend);
        trap_R_DrawStretchPic(0, 0, cgs.glconfig.vidWidth, cgs.glconfig.vidHeight, 0, 0, 1, 1, white);
        trap_R_SetColor(black);
        trap_R_DrawStretchPic(0, 0, cgs.glconfig.vidWidth, bar, 0, 0, 1, 1, white);
        trap_R_DrawStretchPic(0, cgs.glconfig.vidHeight - bar, cgs.glconfig.vidWidth, bar, 0, 0, 1, 1, white);
        trap_R_SetColor(NULL);
        DK_DrawSubtitles();
        return;
    }
    if (cg_blood.integer && cg.damageTime > 0 && cg.time >= cg.damageTime && cg.time - cg.damageTime < DAMAGE_TIME) {
        float tint[4] = {0.7f, 0.02f, 0.01f, 0};
        if (cg.predictedPlayerState.dk3Status & 1) { tint[0] = 0.02f; tint[1] = 0.6f; }
        else if (cg.predictedPlayerState.dk3Status & 4) { tint[0] = 0.02f; tint[2] = 0.7f; }
        tint[3] = ((cg.predictedPlayerState.dk3Status & 5) == 4 ? Com_Clamp(0.1f, 0.4f, 0.4f * cg.predictedPlayerState.dk3FreezeLevel) :
            Com_Clamp(0, 0.35f, cg.damageValue * 0.015f)) * (1 - (cg.time - cg.damageTime) / (float)DAMAGE_TIME);
        trap_R_SetColor(tint);
        trap_R_DrawStretchPic(0, 0, cgs.glconfig.vidWidth, cgs.glconfig.vidHeight, 0, 0, 1, 1, cgs.media.whiteShader);
        trap_R_SetColor(NULL);
    }
    DK_WeaponOverlay();
    DK_DrawSubtitles();
    if (!font.shader) DK_LoadFont(&font);
    if (scale < 0.7f) scale = 0.7f;
    playerState_t *ps = &cg.predictedPlayerState;
    DK_UpdateWeaponSelection();
    StatusBar(ps, scale);
    if (cgs.gametype >= GT_TEAM) {
        Com_sprintf(text, sizeof(text), "Red %d    Blue %d", cgs.scores1, cgs.scores2);
        DK_Text(&font, 24 * scale, 24 * scale, scale, text, textColor);
    }
    if (ps->dk3Objective) {
        if (cgs.gametype == GT_DK3_DEATHTAG)
            Com_sprintf(text, sizeof(text), "Bomb: %d seconds", (ps->dk3ObjectiveUntil - cg.time + 999) / 1000);
        else Q_strncpyz(text, "Flag carried: return to your capture zone", sizeof(text));
        DK_Text(&font, 24 * scale, 50 * scale, scale, text, textColor);
    }
    CompanionBars(cgs.glconfig.vidWidth * 0.5f, cgs.glconfig.vidHeight, scale);
    DK_DrawInventory(scale);
}
