/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_effects.h"

static float Value(const char *key, const char *fallback, float minimum, float maximum) {
    float value;
    G_SpawnFloat(key, fallback, &value);
    if (Q_isnan(value)) G_Error("dk3: invalid effect value %s", key);
    return Com_Clamp(minimum, maximum, value);
}

static char *Text(const char *key) {
    char *value;
    return G_SpawnString(key, "", &value) && *value ? G_NewString(value) : NULL;
}

static float Random(gentity_t *entity) {
    entity->dk.soundRandom = entity->dk.soundRandom * 1664525u + 1013904223u;
    return (entity->dk.soundRandom >> 8) / 16777216.0f;
}

static void StartParticles(gentity_t *entity, qboolean enabled) {
    entity->dk.effectActive = enabled;
    if (enabled) entity->s.dk3EffectFlags |= DK_FX_ENABLED;
    else entity->s.dk3EffectFlags &= ~DK_FX_ENABLED;
    entity->s.dk3EffectStart = level.time;
    entity->dk.effectNextCycle = level.time + entity->dk.effectOnTime;
    entity->dk.expires = enabled && entity->dk.effectStopTime ? level.time + entity->dk.effectStopTime : 0;
}

static void EffectUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    (void)other;
    entity->s.dk3EffectFlags ^= DK_FX_ENABLED;
    entity->s.dk3EffectStart = level.time;
    entity->activator = activator;
    if (entity->s.dk3Effect == DK_FX_PARTICLES) {
        StartParticles(entity, !(entity->spawnflags & 2048) || !entity->dk.effectActive);
    } else if (entity->s.dk3Effect == DK_FX_BEAM && (entity->s.dk3EffectFlags & DK_FX_LIGHTNING)) {
        /* A triggered one-shot cannot be cancelled by another trigger in the same frame. */
        if (entity->spawnflags & 128) entity->s.dk3EffectFlags |= DK_FX_ENABLED;
        entity->dk.nextUse = level.time;
        entity->dk.expires = 0;
    }
    if (entity->s.dk3Effect == DK_FX_QUAKE) {
        entity->s.dk3EffectFlags |= DK_FX_ENABLED;
        entity->dk.expires = level.time + entity->s.dk3EffectDuration;
    }
    entity->nextthink = level.time + FRAMETIME;
    trap_LinkEntity(entity);
}

static void Aim(gentity_t *entity) {
    gentity_t *target = DK_FindNamed(entity->target);
    vec3_t direction;
    if (target && target != entity) {
        VectorCopy(target->r.currentOrigin, entity->s.dk3EffectEnd);
        if (target->r.bmodel) {
            VectorAdd(target->r.absmin, target->r.absmax, entity->s.dk3EffectEnd);
            VectorScale(entity->s.dk3EffectEnd, 0.5f, entity->s.dk3EffectEnd);
        }
    } else {
        AngleVectors(entity->s.angles, direction, NULL, NULL);
        if (!entity->s.angles[0] && !entity->s.angles[1] && entity->s.dk3Effect == DK_FX_PARTICLES) VectorSet(direction, 0, 0, 1);
        VectorMA(entity->r.currentOrigin, entity->s.dk3Effect == DK_FX_SPOTLIGHT ? entity->s.dk3EffectSpeed : 8192, direction, entity->s.dk3EffectEnd);
    }
}

