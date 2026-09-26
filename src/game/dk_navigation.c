/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Authored air, water and track routes; original graph search over live collision. */
#include "g_local.h"
#include "../botlib/botlib.h"
#include "../botlib/be_aas.h"

static int routeReports;

void DK_LoadGroundNavigation(const char *map) {
    char path[MAX_QPATH], text[1024], selected[MAX_QPATH], *cursor, *token;
    const char *mode;
    fileHandle_t file;
    int length, matches = 0;
    if (g_gametype.integer == GT_SINGLE_PLAYER) {
        int skill = trap_Cvar_VariableIntegerValue("g_spSkill");
        mode = skill <= 2 ? "easy" : skill == 3 ? "normal" : "hard";
    } else mode = g_gametype.integer == GT_CTF ? "ctf" :
                  g_gametype.integer == GT_DK3_DEATHTAG ? "deathtag" : "dm";
    Com_sprintf(path, sizeof(path), "dk3/navigation/%s.cfg", map);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 1 || length >= sizeof(text)) {
        if (file) trap_FS_FCloseFile(file);
        G_Error("dk3: %s: navigation selection missing or oversized; rebuild assets", path);
    }
    trap_FS_Read(text, length, file); trap_FS_FCloseFile(file);
    text[length] = 0; cursor = text;
    if (strcmp(COM_Parse(&cursor), "dk3_navigation") || strcmp(COM_Parse(&cursor), "1"))
        G_Error("dk3: %s: unsupported navigation selection", path);
    while (*(token = COM_Parse(&cursor))) {
        qboolean wanted = !strcmp(token, mode);
        const char *letter;
        token = COM_Parse(&cursor);
        if (!*token || strlen(token) >= MAX_QPATH)
            G_Error("dk3: %s: invalid navigation name", path);
        for (letter = token; *letter; ++letter)
            if (!(*letter >= 'a' && *letter <= 'z') && !(*letter >= '0' && *letter <= '9') && *letter != '_' && *letter != '-')
                G_Error("dk3: %s: invalid navigation name", path);
        if (wanted) { Q_strncpyz(selected, token, sizeof(selected)); ++matches; }
    }
    if (matches != 1) G_Error("dk3: %s: expected one %s navigation selection", path, mode);
    G_Printf("dk3: map %s navigation %s (%s)\n", map, selected, mode);
    if (trap_BotLibLoadMap(selected) != BLERR_NOERROR)
        G_Error("dk3: %s: navigation %s could not load; rebuild assets with bundled BSPC", map, selected);
}

qboolean DK_GroundWaypoint(gentity_t *actor, const vec3_t destination, int flags, vec3_t waypoint, int *travel) {
    vec3_t goal;
    aas_predictroute_t route;
    int from, to;
    if (!trap_AAS_Initialized()) return qfalse;
    VectorCopy(destination, goal);
    /* Item origins can intersect the expanded player hull around a pedestal.
       Botlib resolves nearby reachable areas and standing mover surfaces. */
    from = trap_BotReachabilityArea(actor->r.currentOrigin, actor->s.number);
    to = trap_BotReachabilityArea(goal, ENTITYNUM_NONE);
    if (routeReports < 16 && trap_Cvar_VariableIntegerValue("bot_report")) {
        G_Printf("dk3 route actor %u areas %d (%d exits) -> %d (%d exits) travel time %d\n", actor->dk.id,
            from, from ? trap_AAS_AreaReachability(from) : 0, to, to ? trap_AAS_AreaReachability(to) : 0,
            from && to ? trap_AAS_AreaTravelTimeToGoalArea(from, actor->r.currentOrigin, to, flags) : 0);
        ++routeReports;
    }
    if (!from || !to) return qfalse;
    if (from == to) { VectorCopy(goal, waypoint); *travel = TFL_WALK; return qtrue; }
    memset(&route, 0, sizeof(route));
    trap_AAS_PredictRoute(&route, from, actor->r.currentOrigin, to, flags, 1, 0, 0, 0, 0, 0);
    /* This upstream implementation leaves numareas unset, and returns false
       when maxareas stops before the final goal. A timed first reachability is
       still a valid waypoint; requiring either result discarded every route. */
    if (route.time <= 0 || route.stopevent == RSE_NOROUTE) return qfalse;
    VectorCopy(route.endpos, waypoint); *travel = route.endtravelflags;
    return qtrue;
}

#define DK_ROUTE_NODES 4096
#define DK_ROUTE_LINKS 6

