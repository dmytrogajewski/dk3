/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "cg_local.h"
#include "dk_effects.h"

#define DK_PARTICLES 4096
#define DK_EMIT_BUDGET 192

typedef struct {
    int start, end;
    vec3_t origin, velocity, gravity, color;
    float radius, alpha;
    qhandle_t shader, splash;
    qboolean smoke, streak, rain, beamSpark, snow;
    vec3_t contact;
    int owner;
} particle_t;
static particle_t particles[DK_PARTICLES];
static int weatherActive[MAX_GENTITIES];
static int nextParticle, budgetTime, emitted;
static int emissionTime[MAX_GENTITIES], generation[MAX_GENTITIES];
static float carry[MAX_GENTITIES];
static unsigned int randomState;
static int fogState;
static vec3_t fogColor;
static float fogStart, fogEnd, fogSkyEnd;
#define DK_GIBS 100
typedef struct {
    qboolean active, resting;
    int fragtype, start, fadeTime, faded, trailCount;
    float alpha, trail;
    vec3_t origin, velocity, angles, spin, scale, mins, maxs;
    qhandle_t model, skin, fadeSkin;
} dkGib_t;
static dkGib_t gibs[DK_GIBS];
static int gibBurst[MAX_GENTITIES], gibStage[MAX_GENTITIES], gibCloudTime[MAX_GENTITIES];

static void ReadColor(char *text, float scale) {
    int i;
    for (i = 0; i < 3; ++i) fogColor[i] = atof(COM_Parse(&text)) * scale;
}

/* Worldspawn fog_value enables linear fog from fog_start to fog_end, with
   fog_skyend for the sky; fog_color is 0-255 and _color is 0-1. */
static void ParseWorldFog(void) {
    char key[MAX_TOKEN_CHARS], value[MAX_TOKEN_CHARS];
    int active = 0;
    fogState = 1;
    VectorClear(fogColor); fogStart = fogEnd = fogSkyEnd = 0;
    if (!trap_GetEntityToken(key, sizeof(key)) || strcmp(key, "{")) return;
    while (trap_GetEntityToken(key, sizeof(key)) && strcmp(key, "}")) {
        if (!trap_GetEntityToken(value, sizeof(value))) return;
        if (!Q_stricmp(key, "fog_value")) active = atoi(value);
        else if (!Q_stricmp(key, "fog_start")) fogStart = atof(value);
        else if (!Q_stricmp(key, "fog_end")) fogEnd = atof(value);
        else if (!Q_stricmp(key, "fog_skyend")) fogSkyEnd = atof(value);
        else if (!Q_stricmp(key, "fog_color")) ReadColor(value, 1.0f / 255);
        else if (!Q_stricmp(key, "_color")) ReadColor(value, 1);
    }
    if (active) fogState = 2;
}

void DK_SubmitWorldFog(void) {
    static const char *const patterns[] = {
        "m", "mmnmmommommnonmmonqnmmo", "abcdefghijklmnopqrstuvwxyzyxwvutsrqponmlkjihgfedcba",
        "mmmmmaaaaammmmmaaaaaabcdefgabcdefg", "mamamamamama", "jklmnopqrstuvwxyzyxwvutsrqponmlkj",
        "nmonqnmomnmomomno", "mmmaaaabcdefgmmmmaaaammmaamm", "mmmaaammmaaammmabcdefaaaammmmabcdefmmmaaaa",
        "aaaaaaaazzzzzzzz", "mmamammmmammamamaaamammma", "abcdefghijklmnopqrrqponmlkjihgfedcba"
    };
    const char *styles = CG_ConfigString(CS_DK3_LIGHTSTYLES);
    int i, length = strlen(styles), tick = cg.time / 100;
    for (i = 0; i < 256; ++i) {
        char value = i == 63 ? 'a' : i < length ? styles[i] : '*';
        if (value == '*') { const char *pattern = i < ARRAY_LEN(patterns) ? patterns[i] : "m"; value = pattern[tick % strlen(pattern)]; }
        cg.refdef.dk3Lightstyles[i] = value >= 'a' && value <= 'z' ? (value - 'a') / 12.0f : 1;
    }
    DK_UpdateSky();
    if (!fogState) ParseWorldFog();
    if (fogState == 2) trap_R_Dk3Fog(fogColor, fogStart, fogEnd, fogSkyEnd);
}

void DK_ResetWorldEffects(void) {
    fogState = 0;
    DK_ResetWeaponPresentation();
    memset(particles, 0, sizeof(particles));
    memset(weatherActive, 0, sizeof(weatherActive));
    memset(emissionTime, 0, sizeof(emissionTime));
    memset(generation, 0, sizeof(generation));
    memset(carry, 0, sizeof(carry));
    nextParticle = budgetTime = emitted = 0;
    memset(gibs, 0, sizeof(gibs));
    memset(gibBurst, 0, sizeof(gibBurst));
}

static void Gibs(void);

static float Random(void) {
    randomState = randomState * 1664525u + 1013904223u;
    return (randomState >> 8) / 16777216.0f;
}

static void Sprite(const vec3_t point, float size, const vec3_t color, float alpha, qhandle_t shader) {
    polyVert_t vertices[4];
    int i, axis;
    /* Particles share the polygon budget with rain. Reserving one render entity
       per particle exhausts MAX_REFENTITIES before actors and weapons are drawn.
       Match the engine's unrotated sprite corners and texture coordinates. */
    for (i = 0; i < 4; ++i) {
        VectorMA(point, i == 0 || i == 3 ? size : -size, cg.refdef.viewaxis[1], vertices[i].xyz);
        VectorMA(vertices[i].xyz, i < 2 ? size : -size, cg.refdef.viewaxis[2], vertices[i].xyz);
        vertices[i].st[0] = i == 0 || i == 3 ? 0 : 1;
        vertices[i].st[1] = i < 2 ? 0 : 1;
        for (axis = 0; axis < 3; ++axis) vertices[i].modulate[axis] = Com_Clamp(0, 1, color[axis]) * 255;
        vertices[i].modulate[3] = Com_Clamp(0, 1, alpha) * 255;
    }
    trap_R_AddPolyToScene(shader, 4, vertices);
}

static void AtlasParticle(const vec3_t point, float radius, const vec3_t color, float alpha, qhandle_t shader) {
    polyVert_t vertices[3];
    int i, axis;
    /* Atlas cells overlap: only the triangle s+t<=1 belongs to this particle.
       Drawing a whole rectangle also samples its neighbour (notably CP1 inside
       the smoke cell). Position the triangle's centroid at the particle. */
    for (i = 0; i < 3; ++i) {
        float s = i == 1 ? 1 : 0, t = i == 2 ? 1 : 0;
        VectorMA(point, (s - 1.0f / 3) * radius * 2, cg.refdef.viewaxis[2], vertices[i].xyz);
        VectorMA(vertices[i].xyz, (1.0f / 3 - t) * radius * 2, cg.refdef.viewaxis[1], vertices[i].xyz);
        vertices[i].st[0] = s; vertices[i].st[1] = t;
        for (axis = 0; axis < 3; ++axis) vertices[i].modulate[axis] = Com_Clamp(0, 1, color[axis]) * 255;
        vertices[i].modulate[3] = Com_Clamp(0, 1, alpha) * 255;
    }
    trap_R_AddPolyToScene(shader, 3, vertices);
}

