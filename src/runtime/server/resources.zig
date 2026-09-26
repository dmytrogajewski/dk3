// SPDX-License-Identifier: GPL-2.0-or-later
//! Map-scoped resource identities projected through public configstrings.
const std = @import("std");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
fn Registry(comptime limit: usize, comptime base: i32) type {
    return struct {
        names: [limit][c.MAX_QPATH]u8 = @splat(@splat(0)),
        count: usize = 1,
        fn add(self: *@This(), path: []const u8) !u16 {
            if (path.len == 0) return 0;
            if (path.len >= c.MAX_QPATH or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidResourcePath;
            for (1..self.count) |index| if (std.mem.eql(u8, std.mem.sliceTo(&self.names[index], 0), path)) return @intCast(index);
            if (self.count == limit) return error.ResourceCapacity;
            const index = self.count;
            self.count += 1;
            @memcpy(self.names[index][0..path.len], path);
            self.names[index][path.len] = 0;
            engine.config(base + @as(i32, @intCast(index)), self.names[index][0..path.len :0]);
            return @intCast(index);
        }
    };
}
var models: Registry(c.MAX_MODELS, c.CS_MODELS) = .{};
var sounds: Registry(c.MAX_SOUNDS, c.CS_SOUNDS) = .{};
pub fn reset() void {
    models = .{};
    sounds = .{};
}
pub fn model(path: []const u8) !u16 {
    return models.add(path);
}
pub fn sound(path: []const u8) !u16 {
    if (path.len >= c.MAX_QPATH) return error.InvalidResourcePath;
    var normalized: [c.MAX_QPATH]u8 = undefined;
    for (path, 0..) |char, i| normalized[i] = if (char == '\\') '/' else std.ascii.toLower(char);
    const name = normalized[0..path.len];
    return sounds.add(if (std.mem.startsWith(u8, name, "sounds/")) name[7..] else name);
}
pub fn floorBounds(path: []const u8) !?@import("../domain/md3.zig").Bounds {
    if (!std.mem.endsWith(u8, path, ".dkm")) return null;
    var buffer: [c.MAX_QPATH + 5]u8 = undefined;
    const converted = try std.fmt.bufPrintZ(&buffer, "{s}.md3", .{path});
    const bytes = @import("../engine/files.zig").read(.server, &engine.gateway, std.heap.c_allocator, converted, 32 * 1024 * 1024) catch |err| switch (err) {
        error.InvalidFileSize => return null,
        else => return err,
    };
    defer std.heap.c_allocator.free(bytes);
    return @import("../domain/md3.zig").bounds(bytes);
}
