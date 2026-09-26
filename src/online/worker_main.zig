// SPDX-License-Identifier: GPL-2.0-or-later
//! One isolated dedicated process per room. The coordinator never supplies shell text.
const std = @import("std");
const api = @import("api.zig");
const permanent = @import("permanent.zig");
const Http = @import("http.zig").Client;
const Config = struct {
    coordinator: []const u8,
    token: []const u8,
    ca_file: ?[]const u8 = null,
    state: []const u8,
    engine: []const u8,
    guard: []const u8,
    assets: []const u8,
    capacity: usize = 1,
    memory: []const u8 = "2G",
};
const Process = struct {
    arena: std.heap.ArenaAllocator,
    started: i64,
    room: []const u8,
    generation: u64,
    home: []const u8,
    child: std.process.Child,
    pid: std.process.Child.Id,
    ended: std.atomic.Value(bool) = .init(false),
    reported: bool = false,
    wanted: bool = true,
    permanent_room: bool = false,
};
const Assignment = struct { rooms: []api.Room, tickets: []api.Ticket, controls: []api.Control = &.{}, permanent: []permanent.Assignment = &.{}, draining: bool };
const Status = struct { humans: u8, phase: api.Phase, members: []const api.Presence };
fn wait(process: *Process, io: std.Io) void {
    _ = process.child.wait(io) catch {};
    process.ended.store(true, .release);
}
fn stop(process: *Process) void {
    if (!process.ended.load(.acquire)) std.posix.kill(process.pid, .TERM) catch {};
}
fn retainEvidence(io: std.Io, a: std.mem.Allocator, process: *Process) !void {
    // Permanent processes stream to the bounded service journal throughout life.
    if (process.permanent_room) return;
    const path = try std.fmt.allocPrint(a, "{s}/engine.log", .{process.home});
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const size = (try file.stat(io)).size;
    var tail: [65536]u8 = undefined;
    const length = try file.readPositionalAll(io, &tail, size -| tail.len);
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    try writer.interface.print("room {s} generation {d} ended; final engine log:\n{s}\n", .{ process.room, process.generation, tail[0..length] });
    try writer.interface.flush();
}
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2 or std.mem.eql(u8, args[1], "--help")) {
        var buffer: [1024]u8 = undefined;
        var out = std.Io.File.stdout().writer(io, &buffer);
        try out.interface.writeAll("usage: dk3-worker CONFIG.json\nRun as an unprivileged dedicated service user.\n");
        try out.interface.flush();
        return;
    }
    const data = try std.Io.Dir.cwd().readFileAlloc(io, args[1], a, .limited(65536));
    const config = (try std.json.parseFromSlice(Config, a, data, .{})).value;
    if (config.capacity == 0 or config.capacity > 256 or config.token.len < 32) return error.InvalidConfig;
    var http = try Http.init(a, io, config.coordinator, config.token, config.ca_file);
    defer http.deinit();
    try std.Io.Dir.cwd().createDirPath(io, config.state);
    const lock = try std.Io.Dir.cwd().createFile(io, try std.fmt.allocPrint(a, "{s}/worker.lock", .{config.state}), .{ .truncate = false, .lock = .exclusive, .lock_nonblocking = true, .permissions = @enumFromInt(0o600) });
    defer lock.close(io);
    var processes: std.ArrayList(*Process) = .empty;
    var group: std.Io.Group = .init;
    defer {
        for (processes.items) |process| stop(process);
        group.await(io) catch {};
        for (processes.items) |process| {
            process.arena.deinit();
            std.heap.page_allocator.destroy(process);
        }
    }
    var last_error_log: i64 = 0;
    while (true) {
        var cycle = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer cycle.deinit();
        const scratch = cycle.allocator();
        var index: usize = 0;
        while (index < processes.items.len) {
            const process = processes.items[index];
            if (!process.ended.load(.acquire) or !process.reported) {
                index += 1;
                continue;
            }
            _ = processes.swapRemove(index);
            // The room is terminal and acknowledged. Its private state cannot be
            // reused by another generation; bounded service journals retain events.
            retainEvidence(io, scratch, process) catch {};
            std.Io.Dir.cwd().deleteTree(io, process.home) catch {};
            process.arena.deinit();
            std.heap.page_allocator.destroy(process);
        }
        const now: i64 = @intCast(@divTrunc(std.Io.Clock.real.now(io).nanoseconds, std.time.ns_per_s));
        var events: std.ArrayList(api.Event) = .empty;
        var maps: std.ArrayList(permanent.MapStatus) = .empty;
        for (processes.items) |process| {
            if (process.ended.load(.acquire)) {
                if (!process.reported) try events.append(scratch, .{ .room = process.room, .generation = process.generation, .phase = if (process.wanted) .failed else .ended, .humans = 0 });
                continue;
            }
            if (process.permanent_room) {
                const map_path = try std.fmt.allocPrint(scratch, "{s}/dk3/permanent-status.json", .{process.home});
                if (std.Io.Dir.cwd().readFileAlloc(io, map_path, scratch, .limited(4096))) |data_bytes| {
                    if (std.json.parseFromSlice(permanent.Status, scratch, data_bytes, .{})) |state| {
                        try maps.append(scratch, .{ .room = process.room, .generation = process.generation, .map = state.value.map });
                    } else |_| {}
                } else |_| {}
            }
            const status_path = try std.fmt.allocPrint(scratch, "{s}/dk3/online-status.json", .{process.home});
            const status_file = std.Io.Dir.cwd().openFile(io, status_path, .{}) catch {
                if (now - process.started > 90) stop(process);
                continue;
            };
            const stat = status_file.stat(io) catch {
                status_file.close(io);
                continue;
            };
            status_file.close(io);
            if (now - @divTrunc(stat.mtime.nanoseconds, std.time.ns_per_s) > 90) {
                stop(process);
                continue;
            }
            const status_data = std.Io.Dir.cwd().readFileAlloc(io, status_path, scratch, .limited(65536)) catch {
                if (now - process.started > 90) stop(process);
                continue;
            };
            const parsed = std.json.parseFromSlice(Status, scratch, status_data, .{}) catch continue;
            try events.append(scratch, .{ .room = process.room, .generation = process.generation, .phase = parsed.value.phase, .humans = parsed.value.humans, .members = parsed.value.members });
        }
        const assignment = http.call(scratch, Assignment, "/v1/workers/heartbeat", permanent.Heartbeat{ .rooms = events.items, .permanent_rooms = true, .maps = maps.items }) catch |err| {
            if (now - last_error_log >= 30) {
                var buffer: [256]u8 = undefined;
                var log = std.Io.File.stderr().writer(io, &buffer);
                log.interface.print("worker heartbeat failed: {s}\n", .{@errorName(err)}) catch {};
                log.interface.flush() catch {};
                last_error_log = now;
            }
            // Existing matches retain their process and keys during coordinator outages.
            try io.sleep(.fromSeconds(5), .awake);
            continue;
        };
        for (processes.items) |process| {
            process.wanted = false;
            if (process.ended.load(.acquire)) process.reported = true;
        }
        for (assignment.rooms) |room| {
            var found: ?*Process = null;
            for (processes.items) |process| if (std.mem.eql(u8, process.room, room.id) and process.generation == room.generation) {
                found = process;
                break;
            };
            if (found == null) {
                var active: usize = 0;
                for (processes.items) |process| if (!process.ended.load(.acquire)) {
                    active += 1;
                };
                if (room.phase != .allocating) {
                    // The systemd control group kills children on worker restart.
                    // Report an absent prior process; never recreate a playing match.
                    _ = http.call(scratch, Assignment, "/v1/workers/heartbeat", permanent.Heartbeat{ .rooms = &.{.{ .room = room.id, .generation = room.generation, .phase = .failed, .humans = 0 }}, .permanent_rooms = true }) catch {};
                    continue;
                }
                if (active >= config.capacity or assignment.draining) continue;
                var policy: ?permanent.Assignment = null;
                for (assignment.permanent) |candidate| if (std.mem.eql(u8, candidate.room, room.id) and candidate.generation == room.generation) {
                    policy = candidate;
                    break;
                };
                found = try spawn(a, io, config, room, policy);
                try processes.append(a, found.?);
                try group.concurrent(io, wait, .{ found.?, io });
            }
            const process = found.?;
            if (room.phase == .draining) {
                process.wanted = false;
                stop(process);
                continue;
            }
            process.wanted = true;
            if (process.ended.load(.acquire)) continue;
            var controls: std.ArrayList(api.Control) = .empty;
            for (assignment.controls) |control| if (std.mem.eql(u8, control.room, room.id) and control.generation == room.generation) {
                _ = @import("identity.zig").hex(32, control.id) catch continue;
                const receipt = try std.fmt.allocPrint(scratch, "{s}/dk3/control-used/{s}", .{ process.home, control.id });
                if (std.Io.Dir.cwd().readFileAlloc(io, receipt, scratch, .limited(128))) |_| {
                    _ = http.call(scratch, struct { accepted: bool }, "/v1/workers/controlled", .{ .control = control.id }) catch {};
                } else |_| try controls.append(scratch, control);
            };
            // Receipts remain in this allocation's private home until teardown,
            // preventing duplicate application around map changes and ACK loss.
            try atomicJson(io, scratch, try std.fmt.allocPrint(scratch, "{s}/dk3/online-control.json", .{process.home}), controls.items);
            var tickets: std.ArrayList(api.Ticket) = .empty;
            for (assignment.tickets) |ticket| if (std.mem.eql(u8, ticket.room, room.id) and ticket.generation == room.generation) {
                _ = @import("identity.zig").hex(32, ticket.id) catch continue;
                const receipt = try std.fmt.allocPrint(scratch, "{s}/dk3/admission-used/{s}", .{ process.home, ticket.id });
                if (std.Io.Dir.cwd().readFileAlloc(io, receipt, scratch, .limited(128))) |_| {
                    _ = http.call(scratch, struct { accepted: bool }, "/v1/workers/consume", .{ .ticket = ticket.id }) catch continue;
                    try std.Io.Dir.cwd().deleteFile(io, receipt);
                } else |_| try tickets.append(scratch, ticket);
            };
            const file = try std.fmt.allocPrint(scratch, "{s}/dk3/admission.json", .{process.home});
            try atomicJson(io, scratch, file, tickets.items);
            if (tickets.items.len != 0) {
                var ready: std.ArrayList([]const u8) = .empty;
                for (tickets.items) |ticket| try ready.append(scratch, ticket.id);
                _ = http.call(scratch, struct { accepted: bool }, "/v1/workers/ready", .{ .tickets = ready.items }) catch {};
            }
        }
        for (processes.items) |process| if (!process.wanted) stop(process);
        try io.sleep(.fromSeconds(2), .awake);
    }
}
fn spawn(_: std.mem.Allocator, io: std.Io, config: Config, room: api.Room, policy: ?permanent.Assignment) !*Process {
    var lifetime = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer lifetime.deinit();
    const a = lifetime.allocator();
    if (room.id.len != 64) return error.InvalidRoom;
    for (room.id) |ch| if (!std.ascii.isHex(ch)) return error.InvalidRoom;
    for (room.config.map) |ch| if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '-') return error.InvalidMap;
    const home = try std.fmt.allocPrint(a, "{s}/{s}-{d}", .{ config.state, room.id, room.generation });
    try std.Io.Dir.cwd().createDirPath(io, try std.fmt.allocPrint(a, "{s}/dk3", .{home}));
    const colon = std.mem.lastIndexOfScalar(u8, room.endpoint, ':') orelse return error.InvalidEndpoint;
    const port = try std.fmt.parseInt(u16, room.endpoint[colon + 1 ..], 10);
    const mode = switch (room.config.mode) {
        .dm => "0",
        .ctf => "4",
        .deathtag => "8",
    };
    if (std.mem.indexOfAny(u8, room.config.name, "\\\";+\n\r") != null) return error.InvalidRoom;
    if (policy) |settings| if (settings.players != room.config.slots or settings.players < 2 or settings.players > 32 or settings.map_seconds < 60 or settings.map_seconds > 86400) return error.InvalidRoom;
    var rotation: std.ArrayList([]const u8) = .empty;
    try rotation.append(a, room.config.map);
    for (room.config.rotation) |map| {
        if (map.len == 0 or map.len > 64) return error.InvalidMap;
        for (map) |ch| if (!std.ascii.isAlphanumeric(ch) and ch != '_' and ch != '-') return error.InvalidMap;
        if (!std.mem.eql(u8, map, room.config.map)) try rotation.append(a, map);
    }
    var commands = std.Io.Writer.Allocating.init(a);
    try commands.writer.writeAll("set sv_master1 \"\"\nset sv_master2 \"\"\nset sv_master3 \"\"\nset sv_master4 \"\"\nset sv_master5 \"\"\nset sv_voip 0\n");
    for (rotation.items, 0..) |map, index| try commands.writer.print("set dk3_rotate{d} \"map {s}; set nextmap vstr dk3_rotate{d}\"\n", .{ index, map, (index + 1) % rotation.items.len });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}/dk3/managed-rotation.cfg", .{home}), .data = commands.written(), .flags = .{ .permissions = @enumFromInt(0o600) } });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ config.guard, "--mem", config.memory });
    if (policy == null) try argv.appendSlice(a, &.{ "--timeout", "12h" });
    try argv.appendSlice(a, &.{ "--", config.engine, "+set", "dedicated", "2", "+set", "net_port", try std.fmt.allocPrint(a, "{d}", .{port}), "+set", "fs_basepath", config.assets, "+set", "fs_homepath", home, "+set", "fs_homedatapath", home, "+set", "fs_homestatepath", home, "+set", "com_basegame", "dk3", "+set", "vm_game", "0", "+set", "sv_pure", "0", "+set", "dk3_public", "1", "+set", "dk3_room", try a.dupe(u8, room.id), "+set", "dk3_generation", try std.fmt.allocPrint(a, "{d}", .{room.generation}), "+set", "sv_hostname", try a.dupe(u8, room.config.name), "+set", "sv_maxclients", try std.fmt.allocPrint(a, "{d}", .{room.config.slots}), "+set", "g_gametype", mode, "+set", "bot_minplayers", try std.fmt.allocPrint(a, "{d}", .{room.config.bots}), "+set", "g_spSkill", try std.fmt.allocPrint(a, "{d}", .{room.config.skill}), "+set", "dk3_fillSlots", try std.fmt.allocPrint(a, "{d}", .{if (policy) |settings| settings.players else @as(u8, 0)}), "+set", "dk3_rotationSeconds", try std.fmt.allocPrint(a, "{d}", .{if (policy) |settings| settings.map_seconds else @as(u32, 0)}), "+set", "g_doWarmup", if (policy == null) "1" else "0", "+set", "fraglimit", try std.fmt.allocPrint(a, "{d}", .{room.config.fraglimit}), "+set", "timelimit", try std.fmt.allocPrint(a, "{d}", .{if (policy == null) room.config.timelimit else @as(u16, 0)}), "+set", "capturelimit", try std.fmt.allocPrint(a, "{d}", .{room.config.capturelimit}), "+set", "sv_allowDownload", "0", "+set", "sv_cheats", "0", "+exec", "managed-rotation.cfg", "+vstr", "dk3_rotate0" });
    // A permanent match has no lifetime bound. Let systemd's bounded journal own
    // its output instead of growing engine.log up to the service's file limit.
    const log: ?std.Io.File = if (policy == null) try std.Io.Dir.cwd().createFile(io, try std.fmt.allocPrint(a, "{s}/engine.log", .{home}), .{}) else null;
    defer if (log) |file| file.close(io);
    const process = try std.heap.page_allocator.create(Process);
    errdefer std.heap.page_allocator.destroy(process);
    const room_id = try a.dupe(u8, room.id);
    const child = try std.process.spawn(io, .{ .argv = argv.items, .stdin = .ignore, .stdout = if (log) |file| .{ .file = file } else .inherit, .stderr = if (log) |file| .{ .file = file } else .inherit });
    process.* = .{ .arena = lifetime, .started = @intCast(@divTrunc(std.Io.Clock.real.now(io).nanoseconds, std.time.ns_per_s)), .room = room_id, .generation = room.generation, .home = home, .child = child, .pid = child.id.?, .permanent_room = policy != null };
    return process;
}

fn atomicJson(io: std.Io, a: std.mem.Allocator, file: []const u8, value: anytype) !void {
    const temporary = try std.fmt.allocPrint(a, "{s}.tmp", .{file});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = temporary, .data = try std.json.Stringify.valueAlloc(a, value, .{}), .flags = .{ .permissions = @enumFromInt(0o600) } });
    try std.Io.Dir.renameAbsolute(temporary, file, io);
}
