/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "cg_local.h"
#include "../shared/dk_font.h"

static dkFont_t font, statFont, numbers, redNumbers;
static qhandle_t worldModels[DK_WEAPON_COUNT];
static qboolean triedWorld[DK_WEAPON_COUNT];
static unsigned int previousInventory;
static vmCvar_t hudScale;
static int gasPuffTime[MAX_CLIENTS];
static int viewWeapon, viewWeaponState, viewWeaponStart, viewWeaponTime, viewWeaponShot;
static int viewWeaponEnd, viewWeaponIdle, viewWeaponIdleVariant;
static const char *viewWeaponAnimation;
#define DK_VIEW_WEAPON_RATE 20
#define DK_VIEW_WEAPON_IDLE_DELAY 5000

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
    values[2] = weapon > 0 && weapon < DK_WEAPON_COUNT && dk_weapons[weapon].ammoMax ? ps->ammo[weapon] : -1;
    if (values[2] < 0) values[2] = 0;
    if (weapon == DK_W_GASHANDS) values[2] = (ps->powerups[PW_DK3_GASHANDS] - cg.time + 999) / 1000;
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

static void LoadSky(void) {
    char path[MAX_QPATH], text[256], original[MAX_QPATH], replacement[MAX_QPATH], *cursor;
    fileHandle_t file;
    int length;
    Com_sprintf(path, sizeof(path), "dk3/skies/%s.cfg", Info_ValueForKey(CG_ConfigString(CS_SERVERINFO), "mapname"));
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 0) return; /* Maps without authored clouds keep their skybox. */
    if (length < 1 || length >= sizeof(text)) { if (file) trap_FS_FCloseFile(file); CG_Error("dk3: invalid sky metadata %s", path); }
    trap_FS_Read(text, length, file); trap_FS_FCloseFile(file); text[length] = 0; cursor = text;
    if (strcmp(COM_Parse(&cursor), "dk3_sky") || strcmp(COM_Parse(&cursor), "1")) CG_Error("dk3: invalid sky metadata %s", path);
    Q_strncpyz(original, COM_Parse(&cursor), sizeof(original));
    Q_strncpyz(replacement, COM_Parse(&cursor), sizeof(replacement));
    if (!*original || !*replacement || *COM_Parse(&cursor)) CG_Error("dk3: invalid sky binding %s", path);
    if (!trap_R_RegisterShader(replacement)) CG_Error("dk3: missing sky shader %s", replacement);
    trap_R_RemapShader(original, replacement, "0");
    CG_Printf("dk3: map sky %s uses %s\n", original, replacement);
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
        tint[3] = Com_Clamp(0, 0.35f, cg.damageValue * 0.015f) *
            (1 - (cg.time - cg.damageTime) / (float)DAMAGE_TIME);
        trap_R_SetColor(tint);
        trap_R_DrawStretchPic(0, 0, cgs.glconfig.vidWidth, cgs.glconfig.vidHeight, 0, 0, 1, 1, cgs.media.whiteShader);
        trap_R_SetColor(NULL);
    }
    DK_DrawSubtitles();
    if (!font.shader) DK_LoadFont(&font);
    if (scale < 0.7f) scale = 0.7f;
    playerState_t *ps = &cg.predictedPlayerState;
    int weapon = ps->weapon;
    unsigned int acquired = ps->dk3Inventory & ~previousInventory & ~(1u << DK_W_FLASHLIGHT);
    if (!previousInventory || !DK_HasWeapon(ps, cg.weaponSelect)) cg.weaponSelect = weapon;
    else if (acquired && cg_autoswitch.integer) {
        int selected;
        if (acquired & (1u << weapon)) cg.weaponSelect = weapon;
        else for (selected = 1; selected < DK_WEAPON_COUNT; ++selected)
            if (acquired & (1u << selected)) { cg.weaponSelect = selected; break; }
        cg.weaponSelectTime = cg.time;
    }
    previousInventory = ps->dk3Inventory;
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

