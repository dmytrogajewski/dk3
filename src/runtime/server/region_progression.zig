// SPDX-License-Identifier: GPL-2.0-or-later
//! Campaign admission uses the same owners as restoration and diagnostics.
const std = @import("std");
const engine = @import("../engine/server.zig");
const Context = @import("world_context.zig").Context;
const Residents = @import("resident_worlds.zig").State;
const graph = @import("../domain/campaign_regions.zig");
pub const State = struct {
    bytes: ?[]u8 = null,
    manifest: graph.Manifest = .{},
    initial_pending: bool = false,
    held: bool = false,
    pending: ?@import("../domain/travel.zig").Request = null,
    portal_sent: [256]bool = @splat(false),
    pub fn deinit(self: *State) void {
        if (self.bytes) |bytes| std.heap.c_allocator.free(bytes);
        self.* = .{};
    }
    pub fn init(self: *State) !void {
        if (engine.integer("g_gametype") != @import("../engine/abi.zig").c.GT_SINGLE_PLAYER) return;
        self.bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, std.heap.c_allocator, "dk3/campaign-regions.cfg", 256 * 1024);
        self.manifest = try graph.Manifest.parse(self.bytes.?);
        self.initial_pending = true;
    }
    pub fn ready(self: *State, residents: *Residents, initial: *Context, map: []const u8, prefetch: bool) !bool {
        const index = self.manifest.find(map) orelse return true; // Standalone diagnostic/multiplayer map, not a campaign edge.
        const wanted = if (prefetch) self.manifest.ahead(index) else self.manifest.region(index);
        var complete = true;
        for (self.manifest.names[0..self.manifest.count], wanted[0..self.manifest.count]) |name, selected| {
            if (!selected or std.mem.eql(u8, name, std.mem.sliceTo(&initial.map_name, 0))) continue;
            const admitted = residents.ensure(name) catch |err| switch (err) {
                // A rejected future region cannot invalidate the playable one.
                // Required initial/restore/exit admission still rejects it;
                // the resident owner has already reported the precise failure.
                error.RegionPreparationFailed => if (prefetch) {
                    complete = false;
                    continue;
                } else return err,
                else => return err,
            };
            if (!admitted) complete = false;
        }
        return complete;
    }
    pub fn edge(self: *const State, context: *Context, id: u32) !graph.Edge {
        const source = self.manifest.find(std.mem.sliceTo(&context.map_name, 0)) orelse return error.CampaignMapNotInventoried;
        return self.manifest.exit(source, @truncate(id)) orelse error.CampaignExitNotInventoried;
    }
    pub fn publishPortals(self: *State) !void {
        const access = @import("region_access.zig");
        const data = @import("../domain/components.zig");
        const v = @import("../domain/vector.zig");
        for (self.manifest.edges[0..self.manifest.edge_count], 0..) |connection, index| {
            if (connection.kind != .identity or self.portal_sent[index]) continue;
            const source = access.byMap(connection.source) orelse continue;
            const destination = access.byMap(connection.destination) orelse continue;
            const entity = source.world.?.find((source.world.?.id_first & 0xff000000) | @as(u32, connection.exit)) orelse return error.SeamExitMissing;
            const body = try source.world.?.get(entity, data.Body);
            const pose = try source.world.?.get(entity, data.Transform);
            const mins = v.add(pose.position, body.mins);
            const maxs = v.add(pose.position, body.maxs);
            var message: [384]u8 = undefined;
            engine.send(0, try std.fmt.bufPrintZ(&message, "dk3_world_portal {d} {d} {d} {d} {d} \"{d} {d} {d}\" \"{d} {d} {d}\"", .{ index, source.network_id, destination.network_id, connection.axis, connection.direction, mins[0], mins[1], mins[2], maxs[0], maxs[1], maxs[2] }));
            self.portal_sent[index] = true;
        }
    }
    pub fn hold(self: *State, enabled: bool) void {
        if (self.held == enabled) return;
        self.held = enabled;
        engine.send(0, if (enabled) "dk3_region_wait 1" else "dk3_region_wait 0");
    }
    /// Hold for the maps joined to `map` and tell the client how many, so its
    /// loading bar has a fixed denominator from the start.
    pub fn holdFor(self: *State, map: []const u8) void {
        if (self.held) return;
        self.held = true;
        var command: [48]u8 = undefined;
        engine.send(0, std.fmt.bufPrintZ(&command, "dk3_region_wait 1 {d}", .{self.joined(map)}) catch unreachable);
    }
    /// Other maps of `map`'s seamless region (those its admission waits for).
    pub fn joined(self: *const State, map: []const u8) usize {
        const index = self.manifest.find(map) orelse return 0;
        const wanted = self.manifest.region(index);
        var count: usize = 0;
        for (wanted[0..self.manifest.count], 0..) |selected, other| count += @intFromBool(selected and other != index);
        return count;
    }
};

test "failed lookahead leaves the current region ready but never admits the failed destination" {
    const t = std.testing;
    const initial = try t.allocator.create(Context);
    defer t.allocator.destroy(initial);
    initial.* = .{};
    initial.map_name[0] = 'a';
    const residents = try t.allocator.create(Residents);
    defer t.allocator.destroy(residents);
    residents.* = .{};
    var state: State = .{};
    state.manifest.count = 3;
    state.manifest.names[0..3].* = .{ "a", "b", "c" };
    state.manifest.edge_count = 2;
    state.manifest.edges[0] = .{ .source = 0, .destination = 1, .exit = 1, .reciprocal = 0, .kind = .cut };
    state.manifest.edges[1] = .{ .source = 0, .destination = 2, .exit = 2, .reciprocal = 0, .kind = .cut };
    for (0..2) |index| {
        residents.entries[index] = .{
            .handle = @enumFromInt(@as(u32, @intCast(514 + index))),
            .status = .collision_ready,
            .ready = true,
            .publication = .{ .payload = &.{}, .digest = 0, .checksum = 0, .ready = true },
        };
        residents.entries[index].?.name[0] = @intCast('b' + index);
    }
    try t.expect(try state.ready(residents, initial, "a", true));
    residents.entries[0].?.client_failed = true;
    try t.expect(!try state.ready(residents, initial, "a", true));
    try t.expect(try state.ready(residents, initial, "a", false));
    try t.expectError(error.RegionPreparationFailed, state.ready(residents, initial, "b", false));
    try t.expect(try state.ready(residents, initial, "c", false));
    residents.entries[0].?.client_failed = false;
    residents.entries[0].?.status = .failed;
    try t.expect(!try state.ready(residents, initial, "a", true));
    try t.expectError(error.RegionPreparationFailed, state.ready(residents, initial, "b", false));
}
