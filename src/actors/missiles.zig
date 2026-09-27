// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared rocket flight, with class-owned launch and presentation contracts.
pub const Kind = enum { vermin, battleboar, rocketdude, mp_left, mp_right };
pub const Rocket = struct {
    kind: Kind,
    damage: f32,
    speed: f32,
    divisor: u3 = 7,
    next_ms: i64,
    frame: u2 = 0,
};
pub const render_tag = 10007;
pub fn lifetime(kind: Kind) i64 {
    return if (kind == .battleboar) 5000 else 4000;
}
pub fn model(kind: Kind) []const u8 {
    return if (kind == .battleboar) "models/e1/we_swrocket.dkm" else "models/e4/me_missile.dkm";
}
pub fn modelScale(kind: Kind) f32 {
    return switch (kind) {
        .battleboar => 0.65,
        .vermin => 1,
        .rocketdude => 2,
        .mp_left, .mp_right => 0.75,
    };
}
pub fn glow(kind: Kind) []const u8 {
    return if (kind == .battleboar) "models/global/e_sflred.sp2" else "models/global/e_sflorange.sp2";
}
pub fn accelerate(rocket: *Rocket) void {
    if (rocket.kind == .battleboar) return;
    if (rocket.divisor > 1) rocket.divisor -= 1;
    rocket.frame = @intCast((@as(u3, rocket.frame) + 1) % 3);
    rocket.next_ms += 100;
}
test "boar expires at full speed; gang and vermin accelerate" {
    const t = @import("std").testing;
    var rocket: Rocket = .{ .kind = .vermin, .damage = 10, .speed = 450, .next_ms = 10 };
    for (0..6) |_| accelerate(&rocket);
    try t.expectEqual(@as(u3, 1), rocket.divisor);
    try t.expectEqual(@as(i64, 610), rocket.next_ms);
    try t.expectEqual(@as(u2, 0), rocket.frame);
    try t.expectEqual(@as(i64, 5000), lifetime(.battleboar));
    try t.expectEqual(@as(i64, 4000), lifetime(.rocketdude));
}
