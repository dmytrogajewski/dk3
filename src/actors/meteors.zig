// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared authored stave callback; class tuning determines its launch and blast.
pub const model = "models/e3/we_meteor.dkm";
pub const render_tag = 10022;
pub const State = struct {
    phase: enum { stave, fragment, flare, impact } = .stave,
    next_ms: i64,
    scale: [3]f32 = @splat(0.2),
    spin: [3]f32,
    damage: f32,
    radius: f32,
    speed: f32,
    glow: f32 = 2.75,
    bounces: u8 = 0,
    bounce_max: f32 = 0,
    delta: f32 = 0.35,
    normal: [3]f32 = @splat(0),
    scorch: bool = false,
};
