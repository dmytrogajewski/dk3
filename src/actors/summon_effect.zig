// SPDX-License-Identifier: GPL-2.0-or-later
//! The two boss summoning callbacks share this rotating flare contract.
pub const render_tag = 10028;
pub const State = struct {
    kind: enum { red, blue, smoke } = .red,
    scale: [3]f32 = @splat(1),
    spin: [3]f32 = @splat(0),
    alpha: f32 = 0.75,
    alpha_multiplier: f32 = 0.95,
    oriented: bool = false,
    expires_ms: i64,
    next_ms: i64,
};
