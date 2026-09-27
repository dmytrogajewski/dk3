// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "hover" };
pub const breath_tag = 10016;
pub const State = struct {
    phase: enum { choose, hover, attack } = .choose,
    until_ms: i64 = 0,
    ambient_ms: i64 = 0,
    breath_emitted: bool = false,
    breath_until_ms: ?i64 = null,
    breath_direction: [3]f32 = @splat(0),
};
