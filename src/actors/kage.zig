// SPDX-License-Identifier: GPL-2.0-or-later
//! Kage owns his sword, finite smoke escapes and health recharge cycles.
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc", "atake" };
pub const fade_tag = 10026;
pub const Phase = enum { combat, smoke, hidden, returning, protectors, charging };
pub const State = struct {
    phase: Phase = .combat,
    suspended: ?Phase = null,
    suspended_next_ms: i64 = 0,
    alpha: f32 = 1,
    base_health: f32 = 1200,
    health_fraction: f32 = 0,
    charges: u8 = 0,
    escapes: u8 = 0,
    protectors: u8 = 0,
    return_steps: u8 = 0,
    next_ms: i64 = 0,
    recharge_ready_ms: i64 = 0,
    dodge_ready_ms: i64 = 0,
    feedback_ready_ms: i64 = 0,
    feedback: bool = false,
    aura: bool = false,
    awakened: bool = false,
    humming: bool = false,
    aura_started_ms: i64 = 0,
    voice_pose: u2 = 0,
    pub fn recharging(self: State) bool {
        return self.phase == .protectors or self.phase == .charging;
    }
    pub fn invulnerable(self: State) bool {
        return self.suspended != null or self.phase == .smoke or self.phase == .hidden or self.phase == .returning;
    }
    pub fn eligible(self: State, health: i32, skill: i32, now: i64) bool {
        return !self.recharging() and self.charges > 0 and now > self.recharge_ready_ms and @as(f32, @floatFromInt(health)) + self.health_fraction < self.base_health * limit(skill);
    }
    pub fn refund(self: *State, health: *i32, amount: i32) void {
        const remaining = @as(f32, @floatFromInt(health.*)) + self.health_fraction;
        const restored = if (remaining < self.base_health * 0.2) self.base_health * 0.25 + @as(f32, @floatFromInt(amount)) else remaining + @as(f32, @floatFromInt(amount)) * 1.05;
        health.* = @intFromFloat(restored);
        self.health_fraction = restored - @as(f32, @floatFromInt(health.*));
        self.feedback = true;
    }
};
pub fn difficulty(skill: i32) usize {
    return if (skill <= 1) 0 else if (skill == 2) 1 else 2;
}
pub fn limit(skill: i32) f32 {
    return ([_]f32{ 0.25, 0.5, 0.75 })[difficulty(skill)];
}
pub fn initialize(health: i32, skill: i32) State {
    const index = difficulty(skill);
    return .{ .base_health = @floatFromInt(health), .charges = ([_]u8{ 2, 5, 10 })[index], .escapes = ([_]u8{ 2, 4, 8 })[index] };
}
test "Kage refunds lethal recharge hits and retains fractional healing" {
    const t = @import("std").testing;
    var state = initialize(1200, 2);
    state.phase = .protectors;
    var health: i32 = -500;
    state.refund(&health, 600);
    try t.expectEqual(@as(i32, 900), health);
    health -= 1;
    state.refund(&health, 1);
    try t.expectEqual(@as(i32, 900), health);
    try t.expectApproxEqAbs(@as(f32, 0.05), state.health_fraction, 0.001);
    try t.expect(!state.eligible(1, 2, 100));
    state.phase = .combat;
    try t.expect(state.eligible(599, 2, 100));
    try t.expect(!state.eligible(600, 2, 100));
}
