// SPDX-License-Identifier: GPL-2.0-or-later
//! Finite campaign fruit and deathmatch-only regeneration.
const std = @import("std");
pub const model = "models/e1/healthtree.dkm";
pub const sounds = [_][]const u8{ "e1/t_use1.wav", "e1/t_use2.wav" };
pub const regen_sound = "e1/t_regen.wav";
/// Toss contact removes the normal velocity and settles on a supporting floor.
/// A tree must not keep accelerating down walkable slopes like a sliding actor.
pub fn contact(velocity: [3]f32, normal: [3]f32) [3]f32 {
    var dot: f32 = 0;
    for (velocity, normal) |speed, axis| dot += speed * axis;
    var result: [3]f32 = undefined;
    for (&result, velocity, normal) |*out, speed, axis| {
        out.* = speed - axis * dot;
        if (@abs(out.*) < 0.1) out.* = 0;
    }
    return if (normal[2] > 0.7 and result[2] < 60) @splat(0) else result;
}

test "health trees settle on slopes while wall and steep contacts preserve tangential fall" {
    try std.testing.expectEqual([3]f32{ 0, 0, 0 }, contact(.{ 0, 0, -40 }, .{ 0.6, 0, 0.8 }));
    try std.testing.expectEqual([3]f32{ 0, 0, 0 }, contact(.{ 0, 0, -40 }, .{ 0, 0, 1 }));
    try std.testing.expectEqual([3]f32{ 0, 10, -40 }, contact(.{ -100, 10, -40 }, .{ 1, 0, 0 }));
    const steep = contact(.{ 0, 0, -40 }, .{ 0.8, 0, 0.6 });
    try std.testing.expect(steep[0] > 0 and steep[2] < 0);
}
pub const State = struct {
    drugbox: ?@import("drugbox.zig").State = null,
    maximum: u3 = 5,
    fruit: u3 = 5,
    previous: u3 = 5,
    ready_ms: i64 = 0,
    changed_ms: i64 = 0,
    recharge_ms: ?i64 = null,
    pub fn take(self: *State, health: *i32, maximum: i32, now: i64, respawn: bool) bool {
        if (now < self.ready_ms or self.fruit == 0 or health.* <= 0 or health.* >= maximum) return false;
        health.* = @min(maximum, health.* + 10);
        self.previous = self.fruit;
        self.fruit -= 1;
        self.ready_ms = now + 1000;
        self.changed_ms = now;
        // Supplied recharge_rate is intentionally ignored by the reference tree.
        if (respawn) self.recharge_ms = now + @divTrunc(@as(i64, 30), self.maximum) * 1000;
        return true;
    }
    pub fn regenerate(self: *State, now: i64, respawn: bool) bool {
        if (!respawn or self.fruit >= self.maximum or self.recharge_ms == null or now < self.recharge_ms.?) return false;
        self.previous = self.fruit;
        self.fruit += 1;
        self.changed_ms = now;
        self.recharge_ms = if (self.fruit < self.maximum) now + @divTrunc(@as(i64, 30), self.maximum) * 1000 else null;
        return true;
    }
    pub fn frame(self: State, now: i64) i32 {
        if (self.drugbox) |box| return box.frame(now);
        return 5 - @as(i32, if (now - self.changed_ms < 50) self.previous else self.fruit);
    }
};
test "campaign fruit is finite and use cooldown survives exact boundaries" {
    var tree: State = .{ .maximum = 2, .fruit = 2, .previous = 2 };
    var health: i32 = 85;
    try std.testing.expect(tree.take(&health, 100, 100, false));
    try std.testing.expectEqual(@as(i32, 95), health);
    try std.testing.expect(!tree.take(&health, 100, 1099, false));
    try std.testing.expect(tree.take(&health, 100, 1100, false));
    try std.testing.expectEqual(@as(i32, 100), health);
    try std.testing.expect(!tree.regenerate(999999, false));
    try std.testing.expectEqual(@as(u3, 0), tree.fruit);
    health = 50;
    try std.testing.expect(!tree.take(&health, 100, 1000000, false));
}
