/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifdef CGAME
#include "cg_local.h"
#define WeaponError CG_Error
#else
#include "g_local.h"
#define WeaponError G_Error
#endif
#include "dk_weapons.h"

int DK_ExperienceThreshold(int level) {
    return level * level * 250;
}

int DK_Attribute(const playerState_t *ps, int attribute, int time) {
    int value;
    if (attribute < 0 || attribute >= 5) return 0;
    value = ps->dk3Attributes[attribute] + (ps->dk3BoostUntil[attribute] > time ? 1 : 0);
    return value > 5 ? 5 : value;
}
#include "dk_tables.h"

#define WEAPON(name, text, ep, ms) { .classname = "weapon_" name, .label = text, .episode = ep, .interval = ms }
dkWeaponInfo_t dk_weapons[DK_WEAPON_COUNT] = {
    { .classname = "", .label = "Unarmed" },
    WEAPON("disruptor", "Disruptor", 1, 600),
    /* Eight supplied shoota frames at 20 Hz, followed by a 100 ms recovery. */
    WEAPON("ionblaster", "Ion blaster", 1, 500),
    WEAPON("c4", "C4 Vizatergo", 1, 600),
    WEAPON("shotcycler", "Shotcycler-6", 1, 150),
    WEAPON("sidewinder", "Sidewinder", 1, 850),
    WEAPON("shockwave", "Shockwave", 1, 1000),
    WEAPON("gashands", "Gas hands", 1, 450),
    WEAPON("daikatana", "Daikatana", 0, 420),
    WEAPON("discus", "Discus of Daedalus", 2, 650),
    WEAPON("sunflare", "Sunflare", 2, 700),
    WEAPON("venomous", "Venomous", 2, 330),
    WEAPON("hammer", "Hammer of Hephaestus", 2, 700),
    WEAPON("trident", "Trident of Poseidon", 2, 450),
    WEAPON("zeus", "Eye of Zeus", 2, 1200),
    WEAPON("silverclaw", "Silverclaw", 3, 420),
    WEAPON("bolter", "Bolter", 3, 250),
    WEAPON("stavros", "Stavros staff", 3, 850),
    WEAPON("ballista", "Ballista", 3, 900),
    WEAPON("wyndrax", "Wyndrax's wisp", 3, 1000),
    WEAPON("nightmare", "Nharre's Nightmare", 3, 2000),
    WEAPON("glock", "Glock", 4, 230),
    WEAPON("ripgun", "Ripgun", 4, 90),
    WEAPON("slugger", "Slugger", 4, 700),
    WEAPON("kineticore", "Kineticore", 4, 100),
    WEAPON("novabeam", "Novabeam", 4, 80),
    WEAPON("metamaser", "Metamaser", 4, 1300),
    WEAPON("cordite", "Cordite", 4, 850),
    WEAPON("flashlight", "Flashlight", 0, 300)
};
#undef WEAPON

int DK_WeaponId(const char *classname) {
    int i;
    if (!Q_stricmp(classname, "weapon_c4viz")) return DK_W_C4;
    for (i = 1; i < DK_WEAPON_COUNT; ++i)
        if (!Q_stricmp(dk_weapons[i].classname, classname)) return i;
    return 0;
}

