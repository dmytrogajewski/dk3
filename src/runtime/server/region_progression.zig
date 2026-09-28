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
    pub fn hold(self: *State, enabled: bool) void {
        if (self.held == enabled) return;
        self.held = enabled;
        engine.send(0, if (enabled) "dk3_region_wait 1" else "dk3_region_wait 0");
    }
};