typedef struct {
    vec3_t point;
    int index, flags, kind, count, links[DK_ROUTE_LINKS];
    char *target, *targetname;
} routeNode_t;
typedef struct {
    unsigned int id;
    int until, mode;
    vec3_t destination, waypoint;
    qboolean found;
} routeCache_t;
static routeNode_t nodes[DK_ROUTE_NODES];
static int nodeCount;
static routeCache_t cache[MAX_GENTITIES];
static float costs[DK_ROUTE_NODES];
static int parents[DK_ROUTE_NODES], heap[DK_ROUTE_NODES], positions[DK_ROUTE_NODES], heapCount;
static char input[1024 * 1024];

static int Number(char **cursor, int minimum, int maximum, const char *path) {
    char *text = COM_Parse(cursor), *end;
    long number = strtol(text, &end, 10);
    if (!*text || *end || number < minimum || number > maximum) G_Error("dk3: %s: invalid route integer %s", path, text);
    return number;
}

void DK_LoadNavigation(const char *map) {
    char path[MAX_QPATH], *cursor, *token;
    fileHandle_t file;
    int length, kind, count, start, i, j, k, seen = 0;
    memset(cache, 0, sizeof(cache)); nodeCount = routeReports = 0;
    Com_sprintf(path, sizeof(path), "dk3/routes/%s.cfg", map);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 0) { G_Printf("dk3: %s has no authored node graph\n", map); return; }
    if (length == 0 || length >= sizeof(input)) { trap_FS_FCloseFile(file); G_Error("dk3: %s: invalid route length", path); }
    trap_FS_Read(input, length, file); trap_FS_FCloseFile(file); input[length] = 0; cursor = input;
    if (strcmp(COM_Parse(&cursor), "dk3_routes") || Number(&cursor, 1, 1, path) != 1)
        G_Error("dk3: %s: unsupported routes", path);
    while (*(token = COM_Parse(&cursor))) {
        if (strcmp(token, "graph")) G_Error("dk3: %s: expected graph", path);
        token = COM_Parse(&cursor);
        kind = !strcmp(token, "ground") ? 1 : !strcmp(token, "air") ? 4 : !strcmp(token, "track") ? 8 : 0;
        if (!kind || (seen & kind)) G_Error("dk3: %s: invalid or duplicate graph %s", path, token);
        seen |= kind;
        start = nodeCount; count = Number(&cursor, 0, DK_ROUTE_NODES - nodeCount, path);
        for (i = 0; i < count; ++i) {
            routeNode_t *node = &nodes[nodeCount++];
            if (strcmp(COM_Parse(&cursor), "node")) G_Error("dk3: %s: expected node", path);
            memset(node, 0, sizeof(*node)); node->kind = kind;
            node->index = Number(&cursor, 0, DK_ROUTE_NODES - 1, path);
            node->flags = Number(&cursor, 0, 0x7fffffff, path);
            for (j = 0; j < 3; ++j) {
                char *end;
                token = COM_Parse(&cursor); node->point[j] = strtod(token, &end);
                if (!*token || *end || Q_isnan(node->point[j]) || fabs(node->point[j]) > 1048576)
                    G_Error("dk3: %s: invalid node coordinate", path);
            }
            node->target = G_NewString(COM_Parse(&cursor)); node->targetname = G_NewString(COM_Parse(&cursor));
            node->count = Number(&cursor, 0, DK_ROUTE_LINKS, path);
            for (j = 0; j < node->count; ++j) node->links[j] = Number(&cursor, 0, DK_ROUTE_NODES - 1, path);
            for (j = start; j < nodeCount - 1; ++j)
                if (nodes[j].index == node->index) G_Error("dk3: %s: duplicate node index", path);
        }
        for (i = start; i < nodeCount; ++i) for (j = 0; j < nodes[i].count; ++j) {
            for (k = start; k < nodeCount && nodes[k].index != nodes[i].links[j]; ++k) {}
            if (k == nodeCount) G_Error("dk3: %s: node %d links to missing node %d", path, nodes[i].index, nodes[i].links[j]);
            nodes[i].links[j] = k;
        }
    }
    G_Printf("dk3: %s: %d authored route nodes\n", map, nodeCount);
}

static qboolean Compatible(routeNode_t *node, int mode) {
    return mode == 2 ? node->kind == 1 && (node->flags & 2) : node->kind == mode;
}

