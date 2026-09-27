// SPDX-License-Identifier: GPL-2.0-or-later
//! Class projectile contracts; spear, arrow and rotating knife.
pub const Kind = enum { centurion, fletcher, thief, harpy };
pub fn magic(kind: Kind) bool {
    return kind == .fletcher or kind == .harpy;
}
pub const Shaft = struct {
    kind: Kind,
    damage: f32,
    phase: enum { flying, falling, resting } = .flying,
    contact_ms: ?i64 = null,
};
pub const render_tag = 10009;
pub fn model(kind: Kind) []const u8 {
    return switch (kind) {
        .centurion => "models/e2/me_spear.dkm",
        .fletcher, .harpy => "models/e3/we_bolt.dkm",
        .thief => "models/e2/me_thief.dkm",
    };
}
pub fn flightTime(kind: Kind) i64 {
    return if (magic(kind)) 10000 else 3000;
}
