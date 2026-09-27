// SPDX-License-Identifier: GPL-2.0-or-later
//! VenomVermin's bite, short leap and accelerating missile.
pub const attacks = [_][]const u8{ "ataka", "runa", "atakc", "atakd" };
pub const State = struct { ready_ms: i64 = 0 };
pub const Rocket = struct {
    damage: f32,
    speed: f32,
    divisor: u3 = 7,
    next_ms: i64,
    frame: u2 = 0,
};
pub const model = "models/e4/me_missile.dkm";
pub const glow = "models/global/e_sflorange.sp2";
pub const render_tag = 10007;
pub fn select(distance: f32) ?u3 {
    return if (distance <= 40) 0 else if (distance <= 192) 1 else if (distance <= 400) 2 else null;
}
pub fn accelerate(rocket: *Rocket) void {
    if (rocket.divisor > 1) rocket.divisor -= 1;
    rocket.frame = @intCast((@as(u3, rocket.frame) + 1) % 3);
    rocket.next_ms += 100;
}
test "Vermin attack bands and six acceleration steps keep authored boundaries" {
    const t = @import("std").testing;
    try t.expectEqual(@as(?u3, 0), select(40));
    try t.expectEqual(@as(?u3, 1), select(192));
    try t.expectEqual(@as(?u3, 2), select(400));
    try t.expectEqual(@as(?u3, null), select(401));
    var rocket: Rocket = .{ .damage = 10, .speed = 450, .next_ms = 10 };
    for (0..6) |_| accelerate(&rocket);
    try t.expectEqual(@as(u3, 1), rocket.divisor);
    try t.expectEqual(@as(i64, 610), rocket.next_ms);
    try t.expectEqual(@as(u2, 0), rocket.frame);
    accelerate(&rocket);
    try t.expectEqual(@as(u3, 1), rocket.divisor);
}
