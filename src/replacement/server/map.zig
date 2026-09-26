// SPDX-License-Identifier: GPL-2.0-or-later
//! Map parsing is independent of entity behavior registration.
const std = @import("std");
const components = @import("../domain/components.zig");
pub const Object = struct {
    binding: components.MapObject = .{ .classname = "" },
    transform: components.Transform = .{},
};
pub fn vector(text: []const u8) ![3]f32 {
    var iterator = std.mem.tokenizeAny(u8, text, " \t\r\n");
    var result: [3]f32 = undefined;
    for (&result) |*value| {
        value.* = try std.fmt.parseFloat(f32, iterator.next() orelse return error.InvalidVector);
        if (!std.math.isFinite(value.*)) return error.InvalidVector;
    }
    if (iterator.next() != null) return error.InvalidVector;
    return result;
}
pub fn read(allocator: std.mem.Allocator, source: anytype) !?Object {
    var buffer: [4096]u8 = undefined;
    const first = source.token(&buffer) orelse return null;
    if (!std.mem.eql(u8, first, "{")) return error.ExpectedEntity;
    var result: Object = .{};
    var properties: std.ArrayList(components.Property) = .empty;
    defer properties.deinit(allocator);
    errdefer for (properties.items) |property| {
        allocator.free(property.key);
        allocator.free(property.value);
    };
    while (true) {
        const key_view = source.token(&buffer) orelse return error.UnterminatedEntity;
        if (std.mem.eql(u8, key_view, "}")) break;
        if (key_view.len == 0 or key_view.len >= 64 or properties.items.len == 256) return error.EntityFieldLimit;
        var key_buffer: [64]u8 = undefined;
        @memcpy(key_buffer[0..key_view.len], key_view);
        const key = key_buffer[0..key_view.len];
        const value = source.token(&buffer) orelse return error.MissingValue;
        if (std.mem.eql(u8, value, "}")) return error.MissingValue;
        const owned = blk: {
            const owned_key = try allocator.dupe(u8, key);
            errdefer allocator.free(owned_key);
            const owned_value = try allocator.dupe(u8, value);
            errdefer allocator.free(owned_value);
            try properties.append(allocator, .{ .key = owned_key, .value = owned_value });
            break :blk owned_value;
        };
        if (std.mem.eql(u8, key, "origin")) result.transform.position = try vector(value) else if (std.mem.eql(u8, key, "angles")) result.transform.angles = try vector(value) else if (std.mem.eql(u8, key, "angle")) {
            result.transform.angles[1] = try std.fmt.parseFloat(f32, value);
            if (!std.math.isFinite(result.transform.angles[1])) return error.InvalidVector;
        } else if (std.mem.eql(u8, key, "spawnflags")) result.binding.flags = try std.fmt.parseInt(u32, value, 10) else inline for (.{ "classname", "targetname", "target", "model" }) |field| {
            if (std.mem.eql(u8, key, field)) @field(result.binding, field) = owned;
        }
    }
    if (result.binding.classname.len == 0) return error.MissingClass;
    result.binding.properties = try properties.toOwnedSlice(allocator);
    return result;
}
test "map vectors reject truncated and non-finite input" {
    try std.testing.expectEqual([3]f32{ 1, 2, -3 }, try vector("1 2 -3"));
    try std.testing.expectError(error.InvalidVector, vector("1 2"));
    try std.testing.expectError(error.InvalidVector, vector("1 nan 3"));
}

test "authored properties survive parsing without borrowing token buffers" {
    const Source = struct {
        tokens: []const []const u8,
        index: usize = 0,
        fn token(self: *@This(), buffer: []u8) ?[]const u8 {
            if (self.index == self.tokens.len) return null;
            const next = self.tokens[self.index];
            self.index += 1;
            @memcpy(buffer[0..next.len], next);
            return buffer[0..next.len];
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var source: Source = .{ .tokens = &.{ "{", "classname", "func_door", "origin", "1 2 3", "wait", "-1", "target", "laser1", "}" } };
    const object = (try read(arena.allocator(), &source)).?;
    try std.testing.expectEqualStrings("func_door", object.binding.classname);
    try std.testing.expectEqualStrings("laser1", object.binding.target);
    try std.testing.expectEqualStrings("wait", object.binding.properties[2].key);
    try std.testing.expectEqualStrings("-1", object.binding.properties[2].value);
    try std.testing.expectEqual(@as(usize, 4), object.binding.properties.len);
    try std.testing.expect(try read(arena.allocator(), &source) == null);
}
