/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_weapons.h"
#include "dk_inventory.h"
#include "../qcommon/qfiles.h"

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

static void ArmorInfo(const char *name, int *capacity, int *absorption) {
    static const struct { const char *name; int capacity, absorption; } armor[] = {
        {"plasteel", 200, 75}, {"chromatic", 100, 50}, {"silver", 150, 65},
        {"gold", 200, 75}, {"chainmail", 125, 50}, {"black_adamant", 250, 80},
        {"kevlar", 100, 40}, {"ebonite", 200, 75}, {"megashield", 400, 75}
    };
    int i;
    *capacity = 100; *absorption = 50;
    for (i = 0; i < ARRAY_LEN(armor); ++i) if (strstr(name, armor[i].name)) {
        *capacity = armor[i].capacity; *absorption = armor[i].absorption; return;
    }
}

static qboolean Give(gentity_t *item, gentity_t *player) {
    playerState_t *ps = &player->client->ps;
    const char *name = item->classname;
    int i, weapon = DK_WeaponId(name), amount = item->count;
    if (weapon) return DK_GiveWeapon(player, weapon, amount > 0 ? amount : dk_weapons[weapon].initialAmmo);
    weapon = DK_AmmoWeapon(name);
    if (weapon) return DK_AddAmmunition(ps->ammo, weapon, amount);
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
        int capacity, absorption;
        ArmorInfo(name, &capacity, &absorption);
        amount = amount > 0 ? amount : capacity;
        if (ps->stats[STAT_ARMOR] >= amount && ps->dk3ArmorAbsorption >= absorption) return qfalse;
        ps->stats[STAT_ARMOR] = amount;
        ps->dk3ArmorAbsorption = absorption;
        return qtrue;
    }
    if (!strcmp(name, "item_antidote")) {
        player->dk.status = 0;
        ps->dk3Status &= ~7;
        return qtrue;
    }
    if (!strcmp(name, "item_invincibility")) { ps->dk3InvincibleUntil = level.time + 30000; return qtrue; }
    if (!strcmp(name, "item_wraithorb")) { ps->powerups[PW_INVIS] = level.time + 60000; return qtrue; }
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
    if (g_gametype.integer != GT_SINGLE_PLAYER && strcmp(name, "item_savegem")) {
        int delay = strstr(name, "_boost") || !strcmp(name, "item_goldensoul") ? 60000 :
            !strcmp(name, "item_wraithorb") || !strcmp(name, "item_megashield") || !strcmp(name, "item_invincibility") ? 300000 : 30000;
        item->think = Respawn; item->nextthink = level.time + delay;
    }
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

/* Match the supplied mesh for floor collision, so small ammunition does not
   hang against a neighbouring ledge through an oversized generic hull. */
static void ItemFloorBounds(gentity_t *item) {
    md3Header_t header;
    md3Frame_t frame;
    fileHandle_t file;
    char path[MAX_QPATH];
    int length, offset, axis;
    if (!item->model || Q_stricmp(COM_GetExtension(item->model), "dkm")) return;
    Com_sprintf(path, sizeof(path), "%s.md3", item->model);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < sizeof(header)) { if (file) trap_FS_FCloseFile(file); return; }
    trap_FS_Read(&header, sizeof(header), file);
    offset = LittleLong(header.ofsFrames);
    if (LittleLong(header.ident) == MD3_IDENT && LittleLong(header.numFrames) > 0 &&
        offset >= sizeof(header) && offset <= length - (int)sizeof(frame)) {
        trap_FS_Seek(file, offset, FS_SEEK_SET);
        trap_FS_Read(&frame, sizeof(frame), file);
        for (axis = 0; axis < 3; ++axis) {
            float lower = LittleFloat(frame.bounds[0][axis]), upper = LittleFloat(frame.bounds[1][axis]);
            if (Q_isnan(lower) || Q_isnan(upper) || lower < -256 || upper > 256 || lower > upper) break;
        }
        if (axis == 3) for (axis = 0; axis < 3; ++axis) {
            item->r.mins[axis] = LittleFloat(frame.bounds[0][axis]);
            item->r.maxs[axis] = LittleFloat(frame.bounds[1][axis]);
        }
    }
    trap_FS_FCloseFile(file);
}

