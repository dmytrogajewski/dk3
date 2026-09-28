// SPDX-License-Identifier: GPL-2.0-or-later
//! Worker fear owns its poses, retreat deadline and vocal choices.
const std = @import("std");
pub const retreat_ms = 10000;
pub const cower_ms = 10000;
pub const retry_distance = 300;
pub const cower_poses = [_][]const u8{ "gamba", "gambc" };
pub fn owns(classname: []const u8) bool {
    return std.mem.eql(u8, classname, "monster_skinnyworker") or std.mem.eql(u8, classname, "monster_fatworker");
}
pub fn skinny(classname: []const u8) bool {
    return std.mem.eql(u8, classname, "monster_skinnyworker");
}
pub fn voice(thin: bool, chance: f32, choice: f32) ?[]const u8 {
    if (chance <= 0.5) return null;
    return if (choice > 0.75) "e1/Man_snifs.wav" else if (choice > 0.45) "e1/skinnydeath.wav" else if (thin) "e1/skinnydeath2.wav" else "e1/Man_snifs.wav";
}
pub const State = struct {
    phase: enum { calm, retreat, cower } = .calm,
    started_ms: i64 = 0,
    retry_ms: i64 = 0,
    voice_pending: bool = false,
    variant: u1 = 0,
    pub fn start(self: *State, now: i64) void {
        self.phase = .retreat;
        self.started_ms = now;
        self.voice_pending = true;
    }
    pub fn stop(self: *State, now: i64) void {
        self.phase = .cower;
        self.started_ms = now;
        self.retry_ms = now + cower_ms;
    }
};
test "worker retreat ends in cowering and vocals retain class choices" {
    var state: State = .{};
    state.start(100);
    state.stop(200);
    try std.testing.expect(state.phase == .cower);
    try std.testing.expectEqual(@as(i64, 10200), state.retry_ms);
    try std.testing.expect(voice(true, 0.5, 0.8) == null);
    try std.testing.expectEqualStrings("e1/skinnydeath2.wav", voice(true, 0.9, 0.4).?);
    try std.testing.expectEqualStrings("e1/Man_snifs.wav", voice(false, 0.9, 0.4).?);
}
