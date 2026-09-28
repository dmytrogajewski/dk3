// SPDX-License-Identifier: GPL-2.0-or-later
//! Owns visited-world bytes and a single player transfer across module unloads.
//! One validated atomic transfer file contains all required campaign state.
const std = @import("std");
const data = @import("../domain/components.zig");
const travel = @import("../domain/travel.zig");
const snapshot = @import("../domain/snapshot.zig");
const persistence = @import("persistence.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const allocator = std.heap.c_allocator;
pub const Arrival = struct { journey: travel.Journey, traveler: travel.Traveler };
pub const State = struct {
    arena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(allocator),
    visited: []const snapshot.Archive = &.{},
    arrival: ?Arrival = null,
    departing: bool = false,
    pub fn deinit(self: *State) void {
        self.arena.deinit();
        self.* = .{};
    }
    pub fn fromArchives(archives: []const snapshot.Archive) !State {
        var result: State = .{};
        errdefer result.deinit();
        const entries = try result.arena.allocator().alloc(snapshot.Archive, archives.len);
        for (archives, entries) |archive, *entry| entry.* = try clone(result.arena.allocator(), archive);
        result.visited = entries;
        return result;
    }
};
fn clone(memory: std.mem.Allocator, archive: snapshot.Archive) !snapshot.Archive {
    return .{ .map = try memory.dupe(u8, archive.map), .bytes = try memory.dupe(u8, archive.bytes) };
}
pub const Prepared = struct { state: State, world: ?snapshot.Loaded };
pub fn prepare(transfer: *snapshot.Loaded, destination: []const u8, now: i64, table: *const @import("../domain/weapons.zig").Table) !Prepared {
    const journey = transfer.header.journey orelse return error.MissingJourney;
    if (!std.mem.eql(u8, journey.destination, destination)) return error.JourneyMapMismatch;
    var result: Prepared = .{ .state = .{}, .world = null };
    errdefer {
        if (result.world) |*world| world.deinit(allocator);
        result.state.deinit();
    }
    const memory = result.state.arena.allocator();
    var entries: std.ArrayList(snapshot.Archive) = .empty;
    var traveler = try travel.Traveler.capture(&transfer.world, transfer.world.find(transfer.header.player_id).?, transfer.header.episode, transfer.header.at_ms);
    if (journey.kind == .submap) for (&traveler.companions, 0..) |*follower, index| {
        if (journey.companions & (@as(u2, 1) << @as(u1, @intCast(index))) == 0) {
            follower.* = null;
        } else if (follower.*) |value| {
            // Traveling party members are absent from the archived world. Those
            // deliberately left behind retain their own position and inventory.
            if (@import("companions.zig").find(&transfer.world, value.state.identity)) |entity| try transfer.world.destroy(entity);
        }
    };

    if (journey.kind == .submap) {
        for (transfer.visited) |archive| {
            if (std.mem.eql(u8, archive.map, destination)) {
                result.world = try snapshot.decode(allocator, archive.bytes);
            } else try entries.append(memory, try clone(memory, archive));
        }
        if (entries.items.len >= snapshot.archive_limit) return error.ArchiveCapacity;
        var header = transfer.header;
        header.journey = null;
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        const buffer = try scratch.allocator().alloc(u8, snapshot.world_limit);
        const bytes = try snapshot.capture(scratch.allocator(), buffer, &transfer.world, transfer.map, transfer.skill, header);
        const archive = try clone(memory, .{ .map = transfer.map, .bytes = bytes });
        try entries.append(memory, archive);
    }
    result.state.visited = entries.items;
    const episode = if (destination.len >= 2 and destination[0] == 'e' and destination[1] >= '1' and destination[1] <= '4') destination[1] - '0' else transfer.header.episode;
    try traveler.arrive(episode, now, table);
    var owned = journey;
    owned.destination = try memory.dupe(u8, destination);
    owned.spawn = try memory.dupe(u8, journey.spawn);
    result.state.arrival = .{ .journey = owned, .traveler = traveler };
    return result;
}
pub fn spawn(world: *data.World) !void {
    var ids: [@import("../ecs/world.zig").max_entities]@import("../ecs/world.zig").Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.mem.eql(u8, object.classname, "trigger_changelevel")) {
            ids[count] = entity;
            count += 1;
        };
    }
    for (ids[0..count]) |entity| if ((world.get(entity, data.Exit) catch null) == null) {
        try world.put(entity, data.Exit{});
    };
}
pub fn departure(world: *data.World, clients: *const @import("clients.zig").Clients, systems: *@import("world_systems.zig").State, projections: []const @import("../engine/abi.zig").EntityProjection, request: travel.Request, now: i64) !?travel.Journey {
    if (engine.integer("g_gametype") != c.GT_SINGLE_PLAYER) return error.CampaignExitRequiresSinglePlayer;
    const exit = world.find(request.exit) orelse return error.MissingExit;
    const player = clients.entities[0] orelse return error.MissingTraveler;
    if (try world.persistentId(player) != request.player or (try world.get(player, data.Health)).current <= 0) return error.InvalidTraveler;
    const object = (try world.get(exit, data.MapObject)).*;
    if (!try @import("companions.zig").required(world, player, object.flags)) return error.ExitRequiresCompanions;
    if (@import("properties.zig").text(object, "cinematic")) |name| if (name.len > 0 and systems.cinematics.available(name)) {
        const controller = @import("cinematics.zig").findController(world);
        const completed = if (controller) |entity| blk: {
            const playback = (try world.get(entity, data.Cinematic)).*;
            break :blk playback.finished and playback.exit == request.exit;
        } else false;
        if (!completed) {
            if (try systems.cinematics.trigger(world, exit, name, request.player)) {
                (try world.get(@import("cinematics.zig").findController(world).?, data.Cinematic)).exit = request.exit;
            }
            return null;
        }
    };
    if (object.flags & 8 != 0) {
        const ending = try world.get(exit, data.Exit);
        if (ending.ending_started == null) {
            ending.ending_player = request.player;
            ending.ending_started = now;
            ending.camera = try intermissionPose(world);
            (try world.get(player, data.Player)).mode = .frozen;
            (try world.get(player, data.Body)).motion_owner = request.exit;
            (try world.get(player, data.Velocity)).linear = @splat(0);
            engine.send(0, "cp \"Campaign complete\nPress a key after the intermission to continue\"");
            return null;
        }
        if (now <= ending.ending_started.? + 5000) return null;
        var input: c.usercmd_t = undefined;
        engine.usercmd(0, &input);
        if (input.buttons & c.BUTTON_ANY == 0) return null;
    }
    const destination = @import("properties.zig").text(object, "map") orelse return error.MissingExitMap;
    if (!snapshot.validName(destination)) return error.InvalidExitMap;
    var name: [64]u8 = undefined;
    const current = persistence.mapName(&name);
    if (std.mem.eql(u8, current, destination)) return null;
    var path: [80]u8 = undefined;
    const bsp = try std.fmt.bufPrintZ(&path, "maps/{s}.bsp", .{destination});
    var file: c.fileHandle_t = 0;
    const length = engine.gateway.call(c.G_FS_FOPEN_FILE, .{ bsp.ptr, &file, @as(isize, c.FS_READ) });
    if (file != 0) _ = engine.gateway.call(c.G_FS_FCLOSE_FILE, .{@as(isize, file)});
    if (length <= 0 or file == 0) return error.ExitMapUnavailable;
    const projection = projections[(try world.get(exit, data.Binding)).slot];
    const v = @import("../domain/vector.zig");
    const pose = (try world.get(player, data.Transform)).*;
    const journey: travel.Journey = .{ .destination = destination, .spawn = object.target, .offset = v.add(pose.position, v.scale(v.add(projection.shared.absmin, projection.shared.absmax), -0.5)), .angles = pose.angles, .kind = travel.kind(current, destination), .companions = @as(u2, if (object.flags & 4 != 0) 1 else 0) | @as(u2, if (object.flags & 2 != 0) 2 else 0) };
    return journey;
}
pub fn departPrepared(state: *State, world: *data.World, clients: *const @import("clients.zig").Clients, targets: *const @import("targets.zig").Router, systems: *@import("world_systems.zig").State, journey: travel.Journey, now: i64) !void {
    const player = clients.entities[0] orelse return error.MissingTraveler;
    const destination = journey.destination;
    var name: [64]u8 = undefined;
    const current = persistence.mapName(&name);
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const buffer = try scratch.allocator().alloc(u8, snapshot.maximum);
    const bytes = try persistence.capture(scratch.allocator(), buffer, world, clients, targets, now, if (journey.kind == .submap) state.visited else &.{}, journey);
    var admitted = try snapshot.decode(allocator, bytes);
    defer admitted.deinit(allocator);
    try persistence.admit(&admitted, systems);
    try @import("../engine/save_storage.zig").write("dk3-travel-internal", bytes, false);
    _ = engine.gateway.call(c.G_CVAR_SET, .{ @as([*:0]const u8, "dk3_travel_pending"), @as([*:0]const u8, "1") });
    _ = engine.gateway.call(c.G_CVAR_SET, .{ @as([*:0]const u8, "dk3_resume"), @as([*:0]const u8, "0") });
    var text: [256]u8 = undefined;
    const command = try std.fmt.bufPrintZ(&text, "map {s}\n", .{destination});
    _ = engine.gateway.call(c.G_SEND_CONSOLE_COMMAND, .{ @as(isize, c.EXEC_APPEND), command.ptr });
    state.departing = true;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig: campaign departure {s} -> {s} via {s} health={d}\n", .{ current, destination, journey.spawn, (try world.get(player, data.Health)).current }));
}
pub fn disarmArrival(world: *data.World, projections: []const @import("../engine/abi.zig").EntityProjection, player: @import("../ecs/world.zig").Entity) !void {
    const player_slot = (try world.get(player, data.Binding)).slot;
    var query = world.queryAccess(data.World.mask(.{ data.Exit, data.Binding }), 0, data.World.mask(.{data.Exit}));
    defer query.deinit();
    while (query.next()) |view| for (view.write(data.Exit), view.read(data.Binding)) |*exit, binding| {
        exit.latched = @import("interactions.zig").overlap(&projections[player_slot], &projections[binding.slot], 0);
    };
}

