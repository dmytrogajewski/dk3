/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_weapons.h"
#include "dk_inventory.h"

typedef struct { const char *classname; int weapon; } dkAmmo_t;
static const dkAmmo_t ammunition[] = {
    {"ammo_ionpack", DK_W_ION}, {"ammo_c4", DK_W_C4}, {"ammo_shells", DK_W_SHOTCYCLER},
    {"ammo_rockets", DK_W_SIDEWINDER}, {"ammo_shocksphere", DK_W_SHOCKWAVE},
    {"ammo_tritips", DK_W_TRIDENT}, {"ammo_venomous", DK_W_VENOM}, {"ammo_zeus", DK_W_ZEUS},
    {"ammo_bolts", DK_W_BOLTER}, {"ammo_ballista", DK_W_BALLISTA}, {"ammo_stavros", DK_W_STAVROS},
    {"ammo_wisp", DK_W_WYNDRAX}, {"ammo_bullets", DK_W_GLOCK}, {"ammo_ripgun", DK_W_RIPGUN},
    {"ammo_slugger", DK_W_SLUGGER}, {"ammo_cordite", DK_W_CORDITE}, {"ammo_kineticore", DK_W_KINETICORE},
    {"ammo_novabeam", DK_W_NOVABEAM}, {"ammo_metamaser", DK_W_METAMASER}
};


static const char *boosts[] = {"item_power_boost", "item_attack_boost", "item_speed_boost", "item_acro_boost", "item_vita_boost"};

static int KeyIndex(const char *classname) {
    int i;
    for (i = 0; i < DK_KEY_COUNT; ++i) if (!Q_stricmp(dk_keyClasses[i], classname)) return i;
    return -1;
}

qboolean DK_HasKey(gentity_t *player, const char *name) {
    int index = KeyIndex(name);
    unsigned int mask;
    if (!player || !player->client) return qfalse;
    if (DK_ObjectiveMode()) {
        if (!strcmp(name, "item_control_card_red")) return player->client->sess.sessionTeam == TEAM_RED;
        if (!strcmp(name, "item_control_card_blue")) return player->client->sess.sessionTeam == TEAM_BLUE;
    }
    if (!strcmp(name, "item_bomb")) return (player->client->ps.dk3Quest & 1) != 0;
    mask = player->client->ps.dk3Keys;
    if (!strcmp(name, "item_purifier")) return (mask & 0xfe000000u) == 0xfe000000u;
    if (!strcmp(name, "item_purifier_shard2")) return (mask & 0x7c000000u) == 0x7c000000u;
    if (index < 0) return qfalse;
    return ((unsigned int)player->client->ps.dk3Keys & (1u << index)) != 0;
}

static qboolean AddWeapon(int *inventory, int *ammo, int *selected, int weapon, int rounds) {
    dkWeaponInfo_t *info = &dk_weapons[weapon];
    qboolean owned = ((unsigned int)*inventory & (1u << weapon)) != 0;
    if (owned && (!info->ammoMax || ammo[weapon] >= info->ammoMax)) return qfalse;
    *inventory |= 1u << weapon;
    ammo[weapon] += rounds;
    if (ammo[weapon] > info->ammoMax) ammo[weapon] = info->ammoMax;
    if (!owned && weapon != DK_W_FLASHLIGHT) *selected = weapon;
    if (weapon == DK_W_SLUGGER) {
        *inventory |= 1u << DK_W_CORDITE;
        ammo[DK_W_CORDITE] += dk_weapons[DK_W_CORDITE].initialAmmo;
        if (ammo[DK_W_CORDITE] > dk_weapons[DK_W_CORDITE].ammoMax) ammo[DK_W_CORDITE] = dk_weapons[DK_W_CORDITE].ammoMax;
    }
    return qtrue;
}