static void LightningAim(gentity_t *entity) {
    gentity_t *target = NULL, *candidate = NULL;
    int i, count = 0;
    if (!(entity->spawnflags & 32) && Random(entity) < entity->dk.effectChance) {
        for (i = 0; i < level.maxclients; ++i) {
            gentity_t *player = &g_entities[i];
            if (!player->inuse || !player->client || player->health <= 0 ||
                player->client->sess.sessionTeam == TEAM_SPECTATOR ||
                Distance(entity->r.currentOrigin, player->r.currentOrigin) > 2048 || !CanDamage(player, entity->r.currentOrigin)) continue;
            if (++count == 1 || Random(entity) < 1.0f / count) target = player;
        }
    }
    if (target) {
        VectorCopy(target->r.currentOrigin, entity->s.dk3EffectEnd);
        entity->s.dk3EffectEnd[2] += target->client->ps.viewheight / 2;
        return;
    }
    if ((entity->spawnflags & 4) && (!entity->target || Random(entity) < entity->dk.effectGroundChance)) {
        entity->s.dk3EffectEnd[0] = entity->r.currentOrigin[0] + (Random(entity) - 0.5f) * 2048;
        entity->s.dk3EffectEnd[1] = entity->r.currentOrigin[1] + (Random(entity) - 0.5f) * 2048;
        entity->s.dk3EffectEnd[2] = entity->r.currentOrigin[2] - 8192;
        return;
    }
    count = 0;
    if (entity->target) while ((candidate = G_Find(candidate, FOFS(targetname), entity->target)) != NULL) {
        if (entity->spawnflags & 2) {
            if (candidate->count > entity->count && (!target || candidate->count < target->count)) target = candidate;
        } else if (++count == 1 || Random(entity) < 1.0f / count) target = candidate;
    }
    if (!target && (entity->spawnflags & 2) && entity->target) {
        while ((candidate = G_Find(candidate, FOFS(targetname), entity->target)) != NULL)
            if (!target || candidate->count < target->count) target = candidate;
    }
    if (target) {
        entity->count = target->count;
        VectorCopy(target->r.currentOrigin, entity->s.dk3EffectEnd);
    } else Aim(entity);
}

static void BeamThink(gentity_t *entity) {
    trace_t trace;
    vec3_t direction;
    qboolean lightning = (entity->s.dk3EffectFlags & DK_FX_LIGHTNING) != 0;
    entity->nextthink = level.time + 100;
    if (!(entity->s.dk3EffectFlags & DK_FX_ENABLED)) return;
    if (lightning) {
        if (!(entity->spawnflags & 512) && level.time >= entity->dk.expires) {
            if (entity->dk.expires && (entity->spawnflags & 128)) {
                entity->s.dk3EffectFlags &= ~DK_FX_ENABLED;
                return;
            }
            if (level.time < entity->dk.nextUse) return;
        }
        if (!entity->dk.expires || level.time >= entity->dk.expires) {
            int index = entity->dk.soundCount ? entity->dk.soundIndices[(int)(Random(entity) * entity->dk.soundCount)] : 0;
            LightningAim(entity);
            if (index) G_AddEvent(entity, EV_GENERAL_SOUND, index);
            entity->s.dk3EffectStart = level.time;
            entity->dk.expires = level.time + entity->s.dk3EffectDuration;
            entity->dk.nextUse = entity->dk.expires + (int)(entity->wait * 1000 *
                (entity->spawnflags & 8 ? 0.25f + Random(entity) * 0.75f : 1));
        }
    } else Aim(entity);
    trap_Trace(&trace, entity->r.currentOrigin, NULL, NULL, entity->s.dk3EffectEnd, entity->s.number, MASK_SHOT);
    if (!lightning) VectorCopy(trace.endpos, entity->s.dk3EffectEnd);
    if (entity->damage > 0 && trace.entityNum < ENTITYNUM_WORLD) {
        VectorSubtract(trace.endpos, entity->r.currentOrigin, direction);
        G_Damage(&g_entities[trace.entityNum], entity, entity->activator ? entity->activator : entity,
                 direction, trace.endpos, entity->damage, 0, MOD_TRIGGER_HURT);
    }
    trap_LinkEntity(entity);
}

