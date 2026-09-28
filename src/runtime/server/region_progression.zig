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
            if (!(try residents.ensure(name))) complete = false;
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
};
