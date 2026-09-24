/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "g_local.h"
#include "dk_save_schema.h"
#include <limits.h>

const dkSaveMember_t dk_entityMembers[] = {
    {"dk_monsterattack", DK_SAVE_INT, offsetof(gentity_t, dk.monsterAttack), 1, qfalse},
    {"dk_moveraccel", DK_SAVE_INT, offsetof(gentity_t, dk.moverAccel), 1, qfalse},
    {"dk_moverbounce", DK_SAVE_INT, offsetof(gentity_t, dk.moverBounce), 1, qfalse},
    {"dk_moverdust", DK_SAVE_INT, offsetof(gentity_t, dk.moverDust), 1, qfalse},
    {"dk_moverquake", DK_SAVE_INT, offsetof(gentity_t, dk.moverQuake), 1, qfalse},
    {"dk_movermass", DK_SAVE_FLOAT, offsetof(gentity_t, dk.moverMass), 1, qfalse},

    {"dk_combathitbits", DK_SAVE_INT, offsetof(gentity_t, dk.combatHitBits), MAX_GENTITIES / 32, qfalse},
    {"dk_lightstyle", DK_SAVE_INT, offsetof(gentity_t, dk.lightStyle), 1, qfalse},
    {"s_number", DK_SAVE_INT, offsetof(gentity_t, s.number), 1, qfalse},
    {"neverfree", DK_SAVE_INT, offsetof(gentity_t, neverFree), 1, qfalse},
    {"soundpos1", DK_SAVE_INT, offsetof(gentity_t, soundPos1), 1, qfalse},
    {"sound1to2", DK_SAVE_INT, offsetof(gentity_t, sound1to2), 1, qfalse},
    {"sound2to1", DK_SAVE_INT, offsetof(gentity_t, sound2to1), 1, qfalse},
    {"soundpos2", DK_SAVE_INT, offsetof(gentity_t, soundPos2), 1, qfalse},
    {"soundloop", DK_SAVE_INT, offsetof(gentity_t, soundLoop), 1, qfalse},
    {"noise_index", DK_SAVE_INT, offsetof(gentity_t, noise_index), 1, qfalse},
    {"methodofdeath", DK_SAVE_INT, offsetof(gentity_t, methodOfDeath), 1, qfalse},
    {"splashmethodofdeath", DK_SAVE_INT, offsetof(gentity_t, splashMethodOfDeath), 1, qfalse},
    {"spawnflags", DK_SAVE_INT, offsetof(gentity_t, spawnflags), 1, qfalse},
    {"flags", DK_SAVE_INT, offsetof(gentity_t, flags), 1, qfalse},
    {"health", DK_SAVE_INT, offsetof(gentity_t, health), 1, qfalse},
    {"takedamage", DK_SAVE_INT, offsetof(gentity_t, takedamage), 1, qfalse},
    {"damage", DK_SAVE_INT, offsetof(gentity_t, damage), 1, qfalse},
    {"splashdamage", DK_SAVE_INT, offsetof(gentity_t, splashDamage), 1, qfalse},
    {"splashradius", DK_SAVE_INT, offsetof(gentity_t, splashRadius), 1, qfalse},
    {"count", DK_SAVE_INT, offsetof(gentity_t, count), 1, qfalse},
    {"clipmask", DK_SAVE_INT, offsetof(gentity_t, clipmask), 1, qfalse},
    {"moverstate", DK_SAVE_INT, offsetof(gentity_t, moverState), 1, qfalse},
    {"physicsobject", DK_SAVE_INT, offsetof(gentity_t, physicsObject), 1, qfalse},
    {"watertype", DK_SAVE_INT, offsetof(gentity_t, watertype), 1, qfalse},
    {"waterlevel", DK_SAVE_INT, offsetof(gentity_t, waterlevel), 1, qfalse},
    {"s_dk3team", DK_SAVE_INT, offsetof(gentity_t, s.dk3Team), 1, qfalse},
    {"s_dk3carrier", DK_SAVE_INT, offsetof(gentity_t, s.dk3Carrier), 1, qfalse},
    {"s_dk3soundvolume", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3SoundVolume), 1, qfalse},
    {"s_dk3soundmin", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3SoundMin), 1, qfalse},
    {"s_dk3soundmax", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3SoundMax), 1, qfalse},
    {"s_dk3soundflags", DK_SAVE_INT, offsetof(gentity_t, s.dk3SoundFlags), 1, qfalse},
    {"dk_environmentstyle", DK_SAVE_INT, offsetof(gentity_t, dk.environmentStyle), 1, qfalse},
    {"dk_environmentreverb", DK_SAVE_FLOAT, offsetof(gentity_t, dk.environmentReverb), 1, qfalse},
    {"dk_environmentgain", DK_SAVE_FLOAT, offsetof(gentity_t, dk.environmentGain), 1, qfalse},
    {"s_modelindex", DK_SAVE_INT, offsetof(gentity_t, s.modelindex), 1, qfalse},
    {"s_modelindex2", DK_SAVE_INT, offsetof(gentity_t, s.modelindex2), 1, qfalse},
    {"s_loopsound", DK_SAVE_INT, offsetof(gentity_t, s.loopSound), 1, qfalse},
    {"s_etype", DK_SAVE_INT, offsetof(gentity_t, s.eType), 1, qfalse},
    {"s_eflags", DK_SAVE_INT, offsetof(gentity_t, s.eFlags), 1, qfalse},
    {"s_weapon", DK_SAVE_INT, offsetof(gentity_t, s.weapon), 1, qfalse},
    {"s_dk3effect", DK_SAVE_INT, offsetof(gentity_t, s.dk3Effect), 1, qfalse},
    {"s_dk3effectflags", DK_SAVE_INT, offsetof(gentity_t, s.dk3EffectFlags), 1, qfalse},
    {"s_dk3effectstart", DK_SAVE_INT, offsetof(gentity_t, s.dk3EffectStart), 1, qtrue},
    {"s_dk3effectduration", DK_SAVE_INT, offsetof(gentity_t, s.dk3EffectDuration), 1, qfalse},
    {"s_dk3effectrate", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3EffectRate), 1, qfalse},
    {"s_dk3effectspeed", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3EffectSpeed), 1, qfalse},
    {"s_dk3effectspread", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3EffectSpread), 1, qfalse},
    {"s_dk3effectradius", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3EffectRadius), 1, qfalse},
    {"s_dk3effectcolor", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3EffectColor), 3, qfalse},
    {"s_dk3effectmins", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3EffectMins), 3, qfalse},
    {"s_dk3effectmaxs", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3EffectMaxs), 3, qfalse},
    {"s_dk3effectend", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3EffectEnd), 3, qfalse},
    {"s_dk3effectgravity", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3EffectGravity), 3, qfalse},
    {"s_constantlight", DK_SAVE_INT, offsetof(gentity_t, s.constantLight), 1, qfalse},
    {"s_frame", DK_SAVE_INT, offsetof(gentity_t, s.frame), 1, qfalse},
    {"s_solid", DK_SAVE_INT, offsetof(gentity_t, s.solid), 1, qfalse},
    {"r_contents", DK_SAVE_INT, offsetof(gentity_t, r.contents), 1, qfalse},
    {"r_svflags", DK_SAVE_INT, offsetof(gentity_t, r.svFlags), 1, qfalse},
    {"r_bmodel", DK_SAVE_INT, offsetof(gentity_t, r.bmodel), 1, qfalse},
    {"r_linked", DK_SAVE_INT, offsetof(gentity_t, r.linked), 1, qfalse},
    {"s_pos_trtype", DK_SAVE_INT, offsetof(gentity_t, s.pos.trType), 1, qfalse},
    {"s_pos_trduration", DK_SAVE_INT, offsetof(gentity_t, s.pos.trDuration), 1, qfalse},
    {"s_apos_trtype", DK_SAVE_INT, offsetof(gentity_t, s.apos.trType), 1, qfalse},
    {"s_apos_trduration", DK_SAVE_INT, offsetof(gentity_t, s.apos.trDuration), 1, qfalse},
    {"nextthink", DK_SAVE_INT, offsetof(gentity_t, nextthink), 1, qtrue},
    {"pain_debounce_time", DK_SAVE_INT, offsetof(gentity_t, pain_debounce_time), 1, qtrue},
    {"last_move_time", DK_SAVE_INT, offsetof(gentity_t, last_move_time), 1, qtrue},
    {"timestamp", DK_SAVE_INT, offsetof(gentity_t, timestamp), 1, qtrue},
    {"s_pos_trtime", DK_SAVE_INT, offsetof(gentity_t, s.pos.trTime), 1, qtrue},
    {"s_apos_trtime", DK_SAVE_INT, offsetof(gentity_t, s.apos.trTime), 1, qtrue},
    {"s_time", DK_SAVE_INT, offsetof(gentity_t, s.time), 1, qtrue},
    {"s_time2", DK_SAVE_INT, offsetof(gentity_t, s.time2), 1, qtrue},
    {"speed", DK_SAVE_FLOAT, offsetof(gentity_t, speed), 1, qfalse},
    {"wait", DK_SAVE_FLOAT, offsetof(gentity_t, wait), 1, qfalse},
    {"random", DK_SAVE_FLOAT, offsetof(gentity_t, random), 1, qfalse},
    {"physicsbounce", DK_SAVE_FLOAT, offsetof(gentity_t, physicsBounce), 1, qfalse},
    {"s_origin", DK_SAVE_FLOAT, offsetof(gentity_t, s.origin), 3, qfalse},
    {"s_angles", DK_SAVE_FLOAT, offsetof(gentity_t, s.angles), 3, qfalse},
    {"s_origin2", DK_SAVE_FLOAT, offsetof(gentity_t, s.origin2), 3, qfalse},
    {"s_angles2", DK_SAVE_FLOAT, offsetof(gentity_t, s.angles2), 3, qfalse},
    {"r_currentorigin", DK_SAVE_FLOAT, offsetof(gentity_t, r.currentOrigin), 3, qfalse},
    {"r_currentangles", DK_SAVE_FLOAT, offsetof(gentity_t, r.currentAngles), 3, qfalse},
    {"r_mins", DK_SAVE_FLOAT, offsetof(gentity_t, r.mins), 3, qfalse},
    {"r_maxs", DK_SAVE_FLOAT, offsetof(gentity_t, r.maxs), 3, qfalse},
    {"pos1", DK_SAVE_FLOAT, offsetof(gentity_t, pos1), 3, qfalse},
    {"pos2", DK_SAVE_FLOAT, offsetof(gentity_t, pos2), 3, qfalse},
    {"movedir", DK_SAVE_FLOAT, offsetof(gentity_t, movedir), 3, qfalse},
    {"s_pos_trbase", DK_SAVE_FLOAT, offsetof(gentity_t, s.pos.trBase), 3, qfalse},
    {"s_pos_trdelta", DK_SAVE_FLOAT, offsetof(gentity_t, s.pos.trDelta), 3, qfalse},
    {"s_apos_trbase", DK_SAVE_FLOAT, offsetof(gentity_t, s.apos.trBase), 3, qfalse},
    {"s_apos_trdelta", DK_SAVE_FLOAT, offsetof(gentity_t, s.apos.trDelta), 3, qfalse},
    {"classname", DK_SAVE_TEXT, offsetof(gentity_t, classname), 1, qfalse},
    {"model", DK_SAVE_TEXT, offsetof(gentity_t, model), 1, qfalse},
    {"model2", DK_SAVE_TEXT, offsetof(gentity_t, model2), 1, qfalse},
    {"message", DK_SAVE_TEXT, offsetof(gentity_t, message), 1, qfalse},
    {"target", DK_SAVE_TEXT, offsetof(gentity_t, target), 1, qfalse},
    {"targetname", DK_SAVE_TEXT, offsetof(gentity_t, targetname), 1, qfalse},
    {"team", DK_SAVE_TEXT, offsetof(gentity_t, team), 1, qfalse},
    {"targetshadername", DK_SAVE_TEXT, offsetof(gentity_t, targetShaderName), 1, qfalse},
    {"targetshadernewname", DK_SAVE_TEXT, offsetof(gentity_t, targetShaderNewName), 1, qfalse},
    {"dk_killtarget", DK_SAVE_TEXT, offsetof(gentity_t, dk.killtarget), 1, qfalse},
    {"dk_map", DK_SAVE_TEXT, offsetof(gentity_t, dk.map), 1, qfalse},
    {"dk_targets_0", DK_SAVE_TEXT, offsetof(gentity_t, dk.targets[0]), 1, qfalse},
    {"dk_targets_1", DK_SAVE_TEXT, offsetof(gentity_t, dk.targets[1]), 1, qfalse},
    {"dk_targets_2", DK_SAVE_TEXT, offsetof(gentity_t, dk.targets[2]), 1, qfalse},
    {"dk_uniqueid", DK_SAVE_TEXT, offsetof(gentity_t, dk.uniqueid), 1, qfalse},
    {"dk_key", DK_SAVE_TEXT, offsetof(gentity_t, dk.key), 1, qfalse},
    {"dk_parenttarget", DK_SAVE_TEXT, offsetof(gentity_t, dk.parentTarget), 1, qfalse},
    {"dk_parentid", DK_SAVE_INT, offsetof(gentity_t, dk.parentId), 1, qfalse},
    {"dk_monitorid", DK_SAVE_INT, offsetof(gentity_t, dk.monitorId), 1, qfalse},
    {"dk_monitorstart", DK_SAVE_INT, offsetof(gentity_t, dk.monitorStart), 1, qtrue},
    {"dk_monitorunlock", DK_SAVE_INT, offsetof(gentity_t, dk.monitorUnlock), 1, qtrue},
    {"dk_camerafov", DK_SAVE_FLOAT, offsetof(gentity_t, dk.cameraFov), 1, qfalse},
    {"dk_delay", DK_SAVE_INT, offsetof(gentity_t, dk.delay), 1, qfalse},
    {"dk_nextuse", DK_SAVE_INT, offsetof(gentity_t, dk.nextUse), 1, qtrue},
    {"dk_uses", DK_SAVE_INT, offsetof(gentity_t, dk.uses), 1, qfalse},
    {"dk_decorkind", DK_SAVE_INT, offsetof(gentity_t, dk.decorKind), 1, qfalse},
    {"dk_objectmove", DK_SAVE_INT, offsetof(gentity_t, dk.objectMove), 1, qfalse},
    {"dk_animationloop", DK_SAVE_INT, offsetof(gentity_t, dk.animationLoop), 1, qfalse},
    {"dk_supply", DK_SAVE_INT, offsetof(gentity_t, dk.supply), 1, qfalse},
    {"dk_supplymaximum", DK_SAVE_INT, offsetof(gentity_t, dk.supplyMaximum), 1, qfalse},
    {"dk_recharge", DK_SAVE_INT, offsetof(gentity_t, dk.recharge), 1, qfalse},
    {"dk_rechargetime", DK_SAVE_INT, offsetof(gentity_t, dk.rechargeTime), 1, qtrue},
    {"s_dk3scale", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3Scale), 1, qfalse},
    {"s_dk3alpha", DK_SAVE_FLOAT, offsetof(gentity_t, s.dk3Alpha), 1, qfalse},
    {"s_dk3renderflags", DK_SAVE_INT, offsetof(gentity_t, s.dk3RenderFlags), 1, qfalse},
    {"dk_mediapath", DK_SAVE_TEXT, offsetof(gentity_t, dk.mediaPath), 1, qfalse},
    {"dk_soundindices", DK_SAVE_INT, offsetof(gentity_t, dk.soundIndices), 7, qfalse},
    {"dk_soundcount", DK_SAVE_INT, offsetof(gentity_t, dk.soundCount), 1, qfalse},
    {"dk_soundenabled", DK_SAVE_INT, offsetof(gentity_t, dk.soundEnabled), 1, qfalse},
    {"dk_sounddelay", DK_SAVE_INT, offsetof(gentity_t, dk.soundDelay), 1, qfalse},
    {"dk_soundminimum", DK_SAVE_INT, offsetof(gentity_t, dk.soundMinimum), 1, qfalse},
    {"dk_soundrandom", DK_SAVE_INT, offsetof(gentity_t, dk.soundRandom), 1, qfalse},
    {"dk_effectactive", DK_SAVE_INT, offsetof(gentity_t, dk.effectActive), 1, qfalse},
    {"dk_effectontime", DK_SAVE_INT, offsetof(gentity_t, dk.effectOnTime), 1, qfalse},
    {"dk_effectofftime", DK_SAVE_INT, offsetof(gentity_t, dk.effectOffTime), 1, qfalse},
    {"dk_effectstoptime", DK_SAVE_INT, offsetof(gentity_t, dk.effectStopTime), 1, qfalse},
    {"dk_effectnextcycle", DK_SAVE_INT, offsetof(gentity_t, dk.effectNextCycle), 1, qtrue},
    {"dk_effectchance", DK_SAVE_FLOAT, offsetof(gentity_t, dk.effectChance), 1, qfalse},
    {"dk_effectgroundchance", DK_SAVE_FLOAT, offsetof(gentity_t, dk.effectGroundChance), 1, qfalse},
    {"dk_moverkind", DK_SAVE_INT, offsetof(gentity_t, dk.moverKind), 1, qfalse},
    {"dk_moverangular", DK_SAVE_INT, offsetof(gentity_t, dk.moverAngular), 1, qfalse},
    {"dk_moverpaused", DK_SAVE_INT, offsetof(gentity_t, dk.moverPaused), 1, qfalse},
    {"dk_moverarrival", DK_SAVE_INT, offsetof(gentity_t, dk.moverArrival), 1, qfalse},
    {"dk_moverinitialized", DK_SAVE_INT, offsetof(gentity_t, dk.moverInitialized), 1, qfalse},
    {"dk_forcemove", DK_SAVE_INT, offsetof(gentity_t, dk.forceMove), 1, qfalse},
    {"dk_rotationdelta", DK_SAVE_FLOAT, offsetof(gentity_t, dk.rotationDelta), 3, qfalse},
    {"dk_rotationrate", DK_SAVE_FLOAT, offsetof(gentity_t, dk.rotationRate), 3, qfalse},
    {"dk_secretend", DK_SAVE_FLOAT, offsetof(gentity_t, dk.secretEnd), 3, qfalse},
    {"dk_groundedflight", DK_SAVE_INT, offsetof(gentity_t, dk.groundedFlight), 1, qfalse},
    {"dk_actorkind", DK_SAVE_INT, offsetof(gentity_t, dk.actorKind), 1, qfalse},
    {"dk_action", DK_SAVE_INT, offsetof(gentity_t, dk.action), 1, qfalse},
    {"dk_actiontime", DK_SAVE_INT, offsetof(gentity_t, dk.actionTime), 1, qtrue},
    {"dk_destinationid", DK_SAVE_INT, offsetof(gentity_t, dk.destinationId), 1, qfalse},
    {"dk_firstframe", DK_SAVE_INT, offsetof(gentity_t, dk.firstFrame), 1, qfalse},
    {"dk_lastframe", DK_SAVE_INT, offsetof(gentity_t, dk.lastFrame), 1, qfalse},
    {"dk_animationtime", DK_SAVE_INT, offsetof(gentity_t, dk.animationTime), 1, qtrue},
    {"dk_inventory", DK_SAVE_INT, offsetof(gentity_t, dk.inventory), 1, qfalse},
    {"dk_ammunition", DK_SAVE_INT, offsetof(gentity_t, dk.ammunition), 32, qfalse},
    {"dk_armorabsorption", DK_SAVE_INT, offsetof(gentity_t, dk.armorAbsorption), 1, qfalse},
    {"dk_armor", DK_SAVE_INT, offsetof(gentity_t, dk.armor), 1, qfalse},
    {"dk_attributes", DK_SAVE_INT, offsetof(gentity_t, dk.attributes), 5, qfalse},
    {"dk_actorlevel", DK_SAVE_INT, offsetof(gentity_t, dk.actorLevel), 1, qfalse},
    {"dk_maxhealth", DK_SAVE_INT, offsetof(gentity_t, dk.maxHealth), 1, qfalse},
    {"dk_companionorder", DK_SAVE_INT, offsetof(gentity_t, dk.companionOrder), 1, qfalse},
    {"dk_companionenabled", DK_SAVE_INT, offsetof(gentity_t, dk.companionEnabled), 1, qfalse},
    {"dk_pickupid", DK_SAVE_INT, offsetof(gentity_t, dk.pickupId), 1, qfalse},
    {"dk_pickupretry", DK_SAVE_INT, offsetof(gentity_t, dk.pickupRetry), 1, qtrue},
    {"dk_companionname", DK_SAVE_TEXT, offsetof(gentity_t, dk.companionName), 1, qfalse},
    {"dk_triggeranimation", DK_SAVE_TEXT, offsetof(gentity_t, dk.triggerAnimation), 1, qfalse},
    {"dk_triggertoggle", DK_SAVE_INT, offsetof(gentity_t, dk.triggerToggle), 1, qfalse},
    {"dk_triggerdestination", DK_SAVE_FLOAT, offsetof(gentity_t, dk.triggerDestination), 3, qfalse},
    {"dk_experience", DK_SAVE_INT, offsetof(gentity_t, dk.experience), 1, qfalse},
    {"dk_animationindex", DK_SAVE_INT, offsetof(gentity_t, dk.animationIndex), 1, qfalse},
    {"dk_animationcursor", DK_SAVE_INT, offsetof(gentity_t, dk.animationCursor), 1, qfalse},
    {"dk_actorrandom", DK_SAVE_INT, offsetof(gentity_t, dk.actorRandom), 1, qfalse},
    {"dk_attackgroup", DK_SAVE_INT, offsetof(gentity_t, dk.attackGroup), 1, qfalse},
    {"dk_lastseentime", DK_SAVE_INT, offsetof(gentity_t, dk.lastSeenTime), 1, qtrue},
    {"dk_abilitystate", DK_SAVE_INT, offsetof(gentity_t, dk.abilityState), 1, qfalse},
    {"dk_abilitytime", DK_SAVE_INT, offsetof(gentity_t, dk.abilityTime), 1, qtrue},
    {"dk_abilitycharges", DK_SAVE_INT, offsetof(gentity_t, dk.abilityCharges), 1, qfalse},
    {"dk_turretframes", DK_SAVE_INT, offsetof(gentity_t, dk.turretFrames), 1, qfalse},
    {"dk_turretenabled", DK_SAVE_INT, offsetof(gentity_t, dk.turretEnabled), 1, qfalse},
    {"dk_lastseenorigin", DK_SAVE_FLOAT, offsetof(gentity_t, dk.lastSeenOrigin), 3, qfalse},
    {"dk_actorvelocity", DK_SAVE_FLOAT, offsetof(gentity_t, dk.actorVelocity), 3, qfalse},
    {"dk_roamgoal", DK_SAVE_FLOAT, offsetof(gentity_t, dk.roamGoal), 3, qfalse},
    {"dk_roamuntil", DK_SAVE_INT, offsetof(gentity_t, dk.roamUntil), 1, qtrue},
    {"dk_animationrate", DK_SAVE_INT, offsetof(gentity_t, dk.animationRate), 1, qfalse},
    {"dk_scriptuntil", DK_SAVE_INT, offsetof(gentity_t, dk.scriptUntil), 1, qtrue},
    {"dk_ignoreplayer", DK_SAVE_INT, offsetof(gentity_t, dk.ignorePlayer), 1, qfalse},
    {"dk_blockedsince", DK_SAVE_INT, offsetof(gentity_t, dk.blockedSince), 1, qtrue},
    {"dk_yielduntil", DK_SAVE_INT, offsetof(gentity_t, dk.yieldUntil), 1, qtrue},
    {"dk_pathtarget", DK_SAVE_TEXT, offsetof(gentity_t, dk.pathTarget), 1, qfalse},
    {"dk_movinganimation", DK_SAVE_TEXT, offsetof(gentity_t, dk.movingAnimation), 1, qfalse},
    {"dk_aiscript", DK_SAVE_TEXT, offsetof(gentity_t, dk.aiScript), 1, qfalse},
    {"dk_deathtarget", DK_SAVE_TEXT, offsetof(gentity_t, dk.deathTarget), 1, qfalse},
    {"dk_deathspawn", DK_SAVE_TEXT, offsetof(gentity_t, dk.deathSpawn), 1, qfalse},
    {"dk_spawnclass", DK_SAVE_TEXT, offsetof(gentity_t, dk.spawnClass), 1, qfalse},
    {"dk_spawnid", DK_SAVE_TEXT, offsetof(gentity_t, dk.spawnId), 1, qfalse},
    {"dk_cinescript", DK_SAVE_TEXT, offsetof(gentity_t, dk.cineScript), 1, qfalse},
    {"dk_cinekill", DK_SAVE_TEXT, offsetof(gentity_t, dk.cineKill), 1, qfalse},
    {"dk_cinetrigger", DK_SAVE_TEXT, offsetof(gentity_t, dk.cineTrigger), 1, qfalse},
    {"dk_cinematicowned", DK_SAVE_INT, offsetof(gentity_t, dk.cinematicOwned), 1, qfalse},
    {"dk_cinematiccontrolled", DK_SAVE_INT, offsetof(gentity_t, dk.cinematicControlled), 1, qfalse},
    {"dk_moveactive", DK_SAVE_INT, offsetof(gentity_t, dk.moveActive), 1, qfalse},
    {"dk_movegoal", DK_SAVE_FLOAT, offsetof(gentity_t, dk.moveGoal), 3, qfalse},
    {"dk_speedoverride", DK_SAVE_FLOAT, offsetof(gentity_t, dk.speedOverride), 1, qfalse},
    {"dk_savedspeed", DK_SAVE_FLOAT, offsetof(gentity_t, dk.savedSpeed), 1, qfalse},
    {"dk_walkspeed", DK_SAVE_FLOAT, offsetof(gentity_t, dk.walkSpeed), 1, qfalse},
    {"dk_runspeed", DK_SAVE_FLOAT, offsetof(gentity_t, dk.runSpeed), 1, qfalse},
    {"dk_yawspeed", DK_SAVE_FLOAT, offsetof(gentity_t, dk.yawSpeed), 1, qfalse},
    {"dk_sightrange", DK_SAVE_FLOAT, offsetof(gentity_t, dk.sightRange), 1, qfalse},
    {"dk_attackrange", DK_SAVE_FLOAT, offsetof(gentity_t, dk.attackRange), 1, qfalse},
    {"dk_speakrange", DK_SAVE_FLOAT, offsetof(gentity_t, dk.speakRange), 1, qfalse, qtrue},
    {"dk_evadeuntil", DK_SAVE_INT, offsetof(gentity_t, dk.evadeUntil), 1, qtrue, qtrue},
    {"dk_covertime", DK_SAVE_INT, offsetof(gentity_t, dk.coverTime), 1, qtrue, qtrue},
    {"dk_evadekind", DK_SAVE_INT, offsetof(gentity_t, dk.evadeKind), 1, qfalse, qtrue},
    {"dk_evadegoal", DK_SAVE_FLOAT, offsetof(gentity_t, dk.evadeGoal), 3, qfalse, qtrue},    {"dk_fireinterval", DK_SAVE_INT, offsetof(gentity_t, dk.fireInterval), 1, qfalse},
    {"dk_attackdamage", DK_SAVE_INT, offsetof(gentity_t, dk.attackDamage), 1, qfalse},
    {"dk_attackrandomdamage", DK_SAVE_INT, offsetof(gentity_t, dk.attackRandomDamage), 1, qfalse},
    {"dk_savedwalkspeed", DK_SAVE_FLOAT, offsetof(gentity_t, dk.savedWalkSpeed), 1, qfalse},
    {"dk_savedyawspeed", DK_SAVE_FLOAT, offsetof(gentity_t, dk.savedYawSpeed), 1, qfalse},
    {"dk_turngoal", DK_SAVE_FLOAT, offsetof(gentity_t, dk.turnGoal), 3, qfalse},
    {"dk_turnactive", DK_SAVE_INT, offsetof(gentity_t, dk.turnActive), 1, qfalse},
    {"dk_cinematiccompleted", DK_SAVE_INT, offsetof(gentity_t, dk.cinematicCompleted), 1, qfalse},
    {"dk_eventfirst", DK_SAVE_INT, offsetof(gentity_t, dk.eventFirst), 1, qfalse},
    {"dk_eventcount", DK_SAVE_INT, offsetof(gentity_t, dk.eventCount), 1, qfalse},
    {"dk_eventstart", DK_SAVE_INT, offsetof(gentity_t, dk.eventStart), 1, qtrue},
    {"dk_eventcursor", DK_SAVE_INT, offsetof(gentity_t, dk.eventCursor), 1, qfalse},
    {"dk_ownerid", DK_SAVE_INT, offsetof(gentity_t, dk.ownerId), 1, qfalse},
    {"dk_expires", DK_SAVE_INT, offsetof(gentity_t, dk.expires), 1, qtrue},
    {"dk_combatstate", DK_SAVE_INT, offsetof(gentity_t, dk.combatState), 1, qfalse},
    {"dk_combatcount", DK_SAVE_INT, offsetof(gentity_t, dk.combatCount), 1, qfalse},
    {"dk_combatnext", DK_SAVE_INT, offsetof(gentity_t, dk.combatNext), 1, qtrue},
    {"dk_combatend", DK_SAVE_INT, offsetof(gentity_t, dk.combatEnd), 1, qtrue},
    {"dk_weaponholduntil", DK_SAVE_INT, offsetof(gentity_t, dk.weaponHoldUntil), 1, qtrue, qtrue},
    {"dk_weaponparentid", DK_SAVE_INT, offsetof(gentity_t, dk.weaponParentId), 1, qfalse, qtrue},
    {"dk_poisonend", DK_SAVE_INT, offsetof(gentity_t, dk.poisonEnd), 1, qtrue},
    {"dk_poisonnext", DK_SAVE_INT, offsetof(gentity_t, dk.poisonNext), 1, qtrue},
    {"dk_poisoninterval", DK_SAVE_INT, offsetof(gentity_t, dk.poisonInterval), 1, qfalse},
    {"dk_burnend", DK_SAVE_INT, offsetof(gentity_t, dk.burnEnd), 1, qtrue},
    {"dk_burnnext", DK_SAVE_INT, offsetof(gentity_t, dk.burnNext), 1, qtrue},
    {"dk_freezenext", DK_SAVE_INT, offsetof(gentity_t, dk.freezeNext), 1, qtrue},
    {"dk_freezestart", DK_SAVE_INT, offsetof(gentity_t, dk.freezeStart), 1, qtrue},
    {"dk_healinguser", DK_SAVE_INT, offsetof(gentity_t, dk.healingUser), 1, qfalse},
    {"dk_poisondamage", DK_SAVE_FLOAT, offsetof(gentity_t, dk.poisonDamage), 1, qfalse},
    {"dk_poisonfraction", DK_SAVE_FLOAT, offsetof(gentity_t, dk.poisonFraction), 1, qfalse},
    {"dk_freezelevel", DK_SAVE_FLOAT, offsetof(gentity_t, dk.freezeLevel), 1, qfalse},
    {"dk_combattargets", DK_SAVE_INT, offsetof(gentity_t, dk.combatTargets), 32, qfalse},
    {"dk_launchorigin", DK_SAVE_FLOAT, offsetof(gentity_t, dk.launchOrigin), 3, qfalse},
    {"dk_projectile", DK_SAVE_INT, offsetof(gentity_t, dk.projectile), 1, qfalse},
    {"dk_status", DK_SAVE_INT, offsetof(gentity_t, dk.status), 1, qfalse},
    {"dk_statusexpires", DK_SAVE_INT, offsetof(gentity_t, dk.statusExpires), 1, qtrue},
    {"dk_statustick", DK_SAVE_INT, offsetof(gentity_t, dk.statusTick), 1, qtrue},
    {"dk_statusownerid", DK_SAVE_INT, offsetof(gentity_t, dk.statusOwnerId), 1, qfalse},
};
const int dk_entityMemberCount = ARRAY_LEN(dk_entityMembers);

