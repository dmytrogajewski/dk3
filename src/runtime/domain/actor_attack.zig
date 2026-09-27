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
        vermin_rocket: @import("actor_catalog").vermin.Rocket,
    },
};
