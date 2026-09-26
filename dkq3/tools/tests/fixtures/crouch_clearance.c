/* SPDX-License-Identifier: GPL-2.0-or-later */
#undef NDEBUG
#include <assert.h>
#include "../../../../engine/ioquake3/code/game/bg_pmove.c"

static float ceiling = 32;
static void clearance(trace_t *out, const vec3_t start, const vec3_t mins,
                      const vec3_t maxs, const vec3_t end, int pass, int mask) {
    memset(out, 0, sizeof(*out));
    out->allsolid = start[2] + maxs[2] > ceiling;
    out->fraction = out->allsolid ? 0 : 1;
}

int main(void) {
    playerState_t state = {0};
    pmove_t move = {0};
    trace_t trace;
    move.ps = &state;
    move.trace = clearance;
    pm = &move;
    state.origin[2] = 24; /* Feet on the floor, low 32-unit passage overhead. */
    PM_CheckDuck();
    clearance(&trace, state.origin, move.mins, move.maxs, state.origin, 0, 0);
    assert(trace.allsolid); /* Standing cannot enter. */
    move.cmd.upmove = -127;
    PM_CheckDuck();
    clearance(&trace, state.origin, move.mins, move.maxs, state.origin, 0, 0);
    assert(!trace.allsolid);
    assert(state.viewheight == -2); /* Gold eye offset, shared by prediction/server. */
    move.cmd.upmove = 0;
    PM_CheckDuck();
    assert(state.pm_flags & PMF_DUCKED); /* Releasing crouch under the roof stays safe. */
    ceiling = 128;
    PM_CheckDuck();
    assert(!(state.pm_flags & PMF_DUCKED));
    assert(state.viewheight == 22);
    return 0;
}
