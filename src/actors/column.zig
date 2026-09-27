// SPDX-License-Identifier: GPL-2.0-or-later
//! Column is a dormant stone guardian with a hammer-only vulnerability.
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const awakening_distance: f32 = 256;
pub const attack_distance: f32 = 200;
pub const State = struct {
    phase: enum { asleep, awakening, awake } = .asleep,
    started_ms: i64 = 0,
    hurt: bool = false,
};
pub fn acceptsWeapon(hammer: bool) bool {
    return hammer;
}
pub fn select(distance: f32, weapon_range: f32) u3 {
    return if (distance < weapon_range) 0 else 1;
}
