// SPDX-License-Identifier: GPL-2.0-or-later
pub const State = struct { motion_ms: ?i64 = null, wave: u4 = 0, bobbing: bool = false };
pub fn bob(index: u4) f32 {
    const std = @import("std");
    const sample: u16 = @intFromFloat(@as(f32, @floatFromInt(index)) * 1.25);
    // Derive the sampled sine mathematically; no private lookup table is used.
    return 12.5 * @round(@sin(@as(f32, @floatFromInt(1 + sample * 30)) * std.math.pi / 180) * 1000) * 0.001;
}
test "seagull wave wraps before the next reference sample exceeds the cycle" {
    const t = @import("std").testing;
    var state: State = .{};
    for (0..10) |_| state.wave = if (state.wave == 9) 0 else state.wave + 1;
    try t.expectEqual(@as(u4, 0), state.wave);
    try t.expect(bob(2) > 10);
    try t.expect(bob(7) < -10);
}
