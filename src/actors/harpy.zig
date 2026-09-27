// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb", "drop" };
pub const State = struct {
    phase: enum { chase, attack, dodge, approach_land, landing, settling, takeoff, rising } = .chase,
    flying: bool = true,
    started_ms: i64 = 0,
    ready_ms: i64 = 0,
    warmup_started_ms: i64 = 0,
    shot_ms: i64 = 0,
    until_ms: ?i64 = null,
    destination: [3]f32 = @splat(0),
};
pub fn transition(flying: bool, target_room: f32, own_room: f32) enum { none, land, fly } {
    if (flying and target_room < 250) return .land;
    if (!flying and target_room > 350 and own_room > 350) return .fly;
    return .none;
}
test "harpy room decisions keep the authored landing and takeoff hysteresis" {
    const t = @import("std").testing;
    try t.expect(transition(true, 249, 500) == .land);
    try t.expect(transition(true, 250, 500) == .none);
    try t.expect(transition(false, 351, 351) == .fly);
    try t.expect(transition(false, 350, 500) == .none);
    try t.expect(transition(false, 500, 350) == .none);
}
