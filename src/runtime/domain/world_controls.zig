// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored controls with distinct, serializable state.
const v = @import("vector.zig");
pub const Timer = struct {
    wait_ms: i64 = 1000,
    variance_ms: i64 = 0,
    delay_ms: i64 = 0,
    next_ms: ?i64 = null,
    activator: u32 = 0,
    random: u32 = 1,
    once: bool = false,
    pub fn interval(self: *Timer) i64 {
        self.random = self.random *% 1664525 +% 1013904223;
        const fraction = @as(f32, @floatFromInt(self.random >> 8)) / 16777216;
        return self.wait_ms + @as(i64, @intFromFloat((fraction * 2 - 1) * @as(f32, @floatFromInt(self.variance_ms))));
    }
};
pub const Action = union(enum) {
    gib_emitter: @import("gib_emitter.zig").State,
    debris: @import("debris.zig").State,
    room: u8,
    laser: @import("laser.zig").State,
    healer: @import("item_catalog").hosportal.State,
    timer: Timer,
    speaker: @import("audio.zig").Speaker,
    push: struct { enabled: bool = true, velocity: v.Vec3, toggleable: bool = false, once: bool = false },
    teleport: struct { named_subject: []const u8 = "" },
    secret,
    toggle: struct { activator: u32 = 0, center: v.Vec3, radius: f32 },
    music: struct { path: []const u8, volume: f32 = 1, changed_ms: ?i64 = null },
    console: enum { disconnect, sword, first_weapon },
    remove_item: []const u8,
};
pub const State = struct { action: Action, uses: u32 = 0, ready_ms: i64 = 0 };

test "timer random cadence is bounded and resumes the same sequence from saved state" {
    const t = @import("std").testing;
    var timer: Timer = .{ .wait_ms = 18000, .variance_ms = 3000, .random = 42 };
    for (0..8) |_| {
        const interval = timer.interval();
        try t.expect(interval >= 15000 and interval < 21000);
    }
    var restored = timer;
    for (0..8) |_| try t.expectEqual(timer.interval(), restored.interval());
}
