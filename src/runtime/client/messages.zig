// SPDX-License-Identifier: GPL-2.0-or-later
//! Bounded player-facing server notices and chat, independent of cinematic audio.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const canvas = @import("../engine/canvas.zig");
const draw: canvas.Canvas(.client) = .{ .gateway = &engine.gateway };
var center: [1024]u8 = @splat(0);
var center_until: i64 = 0;
var lines: [8]struct { text: [256]u8 = @splat(0), until: i64 = 0 } = @splat(.{});
pub fn reset() void {
    center_until = 0;
    lines = @splat(.{});
}
pub fn command(now: i64) void {
    var name: [32]u8 = @splat(0);
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 0), &name, @as(isize, name.len) });
    const token = std.mem.sliceTo(&name, 0);
    if (std.mem.eql(u8, token, "cp")) {
        @memset(&center, 0);
        _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 1), &center, @as(isize, center.len) });
        center_until = now + 6000;
    } else if (std.mem.eql(u8, token, "chat") or std.mem.eql(u8, token, "tchat")) {
        for (0..lines.len - 1) |i| lines[i] = lines[i + 1];
        const line = &lines[lines.len - 1];
        line.* = .{ .until = now + 8000 };
        _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 1), &line.text, @as(isize, line.text.len) });
    } else if (std.mem.eql(u8, token, "print")) {
        var text: [1024:0]u8 = @splat(0);
        _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 1), &text, @as(isize, text.len) });
        engine.print(std.mem.sliceTo(&text, 0));
    }
}
pub fn render(font: canvas.Font, display: c.glconfig_t, now: i64) void {
    const scale: f32 = @as(f32, @floatFromInt(display.vidHeight)) / 600;
    if (now < center_until) {
        var rows = std.mem.splitScalar(u8, std.mem.sliceTo(&center, 0), '\n');
        var y: f32 = @as(f32, @floatFromInt(display.vidHeight)) * 0.30;
        while (rows.next()) |row| {
            draw.text(font, (@as(f32, @floatFromInt(display.vidWidth)) - font.metrics.width(row, scale)) * 0.5, y, scale, row, canvas.white);
            y += @as(f32, @floatFromInt(font.metrics.height + 3)) * scale;
        }
    }
    var y: f32 = 32 * scale;
    for (lines) |line| if (now < line.until) {
        draw.text(font, 16 * scale, y, scale * 0.75, std.mem.sliceTo(&line.text, 0), canvas.white);
        y += @as(f32, @floatFromInt(font.metrics.height + 3)) * scale * 0.75;
    };
}