const dkSaveMember_t dk_playerMembers[] = {
    {"pm_type", DK_SAVE_INT, offsetof(playerState_t, pm_type), 1, qfalse},
    {"pm_flags", DK_SAVE_INT, offsetof(playerState_t, pm_flags), 1, qfalse},
    {"pm_time", DK_SAVE_INT, offsetof(playerState_t, pm_time), 1, qfalse},
    {"bobcycle", DK_SAVE_INT, offsetof(playerState_t, bobCycle), 1, qfalse},
    {"weapontime", DK_SAVE_INT, offsetof(playerState_t, weaponTime), 1, qfalse},
    {"weapon", DK_SAVE_INT, offsetof(playerState_t, weapon), 1, qfalse},
    {"weaponstate", DK_SAVE_INT, offsetof(playerState_t, weaponstate), 1, qfalse},
    {"gravity", DK_SAVE_INT, offsetof(playerState_t, gravity), 1, qfalse},
    {"speed", DK_SAVE_INT, offsetof(playerState_t, speed), 1, qfalse},
    {"groundentitynum", DK_SAVE_INT, offsetof(playerState_t, groundEntityNum), 1, qfalse},
    {"legstimer", DK_SAVE_INT, offsetof(playerState_t, legsTimer), 1, qfalse},
    {"legsanim", DK_SAVE_INT, offsetof(playerState_t, legsAnim), 1, qfalse},
    {"torsotimer", DK_SAVE_INT, offsetof(playerState_t, torsoTimer), 1, qfalse},
    {"torsoanim", DK_SAVE_INT, offsetof(playerState_t, torsoAnim), 1, qfalse},
    {"movementdir", DK_SAVE_INT, offsetof(playerState_t, movementDir), 1, qfalse},
    {"eflags", DK_SAVE_INT, offsetof(playerState_t, eFlags), 1, qfalse},
    {"viewheight", DK_SAVE_INT, offsetof(playerState_t, viewheight), 1, qfalse},
    {"damageevent", DK_SAVE_INT, offsetof(playerState_t, damageEvent), 1, qfalse},
    {"damageyaw", DK_SAVE_INT, offsetof(playerState_t, damageYaw), 1, qfalse},
    {"damagepitch", DK_SAVE_INT, offsetof(playerState_t, damagePitch), 1, qfalse},
    {"damagecount", DK_SAVE_INT, offsetof(playerState_t, damageCount), 1, qfalse},
    {"generic1", DK_SAVE_INT, offsetof(playerState_t, generic1), 1, qfalse},
    {"loopsound", DK_SAVE_INT, offsetof(playerState_t, loopSound), 1, qfalse},
    {"dk3objective", DK_SAVE_INT, offsetof(playerState_t, dk3Objective), 1, qfalse},
    {"dk3objectiveuntil", DK_SAVE_INT, offsetof(playerState_t, dk3ObjectiveUntil), 1, qtrue},
    {"dk3inventory", DK_SAVE_INT, offsetof(playerState_t, dk3Inventory), 1, qfalse},
    {"dk3experience", DK_SAVE_INT, offsetof(playerState_t, dk3Experience), 1, qfalse},
    {"dk3level", DK_SAVE_INT, offsetof(playerState_t, dk3Level), 1, qfalse},
    {"dk3swordexperience", DK_SAVE_INT, offsetof(playerState_t, dk3SwordExperience), 1, qfalse},
    {"dk3quest", DK_SAVE_INT, offsetof(playerState_t, dk3Quest), 1, qfalse},
    {"dk3soundenvironment", DK_SAVE_INT, offsetof(playerState_t, dk3SoundEnvironment), 1, qfalse},
    {"dk3reverb", DK_SAVE_FLOAT, offsetof(playerState_t, dk3Reverb), 1, qfalse},
    {"dk3soundgain", DK_SAVE_FLOAT, offsetof(playerState_t, dk3SoundGain), 1, qfalse},
    {"dk3keys", DK_SAVE_INT, offsetof(playerState_t, dk3Keys), 1, qfalse},
    {"dk3psyend", DK_SAVE_INT, offsetof(playerState_t, dk3PsyEnd), 1, qtrue},
    {"dk3freezelevel", DK_SAVE_FLOAT, offsetof(playerState_t, dk3FreezeLevel), 1, qfalse},
    {"dk3status", DK_SAVE_INT, offsetof(playerState_t, dk3Status), 1, qfalse},
    {"dk3savegems", DK_SAVE_INT, offsetof(playerState_t, dk3SaveGems), 1, qfalse},
    {"dk3attributepoints", DK_SAVE_INT, offsetof(playerState_t, dk3AttributePoints), 1, qfalse},
    {"dk3attackheld", DK_SAVE_INT, offsetof(playerState_t, dk3AttackHeld), 1, qfalse},
    {"dk3burst", DK_SAVE_INT, offsetof(playerState_t, dk3Burst), 1, qfalse},
    {"dk3armorabsorption", DK_SAVE_INT, offsetof(playerState_t, dk3ArmorAbsorption), 1, qfalse},
    {"dk3glockclip", DK_SAVE_INT, offsetof(playerState_t, dk3GlockClip), 1, qfalse},
    {"dk3weaponsequence", DK_SAVE_INT, offsetof(playerState_t, dk3WeaponSequence), 1, qfalse},
    {"dk3novaspent", DK_SAVE_INT, offsetof(playerState_t, dk3NovaSpent), 1, qfalse},
    {"dk3charge", DK_SAVE_INT, offsetof(playerState_t, dk3Charge), 1, qfalse},
    {"dk3cameraactive", DK_SAVE_INT, offsetof(playerState_t, dk3CameraActive), 1, qfalse},
    {"origin", DK_SAVE_FLOAT, offsetof(playerState_t, origin), 3, qfalse},
    {"velocity", DK_SAVE_FLOAT, offsetof(playerState_t, velocity), 3, qfalse},
    {"viewangles", DK_SAVE_FLOAT, offsetof(playerState_t, viewangles), 3, qfalse},
    {"delta_angles", DK_SAVE_INT, offsetof(playerState_t, delta_angles), 3, qfalse},
    {"stats", DK_SAVE_INT, offsetof(playerState_t, stats), MAX_STATS, qfalse},
    {"persistant", DK_SAVE_INT, offsetof(playerState_t, persistant), MAX_PERSISTANT, qfalse},
    {"ammo", DK_SAVE_INT, offsetof(playerState_t, ammo), MAX_WEAPONS, qfalse},
    {"powerups", DK_SAVE_INT, offsetof(playerState_t, powerups), MAX_POWERUPS, qtrue},
    {"dk3attributes", DK_SAVE_INT, offsetof(playerState_t, dk3Attributes), 5, qfalse},
    {"dk3boostuntil", DK_SAVE_INT, offsetof(playerState_t, dk3BoostUntil), 5, qtrue},
    {"dk3episode", DK_SAVE_INT, offsetof(playerState_t, dk3Episode), 1, qfalse},
    {"dk3invincibleuntil", DK_SAVE_INT, offsetof(playerState_t, dk3InvincibleUntil), 1, qtrue},
    {"dk3envuntil", DK_SAVE_INT, offsetof(playerState_t, dk3EnvUntil), 1, qtrue},
    {"dk3cameraorigin", DK_SAVE_FLOAT, offsetof(playerState_t, dk3CameraOrigin), 3, qfalse},
    {"dk3cameraangles", DK_SAVE_FLOAT, offsetof(playerState_t, dk3CameraAngles), 3, qfalse},
    {"dk3camerafov", DK_SAVE_FLOAT, offsetof(playerState_t, dk3CameraFov), 1, qfalse},
    {"dk3camerablend", DK_SAVE_FLOAT, offsetof(playerState_t, dk3CameraBlend), 4, qfalse},
};
const int dk_playerMemberCount = ARRAY_LEN(dk_playerMembers);
qboolean DK_SaveObject(dkSaveWriter_t *writer, const void *object, const dkSaveMember_t *members, int count) {
    int i, j, values[64];
    for (i = 0; i < count; ++i) {
        const dkSaveMember_t *member = &members[i];
        const byte *address = (const byte *)object + member->offset;
        qboolean ok;
        if (member->type == DK_SAVE_TEXT) ok = DK_SaveText(writer, member->name, *(char *const *)address);
        else if (member->type == DK_SAVE_FLOAT) ok = DK_SaveFloats(writer, member->name, (const float *)address, member->count);
        else {
            if (member->count > ARRAY_LEN(values)) G_Error("dk3 save schema: integer array is too large");
            for (j = 0; j < member->count; ++j) {
                values[j] = ((const int *)address)[j];
                if (member->time) values[j] = values[j] ? values[j] - level.time : INT_MIN;
            }
            ok = DK_SaveInts(writer, member->name, values, member->count);
        }
        if (!ok) return qfalse;
    }
    return qtrue;
}

