/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Original dk3 menus. Artwork and glyphs come only from supplied game assets. */
#include "ui_local.h"
#include "dk_multiplayer.h"
#include "../shared/dk_font.h"
#include "../shared/dk_loading.h"

static dkFont_t font, brightFont, buttonFont;
static glconfig_t display;
static qhandle_t white;
static qboolean active, menuMusic;
static int page, selected, binding = -1, conflict = -1;
static float cursorX = 320, cursorY = 240, scale, offsetX, offsetY;
static char feedback[160], address[128] = "localhost";
static char errorText[2048];
static int errorScroll;
static qboolean editingAddress, stripFocus, keyboardFocus;
static const char *editingCvar;
static char editValue[256];
static int onlineRow, roomPlayers[MAX_CLIENTS], roomPlayerCount, voteTarget;
static void EditOnline(const char *name) {
    editingCvar = name;
    trap_Cvar_VariableStringBuffer(name, editValue, sizeof(editValue));
    Q_strncpyz(feedback, "Type a value; Enter saves, Escape cancels.", sizeof(feedback));
}
static void RoomPlayers(void) {
    int i;
    char info[MAX_INFO_STRING];
    roomPlayerCount = 0;
    for (i = 0; i < MAX_CLIENTS; ++i) {
        trap_GetConfigString(CS_PLAYERS + i, info, sizeof(info));
        if (*Info_ValueForKey(info, "n")) roomPlayers[roomPlayerCount++] = i;
    }
}
static int plate, panelPlate, uiTime, previousUiTime;
static qboolean cursorInPanel;
static char saveNames[128][48];
static int saveCount;
static float platePose[14];
static int hoveredPlate = -1;
static const char *const plateSkins[] = {"singleplay", "multi", "loadgame", "savegame", "sound", "video", "mouse",
    "keyboard", "joystick", "options", "config", "credits", "resume", "quit"};
static int firstRow, mode, mapChoice, slots = 8, botCount = 3, botSkill = 3, serverSource;
typedef struct { float x, y, width, height; int row, setting, kind; } widget_t;
static widget_t widgets[160];
static int widgetCount, hoveredWidget = -1, draggingWidget = -1;
enum { WIDGET_BUTTON, WIDGET_SLIDER, WIDGET_SELECT };
enum { SETTING_BRIGHTNESS = 12 };
typedef struct { char name[48], label[100]; int modes; } map_t;
static map_t maps[512];
static int mapCount;
static const char *modeNames[] = {"Deathmatch", "Capture the flag", "Deathtag"};
static const int gameTypes[] = {0, 4, 8};
static const float normal[4] = {0.8f, 0.85f, 0.9f, 1};
static const float accent[4] = {1, 0.8f, 0.3f, 1};
static const char *labels[] = {"Start campaign (development)", "Resume", "Save / load", "Controls", "Video / audio / gameplay", "Multiplayer", "Console", "Quit"};
static const char *controlLabels[] = {"Forward", "Back", "Left", "Right", "Jump / climb", "Crouch", "Attack", "Walk", "Next weapon", "Previous weapon", "Use", "Inventory", "Next inventory item", "Previous inventory item", "Quicksave", "Quickload", "Companions follow", "Companions wait", "Companions attack", "Companions pickup", "Next attribute", "Increase attribute", "Detonate C4", "Show scores (hold)"};
static const char *commands[] = {"+forward", "+back", "+moveleft", "+moveright", "+moveup", "+movedown", "+attack", "+speed", "weapnext", "weapprev", "use", "inventory", "invnext", "invprev", "save quick", "load quick", "companion follow", "companion wait", "companion attack", "companion pickup", "attribute_next", "attribute_increase", "detonate", "+scores"};

void QDECL Com_Printf(const char *format, ...) {
    va_list args;
    char text[2048];
    va_start(args, format); Q_vsnprintf(text, sizeof(text), format, args); va_end(args);
    trap_Print(text);
}

void QDECL Com_Error(int level, const char *format, ...) {
    va_list args;
    char text[2048];
    (void)level;
    va_start(args, format); Q_vsnprintf(text, sizeof(text), format, args); va_end(args);
    trap_Error(text);
}

static void Layout(void) {
    trap_GetGlconfig(&display);
    scale = display.vidWidth / 640.0f;
    if (display.vidHeight / 480.0f < scale) scale = display.vidHeight / 480.0f;
    if (scale <= 0) scale = 1;
    offsetX = (display.vidWidth - 640 * scale) / 2;
    offsetY = (display.vidHeight - 480 * scale) / 2;
}

static void Text(float x, float y, const char *text, qboolean highlight) {
    const float ink[4] = {1, 1, 1, 1};
    const dkFont_t *face = highlight ? &brightFont : &font;
    DK_Text(face, offsetX + x * scale, offsetY + y * scale, scale * face->height / 16.0f, text, ink);
}

static void Widget(float x, float y, float width, float height, int row, int setting, int kind) {
    widget_t *item;
    if (widgetCount == ARRAY_LEN(widgets)) return;
    item = &widgets[widgetCount++];
    item->x = x; item->y = y; item->width = width; item->height = height;
    item->row = row; item->setting = setting; item->kind = kind;
}

static void Glyph(float x, float y, unsigned char symbol) {
    float width = buttonFont.metrics[12 + symbol], sx = buttonFont.metrics[268 + symbol];
    float sy = buttonFont.metrics[524 + symbol];
    trap_R_SetColor(NULL);
    trap_R_DrawStretchPic(offsetX + x * scale, offsetY + y * scale, width * scale, buttonFont.height * scale,
        sx / buttonFont.width, sy / buttonFont.imageHeight, (sx + width) / buttonFont.width,
        (sy + buttonFont.height) / buttonFont.imageHeight, buttonFont.shader);
}

static void Border(float x, float y, float width, float height) {
    const float red[4] = {0.7f, 0, 0, 1};
    trap_R_SetColor(red);
    trap_R_DrawStretchPic(offsetX + x * scale, offsetY + y * scale, width * scale, scale, 0, 0, 1, 1, white);
    trap_R_DrawStretchPic(offsetX + x * scale, offsetY + (y + height) * scale, width * scale, scale, 0, 0, 1, 1, white);
    trap_R_DrawStretchPic(offsetX + x * scale, offsetY + y * scale, scale, height * scale, 0, 0, 1, 1, white);
    trap_R_DrawStretchPic(offsetX + (x + width) * scale, offsetY + y * scale, scale, height * scale, 0, 0, 1, 1, white);
    trap_R_SetColor(NULL);
}

static void Button(float x, float y, const char *label, int row) {
    float width = DK_TextWidth(&font, label, font.height / 16.0f);
    Glyph(x, y, 5);
    Text(x + (105 - width) * 0.5f, y + (20 - font.height) * 0.5f, label,
        !stripFocus && selected == row && (keyboardFocus || hoveredWidget >= 0));
    Widget(x, y, 105, 20, row, -1, WIDGET_BUTTON);
}

static const char *SliderCvar(int setting) {
    switch (setting) {
    case 3: return "cg_hudScale";
    case 5: return "cg_subtitleScale";
    case 6: return "s_volume";
    case 7: return "s_musicvolume";
    case SETTING_BRIGHTNESS: return "r_gamma";
    default: return "sensitivity";
    }
}

static void SliderRange(int setting, float *minimum, float *maximum) {
    *minimum = 0; *maximum = 1;
    if (setting == 3 || setting == 5) { *minimum = 0.75f; *maximum = 1.5f; }
    else if (setting == 8) { *minimum = 0.5f; *maximum = 10; }
    else if (setting == SETTING_BRIGHTNESS) { *minimum = 0.5f; *maximum = 3; }
}

static void Slider(float x, float y, const char *label, int row, int setting) {
    float minimum, maximum, value = trap_Cvar_VariableValue(SliderCvar(setting));
    char text[32];
    y -= 3; /* Align the supplied glyphs with the 1.3 label/track baseline. */
    SliderRange(setting, &minimum, &maximum);
    Text(x, y, label, !stripFocus && selected == row);
    Glyph(x, y + 18, 10);
    Glyph(x + Com_Clamp(0, 1, (value - minimum) / (maximum - minimum)) * 183, y + 18, 11);
    Com_sprintf(text, sizeof(text), setting == 6 || setting == 7 ? "%.0f" : "%.2f",
        setting == 6 || setting == 7 ? value * 100 : value);
    Text(x + 211, y + 18, text, qfalse);
    Widget(x, y + 18, 203, 20, row, setting, WIDGET_SLIDER);
}

