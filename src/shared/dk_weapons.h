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
#define DK_GLOCK_RELOAD_SEQUENCE 256

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
int DK_WeaponSwitchTime(int weapon, qboolean raising);
void DK_LoadWeaponData(void);
int DK_WeaponId(const char *classname);
int DK_AmmoWeapon(const char *classname);
qboolean DK_AddAmmunition(int *ammo, int weapon, int rounds);
qboolean DK_AddWeapon(int *inventory, int *ammo, int *selected, int weapon, int rounds);
qboolean DK_WeaponProtectsWater(int weapon);
int DK_CompanionFirstWeapon(int episode);
qboolean DK_WeaponInventoryVisible(int weapon);
const char *DK_WeaponInventoryModel(int weapon);
void DK_WeaponInventoryText(const playerState_t *ps, int weapon, int time, char *buffer, int size);
int DK_WeaponHudValue(const playerState_t *ps, int time);
void DK_WeaponChangeEpisode(playerState_t *ps, const playerState_t *starting);
qboolean DK_ValidWeaponPlayer(const playerState_t *ps, int time);
int DK_FirstWeapon(int episode);
int DK_ExperienceThreshold(int level);
int DK_SwordLevel(int experience);

/* Daikatana swings: each has one or two swipes, a follow-through frame and the
   set of swings (bit per index) that may chain after it. Arc endpoints are in
   forward/right/up units of the weapon range; a zero arc is a straight jab. */
typedef struct {
    const char *pose;
    int hits, damageFrame[2], followThrough, next;
    float from[2][3], to[2][3];
} dkSwordSwing_t;
#define DK_SWORD_SWINGS 7
#define DK_SWORD_SWING(sequence) ((sequence) & 7)
#define DK_SWORD_COMBO(sequence) (((sequence) >> 3) & 15)
extern const dkSwordSwing_t dk_swordSwings[DK_SWORD_SWINGS];
int DK_SwordFrameTime(int experience);
int DK_NovaLifetime(int boost);
#define DK_NOVA_RETRACT 64
int DK_SwordSelect(int previous, unsigned int seed);
const char *DK_WeaponWorldModel(int weapon);
qboolean DK_HasWeapon(const playerState_t *ps, int weapon);
int DK_Attribute(const playerState_t *ps, int attribute, int time);
/* Remove an expired temporary weapon and select an owned fallback. */
void DK_ExpireGasHands(playerState_t *ps);
#define DK_MAX_GASHANDS_TIME 3600000

void DK_WeaponMoveZig(pmove_t *movement, int msec);

#endif