static void EffectThink(gentity_t *entity) {
    int i;
    entity->nextthink = level.time + 100;
    if (entity->s.dk3Effect == DK_FX_QUAKE && (entity->s.dk3EffectFlags & DK_FX_ENABLED)) {
        if (level.time >= entity->dk.expires) { entity->s.dk3EffectFlags &= ~DK_FX_ENABLED; return; }
        for (i = 0; i < level.maxclients; ++i) {
            gentity_t *player = &g_entities[i];
            float distance = Distance(player->r.currentOrigin, entity->r.currentOrigin);
            if (!player->inuse || !player->client || player->health <= 0 ||
                player->client->ps.groundEntityNum == ENTITYNUM_NONE || distance > entity->s.dk3EffectRadius) continue;
            player->client->ps.velocity[2] = entity->s.dk3EffectSpeed * (1 - distance / entity->s.dk3EffectRadius);
            player->client->ps.groundEntityNum = ENTITYNUM_NONE;
        }
    } else if (entity->s.dk3Effect == DK_FX_PARTICLES) {
        if (entity->dk.effectActive && entity->dk.expires && level.time >= entity->dk.expires)
            StartParticles(entity, qfalse);
        if (entity->dk.effectActive && entity->dk.effectOffTime && level.time >= entity->dk.effectNextCycle) {
            entity->s.dk3EffectFlags ^= DK_FX_ENABLED;
            entity->s.dk3EffectStart = level.time;
            if (entity->s.dk3EffectFlags & DK_FX_ENABLED)
                entity->dk.effectNextCycle = level.time + entity->dk.effectOnTime;
            else entity->dk.effectNextCycle = level.time + (int)(entity->dk.effectOffTime *
                (entity->spawnflags & 512 ? 0.25f + Random(entity) * 0.75f : 1));
        }
        Aim(entity);
        if (entity->dk.mediaPath) {
            gentity_t *gravity = DK_FindNamed(entity->dk.mediaPath);
            if (gravity) {
                float amount = VectorLength(entity->s.dk3EffectGravity);
                VectorSubtract(gravity->r.currentOrigin, entity->r.currentOrigin, entity->s.dk3EffectGravity);
                VectorNormalize(entity->s.dk3EffectGravity);
                VectorScale(entity->s.dk3EffectGravity, amount, entity->s.dk3EffectGravity);
            }
        }
    }
}

void DK_WorldDebris(gentity_t *entity, int material) {
    gentity_t *burst = G_Spawn();
    vec3_t center;
    VectorCopy(entity->r.currentOrigin, center);
    if (entity->r.bmodel) { VectorAdd(entity->r.absmin, entity->r.absmax, center); VectorScale(center, 0.5f, center); }
    burst->classname = "dk3_debris_burst";
    burst->s.eType = ET_DK3_EFFECT;
    burst->s.dk3Effect = DK_FX_DEBRIS;
    burst->s.dk3EffectFlags = DK_FX_ENABLED;
    burst->s.dk3EffectStart = level.time;
    burst->s.dk3EffectDuration = material;
    burst->s.dk3EffectRate = entity->count > 0 ? Com_Clamp(1, 64, entity->count) : 12;
    burst->s.dk3EffectSpeed = entity->speed > 0 ? entity->speed : 180;
    VectorSubtract(entity->r.maxs, entity->r.mins, burst->s.dk3EffectMaxs);
    G_SetOrigin(burst, center);
    burst->think = G_FreeEntity; burst->nextthink = level.time + 500;
    trap_LinkEntity(burst);
}

static int Material(gentity_t *entity) {
    if (strstr(entity->classname, "gib")) return DK_DEBRIS_FLESH;
    if (entity->spawnflags & 16) return DK_DEBRIS_WOOD;
    if (entity->spawnflags & 8) return DK_DEBRIS_METAL;
    if (entity->spawnflags & 4) return DK_DEBRIS_GLASS;
    return DK_DEBRIS_STONE;
}

