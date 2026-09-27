// SPDX-License-Identifier: GPL-2.0-or-later
//! Episode-four medicine box: open first, then three finite ten-health doses.
const std = @import("std");
pub const model = "models/e4/a4_dbox.dkm";
pub const render_tag = 10033;
pub const Dose = struct { sound: []const u8, volume: f32 };
pub const State = struct {
    stage: u3 = 0,
    ready_ms: i64 = 0,
    changed_ms: i64 = 0,
    fade_ms: ?i64 = null,
    pub fn use(self: *State, health: *i32, maximum: i32, now: i64) ?Dose {
        if (now < self.ready_ms or health.* <= 0 or self.stage == 4) return null;
        if (self.stage == 0) {
            self.stage = 1;
            self.changed_ms = now;
            self.ready_ms = now + 1500;
            return .{ .sound = "", .volume = 0 };
        }
        if (health.* >= maximum) return null;
        health.* = @min(maximum, health.* + 10);
        const index = self.stage - 1;
        self.ready_ms = now + ([_]i64{ 1250, 2250, 1750 })[index];
        self.stage += 1;
        self.changed_ms = now;
        if (self.stage == 4) self.fade_ms = now + 100;
        return ([_]Dose{
            .{ .sound = "e1/m_dspheresteama.wav", .volume = 0.55 },
            .{ .sound = "artifacts/antidoteuse.wav", .volume = 0.65 },
            .{ .sound = "e1/we_dgloveamba.wav", .volume = 0.65 },
        })[index];
    }
    pub fn frame(self: State, now: i64) i32 {
        if (self.stage == 0) return 0;
        const age = @max(0, now - self.changed_ms);
        if (self.stage == 1) return @intCast(@min(29, @divTrunc(age, 50)));
        return 27 + @as(i32, self.stage) + @as(i32, @intFromBool(age >= 50));
    }
    pub fn alpha(self: State, now: i64) f32 {
        const at = self.fade_ms orelse return 1;
        if (now < at) return 1;
        return @max(0, 1 - @as(f32, @floatFromInt(1 + @divTrunc(now - at, 200))) * 0.05);
    }
};
test "medicine opens at full health, dispenses only missing health and cannot refill" {
    const t = std.testing;
    var state: State = .{};
    var health: i32 = 100;
    try t.expect(state.use(&health, 100, 1000) != null);
    try t.expectEqual(@as(i32, 100), health);
    try t.expect(state.use(&health, 100, 2500) == null);
    health = 75;
    try t.expect(state.use(&health, 100, 2499) == null);
    try t.expectEqualStrings("e1/m_dspheresteama.wav", state.use(&health, 100, 2500).?.sound);
    try t.expect(state.use(&health, 100, 3749) == null);
    _ = state.use(&health, 100, 3750);
    _ = state.use(&health, 100, 6000);
    try t.expectEqual(@as(i32, 100), health);
    health = 50;
    try t.expect(state.use(&health, 100, 10000) == null);
    try t.expectEqual(@as(f32, 1), state.alpha(6099));
    try t.expectApproxEqAbs(@as(f32, 0.95), state.alpha(6100), 0.001);
    try t.expect(state.alpha(9700) <= 0.051);
}
