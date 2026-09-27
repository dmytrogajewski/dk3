// SPDX-License-Identifier: GPL-2.0-or-later
//! Black and white prisoners share attacks but keep distinct pain contracts.
pub const attacks = [_][]const u8{ "ataka", "atakb", "atakc", "atakd" };
pub const State = struct { ready_ms: i64 = 0, emit_ms: i64 = 0 };
pub const Rock = struct { damage: f32 };
pub const rock_model = "models/global/e_rock3.dkm";
pub const render_tag = 10011;
pub fn inRange(distance: f32, melee: f32, roll: f32) bool {
    return distance <= melee or (distance >= 350 and distance <= 500 and roll < 0.1);
}
pub fn select(distance: f32, melee: f32, roll: f32) u3 {
    if (distance >= (350 + melee) * 0.5) return 3;
    return if (roll < 0.33) 0 else if (roll < 0.666) 1 else 2;
}
test "prisoner throws use the reviewed closed distance band" {
    const t = @import("std").testing;
    try t.expect(inRange(64, 64, 1));
    try t.expect(!inRange(349, 64, 0));
    try t.expect(inRange(350, 64, 0));
    try t.expect(inRange(500, 64, 0));
    try t.expect(!inRange(501, 64, 0));
    try t.expect(!inRange(400, 64, 0.1));
}