static qboolean Clear(gentity_t *actor, const vec3_t from, const vec3_t to, int mode, int target) {
    trace_t trace;
    trap_Trace(&trace, from, actor->r.mins, actor->r.maxs, to, actor->s.number, MASK_PLAYERSOLID);
    if (trace.startsolid || (trace.fraction < 1 && trace.entityNum != target)) return qfalse;
    if (mode == 2) {
        int step, steps = (int)(Distance(from, to) / 32) + 1;
        vec3_t point, delta;
        if (steps > 128) return qfalse;
        VectorSubtract(to, from, delta);
        for (step = 0; step <= steps; ++step) {
            VectorMA(from, (float)step / steps, delta, point);
            if (!(trap_PointContents(point, actor->s.number) & CONTENTS_WATER)) return qfalse;
        }
    }
    return qtrue;
}

static int Nearest(gentity_t *actor, const vec3_t point, int mode, int target) {
    int i, best = -1;
    float distance = 2048;
    for (i = 0; i < nodeCount; ++i) {
        float candidate = Distance(point, nodes[i].point);
        if (candidate < distance && Compatible(&nodes[i], mode) && Clear(actor, nodes[i].point, point, mode, target)) {
            distance = candidate; best = i;
        }
    }
    return best;
}

static void Swap(int a, int b) {
    int value = heap[a]; heap[a] = heap[b]; heap[b] = value;
    positions[heap[a]] = a; positions[heap[b]] = b;
}

static void Queue(int node) {
    int at = positions[node];
    if (at < 0) { at = heapCount++; heap[at] = node; positions[node] = at; }
    while (at && costs[heap[at]] < costs[heap[(at - 1) / 2]]) { Swap(at, (at - 1) / 2); at = (at - 1) / 2; }
}

static int Pop(void) {
    int node = heap[0], at = 0;
    --heapCount; positions[node] = -2;
    if (heapCount) { heap[0] = heap[heapCount]; positions[heap[0]] = 0; }
    while (at * 2 + 1 < heapCount) {
        int next = at * 2 + 1;
        if (next + 1 < heapCount && costs[heap[next + 1]] < costs[heap[next]]) ++next;
        if (costs[heap[at]] <= costs[heap[next]]) break;
        Swap(at, next); at = next;
    }
    return node;
}

qboolean DK_NavigationGoal(gentity_t *actor, const vec3_t destination, int mode, int target, vec3_t result) {
    routeCache_t *saved = &cache[actor->s.number];
    int first, last, i, current;
    if (mode != 8 && Clear(actor, actor->r.currentOrigin, destination, mode, target)) { VectorCopy(destination, result); return qtrue; }
    if (saved->id == actor->dk.id && saved->mode == mode && saved->until > level.time &&
        Distance(saved->destination, destination) < 64 && Distance(actor->r.currentOrigin, saved->waypoint) > 24) {
        if (saved->found) VectorCopy(saved->waypoint, result);
        return saved->found;
    }
    saved->id = actor->dk.id; saved->mode = mode; saved->until = level.time + 400; saved->found = qfalse;
    VectorCopy(destination, saved->destination);
    first = Nearest(actor, actor->r.currentOrigin, mode, actor->s.number);
    last = Nearest(actor, destination, mode, target);
    if (first < 0 || last < 0) return qfalse;
    heapCount = 0;
    for (i = 0; i < nodeCount; ++i) { costs[i] = 1e30f; parents[i] = -1; positions[i] = -1; }
    costs[first] = 0; Queue(first);
    while (heapCount) {
        current = Pop();
        if (current == last) break;
        for (i = 0; i < nodes[current].count; ++i) {
            int next = nodes[current].links[i];
            float distance = costs[current] + Distance(nodes[current].point, nodes[next].point);
            if (positions[next] == -2 || !Compatible(&nodes[next], mode) || distance >= costs[next] ||
                !Clear(actor, nodes[current].point, nodes[next].point, mode, ENTITYNUM_NONE)) continue;
            costs[next] = distance; parents[next] = current; Queue(next);
        }
    }
    if (positions[last] != -2) return qfalse;
    current = last;
    while (parents[current] >= 0 && parents[current] != first) current = parents[current];
    if (Distance(actor->r.currentOrigin, nodes[first].point) > 48 ||
        !Clear(actor, actor->r.currentOrigin, nodes[current].point, mode, target)) current = first;
    VectorCopy(nodes[current].point, result); VectorCopy(result, saved->waypoint); saved->found = qtrue;
    return qtrue;
}
