// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
pub const Bounds = struct { mins: [3]f32, maxs: [3]f32 };
pub fn bounds(bytes: []const u8) ?Bounds {
    if (bytes.len < 108 or !std.mem.eql(u8, bytes[0..4], "IDP3") or std.mem.readInt(u32, bytes[4..8], .little) != 15) return null;
    if (std.mem.readInt(i32, bytes[76..80], .little) <= 0) return null;
    const offset = std.mem.readInt(u32, bytes[92..96], .little);
    if (offset < 108 or offset > bytes.len or bytes.len - offset < 56) return null;
    var result: Bounds = undefined;
    for (0..3) |axis| {
        const lo = offset + axis * 4;
        const hi = lo + 12;
        result.mins[axis] = @bitCast(std.mem.readInt(u32, bytes[lo..][0..4], .little));
        result.maxs[axis] = @bitCast(std.mem.readInt(u32, bytes[hi..][0..4], .little));
        if (!std.math.isFinite(result.mins[axis]) or !std.math.isFinite(result.maxs[axis]) or result.mins[axis] < -256 or result.maxs[axis] > 256 or result.mins[axis] > result.maxs[axis]) return null;
    }
    return result;
}
test "model bounds reject truncated frames and invalid floating point" {
    var bytes: [164]u8 = @splat(0);
    @memcpy(bytes[0..4], "IDP3");
    std.mem.writeInt(u32, bytes[4..8], 15, .little);
    std.mem.writeInt(u32, bytes[76..80], 1, .little);
    std.mem.writeInt(u32, bytes[92..96], 108, .little);
    try std.testing.expect(bounds(&bytes) != null);
    try std.testing.expect(bounds(bytes[0..163]) == null);
    std.mem.writeInt(u32, bytes[108..112], @bitCast(std.math.nan(f32)), .little);
    try std.testing.expect(bounds(&bytes) == null);
}