static qboolean GiveWeapon(gentity_t *player, int weapon, int rounds) {
    playerState_t *ps = &player->client->ps;
    if (weapon == DK_W_GASHANDS && g_gametype.integer == GT_SINGLE_PLAYER) {
        int duration = (int)(Com_Clamp(0, DK_MAX_GASHANDS_TIME / 1000, dk_weapons[weapon].lifetime) * 1000);
        int remaining = ps->powerups[PW_DK3_GASHANDS] - level.time;
        if (duration <= 0) G_Error("dk3: weapon_gashands requires a positive supplied lifetime");
        if (remaining < 0) remaining = 0;
        if (remaining >= DK_MAX_GASHANDS_TIME) return qfalse;
        if (duration > DK_MAX_GASHANDS_TIME - remaining) duration = DK_MAX_GASHANDS_TIME - remaining;
        ps->powerups[PW_DK3_GASHANDS] = level.time + remaining + duration;
        ps->dk3Inventory |= 1u << weapon;
        ps->weapon = weapon;
        G_AddEvent(player, EV_GENERAL_SOUND, DK_SoundIndex("e1/we_gasstart.wav"));
        trap_SendServerCommand(player->s.number, va("dk3_weapon %d", weapon));
        return qtrue;
    }
    return AddWeapon(&ps->dk3Inventory, ps->ammo, &ps->weapon, weapon, rounds);
}

void DK_RunItemEffects(void) {
    int i;
    if (g_gametype.integer != GT_SINGLE_PLAYER) return;
    for (i = 0; i < level.maxclients; ++i) {
        gentity_t *player = &g_entities[i];
        playerState_t *ps;
        if (!player->inuse || !player->client) continue;
        ps = &player->client->ps;
        if (!DK_HasWeapon(ps, DK_W_GASHANDS)) continue;
        if (player->health <= 0) {
            DK_ExpireGasHands(ps);
            continue;
        }
        if (ps->dk3CameraActive && ps->powerups[PW_DK3_GASHANDS] > 0)
            ps->powerups[PW_DK3_GASHANDS] += level.time - level.previousTime;
        if (ps->powerups[PW_DK3_GASHANDS] > level.time) continue;
        DK_ExpireGasHands(ps);
        G_AddEvent(player, EV_GENERAL_SOUND, DK_SoundIndex("e1/we_gasstopa.wav"));
        trap_SendServerCommand(i, va("dk3_weapon %d", ps->weapon));
        trap_SendServerCommand(i, "print \"Gas Hands has expired.\n\"");
    }
}

int DK_PlayerWeaponLoop(gentity_t *player) {
    playerState_t *ps = &player->client->ps;
    if (player->health > 0 && ps->pm_type == PM_NORMAL && !ps->dk3CameraActive &&
        ps->weapon == DK_W_GASHANDS && DK_HasWeapon(ps, DK_W_GASHANDS))
        return DK_SoundIndex("e1/we_gasloop.wav");
    return 0;
}

void DK_StartingInventory(gentity_t *player) {
    char map[MAX_QPATH];
    int episode, initial;
    trap_Cvar_VariableStringBuffer("mapname", map, sizeof(map));
    episode = map[0] == 'e' && map[1] >= '1' && map[1] <= '4' ? map[1] - '0' : 1;
    initial = DK_FirstWeapon(episode);
    player->health = player->client->ps.stats[STAT_HEALTH] = player->client->ps.stats[STAT_MAX_HEALTH];
    player->client->ps.dk3Inventory = 0;
    memset(player->client->ps.ammo, 0, sizeof(player->client->ps.ammo));
    GiveWeapon(player, initial, dk_weapons[initial].initialAmmo);
    player->client->ps.weapon = initial;
    player->client->ps.stats[STAT_WEAPONS] = 0;
    player->client->ps.dk3Level = 1;
    player->client->ps.dk3Episode = episode;
    player->client->ps.dk3SoundEnvironment = 0;
    player->client->ps.dk3Reverb = 0;
    player->client->ps.dk3SoundGain = 1;
}

