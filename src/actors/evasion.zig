// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored evasive actions; the ground side-step helper reserves 44 units.
pub const Kind = enum { sidestep, strafe, dodge };
pub const State = struct {
    until_ms: ?i64 = null,
    destination: [3]f32 = @splat(0),
    kind: Kind = .sidestep,
    yaw: f32 = 0,
};
pub fn distance(requested: f32) f32 {
    return requested - 44;
}
pub fn choose(ranged: bool, sniper: bool, branch: f32, side: f32) Kind {
    if (ranged and !sniper and branch >= 0.5) return .dodge;
    return if (side > 0.5) .strafe else .sidestep;
}
test "evasive distances reserve hull clearance once" {
    const t = @import("std").testing;
    try t.expectEqual(@as(f32, 52), distance(96));
    try t.expectEqual(@as(f32, 36), distance(80));
    try t.expectEqual(@as(f32, 84), distance(128));
    try t.expectEqual(Kind.dodge, choose(true, false, 0.8, 0.8));
    try t.expectEqual(Kind.strafe, choose(true, true, 0.8, 0.8));
}
