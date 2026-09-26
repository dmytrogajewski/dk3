/* SPDX-License-Identifier: GPL-2.0-or-later */
#undef NDEBUG
#include <assert.h>
#include "../../../../src/game/dk_actors.c"

level_locals_t level;
gentity_t g_entities[MAX_GENTITIES];
vmCvar_t g_gravity;
static qboolean occluded;
int trap_PointContents(const vec3_t point, int pass) { return 0; }
qboolean trap_InPVS(const vec3_t a, const vec3_t b) { return qtrue; }

void trap_Trace(trace_t *out, const vec3_t start, const vec3_t mins,
                const vec3_t maxs, const vec3_t end, int pass, int mask) {
    memset(out, 0, sizeof(*out));
    out->fraction = occluded ? 0 : 1;
    out->entityNum = ENTITYNUM_WORLD;
    VectorCopy(end, out->endpos);
}
void trap_LinkEntity(gentity_t *ent) {}
int trap_Cvar_VariableIntegerValue(const char *name) { return 0; }
void G_Printf(const char *fmt, ...) {}
void G_SetOrigin(gentity_t *ent, vec3_t origin) {
    VectorCopy(origin, ent->r.currentOrigin);
    VectorCopy(origin, ent->s.pos.trBase);
}
void G_Damage(gentity_t *t, gentity_t *i, gentity_t *a, vec3_t d, vec3_t p, int n, int f, int m) {
    assert(!"unexpected damage during unobstructed fall");
}

int main(void) {
    const int intervals[] = {20, 25, 50, 100};
    int i, elapsed;
    g_gravity.value = 800;
    definitions[0].classname[0] = 'x';
    for (i = 0; i < ARRAY_LEN(intervals); ++i) {
        gentity_t actor;
        memset(&actor, 0, sizeof(actor));
        actor.dk.actorKind = 1;
        actor.health = 100;
        actor.inuse = qtrue;
        actor.r.currentOrigin[2] = 1000;
        for (elapsed = 0; elapsed < 1000; elapsed += intervals[i]) {
            level.previousTime = elapsed;
            level.time = elapsed + intervals[i];
            Physics(&actor);
        }
        assert(fabs(actor.r.currentOrigin[2] - 600) < 0.01f);
        assert(fabs(actor.dk.actorVelocity[2] + 800) < 0.01f);
    }
    {
        gentity_t *victim = &g_entities[MAX_CLIENTS], *witness = victim + 1, *attacker = victim + 2;
        strcpy(definitions[0].classname, "monster_fatworker");
        definitions[0].sightRange = 1200; definitions[0].civilian = qtrue;
        level.num_entities = MAX_CLIENTS + 3;
        victim->dk.actorKind = witness->dk.actorKind = attacker->dk.actorKind = 1;
        victim->inuse = witness->inuse = attacker->inuse = qtrue;
        witness->health = attacker->health = 100;
        witness->r.currentOrigin[0] = 450;
        occluded = qtrue; EnemyAlert(victim, attacker); assert(witness->enemy == NULL);
        occluded = qfalse; EnemyAlert(victim, attacker); assert(witness->enemy == attacker);
        witness->enemy = NULL; witness->r.currentOrigin[0] = 2000;
        EnemyAlert(victim, attacker); assert(witness->enemy == NULL);
    }
    puts("Worker witnesses: visible violence alerts; walls and range prevent alerts");
    puts("Actor gravity: 400-unit fall in one second at 10, 20, 40 and 50 Hz");
    return 0;
}
