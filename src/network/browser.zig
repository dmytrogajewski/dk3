// SPDX-License-Identifier: GPL-2.0-or-later
//! Asynchronous native room browser. Engine/VM services stay on the main thread.
const std = @import("std");
const c = @import("abi.zig").c;
const api = @import("../online/api.zig");
const guest = @import("../online/client.zig");
const admission = @import("admission.zig");
const Action = enum { list, create, join };
const Job = struct {
    arena: std.heap.ArenaAllocator,
    config: guest.Config,
    action: Action,
    create: api.RoomConfig,
    request_id: []const u8,
    room: []const u8,
    code: []const u8,
    rooms: []api.Room = &.{},
    joined: ?guest.Joined = null,
    created: ?guest.Created = null,
    failure: ?anyerror = null,
    done: std.atomic.Value(bool) = .init(false),
    canceled: bool = false,
    thread: ?std.Thread = null,
};
var pending: ?*Job = null;
var room_ids: [128][65:0]u8 = @splat(@splat(0));
var room_count: usize = 0;
const Ping = struct { address: c.netadr_t = std.mem.zeroes(c.netadr_t), challenge: [33:0]u8 = @splat(0), sent: c_int = 0, state: enum { idle, queued, waiting, done } = .idle };
var pings: [128]Ping = @splat(.{});
var next_ping: c_int = 0;
fn pingValue(index: usize, text: [*:0]const u8) void {
    const name = c.va("dk3_room%d", @as(c_int, @intCast(index)));
    var info: [1024]u8 = undefined;
    c.Q_strncpyz(&info, c.Cvar_VariableString(name), info.len);
    c.Info_SetValueForKey(&info, "ping", text);
    c.Cvar_Set(name, &info);
}
fn pollPings() void {
    const now = c.Sys_Milliseconds();
    for (&pings, 0..) |*ping, index| {
        if (ping.state == .waiting and now -% ping.sent >= 5000) {
            ping.state = .done;
            pingValue(index, "timeout");
        }
        if (ping.state != .queued or now -% next_ping < 0) continue;
        ping.sent = now;
        ping.state = .waiting;
        next_ping = now +% 100;
        c.NET_OutOfBandPrint(c.NS_CLIENT, ping.address, "getinfo dk3-room-%s", &ping.challenge);
        break;
    }
}
export fn DK_OnlineInfo(from: c.netadr_t, info: [*:0]const u8) callconv(.c) c_int {
    const challenge = std.mem.span(c.Info_ValueForKey(info, "challenge"));
    if (!std.mem.startsWith(u8, challenge, "dk3-room-")) return 0;
    for (&pings, 0..) |*ping, index| {
        if (ping.state != .waiting or c.NET_CompareAdr(from, ping.address) == 0 or !std.mem.eql(u8, challenge[9..], std.mem.sliceTo(&ping.challenge, 0))) continue;
        const elapsed = c.Sys_Milliseconds() -% ping.sent;
        if (elapsed < 0 or elapsed > 5000) return 1;
        ping.state = .done;
        pingValue(index, c.va("%d ms", @as(c_int, @max(1, elapsed))));
        break;
    }
    return 1;
}
fn value(name: [*:0]const u8) []const u8 {
    return std.mem.span(c.Cvar_VariableString(name));
}
fn status(text: [*:0]const u8) void {
    c.Cvar_Set("dk3_onlineStatus", text);
}
fn load(a: std.mem.Allocator, path: [*:0]const u8) ![]u8 {
    const size = c.FS_ReadFile(path, null);
    if (size <= 0 or size > 65536) return error.MissingCompatibility;
    var data: ?*anyopaque = null;
    if (c.FS_ReadFile(path, &data) != size or data == null) {
        if (data != null) c.FS_FreeFile(data);
        return error.MissingCompatibility;
    }
    defer c.FS_FreeFile(data);
    const bytes: [*]const u8 = @ptrCast(data.?);
    return a.dupe(u8, bytes[0..@intCast(size)]);
}
fn textCopy(a: std.mem.Allocator, name: [*:0]const u8) ![]const u8 {
    return a.dupe(u8, value(name));
}
fn begin(action: Action, id: []const u8) !void {
    if (pending != null) return error.Busy;
    const job = try std.heap.c_allocator.create(Job);
    errdefer std.heap.c_allocator.destroy(job);
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    const config_data = try load(a, "compatibility.json");
    const compatibility = (try std.json.parseFromSlice(api.Compatibility, a, config_data, .{ .allocate = .alloc_always })).value;
    const ca_file = try textCopy(a, "dk3_ca_file");
    const home = c.Cvar_VariableString("fs_homedatapath");
    const identity_path = try a.dupe(u8, std.mem.span(c.FS_BuildOSPath(home, "dk3", "guest.key")));
    const mode: api.Mode = switch (c.Cvar_VariableIntegerValue("ui_roomMode")) {
        1 => .ctf,
        2 => .deathtag,
        else => .dm,
    };
    const slots: u8 = @intCast(std.math.clamp(c.Cvar_VariableIntegerValue("ui_roomSlots"), 2, 32));
    var request_id = try textCopy(a, "ui_roomRequest");
    const config: guest.Config = .{ .coordinator = try textCopy(a, "dk3_coordinator"), .ca_file = if (ca_file.len == 0) null else ca_file, .identity_file = identity_path, .compatibility = compatibility };
    var rotation: std.ArrayList([]const u8) = .empty;
    var map_names = std.mem.tokenizeAny(u8, value("ui_roomRotation"), " ,\t");
    while (map_names.next()) |map_name| {
        if (rotation.items.len == 64) return error.InvalidRoom;
        try rotation.append(a, try a.dupe(u8, map_name));
    }
    const create: api.RoomConfig = .{ .rotation = rotation.items, .name = try textCopy(a, "ui_roomName"), .region = try textCopy(a, "ui_roomRegion"), .mode = mode, .map = try textCopy(a, "ui_roomMap"), .slots = slots, .bots = @intCast(std.math.clamp(c.Cvar_VariableIntegerValue("ui_roomBots"), 0, slots - 1)), .skill = @intCast(std.math.clamp(c.Cvar_VariableIntegerValue("ui_roomSkill"), 1, 5)), .privacy = if (c.Cvar_VariableIntegerValue("ui_roomPrivate") != 0) .private else .public };
    if (action == .create) {
        const body = try std.json.Stringify.valueAlloc(a, create, .{});
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(body, &hash, .{});
        const digest = std.fmt.bytesToHex(hash, .lower);
        if (request_id.len == 0 or !std.mem.eql(u8, &digest, value("ui_roomRequestBody"))) {
            var random: [32]u8 = undefined;
            if (c.Sys_RandomBytes(&random, random.len) == 0) return error.EntropyUnavailable;
            const id_text = try a.dupeZ(u8, &std.fmt.bytesToHex(random, .lower));
            c.Cvar_Set("ui_roomRequest", id_text.ptr);
            c.Cvar_Set("ui_roomRequestBody", (try a.dupeZ(u8, &digest)).ptr);
            request_id = id_text;
        }
    }
    const room = try a.dupe(u8, id);
    const code = try textCopy(a, "ui_roomCode");
    job.* = .{ .arena = arena, .action = action, .config = config, .create = create, .request_id = request_id, .room = room, .code = code };
    job.thread = try std.Thread.spawn(.{ .stack_size = 4 << 20 }, run, .{job});
    pending = job;
    status("Contacting room service...");
}
fn run(job: *Job) void {
    execute(job) catch |err| {
        job.failure = err;
    };
    job.done.store(true, .release);
}
fn execute(job: *Job) !void {
    var threaded = std.Io.Threaded.init(std.heap.c_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const a = job.arena.allocator();
    var client = try guest.Client.init(a, io, job.config);
    defer client.deinit();
    if (job.action == .list) {
        job.rooms = try client.list();
        return;
    }
    try client.login();
    var room = job.room;
    var code = job.code;
    if (job.action == .create) {
        const request_id = if (job.request_id.len > 0) job.request_id else &(try @import("../online/identity.zig").token(io));
        job.created = try client.create(request_id, job.create);
        room = job.created.?.room.id;
        code = job.created.?.access_code;
    }
    for (0..30) |_| {
        job.joined = client.join(room, code) catch |err| switch (err) {
            error.NoWorker => {
                try io.sleep(.fromSeconds(1), .awake);
                continue;
            },
            else => return err,
        };
        return;
    }
    return error.NoWorker;
}
fn description(err: anyerror) [*:0]const u8 {
    return switch (err) {
        error.MissingCompatibility => "Install the current game assets and compatibility manifest first.",
        error.HttpsRequired => "Configure an HTTPS room coordinator in online settings.",
        error.Incompatible => "This room requires different gameplay content or a supported build.",
        error.NoWorker => "No compatible worker is ready in that region.",
        error.Capacity => "The room or hosting capacity is full.",
        error.Forbidden => "The private room code is missing or incorrect.",
        error.Banned => "This identity is banned from the room service.",
        error.Conflict => "A conflicting room request or connection is already active.",
        error.CertificateVerificationFailed => "HTTPS certificate verification failed. Check the configured test CA.",
        error.Busy => "A room request is already running.",
        error.RateLimited => "Too many requests. Wait before trying again.",
        error.RequestTimedOut => "The room service did not respond in time.",
        else => "Room request failed. Check the coordinator address and trusted certificate.",
    };
}
fn clean(a: std.mem.Allocator, text: []const u8) ![:0]u8 {
    var buffer: [128]u8 = undefined;
    var length: usize = 0;
    for (text) |ch| {
        if (length == buffer.len) break;
        if (ch < 32 or ch == 127 or ch == '"' or ch == '\\' or ch == ';') continue;
        buffer[length] = ch;
        length += 1;
    }
    return a.dupeZ(u8, buffer[0..length]);
}
fn favorite(id: []const u8) bool {
    var ids = std.mem.splitScalar(u8, value("dk3_roomFavorites"), ',');
    while (ids.next()) |saved| if (std.mem.eql(u8, id, saved)) return true;
    return false;
}
fn matches(room: api.Room, compatibility: api.Compatibility) bool {
    const filter_mode = c.Cvar_VariableIntegerValue("ui_roomFilterMode");
    if (filter_mode >= 0 and filter_mode != @intFromEnum(room.config.mode)) return false;
    const region = value("ui_roomFilterRegion");
    if (region.len > 0 and !std.ascii.eqlIgnoreCase(region, room.config.region)) return false;
    const search = value("ui_roomSearch");
    if (search.len > 0 and std.ascii.indexOfIgnoreCase(room.config.name, search) == null and std.ascii.indexOfIgnoreCase(room.config.map, search) == null) return false;
    if (c.Cvar_VariableIntegerValue("ui_roomFavoritesOnly") != 0 and !favorite(room.id)) return false;
    if (c.Cvar_VariableIntegerValue("ui_roomAvailableOnly") != 0 and (room.humans + room.config.bots >= room.config.slots or !room.compatibility.compatible(compatibility))) return false;
    return true;
}
export fn DK_OnlinePoll() callconv(.c) void {
    pollPings();
    const job = pending orelse return;
    if (!job.done.load(.acquire)) return;
    job.thread.?.join();
    pending = null;
    defer {
        job.arena.deinit();
        std.heap.c_allocator.destroy(job);
    }
    if (job.canceled) {
        status("Room request canceled.");
        return;
    }
    if (job.failure) |err| {
        status(description(err));
        c.Com_Printf("dk3 room request: %s\n", @errorName(err).ptr);
        return;
    }
    if (job.action == .list) {
        room_count = 0;
        pings = @splat(.{});
        next_ping = c.Sys_Milliseconds();
        const a = job.arena.allocator();
        for (job.rooms) |room| {
            if (room_count == room_ids.len or !matches(room, job.config.compatibility)) continue;
            _ = @import("../online/identity.zig").hex(32, room.id) catch continue;
            @memcpy(room_ids[room_count][0..64], room.id);
            room_ids[room_count][64] = 0;
            var row: [1024]u8 = @splat(0);
            c.Info_SetValueForKey(&row, "id", &room_ids[room_count]);
            c.Info_SetValueForKey(&row, "ping", "...");
            const endpoint = a.dupeZ(u8, room.endpoint) catch continue;
            _ = std.Io.net.IpAddress.parseLiteral(room.endpoint) catch continue;
            const ping = &pings[room_count];
            if (c.NET_StringToAdr(endpoint.ptr, &ping.address, c.NA_UNSPEC) != 0) {
                var nonce: [16]u8 = undefined;
                if (c.Sys_RandomBytes(&nonce, nonce.len) != 0) {
                    @memcpy(ping.challenge[0..32], &std.fmt.bytesToHex(nonce, .lower));
                    ping.state = .queued;
                }
            }
            c.Info_SetValueForKey(&row, "name", (clean(a, room.config.name) catch continue).ptr);
            c.Info_SetValueForKey(&row, "map", (clean(a, room.config.map) catch continue).ptr);
            c.Info_SetValueForKey(&row, "region", (clean(a, room.config.region) catch continue).ptr);
            c.Info_SetValueForKey(&row, "mode", @tagName(room.config.mode).ptr);
            c.Info_SetValueForKey(&row, "phase", @tagName(room.phase).ptr);
            c.Info_SetValueForKey(&row, "players", c.va("%d/%d", @as(c_int, room.humans), @as(c_int, room.config.slots)));
            c.Info_SetValueForKey(&row, "compatible", if (room.compatibility.compatible(job.config.compatibility)) "1" else "0");
            c.Info_SetValueForKey(&row, "favorite", if (favorite(room.id)) "1" else "0");
            c.Cvar_Set(c.va("dk3_room%d", @as(c_int, @intCast(room_count))), &row);
            room_count += 1;
        }
        c.Cvar_Set("dk3_roomCount", c.va("%d", @as(c_int, @intCast(room_count))));
        status(if (room_count > 0)
            "Rooms refreshed. Select a room to join."
        else if (job.rooms.len == 0)
            "No public rooms. Back > Create Internet room."
        else
            "No matching rooms. Clear filters, then Refresh.");
    } else if (job.joined) |joined| {
        _ = std.Io.net.IpAddress.parseLiteral(joined.endpoint) catch {
            status("The room returned an invalid address.");
            return;
        };
        if (admission.installTicket(joined.ticket) == 0) {
            status("Room ticket expired. Join again.");
            return;
        }
        const endpoint = job.arena.allocator().dupeZ(u8, joined.endpoint) catch return;
        if (job.created) |created| {
            // Keep the token across ambiguous failures; retire it once creation
            // and admission succeed so a later create is a new user intent.
            c.Cvar_Set("ui_roomRequest", "");
            c.Cvar_Set("ui_roomRequestBody", "");
            const code = job.arena.allocator().dupeZ(u8, created.access_code) catch return;
            c.Cvar_Set("dk3_privateRoomCode", code.ptr);
        }
        const id = job.arena.allocator().dupeZ(u8, joined.ticket.room) catch return;
        c.Cvar_Set("dk3_currentRoom", id.ptr);
        c.Cvar_Set("dk3_roomEndpoint", endpoint.ptr);
        c.Cbuf_ExecuteText(c.EXEC_APPEND, c.va("connect %s\n", endpoint.ptr));
        status("Connecting to room...");
    }
}
export fn DK_OnlineCommand() callconv(.c) void {
    const verb = std.mem.span(c.Cmd_Argv(1));
    if (std.mem.eql(u8, verb, "cancel")) {
        if (pending) |job| job.canceled = true;
        return;
    }
    if (std.mem.eql(u8, verb, "list")) {
        begin(.list, "") catch |err| status(description(err));
        return;
    }
    if (std.mem.eql(u8, verb, "create")) {
        begin(.create, "") catch |err| status(description(err));
        return;
    }
    if (std.mem.eql(u8, verb, "join") or std.mem.eql(u8, verb, "favorite")) {
        const index = std.fmt.parseInt(usize, std.mem.span(c.Cmd_Argv(2)), 10) catch {
            status("Select a room first.");
            return;
        };
        if (index >= room_count) return;
        const id = std.mem.sliceTo(&room_ids[index], 0);
        if (std.mem.eql(u8, verb, "join")) {
            begin(.join, id) catch |err| status(description(err));
            return;
        }
        var list: [1024:0]u8 = @splat(0);
        var writer = std.Io.Writer.fixed(list[0..1023]);
        var old = std.mem.splitScalar(u8, value("dk3_roomFavorites"), ',');
        while (old.next()) |saved| {
            if (saved.len == 0 or std.mem.eql(u8, saved, id)) continue;
            writer.print("{s},", .{saved}) catch break;
        }
        if (!favorite(id)) writer.writeAll(id) catch {
            status("Favorites are full.");
            return;
        };
        c.Cvar_Set("dk3_roomFavorites", &list);
        status("Room favorites updated.");
        return;
    }
    if (std.mem.eql(u8, verb, "private")) {
        const id = value("ui_privateRoom");
        _ = @import("../online/identity.zig").hex(32, id) catch {
            status("Enter a valid private room ID and code.");
            return;
        };
        begin(.join, id) catch |err| status(description(err));
        return;
    }
    if (std.mem.eql(u8, verb, "reconnect")) {
        begin(.join, value("dk3_currentRoom")) catch |err| status(description(err));
        return;
    }
    c.Com_Printf("dk3_online list|create|join <row>|favorite <row>|private|reconnect|cancel\n");
}
export fn DK_OnlineInit() callconv(.c) void {
    for ([_][2][*:0]const u8{ .{ "dk3_coordinator", "" }, .{ "dk3_ca_file", "" }, .{ "dk3_roomFavorites", "" }, .{ "ui_roomName", "My room" }, .{ "ui_roomRegion", "default" }, .{ "ui_roomMap", "e1dm1" }, .{ "ui_roomRotation", "" }, .{ "ui_roomMode", "0" }, .{ "ui_roomSlots", "8" }, .{ "ui_roomBots", "0" }, .{ "ui_roomSkill", "3" }, .{ "ui_roomPrivate", "0" }, .{ "ui_roomFilterMode", "-1" }, .{ "ui_roomFilterRegion", "" }, .{ "ui_roomSearch", "" }, .{ "ui_roomFavoritesOnly", "0" }, .{ "ui_roomAvailableOnly", "1" } }) |entry| _ = c.Cvar_Get(entry[0], entry[1], c.CVAR_ARCHIVE);
    _ = c.Cvar_Get("dk3_onlineStatus", "Refresh to find Internet rooms.", c.CVAR_ROM);
    _ = c.Cvar_Get("dk3_roomCount", "0", c.CVAR_ROM);
}
