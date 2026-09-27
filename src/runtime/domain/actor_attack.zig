// SPDX-License-Identifier: GPL-2.0-or-later
//! Persistent actor attacks share entity ownership, not gameplay rules.
const knights = @import("actor_catalog").knights;
pub const State = struct {
    owner: u32,
    born_ms: i64,
    stepped_ms: i64,
    attack: union(enum) {
        fireball: @import("actor_catalog").fireballs.State,
        knight_zap: knights.Zap,
        knight_punch: void,
        rocket: @import("actor_catalog").missiles.Rocket,
        rotworm_spit: @import("actor_catalog").rotworm.Spit,
        shaft: @import("actor_catalog").shafts.Shaft,
        prisoner_rock: @import("actor_catalog").prisoners.Rock,
        sludge_glob: @import("actor_catalog").sludge.Glob,
        gunner_burst: @import("actor_catalog").gunners.Burst,
        meteor: @import("actor_catalog").meteors.State,
        npc_wisp: @import("actor_catalog").wyndrax.Wisp,
        wyndrax_zap: @import("actor_catalog").wyndrax.Zap,
        wyndrax_bolt: @import("actor_catalog").wyndrax.Bolt,
        summon_effect: @import("actor_catalog").summon_effect.State,
        psyclaw_sphere: @import("actor_catalog").psyclaw.Sphere,
    },
};
