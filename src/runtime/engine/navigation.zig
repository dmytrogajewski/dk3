// SPDX-License-Identifier: GPL-2.0-or-later
//! Owner-thread botlib lifecycle and AAS projection. No gameplay policy lives here.
const std = @import("std");
const abi = @import("abi.zig");
const engine = @import("server.zig");
const rules = @import("../domain/navigation.zig");
const c = abi.c;
pub const Navigation = struct {
    started: bool = false,
    pub fn init(self: *Navigation, allocator: std.mem.Allocator, now: i64) !void {
        if (engine.integer("bot_enable") == 0) return error.NavigationRequiresBotlib;
        var map_buffer: [c.MAX_QPATH]u8 = @splat(0);
        _ = engine.gateway.call(c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "mapname"), &map_buffer, @as(isize, map_buffer.len) });
        const map = std.mem.sliceTo(&map_buffer, 0);
        var path: [128]u8 = undefined;
        const bytes = try @import("files.zig").read(.server, &engine.gateway, allocator, try std.fmt.bufPrintZ(&path, "dk3/navigation/{s}.cfg", .{map}), 4096);
        defer allocator.free(bytes);
        const mode: rules.Mode = switch (engine.integer("g_gametype")) {
            c.GT_SINGLE_PLAYER => if (engine.integer("g_spSkill") <= 2) .easy else if (engine.integer("g_spSkill") == 3) .normal else .hard,
            c.GT_CTF => .ctf,
            c.GT_DK3_DEATHTAG => .deathtag,
            else => .dm,
        };
        const selected = try rules.selection(bytes, mode);
        var name: [64]u8 = undefined;
        const asset = try std.fmt.bufPrintZ(&name, "{s}", .{selected});
        var number: [16]u8 = undefined;
        variable("maxclients", try std.fmt.bufPrintZ(&number, "{d}", .{c.MAX_CLIENTS}));
        variable("maxentities", try std.fmt.bufPrintZ(&number, "{d}", .{c.MAX_GENTITIES}));
        variable("dk3_navigation", "1");
        var checksum: [32]u8 = @splat(0);
        _ = engine.gateway.call(c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "sv_mapChecksum"), &checksum, @as(isize, checksum.len) });
        variable("sv_mapChecksum", checksum[0..std.mem.indexOfScalar(u8, &checksum, 0).? :0]);
        if (engine.gateway.call(c.BOTLIB_SETUP, .{}) != 0) return error.NavigationSetup;
        self.started = true;
        errdefer self.deinit();
        if (engine.gateway.call(c.BOTLIB_LOAD_MAP, .{asset.ptr}) != 0) return error.NavigationLoad;
        try self.frame(now);
        var message: [192]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig navigation: map={s} asset={s} mode={s}\n", .{ map, selected, @tagName(mode) }));
    }
    pub fn deinit(self: *Navigation) void {
        if (self.started) _ = engine.gateway.call(c.BOTLIB_SHUTDOWN, .{});
        self.started = false;
    }
    pub fn frame(self: *Navigation, now: i64) !void {
        if (!self.started) return;
        const seconds: f32 = @as(f32, @floatFromInt(now)) * 0.001;
        if (engine.gateway.call(c.BOTLIB_START_FRAME, .{@as(isize, @as(i32, @bitCast(seconds)))}) != 0) return error.NavigationFrame;
    }
    pub fn sync(self: *Navigation, projections: []const abi.EntityProjection) void {
        if (!self.started) return;
        for (projections, 0..) |entity, index| {
            if (entity.shared.linked == 0 or entity.shared.contents & (c.CONTENTS_SOLID | c.CONTENTS_BODY | c.CONTENTS_CORPSE) == 0) {
                _ = engine.gateway.call(c.BOTLIB_UPDATENTITY, .{ @as(isize, @intCast(index)), @as(?*c.bot_entitystate_t, null) });
                continue;
            }
            var state = std.mem.zeroes(c.bot_entitystate_t);
            state.type = entity.state.eType;
            state.origin = entity.shared.currentOrigin;
            state.angles = entity.shared.currentAngles;
            state.mins = entity.shared.mins;
            state.maxs = entity.shared.maxs;
            state.groundent = entity.state.groundEntityNum;
            state.solid = if (entity.shared.bmodel != 0) c.SOLID_BSP else c.SOLID_BBOX;
            state.modelindex = entity.state.modelindex;
            _ = engine.gateway.call(c.BOTLIB_UPDATENTITY, .{ @as(isize, @intCast(index)), &state });
        }
    }
    pub fn service(self: *Navigation) rules.Service {
        return .{ .context = self, .next_fn = next };
    }
    fn next(raw: *anyopaque, request: rules.Request) !?rules.Waypoint {
        const self: *Navigation = @ptrCast(@alignCast(raw));
        if (!self.started or engine.gateway.call(c.BOTLIB_AAS_INITIALIZED, .{}) == 0) return null;
        const from = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &request.position, @as(isize, request.slot) });
        const to = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &request.destination, @as(isize, c.ENTITYNUM_NONE) });
        if (from == 0 or to == 0) return null;
        if (from == to) return .{ .point = request.destination, .from_area = @intCast(from), .to_area = @intCast(to) };
        // Admit only travel that the ground actor motor implements.
        const flags = c.TFL_WALK | c.TFL_BARRIERJUMP | c.TFL_JUMP | c.TFL_AIR;
        var route = std.mem.zeroes(c.aas_predictroute_t);
        _ = engine.gateway.call(c.BOTLIB_AAS_PREDICT_ROUTE, .{ &route, from, &request.position, to, @as(isize, flags), @as(isize, 1), @as(isize, 0), @as(isize, c.RSE_USETRAVELTYPE), @as(isize, 0), @as(isize, flags), @as(isize, 0) });
        if (route.stopevent == c.RSE_NOROUTE) return null;
        // Approach the reachability entrance before crossing it. A shortcut to its
        // far endpoint can cut across the wall at a corner or launch a jump early.
        if (rules.horizontalDistance(request.position, route.endpos) > 20) return .{ .point = route.endpos, .from_area = @intCast(from), .to_area = @intCast(to) };
        route = std.mem.zeroes(c.aas_predictroute_t);
        _ = engine.gateway.call(c.BOTLIB_AAS_PREDICT_ROUTE, .{ &route, from, &request.position, to, @as(isize, flags), @as(isize, 1), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0) });
        // PredictRoute returns false when maxareas stops short of the final goal.
        if (route.time <= 0 or route.stopevent == c.RSE_NOROUTE) return null;
        return .{ .point = route.endpos, .jump = route.endtravelflags & (c.TFL_JUMP | c.TFL_BARRIERJUMP) != 0, .from_area = @intCast(from), .to_area = @intCast(to) };
    }
};
fn variable(name: [:0]const u8, value: [:0]const u8) void {
    _ = engine.gateway.call(c.BOTLIB_LIBVAR_SET, .{ name.ptr, value.ptr });
}