static void Ribbon(const vec3_t start, const vec3_t end, float radius, const vec3_t color, float alpha) {
    vec3_t direction, toward, side;
    polyVert_t vertices[4];
    int i, axis;
    VectorSubtract(end, start, direction);
    if (!VectorNormalize(direction)) return;
    VectorSubtract(cg.refdef.vieworg, start, toward);
    CrossProduct(direction, toward, side);
    if (VectorNormalize(side) < 0.01f) VectorCopy(cg.refdef.viewaxis[1], side);
    for (i = 0; i < 4; ++i) {
        VectorMA(i < 2 ? start : end, (i == 0 || i == 3 ? -radius : radius), side, vertices[i].xyz);
        vertices[i].st[0] = i == 0 || i == 3 ? 0 : 1;
        vertices[i].st[1] = i < 2 ? 0 : 1;
        for (axis = 0; axis < 3; ++axis) vertices[i].modulate[axis] = Com_Clamp(0, 1, color[axis]) * 255;
        vertices[i].modulate[3] = Com_Clamp(0, 1, alpha) * 255;
    }
    trap_R_AddPolyToScene(trap_R_RegisterShader("dk3/fx/glow"), 4, vertices);
}

static void TexturedBeam(const vec3_t start, const vec3_t end, float width, float endWidth,
                         const vec3_t color, float alpha, float endAlpha, qhandle_t shader) {
    vec3_t direction, toward, side;
    polyVert_t vertices[4];
    int i, axis;
    VectorSubtract(end, start, direction);
    VectorSubtract(cg.refdef.vieworg, start, toward);
    CrossProduct(direction, toward, side);
    if (!VectorNormalize(side)) VectorCopy(cg.refdef.viewaxis[1], side);
    for (i = 0; i < 4; ++i) {
        VectorMA(i < 2 ? start : end, (i == 0 || i == 3 ? -1 : 1) * (i < 2 ? width : endWidth), side, vertices[i].xyz);
        vertices[i].st[0] = i < 2 ? 0 : 1;
        vertices[i].st[1] = i == 0 || i == 3 ? 0 : 1;
        for (axis = 0; axis < 3; ++axis) vertices[i].modulate[axis] = Com_Clamp(0, 1, color[axis]) * 255;
        vertices[i].modulate[3] = Com_Clamp(0, 1, i < 2 ? alpha : endAlpha) * 255;
    }
    trap_R_AddPolyToScene(shader, 4, vertices);
}

/* Rain uses the supplied triangular atlas footprint: 64 units long, 2.56
   across, rather than a glowing line. The basis follows each volume's wind. */
static void RainDrop(const particle_t *particle, const vec3_t point, float age) {
    vec3_t along, across, toward;
    polyVert_t vertices[3];
    int i, axis;
    VectorSubtract(point, cg.refdef.vieworg, toward);
    if (DotProduct(toward, cg.refdef.viewaxis[0]) < -64) return;
    VectorCopy(particle->velocity, along); VectorNormalize(along);
    VectorSubtract(cg.refdef.vieworg, point, toward);
    CrossProduct(along, toward, across);
    if (!VectorNormalize(across)) VectorCopy(cg.refdef.viewaxis[1], across);
    for (i = 0; i < 3; ++i) {
        float s = i == 1 ? 1 : 0, t = i == 2 ? 1 : 0;
        VectorMA(point, (s - 1.0f / 3) * 64, along, vertices[i].xyz);
        VectorMA(vertices[i].xyz, (t - 1.0f / 3) * 2.56f, across, vertices[i].xyz);
        vertices[i].st[0] = s; vertices[i].st[1] = t;
        for (axis = 0; axis < 3; ++axis) vertices[i].modulate[axis] = 255;
        vertices[i].modulate[3] = Com_Clamp(0, 1, (0.4f - age * 0.1f) * 0.5f) * 255;
    }
    trap_R_AddPolyToScene(particle->shader, 3, vertices);
}

static void AddParticle(entityState_t *state, const vec3_t origin, const vec3_t velocity, int duration, float radius, qboolean smoke) {
    particle_t *particle = &particles[nextParticle++ % DK_PARTICLES];
    trace_t trace;
    vec3_t end;
    float seconds = duration / 1000.0f;
    qboolean splash = qfalse;
    memset(particle, 0, sizeof(*particle));
    particle->rain = state->dk3Effect == DK_FX_RAIN;
    particle->snow = state->dk3Effect == DK_FX_SNOW;
    if (state->dk3Effect >= DK_FX_RAIN && state->dk3Effect <= DK_FX_DRIP) particle->owner = state->number + 1;
    particle->start = cg.time; particle->end = cg.time + duration;
    VectorCopy(origin, particle->origin); VectorCopy(velocity, particle->velocity);
    VectorCopy(state->dk3EffectGravity, particle->gravity); VectorCopy(state->dk3EffectColor, particle->color);
    particle->radius = radius; particle->alpha = state->dk3Alpha; particle->smoke = smoke;
    particle->streak = (state->dk3EffectFlags & DK_FX_STREAK) != 0;
    particle->shader = trap_R_RegisterShader(particle->rain ? "dk3/particle/rain" : smoke ? "dk3/particle/smoke" :
        state->dk3EffectFlags & DK_FX_BUBBLE ? "dk3/particle/bubble" :
        state->dk3Effect == DK_FX_SNOW ? "dk3/particle/snow" : "dk3/particle/simple");
    if (state->dk3EffectFlags & DK_FX_PARTICLE_MASK) {
        int kind = (state->dk3EffectFlags & DK_FX_PARTICLE_MASK) >> DK_FX_PARTICLE_SHIFT;
        particle->shader = trap_R_RegisterShader(va("dk3/particle/cp%d", kind));
    }
    VectorMA(origin, seconds, velocity, end); VectorMA(end, 0.5f * seconds * seconds, particle->gravity, end);
    /* Authored rain volumes end on the ground or liquid surface, and the
       original scatters splashes over that floor; liquids must stop drops. */
    CG_Trace(&trace, origin, NULL, NULL, end, ENTITYNUM_NONE, particle->rain ? MASK_SOLID | MASK_WATER : MASK_SOLID);
    if (trace.startsolid) particle->end = cg.time;
    else if (trace.fraction < 1) {
        particle->end = cg.time + (int)(duration * trace.fraction);
        splash = particle->rain && trace.plane.normal[2] > 0.5f;
        VectorMA(trace.endpos, 0.5f, trace.plane.normal, particle->contact);
    } else if (particle->rain) {
        splash = qtrue;
        VectorCopy(end, particle->contact); particle->contact[2] += 0.5f;
    }
    if (splash)
        particle->splash = trap_R_RegisterShader(Random() < 0.5f ? "dk3/particle/rain-splash" : "dk3/particle/rain-splash3");
}

