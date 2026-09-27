// SPDX-License-Identifier: GPL-2.0-or-later
//! Persistent effect deadlines. Simulation time, never render frames, controls decay.
const std = @import("std");
const Effect = @import("weapon_catalog").affliction.Effect;
pub const Poison = struct { source: u32, weapon: u5, damage: f32, until_ms: i64, next_ms: i64, interval_ms: u32 };
pub const Tick = struct { source: u32, weapon: u5, amount: f32, bypass_armor: bool = false };
pub const State = struct {
    mask: u32 = 0,
    warp: ?@import("actor_catalog").psyclaw.Warp = null,
    freeze_level: f32 = 0,
    poison: ?Poison = null,
    freeze_at_ms: ?i64 = null,
    freeze_next_ms: ?i64 = null,
    freeze_source: u32 = 0,
    freeze_weapon: u5 = 0,
    pub fn cure(self: *State) void {
        const retained = self.mask & ~@as(u32, 7);
        self.* = .{ .mask = retained, .warp = self.warp };
    }
    fn thaw(self: *State, now: i64) void {
        if (self.freeze_at_ms) |at| {
            self.freeze_level = @max(0, self.freeze_level - @as(f32, @floatFromInt(@max(0, now - at))) * 0.0001);
            self.freeze_at_ms = @max(at, now);
            if (self.freeze_level < 0.00001) {
                self.freeze_level = 0;
                self.mask &= ~@as(u32, 4);
                self.freeze_at_ms = null;
                self.freeze_next_ms = null;
            }
        }
    }
    pub fn apply(self: *State, effect: Effect, source: u32, weapon: u5, now: i64) bool {
        switch (effect) {
            .none => return false,
            .poison => |value| {
                if (value.damage <= 0 or value.duration_ms == 0 or value.interval_ms == 0) return false;
                if (self.poison) |*active| {
                    if (active.until_ms > now) {
                        if (value.damage <= active.damage or value.interval_ms >= active.interval_ms) return false;
                        active.damage += value.damage;
                        active.interval_ms = value.interval_ms;
                        active.until_ms += value.duration_ms;
                        active.source = source;
                        active.weapon = weapon;
                        return true;
                    }
                }
                self.poison = .{ .source = source, .weapon = weapon, .damage = value.damage, .until_ms = now + value.duration_ms, .next_ms = now + value.interval_ms, .interval_ms = value.interval_ms };
                self.mask |= 1;
                return true;
            },
            .freeze => |value| {
                self.thaw(now);
                self.freeze_level = std.math.clamp(self.freeze_level + value, 0, 1);
                if (self.freeze_level == 0) return false;
                self.freeze_at_ms = now;
                if (self.freeze_next_ms == null) self.freeze_next_ms = now;
                self.freeze_source = source;
                self.freeze_weapon = weapon;
                self.mask |= 4;
                return true;
            },
        }
    }
    /// Drain due damage before advancing decay to now. This preserves timing and
    /// damage across sparse updates and save-clock rebasing.
    pub fn next(self: *State, now: i64) ?Tick {
        if (self.poison) |value| if (value.next_ms > value.until_ms and now > value.until_ms) {
            self.poison = null;
            self.mask &= ~@as(u32, 1);
        };
        const poison_at = if (self.poison) |value| (if (value.next_ms <= value.until_ms) value.next_ms else std.math.maxInt(i64)) else std.math.maxInt(i64);
        const freeze_at = self.freeze_next_ms orelse std.math.maxInt(i64);
        const at = @min(poison_at, freeze_at);
        if (at > now) {
            self.thaw(now);
            return null;
        }
        self.thaw(at);
        if (poison_at <= freeze_at) {
            const value = &self.poison.?;
            value.next_ms += value.interval_ms;
            return .{ .source = value.source, .weapon = value.weapon, .amount = value.damage };
        }
        const amount = self.freeze_level * 5;
        if (self.freeze_next_ms != null) self.freeze_next_ms = at + 2000;
        return .{ .source = self.freeze_source, .weapon = self.freeze_weapon, .amount = amount, .bypass_armor = true };
    }
};

test "poison does not stack identical bites; cure cancels deadlines and freeze decay is frame independent" {
    var status: State = .{};
    const poison: Effect = .{ .poison = .{ .damage = 3, .duration_ms = 3000 } };
    try std.testing.expect(status.apply(poison, 7, 11, 100));
    try std.testing.expect(!status.apply(poison, 7, 11, 900));
    try std.testing.expect(status.next(1099) == null);
    var damage: f32 = 0;
    while (status.next(3200)) |tick| damage += tick.amount;
    try std.testing.expectEqual(@as(f32, 9), damage);
    try std.testing.expectEqual(@as(u32, 0), status.mask);
    _ = status.apply(.{ .freeze = 0.4 }, 7, 24, 4000);
    var sparse = status;
    var frequent_damage: f32 = 0;
    for (0..61) |i| while (status.next(4000 + @as(i64, @intCast(i)) * 100)) |tick| {
        frequent_damage += tick.amount;
    };
    var sparse_damage: f32 = 0;
    while (sparse.next(10000)) |tick| sparse_damage += tick.amount;
    try std.testing.expectApproxEqAbs(sparse_damage, frequent_damage, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), status.freeze_level, 0.0001);
    _ = status.apply(poison, 7, 11, 11000);
    status.mask |= 128;
    status.cure();
    try std.testing.expect(status.next(99999) == null);
    try std.testing.expectEqual(@as(u32, 128), status.mask);
}