static void ItemGravity(gentity_t *item) {
    item->physicsObject = qtrue;
    item->physicsBounce = 0.2f;
    item->clipmask = MASK_SOLID;
    item->s.groundEntityNum = ENTITYNUM_NONE;
    item->s.pos.trType = TR_GRAVITY;
    item->s.pos.trTime = level.time;
}

qboolean DK_SpawnItem(gentity_t *item) {
    if (!strcmp(item->classname, "item_vitality_boost")) item->classname = "item_vita_boost";
    int weapon = DK_WeaponId(item->classname), i;
    qboolean supported = weapon != 0 || KeyIndex(item->classname) >= 0;
    const char *name = item->classname;
    if (DK_AmmoWeapon(name)) supported = qtrue;
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
    ItemFloorBounds(item);
    ItemGravity(item);
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

void DK_AwardExperience(gentity_t *player, int amount, int swordAmount) {
    playerState_t *ps;
    if (!player || (amount <= 0 && swordAmount <= 0)) return;
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
    if (swordAmount > 0) ps->dk3SwordExperience += swordAmount;
    while (ps->dk3Level < 25 && ps->dk3Experience >= DK_ExperienceThreshold(ps->dk3Level)) {
        ++ps->dk3Level;
        ++ps->dk3AttributePoints;
        trap_SendServerCommand(player->s.number, "cp \"Level gained. Use attribute <power|attack|speed|acro|vita> to improve a skill.\"");
    }
}

void DK_RestoreItem(gentity_t *ent) {
    DK_RestoreWeaponItem(ent);
    ItemFloorBounds(ent);
    if ((ent->r.contents & CONTENTS_TRIGGER) && !ent->physicsObject) {
        G_SetOrigin(ent, ent->r.currentOrigin);
        ItemGravity(ent);
    }
    ent->touch = ItemTouch;
    ent->think = ent->dk.expires ? G_FreeEntity : ent->nextthink > 0 ? Respawn : NULL;
}

float DK_CompanionItemValue(gentity_t *actor, gentity_t *item) {
    int i, weapon;
    qboolean mikiko = strstr(actor->classname, "mikiko") && !strstr(actor->classname, "mikikofly");
    if (!item->inuse || item->s.eType != ET_DK3_ITEM || !(item->r.contents & CONTENTS_TRIGGER)) return 0;
    if ((item->spawnflags & 3) && !(item->spawnflags & (mikiko ? 2 : 1))) return 0;
    weapon = DK_WeaponId(item->classname);
    if (weapon) return DK_CompanionWeaponValue(actor, weapon);
    weapon = DK_AmmoWeapon(item->classname);
    if (weapon && actor->dk.ammunition[weapon] < dk_weapons[weapon].ammoMax) return 50;
    if (!strncmp(item->classname, "item_health_", 12) && actor->health < actor->dk.maxHealth) return 400 - actor->health;
    if (strstr(item->classname, "_armor")) {
        int capacity, absorption;
        ArmorInfo(item->classname, &capacity, &absorption);
        if (actor->dk.armor < capacity || actor->dk.armorAbsorption < absorption) return 100;
    }
    return 0;
}

qboolean DK_CompanionPickup(gentity_t *actor, gentity_t *item) {
    int i, weapon, amount = item->count;
    if (!DK_CompanionItemValue(actor, item)) return qfalse;
    weapon = DK_WeaponId(item->classname);
    if (weapon) DK_AddWeapon(&actor->dk.inventory, actor->dk.ammunition, &actor->s.weapon, weapon,
                          amount > 0 ? amount : dk_weapons[weapon].initialAmmo);
    else if (!strncmp(item->classname, "item_health_", 12)) {
        actor->health += amount > 0 ? amount : atoi(item->classname + 12);
        if (actor->health > actor->dk.maxHealth) actor->health = actor->dk.maxHealth;
    } else if (strstr(item->classname, "_armor")) {
        int capacity;
        ArmorInfo(item->classname, &capacity, &actor->dk.armorAbsorption);
        actor->dk.armor = amount > 0 ? amount : capacity;
    }
    else { weapon = DK_AmmoWeapon(item->classname); if (weapon) DK_AddAmmunition(actor->dk.ammunition, weapon, amount); }
    Taken(item, actor);
    return qtrue;
}
