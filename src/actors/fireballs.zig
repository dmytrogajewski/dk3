// SPDX-License-Identifier: GPL-2.0-or-later
//! The authored fireball callback is shared by Knight1, Doombat and Dragon.
pub const Kind = enum { knight, doombat, dragon };
pub const State = struct { kind: Kind, damage: f32, drift_ms: i64 };
pub const model = "models/e3/we_fball.dkm";
pub const render_tag = 10015;
pub fn scale(kind: Kind) f32 {
    return if (kind == .doombat) 0.15 else 1;
}
pub fn pulses(kind: Kind) u3 {
    return if (kind == .doombat) 1 else 5;
}
test "only full-sized authored fireballs add the four secondary pulses" {
    const t = @import("std").testing;
    try t.expectEqual(@as(u3, 1), pulses(.doombat));
    try t.expectEqual(@as(u3, 5), pulses(.knight));
    try t.expectEqual(@as(u3, 5), pulses(.dragon));
}
