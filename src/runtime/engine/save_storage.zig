// SPDX-License-Identifier: GPL-2.0-or-later
//! Engine owns atomic replacement, previous-save recovery and private state paths.
const std = @import("std");
const engine = @import("server.zig");
const c = @import("abi.zig").c;
const snapshot = @import("../domain/snapshot.zig");
fn name(slot: []const u8, buffer: []u8) ![:0]const u8 {
    if (!snapshot.validName(slot)) return error.InvalidSaveSlot;
    return std.fmt.bufPrintZ(buffer, "{s}", .{slot});
}
pub fn write(slot: []const u8, bytes: []const u8, info: bool) !void {
    var buffer: [64]u8 = undefined;
    const slot_name = try name(slot, &buffer);
    const length = engine.gateway.call(c.G_DK3_SAVE_WRITE, .{ @as(isize, if (info) 2 else 1), slot_name.ptr, bytes.ptr, @as(isize, @intCast(bytes.len)) });
    if (length != bytes.len) return error.SaveWriteFailed;
}
pub fn read(allocator: std.mem.Allocator, slot: []const u8, previous: bool) ![]u8 {
    var buffer: [64]u8 = undefined;
    const slot_name = try name(slot, &buffer);
    const scratch = try allocator.alloc(u8, snapshot.maximum);
    defer allocator.free(scratch);
    const length = engine.gateway.call(c.G_DK3_SAVE_READ, .{ @as(isize, 1), slot_name.ptr, scratch.ptr, @as(isize, @intCast(scratch.len)), @as(isize, @intFromBool(previous)) });
    if (length <= 0 or length > scratch.len) return error.SaveMissingOrUnreadable;
    return allocator.dupe(u8, scratch[0..@intCast(length)]);
}
