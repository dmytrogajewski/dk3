/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Whole mover assemblies share ioquake3's transactional rider push. */
#include "g_local.h"

void G_BeginMoverPush(void);
qboolean G_MoverPush(gentity_t *pusher, vec3_t move, vec3_t amove, gentity_t **obstacle);

typedef struct {
    gentity_t *entity;
    unsigned int id;
    int parent;
    vec3_t before, anglesBefore, after, anglesAfter;
} assemblyPart_t;
static assemblyPart_t parts[MAX_GENTITIES];
static int partCount;

static void Rotate(const vec3_t vector, const vec3_t from, const vec3_t to, vec3_t result) {
    vec3_t oldAxes[3], newAxes[3], local;
    int i;
    AnglesToAxis(from, oldAxes); AnglesToAxis(to, newAxes);
    for (i = 0; i < 3; ++i) local[i] = DotProduct(vector, oldAxes[i]);
    VectorClear(result);
    for (i = 0; i < 3; ++i) VectorMA(result, local[i], newAxes[i], result);
}

static void Point(vec3_t point, assemblyPart_t *parent) {
    vec3_t relative, rotated;
    VectorSubtract(point, parent->before, relative);
    Rotate(relative, parent->anglesBefore, parent->anglesAfter, rotated);
    VectorAdd(parent->after, rotated, point);
}

static void Orientation(vec3_t angles, assemblyPart_t *parent) {
    vec3_t axes[3], rotated[3];
    int i;
    AnglesToAxis(angles, axes);
    for (i = 0; i < 3; ++i) Rotate(axes[i], parent->anglesBefore, parent->anglesAfter, rotated[i]);
    vectoangles(rotated[0], angles);
    angles[ROLL] = atan2(rotated[1][2], rotated[2][2]) * 180 / M_PI;
}

static int Add(gentity_t *entity) {
    assemblyPart_t *part;
    int i;
    for (i = 0; i < partCount; ++i) if (parts[i].entity == entity) return i;
    if (partCount == MAX_GENTITIES) G_Error("dk3: mover assembly overflow");
    part = &parts[partCount]; memset(part, 0, sizeof(*part));
    part->entity = entity; part->id = entity->dk.id; part->parent = -1;
    VectorCopy(entity->r.currentOrigin, part->before); VectorCopy(entity->r.currentAngles, part->anglesBefore);
    return partCount++;
}

static void Pose(int index, int depth) {
    assemblyPart_t *part = &parts[index];
    gentity_t *entity = part->entity;
    int i;
    if (depth == MAX_GENTITIES) G_Error("dk3: cyclic mover assembly at entity %u", entity->dk.id);
    BG_EvaluateTrajectory(&entity->s.pos, level.time, part->after);
    BG_EvaluateTrajectory(&entity->s.apos, level.time, part->anglesAfter);
    for (i = 0; i < partCount; ++i) if (entity->dk.parentId && parts[i].id == entity->dk.parentId) {
        part->parent = i; Pose(i, depth + 1);
        Point(part->after, &parts[i]); Orientation(part->anglesAfter, &parts[i]);
        break;
    }
}

static void Rebase(assemblyPart_t *part) {
    gentity_t *entity = part->entity;
    assemblyPart_t *parent;
    vec3_t velocity;
    if (part->parent < 0) return;
    parent = &parts[part->parent];
    Point(entity->s.pos.trBase, parent);
    Rotate(entity->s.pos.trDelta, parent->anglesBefore, parent->anglesAfter, velocity);
    VectorCopy(velocity, entity->s.pos.trDelta);
    Orientation(entity->s.apos.trBase, parent);
    Point(entity->s.origin, parent); Orientation(entity->s.angles, parent);
    if (entity->dk.moverAngular) { Orientation(entity->pos1, parent); Orientation(entity->pos2, parent); }
    else { Point(entity->pos1, parent); Point(entity->pos2, parent); }
    if (entity->dk.moverKind == 4) Point(entity->dk.secretEnd, parent);
    Rotate(entity->movedir, parent->anglesBefore, parent->anglesAfter, velocity);
    VectorCopy(velocity, entity->movedir);
}

