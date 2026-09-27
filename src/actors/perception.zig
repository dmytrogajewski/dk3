// SPDX-License-Identifier: GPL-2.0-or-later
//! Close enemies are heard outside the view cone; pods detect horizontal proximity.
const std = @import("std");
pub fn distance(kind: @import("catalog.zig").Kind, offset: [3]f32) f32 {
    return @sqrt(offset[0] * offset[0] + offset[1] * offset[1] + if (kind == .protopod) @as(f32, 0) else offset[2] * offset[2]);
}
pub fn inCone(kind: @import("catalog.zig").Kind, player: bool, horizontal: f32, dot: f32, fov: f32) bool {
    return kind == .protopod or !player or horizontal < 256 or dot >= @cos(fov * std.math.pi / 360);
}
test "pods see by horizontal range and nearby players do not require facing" {
    const t = std.testing;
    try t.expectEqual(@as(f32, 100), distance(.protopod, .{ 100, 0, 800 }));
    try t.expect(distance(.crox, .{ 100, 0, 800 }) > 800);
    try t.expect(inCone(.protopod, true, 500, -1, 90));
    try t.expect(inCone(.crox, true, 128, -1, 90));
    try t.expect(!inCone(.crox, true, 300, -1, 90));
    try t.expect(inCone(.mishima_guard, true, 300, 1, 90));
    try t.expect(inCone(.mishima_guard, false, 300, -1, 90));
}