static void Destroy(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    unsigned int id = entity->dk.id;
    (void)other;
    if (entity->dk.uses) return;
    entity->dk.uses = 1;
    DK_WorldDebris(entity, Material(entity));
    if (entity->noise_index) G_TempEntity(entity->r.currentOrigin, EV_GENERAL_SOUND)->s.eventParm = entity->noise_index;
    if (entity->damage > 0) G_RadiusDamage(entity->r.currentOrigin, activator,
        entity->damage, entity->splashRadius > 0 ? entity->splashRadius : 160, entity, MOD_TRIGGER_HURT);
    entity->takedamage = qfalse;
    G_UseTargets(entity, activator);
    if (entity->inuse && entity->dk.id == id) G_FreeEntity(entity);
}

static void DestroyDie(gentity_t *entity, gentity_t *inflictor, gentity_t *attacker, int damage, int mod) {
    (void)damage; (void)mod;
    Destroy(entity, inflictor, attacker);
}

static void GibThink(gentity_t *entity) {
    if (!(entity->s.dk3EffectFlags & DK_FX_ENABLED)) { entity->nextthink = 0; return; }
    DK_WorldDebris(entity, DK_DEBRIS_FLESH);
    if (entity->dk.expires && level.time >= entity->dk.expires) entity->s.dk3EffectFlags &= ~DK_FX_ENABLED;
    entity->nextthink = level.time + (int)(entity->wait * 1000);
}

static void GibUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    EffectUse(entity, other, activator);
    entity->dk.expires = entity->s.dk3EffectDuration ? level.time + entity->s.dk3EffectDuration : 0;
    G_UseTargets(entity, activator);
}

static void RampThink(gentity_t *entity) {
    gentity_t *light = NULL;
    float fraction = Com_Clamp(0, 1, (level.time - entity->s.dk3EffectStart) / (float)entity->s.dk3EffectDuration);
    float start = entity->message[entity->dk.action ? 1 : 0] - 'a';
    float finish = entity->message[entity->dk.action ? 0 : 1] - 'a';
    while ((light = G_Find(light, FOFS(targetname), entity->target)) != NULL) {
        if (light->s.eType != ET_DK3_EFFECT) continue;
        light->s.dk3EffectFlags |= DK_FX_ENABLED;
        light->s.dk3Alpha = (start + fraction * (finish - start)) / 25.0f;
    }
    if (fraction < 1) entity->nextthink = level.time + 100;
    else if (entity->spawnflags & 1) entity->dk.action ^= 1;
}

static void RampUse(gentity_t *entity, gentity_t *other, gentity_t *activator) {
    (void)other; (void)activator;
    entity->s.dk3EffectStart = level.time;
    entity->nextthink = level.time + FRAMETIME;
}

