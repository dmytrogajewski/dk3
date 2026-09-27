// SPDX-License-Identifier: GPL-2.0-or-later
//! Stationary popup gun. Defaults are class contracts, overridden by map epairs.
const std = @import("std");
pub const muzzle_model = "models/global/me_mflash.dkm";
pub const flash_tag: i32 = 0x52474154;
pub const Phase = enum { disabled, passive, raising, scanning, lowering };
pub const Burst = struct { remaining: u3 = 5, next_ms: i64 };
pub const State = struct {
    phase: Phase = .passive,
    toggle: bool = false,
    on: bool = false,
    height: u16 = 10,
    raised: bool = false,
    pose_ms: i64 = 0,
    next_attack_ms: i64 = 0,
    next_sound_ms: i64 = 0,
    fire_ms: i64 = 130,
    range: f32 = 512,
    damage: f32 = 1,
    random_damage: f32 = 1,
    sound: []const u8 = "e1/e_rockgatshootmultia.wav",
    up_sound: []const u8 = "doors/e1/lift3start.wav",
    down_sound: []const u8 = "doors/e1/lift3stop.wav",
    hit_sound: []const u8 = "",
    bursts: [16]?Burst = @splat(null),
    shots: u32 = 0,
    pub fn use(self: *State) void {
        if (!self.toggle) return;
        self.on = !self.on;
        self.phase = if (self.on) if (self.height == 0) .scanning else .raising else if (self.height == 0) .disabled else .lowering;
    }
    pub fn frame(self: State, now: i64) u16 {
        if (self.height == 0) return 0;
        const elapsed: u64 = @intCast(@max(0, now - self.pose_ms));
        const progress: u16 = @intCast(@min(self.height, elapsed / 100));
        return if (self.raised) progress else self.height - 1 - @min(self.height - 1, progress);
    }
    pub fn startBurst(self: *State, now: i64) !void {
        for (&self.bursts) |*burst| if (burst.* == null) {
            burst.* = .{ .next_ms = now + 10 };
            return;
        };
        return error.RockgatBurstCapacity;
    }
};
pub fn pitchAllowed(vertical_direction: f32) bool {
    return vertical_direction < 0.35;
}
pub fn damageAdmitted(skill: u8, random: f32) bool {
    const level: f32 = if (skill <= 2) 1 else if (skill == 3) 2 else 3;
    return random > 0.5 / level;
}
pub fn painDamage(amount: i32) i32 {
    // Reference common damage subtracts first; Rockgat's pain callback subtracts
    // the incoming amount again. This rule must not affect other actors.
    return amount;
}
test "Rockgat toggle, popup timing and asymmetric vertical firing bound" {
    const t = std.testing;
    var gun: State = .{ .toggle = true, .phase = .disabled };
    gun.use();
    try t.expectEqual(Phase.raising, gun.phase);
    gun.raised = true;
    gun.pose_ms = 200;
    try t.expectEqual(@as(u16, 0), gun.frame(200));
    try t.expectEqual(@as(u16, 5), gun.frame(700));
    try t.expectEqual(@as(u16, 10), gun.frame(1200));
    gun.use();
    try t.expectEqual(Phase.lowering, gun.phase);
    gun.raised = false;
    try t.expectEqual(@as(u16, 9), gun.frame(200));
    try t.expectEqual(@as(u16, 0), gun.frame(1100));
    try t.expect(pitchAllowed(-0.9));
    try t.expect(!pitchAllowed(0.35));
    try t.expect(!damageAdmitted(3, 0.25));
    try t.expect(damageAdmitted(3, 0.251));
    try gun.startBurst(2000);
    try t.expectEqual(@as(u3, 5), gun.bursts[0].?.remaining);
    try t.expectEqual(@as(i64, 2010), gun.bursts[0].?.next_ms);
}