static void ReadWeapon(const dkRecord_t *row) {
    int id = DK_WeaponId(DK_Field(row, "classname"));
    dkWeaponInfo_t *weapon;
    if (!id) WeaponError("dk3: unsupported weapon table class %s", DK_Field(row, "classname"));
    weapon = &dk_weapons[id];
    if (weapon->loaded) WeaponError("dk3: duplicate weapon table class %s", weapon->classname);
    weapon->ammoMax = DK_Number(row, "ammo_max", 0);
    weapon->ammoCost = DK_Number(row, "ammo_per_use", 0);
    weapon->initialAmmo = DK_Number(row, "initial_ammo", 0);
    weapon->damage = DK_Number(row, "damage", 0);
    weapon->speed = DK_Number(row, "speed", 0);
    weapon->range = DK_Number(row, "range", 0);
    weapon->lifetime = DK_Number(row, "lifetime", 0);
    weapon->muzzle[0] = DK_Number(row, "projectile_x1", DK_Number(row, "projectile_x", 8));
    weapon->muzzle[1] = DK_Number(row, "projectile_y1", DK_Number(row, "projectile_y", 12));
    weapon->muzzle[2] = DK_Number(row, "projectile_z1", DK_Number(row, "projectile_z", 0));
    if (weapon->ammoMax < 0 || weapon->ammoMax > 32767 || weapon->ammoCost < 0 ||
        weapon->initialAmmo < 0 || weapon->initialAmmo > weapon->ammoMax || weapon->damage < 0)
        WeaponError("dk3: invalid ammunition/damage values for %s", weapon->classname);
    {
        const char *stem = weapon->classname + 7;
        switch (id) {
            case DK_W_DISRUPTOR: stem = "tglove"; break;
            case DK_W_SUNFLARE: stem = "sflare"; break;
            case DK_W_ZEUS: stem = "zeuseye"; break;
            case DK_W_BALLISTA: stem = "bal"; break;
            case DK_W_WYNDRAX: stem = "wisp"; break;
            case DK_W_NIGHTMARE: stem = "nmare"; break;
            case DK_W_KINETICORE: stem = "kcore"; break;
            case DK_W_METAMASER: stem = "mmaser"; break;
            case DK_W_GASHANDS: stem = "gashand"; break;
        }
        if (id == DK_W_SWORD) Q_strncpyz(weapon->model, "models/global/w_daikatana.dkm", sizeof(weapon->model));
        else if (id == DK_W_FLASHLIGHT) *weapon->model = 0;
        else Com_sprintf(weapon->model, sizeof(weapon->model), "models/e%d/w_%s.dkm", weapon->episode, stem);
    }
    weapon->loaded = qtrue;
}

void DK_LoadWeaponData(void) {
    int i;
    for (i = 1; i < DK_WEAPON_COUNT; ++i) dk_weapons[i].loaded = qfalse;
    DK_ReadTable("weapons", ReadWeapon);
    for (i = 1; i < DK_W_FLASHLIGHT; ++i)
        if (!dk_weapons[i].loaded) WeaponError("dk3: required weapon table row missing: %s", dk_weapons[i].classname);
}

int DK_FirstWeapon(int episode) {
    return episode == 2 ? DK_W_HAMMER : episode == 3 ? DK_W_SILVERCLAW : episode == 4 ? DK_W_GLOCK : DK_W_DISRUPTOR;
}

qboolean DK_HasWeapon(const playerState_t *ps, int weapon) {
    return weapon > DK_W_NONE && weapon < DK_WEAPON_COUNT &&
           ((unsigned int)ps->dk3Inventory & (1u << weapon)) != 0;
}

void DK_ExpireGasHands(playerState_t *ps) {
    int weapon;
    ps->dk3Inventory &= ~(1u << DK_W_GASHANDS);
    ps->powerups[PW_DK3_GASHANDS] = 0;
    if (ps->weapon != DK_W_GASHANDS) return;
    weapon = DK_W_DISRUPTOR;
    if (!DK_HasWeapon(ps, weapon))
        for (weapon = 1; weapon < DK_WEAPON_COUNT && !DK_HasWeapon(ps, weapon); ++weapon) {}
    ps->weapon = weapon < DK_WEAPON_COUNT ? weapon : DK_W_NONE;
    ps->weaponstate = WEAPON_RAISING;
    ps->weaponTime = 250;
    ps->dk3Burst = ps->dk3Charge = ps->dk3AttackHeld = 0;
}

static const char *worldModels[DK_WEAPON_COUNT] = {
    "", "e1/a_tazer", "e1/wa_ion", "e1/wa_c4", "e1/wa_shot6", "e1/wa_swindr", "e1/wa_shokwv",
    "e1/a_gashand", "global/a_daikatana", "e2/a_discus", "e2/a_sflare", "e2/wa_venom", "e2/a_hammer",
    "e2/wa_trident", "e2/wa_zeus", "e3/a_claw", "e3/wa_bolt", "e3/wa_stav", "e3/wa_bal",
    "e3/a_wyndrx", "e3/a_nmare", "e4/wa_glock", "e4/wa_rip", "e4/wa_slug", "e4/wa_kcore",
    "e4/wa_nova", "e4/a_mmaser", "e4/a_cslug", ""
};

const char *DK_WeaponWorldModel(int weapon) {
    return weapon > 0 && weapon < DK_WEAPON_COUNT && *worldModels[weapon] ? va("models/%s.dkm", worldModels[weapon]) : "";
}
