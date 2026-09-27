// SPDX-License-Identifier: GPL-2.0-or-later
//! The authored Wisp cluster supplies Wyndrax's recharge; it is not an enemy.
pub const classname = "monster_wisp";
pub const model = "models/global/e_sflblue.sp2";
pub const render_tag = 10020;
pub const Swarm = struct {
    children: [10]u32 = @splat(0),
    count: u4 = 3,
    next_ms: i64,
    sound_ms: i64,
    consumer: u32 = 0,
    sending: ?u4 = null,
    goal: [3]f32 = @splat(0),
    delivered: u16 = 0,
};
pub const Particle = struct {
    mode: enum { wander, collect, dormant } = .wander,
    new_goal: bool = false,
    goal: [3]f32,
    respawn_ms: i64 = 0,
    collected_ms: i64 = 0,
    collected_at: [3]f32 = @splat(0),
    blocked: u32 = 0,
    alpha_count: u32 = 0,
    blend_after: u8 = 0,
};
