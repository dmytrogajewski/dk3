// SPDX-License-Identifier: GPL-2.0-or-later
//! Portable v1 named-record codec. Independent of ECS and native ABI layouts.
const std = @import("std");
pub const limit = 256 * 1024 * 1024;
pub const max_records = 16384;
pub const max_fields = 320;
pub const Kind = enum(u8) { integer = 1, float = 2, text = 3, bytes = 4 };
pub const Error = error{ InvalidHeader, UnsupportedVersion, Checksum, Truncated, InvalidName, InvalidField, NonFinite, DuplicateField, Limit, Unconsumed, Capacity };
fn nameValid(name: []const u8) bool {
    if (name.len == 0 or name.len >= 64) return false;
    for (name) |c| if (!(c >= 'a' and c <= 'z') and !(c >= '0' and c <= '9') and c != '_') return false;
    return true;
}
fn read32(data: []const u8) u32 {
    return std.mem.readInt(u32, data[0..4], .little);
}
fn write32(data: []u8, value: usize) void {
    std.mem.writeInt(u32, data[0..4], @intCast(value), .little);
}
pub const Field = struct {
    name: []const u8,
    kind: Kind,
    count: usize,
    data: []const u8,
    pub fn integer(self: Field, index: usize) Error!i32 {
        if (self.kind != .integer or index >= self.count) return error.InvalidField;
        return @bitCast(read32(self.data[index * 4 ..]));
    }
    pub fn float(self: Field, index: usize) Error!f32 {
        if (self.kind != .float or index >= self.count) return error.InvalidField;
        return @bitCast(read32(self.data[index * 4 ..]));
    }
};
pub const Record = struct { name: []const u8, id: u32 };
pub const Reader = struct {
    data: []const u8,
    cursor: usize = 24,
    end: usize = 24,
    records_left: usize,
    fields_left: usize = 0,
    names: [max_fields][]const u8 = undefined,
    name_count: usize = 0,
    pub fn init(data: []const u8) Error!Reader {
        if (data.len < 24 or data.len > limit or !std.mem.eql(u8, data[0..8], "DK3SAVE\x00")) return error.InvalidHeader;
        if (read32(data[8..]) != 1) return error.UnsupportedVersion;
        if (read32(data[12..]) != data.len) return error.Truncated;
        if (read32(data[16..]) > max_records) return error.Limit;
        if (read32(data[20..]) != std.hash.crc.Crc32IsoHdlc.hash(data[24..])) return error.Checksum;
        return .{ .data = data, .records_left = read32(data[16..]) };
    }
    pub fn nextRecord(self: *Reader) Error!?Record {
        if (self.fields_left != 0 or self.cursor != self.end) return error.Unconsumed;
        if (self.records_left == 0) {
            if (self.cursor != self.data.len) return error.Truncated;
            return null;
        }
        if (self.data.len - self.cursor < 12) return error.Truncated;
        const head = self.data[self.cursor..];
        const size = read32(head);
        const len = head[10];
        if (head[11] != 0 or size < 12 + @as(usize, len) or size > head.len) return error.Truncated;
        const name = head[12..][0..len];
        if (!nameValid(name)) return error.InvalidName;
        self.fields_left = std.mem.readInt(u16, head[8..10], .little);
        if (self.fields_left > max_fields) return error.Limit;
        self.end = self.cursor + size;
        self.cursor += 12 + @as(usize, len);
        self.records_left -= 1;
        self.name_count = 0;
        return .{ .name = name, .id = read32(head[4..]) };
    }
    pub fn nextField(self: *Reader) Error!?Field {
        if (self.fields_left == 0) return null;
        if (self.end - self.cursor < 8) return error.Truncated;
        const head = self.data[self.cursor..self.end];
        const kind = std.enums.fromInt(Kind, head[0]) orelse return error.InvalidField;
        const len: usize = head[1];
        const count: usize = read32(head[4..]);
        if (head[2] != 0 or head[3] != 0 or count > limit / 4) return error.InvalidField;
        const bytes = count * @as(usize, if (kind == .integer or kind == .float) 4 else 1);
        if (8 + len + bytes > head.len) return error.Truncated;
        const name = head[8..][0..len];
        if (!nameValid(name)) return error.InvalidName;
        for (self.names[0..self.name_count]) |prior| if (std.mem.eql(u8, name, prior)) return error.DuplicateField;
        self.names[self.name_count] = name;
        self.name_count += 1;
        const data = head[8 + len ..][0..bytes];
        if (kind == .text and std.mem.indexOfScalar(u8, data, 0) != null) return error.InvalidField;
        if (kind == .float) {
            for (0..count) |i| if (!std.math.isFinite(@as(f32, @bitCast(read32(data[i * 4 ..]))))) return error.NonFinite;
        }
        self.cursor += 8 + len + bytes;
        self.fields_left -= 1;
        if (self.fields_left == 0 and self.cursor != self.end) return error.Truncated;
        return .{ .name = name, .kind = kind, .count = count, .data = data };
    }
    pub fn validate(data: []const u8) Error!void {
        var reader = try init(data);
        while (try reader.nextRecord() != null) while (try reader.nextField() != null) {};
    }
};
pub const Writer = struct {
    data: []u8,
    cursor: usize = 24,
    record_start: ?usize = null,
    records: usize = 0,
    fields: u16 = 0,
    failure: ?Error = null,
    pub fn init(data: []u8) Error!Writer {
        if (data.len < 24 or data.len > limit) return error.Capacity;
        @memset(data[0..24], 0);
        @memcpy(data[0..8], "DK3SAVE\x00");
        write32(data[8..], 1);
        return .{ .data = data };
    }
    fn reserve(self: *Writer, length: usize) Error![]u8 {
        if (self.failure) |err| return err;
        if (length > self.data.len - self.cursor) {
            self.failure = error.Capacity;
            return error.Capacity;
        }
        const bytes = self.data[self.cursor..][0..length];
        @memset(bytes, 0);
        self.cursor += length;
        return bytes;
    }
    fn close(self: *Writer) void {
        if (self.record_start) |start| {
            write32(self.data[start..], self.cursor - start);
            std.mem.writeInt(u16, self.data[start + 8 ..][0..2], self.fields, .little);
        }
    }
    pub fn record(self: *Writer, name: []const u8, id: u32) Error!void {
        errdefer |err| self.failure = err;
        if (!nameValid(name)) return error.InvalidName;
        if (self.records == max_records) return error.Limit;
        self.close();
        const start = self.cursor;
        const bytes = try self.reserve(12 + name.len);
        write32(bytes[4..], id);
        bytes[10] = @intCast(name.len);
        @memcpy(bytes[12..], name);
        self.record_start = start;
        self.records += 1;
        self.fields = 0;
    }
    pub fn raw(self: *Writer, field: Field) Error!void {
        errdefer |err| self.failure = err;
        if (!nameValid(field.name)) return error.InvalidName;
        if (self.record_start == null) return error.Unconsumed;
        if (self.fields == max_fields or field.count > limit / 4) return error.Limit;
        const bytes = field.count * @as(usize, if (field.kind == .integer or field.kind == .float) 4 else 1);
        if (bytes != field.data.len) return error.InvalidField;
        const out = try self.reserve(8 + field.name.len + bytes);
        out[0] = @intFromEnum(field.kind);
        out[1] = @intCast(field.name.len);
        write32(out[4..], field.count);
        @memcpy(out[8..][0..field.name.len], field.name);
        @memcpy(out[8 + field.name.len ..], field.data);
        self.fields += 1;
    }
    pub fn integers(self: *Writer, name: []const u8, values: []const i32) Error!void {
        errdefer |err| self.failure = err;
        // Bound the stack staging buffer by the existing codec's scalar arrays.
        if (values.len > 4096) return error.Limit;
        var storage: [4096 * 4]u8 = undefined;
        for (values, 0..) |value, i| write32(storage[i * 4 ..], @as(u32, @bitCast(value)));
        try self.raw(.{ .name = name, .kind = .integer, .count = values.len, .data = storage[0 .. values.len * 4] });
    }
    pub fn finish(self: *Writer) Error![]const u8 {
        if (self.failure) |err| return err;
        self.close();
        write32(self.data[12..], self.cursor);
        write32(self.data[16..], self.records);
        write32(self.data[20..], std.hash.crc.Crc32IsoHdlc.hash(self.data[24..self.cursor]));
        const result = self.data[0..self.cursor];
        try Reader.validate(result);
        return result;
    }
};

