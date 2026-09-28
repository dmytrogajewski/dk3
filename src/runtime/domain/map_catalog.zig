// SPDX-License-Identifier: GPL-2.0-or-later
//! Locally converted map names and authored multiplayer capabilities.
const std = @import("std");
pub const mode_names = [_][]const u8{ "Deathmatch", "CTF", "Deathtag" };
pub const Entry = struct {
    name: [41:0]u8 = @splat(0),
    title: [97:0]u8 = @splat(0),
    modes: u3,
    pub fn supports(self: Entry, mode: u2) bool {
        return mode < mode_names.len and self.modes & (@as(u3, 1) << mode) != 0;
    }
};
pub const Catalog = struct {
    entries: [256]Entry = undefined,
    count: usize = 0,
    pub fn parse(bytes: []const u8) !Catalog {
        var reader: @import("tables.zig").Reader = .{ .bytes = bytes };
        if (!std.mem.eql(u8, try reader.token() orelse "", "dk3_maps") or !std.mem.eql(u8, try reader.token() orelse "", "1")) return error.MapCatalogHeader;
        var result: Catalog = .{};
        while (try reader.token()) |name| {
            if (name.len == 0 or name.len > 40 or result.count == result.entries.len) return error.MapCatalogLimit;
            for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-') return error.MapCatalogName;
            for (result.entries[0..result.count]) |entry| if (std.mem.eql(u8, name, std.mem.sliceTo(&entry.name, 0))) return error.DuplicateMap;
            const modes = try std.fmt.parseInt(u3, try reader.token() orelse return error.MapCatalogTruncated, 10);
            const title = try reader.token() orelse return error.MapCatalogTruncated;
            if (title.len > 96) return error.MapCatalogLimit;
            var entry: Entry = .{ .modes = modes };
            @memcpy(entry.name[0..name.len], name);
            @memcpy(entry.title[0..title.len], title);
            result.entries[result.count] = entry;
            result.count += 1;
        }
        return result;
    }
    pub fn available(self: *const Catalog, mode: u2) usize {
        var total: usize = 0;
        for (self.entries[0..self.count]) |entry| if (entry.supports(mode)) {
            total += 1;
        };
        return total;
    }
    pub fn at(self: *const Catalog, mode: u2, index: usize) ?*const Entry {
        var rank: usize = 0;
        for (self.entries[0..self.count]) |*entry| if (entry.supports(mode)) {
            if (rank == index) return entry;
            rank += 1;
        };
        return null;
    }
    pub fn find(self: *const Catalog, mode: u2, name: []const u8) ?usize {
        var rank: usize = 0;
        for (self.entries[0..self.count]) |entry| if (entry.supports(mode)) {
            if (std.mem.eql(u8, name, std.mem.sliceTo(&entry.name, 0))) return rank;
            rank += 1;
        };
        return null;
    }
};

test "map choices use authored modes and reject unsafe or incomplete records" {
    const catalog = try Catalog.parse("dk3_maps 1\n\"intro\" 0 \"Intro\"\n\"arena\" 1 \"Arena One\"\n\"flags\" 3 \"Flags\"\n\"bomb\" 5 \"Bomb\"");
    try std.testing.expectEqual(@as(usize, 3), catalog.available(0));
    try std.testing.expectEqual(@as(usize, 1), catalog.available(1));
    try std.testing.expectEqual(@as(usize, 1), catalog.available(2));
    try std.testing.expectEqualStrings("flags", std.mem.sliceTo(&catalog.at(1, 0).?.name, 0));
    try std.testing.expect(catalog.find(1, "arena") == null);
    try std.testing.expect(catalog.find(0, "intro") == null);
    try std.testing.expect(catalog.at(2, 1) == null);
    try std.testing.expectError(error.MapCatalogName, Catalog.parse("dk3_maps 1 \"../arena\" 1 \"Bad\""));
    try std.testing.expectError(error.MapCatalogTruncated, Catalog.parse("dk3_maps 1 \"arena\" 1"));
    try std.testing.expectEqual(@as(usize, 0), (try Catalog.parse("dk3_maps 1")).available(0));
}