static qhandle_t WorldModel(int weapon) {
    if (weapon <= 0 || weapon >= DK_WEAPON_COUNT) return 0;
    if (!triedWorld[weapon]) {
        triedWorld[weapon] = qtrue;
        worldModels[weapon] = DK_RegisterModel(DK_WeaponWorldModel(weapon));
    }
    return worldModels[weapon];
}

static void Muzzle(refEntity_t *parent, int weapon, int fired) {
    refEntity_t flash;
    orientation_t tag;
    int axis;
    if (cg.time < fired || cg.time - fired > 80 || weapon <= 0 || weapon >= DK_WEAPON_COUNT ||
        weapon == DK_W_DISRUPTOR || weapon == DK_W_GASHANDS || weapon == DK_W_SWORD || weapon == DK_W_SILVERCLAW ||
        weapon == DK_W_HAMMER || weapon == DK_W_DISCUS || weapon == DK_W_FLASHLIGHT) return;
    memset(&flash, 0, sizeof(flash));
    DK_ModelAnimation("models/global/we_mflash.dkm", "amba", fired, qfalse, &flash);
    if (trap_R_LerpTag(&tag, parent->hModel, parent->oldframe, parent->frame, 1 - parent->backlerp, "fire")) {
        AxisClear(flash.axis); CG_PositionEntityOnTag(&flash, parent, parent->hModel, "fire");
    } else VectorMA(parent->origin, 24, parent->axis[0], flash.origin);
    AxisCopy(parent->axis, flash.axis);
    for (axis = 0; axis < 3; ++axis) VectorScale(flash.axis[axis], 0.6f, flash.axis[axis]);
    flash.nonNormalizedAxes = qtrue; flash.reType = RT_MODEL; flash.renderfx = parent->renderfx;
    flash.shaderRGBA[0] = flash.shaderRGBA[1] = flash.shaderRGBA[2] = flash.shaderRGBA[3] = 255;
    trap_R_AddRefEntityToScene(&flash);
    trap_R_AddLightToScene(flash.origin, 130, 1, 0.65f, 0.3f);
}

static void GasCloud(refEntity_t *parent, int client) {
    vec3_t origin, velocity = {0, 0, 15};
    float side;
    if (client < 0 || client >= MAX_CLIENTS) return;
    if (gasPuffTime[client] > cg.time) gasPuffTime[client] = 0;
    if (cg.time - gasPuffTime[client] < 100) return;
    gasPuffTime[client] = cg.time;
    side = ((cg.time / 100 + client) & 1) ? 1 : -1;
    VectorMA(parent->origin, 18, parent->axis[0], origin);
    VectorMA(origin, side * 6, parent->axis[1], origin);
    VectorMA(origin, -6, parent->axis[2], origin);
    CG_SmokePuff(origin, velocity, 4, 0.5f, 0.65f, 0.45f, 0.18f,
                 450, cg.time, 0, 0, cgs.media.smokePuffShader);
}

static void ViewWeaponAnimation(const char *path, const char *name, int start) {
    viewWeaponAnimation = name;
    viewWeaponStart = start;
    viewWeaponEnd = start + DK_ModelAnimationDuration(path, name, DK_VIEW_WEAPON_RATE);
    viewWeaponIdle = viewWeaponEnd + DK_VIEW_WEAPON_IDLE_DELAY;
}

