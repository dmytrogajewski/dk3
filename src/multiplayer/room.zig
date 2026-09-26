// SPDX-License-Identifier: GPL-2.0-or-later
//! Native room membership and moderation. Votes bind identities, never reusable slots.
const std = @import("std");
const c = @import("../weapons/abi.zig").c;
const Member = struct {
    identity: [64]u8 = @splat(0),
    joined: i64 = 0,
    left: i64 = 0,
    cooldown: i64 = 0,
    banned_until: i64 = 0,
    slot: i32 = -1,
    ready: bool = false,
};
const Kind = enum { kick, restart, nextmap };
const Ballot = struct { identity: [64]u8, choice: enum { pending, yes, no } = .pending };
const Vote = struct {
    kind: Kind,
    target: [64]u8 = @splat(0),
    deadline: i64,
    electorate: [c.MAX_CLIENTS]Ballot = undefined,
    count: usize = 0,
};
var members: [256]Member = @splat(.{});
var vote: ?Vote = null;
var initialized = false;
var next_status: i64 = 0;
var serial: u64 = 0;
fn timestamp() i64 {
    var calendar: c.qtime_t = undefined;
    return c.trap_RealTime(&calendar);
}
fn managed() bool {
    return c.trap_Cvar_VariableIntegerValue("dk3_public") != 0;
}
fn say(slot: c_int, text: [*:0]const u8) void {
    c.trap_SendServerCommand(slot, c.va("print \"%s\n\"", text));
}
fn same(a: [64]u8, b: [64]u8) bool {
    return std.mem.eql(u8, &a, &b);
}
fn at(slot: c_int) ?*Member {
    for (&members) |*member| if (member.joined != 0 and member.slot == slot) return member;
    return null;
}
fn eligible(member: Member) bool {
    return member.slot >= 0 and c.level.clients[@intCast(member.slot)].pers.connected == c.CON_CONNECTED and c.level.clients[@intCast(member.slot)].sess.sessionTeam != c.TEAM_SPECTATOR;
}
fn persist() void {
    if (!managed()) return;
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const data = std.json.Stringify.valueAlloc(arena.allocator(), members, .{}) catch return;
    if (c.trap_DK3SaveWrite(1, "room-members", data.ptr, @intCast(data.len)) != data.len)
        c.G_Error("dk3: cannot persist room moderation state");
}
fn init() void {
    if (initialized) return;
    initialized = true;
    if (!managed()) return;
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const data = a.alloc(u8, 256 * 1024) catch return;
    const length = c.trap_DK3SaveRead(1, "room-members", data.ptr, @intCast(data.len), c.qfalse);
    if (length <= 0 or length > data.len) return;
    const parsed = std.json.parseFromSlice([256]Member, a, data[0..@intCast(length)], .{}) catch {
        c.G_Error("dk3: corrupt room moderation state");
        return;
    };
    members = parsed.value;
    for (&members) |*member| if (member.slot >= 0) {
        member.slot = -1;
        member.left = timestamp();
        member.ready = false;
    };
}
export fn DK_RoomConnect(slot: c_int, bot: c_int) callconv(.c) ?[*:0]const u8 {
    if (bot != 0 or c.g_gametype.integer == c.GT_SINGLE_PLAYER) return null;
    init();
    var info: [c.MAX_INFO_STRING]u8 = undefined;
    c.trap_GetUserinfo(slot, &info, info.len);
    const supplied = std.mem.span(c.Info_ValueForKey(&info, "dk3_identity"));
    var id: [64]u8 = undefined;
    if (managed()) {
        if (supplied.len != 64) return "Managed rooms require a fresh admission ticket.";
        for (supplied) |ch| if (!std.ascii.isHex(ch)) return "Invalid room identity.";
        @memcpy(&id, supplied);
    } else {
        // LAN identities are connection-local and are never trusted as guest keys.
        serial += 1;
        var bytes: [32]u8 = undefined;
        const seed = .{ timestamp(), c.trap_Milliseconds(), slot, serial };
        std.crypto.hash.sha2.Sha256.hash(std.mem.asBytes(&seed), &bytes, .{});
        id = std.fmt.bytesToHex(bytes, .lower);
    }
    const now = timestamp();
    var free: ?*Member = null;
    for (&members) |*member| {
        if (member.joined == 0 or (member.slot < 0 and member.left + 60 < now and member.cooldown <= now and member.banned_until <= now)) free = member;
        if (member.joined == 0 or !same(member.identity, id)) continue;
        if (member.banned_until > now) return "This identity is temporarily banned from this room.";
        if (member.slot >= 0 and member.slot != slot) return "This identity is already connected.";
        member.slot = slot;
        member.left = 0;
        member.ready = false;
        persist();
        return null;
    }
    const member = free orelse return "Room membership capacity reached; retry later.";
    member.* = .{ .identity = id, .joined = now, .slot = slot };
    persist();
    return null;
}
export fn DK_RoomDisconnect(slot: c_int) callconv(.c) void {
    if (at(slot)) |member| {
        member.slot = -1;
        member.left = timestamp();
        member.ready = false;
        persist();
    }
}
fn publishVote() void {
    const ballot = vote orelse {
        c.trap_SetConfigstring(c.CS_VOTE_TIME, "");
        return;
    };
    var yes: c_int = 0;
    var no: c_int = 0;
    for (ballot.electorate[0..ballot.count]) |voter| switch (voter.choice) {
        .yes => yes += 1,
        .no => no += 1,
        .pending => {},
    };
    c.trap_SetConfigstring(c.CS_VOTE_YES, c.va("%d", yes));
    c.trap_SetConfigstring(c.CS_VOTE_NO, c.va("%d", no));
}
fn finish(passed: bool) void {
    const ballot = vote orelse return;
    vote = null;
    publishVote();
    say(-1, if (passed) "Vote passed." else "Vote failed.");
    if (!passed) return;
    switch (ballot.kind) {
        .kick => {
            for (&members) |*member| if (member.joined != 0 and same(member.identity, ballot.target)) {
                member.banned_until = timestamp() + 900;
                persist();
                if (member.slot >= 0) c.trap_DropClient(member.slot, "Removed by room vote (15-minute room ban)");
                break;
            };
        },
        .restart => c.trap_SendConsoleCommand(c.EXEC_APPEND, "map_restart 0\n"),
        .nextmap => c.trap_SendConsoleCommand(c.EXEC_APPEND, "vstr nextmap\n"),
    }
}
export fn DK_RoomCommand(slot: c_int, name: [*:0]const u8) callconv(.c) c_int {
    const command = std.mem.span(name);
    const is_call = std.ascii.eqlIgnoreCase(command, "callvote");
    const is_vote = std.ascii.eqlIgnoreCase(command, "vote");
    const is_ready = std.ascii.eqlIgnoreCase(command, "ready");
    if (std.ascii.eqlIgnoreCase(command, "callteamvote") or std.ascii.eqlIgnoreCase(command, "teamvote")) {
        say(slot, "Use room votes for moderation.");
        return 1;
    }
    if (!is_call and !is_vote and !is_ready) return 0;
    const member = at(slot) orelse return 1;
    if (!eligible(member.*)) {
        say(slot, "Spectators cannot vote or ready for play.");
        return 1;
    }
    if (is_ready) {
        member.ready = !member.ready;
        say(slot, if (member.ready) "Ready." else "Not ready.");
        return 1;
    }
    var argument: [128]u8 = undefined;
    c.trap_Argv(1, &argument, argument.len);
    const arg = std.mem.sliceTo(&argument, 0);
    if (is_vote) {
        if (vote) |*ballot| {
            for (ballot.electorate[0..ballot.count]) |*voter| if (same(voter.identity, member.identity)) {
                if (voter.choice != .pending) {
                    say(slot, "You already voted.");
                    return 1;
                }
                if (std.ascii.eqlIgnoreCase(arg, "yes") or std.mem.eql(u8, arg, "1")) voter.choice = .yes else if (std.ascii.eqlIgnoreCase(arg, "no") or std.mem.eql(u8, arg, "0")) voter.choice = .no else {
                    say(slot, "Use vote yes or vote no.");
                    return 1;
                }
                publishVote();
                return 1;
            };
        }
        say(slot, "You are not in an active vote electorate.");
        return 1;
    }
    if (c.trap_Cvar_VariableIntegerValue("g_allowVote") == 0) {
        say(slot, "Voting is disabled.");
        return 1;
    }
    if (vote != null) {
        say(slot, "A vote is already active.");
        return 1;
    }
    const now = timestamp();
    if (member.cooldown > now) {
        say(slot, "Wait before calling another vote.");
        return 1;
    }
    var ballot: Vote = .{ .kind = .kick, .deadline = now + 30 };
    if (std.ascii.eqlIgnoreCase(arg, "kick") or std.ascii.eqlIgnoreCase(arg, "clientkick")) {
        c.trap_Argv(2, &argument, argument.len);
        const target_slot = std.fmt.parseInt(c_int, std.mem.sliceTo(&argument, 0), 10) catch {
            say(slot, "Use callvote kick followed by a player slot number.");
            return 1;
        };
        const target = at(target_slot) orelse {
            say(slot, "That human player is not connected.");
            return 1;
        };
        if (same(target.identity, member.identity)) {
            say(slot, "You cannot call a vote to kick yourself.");
            return 1;
        }
        ballot.target = target.identity;
    } else if (std.ascii.eqlIgnoreCase(arg, "map_restart")) ballot.kind = .restart else if (std.ascii.eqlIgnoreCase(arg, "nextmap")) ballot.kind = .nextmap else {
        say(slot, "Votes: kick <slot>, map_restart, nextmap.");
        return 1;
    }
    for (members) |candidate| if (candidate.joined != 0 and eligible(candidate) and !(ballot.kind == .kick and same(candidate.identity, ballot.target))) {
        ballot.electorate[ballot.count] = .{ .identity = candidate.identity, .choice = if (same(candidate.identity, member.identity)) .yes else .pending };
        ballot.count += 1;
    };
    if (ballot.count < 2) {
        say(slot, "A vote requires at least two eligible humans besides the kick target.");
        return 1;
    }
    member.cooldown = now + 120;
    vote = ballot;
    persist();
    c.trap_SetConfigstring(c.CS_VOTE_TIME, c.va("%d", @as(c_int, @max(1, c.level.time))));
    c.trap_SetConfigstring(c.CS_VOTE_STRING, switch (ballot.kind) {
        .kick => "Remove selected player for 15 minutes",
        .restart => "Restart map",
        .nextmap => "Next map in rotation",
    });
    say(-1, "Room vote started. Use vote yes or vote no.");
    publishVote();
    return 1;
}
export fn DK_RoomTick() callconv(.c) void {
    init();
    const now = timestamp();
    if (vote) |ballot| {
        var yes: usize = 0;
        var pending: usize = 0;
        for (ballot.electorate[0..ballot.count]) |voter| switch (voter.choice) {
            .yes => yes += 1,
            .pending => pending += 1,
            .no => {},
        };
        const required = @max(2, ballot.count / 2 + 1);
        if (yes >= required) finish(true) else if (now >= ballot.deadline or yes + pending < required) finish(false);
    }
    if (!managed() or now < next_status) return;
    next_status = now + 1;
    operatorControls(now);
    const Presence = struct { identity: []const u8, joined: i64, left: i64, connected: bool, ready: bool, slot: i32 };
    var list: [256]Presence = undefined;
    var count: usize = 0;
    var humans: u8 = 0;
    for (&members) |*member| if (member.joined != 0 and member.banned_until <= now and (member.slot >= 0 or now < member.left + 60)) {
        list[count] = .{ .identity = &member.identity, .joined = member.joined, .left = member.left, .connected = member.slot >= 0, .ready = member.ready, .slot = member.slot };
        count += 1;
        if (member.slot >= 0) humans += 1;
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const phase: []const u8 = if (c.level.warmupTime != 0) "lobby" else "playing";
    const data = std.json.Stringify.valueAlloc(arena.allocator(), .{ .humans = humans, .phase = phase, .members = list[0..count] }, .{}) catch return;
    var file: c.fileHandle_t = 0;
    _ = c.trap_FS_FOpenFile("online-status.json", &file, c.FS_WRITE);
    if (file == 0) return;
    c.trap_FS_Write(data.ptr, @intCast(data.len), file);
    c.trap_FS_FCloseFile(file);
}
export fn DK_RoomWarmup() callconv(.c) c_int {
    if (!managed()) return 0;
    if (c.level.warmupTime == 0) return 1;
    var players: usize = 0;
    var ready = true;
    for (members) |member| if (member.joined != 0 and eligible(member)) {
        players += 1;
        ready = ready and member.ready;
    };
    if (players == 0 or !ready) {
        c.level.warmupTime = -1;
        c.trap_SetConfigstring(c.CS_WARMUP, "-1");
    } else if (c.level.warmupTime < 0) {
        c.level.warmupTime = c.level.time + 5000;
        c.trap_SetConfigstring(c.CS_WARMUP, c.va("%d", c.level.warmupTime));
    } else if (c.level.time >= c.level.warmupTime) {
        // Reuse the engine's acknowledged match restart: reset pickups, health,
        // scores and spawns while g_restarted skips a second readiness countdown.
        c.level.warmupTime += 10000;
        c.trap_Cvar_Set("g_restarted", "1");
        c.trap_SendConsoleCommand(c.EXEC_APPEND, "map_restart 0\n");
        c.level.restarted = c.qtrue;
    }
    return 1;
}

fn operatorControls(now: i64) void {
    var file: c.fileHandle_t = 0;
    const length = c.trap_FS_FOpenFile("online-control.json", &file, c.FS_READ);
    if (file == 0) return;
    defer c.trap_FS_FCloseFile(file);
    if (length <= 0 or length > 65536) return;
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = a.alloc(u8, @intCast(length)) catch return;
    c.trap_FS_Read(bytes.ptr, length, file);
    const commands = std.json.parseFromSlice([]const @import("../online/api.zig").Control, a, bytes, .{}) catch return;
    if (commands.value.len > 64) return;
    var room: [65]u8 = undefined;
    c.trap_Cvar_VariableStringBuffer("dk3_room", &room, room.len);
    const generation = c.trap_Cvar_VariableIntegerValue("dk3_generation");
    for (commands.value) |command| {
        if (command.expires <= now or command.generation != generation or !std.mem.eql(u8, command.room, std.mem.sliceTo(&room, 0))) continue;
        if (command.id.len != 64 or command.identity.len != 64) continue;
        var valid = true;
        for (command.id) |ch| if (!std.ascii.isHex(ch)) {
            valid = false;
            break;
        };
        for (command.identity) |ch| if (!std.ascii.isHex(ch)) {
            valid = false;
            break;
        };
        if (!valid) continue;
        const receipt = std.fmt.allocPrintSentinel(a, "control-used/{s}", .{command.id}, 0) catch return;
        var used: c.fileHandle_t = 0;
        _ = c.trap_FS_FOpenFile(receipt.ptr, &used, c.FS_READ);
        if (used != 0) {
            c.trap_FS_FCloseFile(used);
            continue;
        }
        var target: ?*Member = null;
        for (&members) |*member| if (member.joined != 0 and std.mem.eql(u8, &member.identity, command.identity)) {
            target = member;
            break;
        };
        if (target == null and command.banned_until > now) {
            for (&members) |*member| if (member.joined == 0 or (member.slot < 0 and member.left + 60 < now and member.cooldown <= now and member.banned_until <= now)) {
                member.* = .{ .joined = now, .left = now };
                @memcpy(&member.identity, command.identity);
                target = member;
                break;
            };
            if (target == null) {
                c.G_Error("dk3: room moderation capacity exhausted");
                return;
            }
        }
        if (target) |member| {
            member.banned_until = @max(member.banned_until, command.banned_until);
            persist();
            if (member.slot >= 0) c.trap_DropClient(member.slot, "Removed by server operator");
        }
        // Acknowledge only after durable room state and disconnection. Never
        // interpolate the operator reason into a console or client command.
        var ack: c.fileHandle_t = 0;
        _ = c.trap_FS_FOpenFile(receipt.ptr, &ack, c.FS_WRITE);
        if (ack != 0) {
            c.trap_FS_Write("applied", 7, ack);
            c.trap_FS_FCloseFile(ack);
        }
        c.G_Printf("dk3: operator control %s applied\n", (a.dupeZ(u8, command.id) catch return).ptr);
    }
}
