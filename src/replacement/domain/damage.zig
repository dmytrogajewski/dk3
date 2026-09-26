// SPDX-License-Identifier: GPL-2.0-or-later
//! Health/armor accounting. Identity, collision, knockback and death dispatch are callers' work.
const std = @import("std");
const Health = @import("items.zig").Health;
const Character = @import("character.zig").State;
pub const Options = struct { bypass_armor: bool = false, bypass_protection: bool = false, environmental: bool = false, attacker_class: []const u8 = "" };
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
