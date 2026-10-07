// SPDX-License-Identifier: GPL-2.0-or-later
//! Owner-thread botlib lifecycle and AAS projection. No gameplay policy lives here.
const std = @import("std");
const abi = @import("abi.zig");
const engine = @import("server.zig");
const rules = @import("../domain/navigation.zig");
const c = abi.c;
pub const Navigation = struct {
    started: bool = false,
    owns_library: bool = false,
    pub fn init(self: *Navigation, allocator: std.mem.Allocator, now: i64, restart: bool, resident: bool) !void {
        if (engine.integer("bot_enable") == 0) return error.NavigationRequiresBotlib;
        // A fast VM restart retains the engine hunk and its navigation world.
        // Only full map admission may allocate/load a new bot library.
        if (restart) {
            if (engine.gateway.call(c.BOTLIB_AAS_INITIALIZED, .{}) == 0) return error.NavigationRestartUnavailable;
            self.started = true;
            self.owns_library = true;
            for (0..c.MAX_GENTITIES) |index| _ = engine.gateway.call(c.BOTLIB_UPDATENTITY, .{ @as(isize, @intCast(index)), @as(?*c.bot_entitystate_t, null) });
            try self.frame(now);
            engine.print("dk3 zig navigation: retained engine world for match restart\n");
            return;
        }
        var map_buffer: [c.MAX_QPATH]u8 = @splat(0);
        _ = engine.mapName(&map_buffer);
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
        if (resident) {
            // The region's bot library already exists. Admit only this map's
            // navigation, with the matching server/collision context selected.
            if (engine.gateway.call(c.G_DK3_NAV_LOAD_V1, .{asset.ptr}) == 0) return error.NavigationLoad;
            self.started = true;
        } else {
            var number: [16]u8 = undefined;
            variable("maxclients", try std.fmt.bufPrintZ(&number, "{d}", .{c.MAX_CLIENTS}));
            variable("maxentities", try std.fmt.bufPrintZ(&number, "{d}", .{c.MAX_GENTITIES}));
            variable("dk3_navigation", "1");
            var checksum: [32]u8 = @splat(0);
            _ = engine.gateway.call(c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "sv_mapChecksum"), &checksum, @as(isize, checksum.len) });
            variable("sv_mapChecksum", checksum[0..std.mem.indexOfScalar(u8, &checksum, 0).? :0]);
            if (engine.gateway.call(c.BOTLIB_SETUP, .{}) != 0) return error.NavigationSetup;
            self.started = true;
            self.owns_library = true;
            errdefer self.deinit(false);
            if (engine.gateway.call(c.BOTLIB_LOAD_MAP, .{asset.ptr}) != 0) return error.NavigationLoad;
            self.owns_library = true;
            if (engine.gateway.call(c.G_DK3_NAV_BIND_V1, .{}) == 0) return error.NavigationWorldBinding;
        }
        try self.frame(now);
        var message: [192]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig navigation: map={s} asset={s} mode={s}\n", .{ map, selected, @tagName(mode) }));
    }
    pub fn deinit(self: *Navigation, restart: bool) void {
        if (self.started and self.owns_library and !restart) _ = engine.gateway.call(c.BOTLIB_SHUTDOWN, .{});
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
        return .{ .context = self, .next_fn = next, .predict_fn = predict, .travel_fn = travel };
    }
    /// Successive positions along the predicted route, one per area crossed.
    fn predict(raw: *anyopaque, request: rules.Request, points: [][3]f32) !usize {
        const self: *Navigation = @ptrCast(@alignCast(raw));
        if (!self.started or engine.gateway.call(c.BOTLIB_AAS_INITIALIZED, .{}) == 0) return 0;
        const count = predictFrom(request, points, false);
        return if (count > 0) count else predictFrom(request, points, true);
    }
    fn predictFrom(request: rules.Request, points: [][3]f32, nudged: bool) usize {
        var origin: [3]f32 = request.position;
        const from = startArea(request, &origin, nudged);
        const to = destinationArea(request.destination);
        if (from == 0 or to == 0) return 0;
        const flags = requestFlags(request);
        var count: usize = 0;
        var areas: isize = 1;
        while (count < points.len and areas <= 512) : (areas += 1) {
            var route = std.mem.zeroes(c.aas_predictroute_t);
            _ = engine.gateway.call(c.BOTLIB_AAS_PREDICT_ROUTE, .{ &route, from, &origin, to, @as(isize, flags), areas, @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0) });
            if (route.stopevent == c.RSE_NOROUTE) break;
            // This botlib does not count numareas; an unchanged end means the
            // prediction stopped short of `areas` at the goal.
            const point: [3]f32 = route.endpos;
            if (count != 0 and rules.horizontalDistance(point, points[count - 1]) <= 1 and @abs(point[2] - points[count - 1][2]) <= 1) break;
            points[count] = point;
            count += 1;
            if (route.endarea == to) break;
        }
        return count;
    }
    /// Botlib travel time (hundredths of a second) at running pace, 320 u/s.
    fn travel(raw: *anyopaque, request: rules.Request) !?f32 {
        const self: *Navigation = @ptrCast(@alignCast(raw));
        if (!self.started or engine.gateway.call(c.BOTLIB_AAS_INITIALIZED, .{}) == 0) return null;
        return travelFrom(request, false) orelse travelFrom(request, true);
    }
    fn travelFrom(request: rules.Request, nudged: bool) ?f32 {
        var origin: [3]f32 = request.position;
        const from = startArea(request, &origin, nudged);
        const to = destinationArea(request.destination);
        if (from == 0 or to == 0) return null;
        if (from == to) return 0;
        const time = engine.gateway.call(c.BOTLIB_AAS_AREA_TRAVEL_TIME_TO_GOAL_AREA, .{ from, &origin, to, @as(isize, requestFlags(request)) });
        if (time <= 0) return null;
        return @as(f32, @floatFromInt(time)) * 3.2;
    }
    fn next(raw: *anyopaque, request: rules.Request) !?rules.Waypoint {
        const self: *Navigation = @ptrCast(@alignCast(raw));
        if (!self.started or engine.gateway.call(c.BOTLIB_AAS_INITIALIZED, .{}) == 0) return null;
        return nextFrom(request, false) orelse nextFrom(request, true);
    }
    fn nextFrom(request: rules.Request, nudged: bool) ?rules.Waypoint {
        var origin: [3]f32 = request.position;
        const from = startArea(request, &origin, nudged);
        const to = destinationArea(request.destination);
        if (from == 0 or to == 0) return null;
        if (from == to) return .{ .point = request.destination, .from_area = @intCast(from), .to_area = @intCast(to) };
        var flags = requestFlags(request);
        var route = std.mem.zeroes(c.aas_predictroute_t);
        _ = engine.gateway.call(c.BOTLIB_AAS_PREDICT_ROUTE, .{ &route, from, &origin, to, @as(isize, flags), @as(isize, 1), @as(isize, 0), @as(isize, c.RSE_USETRAVELTYPE), @as(isize, 0), @as(isize, flags), @as(isize, 0) });
        if (route.stopevent == c.RSE_NOROUTE and request.allow_slime_escape) {
            flags |= c.TFL_SLIME;
            route = std.mem.zeroes(c.aas_predictroute_t);
            _ = engine.gateway.call(c.BOTLIB_AAS_PREDICT_ROUTE, .{ &route, from, &origin, to, @as(isize, flags), @as(isize, 1), @as(isize, 0), @as(isize, c.RSE_USETRAVELTYPE), @as(isize, 0), @as(isize, flags), @as(isize, 0) });
        }
        if (route.stopevent == c.RSE_NOROUTE) {
            if (engine.integer("developer") >= 3) {
                var text: [160]u8 = undefined;
                engine.print(std.fmt.bufPrintZ(&text, "dk3 navigation: no route from={d} to={d} origin={d:.0},{d:.0},{d:.0}\n", .{ from, to, origin[0], origin[1], origin[2] }) catch "");
            }
            return null;
        }
        // Approach the reachability entrance before crossing it. A shortcut to its
        // far endpoint can cut across the wall at a corner or launch a jump early.
        // A lift's entrance is marked too: the rider waits there for the lift.
        if (rules.horizontalDistance(request.position, route.endpos) > 20) return .{ .point = route.endpos, .crouch = crouchOnly(from), .elevator = route.endtravelflags & c.TFL_ELEVATOR != 0, .drop = route.endtravelflags & c.TFL_WALKOFFLEDGE != 0, .entrance = route.endpos, .from_area = @intCast(from), .to_area = @intCast(to) };
        const entrance: [3]f32 = route.endpos;
        route = std.mem.zeroes(c.aas_predictroute_t);
        _ = engine.gateway.call(c.BOTLIB_AAS_PREDICT_ROUTE, .{ &route, from, &origin, to, @as(isize, flags), @as(isize, 1), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0) });
        // PredictRoute returns false when maxareas stops short of the final goal.
        if (route.time <= 0 or route.stopevent == c.RSE_NOROUTE) return null;
        // A hop the player already stands on (a thin water layer whose entry
        // lies just below its feet) is never reached by moving toward it: aim
        // at the area after it.
        if (route.endarea != to and rules.horizontalDistance(request.position, route.endpos) < 8 and @abs(request.position[2] - route.endpos[2]) < 16) {
            var further = std.mem.zeroes(c.aas_predictroute_t);
            _ = engine.gateway.call(c.BOTLIB_AAS_PREDICT_ROUTE, .{ &further, from, &origin, to, @as(isize, flags), @as(isize, 2), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0) });
            if (further.stopevent != c.RSE_NOROUTE and further.time > 0 and rules.horizontalDistance(request.position, further.endpos) >= 8) route = further;
        }
        // Walking links into a crawlway are ordinary walks: the areas'
        // presence says when only the ducked hull fits.
        return .{ .point = route.endpos, .jump = route.endtravelflags & (c.TFL_JUMP | c.TFL_BARRIERJUMP) != 0, .crouch = route.endtravelflags & c.TFL_CROUCH != 0 or crouchOnly(from) or crouchOnly(route.endarea), .ladder = route.endtravelflags & c.TFL_LADDER != 0, .elevator = route.endtravelflags & c.TFL_ELEVATOR != 0, .drop = route.endtravelflags & c.TFL_WALKOFFLEDGE != 0, .entrance = entrance, .from_area = @intCast(from), .to_area = @intCast(to) };
    }
};
/// The player's area (botlib's guess). `nudged`, for one pressed against a
/// wall just outside the area graph's expanded solid when that guess has no
/// route (it can be an area above or below): the nearest area a short step
/// away that the hull reaches unobstructed.
fn startArea(request: rules.Request, origin: *[3]f32, nudged: bool) isize {
    if (!nudged) return engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &request.position, @as(isize, request.slot) });
    if (engine.gateway.call(c.BOTLIB_AAS_POINT_AREA_NUM, .{&request.position}) != 0) return 0;
    const directions = [_][2]f32{ .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 }, .{ 0.7071, 0.7071 }, .{ -0.7071, 0.7071 }, .{ 0.7071, -0.7071 }, .{ -0.7071, -0.7071 } };
    for ([_]f32{ 8, 16 }) |distance| for (directions) |direction| {
        const point: [3]f32 = .{ request.position[0] + direction[0] * distance, request.position[1] + direction[1] * distance, request.position[2] };
        const area = engine.gateway.call(c.BOTLIB_AAS_POINT_AREA_NUM, .{&point});
        if (area <= 0 or engine.gateway.call(c.BOTLIB_AAS_AREA_REACHABILITY, .{area}) == 0) continue;
        const clear = engine.collisionService().trace(.{ .start = request.position, .end = point, .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 4 }, .slot = request.slot, .mask = c.MASK_PLAYERSOLID }) catch continue;
        if (clear.start_solid or clear.fraction < 1) continue;
        origin.* = point;
        return area;
    };
    return 0;
}
/// Only the ducked hull fits the area (botlib PRESENCE_CROUCH without PRESENCE_NORMAL).
fn crouchOnly(area: isize) bool {
    var info = std.mem.zeroes(c.aas_areainfo_t);
    if (area <= 0 or engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ area, &info }) == 0) return false;
    return info.presencetype & 2 == 0 and info.presencetype & 4 != 0;
}
/// Area of a destination. A standing origin lies exactly on the boundary of
/// its thin floor area, where the lookup can fall into neither: retry a few
/// units higher before giving up.
pub fn destinationArea(point: [3]f32) isize {
    // The area the point lies in, or one a little above it (a goal set at an
    // item's base in a crawlway sits below the lowest origin there): botlib's
    // own guess from inside solid can be the floor beneath.
    for ([_]f32{ 0, 4, 12, 16, 24 }) |rise| {
        const probe: [3]f32 = .{ point[0], point[1], point[2] + rise };
        const area = engine.gateway.call(c.BOTLIB_AAS_POINT_AREA_NUM, .{&probe});
        if (area > 0 and engine.gateway.call(c.BOTLIB_AAS_AREA_REACHABILITY, .{area}) != 0) return area;
    }
    for ([_]f32{ 0, 4, 12 }) |rise| {
        const probe: [3]f32 = .{ point[0], point[1], point[2] + rise };
        const area = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &probe, @as(isize, c.ENTITYNUM_NONE) });
        if (area != 0) return area;
    }
    return 0;
}
/// A request's travel flags: lift links left out when the lift is away
/// and the traveller cannot call it.
fn requestFlags(request: rules.Request) i32 {
    const flags = travelFlags(request.player);
    return if (request.lifts) flags else flags & ~@as(i32, c.TFL_ELEVATOR | c.TFL_FUNCBOB);
}
pub fn travelFlags(player: bool) i32 {
    // WATER admits areas containing ordinary water, including shallow floors.
    // SWIM is a separate reachability capability. Ground actors still require
    // supported walking/jumping edges and collision-checked floor movement.
    // Damaging volumes are compiled as areas flagged no-entry; the game's
    // navigation gates disable the ones switched on and harmful, so a player
    // route may cross those that are off.
    return c.TFL_WALK | c.TFL_BARRIERJUMP | c.TFL_JUMP | c.TFL_AIR | c.TFL_WATER |
        (if (player) @as(i32, c.TFL_CROUCH | c.TFL_LADDER | c.TFL_SWIM | c.TFL_WATERJUMP | c.TFL_WALKOFFLEDGE | c.TFL_TELEPORT | c.TFL_ELEVATOR | c.TFL_FUNCBOB | c.TFL_NOTTEAM1 | c.TFL_NOTTEAM2) else 0);
}
test "ground routes admit wet walking areas without swimming or hazardous liquid travel" {
    const t = std.testing;
    const ground = travelFlags(false);
    try t.expect(ground & c.TFL_WATER != 0);
    try t.expect(ground & (c.TFL_SWIM | c.TFL_WATERJUMP | c.TFL_SLIME | c.TFL_LAVA | c.TFL_LADDER | c.TFL_ELEVATOR) == 0);
    try t.expect(ground & (c.TFL_WALK | c.TFL_JUMP | c.TFL_BARRIERJUMP) == (c.TFL_WALK | c.TFL_JUMP | c.TFL_BARRIERJUMP));
    try t.expect(travelFlags(true) & (c.TFL_SWIM | c.TFL_WATER | c.TFL_LADDER | c.TFL_ELEVATOR) == (c.TFL_SWIM | c.TFL_WATER | c.TFL_LADDER | c.TFL_ELEVATOR));
}
fn variable(name: [:0]const u8, value: [:0]const u8) void {
    _ = engine.gateway.call(c.BOTLIB_LIBVAR_SET, .{ name.ptr, value.ptr });
}