void DK_AddWorldParticles(void) {
    int i;
    memset(weatherActive, 0, sizeof(weatherActive));
    Gibs();
    for (i = 0; i < DK_PARTICLES; ++i) {
        particle_t *particle = &particles[i];
        vec3_t point;
        float seconds, life, radius;
        if (particle->splash && cg.time >= particle->end && cg.time <= particle->end + 101) {
            vec3_t toward;
            float depth;
            VectorSubtract(particle->contact, cg.refdef.vieworg, toward);
            depth = DotProduct(toward, cg.refdef.viewaxis[0]);
            AtlasParticle(particle->contact, 2 * (depth < 20 ? 1 : 1 + depth * 0.004f), particle->color,
                          0.4f - 0.1f * (cg.time - particle->end) / 1000.0f, particle->splash);
        }
        if (particle->end <= cg.time || particle->start > cg.time) continue;
        if (particle->owner > 0 && particle->owner <= MAX_GENTITIES) ++weatherActive[particle->owner - 1];
        seconds = (cg.time - particle->start) / 1000.0f;
        life = (particle->end - cg.time) / (float)(particle->end - particle->start);
        VectorMA(particle->origin, seconds, particle->velocity, point);
        VectorMA(point, 0.5f * seconds * seconds, particle->gravity, point);
        radius = particle->radius;
        if (particle->rain) {
            RainDrop(particle, point, seconds);
        } else if (particle->beamSpark) {
            vec3_t tail;
            VectorMA(point, -1.0f / 30, particle->velocity, tail);
            TexturedBeam(point, tail, radius, radius * 0.3f, particle->color,
                         particle->alpha * life, particle->alpha * life, particle->shader);
        } else if (particle->streak) {
            vec3_t tail;
            float nearFade = Com_Clamp(0, 1, (Distance(point, cg.refdef.vieworg) - 16) / 48);
            VectorMA(point, -0.025f, particle->velocity, tail);
            Ribbon(tail, point, radius, particle->color, particle->alpha * life * nearFade * 0.6f);
        } else if (particle->snow) {
            vec3_t toward;
            float depth;
            VectorSubtract(point, cg.refdef.vieworg, toward);
            depth = DotProduct(toward, cg.refdef.viewaxis[0]);
            if (depth < -8) continue;
            AtlasParticle(point, radius * (depth < 20 ? 1 : 1 + depth * 0.004f), particle->color, particle->alpha, particle->shader);
        } else AtlasParticle(point, radius, particle->color, particle->alpha * life, particle->shader);
    }
}

void DK_MonsterTrail(centity_t *cent) {
    entityState_t state;
    int kind = cent->currentState.dk3Effect, i;
    if (cent->trailTime > cg.time - 40 && cent->trailTime <= cg.time) return;
    cent->trailTime = cg.time;
    randomState = cent->currentState.number * 2654435761u + cg.time / 40;
    memset(&state, 0, sizeof(state));
    state.dk3Alpha = kind == DK_FX_CRYO ? 0.65f : 0.4f;
    if (kind == DK_FX_CRYO) VectorSet(state.dk3EffectColor, 0.65f, 0.85f, 1);
    else VectorSet(state.dk3EffectColor, 0.35f, 0.65f, 0.15f);
    for (i = 0; i < (kind == DK_FX_CRYO ? 8 : 2); ++i) {
        vec3_t velocity;
        VectorScale(cent->currentState.pos.trDelta, 0.2f, velocity);
        velocity[0] += (Random() - 0.5f) * 100; velocity[1] += (Random() - 0.5f) * 100; velocity[2] += Random() * 40;
        AddParticle(&state, cent->lerpOrigin, velocity, 500, kind == DK_FX_CRYO ? 2 : 1, qtrue);
    }
}

static void Debris(centity_t *cent) {
    static const char *const models[] = {"models/global/e_rock1.dkm", "models/global/e_wood1.dkm",
        "models/global/e_metal1.dkm", "models/global/e_glass1.dkm", "models/global/e_gibchunk.dkm"};
    entityState_t *state = &cent->currentState;
    int i, material = state->dk3EffectDuration;
    qhandle_t model;
    if (material < 0 || material >= ARRAY_LEN(models)) return;
    model = DK_RegisterModel(models[material]);
    for (i = 0; i < (int)state->dk3EffectRate && i < 64; ++i) {
        localEntity_t *piece = CG_AllocLocalEntity();
        int axis;
        piece->leType = LE_FRAGMENT; piece->startTime = cg.time; piece->endTime = cg.time + 3500 + Random() * 2000;
        piece->bounceFactor = material == DK_DEBRIS_GLASS ? 0.2f : 0.4f;
        piece->pos.trType = TR_GRAVITY; piece->pos.trTime = cg.time;
        piece->angles.trType = TR_LINEAR; piece->angles.trTime = cg.time;
        piece->leFlags = LEF_TUMBLE;
        for (axis = 0; axis < 3; ++axis) {
            piece->pos.trBase[axis] = cent->lerpOrigin[axis] + (Random() - 0.5f) * state->dk3EffectMaxs[axis];
            piece->pos.trDelta[axis] = (Random() - 0.5f) * state->dk3EffectSpeed * 2;
            piece->angles.trDelta[axis] = (Random() - 0.5f) * 720;
            piece->refEntity.shaderRGBA[axis] = 255;
        }
        piece->pos.trDelta[2] += state->dk3EffectSpeed * 0.5f;
        piece->refEntity.shaderRGBA[3] = 255; piece->refEntity.reType = RT_MODEL;
        piece->refEntity.hModel = material == DK_DEBRIS_METAL && (i & 1) ?
            DK_RegisterModel("models/global/e_metal2.dkm") : model;
        piece->dk3FragmentScale = state->dk3Scale > 0 ? state->dk3Scale : 1;
        AxisClear(piece->refEntity.axis);
        for (axis = 0; axis < 3; ++axis)
            VectorScale(piece->refEntity.axis[axis], piece->dk3FragmentScale, piece->refEntity.axis[axis]);
        piece->refEntity.nonNormalizedAxes = qtrue;
        VectorCopy(piece->pos.trBase, piece->refEntity.origin);
    }
}

/* Gold's gib.cpp and AI_StartGibFest: bouncing meshes with blood trails, two
   volleys 0.2 s apart and a half-second blood cloud. At most 100 gibs live. */

