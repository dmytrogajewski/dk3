// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
pub const Bounds = struct { mins: [3]f32, maxs: [3]f32 };
pub fn firstMaterial(bytes: []const u8) ?[]const u8 {
    if (bytes.len < 108 or !std.mem.eql(u8, bytes[0..4], "IDP3") or std.mem.readInt(u32, bytes[4..8], .little) != 15 or std.mem.readInt(i32, bytes[84..88], .little) <= 0) return null;
    const surface: usize = std.mem.readInt(u32, bytes[100..104], .little);
    if (surface < 108 or surface > bytes.len or bytes.len - surface < 108) return null;
    const header = bytes[surface..][0..108];
    if (!std.mem.eql(u8, header[0..4], "IDP3") or std.mem.readInt(i32, header[76..80], .little) <= 0) return null;
    const offset: usize = std.mem.readInt(u32, header[92..96], .little);
    const size: usize = std.mem.readInt(u32, header[104..108], .little);
    if (offset < 108 or size > bytes.len - surface or offset > size or size - offset < 68) return null;
    const name = std.mem.sliceTo(bytes[surface + offset ..][0..64], 0);
    if (name.len == 0 or name.len >= 64 or std.mem.indexOf(u8, name, "..") != null) return null;
    return name;
}
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
test "model material stays inside its declared surface and rejects truncated shader records" {
    const t = std.testing;
    var bytes: [284]u8 = @splat(0);
    @memcpy(bytes[0..4], "IDP3");
    std.mem.writeInt(u32, bytes[4..8], 15, .little);
    std.mem.writeInt(u32, bytes[84..88], 1, .little);
    std.mem.writeInt(u32, bytes[100..104], 108, .little);
    @memcpy(bytes[108..112], "IDP3");
    std.mem.writeInt(u32, bytes[184..188], 1, .little);
    std.mem.writeInt(u32, bytes[200..204], 108, .little);
    std.mem.writeInt(u32, bytes[212..216], 176, .little);
    @memcpy(bytes[216..228], "skins/robot1");
    try t.expectEqualStrings("skins/robot1", firstMaterial(&bytes).?);
    try t.expect(firstMaterial(bytes[0..283]) == null);
    std.mem.writeInt(u32, bytes[200..204], 109, .little);
    try t.expect(firstMaterial(&bytes) == null);
}
