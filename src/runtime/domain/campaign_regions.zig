// SPDX-License-Identifier: GPL-2.0-or-later
//! Asset-derived campaign graph. Readiness and geometry qualification are
//! separate: preparing a landing never declares it a continuous portal.
const std = @import("std");
const tables = @import("tables.zig");
pub const limit = 128;
pub const Kind = enum { cut, landing, identity };
pub const Edge = struct { source: u7, destination: u7, exit: u24, reciprocal: u24, kind: Kind };
pub const Manifest = struct {
    names: [limit][]const u8 = @splat(""),
    count: usize = 0,
    edges: [256]Edge = undefined,
    edge_count: usize = 0,
    pub fn find(self: *const Manifest, name: []const u8) ?u7 {
        for (self.names[0..self.count], 0..) |value, index| if (std.mem.eql(u8, name, value)) return @intCast(index);
        return null;
    }
    pub fn parse(bytes: []const u8) !Manifest {
        var self: Manifest = .{};
        var reader = try tables.Reader.init(bytes);
        while (try reader.next()) |row| {
            if (row.field("map")) |name| {
                if (self.edge_count != 0 or self.count == limit or !@import("snapshot.zig").validName(name) or name.len >= 64 or self.find(name) != null) return error.InvalidRegionMap;
                const hash = row.field("sha256") orelse return error.MissingRegionDigest;
                if (hash.len != 64) return error.InvalidRegionDigest;
                for (hash) |letter| if (!std.ascii.isHex(letter)) return error.InvalidRegionDigest;
                self.names[self.count] = name;
                self.count += 1;
                continue;
            }
            if (self.edge_count == self.edges.len) return error.RegionEdgeCapacity;
            const edge: Edge = .{
                .source = self.find(row.field("source") orelse return error.MissingRegionSource) orelse return error.UnknownRegionSource,
                .destination = self.find(row.field("destination") orelse return error.MissingRegionDestination) orelse return error.UnknownRegionDestination,
                .exit = try std.fmt.parseInt(u24, row.field("exit") orelse return error.MissingRegionExit, 10),
                .reciprocal = try std.fmt.parseInt(u24, row.field("reciprocal") orelse "0", 10),
                .kind = std.meta.stringToEnum(Kind, row.field("kind") orelse return error.MissingRegionKind) orelse return error.InvalidRegionKind,
            };
            if (edge.exit == 0 or edge.source == edge.destination or (edge.kind == .identity and edge.reciprocal == 0)) return error.InvalidRegionEdge;
            for (self.edges[0..self.edge_count]) |prior| if (prior.source == edge.source and prior.exit == edge.exit) return error.DuplicateRegionExit;
            self.edges[self.edge_count] = edge;
            self.edge_count += 1;
        }
        for (self.edges[0..self.edge_count]) |edge| if (edge.kind == .identity) {
            const back = self.exit(edge.destination, edge.reciprocal) orelse return error.MissingReciprocalSeam;
            if (back.kind != .identity or back.destination != edge.source or back.reciprocal != edge.exit) return error.MismatchedReciprocalSeam;
        };
        return self;
    }
    pub fn exit(self: *const Manifest, source: u7, local_id: u24) ?Edge {
        for (self.edges[0..self.edge_count]) |edge| if (edge.source == source and edge.exit == local_id) return edge;
        return null;
    }
    pub fn region(self: *const Manifest, seed: u7) [limit]bool {
        var selected: [limit]bool = @splat(false);
        selected[seed] = true;
        var changed = true;
        while (changed) {
            changed = false;
            for (self.edges[0..self.edge_count]) |edge| {
                if (edge.kind == .cut or selected[edge.source] == selected[edge.destination]) continue;
                selected[edge.source] = true;
                selected[edge.destination] = true;
                changed = true;
            }
        }
        return selected;
    }
    pub fn ahead(self: *const Manifest, seed: u7) [limit]bool {
        const current = self.region(seed);
        var selected: [limit]bool = @splat(false);
        for (self.edges[0..self.edge_count]) |edge| if (current[edge.source] and !current[edge.destination]) {
            const next = self.region(edge.destination);
            for (&selected, next) |*value, wanted| value.* = value.* or wanted;
        };
        return selected;
    }
};
test "regions preserve parallel exits and separate authored cuts from seam qualification" {
    const digest = "0000000000000000000000000000000000000000000000000000000000000000";
    const manifest = try Manifest.parse("dk3_table 1 {map movie sha256 " ++ digest ++ "} {map first sha256 " ++ digest ++ "} {map second sha256 " ++ digest ++ "} {map next sha256 " ++ digest ++ "}" ++
        "{source movie destination first exit 2 kind cut}" ++
        "{source first destination second exit 8 kind identity reciprocal 4}" ++
        "{source second destination first exit 4 kind identity reciprocal 8}" ++
        "{source first destination second exit 9 kind landing}" ++
        "{source second destination next exit 5 kind cut}");
    const movie = manifest.region(0);
    try std.testing.expect(movie[0] and !movie[1]);
    const first = manifest.region(1);
    try std.testing.expect(first[1] and first[2] and !first[3] and !first[0]);
    const ahead = manifest.ahead(0);
    try std.testing.expect(ahead[1] and ahead[2] and !ahead[3]);
    try std.testing.expectEqual(Kind.landing, manifest.exit(1, 9).?.kind);
    try std.testing.expectError(error.MissingReciprocalSeam, Manifest.parse("dk3_table 1 {map a sha256 " ++ digest ++ "} {map b sha256 " ++ digest ++ "} {source a destination b exit 1 kind identity reciprocal 2}"));
}