static float Crandom(void) { return Random() * 2 - 1; }

static int LiveGibs(void) {
    int i, count = 0;
    for (i = 0; i < DK_GIBS; ++i) count += gibs[i].active;
    return count;
}

static void GibSound(const vec3_t origin, int number, const char *name, int variants) {
    trap_S_StartSound((float *)origin, number, CHAN_AUTO, trap_S_RegisterSound(
        va("sounds/global/%s%c.wav", name, 'a' + (int)(Random() * variants) % variants), qfalse));
}

static void BloodSplat(const vec3_t origin, const vec3_t normal) {
    CG_ImpactMark(trap_R_RegisterShader(Random() < 0.5f ? "dk3/mark/blood1" : "dk3/mark/blood2"), origin, normal, Random() * 360, 1, 1, 1, 1, qfalse,
        16 * (Crandom() * 0.5f + 0.75f), qfalse);
}

static void ThrowGib(const entityState_t *state, int type, const vec3_t origin, const vec3_t size,
                     const vec3_t toward, float damage, qhandle_t skin, qhandle_t fadeSkin) {
    static const char *const names[] = {"e_gibtorso", "e_gibleg", "e_gibfoot", "e_gibhand", "e_gibhead",
                                        "e_gibchest", "e_gibeye", "e_gibarm", "e_gibmisc"};
    static const float boxes[] = {2, 1, 3, 1, 1, 3, 1, 1, 1};
    dkGib_t *gib = NULL;
    vec3_t angles, direction;
    float mass = Com_Clamp(128, 300, state->dk3EffectRate) / 10, speed;
    int i, fragtype = state->dk3EffectDuration;
    for (i = 0; i < DK_GIBS && !gib; ++i) if (!gibs[i].active) gib = &gibs[i];
    if (!gib) return;
    memset(gib, 0, sizeof(*gib));
    gib->active = qtrue; gib->fragtype = fragtype; gib->start = cg.time; gib->alpha = 1; gib->trailCount = 1024;
    VectorCopy(origin, gib->origin);
    VectorSet(gib->maxs, boxes[type], boxes[type], type == 4 ? 3 : boxes[type]);
    VectorNegate(gib->maxs, gib->mins);
    if (fragtype & DK_FRAG_BONE) {
        float s0 = Random() * 0.03f, s1 = Random() * 0.03f;
        if (s0 < 0.022f) s0 = 0.022f;
        if (s1 < 0.022f) s1 = 0.022f;
        gib->model = DK_RegisterModel("models/global/g_bone.dkm");
        VectorSet(gib->scale, (size[0] + 2) * s0, (size[1] + 2) * s1, (size[2] + 2) * s0);
    } else {
        float s0 = Random() * 0.06f, s2 = Random() * ((fragtype & DK_FRAG_ROBOTIC) ? 0.06f : 0.05f);
        if (s0 < 0.038f) s0 = 0.038f;
        if (s2 < 0.038f) s2 = 0.038f;
        gib->model = DK_RegisterModel(va("models/global/%s.dkm", names[type]));
        if (fragtype & DK_FRAG_ROBOTIC) { gib->skin = skin; gib->fadeSkin = fadeSkin; }
        VectorSet(gib->scale, mass * s0, mass * s0, mass * s2);
    }
    /* GibLimitDirection: away from the attacker, then up to 45 degrees off. */
    VectorNegate(toward, direction);
    vectoangles(direction, angles);
    angles[YAW] += Crandom() * 45; angles[PITCH] += Crandom() * 45;
    AngleVectors(angles, direction, NULL, NULL);
    speed = Com_Clamp(225, 300, (damage < 100 ? damage / 100 : 1) * Random() * 3000);
    VectorScale(direction, speed, gib->velocity);
    if (fragtype & (DK_FRAG_ROBOTIC | DK_FRAG_BONE)) {
        gib->velocity[0] *= 1.15f; gib->velocity[1] *= 1.15f; gib->velocity[2] *= 2.45f;
    } else {
        gib->velocity[0] *= 1.65f; gib->velocity[1] *= 1.65f; gib->velocity[2] *= 2.15f;
    }
    VectorScale(gib->velocity, 2.5f, gib->spin);
    VectorAdd(gib->velocity, state->dk3EffectGravity, gib->velocity);
}

/* AI_GibFest: pieces rise along the victim's taller axis from its absmin. */
static void GibVolley(centity_t *cent, qboolean second) {
    entityState_t *state = &cent->currentState;
    int i, count, fragtype = state->dk3EffectDuration, axis = 2;
    float mod = Com_Clamp(0.35f, 1, state->dk3EffectRate / 500), step;
    vec3_t absmin, size, toward;
    qhandle_t skin = 0, fadeSkin = 0;
    count = (int)((cgs.gametype == GT_SINGLE_PLAYER ? 16 : 6) * mod * 0.5f);
    if (count < 1) count = 1;
    if (second) {
        VectorSet(absmin, -1, -1, -1); VectorAdd(absmin, cent->lerpOrigin, absmin);
        VectorClear(size); VectorClear(toward);
    } else {
        VectorSet(absmin, -1, -1, -1); VectorAdd(absmin, state->dk3EffectMins, absmin);
        VectorAdd(cent->lerpOrigin, absmin, absmin);
        VectorSubtract(state->dk3EffectMaxs, state->dk3EffectMins, size);
        VectorCopy(state->dk3EffectEnd, toward);
    }
    if ((fragtype & DK_FRAG_ROBOTIC) && state->modelindex2 > 0 && state->modelindex2 < MAX_MODELS) {
        char base[MAX_QPATH];
        COM_StripExtension(COM_SkipPath((char *)CG_ConfigString(CS_MODELS + state->modelindex2)), base, sizeof(base));
        skin = trap_R_RegisterShader(va("skins/%s", base));
        fadeSkin = trap_R_RegisterShader(va("skins/%s@alpha", base));
    }
    /* The original divides 1 by the integer count on the wide branch, so wide
       victims throw every piece from the same x. */
    if (size[2] > size[0]) step = size[2] / count;
    else { axis = 0; step = count == 1 ? size[0] : 0; }
    for (i = 0; i < count; ++i) {
        vec3_t origin;
        int other;
        if (LiveGibs() >= DK_GIBS) break;
        VectorCopy(absmin, origin);
        origin[axis] += (i + 3) * step;
        for (other = 0; other < 3; ++other) if (other != axis) origin[other] += Random() * size[other];
        ThrowGib(state, i % 9, origin, size, toward, second ? 0 : state->dk3EffectSpeed, skin, fadeSkin);
    }
    if (fragtype & DK_FRAG_ROBOTIC) GibSound(cent->lerpOrigin, state->number, "m_gibsurf", 2);
    else if (fragtype & DK_FRAG_BONE) {
        GibSound(cent->lerpOrigin, state->number, "m_gibbone", 1);
        GibSound(cent->lerpOrigin, state->number, "m_gibbonecrk", 4);
    } else {
        GibSound(cent->lerpOrigin, state->number, "m_gibslop", 4);
        GibSound(cent->lerpOrigin, state->number, "m_gibmeat", 5);
    }
}