static void ViewWeaponPose(playerState_t *ps, refEntity_t *entity) {
    const char *path = dk_weapons[ps->weapon].model;
    int shot = cg.predictedPlayerEntity.muzzleFlashTime;
    qboolean reset = viewWeapon != ps->weapon || cg.time < viewWeaponTime || !viewWeaponAnimation;
    if (reset) {
        viewWeapon = ps->weapon; viewWeaponState = WEAPON_READY;
        viewWeaponShot = shot; viewWeaponIdleVariant = 0;
        ViewWeaponAnimation(path, "ready", cg.time - DK_ModelAnimationDuration(path, "ready", DK_VIEW_WEAPON_RATE));
    }
    if (ps->weaponstate == WEAPON_FIRING && (viewWeaponState != WEAPON_FIRING || viewWeaponShot != shot)) {
        ViewWeaponAnimation(path, "shoot", cg.time);
    } else if ((reset || ps->weaponstate != viewWeaponState) && ps->weaponstate == WEAPON_RAISING) {
        ViewWeaponAnimation(path, "ready", cg.time);
    } else if (ps->weaponstate != viewWeaponState && ps->weaponstate == WEAPON_DROPPING) {
        ViewWeaponAnimation(path, "away", cg.time);
    } else if (ps->weaponstate == WEAPON_READY && cg.time >= viewWeaponIdle) {
        const char *idle = (++viewWeaponIdleVariant & 1) ? "amba" : "ambb";
        if (!DK_ModelAnimationDuration(path, idle, DK_VIEW_WEAPON_RATE)) idle = "amba";
        if (DK_ModelAnimationDuration(path, idle, DK_VIEW_WEAPON_RATE)) ViewWeaponAnimation(path, idle, cg.time);
        else viewWeaponIdle = cg.time + DK_VIEW_WEAPON_IDLE_DELAY;
    }
    viewWeaponState = ps->weaponstate; viewWeaponShot = shot; viewWeaponTime = cg.time;
    /* READY permits the next shot; it does not interrupt the previous pose.
       Each finite sequence settles on its final frame between actions. */
    DK_ModelAnimationRate(path, viewWeaponAnimation, viewWeaponStart, qfalse, DK_VIEW_WEAPON_RATE, entity);
}

void DK_DrawViewWeapon(playerState_t *ps) {
    refEntity_t entity;
    if (cg.renderingThirdPerson || ps->pm_type != PM_NORMAL || !cg_drawGun.integer) return;
    memset(&entity, 0, sizeof(entity));
    if (ps->weapon <= 0 || ps->weapon >= DK_WEAPON_COUNT || !*dk_weapons[ps->weapon].model) return;
    ViewWeaponPose(ps, &entity);
    if (!entity.hModel) return;
    VectorCopy(cg.refdef.vieworg, entity.origin);
    /* Supplied first-person meshes already include their camera-relative offset. */
    VectorMA(entity.origin, cg_gun_x.value, cg.refdef.viewaxis[0], entity.origin);
    VectorMA(entity.origin, cg_gun_y.value, cg.refdef.viewaxis[1], entity.origin);
    VectorMA(entity.origin, cg_gun_z.value, cg.refdef.viewaxis[2], entity.origin);
    AxisCopy(cg.refdef.viewaxis, entity.axis);
    entity.reType = RT_MODEL;
    entity.renderfx = RF_DEPTHHACK | RF_FIRST_PERSON | RF_MINLIGHT;
    entity.shaderRGBA[0] = entity.shaderRGBA[1] = entity.shaderRGBA[2] = entity.shaderRGBA[3] = 255;
    if (ps->powerups[PW_INVIS] > cg.time) {
        entity.customShader = trap_R_RegisterShader("dk3/fx/cloak"); entity.shaderRGBA[3] = 100;
    }
    trap_R_AddRefEntityToScene(&entity);
    Muzzle(&entity, ps->weapon, cg.predictedPlayerEntity.muzzleFlashTime);
    if (ps->weapon == DK_W_GASHANDS) GasCloud(&entity, ps->clientNum);
}

void DK_DrawPlayerWeapon(refEntity_t *parent, centity_t *cent) {
    refEntity_t entity;
    memset(&entity, 0, sizeof(entity));
    entity.hModel = WorldModel(cent->currentState.weapon);
    if (!entity.hModel) return;
    entity.reType = RT_MODEL;
    AxisClear(entity.axis);
    CG_PositionEntityOnTag(&entity, parent, parent->hModel, "hp_gun");
    AxisCopy(parent->axis, entity.axis);
    entity.shaderRGBA[0] = entity.shaderRGBA[1] = entity.shaderRGBA[2] = entity.shaderRGBA[3] = 255;
    entity.renderfx = parent->renderfx;
    entity.customShader = parent->customShader;
    entity.shaderRGBA[3] = parent->shaderRGBA[3];
    trap_R_AddRefEntityToScene(&entity);
    if (cent->currentState.number != cg.clientNum || cg.renderingThirdPerson)
        Muzzle(&entity, cent->currentState.weapon, cent->muzzleFlashTime);
    if (cent->currentState.weapon == DK_W_GASHANDS &&
        (cent->currentState.number != cg.clientNum || cg.renderingThirdPerson))
        GasCloud(&entity, cent->currentState.number);
}

