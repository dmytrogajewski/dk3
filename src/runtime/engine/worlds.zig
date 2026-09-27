// SPDX-License-Identifier: GPL-2.0-or-later
//! Resident static geometry; collision readiness does not imply gameplay,
//! navigation or presentation readiness. All gateway calls stay on the owner.
const std = @import("std");
const engine = @import("server.zig");
const c = @import("abi.zig").c;
pub const Handle = enum(u32) { _ };
pub const Status = enum { reading, collision_ready, failed };

pub fn request(name: []const u8) !Handle {
    if (!@import("../domain/snapshot.zig").validName(name)) return error.InvalidWorldName;
    var buffer: [c.MAX_QPATH]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buffer, "maps/{s}.bsp", .{name});
    const value = engine.gateway.call(c.G_DK3_WORLD_REQUEST_V1, .{path.ptr});
    if (value <= 0) return error.WorldPreparationUnavailable;
    return @enumFromInt(@as(u32, @intCast(value)));
}
pub fn poll(handle: Handle) Status {
    return switch (engine.gateway.call(c.G_DK3_WORLD_POLL_V1, .{@as(isize, @intFromEnum(handle))})) {
        0 => .reading,
        1 => .collision_ready,
        else => .failed,
    };
}
pub fn release(handle: Handle) bool {
    return engine.gateway.call(c.G_DK3_WORLD_RELEASE_V1, .{@as(isize, @intFromEnum(handle))}) != 0;
}
pub fn bytes(handle: Handle) usize {
    return @intCast(engine.gateway.call(c.G_DK3_WORLD_BYTES_V1, .{@as(isize, @intFromEnum(handle))}));
}
pub fn entities(allocator: std.mem.Allocator, handle: Handle) ![]u8 {
    const length = engine.gateway.call(c.G_DK3_WORLD_ENTITIES_V1, .{ @as(isize, @intFromEnum(handle)), @as(?*u8, null), @as(isize, 0) });
    if (length <= 0 or length > 4 * 1024 * 1024) return error.WorldEntitiesUnavailable;
    const buffer = try allocator.alloc(u8, @intCast(length));
    errdefer allocator.free(buffer);
    if (engine.gateway.call(c.G_DK3_WORLD_ENTITIES_V1, .{ @as(isize, @intFromEnum(handle)), buffer.ptr, length }) != length or buffer[buffer.len - 1] != 0) return error.WorldEntitiesUnavailable;
    return buffer;
}
pub fn trace(handle: Handle, start: [3]f32, end: [3]f32, mins: [3]f32, maxs: [3]f32, model: i32, mask: i32) !c.trace_t {
    var result: c.trace_t = undefined;
    if (engine.gateway.call(c.G_DK3_WORLD_TRACE_V1, .{ @as(isize, @intFromEnum(handle)), &result, &start, &end, &mins, &maxs, @as(isize, model), @as(isize, mask) }) == 0) return error.WorldNotReady;
    return result;
}
