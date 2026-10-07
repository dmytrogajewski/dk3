// SPDX-License-Identifier: GPL-2.0-or-later
//! Health/armor accounting. Identity, collision, knockback and death dispatch are callers' work.
const std = @import("std");
const Health = @import("items.zig").Health;
const Character = @import("character.zig").State;
pub const Feedback = struct {
    handled_revision: u32 = 0,
    death_handled: bool = false,
    gibbed: bool = false,
    pain_ready_ms: ?i64 = null,
    hazard_voice_ms: ?i64 = null,
    flash_alpha: f32 = 0,
    flash_ms: i64 = 0,
    pub fn alpha(self: Feedback, now: i64) f32 {
        // The reference display loses .045 every 100 ms. Use elapsed time so
        // rendering and server tick rates cannot change the fade duration.
        return @max(0, self.flash_alpha - @as(f32, @floatFromInt(@max(0, now - self.flash_ms))) * 0.00045);
    }
    pub fn hit(self: *Feedback, blood: i32, now: i64, suppress: bool) void {
        self.flash_alpha = if (suppress) 0 else @min(0.75, self.alpha(now) + @as(f32, @floatFromInt(blood)) / 40);
        self.flash_ms = now;
    }
};
pub const Receipt = struct {
    source: u32 = 0,
    at_ms: i64 = -1,
    revision: u32 = 0,
    weapon: u5 = 0,
    amount: i32 = 0,
    feedback: Feedback = .{},
    // Cumulative velocity changes survive coalesced network snapshots. Each
    // presentation applies the difference once, including hits on sleeping bodies.
    impulse: @import("vector.zig").Vec3 = @splat(0),
    impulse_point: @import("vector.zig").Vec3 = @splat(0),
    impulse_serial: u32 = 0,
    impulse_revision: ?u32 = null,
    revision_impulse: @import("vector.zig").Vec3 = @splat(0),
};
pub const Options = struct { source: u32 = 0, weapon: u5 = 0, bypass_armor: bool = false, bypass_protection: bool = false, environmental: bool = false, self_hazard: bool = false, suppress_flash: bool = false, attacker_class: []const u8 = "" };
pub const Result = struct { blood: i32 = 0, armor: i32 = 0, killed: bool = false };
pub fn apply(health: *Health, character: ?Character, amount: i32, now: i64, options: Options) Result {
    if (amount <= 0 or health.current <= 0) return .{};
    var damage = amount;
    if (character) |state| {
        if (!options.bypass_protection and (state.invincible_until > now or (options.environmental and state.environment_until > now))) return .{};
        damage = @import("weapon_catalog").character.ringDamage(state.rings, options.attacker_class, damage);
    }
    var saved: i32 = 0;
    if (!options.bypass_armor and health.armor > 0) {
        const percent = if (health.absorption > 0) std.math.clamp(health.absorption, 0, 100) else 50;
        const absorb = @divTrunc(@as(i64, damage) * percent + 99, 100);
        saved = @intCast(@min(health.armor, absorb));
    }
    health.armor -= saved;
    const blood = damage - saved;
    health.current -= blood;
    return .{ .blood = blood, .armor = saved, .killed = health.current <= 0 };
}
test "invincibility and environment precede armor; armor rounds absorption upward" {
    var health: Health = .{ .armor = 100, .absorption = 75 };
    var character: Character = .{ .invincible_until = 1000, .environment_until = 2000 };
    try std.testing.expectEqual(@as(i32, 0), apply(&health, character, 41, 999, .{}).blood);
    const hit = apply(&health, character, 41, 1000, .{});
    try std.testing.expectEqual(@as(i32, 31), hit.armor);
    try std.testing.expectEqual(@as(i32, 10), hit.blood);
    try std.testing.expectEqual(@as(i32, 0), apply(&health, character, 50, 1500, .{ .environmental = true }).blood);
    character.rings = 16;
    try std.testing.expectEqual(@as(i32, 10), apply(&health, character, 40, 2000, .{ .bypass_armor = true, .attacker_class = "monster_stavros" }).blood);
    try std.testing.expect(apply(&health, character, 1000, 2500, .{ .bypass_armor = true }).killed);
}

test "injury blend uses surviving damage, accumulates, and decays by elapsed time" {
    var feedback: Feedback = .{};
    var health: Health = .{ .armor = 100, .absorption = 75 };
    const hit = apply(&health, null, 40, 1000, .{});
    feedback.hit(hit.blood, 1000, false);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), feedback.alpha(1000), 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.205), feedback.alpha(1100), 0.00001);
    feedback.hit(30, 1100, false);
    try std.testing.expectEqual(@as(f32, 0.75), feedback.alpha(1100));
    try std.testing.expectEqual(@as(f32, 0), feedback.alpha(3000));
    feedback.hit(20, 3100, false);
    feedback.hit(1, 3150, true);
    try std.testing.expectEqual(@as(f32, 0), feedback.alpha(3150));
}
