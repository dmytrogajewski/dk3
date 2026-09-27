// SPDX-License-Identifier: GPL-2.0-or-later
//! Amphibious melee policy. Numeric weapon tuning belongs to supplied aidata.
const std = @import("std");
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc", "atakd" };
pub const State = struct {
    pose: u2 = 0,
    attacking: bool = false,
    struck: bool = false,
    sounded: u2 = 0,
    swimming: bool = false,
    water: u2 = 0,
    wandering: bool = false,
    death_b: bool = false,
    start: [3]f32 = @splat(0),
    destination: ?[3]f32 = null,
    started_ms: i64 = 0,
    wander_until_ms: i64 = 0,
    cycle_ms: i64 = 0,
    pub fn begin(self: *State, now: i64, random: f32) void {
        self.pose = attackPose(self.water, random);
        self.attacking = true;
        self.struck = false;
        self.sounded = 0;
        self.started_ms = now;
    }
};
pub fn attackPose(water: u2, random: f32) u2 {
    return if (water < 3) if (random < 0.666) 2 else 3 else if (random < 0.666) 1 else 0;
}
pub fn beyondHeight(vertical: f32) bool {
    return @abs(vertical) > 100;
}
pub fn facing(yaw_delta: f32) bool {
    return @abs(@mod(yaw_delta + 180, 360) - 180) < 5;
}
pub fn wanderCandidate(distance_from_start: f32, active_range: f32, horizontal: f32, vertical: f32, yaw_delta: f32, walk_speed: f32) bool {
    return !(horizontal < walk_speed * 0.2 and @abs(vertical) < 32) and distance_from_start < active_range and @abs(@mod(yaw_delta + 180, 360) - 180) <= 90;
}
test "Crox chooses four authored poses at actual water boundary and resumes within height band" {
    const t = std.testing;
    try t.expectEqual(@as(u2, 2), attackPose(2, 0.665));
    try t.expectEqual(@as(u2, 3), attackPose(2, 0.666));
    try t.expectEqual(@as(u2, 1), attackPose(3, 0.665));
    try t.expectEqual(@as(u2, 0), attackPose(3, 0.666));
    try t.expect(!beyondHeight(100));
    try t.expect(beyondHeight(-101));
    try t.expect(facing(359));
    try t.expect(!facing(5));
    try t.expect(wanderCandidate(100, 1300, 100, 0, 350, 50));
    try t.expect(!wanderCandidate(100, 1300, 5, 0, 0, 50));
    try t.expect(!wanderCandidate(1300, 1300, 100, 0, 0, 50));
    try t.expect(!wanderCandidate(100, 1300, 100, 0, 91, 50));
}
