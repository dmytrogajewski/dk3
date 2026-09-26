// SPDX-License-Identifier: GPL-2.0-or-later
//! Map-scoped resource identities projected through public configstrings.
const std = @import("std");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
var models: [c.MAX_MODELS][c.MAX_QPATH]u8 = undefined;
var count: usize = 1;
pub fn reset() void {
    @memset(std.mem.asBytes(&models), 0);
    count = 1;
}
pub fn model(path: []const u8) !u16 {
    if (path.len == 0) return 0;
    if (path.len >= c.MAX_QPATH or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidModelPath;
    for (1..count) |index| if (std.mem.eql(u8, std.mem.sliceTo(&models[index], 0), path)) return @intCast(index);
    if (count == models.len) return error.ModelCapacity;
    const index = count;
    count += 1;
    @memcpy(models[index][0..path.len], path);
    models[index][path.len] = 0;
    engine.config(@as(i32, c.CS_MODELS) + @as(i32, @intCast(index)), models[index][0..path.len :0]);
    return @intCast(index);
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