static void MoveSlider(const widget_t *item) {
    float minimum, maximum;
    SliderRange(item->setting, &minimum, &maximum);
    trap_Cvar_SetValue(SliderCvar(item->setting), minimum +
        Com_Clamp(0, 1, (cursorX - item->x - 10) / 183) * (maximum - minimum));
    if (item->setting == SETTING_BRIGHTNESS)
        Q_strncpyz(feedback, "Choose Apply to update brightness.", sizeof(feedback));
}

static void UpdateHover(void) {
    int i;
    hoveredWidget = -1; cursorInPanel = qfalse;
    stripFocus = cursorX >= 440 && cursorX < 640 && cursorY >= 58 && cursorY < 449;
    for (i = 0; i < widgetCount; ++i) {
        widget_t *item = &widgets[i];
        if (cursorX >= item->x && cursorX < item->x + item->width &&
            cursorY >= item->y && cursorY < item->y + item->height) {
            hoveredWidget = i; cursorInPanel = qtrue; stripFocus = qfalse;
            if (page != 3) selected = item->row;
            return;
        }
    }
    if (stripFocus) plate = (int)Com_Clamp(0, 13, (cursorY - 58) / (391.0f / 14));
}

static void LoadMaps(void) {
    static char text[100000];
    char *cursor, *token;
    fileHandle_t file;
    int length = trap_FS_FOpenFile("dk3/maps.cfg", &file, FS_READ);
    mapCount = 0;
    if (length < 1 || length >= sizeof(text)) { if (file) trap_FS_FCloseFile(file); return; }
    trap_FS_Read(text, length, file); trap_FS_FCloseFile(file); text[length] = 0; cursor = text;
    if (strcmp(COM_Parse(&cursor), "dk3_maps") || strcmp(COM_Parse(&cursor), "1")) return;
    while (*(token = COM_Parse(&cursor)) && mapCount < ARRAY_LEN(maps)) {
        map_t *map = &maps[mapCount++];
        const char *p;
        Q_strncpyz(map->name, token, sizeof(map->name));
        for (p = map->name; *p; ++p) if (!((*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9') || *p == '_' || *p == '-')) {
            mapCount = 0; return;
        }
        map->modes = atoi(COM_Parse(&cursor));
        Q_strncpyz(map->label, COM_Parse(&cursor), sizeof(map->label));
        if (!cursor) { mapCount = 0; return; }
    }
}

static void ChooseMap(int direction) {
    int i;
    if (!mapCount) { mapChoice = -1; return; }
    for (i = 0; i < mapCount; ++i) {
        mapChoice = (mapChoice + direction + mapCount) % mapCount;
        if (maps[mapChoice].modes & (1 << mode)) return;
    }
    mapChoice = -1;
}

static int SettingRow(int row) {
    static const int sound[] = {6, 7}, video[] = {0, 1, SETTING_BRIGHTNESS, 2}, mouse[] = {8, 9}, options[] = {3, 4, 5, 10};
    if (panelPlate == 4) return row < 0 ? ARRAY_LEN(sound) : sound[row];
    if (panelPlate == 5) return row < 0 ? ARRAY_LEN(video) : video[row];
    if (panelPlate == 6) return row < 0 ? ARRAY_LEN(mouse) : mouse[row];
    return row < 0 ? ARRAY_LEN(options) : options[row];
}

static const char *SelectedSave(void) {
    if (panelPlate == 3) return selected ? va("save%d", selected) : "quick";
    if (selected >= 3 && selected - 3 < saveCount) return saveNames[selected - 3];
    return selected == 1 ? "autosave" : "quick";
}

static void SaveDetails(void) {
    char text[1024], *cursor, *token, key[32], line[128], path[MAX_QPATH];
    fileHandle_t file;
    int length, y = 175;
    Com_sprintf(path, sizeof(path), "saves/%s.info%s", SelectedSave(), panelPlate != 3 && selected == 2 ? ".previous" : "");
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length <= 0 || length >= sizeof(text)) { if (file) trap_FS_FCloseFile(file); return; }
    trap_FS_Read(text, length, file); trap_FS_FCloseFile(file); text[length] = 0; cursor = text;
    if (strcmp(COM_Parse(&cursor), "dk3_save_info") || strcmp(COM_Parse(&cursor), "1")) return;
    while (*(token = COM_Parse(&cursor)) && y < 310) {
        Q_strncpyz(key, token, sizeof(key));
        token = COM_Parse(&cursor);
        Com_sprintf(line, sizeof(line), "%s: %s", key, token);
        if (!strcmp(key, "secrets")) { Q_strcat(line, sizeof(line), "/"); Q_strcat(line, sizeof(line), COM_Parse(&cursor)); }
        if (!strcmp(key, "actors")) { Q_strncpyz(line, "Actors remaining: ", sizeof(line)); Q_strcat(line, sizeof(line), COM_Parse(&cursor)); }
        Text(103, y, line, qfalse); y += 12;
    }
}

static void LoadSaveSlots(void) {
    char files[16384], *name;
    int count = trap_FS_GetFileList("saves", ".sav", files, sizeof(files)), i;
    saveCount = 0;
    for (i = 0, name = files; i < count && saveCount < ARRAY_LEN(saveNames); ++i) {
        char slot[48];
        int length = strlen(name), j;
        if (length > 4 && length - 4 < sizeof(slot) && !strcmp(name + length - 4, ".sav")) {
            memcpy(slot, name, length - 4); slot[length - 4] = 0;
            for (j = 0; slot[j]; ++j)
                if (!((slot[j] >= 'a' && slot[j] <= 'z') || (slot[j] >= '0' && slot[j] <= '9') || slot[j] == '_' || slot[j] == '-')) break;
            if (!slot[j] && strncmp(slot, "dk3-", 4) && strcmp(slot, "quick") && strcmp(slot, "autosave"))
                Q_strncpyz(saveNames[saveCount++], slot, sizeof(saveNames[0]));
        }
        name += length + 1;
    }
}

static int Rows(void) {
    int count;
    if (page == 9) return 4;
    if (page == 10) return 5;
    if (page == 11) return 2;
    if (page == 12) return 2;
    if (page == 13) return 2;
    if (page == 1) return ARRAY_LEN(commands) + 1;
    if (page == 2) return SettingRow(-1);
    if (page == 3) return panelPlate == 3 ? 9 : saveCount + 3;
    if (page == 4) return 11;
    if (page == 14) return 7 + (int)Com_Clamp(0, 128, trap_Cvar_VariableValue("dk3_roomCount"));
    if (page == 15) return 11;
    if (page == 16) return 6;
    if (page == 17) return 3;
    if (page == 18) { RoomPlayers(); return 5 + roomPlayerCount; }
    if (page == 19) return 6;
    if (page == 5) return 8;
    if (page == 6) return 6;
    if (page == 7) { count = trap_LAN_GetServerCount(serverSource); return 2 + (int)Com_Clamp(0, 128, count); }
    if (page == 8) return 5;
    return ARRAY_LEN(labels);
}

static qboolean ValidAddress(const char *text) {
    const char *p;
    if (!*text) return qfalse;
    for (p = text; *p; ++p) if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
        (*p >= '0' && *p <= '9') || strchr(".:-[]%_", *p))) return qfalse;
    return qtrue;
}

static void RefreshServers(void) {
    trap_LAN_ResetPings(serverSource); trap_LAN_MarkServerVisible(serverSource, -1, qtrue);
    if (serverSource == AS_LOCAL) trap_Cmd_ExecuteText(EXEC_APPEND, "localservers\n");
    Q_strncpyz(feedback, "Select a server to join. Refresh updates the list.", sizeof(feedback));
}

static void Close(void) {
    if (active) trap_S_StartLocalSound(trap_S_RegisterSound("sounds/menus/exit menu_001.wav", qfalse), CHAN_LOCAL_SOUND);
    if (menuMusic) {
        uiClientState_t state;
        trap_GetClientState(&state);
        if (state.connState < CA_ACTIVE) trap_S_StopBackgroundTrack();
        menuMusic = qfalse;
    }
    active = qfalse;
    trap_Key_SetCatcher(trap_Key_GetCatcher() & ~KEYCATCH_UI);
    trap_Key_ClearStates();
    trap_Cvar_Set("cl_paused", "0");
}