void DK_SelectWeapon(int direction, int requested) {
    int weapon, i;
    if (!cg.snap || (cg.snap->ps.pm_flags & PMF_FOLLOW)) return;
    if (!direction) {
        if (DK_HasWeapon(&cg.snap->ps, requested)) cg.weaponSelect = requested;
    } else {
        weapon = cg.weaponSelect;
        for (i = 0; i < DK_WEAPON_COUNT; ++i) {
            weapon = (weapon + direction + DK_WEAPON_COUNT) % DK_WEAPON_COUNT;
            if (DK_HasWeapon(&cg.snap->ps, weapon)) { cg.weaponSelect = weapon; break; }
        }
    }
    cg.weaponSelectTime = cg.time;
}

typedef struct { int start, end, weapon; vec3_t origin; } combatEffect_t;
static combatEffect_t combatEffects[64];
static int nextCombatEffect;

static const char *const projectileModels[DK_WEAPON_COUNT] = {
    "", "", "models/e1/we_ionbl.dkm", "models/e1/we_c4prj.dkm", "",
    "models/e1/we_swrocket.dkm", "models/e1/we_3dshock.dkm", "", "",
    "models/e2/we_discus.dkm", "models/e2/we_sunprj.dkm", "models/e2/we_3dvenom.dkm", "", "models/e2/we_tritip.dkm",
    "", "", "models/e3/we_bolt.dkm", "models/e3/we_fball.dkm", "models/e3/we_balprj.dkm",
    "models/e3/we_wisp.sp2", "models/e3/we_nnreaper.dkm", "", "", "",
    "models/e4/we_kcoreshot.sp2", "", "models/e4/we_mmprj.dkm", "models/e4/we_ripgren.dkm", ""
};
static const char *const firingSounds[DK_WEAPON_COUNT] = {
    "", "e1/we_dgloveshoota.wav", "e1/we_ionshootb.wav", "e1/we_c4shoota.wav", "e1/we_shotcyclershoota.wav",
    "e1/we_sidewindershoot.wav", "e1/we_shockwaveshoota.wav", "e1/we_gasclang.wav", "global/we_dk_01.wav",
    "e2/we_discfire.wav", "e2/we_sflareshoota.wav", "e2/we_venomshoota.wav", "e2/we_hammerd.wav", "e2/we_tridentfirea.wav",
    "e2/we_zeusshoota.wav", "e3/we_sclawshoota.wav", "e3/we_bolterfire.wav", "e3/we_stavefire.wav", "e3/we_ballistafirea.wav",
    "e3/we_wwispshoota.wav", "e3/we_nharrewind.wav", "e4/we_glockshoota2.wav", "e4/we_ripgunshoota.wav", "e4/we_sluggershoota.wav",
    "e4/we_kcoreshoota.wav", "e4/we_novafirea.wav", "e4/we_metamaszapa.wav", "e4/we_sluggershootb.wav", ""
};

static void WeaponColor(int weapon, vec3_t color) {
    if (weapon == DK_W_ION) VectorSet(color, 0, 0.8f, 0);
    else if (weapon == DK_W_KINETICORE || weapon == DK_W_ZEUS) VectorSet(color, 0.2f, 0.65f, 1);
    else if (weapon == DK_W_VENOM || weapon == DK_W_WYNDRAX) VectorSet(color, 0.35f, 1, 0.2f);
    else if (weapon == DK_W_NIGHTMARE || weapon == DK_W_METAMASER) VectorSet(color, 0.9f, 0.2f, 1);
    else VectorSet(color, 1, 0.45f, 0.12f);
}

