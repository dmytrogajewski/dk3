// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc", "atakd", "speciala", "diea" };
pub const melt_tag = 10019;
pub const State = struct {
    phase: enum { living, coffin, melting, melted, unmelting, collapsed, rising, terminal } = .living,
    started_ms: i64 = 0,
    until_ms: i64 = 0,
    alpha: f32 = 1,
    pub fn invulnerable(self: State) bool {
        return self.phase == .melting or self.phase == .melted or self.phase == .unmelting;
    }
    pub fn resurrecting(self: State) bool {
        return self.phase == .collapsed or self.phase == .rising;
    }
    /// The first lethal hit begins resurrection. A subsequent lethal hit during
    /// that goal finishes the actor; nonlethal interruption retains one health.
    pub fn damage(self: *State, health: *i32, self_kill: bool, now: i64) bool {
        if (health.* > 0) {
            if (self.resurrecting()) health.* = 1;
            return false;
        }
        if (self.resurrecting() or self_kill) {
            self.phase = .terminal;
            return true;
        }
        self.phase = .collapsed;
        self.started_ms = now;
        self.until_ms = now + 10000;
        health.* = 1;
        return false;
    }
};
test "buboid first lethal hit resurrects, another during that goal is terminal" {
    const t = @import("std").testing;
    var state: State = .{};
    var health: i32 = -200;
    try t.expect(!state.damage(&health, false, 100));
    try t.expectEqual(@as(i32, 1), health);
    try t.expectEqual(@as(i64, 10100), state.until_ms);
    var restored = state;
    health = 0;
    try t.expect(restored.damage(&health, false, 500));
    try t.expect(restored.phase == .terminal);
    state.phase = .rising;
    health = 99;
    try t.expect(!state.damage(&health, false, 12000));
    try t.expectEqual(@as(i32, 1), health);
}