static qboolean InGame(void) {
    uiClientState_t state;
    trap_GetClientState(&state);
    return state.connState == CA_ACTIVE;
}

static void SelectPlate(int index) {
    if ((index == 3 || index == 12) && !InGame()) return;
    if (panelPlate != index) {
        trap_S_StartLocalSound(trap_S_RegisterSound("sounds/menus/600ms rotate descend_001.wav", qfalse), CHAN_LOCAL);
        trap_S_StartLocalSound(trap_S_RegisterSound("sounds/menus/600ms rotate ascend_001.wav", qfalse), CHAN_LOCAL_SOUND);
    }
    plate = panelPlate = index; selected = firstRow = 0;
    feedback[0] = 0; binding = -1; editingAddress = qfalse;
    hoveredWidget = draggingWidget = -1; widgetCount = 0;
    if (index == 12) { Close(); return; }
    if (index == 13) { page = 13; return; }
    if (index == 0) page = 9;
    else if (index == 1) page = 4;
    else if (index == 2 || index == 3) { page = 3; LoadSaveSlots(); }
    else if (index == 7) page = 1;
    else if (index == 8) page = 10;
    else if (index == 10) page = 11;
    else if (index == 11) page = 12;
    else page = 2;
}

static void MenuArt(void) {
    refdef_t scene;
    int i, hover = stripFocus && (keyboardFocus || cursorX >= 440) ? plate : -1;
    if (hover != hoveredPlate) {
        if (hover >= 0) trap_S_StartLocalSound(trap_S_RegisterSound("sounds/menus/button_003.wav", qfalse), CHAN_LOCAL_SOUND);
        hoveredPlate = hover;
    }
    for (i = 0; i < 6; ++i) {
        qhandle_t tile = trap_R_RegisterShaderNoMip(va("pics/interface/back%d%d.tga", i / 3, i % 3));
        float width = i % 3 == 2 ? 128 : 256, height = i / 3 ? 224 : 256;
        trap_R_DrawStretchPic(offsetX + i % 3 * 256 * scale, offsetY + i / 3 * 256 * scale,
            width * scale, height * scale, 0, 0, width / 256, height / 256, tile);
    }
    memset(&scene, 0, sizeof(scene));
    scene.x = offsetX; scene.y = offsetY; scene.width = 640 * scale; scene.height = 480 * scale;
    scene.fov_x = 40; scene.fov_y = atan(tan(20 * M_PI / 180) * 480 / 640) * 360 / M_PI;
    scene.time = uiTime; scene.rdflags = RDF_NOWORLDMODEL;
    AxisClear(scene.viewaxis); trap_R_ClearScene();
    for (i = 0; i < ARRAY_LEN(plateSkins); ++i) {
        refEntity_t button;
        vec3_t angles = {0, 210, 0};
        float goal = i == panelPlate ? 15 : i == hover ? 1 : 0;
        float step = Com_Clamp(0, 100, uiTime - previousUiTime) *
            (goal == 15 || platePose[i] > 1 ? 14 / 350.0f : 1 / 175.0f);
        int axis;
        if (platePose[i] < goal) platePose[i] = Com_Clamp(0, goal, platePose[i] + step);
        else if (platePose[i] > goal) platePose[i] = Com_Clamp(goal, 15, platePose[i] - step);
        memset(&button, 0, sizeof(button));
        button.reType = RT_MODEL;
        button.hModel = trap_R_RegisterModel("models/interface/ib_button.dkm.md3");
        button.customShader = trap_R_RegisterShaderNoMip(va("dkq3/menu/ib_%s", plateSkins[i]));
        VectorSet(button.origin, 35, -2.8f, 8.35f - 1.165f * i);
        AnglesToAxis(angles, button.axis);
        for (axis = 0; axis < 3; ++axis) VectorScale(button.axis[axis], 1.09f, button.axis[axis]);
        button.nonNormalizedAxes = qtrue;
        button.oldframe = (int)platePose[i]; button.frame = button.oldframe < 15 ? button.oldframe + 1 : 15;
        button.backlerp = 1 - (platePose[i] - button.oldframe);
        button.shaderRGBA[0] = button.shaderRGBA[1] = button.shaderRGBA[2] =
            ((i == 3 || i == 12) && !InGame()) ? 64 : 255;
        button.shaderRGBA[3] = 255;
        trap_R_AddRefEntityToScene(&button);
    }
    trap_R_RenderScene(&scene);
    previousUiTime = uiTime;
}

