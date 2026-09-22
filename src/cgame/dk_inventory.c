/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "cg_local.h"
#include "../shared/dk_font.h"
#include "dk_inventory.h"

static dkFont_t font;
static qboolean inventoryOpen;
static int attributeChoice, itemChoice;
static const char *attributeCommands[] = {"power", "attack", "speed", "acro", "vita"};
static const char *attributeLabels[] = {"POWER", "ATTACK", "SPEED", "ACRO", "VITALITY"};

void DK_InitClientCommands(void) {
    const char *commands[] = {"inventory", "invnext", "invprev", "attribute_next", "attribute_increase", "attribute", "companion", "use", "save", "load", "cin_skip", "detonate", "c4_detonate"};
    int i;
    for (i = 0; i < ARRAY_LEN(commands); ++i) trap_AddCommand(commands[i]);
    inventoryOpen = qfalse; attributeChoice = itemChoice = 0;
}

qboolean DK_InventoryCommand(const char *command) {
    if (!strcmp(command, "inventory")) { inventoryOpen = !inventoryOpen; return qtrue; }
    if (!strcmp(command, "invnext") || !strcmp(command, "invprev")) {
        int count = 0, i;
        if (cg.snap) for (i = 0; i < DK_KEY_COUNT; ++i)
            if ((unsigned int)cg.snap->ps.dk3Keys & (1u << i)) ++count;
        itemChoice = count ? (itemChoice + (!strcmp(command, "invnext") ? 1 : count - 1)) % count : 0;
        inventoryOpen = qtrue; return qtrue;
    }
    if (!strcmp(command, "attribute_next")) { attributeChoice = (attributeChoice + 1) % 5; inventoryOpen = qtrue; return qtrue; }
    if (!strcmp(command, "attribute_increase")) {
        if (cg.snap) trap_SendClientCommand(va("attribute %s", attributeCommands[attributeChoice]));
        inventoryOpen = qtrue; return qtrue;
    }
    return qfalse;
}

static void Picture(float x, float y, float w, float h, const char *name, float alpha) {
    float color[4] = {1, 1, 1, alpha};
    trap_R_SetColor(color);
    trap_R_DrawStretchPic(x, y, w, h, 0, 0, 1, 1,
        trap_R_RegisterShaderNoMip(va("pics/statusbar/%s.tga", name)));
    trap_R_SetColor(NULL);
}

/* Use the supplied pickup geometry in a small independent render view. Model
   bounds determine the framing, including models whose origin is off-centre. */
static void Model(float x, float y, float w, float h, const char *path) {
    refdef_t view;
    refEntity_t entity;
    vec3_t mins, maxs, center, rotated, angles = {0, 35, 0};
    float radius;
    int axis;
    if (!path || !*path || w < 1 || h < 1) return;
    memset(&entity, 0, sizeof(entity));
    entity.hModel = DK_RegisterModel(path);
    if (!entity.hModel) return;
    trap_R_ModelBounds(entity.hModel, mins, maxs);
    VectorAdd(mins, maxs, center); VectorScale(center, 0.5f, center);
    radius = Distance(mins, maxs) * 0.5f;
    if (radius < 1) radius = 1;
    memset(&view, 0, sizeof(view));
    view.x = x; view.y = y; view.width = w; view.height = h;
    view.fov_y = 30; view.fov_x = atan(tan(15 * M_PI / 180) * w / h) * 360 / M_PI;
    AxisClear(view.viewaxis); view.rdflags = RDF_NOWORLDMODEL; view.time = cg.time;
    entity.reType = RT_MODEL; entity.renderfx = RF_NOSHADOW | RF_MINLIGHT;
    AnglesToAxis(angles, entity.axis);
    for (axis = 0; axis < 3; ++axis)
        rotated[axis] = center[0] * entity.axis[0][axis] + center[1] * entity.axis[1][axis] + center[2] * entity.axis[2][axis];
    VectorNegate(rotated, entity.origin);
    entity.origin[0] += radius / sin(15 * M_PI / 180);
    entity.shaderRGBA[0] = entity.shaderRGBA[1] = entity.shaderRGBA[2] = entity.shaderRGBA[3] = 255;
    trap_R_ClearScene(); trap_R_AddRefEntityToScene(&entity);
    trap_R_AddLightToScene(view.vieworg, radius * 12, 1, 1, 1);
    trap_R_RenderScene(&view);
}

static void Nodules(float x, float y, int filled, int count, float scale) {
    const float colors[2][4] = {{0.10f, 0.16f, 0.09f, 0.85f}, {0.45f, 0.95f, 0.2f, 1}};
    int i;
    for (i = 0; i < count; ++i) {
        trap_R_SetColor(colors[i < filled]);
        trap_R_DrawStretchPic(x + i * 8 * scale, y, 6 * scale, 8 * scale, 0, 0, 1, 1, cgs.media.whiteShader);
    }
    trap_R_SetColor(NULL);
}