static qboolean Give(gentity_t *item, gentity_t *player) {
    playerState_t *ps = &player->client->ps;
    const char *name = item->classname;
    int i, weapon = DK_WeaponId(name), amount = item->count;
    if (weapon) return GiveWeapon(player, weapon, amount > 0 ? amount : dk_weapons[weapon].initialAmmo);
    for (i = 0; i < ARRAY_LEN(ammunition); ++i) if (!strcmp(name, ammunition[i].classname)) {
        weapon = ammunition[i].weapon;
        if (ps->ammo[weapon] >= dk_weapons[weapon].ammoMax) return qfalse;
        ps->ammo[weapon] += amount > 0 ? amount : dk_weapons[weapon].initialAmmo;
        if (ps->ammo[weapon] > dk_weapons[weapon].ammoMax) ps->ammo[weapon] = dk_weapons[weapon].ammoMax;
        return qtrue;
    }
    i = KeyIndex(name);
    if (i >= 0) {
        unsigned int bombParts = 0x0003c000u;
        ps->dk3Keys |= 1u << i;
        if (((unsigned int)ps->dk3Keys & bombParts) == bombParts) {
            ps->dk3Keys &= ~bombParts; ps->dk3Quest |= 1;
            trap_SendServerCommand(player->s.number, "cp \"The bottle bomb is assembled.\"");
        }
        return qtrue;
    }
    for (i = 0; i < ARRAY_LEN(boosts); ++i) if (!strcmp(name, boosts[i])) {
        if (ps->dk3Attributes[i] >= 5) return qfalse;
        ps->dk3BoostUntil[i] = level.time + 30000;
        return qtrue;
    }
    if (!strncmp(name, "item_health_", 12) || !strcmp(name, "item_goldensoul")) {
        qboolean soul = !strcmp(name, "item_goldensoul");
        int maximum = ps->stats[STAT_MAX_HEALTH] + (soul ? 100 : 0);
        if (player->health >= maximum) return qfalse;
        player->health += amount > 0 ? amount : soul ? 100 : atoi(name + 12);
        if (player->health > maximum) player->health = maximum;
        ps->stats[STAT_HEALTH] = player->health;
        return qtrue;
    }
    if (strstr(name, "_armor") || !strcmp(name, "item_megashield")) {
        amount = amount > 0 ? amount : !strcmp(name, "item_megashield") ? 200 : 100;
        if (ps->stats[STAT_ARMOR] >= amount) return qfalse;
        ps->stats[STAT_ARMOR] = amount;
        return qtrue;
    }
    if (!strcmp(name, "item_antidote")) {
        player->dk.status = 0;
        ps->dk3Status &= ~7;
        return qtrue;
    }
    if (!strcmp(name, "item_invincibility")) { ps->dk3InvincibleUntil = level.time + 30000; return qtrue; }
    if (!strcmp(name, "item_wraithorb")) { ps->powerups[PW_INVIS] = level.time + 30000; return qtrue; }
    if (!strcmp(name, "item_envirosuit")) { ps->dk3EnvUntil = level.time + 60000; return qtrue; }
    if (!strcmp(name, "item_ring_of_fire") || !strcmp(name, "item_ring_of_lightning") || !strcmp(name, "item_ring_of_undead")) {
        ps->dk3Status |= !strcmp(name, "item_ring_of_fire") ? 16 : !strcmp(name, "item_ring_of_lightning") ? 32 : 64;
        return qtrue;
    }
    if (!strcmp(name, "item_savegem")) { ++ps->dk3SaveGems; return qtrue; }
    return qfalse;
}

static void Respawn(gentity_t *item) {
    item->r.contents = CONTENTS_TRIGGER;
    item->r.svFlags &= ~SVF_NOCLIENT;
    trap_LinkEntity(item);
}

