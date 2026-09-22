/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef DK_WEAPONS_H
#define DK_WEAPONS_H

typedef enum {
    DK_W_NONE, DK_W_DISRUPTOR, DK_W_ION, DK_W_C4, DK_W_SHOTCYCLER,
    DK_W_SIDEWINDER, DK_W_SHOCKWAVE, DK_W_GASHANDS, DK_W_SWORD,
    DK_W_DISCUS, DK_W_SUNFLARE, DK_W_VENOM, DK_W_HAMMER, DK_W_TRIDENT,
    DK_W_ZEUS, DK_W_SILVERCLAW, DK_W_BOLTER, DK_W_STAVROS, DK_W_BALLISTA,
    DK_W_WYNDRAX, DK_W_NIGHTMARE, DK_W_GLOCK, DK_W_RIPGUN, DK_W_SLUGGER,
    DK_W_KINETICORE, DK_W_NOVABEAM, DK_W_METAMASER, DK_W_CORDITE,
    DK_W_FLASHLIGHT, DK_WEAPON_COUNT
} dkWeapon_t;

/* Event cause values 129..156 name native weapons; upstream causes stay intact. */
#define DK_MOD_WEAPON_BASE 128
#define DK_WEAPON_MOD(weapon) ((weapon) > DK_W_NONE && (weapon) < DK_WEAPON_COUNT ? DK_MOD_WEAPON_BASE + (weapon) : MOD_UNKNOWN)

typedef struct {
    const char *classname;
    const char *label;
    int episode;
    int interval;
    int ammoMax, ammoCost, initialAmmo;
    float damage, range, speed, lifetime;
    vec3_t muzzle;
    char model[MAX_QPATH];
    qboolean loaded;
} dkWeaponInfo_t;

extern dkWeaponInfo_t dk_weapons[DK_WEAPON_COUNT];
void DK_LoadWeaponData(void);
int DK_WeaponId(const char *classname);
int DK_FirstWeapon(int episode);
int DK_ExperienceThreshold(int level);
const char *DK_WeaponWorldModel(int weapon);
qboolean DK_HasWeapon(const playerState_t *ps, int weapon);
int DK_Attribute(const playerState_t *ps, int attribute, int time);
/* Remove an expired temporary weapon and select an owned fallback. */
void DK_ExpireGasHands(playerState_t *ps);
#define DK_MAX_GASHANDS_TIME 3600000

#endif
