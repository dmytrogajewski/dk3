/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "cg_local.h"
#include "dk_multiplayer.h"

#define DK_MODEL_CACHE 64
#define DK_MODEL_SEQUENCES 256
typedef struct { char name[32]; int first, last, rate; } modelSequence_t;
typedef struct {
    char path[MAX_QPATH];
    qhandle_t handle;
    int frames, count;
    modelSequence_t sequences[DK_MODEL_SEQUENCES];
} animatedModel_t;
static animatedModel_t models[DK_MODEL_CACHE];
static int modelCount;
static int characterState[MAX_GENTITIES], characterStart[MAX_GENTITIES];
static refEntity_t characterModels[MAX_CLIENTS];
static int characterFrames[MAX_CLIENTS];

static animatedModel_t *Model(const char *path) {
    int i, length;
    char filename[MAX_QPATH], text[32768], *cursor, *token;
    animatedModel_t *model;
    fileHandle_t file;
    for (i = 0; i < modelCount; ++i) if (!Q_stricmp(models[i].path, path)) return &models[i];
    if (modelCount == DK_MODEL_CACHE) CG_Error("dk3: animated model cache is full");
    model = &models[modelCount++];
    Q_strncpyz(model->path, path, sizeof(model->path));
    model->handle = DK_RegisterModel(path);
    Com_sprintf(filename, sizeof(filename), "%s.anim", path);
    length = trap_FS_FOpenFile(filename, &file, FS_READ);
    if (length < 1 || length >= sizeof(text)) {
        if (file) trap_FS_FCloseFile(file);
        CG_Error("dk3: missing or oversized animation metadata %s", filename);
    }
    trap_FS_Read(text, length, file); trap_FS_FCloseFile(file); text[length] = 0;
    cursor = text;
    if (strcmp(COM_Parse(&cursor), "dk3_animation") || strcmp(COM_Parse(&cursor), "1"))
        CG_Error("dk3: unsupported animation metadata %s", filename);
    model->frames = atoi(COM_Parse(&cursor));
    while (*(token = COM_Parse(&cursor))) {
        modelSequence_t *sequence;
        if (model->count == DK_MODEL_SEQUENCES) CG_Error("dk3: sequence limit exceeded for %s", path);
        sequence = &model->sequences[model->count++];
        Q_strncpyz(sequence->name, token, sizeof(sequence->name));
        sequence->first = atoi(COM_Parse(&cursor)); sequence->last = atoi(COM_Parse(&cursor));
        sequence->rate = atoi(COM_Parse(&cursor));
        if (!cursor || sequence->first < 0 || sequence->last < sequence->first || sequence->last >= model->frames ||
            sequence->rate < 1 || sequence->rate > 100) CG_Error("dk3: invalid animation %s:%s", path, sequence->name);
    }
    if (model->frames < 1 || model->frames > 65535) CG_Error("dk3: invalid frame count for %s", path);
    if (!model->count) {
        modelSequence_t *sequence = &model->sequences[model->count++];
        Q_strncpyz(sequence->name, "amba", sizeof(sequence->name));
        sequence->first = 0; sequence->last = model->frames - 1; sequence->rate = 10;
    }
    return model;
}

static modelSequence_t *Sequence(animatedModel_t *model, const char *name) {
    int i, selected = -1;
    for (i = 0; i < model->count; ++i) {
        if (!Q_stricmp(model->sequences[i].name, name)) { selected = i; break; }
        if (selected < 0 && !Q_stricmpn(model->sequences[i].name, name, strlen(name))) selected = i;
    }
    return selected < 0 ? NULL : &model->sequences[selected];
}

/* A frozen creature gains a blue shell that deepens with its freeze level;
   a melting Buboid sheds a grey smoke cloud around its feet. */
void DK_AddStatusEffects(const entityState_t *state, const refEntity_t *model) {
    static int smokeTime[MAX_GENTITIES];
    refEntity_t shell;
    int step = (state->dk3RenderFlags & DK3_RF_FROZEN) >> DK3_RF_FROZEN_SHIFT;
    if ((state->dk3RenderFlags & DK3_RF_MELT) && (smokeTime[state->number] > cg.time || cg.time - smokeTime[state->number] >= 50)) {
        vec3_t origin, velocity;
        int puff;
        smokeTime[state->number] = cg.time;
        for (puff = 0; puff < 2; ++puff) {
            float angle = random() * 2 * M_PI, spread = random() * 45;
            VectorSet(origin, model->origin[0] + cos(angle) * spread, model->origin[1] + sin(angle) * spread, model->origin[2] - 24);
            VectorSet(velocity, crandom() * 10, crandom() * 10, 20 + random() * 30);
            CG_SmokePuff(origin, velocity, 12 + random() * 10, 0.25f, 0.25f, 0.25f, 0.45f, 1500, cg.time, 0, 0,
                         cgs.media.smokePuffShader);
        }
    }
    if (!step || (state->dk3RenderFlags & DK3_RF_STONE)) return;
    shell = *model;
    shell.customShader = trap_R_RegisterShader("dk3/fx/freeze");
    shell.shaderRGBA[0] = shell.shaderRGBA[1] = 12 * step; shell.shaderRGBA[2] = 60 * step; shell.shaderRGBA[3] = 255;
    trap_R_AddRefEntityToScene(&shell);
}

