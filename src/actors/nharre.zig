// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "atakb", "atakc" };
pub const reaper_tag = 10027;
pub const reaper_model = "models/e3/we_nnreaper.dkm";
pub const State = struct {
    phase: enum { combat, fading_out, fading_in, retreat } = .combat,
    alpha: f32 = 1,
    teleport_ready_ms: i64 = 0,
    summon_ready_ms: i64 = 0,
    destination: [3]f32 = @splat(0),
    retreat_until_ms: i64 = 0,
    teleports: [10][3]f32 = @splat(@splat(0)),
    teleport_count: u8 = 0,
    teleports_ready: bool = false,
    pub fn invulnerable(self: State) bool {
        return self.phase == .fading_out or self.phase == .fading_in;
    }
    pub fn fade(self: *State, clear: bool) enum { waiting, relocate, finished } {
        if (self.phase == .fading_out) {
            if (self.alpha > 0.1) self.alpha = @max(0, self.alpha - 0.1) else if (clear) {
                self.phase = .fading_in;
                return .relocate;
            }
        } else if (self.phase == .fading_in) {
            if (self.alpha >= 1) {
                self.phase = .combat;
                return .finished;
            }
            self.alpha = @min(1, self.alpha + 0.1);
        }
        return .waiting;
    }
    pub fn teleportIndex(self: State, roll: f32) ?usize {
        if (self.teleport_count == 0) return null;
        // The authored callback multiplies by count-1, excluding the final
        // destination when multiple points exist. Keep that selection contract.
        return @intFromFloat(@as(f32, @floatFromInt(self.teleport_count - 1)) * roll);
    }
};
pub const Reaper = struct {
    target: u32,
    next_ms: i64,
    appeared_ms: ?i64 = null,
    released: bool = false,
    struck: bool = false,
    previous_velocity: [3]f32 = @splat(0),
    previous_view_height: f32 = 22,
    previous_mask: u32 = 0,
    look_angles: [3]f32 = @splat(0),
    floor: [3]f32 = @splat(0),
    ceiling: [3]f32 = @splat(0),
    scorch: [3]f32 = @splat(0),
    normal: [3]f32 = @splat(0),
    flame_next_ms: i64 = 0,
};
test "Nharre teleport selection preserves the final-point exclusion without underflow" {
    const t = @import("std").testing;
    var state: State = .{};
    try t.expect(state.teleportIndex(0.5) == null);
    state.teleport_count = 1;
    try t.expectEqual(@as(?usize, 0), state.teleportIndex(0.999));
    state.teleport_count = 4;
    try t.expectEqual(@as(?usize, 2), state.teleportIndex(0.999));
    try t.expectEqual(@as(?usize, 1), state.teleportIndex(0.5));
}

test "Nharre waits on an occupied point and restores damage only after fading in" {
    const t = @import("std").testing;
    var state: State = .{ .phase = .fading_out };
    for (0..30) |_| try t.expect(state.fade(false) == .waiting);
    try t.expect(state.alpha <= 0.1 and state.invulnerable());
    const alpha = state.alpha;
    try t.expect(state.fade(true) == .relocate);
    try t.expectEqual(alpha, state.alpha);
    try t.expect(state.phase == .fading_in and state.invulnerable());
    for (0..9) |_| try t.expect(state.fade(true) == .waiting);
    while (state.alpha < 1) try t.expect(state.fade(true) == .waiting);
    try t.expect(state.invulnerable());
    try t.expect(state.fade(true) == .finished);
    try t.expect(!state.invulnerable());
}
