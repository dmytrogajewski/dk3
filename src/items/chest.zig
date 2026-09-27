// SPDX-License-Identifier: GPL-2.0-or-later
//! Episode-three containers own their opening, reward and trap contracts.
const std = @import("std");
pub const render_tag = 10043;
pub const Kind = enum { wood, black };
pub fn kind(name: []const u8) ?Kind {
    if (std.ascii.eqlIgnoreCase(name, "item_wood_chest")) return .wood;
    if (std.ascii.eqlIgnoreCase(name, "item_black_chest")) return .black;
    return null;
}
pub fn classname(value: Kind) []const u8 {
    return if (value == .wood) "item_wood_chest" else "item_black_chest";
}
pub fn model(value: Kind) []const u8 {
    return if (value == .wood) "models/e3/a_chest.dkm" else "models/e3/a_blackchest.dkm";
}
pub const State = struct {
    kind: Kind,
    phase: enum { closed, opening, revealing, exploding, spent } = .closed,
    opener: u32 = 0,
    explosive: bool = false,
    reward: u3 = 0,
    started_ms: ?i64 = null,
    next_ms: ?i64 = null,
    stepped_ms: i64,
    pub fn use(self: *State, opener: u32, now: i64, roll: u8) bool {
        if (self.phase != .closed or opener == 0) return false;
        self.phase = .opening;
        self.opener = opener;
        self.explosive = self.kind == .black and roll < 50;
        self.started_ms = now;
        self.next_ms = now + if (self.explosive) @as(i64, 1000) else 1800;
        return true;
    }
    pub fn frame(self: State, now: i64) i32 {
        const start = self.started_ms orelse return 0;
        return @intCast(std.math.clamp(@divTrunc(now - start, 100), 0, 19));
    }
    pub fn advance(self: *State, now: i64, roll: u8) enum { none, explode, reveal, reward, remove } {
        if (self.next_ms == null or now < self.next_ms.?) return .none;
        const at = self.next_ms.?;
        self.next_ms = null;
        if (self.phase == .exploding) {
            self.phase = .spent;
            return .remove;
        }
        if (self.explosive) {
            self.phase = .exploding;
            self.next_ms = at + 300;
            return .explode;
        }
        if (self.phase == .opening) {
            self.reward = @intCast(roll % (if (self.kind == .wood) @as(u8, 5) else 4));
            if (self.kind == .black) {
                self.phase = .revealing;
                self.next_ms = at + 1500;
                return .reveal;
            }
        }
        self.phase = .spent;
        return .reward;
    }
    pub fn rewardClass(self: State) []const u8 {
        return if (self.kind == .wood)
            ([_][]const u8{ "item_power_boost", "item_attack_boost", "item_acro_boost", "item_speed_boost", "item_vita_boost" })[self.reward]
        else
            ([_][]const u8{ "item_goldensoul", "item_wraithorb", "item_megashield", "item_invincibility" })[self.reward];
    }
};
test "chests consume use once, choose trap at opening, and delay black rewards" {
    const t = std.testing;
    var wood: State = .{ .kind = .wood, .stepped_ms = 0 };
    try t.expect(wood.use(7, 100, 0));
    try t.expect(!wood.use(8, 200, 99));
    try t.expectEqual(.none, wood.advance(1899, 4));
    try t.expectEqual(.reward, wood.advance(1900, 4));
    try t.expectEqualStrings("item_vita_boost", wood.rewardClass());
    try t.expectEqual(.none, wood.advance(3000, 0));
    var trap: State = .{ .kind = .black, .stepped_ms = 0 };
    _ = trap.use(7, 100, 49);
    try t.expectEqual(.explode, trap.advance(1100, 99));
    try t.expectEqual(.none, trap.advance(1399, 0));
    try t.expectEqual(.remove, trap.advance(1400, 0));
    try t.expectEqual(.none, trap.advance(1500, 0));
    var safe: State = .{ .kind = .black, .stepped_ms = 0 };
    _ = safe.use(7, 100, 50);
    try t.expectEqual(.reveal, safe.advance(1900, 2));
    var restored = safe;
    try t.expectEqual(.none, restored.advance(3399, 0));
    try t.expectEqual(.reward, restored.advance(3400, 0));
    try t.expectEqualStrings("item_megashield", restored.rewardClass());
    try t.expectEqual(@as(i32, 19), restored.frame(10000));
}
