// SPDX-License-Identifier: GPL-2.0-or-later
//! Episode-four gunner policies. The commando's two poses are both stationary.
pub const Kind = enum { captain, commando, girl, uzi };
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct {
    pursuing: bool = true,
    ready_ms: i64 = 0,
    emit_ms: i64 = 0,
    pain_lock_ms: i64 = 0,
};
pub const BurstKind = enum { commando, uzi, shotgun };
pub const Burst = struct {
    kind: BurstKind,
    tuning: @import("weapon.zig").Tuning,
    next_ms: i64,
    shots: u16 = 0,
    two_hands: bool = false,
};
pub const flash_model = "models/global/we_mflash.dkm";
pub const render_tag = 10013;
// These callbacks request .01s but run once per reference 100ms server frame.
pub const burst_tick_ms: i64 = 100;
pub fn chaseDistance(kind: Kind) f32 {
    return if (kind == .captain) 300 else 200;
}
pub fn painLimit(kind: Kind) i32 {
    return switch (kind) {
        .captain, .girl => 35,
        .commando => 45,
        .uzi => 50,
    };
}
pub fn shotgunDamage(base: f32, random_damage: f32, roll: f32, distance: f32, range: f32) f32 {
    const damage = base + random_damage * roll;
    return if (distance <= 256) damage else @max(0, damage * (1 - (distance - 256) / (range - 256)));
}
test "shotgun damage uses enemy distance beyond the full damage band" {
    const t = @import("std").testing;
    try t.expectEqual(@as(f32, 25), shotgunDamage(20, 10, 0.5, 256, 500));
    try t.expectEqual(@as(f32, 12.5), shotgunDamage(20, 10, 0.5, 378, 500));
    try t.expectEqual(@as(f32, 0), shotgunDamage(20, 10, 0.5, 500, 500));
}