static void Activate(void) {
    if (page == 9) {
        if (selected < 3) {
            trap_Cvar_SetValue("g_spSkill", selected == 0 ? 1 : selected == 1 ? 3 : 5);
            page = selected = 0; Activate();
        } else SelectPlate(9);
        return;
    }
    if (page == 10) {
        const char *variables[] = {"in_joystick", "joy_threshold", "j_yaw", "j_pitch"};
        if (selected == 4) { Close(); trap_Cmd_ExecuteText(EXEC_APPEND, "in_restart\n"); }
        else if (!selected) trap_Cvar_SetValue(variables[0], !trap_Cvar_VariableValue(variables[0]));
        else if (selected == 1) {
            float value = trap_Cvar_VariableValue(variables[1]) + 0.05f;
            trap_Cvar_SetValue(variables[1], value > 0.31f ? 0.05f : value);
        } else trap_Cvar_SetValue(variables[selected], -trap_Cvar_VariableValue(variables[selected]));
        return;
    }
    if (page == 11) {
        trap_Cmd_ExecuteText(EXEC_APPEND, selected ? "exec dk3-user.cfg\n" : "writeconfig dk3-user.cfg\n");
        Q_strncpyz(feedback, selected ? "Configuration loaded." : "Configuration saved.", sizeof(feedback)); return;
    }
    if (page == 12) {
        if (selected) SelectPlate(0);
        else { Close(); trap_Cmd_ExecuteText(EXEC_APPEND, "map credits\n"); }
        return;
    }
    if (page == 13) {
        if (!selected) trap_Cmd_ExecuteText(EXEC_APPEND, "quit\n"); else SelectPlate(0);
        return;
    }
    if (page == 1) {
        if (selected == ARRAY_LEN(commands)) { SelectPlate(0); return; }
        binding = selected;
        conflict = -1;
        Q_strncpyz(feedback, "Press a key; Escape cancels.", sizeof(feedback));
    } else if (page == 2) {
        int setting = SettingRow(selected);
        if (setting == 0) trap_Cvar_SetValue("r_fullscreen", !trap_Cvar_VariableValue("r_fullscreen"));
        if (setting == 1) trap_Cvar_Set("r_mode", "-2");
        if (setting == 2) { Close(); trap_Cmd_ExecuteText(EXEC_APPEND, "vid_restart\n"); }
        if (setting == 3) { float value = trap_Cvar_VariableValue("cg_hudScale") + 0.1f; trap_Cvar_SetValue("cg_hudScale", value > 1.51f ? 0.75f : value); }
        if (setting == 4) trap_Cvar_SetValue("cg_subtitles", !trap_Cvar_VariableValue("cg_subtitles"));
        if (setting == 5) { float value = trap_Cvar_VariableValue("cg_subtitleScale") + 0.1f; trap_Cvar_SetValue("cg_subtitleScale", value > 1.51f ? 0.75f : value); }
        if (setting == 6) { float value = trap_Cvar_VariableValue("s_volume") + 0.1f; trap_Cvar_SetValue("s_volume", value > 1.01f ? 0 : value); }
        if (setting == 7) { float value = trap_Cvar_VariableValue("s_musicvolume") + 0.1f; trap_Cvar_SetValue("s_musicvolume", value > 1.01f ? 0 : value); }
        if (setting == 8) { float value = trap_Cvar_VariableValue("sensitivity") + 0.5f; trap_Cvar_SetValue("sensitivity", value > 10 ? 0.5f : value); }
        if (setting == 9) trap_Cvar_SetValue("m_pitch", -trap_Cvar_VariableValue("m_pitch"));
        if (setting == 10) {
            trap_Cvar_SetValue("cg_shinyWeapons", ((int)trap_Cvar_VariableValue("cg_shinyWeapons") + 1) % 3);
        }
        if (setting == 11) SelectPlate(0);
        if (setting == SETTING_BRIGHTNESS) {
            float value = trap_Cvar_VariableValue("r_gamma") + 0.1f;
            trap_Cvar_SetValue("r_gamma", value > 3.01f ? 0.5f : value);
            Q_strncpyz(feedback, "Choose Apply to update brightness.", sizeof(feedback));
        }
    } else if (page == 3) {
        qboolean writing = panelPlate == 3, previous = !writing && selected == 2;
        char slot[48];
        if (writing) Q_strncpyz(slot, selected ? va("save%d", selected) : "quick", sizeof(slot));
        else Q_strncpyz(slot, selected >= 3 ? saveNames[selected - 3] : selected == 1 ? "autosave" : "quick", sizeof(slot));
        if (InGame()) {
            Close(); trap_Cmd_ExecuteText(EXEC_APPEND, va("%s %s%s\n", writing ? "save" : "load", slot, previous ? " previous" : ""));
        } else if (writing) Q_strncpyz(feedback, "Start a campaign before saving.", sizeof(feedback));
        else {
            trap_Cvar_Set("g_gametype", "2"); trap_Cvar_Set("teampref", "auto");
            trap_Cmd_ExecuteText(EXEC_APPEND, va("dk3_loadmenu %s%s\n", slot, previous ? " previous" : ""));
        }
    } else if (page == 4) {
        if (selected == 0) { page = 14; trap_Cmd_ExecuteText(EXEC_APPEND, "dk3_online list\n"); }
        else if (selected == 1) { page = 15; mapChoice = -1; ChooseMap(1); }
        else if (selected == 2) { page = 5; mapChoice = -1; ChooseMap(1); }
        else if (selected == 3) page = 6;
        else if (selected == 4) page = 8;
        else if (selected == 5 || selected == 6) {
            char model[MAX_QPATH];
            int appearance;
            trap_Cvar_VariableStringBuffer("model", model, sizeof(model));
            appearance = DK_AppearanceNext(DK_AppearanceFind(model), selected == 5);
            trap_Cvar_Set("model", DK_AppearanceSelection(appearance));
            return;
        } else if (selected == 7) page = 18;
        else if (selected == 8) page = 16;
        else if (selected == 9) { Close(); trap_Cmd_ExecuteText(EXEC_APPEND, "disconnect\n"); return; }
        else SelectPlate(0);
        selected = 0;
    } else if (page == 14) {
        if (selected == 0) trap_Cmd_ExecuteText(EXEC_APPEND, "dk3_online list\n");
        else if (selected == 1) trap_Cvar_SetValue("ui_roomFilterMode", ((int)trap_Cvar_VariableValue("ui_roomFilterMode") + 2) % 4 - 1);
        else if (selected == 2) EditOnline("ui_roomFilterRegion");
        else if (selected == 3) EditOnline("ui_roomSearch");
        else if (selected == 4) trap_Cvar_SetValue("ui_roomAvailableOnly", !trap_Cvar_VariableValue("ui_roomAvailableOnly"));
        else if (selected == 5) trap_Cvar_SetValue("ui_roomFavoritesOnly", !trap_Cvar_VariableValue("ui_roomFavoritesOnly"));
        else if (selected == 6) { page = 4; selected = 0; }
        else { onlineRow = selected - 7; page = 17; selected = 0; }
    } else if (page == 15) {
        if (selected == 0) EditOnline("ui_roomName");
        else if (selected == 1) EditOnline("ui_roomRegion");
        else if (selected == 2) { mode = (mode + 1) % 3; mapChoice = -1; ChooseMap(1); }
        else if (selected == 3) ChooseMap(1);
        else if (selected == 4) { slots = slots >= 32 ? 2 : slots + 2; if (botCount >= slots) botCount = slots - 1; }
        else if (selected == 5) botCount = (botCount + 1) % slots;
        else if (selected == 6) botSkill = botSkill % 5 + 1;
        else if (selected == 7) trap_Cvar_SetValue("ui_roomPrivate", !trap_Cvar_VariableValue("ui_roomPrivate"));
        else if (selected == 8) EditOnline("ui_roomRotation");
        else if (selected == 10) { page = 4; selected = 0; }
        else if (selected == 9 && mapChoice >= 0) {
            trap_Cvar_Set("ui_roomMap", maps[mapChoice].name);
            trap_Cvar_SetValue("ui_roomMode", mode); trap_Cvar_SetValue("ui_roomSlots", slots);
            trap_Cvar_SetValue("ui_roomBots", botCount); trap_Cvar_SetValue("ui_roomSkill", botSkill);
            trap_Cmd_ExecuteText(EXEC_APPEND, "dk3_online create\n");
        }
    } else if (page == 16) {
        const char *settings[] = {"dk3_coordinator", "dk3_ca_file", "ui_privateRoom", "ui_roomCode"};
        if (selected < 4) EditOnline(settings[selected]);
        else if (selected == 4) trap_Cmd_ExecuteText(EXEC_APPEND, "dk3_online private\n");
        else { page = 4; selected = 0; }
    } else if (page == 17) {
        if (selected < 2) trap_Cmd_ExecuteText(EXEC_APPEND, va("dk3_online %s %d\n", selected ? "favorite" : "join", onlineRow));
        else { page = 14; selected = 0; }
    } else if (page == 18) {
        if (selected == 0) trap_Cmd_ExecuteText(EXEC_APPEND, "cmd ready\n");
        else if (selected == 1) EditOnline("ui_roomChat");
        else if (selected == 2) { page = 8; selected = 0; }
        else if (selected == 3) trap_Cmd_ExecuteText(EXEC_APPEND, "disconnect; dk3_online reconnect\n");
        else if (selected == 4) { page = 4; selected = 0; }
        else { voteTarget = roomPlayers[selected - 5]; page = 19; selected = 0; }
    } else if (page == 19) {
        if (selected == 0) trap_Cmd_ExecuteText(EXEC_APPEND, va("cmd callvote kick %d\n", voteTarget));
        else if (selected == 1) trap_Cmd_ExecuteText(EXEC_APPEND, "cmd vote yes\n");
        else if (selected == 2) trap_Cmd_ExecuteText(EXEC_APPEND, "cmd vote no\n");
        else if (selected == 3) trap_Cmd_ExecuteText(EXEC_APPEND, "cmd callvote map_restart\n");
        else if (selected == 4) trap_Cmd_ExecuteText(EXEC_APPEND, "cmd callvote nextmap\n");
        else { page = 18; selected = 0; }
    } else if (page == 8) {
        static const char *teams[] = {"auto", "red", "blue", "spectator"};
        uiClientState_t state;
        char info[MAX_INFO_STRING];
        if (selected == 4) { page = 4; selected = 0; return; }
        trap_GetClientState(&state);
        trap_GetConfigString(CS_SERVERINFO, info, sizeof(info));
        if (state.connState == CA_ACTIVE && atoi(Info_ValueForKey(info, "g_gametype")) == GT_SINGLE_PLAYER) {
            Q_strncpyz(feedback, "Team selection is available in multiplayer.", sizeof(feedback)); return;
        }
        trap_Cvar_Set("teampref", teams[selected]);
        if (state.connState == CA_ACTIVE) {
            Close(); trap_Cmd_ExecuteText(EXEC_APPEND, va("team %s\n", teams[selected]));
        } else Q_strncpyz(feedback, "Team preference saved for the next connection.", sizeof(feedback));
    } else if (page == 5) {
        if (selected == 0) { mode = (mode + 1) % 3; mapChoice = -1; ChooseMap(1); }
        else if (selected == 1) ChooseMap(1);
        else if (selected == 2) { slots = slots >= 32 ? 2 : slots + 2; if (botCount >= slots) botCount = slots - 1; }
        else if (selected == 3) botCount = (botCount + 1) % slots;
        else if (selected == 4) botSkill = botSkill % 5 + 1;
        else if (selected == 5) trap_Cvar_SetValue("g_friendlyFire", !trap_Cvar_VariableValue("g_friendlyFire"));
        else if (selected == 7) { page = 4; selected = 0; }
        else if (mapChoice < 0) Q_strncpyz(feedback, "No supplied map supports this mode. Rebuild assets.", sizeof(feedback));
        else {
            trap_Cvar_SetValue("g_gametype", gameTypes[mode]); trap_Cvar_SetValue("sv_maxclients", slots);
            trap_Cvar_SetValue("bot_minplayers", 0); trap_Cvar_Set("dk3_resume", "0"); trap_Cvar_Set("dk3_loadRequest", "");
            trap_Cvar_Set("g_spSkill", va("%d", botSkill));
            Close(); trap_Cmd_ExecuteText(EXEC_APPEND, va("map %s\n", maps[mapChoice].name));
            trap_Cmd_ExecuteText(EXEC_APPEND, va("set bot_minplayers %d\n", botCount + 1));
        }
    } else if (page == 6) {
        if (selected == 0) { editingAddress = qtrue; Q_strncpyz(feedback, "Enter a host or IP with optional port; Enter confirms.", sizeof(feedback)); }
        else if (selected == 1) {
            if (ValidAddress(address)) { Close(); trap_Cmd_ExecuteText(EXEC_APPEND, va("connect %s\n", address)); }
            else Q_strncpyz(feedback, "Enter a valid hostname or IP address.", sizeof(feedback));
        } else if (selected == 2 || selected == 3) {
            serverSource = selected == 2 ? AS_LOCAL : AS_FAVORITES; page = 7; selected = 0; RefreshServers();
        } else if (selected == 4) {
            if (ValidAddress(address)) {
                int result = trap_LAN_AddServer(AS_FAVORITES, address, address);
                trap_LAN_SaveCachedServers();
                Q_strncpyz(feedback, result < 0 ? "Favorites list is full." : result ? "Server added to favorites." : "Server is already a favorite.", sizeof(feedback));
            }
        } else { page = 4; selected = 0; }
    } else if (page == 7) {
        if (selected == 0) RefreshServers();
        else if (selected == 1) { page = 6; selected = 0; }
        else {
            char target[128];
            trap_LAN_GetServerAddressString(serverSource, selected - 2, target, sizeof(target));
            if (ValidAddress(target)) { Close(); trap_Cmd_ExecuteText(EXEC_APPEND, va("connect %s\n", target)); }
        }
    } else switch (selected) {
        case 0:
            trap_Cvar_Set("g_gametype", "2");
            trap_Cvar_Set("teampref", "auto");
            trap_Cvar_Set("dk3_entry", "");
            trap_Cvar_Set("dk3_travel", "");
            trap_Cvar_Set("dk3_resume", "0");
            trap_Cvar_Set("dk3_loadRequest", "");
            trap_Cvar_Set("dk3_mikiko_travel", "");
            trap_Cvar_Set("dk3_superfly_travel", "");
            Close(); trap_Cmd_ExecuteText(EXEC_APPEND, "map intro\n"); break;
        case 1: Close(); break;
        case 2: page = 3; selected = 0; break;
        case 3: page = 1; selected = 0; break;
        case 4: page = 2; selected = 0; break;
        case 5: page = 4; selected = 0; feedback[0] = 0; break;
        case 6: Close(); trap_Cmd_ExecuteText(EXEC_APPEND, "toggleconsole\n"); break;
        case 7: trap_Cmd_ExecuteText(EXEC_APPEND, "quit\n"); break;
    }
}

