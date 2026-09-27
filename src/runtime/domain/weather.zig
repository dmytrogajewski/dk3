// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const v = @import("vector.zig");
pub const render_tag = 10040;
pub const Kind = enum(u8) { rain, snow };
pub const State = struct { kind: Kind, flags: u32, mins: v.Vec3, maxs: v.Vec3 };
pub fn velocity(kind: Kind, flags: u32, roll: u32) v.Vec3 {
    if (kind == .snow) return .{ 0, 0, -50 - @as(f32, @floatFromInt(roll & 10)) };
    return .{ if (flags & 3 == 0 and flags & 4 != 0) @as(f32, 300) else if (flags & 7 == 0 and flags & 8 != 0) -300 else 0, if (flags & 1 != 0) @as(f32, 300) else if (flags & 2 != 0) -300 else 0, -400 };
}
pub fn capacity(kind: Kind, width: i32, depth: i32, distance: f32) u32 {
    if (width <= 0 or depth <= 0) return 0;
    const area = @as(u64, @intCast(width)) * @as(u64, @intCast(depth));
    return @intCast(@min(4096, if (kind == .snow) area >> 12 else @as(u64, @intFromFloat(@as(f64, @floatFromInt(area)) * (if (distance < 512) @as(f64, 0.01) else 0.005)))));
}
pub fn births(kind: Kind, maximum: u32, active: u32) u32 {
    if (active >= maximum) return 0;
    const count = if (active < maximum >> 2) maximum >> (if (kind == .snow) @as(u5, 1) else 2) else 1;
    return @min(count, maximum - active);
}
pub fn cornerDistance(state: State, eye: v.Vec3, forward: v.Vec3) ?f32 {
    const limit: f32 = if (state.kind == .rain) 512 else 1024;
    var closest = limit;
    for ([_][2]f32{ .{ state.mins[0], state.mins[1] }, .{ state.mins[0], state.maxs[1] }, .{ state.maxs[0], state.mins[1] }, .{ state.maxs[0], state.maxs[1] } }) |corner| {
        const offset: v.Vec3 = .{ corner[0] - eye[0], corner[1] - eye[1], 0 };
        if (v.dot(forward, offset) >= 0) closest = @min(closest, v.length(offset));
    }
    return if (closest < limit) closest else null;
}

test "weather densities, fill thresholds and directional flag priority remain distinct" {
    const t = std.testing;
    try t.expectEqual(@as(u32, 16), capacity(.snow, 256, 256, 0));
    try t.expectEqual(@as(u32, 655), capacity(.rain, 256, 256, 0));
    try t.expectEqual(@as(u32, 327), capacity(.rain, 256, 256, 512));
    try t.expectEqual(@as(u32, 8), births(.snow, 16, 0));
    try t.expectEqual(@as(u32, 1), births(.snow, 16, 4));
    try t.expectEqual(@as(u32, 0), births(.snow, 16, 16));
    try t.expectEqual(v.Vec3{ 0, 300, -400 }, velocity(.rain, 15, 0));
    try t.expectEqual(v.Vec3{ -300, 0, -400 }, velocity(.rain, 8, 0));
}
