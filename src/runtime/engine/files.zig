// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const abi = @import("abi.zig");
const c = abi.c;
const Side = enum { server, client, ui };
pub fn read(comptime side: Side, gateway: *abi.Gateway, allocator: std.mem.Allocator, path: [:0]const u8, maximum: usize) ![]u8 {
    return try readOptional(side, gateway, allocator, path, maximum) orelse error.InvalidFileSize;
}
/// Absence is distinct from an existing empty, oversized or malformed file.
pub fn readOptional(comptime side: Side, gateway: *abi.Gateway, allocator: std.mem.Allocator, path: [:0]const u8, maximum: usize) !?[]u8 {
    const open = switch (side) {
        .server => c.G_FS_FOPEN_FILE,
        .client => c.CG_FS_FOPENFILE,
        .ui => c.UI_FS_FOPENFILE,
    };
    const close = switch (side) {
        .server => c.G_FS_FCLOSE_FILE,
        .client => c.CG_FS_FCLOSEFILE,
        .ui => c.UI_FS_FCLOSEFILE,
    };
    const get = switch (side) {
        .server => c.G_FS_READ,
        .client => c.CG_FS_READ,
        .ui => c.UI_FS_READ,
    };
    var handle: c.fileHandle_t = 0;
    const length = gateway.call(open, .{ path.ptr, &handle, @as(isize, c.FS_READ) });
    defer if (handle != 0) {
        _ = gateway.call(close, .{@as(isize, handle)});
    };
    if (length < 0 and handle == 0) return null;
    if (length <= 0 or length > maximum or handle == 0) return error.InvalidFileSize;
    const bytes = try allocator.alloc(u8, @intCast(length));
    _ = gateway.call(get, .{ bytes.ptr, length, @as(isize, handle) });
    return bytes;
}
