// SPDX-License-Identifier: GPL-2.0-or-later
pub const render_tag = 10042;
pub const State = struct {
    next_ms: i64,
    until_ms: ?i64 = null,
    extent: [3]f32,
    mass: f32,
};
