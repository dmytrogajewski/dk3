/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "dk_weapons.h"

static void DK_WeaponMove(void) {
    dkWeaponInfo_t *weapon;
    qboolean pressed = (pm->cmd.buttons & BUTTON_ATTACK) != 0;
    int selected = pm->cmd.weapon;
    if (pm->ps->pm_type != PM_NORMAL || pm->ps->stats[STAT_HEALTH] <= 0 ||
        (pm->ps->pm_flags & PMF_RESPAWNED)) return;
    if (pm->ps->powerups[PW_DK3_GASHANDS] > 0 &&
        pm->ps->powerups[PW_DK3_GASHANDS] <= pm->cmd.serverTime)
        DK_ExpireGasHands(pm->ps);
    pm->ps->weaponTime -= pml.msec;
    if (pm->ps->weaponTime < -pml.msec) pm->ps->weaponTime = -pml.msec;
    if (selected != pm->ps->weapon && DK_HasWeapon(pm->ps, selected) && pm->ps->weaponTime <= 0) {
        pm->ps->weapon = selected;
        pm->ps->weaponstate = WEAPON_RAISING;
        pm->ps->weaponTime = 250;
        pm->ps->dk3Burst = pm->ps->dk3Charge = 0;
        return;
    }
    if (!DK_HasWeapon(pm->ps, pm->ps->weapon)) return;
    weapon = &dk_weapons[pm->ps->weapon];
    if (pm->ps->weapon == DK_W_HAMMER) {
        if (pressed) {
            if (!pm->ps->dk3AttackHeld) pm->ps->dk3Charge = 0;
            pm->ps->dk3Charge += pml.msec;
            if (pm->ps->dk3Charge > 1800) pm->ps->dk3Charge = 1800;
        }
        if (pressed || !pm->ps->dk3AttackHeld) { pm->ps->dk3AttackHeld = pressed; return; }
    } else if (!pressed && !pm->ps->dk3Burst) {
        pm->ps->dk3AttackHeld = 0;
        if (pm->ps->weaponTime <= 0) pm->ps->weaponstate = WEAPON_READY;
        return;
    }
    pm->ps->dk3AttackHeld = pressed;
    if (pm->ps->weaponTime > 0) return;
    if (weapon->ammoCost && pm->ps->ammo[pm->ps->weapon] < weapon->ammoCost) {
        PM_AddEvent(EV_NOAMMO);
        pm->ps->weaponTime = 300;
        pm->ps->dk3Burst = 0;
        return;
    }
    if (pm->ps->weapon == DK_W_SHOTCYCLER && !pm->ps->dk3Burst) pm->ps->dk3Burst = 6;
    pm->ps->ammo[pm->ps->weapon] -= weapon->ammoCost;
    pm->ps->weaponstate = WEAPON_FIRING;
    PM_StartTorsoAnim(TORSO_ATTACK);
    PM_AddEvent(EV_FIRE_WEAPON);
    pm->ps->weaponTime += weapon->interval / (1 + 0.1f * DK_Attribute(pm->ps, 1, pm->cmd.serverTime));
    if (pm->ps->dk3Burst && --pm->ps->dk3Burst == 0) pm->ps->weaponTime += 450;
}
