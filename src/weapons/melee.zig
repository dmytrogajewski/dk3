// SPDX-License-Identifier: GPL-2.0-or-later
//! Timed melee contracts, owned by concrete weapon classes.
pub const Plan = struct {
    hits: u8 = 1,
    delays_ms: [2]u16 = .{ 0, 0 },
    from: [2][3]f32 = @splat(@splat(0)),
    to: [2][3]f32 = @splat(@splat(0)),
    radius: f32 = 0,
    height: f32 = 0,
    crouching_height: f32 = 0,
    fallback_range: f32 = 64,
    range: ?f32 = null,
    body_trace: bool = false,
    /// Some authored strikes add the supplied muzzle in world coordinates.
    world_muzzle: bool = false,
    inertial: bool = false,
    scale_timing: bool = false,
    sound_on_strike: bool = false,
    require_selected: bool = true,
};
pub const Hit = struct {
    damage: f32,
    lifetime_ms: u32 = 0,
    experience: i32,
    victim_class: []const u8,
    forward: [3]f32,
    facing: [3]f32,
    defending: bool,
    serial: u32,
};
pub const Damage = struct { amount: f32, sound: ?[:0]const u8 = null, effect: @import("affliction.zig").Effect = .none };