static void Taken(gentity_t *item, gentity_t *collector) {
    const char *name = item->classname, *sound = "global/itempickup1.wav";
    int i;
    static const char *boostSounds[] = {"global/a_pboost.wav", "global/a_atkboost.wav", "global/a_sboost.wav", "global/a_aboost.wav", "global/a_vboost.wav"};
    if (DK_WeaponId(name)) sound = "global/i_pickup6.wav";
    else if (!strncmp(name, "ammo_", 5)) {
        sound = "global/i_c4ammo.wav";
        if (!strcmp(name, "ammo_ionpack")) sound = "global/i_ionammo.wav";
        else if (!strcmp(name, "ammo_shells")) sound = "global/i_scyclerammo.wav";
        else if (!strcmp(name, "ammo_rockets")) sound = "global/i_swinderammo.wav";
        else if (!strcmp(name, "ammo_shocksphere")) sound = "global/i_swaveammo.wav";
    } else if (!strncmp(name, "item_health_", 12)) sound = atoi(name + 12) >= 50 ? "global/a_h50pick.wav" : "global/a_hpick.wav";
    else if (strstr(name, "_armor")) sound = strstr(name, "plasteel") || strstr(name, "silver") || strstr(name, "chainmail") ?
        "global/armorpickup2.wav" : "global/armorpickup1.wav";
    else if (!strcmp(name, "item_goldensoul")) sound = "artifacts/goldensoulpickup.wav";
    else if (!strcmp(name, "item_savegem")) sound = "artifacts/savegem_pickup.wav";
    else if (!strcmp(name, "item_wraithorb")) sound = "artifacts/wraithorbpickup.wav";
    else if (!strcmp(name, "item_envirosuit")) sound = "artifacts/envirosuitpickup.wav";
    for (i = 0; i < ARRAY_LEN(boosts); ++i) if (!strcmp(name, boosts[i])) sound = boostSounds[i];
    G_Sound(collector, CHAN_ITEM, DK_SoundIndex(sound));
    item->r.contents = 0;
    item->r.svFlags |= SVF_NOCLIENT;
    trap_UnlinkEntity(item);
    G_UseTargets(item, collector);
    if (!item->inuse) return;
    if (item->dk.expires) { G_FreeEntity(item); return; }
    if (g_gametype.integer != GT_SINGLE_PLAYER) { item->think = Respawn; item->nextthink = level.time + 30000; }
    if (collector->client) {
        int weapon = DK_WeaponId(item->classname);
        trap_SendServerCommand(collector->s.number, va("print \"Picked up %s\n\"", weapon ? dk_weapons[weapon].label : item->classname));
    }
}

static void ItemTouch(gentity_t *item, gentity_t *other, trace_t *trace) {
    (void)trace;
    if (!other->client || other->health <= 0 || !(item->r.contents & CONTENTS_TRIGGER)) return;
    if (Give(item, other)) Taken(item, other);
}

qboolean DK_SpawnItem(gentity_t *item) {
    if (!strcmp(item->classname, "item_vitality_boost")) item->classname = "item_vita_boost";
    int weapon = DK_WeaponId(item->classname), i;
    qboolean supported = weapon != 0 || KeyIndex(item->classname) >= 0;
    const char *name = item->classname;
    for (i = 0; i < ARRAY_LEN(ammunition); ++i) if (!strcmp(name, ammunition[i].classname)) supported = qtrue;
    for (i = 0; i < ARRAY_LEN(boosts); ++i) if (!strcmp(name, boosts[i])) supported = qtrue;
    if (!strncmp(name, "item_health_", 12) || strstr(name, "_armor") ||
        !strcmp(name, "item_megashield") || !strcmp(name, "item_antidote") || !strcmp(name, "item_invincibility") ||
        !strcmp(name, "item_wraithorb") || !strcmp(name, "item_envirosuit") || !strcmp(name, "item_savegem") ||
        !strcmp(name, "item_goldensoul") || !strncmp(name, "item_ring_of_", 13)) supported = qtrue;
    if (!supported) return qfalse;
    item->s.eType = ET_DK3_ITEM;
    item->r.contents = CONTENTS_TRIGGER;
    item->touch = ItemTouch;
    VectorSet(item->r.mins, -16, -16, -16);
    VectorSet(item->r.maxs, 16, 16, 16);
    if (!item->model) item->model = DK_ItemModel(item->classname);
    if (item->model) item->s.modelindex = G_ModelIndex(item->model);
    G_SetOrigin(item, item->s.origin);
    trap_LinkEntity(item);
    return qtrue;
}

