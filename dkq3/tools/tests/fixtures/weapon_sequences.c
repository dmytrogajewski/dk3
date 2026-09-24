/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "bg_local.h"
#include "dk_weapons.h"
#include <assert.h>
pmove_t *pm;
pml_t pml;
static int shots, contents, contact;
void PM_AddEvent(int event) { if (event == EV_FIRE_WEAPON) ++shots; }
void PM_StartTorsoAnim(int animation) { pm->ps->torsoAnim = animation; }
static void Trace(trace_t *hit, const vec3_t start, const vec3_t mins, const vec3_t maxs,
                  const vec3_t end, int pass, int mask) {
    (void)start; (void)mins; (void)maxs; (void)pass; (void)mask;
    memset(hit, 0, sizeof(*hit)); hit->fraction = contact ? 0.5f : 1;
    VectorCopy(end, hit->endpos);
}
void BG_AddPredictableEventToPlayerstate(int event, int parm, playerState_t *ps) { (void)parm; (void)ps; PM_AddEvent(event); }
static playerState_t state;
static pmove_t movement;
static void Begin(int weapon, int ammo) {
    memset(&state, 0, sizeof(state)); memset(&movement, 0, sizeof(movement));
    shots = contents = contact = 0;
    movement.ps = &state; movement.trace = Trace; movement.cmd.weapon = weapon; pm = &movement;
    state.pm_type = PM_NORMAL; state.stats[STAT_HEALTH] = 100;
    state.weapon = weapon; state.dk3Inventory = 1u << weapon; state.ammo[weapon] = ammo;
    dk_weapons[weapon].loaded = qtrue; dk_weapons[weapon].ammoCost = 1;
    pml.msec = 10;
}
static void Run(int milliseconds, qboolean attack) {
    int i;
    movement.cmd.buttons = attack ? BUTTON_ATTACK : 0;
    for (i = 0; i < milliseconds; i += 10) { movement.cmd.serverTime += 10; DK_WeaponMoveZig(pm, pml.msec); }
}
int main(void) {
    int weapon;
    playerState_t checkpoint, result;
    int checkpointTime, firstShots;
    /* Every concrete weapon reaches its attack through the shared predictor. */
    for (weapon = 1; weapon < DK_WEAPON_COUNT; ++weapon) {
        Begin(weapon, 20);
        state.dk3GlockClip = 10;
        state.powerups[PW_DK3_GASHANDS] = 60000;
        Run(100, qtrue); Run(5000, qfalse);
        assert(shots > 0 && state.ammo[weapon] >= 0);
        state.stats[STAT_HEALTH] = 0; firstShots = shots;
        Run(100, qtrue); assert(shots == firstShots);
    }
    /* Replaying unacknowledged burst input must reproduce state and events. */
    Begin(DK_W_SHOTCYCLER, 20); Run(400, qtrue);
    checkpoint = state; checkpointTime = movement.cmd.serverTime; shots = 0;
    Run(900, qfalse); result = state; firstShots = shots;
    state = checkpoint; movement.cmd.serverTime = checkpointTime; shots = 0;
    Run(900, qfalse);
    assert(shots == firstShots && memcmp(&state, &result, sizeof(state)) == 0);

    Begin(DK_W_SHOTCYCLER, 20);
    Run(10, qtrue); assert(shots == 1 && state.dk3Burst == 5);
    Run(260, qfalse); assert(shots == 1);
    Run(1090, qfalse); assert(shots == 6 && state.ammo[DK_W_SHOTCYCLER] == 14);
    Run(2050, qtrue); assert(shots == 6);
    Run(20, qtrue); assert(shots == 7 && state.dk3Burst == 5);

    Begin(DK_W_HAMMER, 0);
    Run(900, qtrue); assert(shots == 0 && state.dk3Charge == 900);
    Run(10, qfalse); assert(shots == 1 && state.dk3Charge == 900);

    Begin(DK_W_KINETICORE, 20);
    Run(10, qtrue); Run(500, qfalse);
    assert(shots == 5 && state.ammo[DK_W_KINETICORE] == 15);
    Run(600, qtrue); assert(shots == 5);
    Run(400, qtrue); assert(shots > 5);

    Begin(DK_W_GLOCK, 25); state.dk3GlockClip = 10;
    Run(2310, qtrue); assert(shots == 10 && state.dk3GlockClip == 0 && state.weaponstate == WEAPON_DROPPING);
    assert(state.dk3WeaponSequence == DK_GLOCK_RELOAD_SEQUENCE);
    Run(800, qtrue); assert(shots == 10);
    Run(400, qtrue); assert(shots == 11 && state.ammo[DK_W_GLOCK] == 14);
    assert(state.dk3WeaponSequence != DK_GLOCK_RELOAD_SEQUENCE);

    Begin(DK_W_GLOCK, 25); state.dk3GlockClip = 0;
    state.dk3Inventory |= 1u << DK_W_RIPGUN; movement.cmd.weapon = DK_W_RIPGUN;
    Run(10, qfalse); assert(state.weaponstate == WEAPON_DROPPING && state.dk3WeaponSequence != DK_GLOCK_RELOAD_SEQUENCE);
    Run(DK_WeaponSwitchTime(DK_W_GLOCK, qfalse), qfalse);
    assert(state.weapon == DK_W_RIPGUN && state.weaponstate == WEAPON_RAISING);

    Begin(DK_W_DISRUPTOR, 0);
    state.dk3Inventory |= 1u << DK_W_HAMMER; movement.cmd.weapon = DK_W_HAMMER;
    Run(10, qfalse); assert(state.weapon == DK_W_DISRUPTOR && state.weaponstate == WEAPON_DROPPING);
    Run(DK_WeaponSwitchTime(DK_W_DISRUPTOR, qfalse), qfalse);
    assert(state.weapon == DK_W_HAMMER && state.weaponstate == WEAPON_RAISING);
    Run(DK_WeaponSwitchTime(DK_W_HAMMER, qtrue) + 10, qfalse);
    assert(state.weapon == DK_W_HAMMER && state.weaponstate == WEAPON_READY);

    Begin(DK_W_VENOM, 0); Run(10, qtrue);
    assert(shots == 1 && state.dk3WeaponSequence == 128 && state.ammo[DK_W_VENOM] == 0);
    Begin(DK_W_VENOM, 10); contact = 1; Run(10, qtrue);
    assert(shots == 1 && state.ammo[DK_W_VENOM] == 10);
    Begin(DK_W_VENOM, 10); movement.waterlevel = 3; Run(10, qtrue);
    assert(shots == 1 && state.ammo[DK_W_VENOM] == 10);
    Begin(DK_W_VENOM, 10); Run(10, qtrue);
    assert(shots == 1 && state.ammo[DK_W_VENOM] == 9);

    Begin(DK_W_FLASHLIGHT, 20); Run(1000, qtrue); assert(shots == 1);
    Run(10, qfalse); Run(10, qtrue); assert(shots == 2);
    assert(DK_SwordLevel(249) == 1 && DK_SwordLevel(250) == 2 && DK_SwordLevel(749) == 2);
    assert(DK_SwordLevel(750) == 3 && DK_SwordLevel(1500) == 4 && DK_SwordLevel(3000) == 5);
    /* Episode transfer keeps sword progression while replacing episode gear. */
    Begin(DK_W_SHOTCYCLER, 20);
    state.dk3Inventory |= (1u << DK_W_SWORD) | (1u << DK_W_GASHANDS);
    state.dk3SwordExperience = 900; state.powerups[PW_DK3_GASHANDS] = 60000;
    memset(&checkpoint, 0, sizeof(checkpoint));
    checkpoint.weapon = DK_W_HAMMER; checkpoint.dk3Inventory = 1u << DK_W_HAMMER;
    DK_WeaponChangeEpisode(&state, &checkpoint);
    assert(state.weapon == DK_W_HAMMER && state.dk3Inventory == ((1u << DK_W_HAMMER) | (1u << DK_W_SWORD)));
    assert(state.dk3SwordExperience == 900 && state.powerups[PW_DK3_GASHANDS] == 0);
    assert(state.ammo[DK_W_SHOTCYCLER] == 0);
    assert(DK_ValidWeaponPlayer(&state, 100));
    state.dk3Charge = 1801; assert(!DK_ValidWeaponPlayer(&state, 100));
    return 0;
}
