// SPDX-License-Identifier: GPL-2.0-or-later
//! Persistent actor attacks share entity ownership, not gameplay rules.
const knights = @import("actor_catalog").knights;
pub const State = struct {
    owner: u32,
    born_ms: i64,
    stepped_ms: i64,
    attack: union(enum) {
        knight_flame: knights.Flame,
        knight_zap: knights.Zap,
        knight_punch: void,
        rocket: @import("actor_catalog").missiles.Rocket,
        rotworm_spit: @import("actor_catalog").rotworm.Spit,
        shaft: @import("actor_catalog").shafts.Shaft,
        prisoner_rock: @import("actor_catalog").prisoners.Rock,
    },
};
