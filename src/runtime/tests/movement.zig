// SPDX-License-Identifier: GPL-2.0-or-later
//! Differential command replays against bundled GPL movement, using identical traces.
const std = @import("std");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const bridge = @import("../engine/player_state.zig");
const move = @import("../domain/player_move.zig");
const collision = @import("../domain/collision.zig");
const v = @import("../domain/vector.zig");
extern fn reference_move(*c.playerState_t, c.usercmd_t, *const fn ([*c]c.trace_t, [*c]const f32, [*c]const f32, [*c]const f32, [*c]const f32, c_int, c_int) callconv(.c) void, *const fn ([*c]const f32, c_int) callconv(.c) c_int) void;
fn plane(start: v.Vec3, mins: v.Vec3, end: v.Vec3) collision.Trace {
    const a = start[2] + mins[2];
    const b = end[2] + mins[2];
    if (a < 0) return .{ .fraction = 0, .end = start, .normal = .{ 0, 0, 1 }, .start_solid = true, .all_solid = b < 0, .entity = 2046 };
    if (b >= 0) return .{ .fraction = 1, .end = end, .normal = .{ 0, 0, 1 } };
    const fraction = a / (a - b);
    return .{ .fraction = fraction, .end = v.add(start, v.scale(v.add(end, v.scale(start, -1)), fraction)), .normal = .{ 0, 0, 1 }, .entity = 2046 };
}
fn referenceTrace(out: [*c]c.trace_t, start: [*c]const f32, mins: [*c]const f32, _: [*c]const f32, end: [*c]const f32, _: c_int, _: c_int) callconv(.c) void {
    const hit = plane(start[0..3].*, mins[0..3].*, end[0..3].*);
    out[0] = std.mem.zeroes(c.trace_t);
    out[0].fraction = hit.fraction;
    out[0].endpos = hit.end;
    out[0].plane.normal = hit.normal;
    out[0].allsolid = @intFromBool(hit.all_solid);
    out[0].startsolid = @intFromBool(hit.start_solid);
    out[0].entityNum = hit.entity;
}
var water_surface: ?f32 = null;
fn referenceContents(point: [*c]const f32, _: c_int) callconv(.c) c_int {
    return if (water_surface) |surface| (if (point[2] < surface) c.CONTENTS_WATER else 0) else 0;
}
fn trace(_: *anyopaque, request: collision.Request) !collision.Trace {
    return plane(request.start, request.mins, request.end);
}
fn contents(_: *anyopaque, point: v.Vec3, _: u16) !u32 {
    return @intCast(referenceContents(&point, 0));
}
test "walking swimming diagonal crouch jump and gravity follow bundled movement" {
    var context: u8 = 0;
    defer water_surface = null;
    for ([_]?f32{ null, 16, 80 }) |surface| {
        water_surface = surface;
        for ([_]i8{ 0, 127 }) |strafe| {
            var reference = std.mem.zeroes(c.playerState_t);
            reference.origin = .{ 0, 0, 24 };
            reference.stats[c.STAT_HEALTH] = 100;
            reference.speed = 320;
            reference.gravity = 800;
            reference.groundEntityNum = c.ENTITYNUM_NONE;
            reference.viewheight = 22;
            var player = bridge.read(&reference);
            var motion: @import("../domain/slide.zig").State = .{ .position = reference.origin, .velocity = reference.velocity };
            var delta: [3]i32 = @splat(0);
            for (0..240) |frame| {
                var cmd = std.mem.zeroes(c.usercmd_t);
                cmd.serverTime = @intCast((frame + 1) * 16);
                cmd.forwardmove = if (frame < 180) 127 else 0;
                cmd.rightmove = strafe;
                cmd.upmove = if (frame >= 40 and frame < 80) -127 else if (frame >= 100 and frame < 120) 127 else 0;
                reference_move(&reference, cmd, referenceTrace, referenceContents);
                _ = try move.run(&player, &motion, bridge.command(cmd, &delta), bridge.parameters(0), .{ .context = &context, .trace_fn = trace, .contents_fn = contents });
                for (0..3) |axis| {
                    if (@abs(reference.origin[axis] - motion.position[axis]) > 0.05 or @abs(reference.velocity[axis] - motion.velocity[axis]) > 0.05)
                        std.debug.print("movement mismatch frame={d} strafe={d} axis={d} reference={d}/{d} zig={d}/{d}\n", .{ frame, strafe, axis, reference.origin[axis], reference.velocity[axis], motion.position[axis], motion.velocity[axis] });
                    try std.testing.expectApproxEqAbs(reference.origin[axis], motion.position[axis], 0.05);
                    try std.testing.expectApproxEqAbs(reference.velocity[axis], motion.velocity[axis], 0.05);
                }
                try std.testing.expectEqual(reference.viewheight, @as(i32, @intFromFloat(player.view_height)));
            }
        }
    }
}
