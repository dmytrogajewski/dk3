// SPDX-License-Identifier: GPL-2.0-or-later
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakd", "drop", "jumpa" };
pub const State = struct {
    phase: enum { chase, descend, land, retreat, leap, attack } = .chase,
    flying: bool = true,
    started_ms: i64 = 0,
    until_ms: ?i64 = null,
    destination: [3]f32 = @splat(0),
    previous: [3]f32 = @splat(0),
    blocked: u8 = 0,
};
pub fn wantsLeap(distance: f32, roll: f32) bool {
    return distance > 150 and distance < 300 and roll < 0.25;
}
test "griffon ground leap uses the authored open interval" {
    const t = @import("std").testing;
    try t.expect(!wantsLeap(150, 0));
    try t.expect(wantsLeap(151, 0.24));
    try t.expect(!wantsLeap(299, 0.25));
    try t.expect(!wantsLeap(300, 0));
}