void DK_DrawInventory(float scale) {
    playerState_t *player = &cg.predictedPlayerState;
    float center = cgs.glconfig.vidWidth * 0.5f, bottom = cgs.glconfig.vidHeight;
    const float normal[4] = {0.85f, 0.95f, 0.78f, 1}, active[4] = {1, 0.8f, 0.25f, 1};
    int i, owned[DK_WEAPON_COUNT], count = 0, selected = 0;
    char text[160];
    if (player->dk3CameraActive) return;
    if (scale < 0.7f) scale = 0.7f;
    if (!font.shader) DK_LoadNamedFont(&font, "statbar_font");
    if (cgs.gametype == GT_SINGLE_PLAYER) {
        int level = player->dk3Level > 0 ? player->dk3Level : 1;
        int lower = DK_ExperienceThreshold(level - 1), upper = DK_ExperienceThreshold(level);
        int progress = level >= 25 ? 10 : (int)Com_Clamp(0, 10, 10.0f * (player->dk3Experience - lower) / (upper - lower));
        for (i = 0; i < 5; ++i) {
            float x = 0, y = bottom - (268 - i * 36) * scale;
            DK_Text(&font, x, y - 6 * scale, scale * font.height / 16.0f, attributeLabels[i],
                player->dk3AttributePoints > 0 && i == attributeChoice ? active : normal);
            Picture(x, y + 9 * scale, 64 * scale, 32 * scale, "skill_window", 0.7f);
            Nodules(x + 9 * scale, y + 16 * scale, DK_Attribute(player, i, cg.time), 5, scale);
            if (player->dk3AttributePoints > 0 && i == attributeChoice && (cg.time / 400) % 2)
                Picture(x, y + 9 * scale, 64 * scale, 32 * scale, "selec_skill", 1);
        }
        /* The experience meter sits beside LEVEL in the lower status bar. */
        for (i = 0; i < 10; ++i) {
            const float dim[4] = {0.1f, 0.2f, 0.05f, 0.7f}, lit[4] = {0.25f, 1, 0, 1};
            trap_R_SetColor(i < progress ? lit : dim);
            trap_R_DrawStretchPic(center + 142 * scale, bottom - (8 + i * 3) * scale,
                6 * scale, 2 * scale, 0, 0, 1, 1, cgs.media.whiteShader);
        }
        trap_R_SetColor(NULL);
    }
    for (i = 1; i < DK_WEAPON_COUNT; ++i) if (DK_HasWeapon(player, i) && i != DK_W_FLASHLIGHT) {
        if (i == cg.weaponSelect) selected = count;
        owned[count++] = i;
    }
    {
        int first = selected / 6 * 6;
        float x = cgs.glconfig.vidWidth - 88 * scale;
        for (i = first; i < first + 6; ++i) {
            float y = (16 + (i - first) * 61) * scale;
            Picture(x, y, 128 * scale, 128 * scale, "weapn_win", 0.7f);
            if (i < count) {
                int weapon = owned[i];
                const char *model = weapon == DK_W_DISRUPTOR ? dk_weapons[weapon].model : DK_WeaponWorldModel(weapon);
                Model(x + 8 * scale, y + 10 * scale, 73 * scale, 39 * scale, model);
                if (i == selected) Picture(x, y, 128 * scale, 128 * scale, "selec_weapn", 0.7f);
                if (weapon == DK_W_GASHANDS) Com_sprintf(text, sizeof(text), "%ds", (player->powerups[PW_DK3_GASHANDS] - cg.time + 999) / 1000);
                else if (dk_weapons[weapon].ammoMax) Com_sprintf(text, sizeof(text), "%d", player->ammo[weapon]);
                else text[0] = 0;
                DK_Text(&font, x + 48 * scale, y + 50 * scale, scale * 0.65f, text, normal);
            }
        }
        if (cg.time - cg.weaponSelectTime < WEAPON_SELECT_TIME && selected < count)
            DK_Text(&font, center - DK_TextWidth(&font, dk_weapons[owned[selected]].label, scale) * 0.5f,
                bottom - 155 * scale, scale, dk_weapons[owned[selected]].label, active);
    }
    if (inventoryOpen) {
        int keys[DK_KEY_COUNT], keyCount = 0, first;
        float x = 20 * scale, y = 140 * scale;
        for (i = 0; i < DK_KEY_COUNT; ++i) if ((unsigned int)player->dk3Keys & (1u << i)) keys[keyCount++] = i;
        if (itemChoice >= keyCount) itemChoice = 0;
        first = itemChoice / 3 * 3;
        Picture(x, y, 80 * scale, 320 * scale, "inv_window2", 0.85f);
        for (i = first; i < keyCount && i < first + 3; ++i) {
            const char *name = DK_ItemModelName(dk_keyClasses[keys[i]]);
            float row = y + (17 + (i - first) * 83) * scale;
            if (name) Model(x + 7 * scale, row, 52 * scale, 45 * scale, va("models/%s.dkm", name));
            DK_Text(&font, x + 86 * scale, row + 16 * scale, scale * 0.75f, dk_keyLabels[keys[i]],
                i == itemChoice ? active : normal);
        }
        if (!keyCount) DK_Text(&font, x + 86 * scale, y + 30 * scale, scale * 0.75f, "No campaign items", normal);
        Com_sprintf(text, sizeof(text), "Save gems: %d", player->dk3SaveGems);
        DK_Text(&font, x, y - 28 * scale, scale * 0.8f, text, normal);
        Com_sprintf(text, sizeof(text), "Experience: %d    Skill points: %d", player->dk3Experience, player->dk3AttributePoints);
        DK_Text(&font, center - DK_TextWidth(&font, text, scale * 0.8f) * 0.5f, bottom - 180 * scale, scale * 0.8f, text, normal);
    }
}
