// SPDX-License-Identifier: GPL-2.0-or-later
//! Wyndrax owns recharge and ammunition; its attack wisps also serve Garroth.
pub const attacks = [_][]const u8{ "charged", "wispa", "chargea", "wispb", "wispc" };
pub const render_tag = 10021;
pub const model = "models/e3/we_wisp.dkm";
pub const State = struct {
    phase: enum { combat, powerup, approach_charge, find_swarm, approach_swarm, collect, retreat, wander } = .combat,
    ammo: u8 = 3,
    charged: bool = true,
    source: u32 = 0,
    charge: u32 = 0,
    destination: [3]f32 = @splat(0),
    until_ms: i64 = 0,
    running: bool = true,
    start_position: [3]f32 = @splat(0),
};
pub const Wisp = struct {
    target: u32,
    next_ms: i64,
    sine_ms: i64 = 0,
    phase: u4 = 0,
    personality: f32,
    forward: [3]f32,
    fading: bool = false,
    alpha: f32 = 1,
    scale: [3]f32 = @splat(2),
    sprite_scale: f32,
};
pub const Zap = struct {
    target: u32,
    destination: [3]f32,
    emitted: u3 = 0,
};
pub const Bolt = struct {
    parent: u32,
    target: u32 = 0,
    destination: [3]f32,
    contact: [3]f32,
    next_ms: i64,
    until_ms: i64,
    kind: enum { wisp, scenery, zap, charge },
    color: [3]f32 = .{ 0.1, 0.2, 0.75 },
    flare: ?[3]f32 = null,
    flare_until_ms: i64 = 0,
    flare_scale: f32 = 2.15,
};