void DK_DeathSpawn(gentity_t *source) {
    gentity_t *spawn;
    vec3_t origin, destination;
    trace_t trace, path;
    int attempt;
    if (!source->dk.deathSpawn) return;
    spawn = G_Spawn(); spawn->classname = G_NewString(source->dk.deathSpawn);
    VectorCopy(source->r.currentOrigin, origin); VectorCopy(origin, spawn->s.origin);
    if (!DK_SpawnItem(spawn) && !DK_SpawnActor(spawn)) {
        G_Error("dk3: entity %u (%s): unsupported death spawn %s", source->dk.id, source->classname, spawn->classname);
        return;
    }
    trap_UnlinkEntity(spawn);
    for (attempt = 0; attempt < 9; ++attempt) {
        VectorCopy(origin, destination); destination[2] += 24;
        if (attempt) {
            destination[0] += cos((attempt - 1) * M_PI / 4) * 48;
            destination[1] += sin((attempt - 1) * M_PI / 4) * 48;
        }
        trap_Trace(&trace, destination, spawn->r.mins, spawn->r.maxs, destination, source->s.number, MASK_PLAYERSOLID);
        trap_Trace(&path, origin, NULL, NULL, destination, source->s.number, MASK_SOLID);
        if (!trace.startsolid && !trace.allsolid && path.fraction == 1) break;
    }
    if (attempt == 9) G_Error("dk3: entity %u (%s): death spawn %s has no clear placement", source->dk.id, source->classname, spawn->classname);
    G_SetOrigin(spawn, destination);
    if (spawn->s.eType == ET_DK3_ITEM) {
        spawn->physicsObject = qtrue; spawn->physicsBounce = 0.35f;
        spawn->s.pos.trType = TR_GRAVITY; spawn->s.pos.trTime = level.time;
        spawn->s.pos.trDelta[2] = 100; spawn->s.groundEntityNum = ENTITYNUM_NONE;
        spawn->clipmask = MASK_SOLID;
    } else spawn->enemy = source->enemy;
    trap_LinkEntity(spawn);
}

void DK_AwardExperience(gentity_t *player, int amount, qboolean sword) {
    playerState_t *ps;
    if (!player || amount <= 0) return;
    if (DK_IsCompanion(player)) {
        player->dk.experience += amount;
        while (player->dk.actorLevel < 25 && player->dk.experience >= DK_ExperienceThreshold(player->dk.actorLevel)) {
            int attribute = player->dk.actorLevel % 5;
            ++player->dk.actorLevel;
            if (player->dk.attributes[attribute] < 5) ++player->dk.attributes[attribute];
            player->dk.maxHealth = 100 + player->dk.attributes[4] * 20;
            player->health = player->dk.maxHealth;
        }
        return;
    }
    if (!player->client) return;
    ps = &player->client->ps;
    ps->dk3Experience += amount;
    if (sword) ps->dk3SwordExperience += amount;
    while (ps->dk3Level < 25 && ps->dk3Experience >= DK_ExperienceThreshold(ps->dk3Level)) {
        ++ps->dk3Level;
        ++ps->dk3AttributePoints;
        trap_SendServerCommand(player->s.number, "cp \"Level gained. Use attribute <power|attack|speed|acro|vita> to improve a skill.\"");
    }
}