qboolean DK_SpawnWorldEffect(gentity_t *entity) {
    const char *name = entity->classname;
    char *value;
    int kind = DK_FX_NONE, axis;
    if (!strcmp(name, "func_wall_explode") || !strcmp(name, "func_debris") || !strcmp(name, "func_debris_visible")) {
        if (!entity->model) G_Error("dk3: %s %u has no brush model", name, entity->dk.id);
        trap_SetBrushModel(entity, entity->model);
        G_SetOrigin(entity, entity->s.origin); entity->r.contents = CONTENTS_SOLID;
        entity->s.eType = ET_MOVER; entity->dk.decorKind = -2;
        entity->use = Destroy; entity->die = DestroyDie;
        entity->takedamage = entity->health > 0;
        entity->speed = Value("velocity", "180", 1, 2000);
        value = Text("sound"); if (value) entity->noise_index = DK_SoundIndex(value);
        trap_LinkEntity(entity); return qtrue;
    }
    if (!strcmp(name, "target_lightramp")) {
        if (!entity->target || !entity->message || strlen(entity->message) != 2 ||
            entity->message[0] < 'a' || entity->message[0] > 'z' || entity->message[1] < 'a' || entity->message[1] > 'z')
            G_Error("dk3: light ramp %u requires a target and two brightness letters", entity->dk.id);
        entity->s.eType = ET_DK3_EFFECT; entity->r.svFlags |= SVF_NOCLIENT;
        entity->s.dk3EffectDuration = (int)(Value("speed", "1", 0.01f, 3600) * 1000);
        entity->think = RampThink; entity->use = RampUse; return qtrue;
    }
    if (!strcmp(name, "func_gib")) {
        entity->s.eType = ET_DK3_EFFECT; entity->r.svFlags |= SVF_NOCLIENT;
        entity->wait = Value("wait", "1", 0.05f, 3600);
        entity->speed = Value("velocity", "180", 1, 2000);
        entity->s.dk3EffectDuration = Value("stoptime", "1", 0, 3600) * 1000;
        G_SetOrigin(entity, entity->s.origin);
        entity->use = GibUse; entity->think = GibThink; return qtrue;
    }
    if (!strcmp(name, "effect_rain")) kind = DK_FX_RAIN;
    else if (!strcmp(name, "effect_snow")) kind = DK_FX_SNOW;
    else if (!strcmp(name, "effect_drip")) kind = DK_FX_DRIP;
    else if (!strcmp(name, "sfx_complex_particle") || !strcmp(name, "target_splash") || !strcmp(name, "target_effect")) kind = DK_FX_PARTICLES;
    else if (!strcmp(name, "monster_firefly")) kind = DK_FX_FIREFLIES;
    else if (!strcmp(name, "light_flame") || !strcmp(name, "light_e1") || !strcmp(name, "light_e2") || !strcmp(name, "light_e3") || !strcmp(name, "light_e4")) kind = DK_FX_FLAME;
    else if (!strcmp(name, "light_flare")) kind = DK_FX_FLARE;
    else if (!strcmp(name, "target_spotlight")) kind = DK_FX_SPOTLIGHT;
    else if (!strcmp(name, "light_strobe") || !strcmp(name, "func_dynalight") ||
        (!strcmp(name, "light") && entity->targetname)) kind = DK_FX_LIGHT;
    else if (!strcmp(name, "target_laser") || !strcmp(name, "effect_lightning")) kind = DK_FX_BEAM;
    else if (!strcmp(name, "target_earthquake")) kind = DK_FX_QUAKE;
    if (!kind) return qfalse;
    entity->s.eType = ET_DK3_EFFECT; entity->s.dk3Effect = kind;
    entity->dk.soundRandom = entity->dk.id * 747796405u;
    entity->s.dk3EffectFlags = DK_FX_ENABLED; entity->s.dk3EffectStart = level.time;
    entity->s.dk3EffectDuration = 3000;
    entity->s.dk3EffectRadius = Value("radius", kind == DK_FX_QUAKE ? "1024" : "96", 1, 65536);
    entity->s.dk3EffectRate = Value("count", "4", 1, 200) * 10;
    entity->s.dk3EffectSpeed = Value("velocity", "50", 0, 4000);
    entity->s.dk3EffectSpread = Value("spread", "15", 0, 360);
    entity->s.dk3Scale = Value("scale", "1", 0.01f, 100);
    entity->s.dk3Alpha = Value("alpha_level", "1", 0, 1);
    G_SpawnVector("_color", "1 1 1", entity->s.dk3EffectColor);
    for (axis = 0; axis < 3; ++axis) entity->s.dk3EffectColor[axis] = Com_Clamp(0, 1, entity->s.dk3EffectColor[axis]);
    G_SetOrigin(entity, entity->s.origin);
    entity->use = EffectUse; entity->think = EffectThink; entity->nextthink = level.time + FRAMETIME;
    if (kind == DK_FX_RAIN || kind == DK_FX_SNOW || kind == DK_FX_DRIP) {
        if (!entity->model) G_Error("dk3: weather entity %u has no volume", entity->dk.id);
        trap_SetBrushModel(entity, entity->model); entity->r.contents = 0;
        trap_LinkEntity(entity);
        VectorCopy(entity->r.absmin, entity->s.dk3EffectMins); VectorCopy(entity->r.absmax, entity->s.dk3EffectMaxs);
        entity->s.dk3EffectMins[2] = entity->s.dk3EffectMaxs[2] - Value("height", va("%f", entity->r.maxs[2] - entity->r.mins[2]), 1, 65536);
        entity->s.dk3EffectRate = kind == DK_FX_DRIP ? 3 : kind == DK_FX_SNOW ? 32 : 100;
        entity->s.dk3EffectSpeed = kind == DK_FX_SNOW ? 75 : 700;
        if (kind == DK_FX_RAIN) entity->s.dk3EffectFlags |= DK_FX_STREAK;
        entity->s.dk3EffectEnd[0] = (entity->spawnflags & 1 ? 100 : 0) - (entity->spawnflags & 2 ? 100 : 0);
        entity->s.dk3EffectEnd[1] = (entity->spawnflags & 4 ? 100 : 0) - (entity->spawnflags & 8 ? 100 : 0);
        entity->nextthink = 0;
    } else if (kind == DK_FX_PARTICLES) {
        float fade = Value("delta_alpha", "0.75", 0.01f, 100);
        float emission = Value("emission", "1", 1, 36000);
        entity->s.dk3Alpha = Value("alpha_level", "0.75", 0, 1);
        /* Normalize frame-authored emission intervals to a 60 Hz presentation
           reference, independent of the player's rendering frame rate. */
        entity->s.dk3EffectRate = Value("count", "1", 1, 10) * 60;
        entity->s.dk3EffectSpeed = Value("velocity", "35", 1, 1000);
        entity->s.dk3EffectSpread = Value("spread", "2", 0, 360);
        if (entity->spawnflags & 128) entity->s.dk3EffectFlags |= DK_FX_BUBBLE;
        else if (entity->spawnflags & 8) entity->s.dk3EffectFlags |= DK_FX_SMOKE;
        else entity->s.dk3EffectFlags |= DK_FX_SPARK;
        if (entity->spawnflags & 64) entity->s.dk3EffectFlags |= DK_PARTICLE_CP4 << DK_FX_PARTICLE_SHIFT;
        else if (entity->spawnflags & 32) entity->s.dk3EffectFlags |= DK_PARTICLE_CP2 << DK_FX_PARTICLE_SHIFT;
        else if (entity->spawnflags & 16) entity->s.dk3EffectFlags |= DK_PARTICLE_CP1 << DK_FX_PARTICLE_SHIFT;
        else if (entity->spawnflags & 2) entity->s.dk3EffectFlags |= DK_PARTICLE_CP3 << DK_FX_PARTICLE_SHIFT;
        if ((entity->spawnflags & 4) && !(entity->spawnflags & 248)) entity->s.dk3EffectFlags |= DK_FX_STREAK;
        if (entity->spawnflags & 1024) entity->s.dk3EffectFlags &= ~DK_FX_ENABLED;
        entity->s.dk3EffectDuration = Com_Clamp(50, 30000, entity->s.dk3Alpha / fade * 1000);
        entity->s.dk3EffectGravity[2] = -Value("gravity", "0", -4000, 4000);
        entity->dk.mediaPath = Text("gravitydir");
        entity->s.dk3EffectRadius = Value("radius", "0", 0, 4096);
        entity->dk.effectStopTime = Value("stoptime", "0", 0, 3600) * 1000;
        if (entity->spawnflags & 256) {
            entity->dk.effectOnTime = Value("emissiontime", "12", 1, 36000) * (1000.0f / 60);
            entity->dk.effectOffTime = emission * (1000.0f / 60);
        } else entity->s.dk3EffectRate /= emission;
        if (!strcmp(name, "target_splash") || !strcmp(name, "target_effect")) entity->s.dk3EffectFlags &= ~DK_FX_ENABLED;
        if (!strcmp(name, "target_splash")) entity->dk.effectStopTime = 200;
        StartParticles(entity, (entity->s.dk3EffectFlags & DK_FX_ENABLED) != 0);
    } else if (kind == DK_FX_FIREFLIES) {
        entity->s.dk3EffectRate = Value("count", "4", 1, 64);
        entity->s.dk3EffectRadius = Value("distance", "48", 1, 1024); entity->nextthink = 0;
    } else if (kind == DK_FX_SPOTLIGHT) {
        entity->s.dk3EffectRadius = Value("radius", "4", 1, 1024);
        entity->s.dk3EffectSpeed = Value("length", "2048", 1, 4000);
        if (!(entity->spawnflags & 1)) entity->s.dk3EffectFlags &= ~DK_FX_ENABLED;
        entity->think = BeamThink;
    } else if (kind == DK_FX_FLAME || kind == DK_FX_FLARE || kind == DK_FX_LIGHT) {
        entity->s.dk3EffectRadius = Value("light", "180", 0, 4096);
        if (kind != DK_FX_FLAME && (entity->spawnflags & 1)) entity->s.dk3EffectFlags &= ~DK_FX_ENABLED;
        if (!strcmp(name, "light_strobe")) entity->s.dk3EffectFlags |= DK_FX_STROBE;
        if (kind == DK_FX_FLAME) {
            entity->model = G_NewString(!strcmp(name, "light_e3") ? "models/global/e3_firea.sp2" :
                !strcmp(name, "light_e4") ? "models/global/e4_firea.sp2" : "models/global/e2_firea.sp2");
            entity->s.dk3RenderFlags |= 1 | 2;
            if (Text("sound")) entity->s.loopSound = DK_SoundIndex(Text("sound"));
        } else if (!entity->model) entity->model = G_NewString("models/global/e_flare2.sp2");
        entity->s.modelindex = G_ModelIndex(entity->model); entity->nextthink = 0;
    } else if (kind == DK_FX_BEAM) {
        entity->think = BeamThink;
        if (!(entity->spawnflags & 1)) entity->s.dk3EffectFlags &= ~DK_FX_ENABLED;
        if (!strcmp(name, "effect_lightning")) entity->s.dk3EffectFlags |= DK_FX_LIGHTNING;
        entity->damage = Value("dmg", "0", 0, 100000);
        entity->damage = Value("damage", va("%d", entity->damage), 0, 100000);
        entity->wait = Value("delay", "2", 0.1f, 3600);
        entity->s.dk3EffectDuration = Value("duration", "0.5", 0.1f, 3600) * 1000;
        entity->dk.effectChance = Value("chance", "0.1", 0, 1);
        entity->dk.effectGroundChance = Value("gndchance", "0.2", 0, 1);
        if ((entity->s.dk3EffectFlags & DK_FX_LIGHTNING) && (entity->spawnflags & 16))
            entity->s.dk3EffectFlags |= DK_FX_LIGHT_AT_END;
        entity->s.dk3Scale = Value("scale", "2", 0.1f, 64);
        for (axis = 0; axis < 4; ++axis) {
            value = Text(axis ? va("sound%d", axis) : "sound");
            if (value) entity->dk.soundIndices[entity->dk.soundCount++] = DK_SoundIndex(value);
        }
    } else if (kind == DK_FX_QUAKE) {
        entity->s.dk3EffectFlags &= ~DK_FX_ENABLED;
        entity->s.dk3EffectDuration = Value("duration", va("%d", entity->count > 0 ? entity->count : 3), 0.1f, 3600) * 1000;
        entity->s.dk3EffectSpeed = Value("speed", "200", 0, 2000);
    }
    trap_LinkEntity(entity);
    return qtrue;
}