static void CloudParticle(const vec3_t origin, float spread, float speed, float radius, const vec3_t color,
                          float alpha, float fade, const char *shader) {
    particle_t *particle = &particles[nextParticle++ % DK_PARTICLES];
    vec3_t direction, angles;
    VectorSet(direction, Crandom(), Crandom(), Crandom());
    if (!VectorNormalize(direction)) VectorSet(direction, 0, 0, 1);
    vectoangles(direction, angles);
    angles[PITCH] += Crandom() * spread * 0.5f; angles[YAW] += Crandom() * spread * 0.5f;
    AngleVectors(angles, direction, NULL, NULL);
    memset(particle, 0, sizeof(*particle));
    particle->start = cg.time; particle->end = cg.time + (int)(alpha / fade * 1000);
    VectorCopy(origin, particle->origin);
    VectorScale(direction, speed * (0.55f + Random() * 0.45f), particle->velocity);
    VectorSet(particle->gravity, 0, 0, -100);
    VectorCopy(color, particle->color);
    particle->radius = radius; particle->alpha = alpha;
    particle->shader = trap_R_RegisterShader(shader);
}

/* ArtFx_BloodCloud with the scale of Gold's two-unit blood entity. Smoke atlas
   cells draw 7 units per scale step and the small cells 1.5. */
static void BloodCloud(centity_t *cent) {
    static const vec3_t red = {0.2f, 0, 0}, black = {0, 0, 0}, spark = {0.8f, 0.55f, 0.15f}, dust = {0.5f, 0.45f, 0.45f};
    entityState_t *state = &cent->currentState;
    const float sm = 2.3f / 85;
    int i, fragtype = state->dk3EffectDuration;
    vec3_t origin;
    VectorCopy(cent->lerpOrigin, origin);
    origin[0] += Crandom() * 2.3f * 0.85f; origin[1] += Crandom() * 2.3f * 0.85f;
    origin[2] += Crandom() * (state->dk3EffectMaxs[2] - state->dk3EffectMins[2]) * 0.25f;
    if (fragtype & DK_FRAG_ROBOTIC) {
        for (i = 0; i < 2; ++i)
            CloudParticle(origin, 360, 100, 3.5f * 3 * (0.5f + 80 * sm), black, 0.85f, 1.25f + Random() * 0.1f, "dk3/particle/smoke");
        for (i = 0; i < 3; ++i)
            CloudParticle(origin, 360, 100, 0.75f * 3 * (0.5f + 10 * sm), spark, 0.65f, 0.95f + Random() * 0.1f, "dk3/particle/sparks");
    } else if (fragtype & DK_FRAG_BONE) {
        for (i = 0; i < 3; ++i)
            CloudParticle(origin, 360, 100, 3.5f * 3 * (0.5f + 90 * sm), dust, 0.85f, 1.25f + Random() * 0.1f, "dk3/particle/smoke");
    } else {
        vec3_t offset;
        for (i = 0; i < 2; ++i) {
            VectorSet(offset, Crandom() * 5, Crandom() * 5, Crandom() * 5); VectorAdd(offset, origin, offset);
            CloudParticle(offset, 360, 100, 3.5f * 3 * (1.5f + 80 * sm), red, 0.45f, 1.65f + Random() * 0.1f, "dk3/particle/smoke");
        }
        for (i = 0; i < 3; ++i)
            CloudParticle(origin, 35, 50, 0.75f * 3 * (5.5f + 80 * sm), red, 0.55f, 0.8f + Random() * 0.1f, "dk3/particle/cp4");
    }
}

static void GibBurst(centity_t *cent) {
    entityState_t *state = &cent->currentState;
    int number = state->number, age = cg.time - state->dk3EffectStart;
    if (gibBurst[number] != state->dk3EffectStart) {
        gibBurst[number] = state->dk3EffectStart; gibStage[number] = 0; gibCloudTime[number] = 0;
    }
    randomState = (number + 1) * 2654435761u ^ (unsigned int)cg.time * 2246822519u;
    if (gibStage[number] == 0) { gibStage[number] = 1; if (age < 500) GibVolley(cent, qfalse); }
    if (gibStage[number] == 1 && age >= 200) { gibStage[number] = 2; GibVolley(cent, qtrue); }
    if (age >= 200 && age <= 700 && cg.time >= gibCloudTime[number] && !(state->dk3EffectDuration & DK_FRAG_NEVERGIB)) {
        gibCloudTime[number] = cg.time + 33;
        BloodCloud(cent);
    }
}

/* CL_DiminishingTrail for EF_GIB: a blood drop every two units of travel. */
static void GibTrail(dkGib_t *gib, const vec3_t from, const vec3_t to) {
    static const vec3_t red = {0.8f, 0, 0};
    vec3_t step, point;
    float length, orgScale = gib->trailCount > 700 ? 4 : gib->trailCount > 400 ? 2 : 1;
    float velScale = gib->trailCount > 700 ? 15 : gib->trailCount > 400 ? 10 : 5;
    VectorSubtract(to, from, step);
    length = VectorNormalize(step) + gib->trail;
    VectorMA(from, -gib->trail, step, point);
    while (length >= 2) {
        length -= 2;
        VectorMA(point, 2, step, point);
        if (((int)(Random() * 256) & 128) < gib->trailCount) {
            particle_t *particle = &particles[nextParticle++ % DK_PARTICLES];
            int axis;
            memset(particle, 0, sizeof(*particle));
            particle->start = cg.time; particle->end = cg.time + 1000;
            for (axis = 0; axis < 3; ++axis) particle->origin[axis] = point[axis] + Crandom() * orgScale;
            VectorSet(particle->velocity, Crandom() * velScale, Crandom() * velScale,
                      Random() > 0.7f ? Crandom() * velScale : 0);
            VectorSet(particle->gravity, 0, 0, -250);
            VectorCopy(red, particle->color);
            particle->radius = 0.75f * Random() * 5; particle->alpha = 1;
            particle->shader = trap_R_RegisterShader(va("dk3/particle/blood%d", 1 + (int)(Random() * 4) % 4));
        }
    }
    gib->trail = length;
    gib->trailCount = gib->trailCount > 105 ? gib->trailCount - 5 : 100;
}