void DK_RestoreItem(gentity_t *ent) {
    ent->touch = ItemTouch;
    ent->think = ent->dk.expires ? G_FreeEntity : ent->nextthink > 0 ? Respawn : NULL;
}

void DK_DropInventory(gentity_t *player) {
    int weapon = player->client->ps.weapon;
    gentity_t *item;
    DK_DropObjective(player);
    if (g_gametype.integer == GT_SINGLE_PLAYER || weapon <= DK_W_NONE || weapon >= DK_W_FLASHLIGHT ||
        !dk_weapons[weapon].ammoMax || player->client->ps.ammo[weapon] <= 0) return;
    item = G_Spawn();
    item->classname = G_NewString(dk_weapons[weapon].classname);
    item->count = player->client->ps.ammo[weapon];
    VectorCopy(player->r.currentOrigin, item->s.origin);
    if (!DK_SpawnItem(item)) { G_FreeEntity(item); return; }
    item->dk.expires = level.time + 30000;
    item->think = G_FreeEntity;
    item->nextthink = item->dk.expires;
}

float DK_CompanionItemValue(gentity_t *actor, gentity_t *item) {
    int i, weapon;
    qboolean mikiko = strstr(actor->classname, "mikiko") && !strstr(actor->classname, "mikikofly");
    if (!item->inuse || item->s.eType != ET_DK3_ITEM || !(item->r.contents & CONTENTS_TRIGGER)) return 0;
    if ((item->spawnflags & 3) && !(item->spawnflags & (mikiko ? 2 : 1))) return 0;
    weapon = DK_WeaponId(item->classname);
    if (weapon && weapon != DK_W_SWORD && weapon != DK_W_FLASHLIGHT && weapon != DK_W_GASHANDS) {
        if (!((unsigned int)actor->dk.inventory & (1u << weapon))) return 300;
        if (actor->dk.ammunition[weapon] < dk_weapons[weapon].ammoMax) return 60;
    }
    for (i = 0; i < ARRAY_LEN(ammunition); ++i)
        if (!strcmp(item->classname, ammunition[i].classname) && actor->dk.ammunition[ammunition[i].weapon] < dk_weapons[ammunition[i].weapon].ammoMax) return 50;
    if (!strncmp(item->classname, "item_health_", 12) && actor->health < actor->dk.maxHealth) return 400 - actor->health;
    if (strstr(item->classname, "_armor") && actor->dk.armor < 100) return 100;
    return 0;
}

qboolean DK_CompanionPickup(gentity_t *actor, gentity_t *item) {
    int i, weapon, amount = item->count;
    if (!DK_CompanionItemValue(actor, item)) return qfalse;
    weapon = DK_WeaponId(item->classname);
    if (weapon) AddWeapon(&actor->dk.inventory, actor->dk.ammunition, &actor->s.weapon, weapon,
                          amount > 0 ? amount : dk_weapons[weapon].initialAmmo);
    else if (!strncmp(item->classname, "item_health_", 12)) {
        actor->health += amount > 0 ? amount : atoi(item->classname + 12);
        if (actor->health > actor->dk.maxHealth) actor->health = actor->dk.maxHealth;
    } else if (strstr(item->classname, "_armor")) actor->dk.armor = amount > 0 ? amount : 100;
    else for (i = 0; i < ARRAY_LEN(ammunition); ++i) if (!strcmp(item->classname, ammunition[i].classname)) {
        weapon = ammunition[i].weapon;
        actor->dk.ammunition[weapon] += amount > 0 ? amount : dk_weapons[weapon].initialAmmo;
        if (actor->dk.ammunition[weapon] > dk_weapons[weapon].ammoMax) actor->dk.ammunition[weapon] = dk_weapons[weapon].ammoMax;
        break;
    }
    Taken(item, actor);
    return qtrue;
}
