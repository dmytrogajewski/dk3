// SPDX-License-Identifier: GPL-2.0-or-later
//! Ambient fireflies are a swarm emitter, not a hostile monster.
pub const classname = "monster_firefly";
pub const render_tag = 10004;
pub const models = [_][]const u8{ "models/global/e_flare.sp2", "models/global/e_flare4+.sp2", "models/global/e_flare4+o.sp2", "models/global/e_flare4x.sp2", "models/global/e_flare4x.sp2", "models/global/e_flare8+.sp2", "models/global/e_flare8+o.sp2", "models/global/e_flareo.sp2" };
pub fn shape(flags: u32) u3 {
    for (0..7) |i| if (flags & (@as(u32, 1) << @intCast(i)) != 0) return @intCast(i + 1);
    return 0;
}
pub const State = struct {
    source: u32,
    shape: u3,
    distance: f32 = 75,
    speed: f32 = 55,
    scale: f32 = 0.5,
    color: [3]f32 = @splat(1),
    color2: [3]f32 = @splat(0),
    displayed_color: [3]f32 = @splat(1),
    alpha: f32 = 0.75,
    maximum_alpha: f32 = 0.75,
    delta_alpha: f32 = 0,
    personality: f32,
    next_ms: i64,
    direction: [3]f32 = @splat(0),
    previous: [3]f32,
    outward: bool = false,
    phase: u4 = 0,
    alpha_up: bool = false,
    alpha_count: u3 = 0,
    color_forward: bool = false,
    color_fraction: f32 = 0.1,
};
