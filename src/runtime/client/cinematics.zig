// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
var loop_sound: c.sfxHandle_t = 0;
fn argument(index: isize, buffer: []u8) []const u8 {
    @memset(buffer, 0);
    _ = engine.gateway.call(c.CG_ARGV, .{ index, buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
pub fn reset() void {
    loop_sound = 0;
}
pub fn command() !void {
    var buffer: [128]u8 = undefined;
    const name = argument(0, &buffer);
    if (std.mem.eql(u8, name, "dk3_cine_stop")) {
        reset();
        return;
    }
    if (!std.mem.eql(u8, name, "dk3_cine_sound")) return;
    const looping = std.mem.eql(u8, argument(1, &buffer), "1");
    const channel = try std.fmt.parseInt(u8, argument(2, &buffer), 10);
    const path = argument(3, &buffer);
    const handle = try engine.registerSound(path);
    if (handle == 0) {
        // Missing authored audio does not abort reference cinematic playback.
        // Keep the original path visible instead of inventing a replacement.
        var warning: [192]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&warning, "dk3 cinematic: unavailable sound={s}\n", .{path}));
        return;
    }
    if (looping) loop_sound = handle else _ = engine.gateway.call(c.CG_S_STARTLOCALSOUND, .{ @as(isize, handle), @as(isize, if (channel == 2) c.CHAN_VOICE else c.CHAN_AUTO) });
}
pub fn audio(origin: [3]f32) void {
    if (loop_sound != 0) {
        const velocity: [3]f32 = @splat(0);
        _ = engine.gateway.call(c.CG_S_ADDLOOPINGSOUND, .{ @as(isize, c.ENTITYNUM_WORLD), &origin, &velocity, @as(isize, loop_sound) });
    }
}
pub fn overlay(color: [4]f32, display: c.glconfig_t) void {
    if (color[3] <= 0) return;
    const white = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "white")});
    _ = engine.gateway.call(c.CG_R_SETCOLOR, .{&color});
    _ = engine.gateway.call(c.CG_R_DRAWSTRETCHPIC, .{ engine.floatArg(0), engine.floatArg(0), engine.floatArg(@floatFromInt(display.vidWidth)), engine.floatArg(@floatFromInt(display.vidHeight)), engine.floatArg(0), engine.floatArg(0), engine.floatArg(1), engine.floatArg(1), white });
    _ = engine.gateway.call(c.CG_R_SETCOLOR, .{@as(?*const [4]f32, null)});
}
