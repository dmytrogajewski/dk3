// SPDX-License-Identifier: GPL-2.0-or-later
//! Immutable map configstrings carried over acknowledged native commands.
//! Resource names come from the owning classes' existing registration tables.
const std = @import("std");
pub const version = 1;
pub const config_limit = 4096;
pub const string_limit = 128 * 1024;
pub const maximum = string_limit + config_limit * 6;
pub const chunk_size = 384;
pub const window = chunk_size * 4;
pub fn append(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), index: u16, value: []const u8) !void {
    if (index >= config_limit or value.len == 0 or value.len > string_limit or std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidWorldConfig;
    if (bytes.items.len + 6 + value.len > maximum) return error.WorldConfigCapacity;
    var header: [6]u8 = undefined;
    std.mem.writeInt(u16, header[0..2], index, .little);
    std.mem.writeInt(u32, header[2..6], @intCast(value.len), .little);
    try bytes.appendSlice(allocator, &header);
    try bytes.appendSlice(allocator, value);
}
pub const Reader = struct {
    bytes: []const u8,
    last: ?u16 = null,
    strings: usize = 1,
    pub const Row = struct { index: u16, value: []const u8 };
    pub fn next(self: *Reader) !?Row {
        if (self.bytes.len == 0) return null;
        if (self.bytes.len < 6) return error.TruncatedWorldConfig;
        const index = std.mem.readInt(u16, self.bytes[0..2], .little);
        const length = std.mem.readInt(u32, self.bytes[2..6], .little);
        if (index >= config_limit or (self.last != null and index <= self.last.?)) return error.InvalidWorldConfigOrder;
        if (length == 0 or length > self.bytes.len - 6 or self.strings + length + 1 > string_limit) return error.WorldConfigCapacity;
        const value = self.bytes[6..][0..length];
        if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidWorldConfig;
        self.last = index;
        self.strings += length + 1;
        self.bytes = self.bytes[6 + length ..];
        return .{ .index = index, .value = value };
    }
};
pub const Receiver = struct {
    bytes: []u8,
    digest: u64,
    received: usize = 0,
    pub fn init(allocator: std.mem.Allocator, length: usize, digest: u64) !Receiver {
        if (length == 0 or length > maximum) return error.WorldConfigCapacity;
        return .{ .bytes = try allocator.alloc(u8, length), .digest = digest };
    }
    pub fn deinit(self: *Receiver, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
    pub fn accept(self: *Receiver, offset: usize, bytes: []const u8) !void {
        if (offset != self.received or bytes.len == 0 or bytes.len > chunk_size or bytes.len > self.bytes.len - self.received) return error.InvalidWorldChunk;
        @memcpy(self.bytes[self.received..][0..bytes.len], bytes);
        self.received += bytes.len;
    }
    pub fn finish(self: *const Receiver) !Reader {
        if (self.received != self.bytes.len) return error.IncompleteWorldConfig;
        if (std.hash.Wyhash.hash(0, self.bytes) != self.digest) return error.WorldConfigDigest;
        var reader: Reader = .{ .bytes = self.bytes };
        while (try reader.next()) |_| {}
        return .{ .bytes = self.bytes };
    }
};
pub fn hex(out: []u8, bytes: []const u8) ![]const u8 {
    if (out.len < bytes.len * 2) return error.WorldChunkCapacity;
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |value, i| {
        out[i * 2] = alphabet[value >> 4];
        out[i * 2 + 1] = alphabet[value & 15];
    }
    return out[0 .. bytes.len * 2];
}

test "world admission rejects missing, reordered, duplicated and corrupted definitions" {
    const t = std.testing;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(t.allocator);
    try append(t.allocator, &bytes, 32, "models/authored.dkm");
    try append(t.allocator, &bytes, 544, "weapons/authored.wav");
    var receiver = try Receiver.init(t.allocator, bytes.items.len, std.hash.Wyhash.hash(0, bytes.items));
    defer receiver.deinit(t.allocator);
    try t.expectError(error.IncompleteWorldConfig, receiver.finish());
    try t.expectError(error.InvalidWorldChunk, receiver.accept(1, bytes.items));
    try receiver.accept(0, bytes.items[0..7]);
    try t.expectError(error.InvalidWorldChunk, receiver.accept(0, bytes.items[0..7]));
    try receiver.accept(7, bytes.items[7..]);
    var reader = try receiver.finish();
    try t.expectEqualStrings("models/authored.dkm", (try reader.next()).?.value);
    try t.expectEqualStrings("weapons/authored.wav", (try reader.next()).?.value);
    try t.expect(try reader.next() == null);
    receiver.bytes[7] ^= 1;
    try t.expectError(error.WorldConfigDigest, receiver.finish());
    bytes.clearRetainingCapacity();
    try append(t.allocator, &bytes, 3, "first");
    try append(t.allocator, &bytes, 3, "duplicate");
    reader = .{ .bytes = bytes.items };
    _ = try reader.next();
    try t.expectError(error.InvalidWorldConfigOrder, reader.next());
}
