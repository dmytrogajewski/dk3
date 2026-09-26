// SPDX-License-Identifier: GPL-2.0-or-later
//! Validated converted sprite dimensions and origins; no square-sprite assumption.
const std = @import("std");
pub const Frame = struct { width: u16, height: u16, origin_x: i16, origin_y: i16, shader: []const u8, additive: []const u8 };
pub const Document = struct { frames: [128]Frame = undefined, count: u8 = 0 };
pub fn parse(bytes: []const u8) !Document {
    var words = std.mem.tokenizeAny(u8, bytes, " \t\r\n\"");
    if (!std.mem.eql(u8, words.next() orelse "", "dk3_sprite") or !std.mem.eql(u8, words.next() orelse "", "1")) return error.InvalidSpriteHeader;
    const count = try std.fmt.parseInt(u8, words.next() orelse return error.InvalidSpriteCount, 10);
    if (count == 0 or count > 128) return error.InvalidSpriteCount;
    var result: Document = .{ .count = count };
    for (result.frames[0..count]) |*frame| {
        frame.* = .{
            .width = try std.fmt.parseInt(u16, words.next() orelse return error.InvalidSpriteFrame, 10),
            .height = try std.fmt.parseInt(u16, words.next() orelse return error.InvalidSpriteFrame, 10),
            .origin_x = try std.fmt.parseInt(i16, words.next() orelse return error.InvalidSpriteFrame, 10),
            .origin_y = try std.fmt.parseInt(i16, words.next() orelse return error.InvalidSpriteFrame, 10),
            .shader = words.next() orelse return error.InvalidSpriteFrame,
            .additive = words.next() orelse return error.InvalidSpriteFrame,
        };
        if (frame.width == 0 or frame.height == 0 or frame.width > 4096 or frame.height > 4096 or frame.shader.len >= 64 or frame.additive.len >= 64 or @abs(@as(i32, frame.origin_x)) > 8192 or @abs(@as(i32, frame.origin_y)) > 8192) return error.InvalidSpriteFrame;
    }
    if (words.next() != null) return error.InvalidSpriteTrailingData;
    return result;
}
test "sprite metadata retains rectangular frames and off-center origins" {
    const doc = try parse("dk3_sprite 1 1\n64 32 12 -4 \"sprite/0\" \"sprite/0@alphachannel\"\n");
    try std.testing.expectEqual(@as(u16, 64), doc.frames[0].width);
    try std.testing.expectEqual(@as(i16, -4), doc.frames[0].origin_y);
    try std.testing.expectError(error.InvalidSpriteFrame, parse("dk3_sprite 1 1 0 32 12 4 a b"));
    try std.testing.expectError(error.InvalidSpriteFrame, parse("dk3_sprite 1 2 64 32 12 4 a b"));
}
