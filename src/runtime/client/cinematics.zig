// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
var loop_sound: c.sfxHandle_t = 0;
var channels: [256]bool = @splat(false);
pub var boundary: u32 = 0;
fn cut() void {
    loop_sound = 0;
    boundary +%= 1;
}
fn argument(index: isize, buffer: []u8) []const u8 {
    @memset(buffer, 0);
    _ = engine.gateway.call(c.CG_ARGV, .{ index, buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
pub fn reset() void {
    cut();
    for (&channels, 0..) |*playing, channel| if (playing.*) {
        _ = engine.gateway.call(c.CG_DK3_STOP_LOCAL_SOUND_V1, .{@as(isize, @intCast(32 + channel))});
        playing.* = false;
    };
}
pub fn command() !void {
    var buffer: [128]u8 = undefined;
    const name = argument(0, &buffer);
    if (std.mem.eql(u8, name, "dk3_cine_cut")) {
        cut();
        return;
    }
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
    if (looping) loop_sound = handle else if (std.mem.endsWith(u8, path, ".mp3")) {
        // Authored streams replace their channel and survive camera cuts.
        channels[channel] = true;
        _ = engine.gateway.call(c.CG_S_STARTLOCALSOUND, .{ @as(isize, handle), @as(isize, 32) + channel });
    } else _ = engine.gateway.call(c.CG_S_STARTLOCALSOUND, .{ @as(isize, handle), @as(isize, c.CHAN_AUTO) });
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

test "camera cuts retain dialogue; completion stops only cinematic stream channels" {
    const t = std.testing;
    const Capture = struct {
        var stops: usize = 0;
        var channel: isize = 0;
        fn syscall(operation: isize, ...) callconv(.c) isize {
            std.debug.assert(operation == c.CG_DK3_STOP_LOCAL_SOUND_V1);
            var args = @cVaStart();
            defer @cVaEnd(&args);
            channel = @cVaArg(&args, isize);
            stops += 1;
            return 0;
        }
    };
    const saved_gateway = engine.gateway;
    defer engine.gateway = saved_gateway;
    engine.gateway.bind(Capture.syscall);
    channels[2] = true;
    loop_sound = 123;
    const previous = boundary;
    cut();
    try t.expect(channels[2]);
    try t.expectEqual(@as(usize, 0), Capture.stops);
    try t.expectEqual(@as(c.sfxHandle_t, 0), loop_sound);
    try t.expectEqual(previous +% 1, boundary);
    reset();
    try t.expect(!channels[2]);
    try t.expectEqual(@as(usize, 1), Capture.stops);
    try t.expectEqual(@as(isize, 34), Capture.channel);
    reset();
    try t.expectEqual(@as(usize, 1), Capture.stops);
}
