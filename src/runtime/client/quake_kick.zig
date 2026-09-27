// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const v = @import("../domain/vector.zig");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
var started: ?i64 = null;
var angles: v.Vec3 = @splat(0);
pub fn reset() void { started = null; angles = @splat(0); }
pub fn command() void {
    var buffer: [128]u8 = @splat(0);
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 0), &buffer, @as(isize, buffer.len) });
    if (!std.mem.eql(u8, std.mem.sliceTo(&buffer, 0), "dk3_quake_kick")) return;
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 1), &buffer, @as(isize, buffer.len) });
    const at = std.fmt.parseInt(i64, std.mem.sliceTo(&buffer, 0), 10) catch return;
    var kick: v.Vec3 = undefined;
    for (&kick, 0..) |*axis, i| {
        _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, @intCast(i + 2)), &buffer, @as(isize, buffer.len) });
        axis.* = std.fmt.parseFloat(f32, std.mem.sliceTo(&buffer, 0)) catch return;
        if (!std.math.isFinite(axis.*) or @abs(axis.*) > 40000000) return;
    }
    started = at;
    angles = kick;
}
pub fn offset(now: i64) v.Vec3 {
    const at = started orelse return @splat(0);
    return v.scale(angles, @import("../domain/earthquake.zig").kickScale(now - at));
}
