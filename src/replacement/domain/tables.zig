// SPDX-License-Identifier: GPL-2.0-or-later
//! Borrowed, bounded records from locally converted dk3_table text.
const std = @import("std");
pub const Row = struct {
    pub const Field = struct { key: []const u8, value: []const u8 };
    fields: [96]Field = undefined,
    count: usize = 0,
    pub fn field(self: *const Row, name: []const u8) ?[]const u8 {
        for (self.fields[0..self.count]) |item| if (std.mem.eql(u8, item.key, name)) return item.value;
        return null;
    }
    pub fn number(self: *const Row, name: []const u8, fallback: f32) !f32 {
        const value = self.field(name) orelse return fallback;
        if (value.len == 0) return fallback;
        const result = std.fmt.parseFloat(f32, value) catch return error.InvalidTableNumber;
        if (!std.math.isFinite(result) or @abs(result) > 10000000) return error.InvalidTableNumber;
        return result;
    }
};
pub const Reader = struct {
    bytes: []const u8,
    cursor: usize = 0,
    pub fn init(bytes: []const u8) !Reader {
        if (bytes.len == 0 or bytes.len > 4 * 1024 * 1024) return error.TableSize;
        var self: Reader = .{ .bytes = bytes };
        if (!std.mem.eql(u8, try self.token() orelse return error.TableHeader, "dk3_table") or !std.mem.eql(u8, try self.token() orelse return error.TableHeader, "1")) return error.TableHeader;
        return self;
    }
    fn token(self: *Reader) !?[]const u8 {
        while (self.cursor < self.bytes.len and std.ascii.isWhitespace(self.bytes[self.cursor])) self.cursor += 1;
        if (self.cursor == self.bytes.len) return null;
        const start = self.cursor;
        if (self.bytes[start] == '"') {
            self.cursor += 1;
            const content = self.cursor;
            while (self.cursor < self.bytes.len and self.bytes[self.cursor] != '"') : (self.cursor += 1) {
                if (self.bytes[self.cursor] == 0 or self.bytes[self.cursor] == '\n' or self.bytes[self.cursor] == '\r') return error.InvalidTableString;
            }
            if (self.cursor == self.bytes.len) return error.UnterminatedTableString;
            const end = self.cursor;
            self.cursor += 1;
            return self.bytes[content..end];
        }
        if (self.bytes[start] == '{' or self.bytes[start] == '}') {
            self.cursor += 1;
            return self.bytes[start..self.cursor];
        }
        while (self.cursor < self.bytes.len and !std.ascii.isWhitespace(self.bytes[self.cursor]) and self.bytes[self.cursor] != '{' and self.bytes[self.cursor] != '}') self.cursor += 1;
        if (self.cursor == start) return error.InvalidTableToken;
        return self.bytes[start..self.cursor];
    }
    pub fn next(self: *Reader) !?Row {
        const start = try self.token() orelse return null;
        if (!std.mem.eql(u8, start, "{")) return error.ExpectedTableRow;
        var row: Row = .{};
        while (true) {
            const key = try self.token() orelse return error.UnterminatedTableRow;
            if (std.mem.eql(u8, key, "}")) return row;
            if (key.len == 0 or key.len >= 64 or row.count == row.fields.len) return error.TableFieldLimit;
            if (row.field(key) != null) return error.DuplicateTableField;
            const value = try self.token() orelse return error.MissingTableValue;
            if (value.len >= 256 or std.mem.eql(u8, value, "}")) return error.InvalidTableValue;
            row.fields[row.count] = .{ .key = key, .value = value };
            row.count += 1;
        }
    }
};