int DK_ModelAnimationDuration(const char *path, const char *name, int rate) {
    animatedModel_t *model = Model(path);
    int i;
    /* Weapon bindings require the authored sequence, never a prefix match such
       as shoot -> shoota. Other animated entities still use Sequence's fallback. */
    for (i = 0; i < model->count; ++i) {
        modelSequence_t *sequence = &model->sequences[i];
        if (!Q_stricmp(sequence->name, name))
            return (sequence->last - sequence->first + 1) * 1000 / (rate > 0 ? rate : sequence->rate);
    }
    return 0;
}

void DK_ModelAnimationFrame(const char *path, const char *name, float frame, refEntity_t *entity) {
    animatedModel_t *model = Model(path);
    modelSequence_t *sequence = Sequence(model, name);
    int first, last, current;
    if (!sequence) sequence = &model->sequences[0];
    first = sequence->first; last = sequence->last;
    frame = Com_Clamp(0, last - first, frame);
    current = (int)frame;
    entity->hModel = model->handle;
    entity->oldframe = first + current;
    entity->frame = first + (current < last - first ? current + 1 : current);
    entity->backlerp = 1 - (frame - current);
}

void DK_ModelAnimationRate(const char *path, const char *name, int start, qboolean loop, int rate, refEntity_t *entity) {
    animatedModel_t *model = Model(path);
    modelSequence_t *sequence = Sequence(model, name);
    int frames, previous, next;
    float position;
    if (!sequence) sequence = &model->sequences[0];
    frames = sequence->last - sequence->first + 1;
    position = (cg.time - start) * (rate > 0 ? rate : sequence->rate) / 1000.0f;
    if (position < 0) position = 0;
    previous = (int)position;
    entity->backlerp = 1 - (position - previous);
    if (loop) { previous %= frames; next = (previous + 1) % frames; }
    else { if (previous >= frames) previous = frames - 1; next = previous + 1 < frames ? previous + 1 : previous; }
    entity->hModel = model->handle;
    entity->oldframe = sequence->first + previous;
    entity->frame = sequence->first + next;
}

void DK_ModelAnimation(const char *path, const char *name, int start, qboolean loop, refEntity_t *entity) {
    DK_ModelAnimationRate(path, name, start, loop, 0, entity);
}