void DK_RestoreWorldEffect(gentity_t *entity) {
    if (entity->dk.decorKind == -2) { entity->use = Destroy; entity->die = DestroyDie; return; }
    if (!strcmp(entity->classname, "dk3_debris_burst")) { entity->think = G_FreeEntity; return; }
    if (!strcmp(entity->classname, "target_lightramp")) { entity->use = RampUse; entity->think = RampThink; return; }
    if (!strcmp(entity->classname, "func_gib")) { entity->use = GibUse; entity->think = GibThink; return; }
    entity->use = EffectUse; entity->think = (entity->s.dk3Effect == DK_FX_BEAM || entity->s.dk3Effect == DK_FX_SPOTLIGHT) ? BeamThink : EffectThink;
}

qboolean DK_ValidateWorldEffect(gentity_t *entity) {
    entityState_t *state = &entity->s;
    int i;
    if (entity->dk.decorKind == -2)
        return state->eType == ET_MOVER && entity->r.bmodel &&
            (!strcmp(entity->classname, "func_wall_explode") || !strcmp(entity->classname, "func_debris") ||
             !strcmp(entity->classname, "func_debris_visible"));
    if (state->dk3Effect < 0 || state->dk3Effect >= DK_FX_COUNT || state->dk3EffectDuration < 0 ||
        state->dk3EffectDuration > 3600000 || state->dk3EffectRate < 0 || state->dk3EffectRate > 2000 ||
        state->dk3EffectSpeed < 0 || state->dk3EffectSpeed > 4000 || state->dk3EffectRadius < 0 || state->dk3EffectRadius > 65536 ||
        state->dk3EffectSpread < 0 || state->dk3EffectSpread > 360 || (state->dk3EffectFlags & ~(255 | DK_FX_PARTICLE_MASK)) ||
        ((state->dk3EffectFlags & DK_FX_PARTICLE_MASK) >> DK_FX_PARTICLE_SHIFT) > DK_PARTICLE_CP4 ||
        entity->dk.effectActive < 0 || entity->dk.effectActive > 1 ||
        entity->dk.effectOnTime < 0 || entity->dk.effectOnTime > 3600000 ||
        entity->dk.effectOffTime < 0 || entity->dk.effectOffTime > 3600000 ||
        entity->dk.effectStopTime < 0 || entity->dk.effectStopTime > 3600000 ||
        entity->dk.effectChance < 0 || entity->dk.effectChance > 1 ||
        entity->dk.effectGroundChance < 0 || entity->dk.effectGroundChance > 1) return qfalse;
    if (state->eType != ET_DK3_EFFECT) {
        if (!state->dk3Effect) return qtrue;
        if (state->eType != ET_GENERAL || !entity->dk.actorKind ||
            strcmp(entity->classname, "monster_cambot") || state->dk3Effect != DK_FX_SPOTLIGHT) return qfalse;
    }
    if (!state->dk3Effect && strcmp(entity->classname, "target_lightramp") && strcmp(entity->classname, "func_gib")) return qfalse;
    if (state->dk3Effect == DK_FX_QUAKE && state->dk3EffectRadius <= 0) return qfalse;
    if (!strcmp(entity->classname, "target_lightramp") && (!entity->target || !entity->message || strlen(entity->message) != 2 ||
        entity->message[0] < 'a' || entity->message[0] > 'z' || entity->message[1] < 'a' || entity->message[1] > 'z' ||
        state->dk3EffectDuration <= 0 || entity->dk.action < 0 || entity->dk.action > 1)) return qfalse;
    if (state->dk3Effect >= DK_FX_RAIN && state->dk3Effect <= DK_FX_DRIP) {
        if (state->dk3EffectSpeed <= 0) return qfalse;
        for (i = 0; i < 3; ++i) if (state->dk3EffectMins[i] > state->dk3EffectMaxs[i]) return qfalse;
    }
    for (i = 0; i < 3; ++i) if (state->dk3EffectColor[i] < 0 || state->dk3EffectColor[i] > 1 ||
        fabs(state->dk3EffectGravity[i]) > 4000) return qfalse;
    return qtrue;
}
