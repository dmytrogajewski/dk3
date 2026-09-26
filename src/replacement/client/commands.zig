// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
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
