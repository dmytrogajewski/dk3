/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "cg_local.h"
#include "dk_effects.h"

#define DK_PARTICLES 2048
#define DK_EMIT_BUDGET 192

typedef struct {
    int start, end;
    vec3_t origin, velocity, gravity, color;
    float radius, alpha;
    qhandle_t shader;
    qboolean smoke, streak;
} particle_t;
static particle_t particles[DK_PARTICLES];
static int nextParticle, budgetTime, emitted;
static int emissionTime[MAX_GENTITIES], generation[MAX_GENTITIES];
static float carry[MAX_GENTITIES];
static unsigned int randomState;

void DK_ResetWorldEffects(void) {
    memset(particles, 0, sizeof(particles));
    memset(emissionTime, 0, sizeof(emissionTime));
    memset(generation, 0, sizeof(generation));
    memset(carry, 0, sizeof(carry));
    nextParticle = budgetTime = emitted = 0;
}

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

static void AddParticle(entityState_t *state, const vec3_t origin, const vec3_t velocity, int duration, float radius, qboolean smoke) {
    particle_t *particle = &particles[nextParticle++ % DK_PARTICLES];
    trace_t trace;
    vec3_t end;
    float seconds = duration / 1000.0f;
    particle->start = cg.time; particle->end = cg.time + duration;
    VectorCopy(origin, particle->origin); VectorCopy(velocity, particle->velocity);
    VectorCopy(state->dk3EffectGravity, particle->gravity); VectorCopy(state->dk3EffectColor, particle->color);
    particle->radius = radius; particle->alpha = state->dk3Alpha; particle->smoke = smoke;
    particle->streak = (state->dk3EffectFlags & DK_FX_STREAK) != 0;
    particle->shader = trap_R_RegisterShader(smoke ? "dk3/particle/smoke" :
        state->dk3EffectFlags & DK_FX_BUBBLE ? "dk3/particle/bubble" :
        state->dk3Effect == DK_FX_SNOW ? "dk3/particle/snow" : "dk3/particle/simple");
    if (state->dk3EffectFlags & DK_FX_PARTICLE_MASK) {
        int kind = (state->dk3EffectFlags & DK_FX_PARTICLE_MASK) >> DK_FX_PARTICLE_SHIFT;
        particle->shader = trap_R_RegisterShader(va("dk3/particle/cp%d", kind));
    }
    VectorMA(origin, seconds, velocity, end); VectorMA(end, 0.5f * seconds * seconds, particle->gravity, end);
    CG_Trace(&trace, origin, NULL, NULL, end, ENTITYNUM_NONE, MASK_SOLID);
    if (trace.startsolid) particle->end = cg.time;
    else if (trace.fraction < 1) particle->end = cg.time + (int)(duration * trace.fraction);
}

void DK_AddWorldParticles(void) {
    int i;
    for (i = 0; i < DK_PARTICLES; ++i) {
        particle_t *particle = &particles[i];
        vec3_t point;
        float seconds, life, radius;
        if (particle->end <= cg.time || particle->start > cg.time) continue;
        seconds = (cg.time - particle->start) / 1000.0f;
        life = (particle->end - cg.time) / (float)(particle->end - particle->start);
        VectorMA(particle->origin, seconds, particle->velocity, point);
        VectorMA(point, 0.5f * seconds * seconds, particle->gravity, point);
        radius = particle->radius;
        if (particle->streak) {
            vec3_t tail;
            float nearFade = Com_Clamp(0, 1, (Distance(point, cg.refdef.vieworg) - 16) / 48);
            VectorMA(point, -0.025f, particle->velocity, tail);
            Ribbon(tail, point, radius, particle->color, particle->alpha * life * nearFade * 0.6f);
        } else AtlasParticle(point, radius, particle->color, particle->alpha * life, particle->shader);
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
        piece->refEntity.hModel = model; AxisClear(piece->refEntity.axis);
        VectorCopy(piece->pos.trBase, piece->refEntity.origin);
    }
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

static void Emit(centity_t *cent, int count) {
    entityState_t *state = &cent->currentState;
    int i, axis;
    qboolean weather = state->dk3Effect >= DK_FX_RAIN && state->dk3Effect <= DK_FX_DRIP;
    for (i = 0; i < count && emitted < DK_EMIT_BUDGET; ++i, ++emitted) {
        vec3_t point, velocity;
        int duration = state->dk3EffectDuration;
        float radius = state->dk3Scale;
        if (weather) {
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
            VectorSet(velocity, state->dk3EffectEnd[0], state->dk3EffectEnd[1], -state->dk3EffectSpeed);
            if (state->dk3Effect == DK_FX_SNOW) velocity[0] += (Random() - 0.5f) * 30;
            duration = Com_Clamp(50, 12000, (point[2] - state->dk3EffectMins[2]) / state->dk3EffectSpeed * 1000);
            radius = state->dk3Effect == DK_FX_SNOW ? 1.8f : 0.65f;
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
    DK_DrawSpriteAt("models/e1/me_cambotf.sp2", cg.time / 100, origin, cent->lerpAngles,
        3, 1, state->dk3EffectColor, DK_SPRITE_ADDITIVE);
    trap_R_AddLightToScene(origin, 225, state->dk3EffectColor[0], state->dk3EffectColor[1], state->dk3EffectColor[2]);
}

void DK_DrawWorldEffect(centity_t *cent) {
    entityState_t *state = &cent->currentState;
    int number = state->number, count, elapsed;
    if (number < 0 || number >= MAX_GENTITIES || !(state->dk3EffectFlags & DK_FX_ENABLED)) return;
    if (budgetTime != cg.time) { budgetTime = cg.time; emitted = 0; }
    randomState = number * 2654435761u + cg.time / 32;
    if (state->dk3Effect == DK_FX_DEBRIS) {
        if (generation[number] != state->dk3EffectStart) { generation[number] = state->dk3EffectStart; Debris(cent); }
        return;
    }
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
        if (state->dk3Effect != DK_FX_LIGHT) {
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
    carry[number] += state->dk3EffectRate * elapsed / 1000.0f;
    count = (int)carry[number]; carry[number] -= count;
    if (count > 24) count = 24;
    Emit(cent, count);
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
    strength = Com_Clamp(0, 8, strength);
    cg.refdef.vieworg[2] += sin(cg.time * 0.071f) * strength;
    cg.refdefViewAngles[ROLL] += sin(cg.time * 0.053f) * strength * 0.5f;
    AnglesToAxis(cg.refdefViewAngles, cg.refdef.viewaxis);
}
