// SPDX-License-Identifier: GPL-2.0-or-later
//! Engine-independent inventory transitions shared by native runtimes.
const std = @import("std");
pub const Policy = struct { maximum: i32, auto_select: bool };
/// The caller validates the weapon registry and applies weapon-specific acquisition effects.
/// Returning false leaves all state unchanged.
pub fn acquire(owned: *u32, ammunition: []i32, selected: *i32, id: u5, rounds: i32, policy: Policy) bool {
    if (id == 0 or id >= ammunition.len or policy.maximum < 0) return false;
    const mask = @as(u32, 1) << id;
    const already_owned = owned.* & mask != 0;
    if (already_owned and (policy.maximum == 0 or ammunition[id] >= policy.maximum)) return false;
    owned.* |= mask;
    // Widen before addition: a malformed large pickup count must not wrap ammunition.
    ammunition[id] = @intCast(@min(@as(i64, policy.maximum), @as(i64, ammunition[id]) + @max(0, @as(i64, rounds))));
    if (!already_owned and policy.auto_select) selected.* = id;
    return true;
}

pub const Inventory = struct {
    owned: u32 = 0,
    ammunition: [32]i32 = @splat(0),
    selected: i32 = 0,
    pub fn add(self: *Inventory, id: u5, rounds: i32, policy: Policy) bool {
        return acquire(&self.owned, &self.ammunition, &self.selected, id, rounds, policy);
    }
};

test "pickup ownership, saturation and selection share one transition" {
    var state: Inventory = .{};
    try std.testing.expect(state.add(2, 10, .{ .maximum = 100, .auto_select = true }));
    try std.testing.expectEqual(@as(i32, 2), state.selected);
    state.selected = 1;
    try std.testing.expect(state.add(2, std.math.maxInt(i32), .{ .maximum = 100, .auto_select = true }));
    try std.testing.expectEqual(@as(i32, 100), state.ammunition[2]);
    try std.testing.expectEqual(@as(i32, 1), state.selected);
    const before = state;
    try std.testing.expect(!state.add(2, 10, .{ .maximum = 100, .auto_select = true }));
    try std.testing.expectEqualDeep(before, state);
    try std.testing.expect(state.add(3, -10, .{ .maximum = 0, .auto_select = false }));
    try std.testing.expect(!state.add(3, 0, .{ .maximum = 0, .auto_select = true }));
    try std.testing.expectEqual(@as(i32, 0), state.ammunition[3]);
}
