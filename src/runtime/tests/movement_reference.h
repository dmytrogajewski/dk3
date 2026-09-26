/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "q_shared.h"
#include "bg_public.h"
void reference_move(playerState_t *state, usercmd_t command,
    void (*trace)(trace_t *, const vec3_t, const vec3_t, const vec3_t, const vec3_t, int, int),
    int (*contents)(const vec3_t, int));