void DK_MoveAssembly(gentity_t *root) {
    gentity_t *part, *obstacle = NULL;
    int i, j;
    qboolean changed, blocked = qfalse;
    if (root->dk.parentId && !DK_FindEntity(root->dk.parentId)) root->dk.parentId = 0;
    if (root->dk.parentId || (root->flags & FL_TEAMMEMBER)) return;
    partCount = 0;
    for (part = root; part; part = part->teamchain) Add(part);
    do {
        changed = qfalse;
        for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
            gentity_t *child = &g_entities[i];
            int before = partCount;
            if (!child->inuse || !child->dk.parentId) continue;
            for (j = 0; j < partCount; ++j) if (parts[j].id == child->dk.parentId) break;
            if (j == partCount) continue;
            Add(child);
            if (!(child->flags & FL_TEAMMEMBER)) for (part = child->teamchain; part; part = part->teamchain) Add(part);
            if (before != partCount) changed = qtrue;
        }
    } while (changed);
    for (i = 0; i < partCount; ++i) Pose(i, 0);
    G_BeginMoverPush();
    for (i = 0; i < partCount; ++i) {
        vec3_t move, amove;
        VectorSubtract(parts[i].after, parts[i].before, move);
        for (j = 0; j < 3; ++j) amove[j] = AngleSubtract(parts[i].anglesAfter[j], parts[i].anglesBefore[j]);
        if (VectorLengthSquared(move) + VectorLengthSquared(amove) == 0) continue;
        if (!G_MoverPush(parts[i].entity, move, amove, &obstacle)) { blocked = qtrue; break; }
    }
    if (blocked) {
        for (i = 0; i < partCount; ++i) {
            part = parts[i].entity;
            VectorCopy(parts[i].before, part->r.currentOrigin); VectorCopy(parts[i].anglesBefore, part->r.currentAngles);
            part->s.pos.trTime += level.time - level.previousTime;
            part->s.apos.trTime += level.time - level.previousTime;
            trap_LinkEntity(part);
        }
        if (root->blocked) root->blocked(root, obstacle);
    } else {
        for (i = 0; i < partCount; ++i) Rebase(&parts[i]);
        for (i = 0; i < partCount; ++i) {
            part = parts[i].entity;
            if ((part->s.pos.trType == TR_LINEAR_STOP || part->s.apos.trType == TR_LINEAR_STOP) &&
                (part->s.pos.trType != TR_LINEAR_STOP || level.time >= part->s.pos.trTime + part->s.pos.trDuration) &&
                (part->s.apos.trType != TR_LINEAR_STOP || level.time >= part->s.apos.trTime + part->s.apos.trDuration) && part->reached)
                part->reached(part);
        }
    }
    for (i = 0; i < partCount; ++i)
        if (parts[i].entity->inuse && parts[i].entity->dk.id == parts[i].id) G_RunThink(parts[i].entity);
}

void DK_SetupAttachments(void) {
    int i, depth;
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *entity = &g_entities[i], *parent;
        if (!entity->inuse || !entity->dk.parentTarget) continue;
        parent = NULL;
        while ((parent = G_Find(parent, FOFS(targetname), entity->dk.parentTarget)) != NULL)
            if (parent != entity && parent->s.eType == ET_MOVER) break;
        if (!parent)
            G_Error("dk3: %s %u: invalid mover parent %s", entity->classname, entity->dk.id, entity->dk.parentTarget);
        entity->dk.parentId = parent->dk.id;
        /* Rigid attachments inherit their parent's translation. Applying a
           free-fall trajectory here adds gravity again on every rebase. */
        if (entity->s.eType != ET_MOVER && entity->s.pos.trType == TR_GRAVITY) {
            G_SetOrigin(entity, entity->r.currentOrigin);
            VectorClear(entity->s.pos.trDelta);
        }
    }
    for (i = MAX_CLIENTS; i < level.num_entities; ++i) {
        gentity_t *parent = &g_entities[i];
        for (depth = 0; parent && parent->dk.parentId; ++depth) {
            if (depth == MAX_GENTITIES) G_Error("dk3: cyclic parenttarget at entity %u", g_entities[i].dk.id);
            parent = DK_FindEntity(parent->dk.parentId);
        }
    }
}
