// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const Object = @import("../domain/components.zig").MapObject;
pub fn text(object: Object, key: []const u8) ?[]const u8 {
    // Map spawning historically uses the first authored occurrence.
    for (object.properties) |property| if (std.mem.eql(u8, property.key, key)) return property.value;
    return null;
}
pub fn number(object: Object, key: []const u8, fallback: f32) !f32 {
    const value = text(object, key) orelse return fallback;
    const result = std.fmt.parseFloat(f32, value) catch return error.InvalidMapNumber;
    if (!std.math.isFinite(result) or @abs(result) > 1000000) return error.InvalidMapNumber;
    return result;
}
pub fn milliseconds(object: Object, key: []const u8, fallback: f32) !i32 {
    return @intFromFloat(try number(object, key, fallback) * 1000);
}

pub fn nonempty(object: Object, key: []const u8) bool {
    return if (text(object, key)) |value| value.len > 0 else false;
}