static void Key(int key, int down) {
    char previous[128], keyName[64];
    if (key == K_MOUSE1 && !down) draggingWidget = -1;
    if (!down || !active) return;
    if (key == K_MOUSE1) { keyboardFocus = qfalse; UpdateHover(); }
    else if (!(key & K_CHAR_FLAG)) keyboardFocus = qtrue;
    trap_Cvar_VariableStringBuffer("com_errorMessage", errorText, sizeof(errorText));
    if (*errorText) {
        if (key == K_ENTER || key == K_ESCAPE || key == K_MOUSE1) {
            trap_Cvar_Set("com_errorMessage", ""); errorText[0] = 0; errorScroll = 0;
        } else if (key == K_DOWNARROW || key == K_MWHEELDOWN) ++errorScroll;
        else if ((key == K_UPARROW || key == K_MWHEELUP) && errorScroll > 0) --errorScroll;
        return;
    }
    if (key == K_MOUSE1 && !stripFocus && !cursorInPanel) return;
    if (editingCvar) {
        size_t length = strlen(editValue);
        if (key == K_ENTER) {
            trap_Cvar_Set(editingCvar, editValue);
            if (!strcmp(editingCvar, "ui_roomChat")) trap_Cmd_ExecuteText(EXEC_APPEND, va("cmd say \"%s\"\n", editValue));
            editingCvar = NULL; feedback[0] = 0; return;
        }
        if (key == K_ESCAPE) { editingCvar = NULL; feedback[0] = 0; return; }
        if (key == K_BACKSPACE && length) editValue[length - 1] = 0;
        if ((key & K_CHAR_FLAG) && length < sizeof(editValue) - 1) {
            int ch = key & ~K_CHAR_FLAG;
            if (ch >= 32 && ch < 127 && ch != '"' && ch != '\\' && ch != ';') { editValue[length] = ch; editValue[length + 1] = 0; }
        }
        return;
    }
    if (editingAddress) {
        int length = strlen(address);
        if (key == K_ENTER || key == K_ESCAPE) { editingAddress = qfalse; feedback[0] = 0; return; }
        if (key == K_BACKSPACE && length) address[length - 1] = 0;
        if ((key & K_CHAR_FLAG) && length < sizeof(address) - 1) {
            char character[2] = {(char)(key & ~K_CHAR_FLAG), 0};
            if (ValidAddress(character)) { address[length] = character[0]; address[length + 1] = 0; }
        }
        return;
    }
    if (binding >= 0) {
        if (key == K_ESCAPE) { binding = -1; feedback[0] = 0; return; }
        if (key & K_CHAR_FLAG) return;
        trap_Key_GetBindingBuf(key, previous, sizeof(previous));
        if (*previous && Q_stricmp(previous, commands[binding]) && conflict != key) {
            conflict = key;
            trap_Key_KeynumToStringBuf(key, keyName, sizeof(keyName));
            Com_sprintf(feedback, sizeof(feedback), "%s: %s. Press again to replace.", keyName, previous);
            return;
        }
        trap_Key_SetBinding(key, commands[binding]);
        binding = -1; feedback[0] = 0;
        return;
    }
    if (key == K_MOUSE1 && !stripFocus && hoveredWidget >= 0 && hoveredWidget < widgetCount) {
        widget_t *item = &widgets[hoveredWidget];
        if (item->kind == WIDGET_SELECT) { selected = item->row; return; }
        if (item->kind == WIDGET_SLIDER) {
            MoveSlider(item); draggingWidget = hoveredWidget; return;
        }
    }
    if (key == K_LEFTARROW || key == K_RIGHTARROW) { stripFocus = key == K_RIGHTARROW; return; }
    if (stripFocus) {
        if (key == K_UPARROW || key == K_MWHEELUP) plate = (plate + 13) % 14;
        else if (key == K_DOWNARROW || key == K_MWHEELDOWN) plate = (plate + 1) % 14;
        else if (key == K_ENTER || key == K_MOUSE1) { SelectPlate(plate); stripFocus = qfalse; }
        else if (key == K_ESCAPE) { if (InGame()) Close(); else stripFocus = qfalse; }
        return;
    }
    if (key == K_ESCAPE) {
        if (InGame()) Close(); else { SelectPlate(0); selected = 1; }
    } else if (key == K_UPARROW) selected = (selected + Rows() - 1) % Rows();
    else if (key == K_MWHEELUP) selected = (selected + Rows() - 1) % Rows();
    else if (key == K_DOWNARROW || key == K_TAB || key == K_MWHEELDOWN) selected = (selected + 1) % Rows();
    else if (key == K_ENTER || key == K_MOUSE1) Activate();
}