test "portable codec preserves signed fields and rejects corruption" {
    var bytes: [512]u8 = undefined;
    var writer = try Writer.init(&bytes);
    try writer.record("entity", 42);
    try writer.integers("health", &.{ -1, 93 });
    const data = try writer.finish();
    var reader = try Reader.init(data);
    try std.testing.expectEqual(@as(u32, 42), (try reader.nextRecord()).?.id);
    const field = (try reader.nextField()).?;
    try std.testing.expectEqual(@as(i32, -1), try field.integer(0));
    try std.testing.expectEqual(@as(i32, 93), try field.integer(1));
    try std.testing.expect(try reader.nextRecord() == null);
    bytes[bytes.len / 16] ^= 1;
    try std.testing.expectError(error.Checksum, Reader.validate(data));
}
test "duplicate fields and exhausted buffers cannot produce valid saves" {
    var bytes: [100]u8 = undefined;
    var writer = try Writer.init(&bytes);
    try writer.record("entity", 1);
    try writer.integers("health", &.{1});
    try writer.integers("health", &.{2});
    try std.testing.expectError(error.DuplicateField, writer.finish());
    var small = try Writer.init(bytes[0..24]);
    try std.testing.expectError(error.Capacity, small.record("entity", 1));
    try std.testing.expectError(error.Capacity, small.finish());
}
