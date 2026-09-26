// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied DKF glyph metrics. Layout uses pixels, independent of either UI renderer.
const std = @import("std");
pub const Metrics = struct {
    height: u16,
    widths: [256]u8,
    x: [256]u8,
    y: [256]u8,
    pub fn parse(bytes: []const u8, image_width: u16, image_height: u16) !Metrics {
        if (bytes.len < 780 or !std.mem.eql(u8, bytes[0..4], "dkf ") or std.mem.readInt(u32, bytes[4..8], .little) != 0) return error.InvalidFont;
        const height = std.mem.readInt(u32, bytes[8..12], .little);
        if (height == 0 or height > 256 or image_width == 0 or image_height == 0) return error.InvalidFontDimensions;
        const result: Metrics = .{ .height = @intCast(height), .widths = bytes[12..268].*, .x = bytes[268..524].*, .y = bytes[524..780].* };
        for (result.widths, result.x, result.y) |glyph_width, x, y| if (glyph_width != 0 and (@as(u32, x) + glyph_width > image_width or @as(u32, y) + height > image_height)) return error.InvalidGlyphBounds;
        return result;
    }
    pub fn advance(self: Metrics, char: u8, scale: f32) f32 {
        return (if (char == ' ') @as(f32, @floatFromInt(self.height)) * 0.5 else if (self.widths[char] > 0) @as(f32, @floatFromInt(self.widths[char])) + 1 else 0) * scale;
    }
    pub fn width(self: Metrics, text: []const u8, scale: f32) f32 {
        var result: f32 = 0;
        for (text) |char| {
            if (char == '\n') break;
            result += self.advance(char, scale);
        }
        return result;
    }
};
test "glyph bounds are checked and text measurement matches advances" {
    var bytes: [780]u8 = @splat(0);
    @memcpy(bytes[0..4], "dkf ");
    std.mem.writeInt(u32, bytes[8..12], 16, .little);
    bytes[12 + 'A'] = 8;
    const font = try Metrics.parse(&bytes, 128, 64);
    try std.testing.expectEqual(@as(f32, 52), font.width("A A", 2));
    bytes[268 + 'A'] = 125;
    try std.testing.expectError(error.InvalidGlyphBounds, Metrics.parse(&bytes, 128, 64));
}