static qboolean DrawError(void) {
    char wrapped[2304], *line, *next;
    float lineHeight = (font.height + 3) * 16.0f / font.height;
    int count, row = 0, visible = (int)(270 / lineHeight);
    trap_Cvar_VariableStringBuffer("com_errorMessage", errorText, sizeof(errorText));
    if (!*errorText) { errorScroll = 0; return qfalse; }
    count = DK_WrapText(&font, errorText, 1, 365, wrapped, sizeof(wrapped));
    errorScroll = (int)Com_Clamp(0, count > visible ? count - visible : 0, errorScroll);
    Text(60, 115, "Unable to continue", qtrue);
    for (line = wrapped; line; line = next, ++row) {
        next = strchr(line, '\n');
        if (next) *next++ = 0;
        if (row >= errorScroll && row < errorScroll + visible)
            Text(60, 150 + (row - errorScroll) * lineHeight, line, qfalse);
    }
    Text(60, 444, "Enter/Escape: dismiss    Up/Down: scroll", qtrue);
    return qtrue;
}

/* Layout measured from the private 1.3 captures. The controls and event handling
   use native UI services; only the supplied font/figure artwork is shared. */
static qboolean DrawPanel(void) {
    int i;
    if (page == 9) {
        static const char *const names[] = {"Ronin", "Samurai", "Shogun"};
        const float ink[4] = {1, 1, 1, 0.9f};
        Text(220, 130, "Select Difficulty:", qtrue);
        for (i = 0; i < 3; ++i) {
            trap_R_SetColor(ink);
            trap_R_DrawStretchPic(offsetX + (88 + i * 130) * scale, offsetY + 80 * scale,
                128 * scale, 256 * scale, 0, 0, 1, 1,
                trap_R_RegisterShaderNoMip(va("pics/menu/skill_%d.tga", i)));
            trap_R_SetColor(NULL);
            Button(100 + i * 130, 340, names[i], i);
        }
        Button(360, 390, "Extra Options", 3);
        return qtrue;
    }
    if (page == 2) {
        for (i = 0; i < Rows(); ++i) {
            int setting = SettingRow(i);
            float y = 130 + i * 60;
            const char *name = NULL;
            if (setting == 6) name = "Sound Effect Volume";
            if (setting == 7) name = "Music Volume";
            if (setting == 8) name = "Mouse Sensitivity";
            if (setting == 3) name = "HUD Size";
            if (setting == 5) name = "Subtitle Size";
            if (setting == SETTING_BRIGHTNESS) name = "Brightness";
            if (name) Slider(180, y, name, i, setting);
            else {
                char text[96];
                if (setting == 0) Com_sprintf(text, sizeof(text), "Fullscreen: %s", trap_Cvar_VariableValue("r_fullscreen") ? "On" : "Off");
                else if (setting == 1) Q_strncpyz(text, "Desktop Resolution", sizeof(text));
                else if (setting == 2) { Button(360, 390, "Apply", i); continue; }
                else if (setting == 4) Com_sprintf(text, sizeof(text), "Subtitles: %s", trap_Cvar_VariableValue("cg_subtitles") ? "On" : "Off");
                else if (setting == 9) Com_sprintf(text, sizeof(text), "Reverse Mouse: %s", trap_Cvar_VariableValue("m_pitch") < 0 ? "On" : "Off");
                else {
                    int shine = trap_Cvar_VariableValue("cg_shinyWeapons");
                    Com_sprintf(text, sizeof(text), "Shiny Weapons: %s", shine <= 0 ? "Off" : shine == 1 ? "On" : "Enhanced");
                }
                Text(180, y, text, selected == i && !stripFocus);
                Widget(175, y, 250, 22, i, setting, WIDGET_BUTTON);
            }
        }
        return qtrue;
    }
    if (page == 3) {
        qboolean writing = panelPlate == 3;
        int first = selected > 3 ? selected - 3 : 0;
        Text(100, 116, writing ? "Save Game" : "Load Game", qfalse);
        Text(100, 138, "Select a slot below", qfalse);
        Border(100, 160, 370, 1);
        trap_R_SetColor(NULL);
        {
            char path[MAX_QPATH]; fileHandle_t file; qhandle_t preview;
            Com_sprintf(path, sizeof(path), "screenshots/dk3-save-%s.jpg", SelectedSave());
            if ((panelPlate == 3 || selected != 2) && trap_FS_FOpenFile(path, &file, FS_READ) >= 0) { trap_FS_FCloseFile(file); preview = trap_R_RegisterShaderNoMip(path); }
            else preview = trap_R_RegisterShaderNoMip("pics/noscreen_avail.tga");
            trap_R_DrawStretchPic(offsetX + 335 * scale, offsetY + 170 * scale, 133 * scale, 100 * scale, 0, 0, 1, 1, preview);
            SaveDetails();
        }
        Border(334, 168, 135, 103);
        Button(363, 295, writing ? "Save Game" : "Load Game", selected);
        Border(100, 320, 370, 73);
        for (i = first; i < Rows() && i < first + 4; ++i) {
            char text[80];
            if (writing) Com_sprintf(text, sizeof(text), i ? "Save slot %d" : "Quick save", i);
            else if (i >= 3) Q_strncpyz(text, saveNames[i - 3], sizeof(text));
            else Q_strncpyz(text, i == 0 ? "Quick save" : i == 1 ? "Entry autosave" : "Previous quick save", sizeof(text));
            Text(105, 322 + (i - first) * 18, text, i == selected);
            Widget(101, 321 + (i - first) * 18, 368, 18, i, -1, WIDGET_SELECT);
        }
        return qtrue;
    }
    if (page == 1) {
        int first = selected > 13 ? selected - 13 : 0;
        Text(130, 110, "Action", qfalse); Text(330, 110, "Key", qfalse);
        Border(125, 130, 310, 263);
        for (i = first; i < Rows() && i < first + 14; ++i) {
            char name[64] = "--", bound[128];
            int k;
            if (i == ARRAY_LEN(commands)) { Button(100, 403, "Back", i); continue; }
            for (k = 0; k < 256; ++k) {
                trap_Key_GetBindingBuf(k, bound, sizeof(bound));
                if (!Q_stricmp(bound, commands[i])) { trap_Key_KeynumToStringBuf(k, name, sizeof(name)); break; }
            }
            Text(130, 133 + (i - first) * 18, controlLabels[i], selected == i);
            Text(350, 133 + (i - first) * 18, name, selected == i);
            Widget(126, 132 + (i - first) * 18, 308, 18, i, -1, WIDGET_BUTTON);
        }
        return qtrue;
    }
    return qfalse;
}