void DK_DrawCharacter(centity_t *cent) {
    refEntity_t entity;
    entityState_t *state = &cent->currentState;
    vec3_t angles;
    const char *animation, *model = "models/global/m_hiro.dkm";
    int skin = 0;
    int motion = state->legsAnim & ~ANIM_TOGGLEBIT, condition;
    qboolean loop = qtrue;
    if (state->eFlags & EF_NODRAW) return;
    if (state->eFlags & EF_DEAD) { condition = 1; animation = "die"; loop = qfalse; }
    else if (state->eFlags & EF_FIRING) { condition = 2; animation = "atak"; }
    else if (motion == LEGS_SWIM) { condition = 3; animation = "swim"; }
    else if (motion == LEGS_WALKCR) { condition = 4; animation = "cwalk"; }
    else if (motion == LEGS_IDLECR) { condition = 5; animation = "camb"; }
    else if (motion == LEGS_JUMP || motion == LEGS_JUMPB) { condition = 6; animation = "jump"; loop = qfalse; }
    else if (motion == LEGS_RUN || motion == LEGS_BACK) { condition = 7; animation = "run"; }
    else if (motion == LEGS_WALK) { condition = 8; animation = "walk"; }
    else { condition = 9; animation = "aamb"; }
    if (characterState[state->number] != condition) {
        characterState[state->number] = condition; characterStart[state->number] = cg.time;
    }
    memset(&entity, 0, sizeof(entity));
    if (cgs.gametype != GT_SINGLE_PLAYER && state->clientNum >= 0 && state->clientNum < MAX_CLIENTS) {
        clientInfo_t *info = &cgs.clientinfo[state->clientNum];
        int appearance = DK_AppearanceFind(va("%s/%s", info->modelName, info->skinName));
        if (appearance < 0) appearance = 0;
        model = DK_AppearanceModel(appearance);
        entity.customSkin = trap_R_RegisterSkin(DK_AppearanceSkin(appearance));

    }
    DK_ModelAnimation(model, animation, characterStart[state->number], loop, &entity);
    entity.skinNum = skin;
    entity.reType = RT_MODEL;
    VectorCopy(cent->lerpOrigin, entity.origin);
    VectorCopy(entity.origin, entity.lightingOrigin);
    VectorSet(angles, 0, cent->lerpAngles[YAW], 0); AnglesToAxis(angles, entity.axis);
    entity.renderfx = RF_LIGHTING_ORIGIN;
    if (state->number == cg.clientNum && !cg.renderingThirdPerson) entity.renderfx |= RF_THIRD_PERSON;
    entity.shaderRGBA[0] = entity.shaderRGBA[1] = entity.shaderRGBA[2] = entity.shaderRGBA[3] = 255;
    if ((state->powerups & (1 << PW_INVIS)) && !(state->eFlags & EF_DEAD)) {
        entity.customShader = trap_R_RegisterShader("dk3/fx/cloak");
        entity.shaderRGBA[3] = state->eFlags & EF_FIRING ? 150 : 35;
    }
    if (cgs.gametype >= GT_TEAM && state->clientNum >= 0 && state->clientNum < MAX_CLIENTS) {
        team_t team = cgs.clientinfo[state->clientNum].team;
        if (team == TEAM_RED || team == TEAM_BLUE) {
            entity.shaderRGBA[0] = team == TEAM_RED ? 255 : 100;
            entity.shaderRGBA[1] = 100;
            entity.shaderRGBA[2] = team == TEAM_BLUE ? 255 : 100;
        }
    }
    if (state->dk3RenderFlags & DK3_RF_STONE) {
        entity.customShader = trap_R_RegisterShader("dk3/fx/stone");
        entity.frame = entity.oldframe = 0; entity.backlerp = 0;
        entity.shaderRGBA[0] = entity.shaderRGBA[1] = entity.shaderRGBA[2] = 160; entity.shaderRGBA[3] = 178;
    }
    trap_R_AddRefEntityToScene(&entity);
    DK_AddStatusEffects(state, &entity);
    if (state->clientNum >= 0 && state->clientNum < MAX_CLIENTS) {
        characterModels[state->clientNum] = entity;
        characterFrames[state->clientNum] = cg.time;
    }
    if (cgs.gametype >= GT_TEAM && !entity.customShader && state->clientNum >= 0 && state->clientNum < MAX_CLIENTS &&
        (cgs.clientinfo[state->clientNum].team == TEAM_RED || cgs.clientinfo[state->clientNum].team == TEAM_BLUE)) {
        refEntity_t tint = entity;
        tint.customShader = trap_R_RegisterShader("dk3/fx/cloak"); tint.shaderRGBA[3] = 48;
        trap_R_AddRefEntityToScene(&tint);
    }
    if (!(state->eFlags & EF_DEAD)) DK_DrawPlayerWeapon(&entity, cent);
}

qboolean DK_DrawCarriedObjective(centity_t *cent) {
    refEntity_t objective, *parent;
    orientation_t tag;
    int carrier = cent->currentState.dk3Carrier - 1;
    if (carrier < 0 || carrier >= MAX_CLIENTS) return qfalse;
    if (characterFrames[carrier] != cg.time) return qtrue;
    parent = &characterModels[carrier];
    memset(&objective, 0, sizeof(objective));
    objective.reType = RT_MODEL; objective.hModel = cgs.gameModels[cent->currentState.modelindex];
    if (trap_R_LerpTag(&tag, parent->hModel, parent->oldframe, parent->frame, 1 - parent->backlerp, "ctf_flag")) {
        AxisClear(objective.axis);
        CG_PositionEntityOnTag(&objective, parent, parent->hModel, "ctf_flag");
    } else {
        VectorMA(parent->origin, -12, parent->axis[0], objective.origin); objective.origin[2] += 20;
    }
    AxisCopy(parent->axis, objective.axis);
    objective.renderfx = parent->renderfx;
    objective.shaderRGBA[0] = objective.shaderRGBA[1] = objective.shaderRGBA[2] = objective.shaderRGBA[3] = 255;
    trap_R_AddRefEntityToScene(&objective);
    return qtrue;
}
