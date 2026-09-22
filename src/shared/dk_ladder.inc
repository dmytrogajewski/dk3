/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Included by the shared ioquake3 movement unit in both authoritative and predicted movement. */
static qboolean DK_LadderMove(void) {
    vec3_t direction, endpoint, wish, horizontal;
    trace_t hit;
    float climb, speed, facing;
    int axis;
    qboolean found = qfalse;
    if (pm->ps->pm_type != PM_NORMAL || pm->waterlevel > 1) return qfalse;
    VectorCopy(pml.forward, horizontal);
    horizontal[2] = 0;
    if (!VectorNormalize(horizontal)) return qfalse;
    /* Probe around the body, allowing lateral attachment without rotating the view. */
    for (axis = 0; axis < 4; ++axis) {
        VectorClear(direction);
        direction[axis / 2] = axis & 1 ? -1 : 1;
        VectorMA(pm->ps->origin, 3, direction, endpoint);
        pm->trace(&hit, pm->ps->origin, pm->mins, pm->maxs, endpoint, pm->ps->clientNum, pm->tracemask);
        if (hit.fraction < 1 && (hit.surfaceFlags & SURF_LADDER) && fabs(hit.plane.normal[2]) < 0.5f) {
            found = qtrue;
            break;
        }
    }
    if (!found) return qfalse;
    facing = DotProduct(horizontal, hit.plane.normal);
    /* Forward motion only climbs when facing into the ladder. Proximity alone
       made walking alongside a ladder climb to its top and fall repeatedly.
       Backing away releases it; an explicit up/down command can attach from
       the side. Keep ordinary tangential motion in shared walking physics. */
    if (pm->cmd.forwardmove && (pm->cmd.forwardmove < 0 ? facing < -0.1f : facing > 0.1f)) return qfalse;
    if (!pm->cmd.upmove && facing > -0.5f) return qfalse;
    climb = pm->cmd.upmove;
    if (!climb) climb = pm->cmd.forwardmove * (pml.forward[2] < -0.35f ? -1.0f : 1.0f);
    speed = pm->ps->speed < 140 ? pm->ps->speed : 140;
    VectorScale(pml.right, pm->cmd.rightmove * speed / 127.0f, wish);
    wish[2] = climb * speed / 127.0f;
    PM_ClipVelocity(wish, hit.plane.normal, wish, OVERCLIP);
    /* Exponential drag is stable under subdivided prediction commands. */
    for (axis = 0; axis < 3; ++axis) {
        float difference = wish[axis] - pm->ps->velocity[axis];
        float fraction = 12 * pml.frametime;
        if (fraction > 1) fraction = 1;
        pm->ps->velocity[axis] += difference * fraction;
    }
    pm->ps->groundEntityNum = ENTITYNUM_NONE;
    PM_StepSlideMove(qfalse);
    return qtrue;
}