static void Draw(qboolean connecting) {
    int i;
    float background[4] = {0.025f, 0.04f, 0.05f, 0.96f};
    Layout();
    if (connecting) {
        char map[MAX_QPATH], serverInfo[MAX_INFO_STRING], screen[MAX_QPATH];
        trap_Cvar_VariableStringBuffer("dk3_loadingMap", map, sizeof(map));
        trap_GetConfigString(CS_SERVERINFO, serverInfo, sizeof(serverInfo));
        trap_GetConfigString(CS_DK3_LOADSCREEN, screen, sizeof(screen));
        if (!trap_Cvar_VariableValue("sv_running"))
            Q_strncpyz(map, Info_ValueForKey(serverInfo, "mapname"), sizeof(map));
        DK_LoadingScreen(map, !Q_stricmp(map, Info_ValueForKey(serverInfo, "mapname")) ? screen : NULL,
            trap_Cvar_VariableValue("dk3_loadingProgress"), display.vidWidth, display.vidHeight);
        return;
    }
    trap_R_SetColor(background);
    trap_R_DrawStretchPic(0, 0, display.vidWidth, display.vidHeight, 0, 0, 1, 1, white);
    trap_R_SetColor(NULL);
    MenuArt();
    Text(416, 412, "dk3 dev", qfalse);
    if (DrawError()) return;
    if (page == 7) trap_LAN_UpdateVisiblePings(serverSource);
    if (selected >= Rows()) selected = Rows() - 1;
    widgetCount = 0;
    if (DrawPanel()) goto overlay;
    firstRow = selected > 10 ? selected - 10 : 0;
    for (i = firstRow; i < Rows() && i < firstRow + 12; ++i) {
        const char *label;
        char line[160], keyName[64], bound[128];
        if (page == 1 && i < ARRAY_LEN(commands)) {
            int k;
            Q_strncpyz(keyName, "unbound", sizeof(keyName));
            for (k = 0; k < 256; ++k) {
                trap_Key_GetBindingBuf(k, bound, sizeof(bound));
                if (!Q_stricmp(bound, commands[i])) { trap_Key_KeynumToStringBuf(k, keyName, sizeof(keyName)); break; }
            }
            Com_sprintf(line, sizeof(line), "%s: %s", controlLabels[i], keyName);
            label = line;
        } else if (page == 1) label = "Back";
        else if (page == 2) {
            int setting = SettingRow(i);
            if (setting == 0) Q_strncpyz(line, "Toggle fullscreen", sizeof(line));
            else if (setting == 1) Q_strncpyz(line, "Use desktop resolution", sizeof(line));
            else if (setting == 2) Q_strncpyz(line, "Apply video settings", sizeof(line));
            else if (setting == 3) Com_sprintf(line, sizeof(line), "HUD size: %.2f", trap_Cvar_VariableValue("cg_hudScale"));
            else if (setting == 4) Com_sprintf(line, sizeof(line), "Subtitles: %s", trap_Cvar_VariableValue("cg_subtitles") ? "on" : "off");
            else if (setting == 5) Com_sprintf(line, sizeof(line), "Subtitle size: %.2f", trap_Cvar_VariableValue("cg_subtitleScale"));
            else if (setting == 6) Com_sprintf(line, sizeof(line), "Sound volume: %.0f%%", trap_Cvar_VariableValue("s_volume") * 100);
            else if (setting == 7) Com_sprintf(line, sizeof(line), "Music volume: %.0f%%", trap_Cvar_VariableValue("s_musicvolume") * 100);
            else if (setting == 8) Com_sprintf(line, sizeof(line), "Mouse sensitivity: %.1f", trap_Cvar_VariableValue("sensitivity"));
            else if (setting == 9) Com_sprintf(line, sizeof(line), "Invert mouse: %s", trap_Cvar_VariableValue("m_pitch") < 0 ? "on" : "off");
            else if (setting == SETTING_BRIGHTNESS) Com_sprintf(line, sizeof(line), "Brightness: %.2f (Apply to update)", trap_Cvar_VariableValue("r_gamma"));
            else if (setting == 10) {
                int shine = trap_Cvar_VariableValue("cg_shinyWeapons");
                Com_sprintf(line, sizeof(line), "Shiny weapons: %s", shine <= 0 ? "Off" : shine == 1 ? "On" : "Enhanced");
            }
            else Q_strncpyz(line, "Back", sizeof(line));
            label = line;
        } else if (page == 3) {
            if (panelPlate == 3) Com_sprintf(line, sizeof(line), i ? "Save slot %d" : "Quick save", i);
            else if (i >= 3) Q_strncpyz(line, saveNames[i - 3], sizeof(line));
            else Q_strncpyz(line, i == 0 ? "Quick load" : i == 1 ? "Load entry autosave" : "Recover previous quick save", sizeof(line));
            label = line;
        } else if (page == 4) {
            const char *multi[] = {"Internet rooms", "Create Internet room", "Host LAN game", "Join LAN game", "Choose team", "Character", "Skin", "Lobby / players", "Online settings / private room", "Disconnect", "Back"}; label = multi[i];
            if (i == 5 || i == 6) {
                char model[MAX_QPATH]; trap_Cvar_VariableStringBuffer("model", model, sizeof(model));
                Com_sprintf(line, sizeof(line), "%s: %s", multi[i], model); label = line;
            }
        } else if (page == 14) {
            if (i < 7) {
                const char *fields[] = {"Refresh", "Mode", "Region (empty: all)", "Search", "Available compatible rooms", "Favorites only", "Back"};
                const char *vars[] = {"", "", "ui_roomFilterRegion", "ui_roomSearch", "", "", ""};
                char value[128] = "";
                if (i == 1) { int filter = trap_Cvar_VariableValue("ui_roomFilterMode"); Q_strncpyz(value, filter < 0 ? "all" : modeNames[(int)Com_Clamp(0,2,filter)], sizeof(value)); }
                else if (i == 2 || i == 3) trap_Cvar_VariableStringBuffer(vars[i], value, sizeof(value));
                else if (i == 4 || i == 5) Q_strncpyz(value, trap_Cvar_VariableValue(i == 4 ? "ui_roomAvailableOnly" : "ui_roomFavoritesOnly") ? "yes" : "no", sizeof(value));
                Com_sprintf(line, sizeof(line), "%s%s%s", fields[i], *value ? ": " : "", value);
            } else {
                char info[MAX_INFO_STRING], name[80], map[48], region[48], ping[24];
                trap_Cvar_VariableStringBuffer(va("dk3_room%d", i - 7), info, sizeof(info));
                Q_strncpyz(name, Info_ValueForKey(info, "name"), sizeof(name)); Q_strncpyz(map, Info_ValueForKey(info, "map"), sizeof(map));
                Q_strncpyz(region, Info_ValueForKey(info, "region"), sizeof(region));
                Q_strncpyz(ping, Info_ValueForKey(info, "ping"), sizeof(ping));
                Com_sprintf(line, sizeof(line), "%s | %s | %s | %s | %s", name, map, region, Info_ValueForKey(info, "players"), ping);
            }
            label = line;
        } else if (page == 15) {
            char value[128];
            if (i == 0 || i == 1) { trap_Cvar_VariableStringBuffer(i ? "ui_roomRegion" : "ui_roomName", value, sizeof(value)); Com_sprintf(line,sizeof(line),"%s: %s",i ? "Region" : "Room name",value); }
            else if (i == 2) Com_sprintf(line,sizeof(line),"Mode: %s",modeNames[mode]);
            else if (i == 3) Com_sprintf(line,sizeof(line),"Map: %s",mapChoice >= 0 ? maps[mapChoice].label : "none available");
            else if (i == 4) Com_sprintf(line,sizeof(line),"Player slots: %d",slots);
            else if (i == 5) Com_sprintf(line,sizeof(line),"Bots: %d",botCount);
            else if (i == 6) Com_sprintf(line,sizeof(line),"Bot skill: %d / 5",botSkill);
            else if (i == 7) Com_sprintf(line,sizeof(line),"Privacy: %s",trap_Cvar_VariableValue("ui_roomPrivate") ? "private" : "public");
            else if (i == 8) { trap_Cvar_VariableStringBuffer("ui_roomRotation",value,sizeof(value)); Com_sprintf(line,sizeof(line),"Next maps: %s", *value ? value : "repeat current map"); }
            else Q_strncpyz(line,i == 9 ? "Create room and join" : "Back",sizeof(line));
            label = line;
        } else if (page == 16) {
            const char *fields[] = {"Coordinator HTTPS URL", "Trusted test CA (optional)", "Private room ID", "Private room code", "Join private room", "Back"};
            const char *vars[] = {"dk3_coordinator", "dk3_ca_file", "ui_privateRoom", "ui_roomCode"};
            char value[128] = "";
            if (i < 4) trap_Cvar_VariableStringBuffer(vars[i],value,sizeof(value));
            Com_sprintf(line,sizeof(line),"%s%s%s",fields[i],*value ? ": " : "",value); label=line;
        } else if (page == 17) {
            const char *actions[] = {"Join selected room", "Toggle favorite", "Back"}; label=actions[i];
        } else if (page == 18) {
            if (i < 5) { const char *actions[] = {"Toggle ready", "Send lobby chat", "Choose team / spectate", "Reconnect to Internet room", "Back"}; label=actions[i]; }
            else { char info[MAX_INFO_STRING]; trap_GetConfigString(CS_PLAYERS+roomPlayers[i-5],info,sizeof(info)); Com_sprintf(line,sizeof(line),"Player %d: %s",roomPlayers[i-5],Info_ValueForKey(info,"n")); label=line; }
        } else if (page == 19) {
            const char *actions[] = {"Vote to kick selected player", "Vote yes", "Vote no", "Vote to restart map", "Vote next map", "Back"}; label=actions[i];
        } else if (page == 8) {
            const char *teams[] = {"Join balanced team", "Join red", "Join blue", "Spectate", "Back"}; label = teams[i];
        } else if (page == 5) {
            switch (i) {
                case 0: Com_sprintf(line, sizeof(line), "Mode: %s", modeNames[mode]); break;
                case 1: Com_sprintf(line, sizeof(line), "Map: %s", mapChoice >= 0 ? maps[mapChoice].label : "none available"); break;
                case 2: Com_sprintf(line, sizeof(line), "Player slots: %d", slots); break;
                case 3: Com_sprintf(line, sizeof(line), "Bots: %d", botCount); break;
                case 4: Com_sprintf(line, sizeof(line), "Bot skill: %d / 5", botSkill); break;
                case 5: Com_sprintf(line, sizeof(line), "Friendly fire: %s", trap_Cvar_VariableValue("g_friendlyFire") ? "on" : "off"); break;
                default: Q_strncpyz(line, i == 6 ? "Start server" : "Back", sizeof(line)); break;
            }
            label = line;
        } else if (page == 6) {
            const char *join[] = {"", "Connect", "Find LAN servers", "Favorite servers", "Add address to favorites", "Back"};
            Com_sprintf(line, sizeof(line), "Address: %s%s", address, editingAddress ? "_" : ""); label = i ? join[i] : line;
        } else if (page == 7) {
            if (i < 2) label = i ? "Back" : "Refresh";
            else {
                char info[MAX_INFO_STRING], hostname[80], map[48];
                trap_LAN_GetServerInfo(serverSource, i - 2, info, sizeof(info));
                Q_strncpyz(hostname, Info_ValueForKey(info, "hostname"), sizeof(hostname));
                Q_strncpyz(map, Info_ValueForKey(info, "mapname"), sizeof(map));
                Com_sprintf(line, sizeof(line), "%s  %s  %s ms", hostname, map, Info_ValueForKey(info, "ping")); label = line;
            }
        } else if (page == 9) {
            const char *difficulty[] = {"Easy", "Normal", "Hard", "Game options"}; label = difficulty[i];
        } else if (page == 10) {
            const char *controls[] = {"Controller", "Dead zone", "Reverse horizontal axis", "Reverse vertical axis", "Apply controller settings"};
            if (i == 0) Com_sprintf(line, sizeof(line), "%s: %s", controls[i], trap_Cvar_VariableValue("in_joystick") ? "on" : "off");
            else if (i == 1) Com_sprintf(line, sizeof(line), "%s: %.2f", controls[i], trap_Cvar_VariableValue("joy_threshold"));
            else Q_strncpyz(line, controls[i], sizeof(line));
            label = line;
        } else if (page == 11) label = i ? "Load saved controls and settings" : "Save controls and settings";
        else if (page == 12) {
            label = i ? "Back" : "Play supplied credits";
        } else if (page == 13) label = i ? "Return to menu" : "Quit game";
        else label = labels[i];
        {
            float textScale = scale, width = DK_TextWidth(&font, label, textScale);
            if (width > 320 * scale) textScale *= 320 * scale / width;
            DK_Text(&font, offsetX + 105 * scale, offsetY + (130 + (i - firstRow) * 24) * scale,
                textScale, label, !stripFocus && selected == i ? accent : normal);
            Widget(100, 130 + (i - firstRow) * 24, 340, 24, i, -1, WIDGET_BUTTON);
        }
    }
overlay:
    if (editingCvar) { char line[280]; Com_sprintf(line, sizeof(line), "%s_", editValue); Text(105, 403, line, qtrue); }
    if (page >= 14 && page <= 17 && !editingCvar) trap_Cvar_VariableStringBuffer("dk3_onlineStatus", feedback, sizeof(feedback));
    Text(105, 425, feedback, qtrue);
    trap_R_SetColor(NULL);
    trap_R_DrawStretchPic(offsetX + (cursorX - 6) * scale, offsetY + (cursorY - 8) * scale, 32 * scale, 32 * scale,
        0, 0, 1, 1, trap_R_RegisterShaderNoMip(va("pics/interface/cursor_%02d.tga", 1 + (uiTime / 45) % 9)));
}