void DK_WeaponFireSound(centity_t *entity) {
    int weapon = entity->currentState.weapon;
    if (weapon > 0 && weapon < DK_WEAPON_COUNT && *firingSounds[weapon])
        trap_S_StartSound(NULL, entity->currentState.number, CHAN_WEAPON,
            trap_S_RegisterSound(va("sounds/%s", firingSounds[weapon]), qfalse));
}

void DK_DrawProjectile(centity_t *cent) {
    refEntity_t entity;
    vec3_t color, angles;
    int weapon = cent->currentState.weapon;
    const char *model;
    if (weapon <= 0 || weapon >= DK_WEAPON_COUNT) return;
    if (cent->currentState.modelindex && DK_DrawSprite(cent)) {
        trap_R_AddLightToScene(cent->lerpOrigin, 160, 0.15f, 0.95f, 0.35f);
        return;
    }
    model = projectileModels[weapon];
    WeaponColor(weapon, color);
    vectoangles(cent->currentState.pos.trDelta, angles);
    if (*model && !DK_DrawSpriteAt(model, (cg.time - cent->currentState.time) / 70,
            cent->lerpOrigin, angles, 1, 1, color, 2)) {
        memset(&entity, 0, sizeof(entity));
        entity.reType = RT_MODEL; entity.hModel = DK_RegisterModel(model);
        VectorCopy(cent->lerpOrigin, entity.origin);
        if (weapon == DK_W_DISCUS) angles[YAW] += cg.time * 0.8f;
        AnglesToAxis(angles, entity.axis);
        if (weapon == DK_W_ION) {
            int axis;
            for (axis = 0; axis < 3; ++axis) VectorScale(entity.axis[axis], 3, entity.axis[axis]);
            entity.nonNormalizedAxes = qtrue;
        }
        entity.shaderRGBA[0] = entity.shaderRGBA[1] = entity.shaderRGBA[2] = entity.shaderRGBA[3] = 255;
        trap_R_AddRefEntityToScene(&entity);
    }
    if (weapon == DK_W_ION)
        DK_DrawSpriteAt("models/e1/we_ionbf.sp2", 0, cent->lerpOrigin, angles, 0.75f, 1, color, 2);
    trap_R_AddLightToScene(cent->lerpOrigin, weapon == DK_W_ION ? 300 : 70, color[0], color[1], color[2]);
}

static const char *ImpactSprite(int weapon) {
    switch (weapon) {
    case DK_W_ION: return "models/e1/we_ionexpl.sp2";
    case DK_W_SHOCKWAVE: return "models/e1/we_shockexp.sp2";
    case DK_W_VENOM: return "models/e2/we_vendis.sp2";
    case DK_W_SUNFLARE: return "models/e2/we_fire.sp2";
    case DK_W_KINETICORE: return "models/e4/we_kcorehitb.sp2";
    case DK_W_NOVABEAM: return "models/e4/we_novahit.sp2";
    case DK_W_METAMASER: return "models/e4/we_mmaserexp.sp2";
    default: return "models/global/we_expl.sp2";
    }
}