qboolean DK_ReadObject(dkSaveReader_t *reader, void *object, const dkSaveMember_t *members, int count,
                       dkSaveStrings_t *strings) {
    dkSaveField_t field;
    qboolean seen[DK_SAVE_FIELDS];
    int i, j;
    memset(seen, 0, sizeof(seen));
    if (count > DK_SAVE_FIELDS) G_Error("dk3 save schema exceeds field limit");
    while (DK_SaveNextField(reader, &field)) {
        byte *address;
        const dkSaveMember_t *member;
        for (i = 0; i < count; ++i) if (!strcmp(field.name, members[i].name)) break;
        if (i == count || seen[i]) {
            Q_strncpyz(reader->error, "unknown or duplicate object field", sizeof(reader->error)); return qfalse;
        }
        member = &members[i]; address = (byte *)object + member->offset;
        if (member->type != field.type || (field.type != DK_SAVE_TEXT && member->count != field.count)) {
            Q_strncpyz(reader->error, "object field has incompatible type or count", sizeof(reader->error)); return qfalse;
        }
        seen[i] = qtrue;
        if (field.type == DK_SAVE_TEXT) {
            char *text;
            if (field.count + 1 > strings->capacity - strings->used) {
                Q_strncpyz(reader->error, "saved strings exceed capacity", sizeof(reader->error)); return qfalse;
            }
            text = strings->bytes + strings->used;
            DK_SaveString(&field, text, field.count + 1);
            strings->used += field.count + 1;
            *(char **)address = *text ? text : NULL;
        } else if (field.type == DK_SAVE_FLOAT) {
            for (j = 0; j < field.count; ++j) ((float *)address)[j] = DK_SaveFloat(&field, j);
        } else {
            for (j = 0; j < field.count; ++j) {
                int value = DK_SaveInt(&field, j);
                if (member->time) {
                    if (value != INT_MIN && ((long long)value + level.time > INT_MAX || (long long)value + level.time < INT_MIN)) {
                        Q_strncpyz(reader->error, "saved time exceeds simulation range", sizeof(reader->error)); return qfalse;
                    }
                    value = value == INT_MIN ? 0 : value + level.time;
                }
                ((int *)address)[j] = value;
            }
        }
    }
    if (*reader->error) return qfalse;
    for (i = 0; i < count; ++i) if (!seen[i] && !members[i].optional) {
        Com_sprintf(reader->error, sizeof(reader->error), "missing object field %s", members[i].name); return qfalse;
    }
    return qtrue;
}

void DK_ApplyObject(void *destination, const void *source, const dkSaveMember_t *members, int count) {
    int i;
    for (i = 0; i < count; ++i) {
        const dkSaveMember_t *member = &members[i];
        const byte *from = (const byte *)source + member->offset;
        byte *to = (byte *)destination + member->offset;
        if (member->type == DK_SAVE_TEXT) {
            const char *text = *(char *const *)from;
            *(char **)to = text ? G_NewString(text) : NULL;
        } else memcpy(to, from, member->count * 4);
    }
}