static void UpdateGib(dkGib_t *gib, float seconds, int live) {
    refEntity_t model;
    int axis;
    if (!gib->resting) {
        trace_t trace;
        vec3_t end, from;
        gib->velocity[2] -= 800 * seconds;
        VectorMA(gib->angles, seconds, gib->spin, gib->angles);
        VectorMA(gib->origin, seconds, gib->velocity, end);
        CG_Trace(&trace, gib->origin, gib->mins, gib->maxs, end, ENTITYNUM_NONE, MASK_SOLID | CONTENTS_PLAYERCLIP);
        VectorCopy(gib->origin, from);
        if (trace.allsolid) { gib->active = qfalse; return; }
        VectorCopy(trace.endpos, gib->origin);
        if (!(gib->fragtype & DK_FRAG_NOBLOOD)) GibTrail(gib, from, gib->origin);
        if (trace.fraction < 1) {
            float speed = VectorLength(gib->velocity), backoff = DotProduct(gib->velocity, trace.plane.normal) * 1.5f;
            VectorMA(gib->velocity, -backoff, trace.plane.normal, gib->velocity);
            for (axis = 0; axis < 3; ++axis) gib->spin[axis] = Random() * speed * 2 - speed;
            if (trace.entityNum == ENTITYNUM_WORLD && Random() < 0.025f)
                GibSound(gib->origin, ENTITYNUM_WORLD, (gib->fragtype & DK_FRAG_ROBOTIC) ? "m_gibsurf" :
                    (gib->fragtype & DK_FRAG_BONE) ? "m_gibbone" : "m_gibslop",
                    (gib->fragtype & DK_FRAG_ROBOTIC) ? 2 : (gib->fragtype & DK_FRAG_BONE) ? 1 : 4);
            if (speed > 125 && !(gib->fragtype & DK_FRAG_NOBLOOD) && Random() < 0.15f)
                BloodSplat(trace.endpos, trace.plane.normal);
            /* The original stops once a bounce off the floor can no longer lift it. */
            if (trace.plane.normal[2] > 0.7f && gib->velocity[2] < 40) {
                gib->resting = qtrue; VectorClear(gib->velocity); VectorClear(gib->spin);
            }
        }
        if (gib->resting)
            gib->fadeTime = (cg.time > gib->start + 1500 ? cg.time : gib->start + 1500) + 5000 + (int)(Random() * 10000);
    } else if (cg.time >= gib->fadeTime) {
        float fader = live > 70 ? 3 * live / 100.0f : 1;
        int steps = (cg.time - gib->fadeTime) / 100 - gib->faded;
        if (steps > 0) { gib->alpha -= 0.15f * fader * steps; gib->faded += steps; }
        if (gib->alpha <= 0.1f) { gib->active = qfalse; return; }
    }
    memset(&model, 0, sizeof(model));
    model.reType = RT_MODEL; model.hModel = gib->model;
    VectorCopy(gib->origin, model.origin); VectorCopy(gib->origin, model.oldorigin);
    VectorCopy(gib->origin, model.lightingOrigin);
    AnglesToAxis(gib->angles, model.axis);
    for (axis = 0; axis < 3; ++axis) VectorScale(model.axis[axis], gib->scale[axis], model.axis[axis]);
    model.nonNormalizedAxes = qtrue;
    model.shaderRGBA[0] = model.shaderRGBA[1] = model.shaderRGBA[2] = 255;
    model.shaderRGBA[3] = 255 * Com_Clamp(0, 1, gib->alpha);
    model.customShader = gib->alpha < 1 ? gib->fadeSkin : gib->skin;
    if (gib->alpha < 1 && !gib->fadeSkin) model.skinNum = 1;
    trap_R_AddRefEntityToScene(&model);
}

static void Gibs(void) {
    static int lastTime;
    float seconds = Com_Clamp(0, 0.1f, (cg.time - lastTime) / 1000.0f);
    int i, live = LiveGibs();
    lastTime = cg.time;
    randomState ^= (unsigned int)cg.time * 2654435761u;
    for (i = 0; i < DK_GIBS; ++i) if (gibs[i].active) UpdateGib(&gibs[i], seconds, live);
}

static void Beam(centity_t *cent) {
    entityState_t *state = &cent->currentState;
    int i, segment, count = state->dk3EffectFlags & DK_FX_LIGHTNING ? 8 : 1;
    vec3_t previous, point, delta;
    if (count > 1 && cg.time - state->dk3EffectStart > state->dk3EffectDuration) return;
    if (state->dk3EffectFlags & DK_FX_LIGHT_AT_END)
        trap_R_AddLightToScene(state->dk3EffectEnd, 180, state->dk3EffectColor[0], state->dk3EffectColor[1], state->dk3EffectColor[2]);
    VectorCopy(cent->lerpOrigin, previous); VectorSubtract(state->dk3EffectEnd, previous, delta);
    for (segment = 1; segment <= count; ++segment) {
        VectorMA(cent->lerpOrigin, (float)segment / count, delta, point);
        if (segment != count) for (i = 0; i < 3; ++i) point[i] += (Random() - 0.5f) * 24;
        Ribbon(previous, point, state->dk3Scale, state->dk3EffectColor, state->dk3Alpha);
        VectorCopy(point, previous);
    }
}

/* Weather rates describe the whole volume; only the part near the viewer emits. */
static float WeatherCoverage(const entityState_t *state) {
    float coverage = 1;
    int axis;
    if (state->dk3Effect < DK_FX_RAIN || state->dk3Effect > DK_FX_DRIP) return 1;
    for (axis = 0; axis < 2; ++axis) {
        float low = state->dk3EffectMins[axis], high = state->dk3EffectMaxs[axis], size = high - low;
        if (size <= 0) return 0;
        if (low < cg.refdef.vieworg[axis] - 512) low = cg.refdef.vieworg[axis] - 512;
        if (high > cg.refdef.vieworg[axis] + 512) high = cg.refdef.vieworg[axis] + 512;
        if (low >= high) return 0;
        coverage *= (high - low) / size;
    }
    return coverage;
}

