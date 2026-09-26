/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Test-only boundary to the licensed bundled movement; never linked into runtime products. */
#include "movement_reference.h"
#include <math.h>
#include <stdlib.h>
void QDECL Com_Printf(const char *format, ...) { (void)format; }
void QDECL Com_Error(int level, const char *format, ...) { (void)level; (void)format; abort(); }
void BG_AddPredictableEventToPlayerstate(int event, int parameter, playerState_t *ps) {
    int index=ps->eventSequence & (MAX_PS_EVENTS-1);
    ps->events[index]=event; ps->eventParms[index]=parameter; ps->eventSequence++;
}
void DK_WeaponMoveZig(pmove_t *pmove, int milliseconds) { (void)pmove; (void)milliseconds; }
int DK_Attribute(const playerState_t *state, int attribute, int time) { (void)state; (void)attribute; (void)time; return 0; }
void trap_SnapVector(float *values) { int i; for(i=0;i<3;i++) values[i]=nearbyintf(values[i]); }
void reference_move(playerState_t *state, usercmd_t command,
    void (*trace)(trace_t *, const vec3_t, const vec3_t, const vec3_t, const vec3_t, int, int),
    int (*contents)(const vec3_t, int)) {
    pmove_t move={0};
    move.ps=state; move.cmd=command; move.tracemask=MASK_PLAYERSOLID;
    move.trace=trace; move.pointcontents=contents;
    Pmove(&move);
}