void DK_WeaponImpact(centity_t *cent) {
    int weapon = cent->currentState.weapon, kind = cent->currentState.eventParm;
    const char *mark = NULL, *sound = NULL;
    float radius = 4;
    if (weapon == DK_W_DISRUPTOR) {
        mark = "models/global/we_dispunch.sp2/0@mark"; radius = 8;
        sound = kind == 1 ? "e1/we_dglovehita.wav" : "e1/we_dglovehitc.wav";
    } else if (weapon == DK_W_ION) {
        static const char *contact[] = {"global/e_electronsprka.wav", "global/e_electronsprke.wav",
            "global/e_electronsprkg.wav", "global/e_electronsprkh.wav"};
        sound = kind == 1 ? "e1/we_ionexplodea.wav" : kind == 2 ? "e1/we_ionwaterhita.wav" :
            contact[cent->currentState.number & 3];
    } else if (weapon == DK_W_GLOCK || weapon == DK_W_RIPGUN || weapon == DK_W_SHOTCYCLER || weapon == DK_W_SLUGGER) {
        mark = "models/global/we_bhole.sp2/0@mark";
        sound = kind == 1 ? "global/bullethitflesh.wav" : "global/e_ricocheta.wav";
    } else if (weapon == DK_W_SIDEWINDER || weapon == DK_W_BALLISTA || weapon == DK_W_STAVROS || weapon == DK_W_CORDITE) {
        mark = "models/global/we_scorch.sp2/0@mark"; radius = 16;
    }
    if (sound) trap_S_StartSound(cent->lerpOrigin, ENTITYNUM_WORLD, CHAN_AUTO,
        trap_S_RegisterSound(va("sounds/%s", sound), qfalse));
    if (kind == 0 && mark)
        CG_ImpactMark(trap_R_RegisterShader(mark), cent->lerpOrigin, cent->currentState.origin2,
            (cent->currentState.number * 137) % 360, 1, 1, 1, 1, qtrue, radius, qfalse);
}

void DK_CombatEffect(centity_t *cent, qboolean blast) {
    int weapon = cent->currentState.weapon;
    vec3_t color;
    WeaponColor(weapon, color);
    if (blast) {
        combatEffect_t *effect = &combatEffects[nextCombatEffect++ % ARRAY_LEN(combatEffects)];
        effect->start = cg.time; effect->end = cg.time + 600; effect->weapon = weapon;
        VectorCopy(cent->lerpOrigin, effect->origin);
        if (weapon == DK_W_ION) trap_S_StartSound(cent->lerpOrigin, ENTITYNUM_WORLD, CHAN_AUTO,
            trap_S_RegisterSound("sounds/e1/we_ionhit.wav", qfalse));
        return;
    }
    {
        localEntity_t *effect = CG_AllocLocalEntity();
        refEntity_t *entity = &effect->refEntity;
        int i;
        effect->startTime = cg.time; effect->endTime = cg.time + 100;
        effect->lifeRate = 1.0f / (effect->endTime - effect->startTime); effect->leType = LE_FADE_RGB;
        for (i = 0; i < 3; ++i) { effect->color[i] = color[i]; entity->shaderRGBA[i] = color[i] * 255; }
        effect->color[3] = 1; entity->shaderRGBA[3] = 255;
        entity->reType = RT_RAIL_CORE; entity->radius = 2;
        entity->customShader = trap_R_RegisterShader("dk3/fx/beam");
        VectorCopy(cent->currentState.pos.trBase, entity->origin);
        VectorCopy(cent->currentState.origin2, entity->oldorigin);
    }
}

void DK_AddCombatEffects(void) {
    int i;
    vec3_t color, angles = {0, 0, 0};
    for (i = 0; i < ARRAY_LEN(combatEffects); ++i) {
        combatEffect_t *effect = &combatEffects[i];
        float alpha;
        if (cg.time < effect->start || cg.time >= effect->end) continue;
        alpha = (effect->end - cg.time) / (float)(effect->end - effect->start);
        WeaponColor(effect->weapon, color);
        DK_DrawSpriteAt(ImpactSprite(effect->weapon), (cg.time - effect->start) / 70, effect->origin, angles,
                       effect->weapon == DK_W_SHOCKWAVE ? 2 : 1, alpha, color,
                       DK_SPRITE_ADDITIVE | DK_SPRITE_CLAMP);
        trap_R_AddLightToScene(effect->origin, 180 * alpha, color[0], color[1], color[2]);
    }
}

void DK_OutOfAmmo(void) {
    int weapon;
    if (!cg.snap) return;
    for (weapon = DK_W_FLASHLIGHT - 1; weapon > 0; --weapon)
        if (DK_HasWeapon(&cg.snap->ps, weapon) && (!dk_weapons[weapon].ammoCost ||
            cg.snap->ps.ammo[weapon] >= dk_weapons[weapon].ammoCost)) {
            cg.weaponSelect = weapon;
            cg.weaponSelectTime = cg.time;
            return;
        }
}
