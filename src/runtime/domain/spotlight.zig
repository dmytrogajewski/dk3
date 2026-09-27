// SPDX-License-Identifier: GPL-2.0-or-later
pub const render_tag = 10035;
pub const State = struct {
    dynamic: bool = false,
    cone: bool = true,
    flare: bool = false,
    model: []const u8 = "",
    brightness: f32 = 200,
    spin: [3]f32 = @splat(0),
    stepped_ms: i64 = 0,
    enabled: bool = false,
    initialized: bool = false,
    next_ms: i64,
    target: u32 = 0,
    radius: f32 = 4,
    length: f32 = 2048,
    direction: [3]f32,
    endpoint: [3]f32,
    color: [3]f32 = @splat(1),
};
