// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared metadata also consumed by the legacy C presentation and item code.
const std = @import("std");
const Pair = struct { name: []const u8, value: []const u8 };
fn count(comptime bytes: []const u8) usize {
    @setEvalBranchQuota(100000);
    var n: usize = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, "DK_")) {
        n += 1;
    };
    return n;
}
fn read(comptime bytes: []const u8) [count(bytes)]Pair {
    @setEvalBranchQuota(100000);
    var result: [count(bytes)]Pair = undefined;
    var i: usize = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "DK_")) continue;
        var fields = std.mem.splitScalar(u8, line, '"');
        _ = fields.next();
        const name = fields.next().?;
        _ = fields.next();
        result[i] = .{ .name = name, .value = fields.next().? };
        i += 1;
    }
    return result;
}
pub const keys = read(@embedFile("keys.def"));
pub const models = read(@embedFile("models.def"));
pub fn keyIndex(name: []const u8) ?u5 {
    for (keys, 0..) |key, index| if (std.ascii.eqlIgnoreCase(key.name, name)) return @intCast(index);
    return null;
}
pub fn model(name: []const u8) ?[]const u8 {
    for (models) |entry| if (std.mem.eql(u8, entry.name, name)) return entry.value;
    return null;
}
pub const Keys = struct {
    mask: u32 = 0,
    quest: u32 = 0,
    /// Bomb assembly consumes its four parts; all other keys remain reusable.
    pub fn collect(self: *Keys, index: u5) bool {
        self.mask |= @as(u32, 1) << index;
        const parts: u32 = 0x0003c000;
        if (self.mask & parts != parts) return false;
        self.mask &= ~parts;
        self.quest |= 1;
        return true;
    }
    pub fn has(self: Keys, name: []const u8) bool {
        if (std.mem.eql(u8, name, "item_bomb")) return self.quest & 1 != 0;
        if (std.mem.eql(u8, name, "item_purifier")) return self.mask & 0xfe000000 == 0xfe000000;
        if (std.mem.eql(u8, name, "item_purifier_shard2")) return self.mask & 0x7c000000 == 0x7c000000;
        const index = keyIndex(name) orelse return false;
        return self.mask & (@as(u32, 1) << index) != 0;
    }
};
test "key identities, bomb consumption and complete purifier parts" {
    try std.testing.expectEqual(@as(usize, 32), keys.len);
    var inventory: Keys = .{};
    for ([_][]const u8{ "item_charcoal", "item_saltpeter", "item_sulphur" }) |name| try std.testing.expect(!inventory.collect(keyIndex(name).?));
    try std.testing.expect(inventory.collect(keyIndex("item_bottle").?));
    try std.testing.expect(inventory.has("item_bomb") and !inventory.has("item_bottle"));
    for (25..31) |index| {
        _ = inventory.collect(@intCast(index));
    }
    try std.testing.expect(inventory.has("item_purifier_shard2") and !inventory.has("item_purifier"));
    _ = inventory.collect(31);
    try std.testing.expect(inventory.has("item_purifier"));
}