Q_EXPORT intptr_t vmMain(int command, int arg0, int arg1, int arg2, int arg3, int arg4,
                        int arg5, int arg6, int arg7, int arg8, int arg9, int arg10, int arg11) {
    (void)arg2; (void)arg3; (void)arg4; (void)arg5; (void)arg6; (void)arg7; (void)arg8;
    (void)arg9; (void)arg10; (void)arg11;
    switch (command) {
        case UI_GETAPIVERSION: return UI_API_VERSION;
        case UI_INIT:
            /* Upgrade pre-scoreboard profiles once; preserve custom bindings and
               allow players to unbind Tab afterward without restoring it. */
            trap_Cvar_Register(NULL, "ui_scoreBindingVersion", "0", CVAR_ARCHIVE);
            if (trap_Cvar_VariableValue("ui_scoreBindingVersion") < 1) {
                char tabBinding[128];
                trap_Key_GetBindingBuf(K_TAB, tabBinding, sizeof(tabBinding));
                if (!*tabBinding) trap_Key_SetBinding(K_TAB, "+scores");
                trap_Cvar_Set("ui_scoreBindingVersion", "1");
            }
            trap_Cvar_Register(NULL, "teampref", "auto", CVAR_ARCHIVE | CVAR_USERINFO);
            trap_Cvar_Register(NULL, "cg_shinyWeapons", "1", CVAR_ARCHIVE);
            trap_Cvar_Register(NULL, "cg_hudScale", "1", CVAR_ARCHIVE);
            trap_Cvar_Register(NULL, "cg_subtitleScale", "1", CVAR_ARCHIVE);
            trap_Cvar_Register(NULL, "cg_subtitles", "1", CVAR_ARCHIVE);
            trap_Cvar_Register(NULL, "g_spSkill", "3", CVAR_ARCHIVE);
            LoadMaps(); trap_LAN_LoadCachedServers(); Layout(); DK_LoadNamedFont(&font, "int_font");
            DK_LoadNamedFont(&brightFont, "int_font_bright"); DK_LoadNamedFont(&buttonFont, "int_buttons");
            white = trap_R_RegisterShaderNoMip("white"); return 0;
        case UI_SHUTDOWN: trap_LAN_SaveCachedServers(); Close(); return 0;
        case UI_IS_FULLSCREEN: return active;
        case UI_SET_ACTIVE_MENU:
            keyboardFocus = qfalse; hoveredWidget = draggingWidget = -1;
            if (arg0 == UIMENU_NONE) Close();
            else {
                if (!active) trap_S_StartLocalSound(trap_S_RegisterSound("sounds/menus/enter menu_001.wav", qfalse), CHAN_LOCAL_SOUND);
                memset(platePose, 0, sizeof(platePose)); platePose[0] = 15; hoveredPlate = -1;
                active = qtrue; page = 9; selected = 1; panelPlate = 0; plate = InGame() ? 12 : 0; stripFocus = InGame(); trap_Cvar_Set("cl_paused", trap_Cvar_VariableValue("sv_running") && trap_Cvar_VariableValue("g_gametype") == 2 ? "1" : "0"); trap_Key_SetCatcher(trap_Key_GetCatcher() | KEYCATCH_UI);
            }
            return 0;
        case UI_KEY_EVENT: Key(arg0, arg1); return 0;
        case UI_MOUSE_EVENT:
            /* ioquake3 may deliver a zero delta while the pointer is still.
               That must not cancel keyboard navigation on every frame. */
            if (!arg0 && !arg1) return 0;
            keyboardFocus = qfalse;
            cursorX = Com_Clamp(0, 640, cursorX + arg0 / scale);
            cursorY = Com_Clamp(0, 480, cursorY + arg1 / scale);
            if (draggingWidget >= 0 && draggingWidget < widgetCount) MoveSlider(&widgets[draggingWidget]);
            UpdateHover();
            return 0;
        case UI_REFRESH:
            uiTime = arg0;
            if (active) {
                uiClientState_t state;
                trap_GetClientState(&state);
                if (!menuMusic && state.connState == CA_DISCONNECTED) {
                    trap_S_StartBackgroundTrack("music/menu_01.mp3.ogg", "music/menu_02.mp3.ogg");
                    menuMusic = qtrue;
                } else if (menuMusic && state.connState != CA_DISCONNECTED) {
                    if (state.connState < CA_ACTIVE) trap_S_StopBackgroundTrack();
                    menuMusic = qfalse;
                }
                Draw(qfalse);
            }
            return 0;
        case UI_DRAW_CONNECT_SCREEN: Draw(qtrue); return 0;
        case UI_CONSOLE_COMMAND: return qfalse;
        case UI_HASUNIQUECDKEY: return qfalse;
    }
    return -1;
}
