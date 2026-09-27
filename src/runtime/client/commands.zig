// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
pub const Restore = struct {
    fire: ?struct { weapon: u5, serial: u32, started_ms: i64 } = null,
};
pub fn restored() ?Restore {
    var buffer: [128]u8 = @splat(0);
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 0), &buffer, @as(isize, buffer.len) });
    if (std.mem.eql(u8, std.mem.sliceTo(&buffer, 0), "map_restart")) return .{};
    if (!std.mem.eql(u8, std.mem.sliceTo(&buffer, 0), "dk3_restored")) return null;
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 1), &buffer, @as(isize, buffer.len) });
    const weapon = std.fmt.parseInt(u5, std.mem.sliceTo(&buffer, 0), 10) catch return .{};
    if (@import("weapon_catalog").find(weapon) == null) return .{};
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 2), &buffer, @as(isize, buffer.len) });
    const serial = std.fmt.parseInt(u32, std.mem.sliceTo(&buffer, 0), 10) catch return .{};
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 3), &buffer, @as(isize, buffer.len) });
    const started_ms = std.fmt.parseInt(i32, std.mem.sliceTo(&buffer, 0), 10) catch return .{};
    return .{ .fire = .{ .weapon = weapon, .serial = serial, .started_ms = started_ms } };
}
/// Server-forced acquisition/expiry selection. Malformed or unowned IDs are ignored.
pub fn selectedWeapon(inventory: i32) ?i32 {
    var buffer: [128]u8 = @splat(0);
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 0), &buffer, @as(isize, buffer.len) });
    if (!std.mem.eql(u8, std.mem.sliceTo(&buffer, 0), "dk3_weapon")) return null;
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, 1), &buffer, @as(isize, buffer.len) });
    const id = std.fmt.parseInt(u5, std.mem.sliceTo(&buffer, 0), 10) catch return null;
    if (@import("weapon_catalog").find(id) == null or @as(u32, @bitCast(inventory)) & (@as(u32, 1) << id) == 0) return null;
    return id;
}