fn intermissionPose(world: *data.World) !data.Transform {
    var best: ?data.Transform = null;
    var target: []const u8 = "";
    var best_id: u32 = std.math.maxInt(u32);
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject), view.read(data.Transform)) |entity, object, pose| {
            if (!std.mem.eql(u8, object.classname, "info_player_intermission")) continue;
            const id = try world.persistentId(entity);
            if (id < best_id) {
                best = pose;
                target = object.target;
                best_id = id;
            }
        };
    }
    var pose = best orelse (try @import("spawns.zig").select(world, "")).pose;
    if (target.len > 0) if (@import("scripts.zig").named(world, target)) |entity| {
        const v = @import("../domain/vector.zig");
        const delta = v.subtract((try world.get(entity, data.Transform)).position, pose.position);
        pose.angles = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
    };
    return pose;
}
pub fn endings(world: *data.World, router: *@import("targets.zig").Router, now: i64) !void {
    var query = world.queryAccess(data.World.mask(.{data.Exit}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Exit)) |entity, exit| if (exit.ending_started) |started| {
        if (now > started + 5000 and router.travel == null) {
            var input: c.usercmd_t = undefined;
            engine.usercmd(0, &input);
            if (input.buttons & c.BUTTON_ANY != 0) router.travel = .{ .exit = try world.persistentId(entity), .player = exit.ending_player };
        }
    };
}
pub fn camera(world: *data.World, player: @import("../ecs/world.zig").Entity, ps: *c.playerState_t) !void {
    const owner = (try world.get(player, data.Body)).motion_owner orelse return;
    const exit = world.get(world.find(owner) orelse return, data.Exit) catch return;
    if (exit.ending_started == null) return;
    ps.dk3CameraActive = 4;
    ps.dk3CameraOrigin = exit.camera.position;
    ps.dk3CameraAngles = exit.camera.angles;
    ps.dk3CameraFov = 90;
    ps.dk3CameraBlend = @splat(0);
}
