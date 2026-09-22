/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "cg_local.h"

typedef struct { float width, height, x, y; qhandle_t shader[2]; } spriteFrame_t;
typedef struct { char name[MAX_QPATH]; int count; spriteFrame_t frames[32]; } sprite_t;
static sprite_t sprites[128];
static int spriteCount;

static sprite_t *Load(const char *name) {
    char path[MAX_QPATH], text[16384], *cursor;
    fileHandle_t file;
    int i, length;
    sprite_t *sprite;
    for (i = 0; i < spriteCount; ++i) if (!Q_stricmp(sprites[i].name, name)) return &sprites[i];
    if (spriteCount == ARRAY_LEN(sprites)) CG_Error("dk3: sprite cache limit exceeded");
    sprite = &sprites[spriteCount++]; Q_strncpyz(sprite->name, name, sizeof(sprite->name));
    Com_sprintf(path, sizeof(path), "%s.frames", name);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 1 || length >= sizeof(text)) { if (file) trap_FS_FCloseFile(file); CG_Error("dk3: missing sprite metadata %s", path); }
    trap_FS_Read(text, length, file); trap_FS_FCloseFile(file); text[length] = 0; cursor = text;
    if (strcmp(COM_Parse(&cursor), "dk3_sprite") || strcmp(COM_Parse(&cursor), "1")) CG_Error("dk3: invalid sprite %s", path);
    sprite->count = atoi(COM_Parse(&cursor));
    if (sprite->count < 1 || sprite->count > ARRAY_LEN(sprite->frames)) CG_Error("dk3: invalid sprite frame count in %s", path);
    for (i = 0; i < sprite->count; ++i) {
        spriteFrame_t *frame = &sprite->frames[i];
        frame->width = atof(COM_Parse(&cursor)); frame->height = atof(COM_Parse(&cursor));
        frame->x = atof(COM_Parse(&cursor)); frame->y = atof(COM_Parse(&cursor));
        frame->shader[0] = trap_R_RegisterShader(COM_Parse(&cursor)); frame->shader[1] = trap_R_RegisterShader(COM_Parse(&cursor));
        if (!cursor || frame->width <= 0 || frame->height <= 0 || frame->width > 8192 || frame->height > 8192)
            CG_Error("dk3: invalid sprite dimensions in %s", path);
    }
    return sprite;
}

qboolean DK_DrawSpriteAt(const char *name, int index, const vec3_t origin, const vec3_t angles,
                         float scale, float alpha, const vec3_t color, int flags) {
    sprite_t *sprite;
    spriteFrame_t *frame;
    polyVert_t vertices[4];
    vec3_t right, up, axes[3];
    if (scale <= 0) scale = 1;
    const float uv[4][2] = {{0, 1}, {1, 1}, {1, 0}, {0, 0}};
    int i;
    if (Q_stricmp(COM_GetExtension(name), "sp2")) return qfalse;
    sprite = Load(name);
    if (flags & DK_SPRITE_CLAMP) index = (int)Com_Clamp(0, sprite->count - 1, index);
    frame = &sprite->frames[(unsigned int)index % sprite->count];
    if (flags & DK_SPRITE_ORIENTED) AnglesToAxis(angles, axes);
    else AxisCopy(cg.refdef.viewaxis, axes);
    VectorScale(axes[1], -1, right); VectorCopy(axes[2], up);
    memset(vertices, 0, sizeof(vertices));
    for (i = 0; i < 4; ++i) {
        float horizontal = (uv[i][0] * frame->width - frame->x) * scale;
        float vertical = ((1 - uv[i][1]) * frame->height - frame->y) * scale;
        VectorMA(origin, horizontal, right, vertices[i].xyz);
        VectorMA(vertices[i].xyz, vertical, up, vertices[i].xyz);
        vertices[i].st[0] = uv[i][0]; vertices[i].st[1] = uv[i][1];
        { int axis; for (axis = 0; axis < 3; ++axis) vertices[i].modulate[axis] = Com_Clamp(0, 1, color[axis]) * 255; }
        vertices[i].modulate[3] = Com_Clamp(0, 1, alpha) * 255;
    }
    trap_R_AddPolyToScene(frame->shader[(flags & DK_SPRITE_ADDITIVE) != 0], 4, vertices);
    return qtrue;
}

qboolean DK_DrawSprite(centity_t *entity) {
    vec3_t color = {1, 1, 1};
    if (entity->currentState.eType == ET_DK3_EFFECT) VectorCopy(entity->currentState.dk3EffectColor, color);
    return DK_DrawSpriteAt(CG_ConfigString(CS_MODELS + entity->currentState.modelindex), entity->currentState.frame,
        entity->lerpOrigin, entity->lerpAngles, entity->currentState.dk3Scale, entity->currentState.dk3Alpha,
        color, entity->currentState.dk3RenderFlags);
}