static void Emit(centity_t *cent, int count, qboolean fill) {
    entityState_t *state = &cent->currentState;
    int i, axis;
    qboolean weather = state->dk3Effect >= DK_FX_RAIN && state->dk3Effect <= DK_FX_DRIP;
    for (i = 0; i < count && emitted < DK_EMIT_BUDGET; ++i, ++emitted) {
        vec3_t point, velocity;
        int duration = state->dk3EffectDuration;
        float radius = state->dk3Scale;
        if (weather) {
            /* Like the original's exhausted particle list, stop spawning rather
               than recycling drops that have not landed and splashed yet. */
            const particle_t *next = &particles[nextParticle % DK_PARTICLES];
            if (cg.time < next->end + (next->splash ? 101 : 0) && next->start <= cg.time) return;
            for (axis = 0; axis < 2; ++axis) {
                float low = state->dk3EffectMins[axis], high = state->dk3EffectMaxs[axis];
                if (low < cg.refdef.vieworg[axis] - 512) low = cg.refdef.vieworg[axis] - 512;
                if (high > cg.refdef.vieworg[axis] + 512) high = cg.refdef.vieworg[axis] + 512;
                if (low >= high) return;
                point[axis] = low + Random() * (high - low);
            }
            point[2] = state->dk3EffectMaxs[2];
            if (point[2] > cg.refdef.vieworg[2] + 384) point[2] = cg.refdef.vieworg[2] + 384;
            if (point[2] < state->dk3EffectMins[2]) return;
            /* A sparse volume is filled throughout its height, not only from the top. */
            if (fill) point[2] = state->dk3EffectMins[2] + Random() * (point[2] - state->dk3EffectMins[2]);
            VectorSet(velocity, state->dk3EffectEnd[0], state->dk3EffectEnd[1], -state->dk3EffectSpeed);
            if (state->dk3Effect == DK_FX_SNOW) {
                velocity[0] += (Random() * 2 - 1) * state->dk3EffectSpread;
                velocity[1] += (Random() * 2 - 1) * state->dk3EffectSpread;
                velocity[2] -= (int)(Random() * 16) & 10;
            }
            duration = Com_Clamp(50, 60000, (point[2] - state->dk3EffectMins[2]) / -velocity[2] * 1000);
            radius = state->dk3Effect == DK_FX_SNOW ? 1.15f : 0.65f;
        } else {
            VectorCopy(cent->lerpOrigin, point);
            if (state->dk3EffectRadius > 0) {
                float angle = Random() * 2 * M_PI, distance = sqrt(Random()) * state->dk3EffectRadius;
                vec3_t axis, right, up;
                VectorSubtract(state->dk3EffectEnd, point, axis);
                if (!VectorNormalize(axis)) VectorSet(axis, 0, 0, 1);
                PerpendicularVector(right, axis); CrossProduct(axis, right, up);
                VectorMA(point, cos(angle) * distance, right, point);
                VectorMA(point, sin(angle) * distance, up, point);
            }
            VectorSubtract(state->dk3EffectEnd, point, velocity);
            if (!VectorNormalize(velocity)) VectorSet(velocity, 0, 0, 1);
            {
                vec3_t angles;
                vectoangles(velocity, angles);
                angles[PITCH] += (Random() * 2 - 1) * state->dk3EffectSpread;
                angles[YAW] += (Random() * 2 - 1) * state->dk3EffectSpread;
                AngleVectors(angles, velocity, NULL, NULL);
            }
            VectorScale(velocity, state->dk3EffectSpeed * (0.55f + Random() * 0.45f), velocity);
            radius *= 0.5f + Random();
            radius *= state->dk3EffectFlags & DK_FX_SMOKE ? 10.5f : 2.25f;
        }
        AddParticle(state, point, velocity, duration, radius, (state->dk3EffectFlags & DK_FX_SMOKE) != 0);
    }
}

static void Spotlight(centity_t *cent) {
    const entityState_t *state = &cent->currentState;
    vec3_t forward, right, up;
    float length, nearRadius = state->dk3EffectRadius, farRadius;
    int side, vertex, axis;
    qhandle_t shader = trap_R_RegisterShader("dk3/fx/beam");
    VectorSubtract(state->dk3EffectEnd, cent->lerpOrigin, forward);
    length = VectorNormalize(forward);
    if (length < 1) return;
    PerpendicularVector(right, forward); CrossProduct(forward, right, up);
    farRadius = nearRadius + length * 0.2f;
    for (side = 0; side < 16; ++side) {
        polyVert_t polygon[4];
        for (vertex = 0; vertex < 4; ++vertex) {
            qboolean far = vertex >= 2;
            float angle = (side + (vertex == 1 || vertex == 2)) * 2 * M_PI / 16;
            float radius = far ? farRadius : nearRadius;
            VectorCopy(far ? state->dk3EffectEnd : cent->lerpOrigin, polygon[vertex].xyz);
            VectorMA(polygon[vertex].xyz, cos(angle) * radius, right, polygon[vertex].xyz);
            VectorMA(polygon[vertex].xyz, sin(angle) * radius, up, polygon[vertex].xyz);
            polygon[vertex].st[0] = 0.5f; polygon[vertex].st[1] = far ? 1 : 0;
            for (axis = 0; axis < 3; ++axis) polygon[vertex].modulate[axis] = state->dk3EffectColor[axis] * 255;
            polygon[vertex].modulate[3] = far ? 0 : 45;
        }
        trap_R_AddPolyToScene(shader, 4, polygon);
    }
    trap_R_AddLightToScene(state->dk3EffectEnd, 100, state->dk3EffectColor[0], state->dk3EffectColor[1], state->dk3EffectColor[2]);
}

void DK_DrawSpotlightSource(centity_t *cent, const refEntity_t *model) {
    const entityState_t *state = &cent->currentState;
    orientation_t tag;
    vec3_t origin;
    int axis;
    if (state->dk3Effect != DK_FX_SPOTLIGHT || !(state->dk3EffectFlags & DK_FX_ENABLED)) return;
    VectorCopy(model->origin, origin);
    if (trap_R_LerpTag(&tag, model->hModel, model->oldframe, model->frame, 1 - model->backlerp, "hr_light"))
        for (axis = 0; axis < 3; ++axis) VectorMA(origin, tag.origin[axis], model->axis[axis], origin);
    /* An alerted camera publishes its red cone; the original swaps to the red flare with it. */
    DK_DrawSpriteAt(state->dk3EffectColor[1] < 0.3f ? "models/global/e_sflred.sp2" : "models/e1/me_cambotf.sp2",
        cg.time / 100, origin, cent->lerpAngles, 3, 1, state->dk3EffectColor, DK_SPRITE_ADDITIVE);
    trap_R_AddLightToScene(origin, 225, state->dk3EffectColor[0], state->dk3EffectColor[1], state->dk3EffectColor[2]);
}

