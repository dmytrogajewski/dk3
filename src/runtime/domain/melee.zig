// SPDX-License-Identifier: GPL-2.0-or-later
const catalog = @import("weapon_catalog");
pub const State = struct {
    owner: u32,
    weapon: u5,
    sequence: i32,
    experience: i32,
    damage: f32,
    started_ms: i64,
    next_hit: u8 = 0,
    pub fn plan(self: State) !catalog.melee.Plan {
        return catalog.meleePlan(self.weapon, self.sequence, self.experience);
    }
    pub fn due(self: State, now: i64) !bool {
        const attack = try self.plan();
        return self.next_hit < attack.hits and now >= self.started_ms + attack.delays_ms[self.next_hit];
    }
};
test "saved melee cursors retain the second strike without replaying the first" {
    const std = @import("std");
    var state: State = .{ .owner = 1, .weapon = 8, .sequence = 1, .experience = 0, .damage = 10, .started_ms = 1000 };
    try std.testing.expect(!try state.due(1251));
    try std.testing.expect(try state.due(1252));
    state.next_hit = 1;
    try std.testing.expect(!try state.due(1647));
    try std.testing.expect(try state.due(1648));
    state.next_hit = 2;
    try std.testing.expect(!try state.due(5000));
}
