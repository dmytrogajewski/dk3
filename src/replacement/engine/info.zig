// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
pub fn get(text: []const u8, name: []const u8) ?[]const u8 {
    var fields = std.mem.splitScalar(u8, if (text.len > 0 and text[0] == '\\') text[1..] else text, '\\');
    while (fields.next()) |key| {
        const value = fields.next() orelse return null;
        if (std.mem.eql(u8, key, name)) return value;
    }
    return null;
}