void DK_DrawWorldEffect(centity_t *cent) {
    entityState_t *state = &cent->currentState;
    int number = state->number, count, elapsed, fill = 0;
    float coverage;
    if (number < 0 || number >= MAX_GENTITIES || !(state->dk3EffectFlags & DK_FX_ENABLED)) return;
    if (budgetTime != cg.time) { budgetTime = cg.time; emitted = 0; }
    randomState = number * 2654435761u + cg.time / 32;
    if (state->dk3Effect == DK_FX_DEBRIS) {
        if (generation[number] != state->dk3EffectStart) { generation[number] = state->dk3EffectStart; Debris(cent); }
        return;
    }
    if (state->dk3Effect == DK_FX_GIB) { GibBurst(cent); return; }
    if (state->dk3Effect == DK_FX_SPOTLIGHT) { Spotlight(cent); return; }
    if (state->dk3Effect == DK_FX_BEAM) { Beam(cent); return; }
    if (state->dk3Effect == DK_FX_QUAKE || state->dk3Effect == DK_FX_NONE) return;
    if (state->dk3Effect == DK_FX_FLAME || state->dk3Effect == DK_FX_FLARE || state->dk3Effect == DK_FX_LIGHT) {
        float intensity = state->dk3Alpha;
        if (state->dk3EffectFlags & DK_FX_STROBE) intensity *= ((cg.time / 120 + number) & 1) ? 1 : 0.12f;
        if (state->dk3Effect == DK_FX_FLAME) intensity *= 0.8f + 0.2f * sin(cg.time * 0.009f + number);
        if (state->dk3Effect == DK_FX_LIGHT)
            trap_R_AddLightToScene(cent->lerpOrigin, state->dk3EffectRadius * intensity,
                state->dk3EffectColor[0], state->dk3EffectColor[1], state->dk3EffectColor[2]);
        if (state->dk3Effect == DK_FX_FLARE) {
            /* Hidden when the eye trace stops more than 16 units short; drawn halfway
               to the viewer, fading out and shrinking by 1024 units. */
            static const vec3_t white = {1, 1, 1};
            trace_t trace;
            vec3_t toward, origin;
            float length, alpha, width, height;
            CG_Trace(&trace, cg.refdef.vieworg, NULL, NULL, cent->lerpOrigin, cg.snap->ps.clientNum, MASK_SOLID);
            if (trace.allsolid || trace.startsolid) return;
            VectorSubtract(cg.refdef.vieworg, cent->lerpOrigin, toward);
            length = VectorNormalize(toward);
            if ((1 - trace.fraction) * length > 16) return;
            length = (int)length >> 1;
            alpha = 1 - length / 512;
            if (alpha <= 0) return;
            width = (state->dk3EffectEnd[0] > 0 ? state->dk3EffectEnd[0] : state->dk3Scale) + alpha;
            height = (state->dk3EffectEnd[1] > 0 ? state->dk3EffectEnd[1] : state->dk3Scale) + alpha;
            VectorMA(cent->lerpOrigin, length, toward, origin);
            DK_DrawSpriteScaled(CG_ConfigString(CS_MODELS + state->modelindex), 0, origin, cent->lerpAngles,
                                width, height, alpha * intensity, white, state->dk3RenderFlags | 2);
        } else if (state->dk3Effect != DK_FX_LIGHT) {
            centity_t sprite = *cent;
            sprite.currentState.frame = (cg.time - state->dk3EffectStart) / 100;
            sprite.currentState.dk3RenderFlags |= 2; sprite.currentState.dk3Alpha *= intensity;
            DK_DrawSprite(&sprite);
            if (state->dk3Effect == DK_FX_FLAME) {
                sprite.lerpAngles[YAW] += 90;
                DK_DrawSprite(&sprite);
            }
        }
        return;
    }
    if (state->dk3Effect == DK_FX_FIREFLIES) {
        int i;
        for (i = 0; i < (int)state->dk3EffectRate && i < 64; ++i) {
            vec3_t point;
            float phase = cg.time * (state->dk3EffectSpeed > 0 ? state->dk3EffectSpeed : 50) / 5000.0f + i * 2.39996f + number;
            VectorCopy(cent->lerpOrigin, point);
            point[0] += cos(phase) * state->dk3EffectRadius;
            point[1] += sin(phase * 1.13f) * state->dk3EffectRadius;
            point[2] += sin(phase * 0.73f) * state->dk3EffectRadius * 0.5f;
            Sprite(point, 2 * state->dk3Scale, state->dk3EffectColor, state->dk3Alpha * (0.6f + 0.4f * sin(phase * 2)),
                   trap_R_RegisterShader("dk3/fx/glow"));
        }
        return;
    }
    if (generation[number] != state->dk3EffectStart || emissionTime[number] > cg.time) {
        generation[number] = state->dk3EffectStart; emissionTime[number] = cg.time; carry[number] = 0;
    }
    elapsed = cg.time - emissionTime[number];
    if (elapsed > 100) elapsed = 100;
    emissionTime[number] = cg.time;
    /* Each frame emits a fresh sequence: a coarse time seed would repeat spawn
       positions, and nearby LCG seeds correlate their first outputs. */
    randomState = (number + 1) * 2654435761u ^ (unsigned int)cg.time * 2246822519u;
    randomState ^= randomState >> 15; randomState *= 2246822519u; randomState ^= randomState >> 13;
    coverage = WeatherCoverage(state);
    carry[number] += state->dk3EffectRate * coverage * elapsed / 1000.0f;
    count = (int)carry[number]; carry[number] -= count;
    if (state->dk3Effect >= DK_FX_RAIN && state->dk3Effect <= DK_FX_DRIP && coverage > 0) {
        /* Population is rate times fall time; below a quarter of it, the original
           spawns another quarter at once. */
        float top = state->dk3EffectMaxs[2] < cg.refdef.vieworg[2] + 384 ? state->dk3EffectMaxs[2] : cg.refdef.vieworg[2] + 384;
        int population = state->dk3EffectRate * coverage * (top - state->dk3EffectMins[2]) / state->dk3EffectSpeed;
        if (weatherActive[number] < population / 4 && population >= 4) {
            fill = population / 4;
            carry[number] = 0;
        }
    }
    if (fill) { if (fill > 24) fill = 24; Emit(cent, fill, qtrue); return; }
    if (count > 24) count = 24;
    Emit(cent, count, qfalse);
}

void DK_ShakeView(void) {
    int i;
    float strength = 0;
    if (!cg.snap) return;
    for (i = 0; i < cg.snap->numEntities; ++i) {
        entityState_t *state = &cg.snap->entities[i];
        float distance, falloff;
        if (state->eType != ET_DK3_EFFECT || state->dk3Effect != DK_FX_QUAKE ||
            !(state->dk3EffectFlags & DK_FX_ENABLED) || state->dk3EffectRadius <= 0) continue;
        distance = Distance(cg.refdef.vieworg, state->pos.trBase);
        falloff = 1 - distance / state->dk3EffectRadius;
        if (falloff > 0) strength += state->dk3EffectSpeed * falloff * 0.01f;
    }
    if (cg.predictedPlayerState.dk3PsyEnd > cg.time) {
        float fade = Com_Clamp(0, 1, (cg.predictedPlayerState.dk3PsyEnd - cg.time) / 3000.0f);
        cg.refdef.fov_x += sin(cg.time * 0.007f) * 12 * fade;
        cg.refdef.fov_y += cos(cg.time * 0.005f) * 8 * fade;
        cg.refdefViewAngles[ROLL] += sin(cg.time * 0.009f) * 8 * fade;
    }
    strength = Com_Clamp(0, 8, strength);
    cg.refdef.vieworg[2] += sin(cg.time * 0.071f) * strength;
    cg.refdefViewAngles[ROLL] += sin(cg.time * 0.053f) * strength * 0.5f;
    AnglesToAxis(cg.refdefViewAngles, cg.refdef.viewaxis);
}
