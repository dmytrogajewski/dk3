// SPDX-License-Identifier: GPL-2.0-or-later
//! Native membership, readiness and identity-bound moderation. Hosting owns room allocation.
const std = @import("std");
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const Clients = @import("clients.zig").Clients;
const api = @import("online_api");
const allocator = std.heap.c_allocator;
const Member = struct {
    identity: [64]u8 = @splat(0),
    joined: i64 = 0,
    left: i64 = 0,
    cooldown: i64 = 0,
    banned_until: i64 = 0,
    slot: i32 = -1,
    session: ?data.Session = null,
    ready: bool = false,
};
const Kind = enum { kick, restart, nextmap };
const Ballot = struct { identity: [64]u8, choice: enum { pending, yes, no } = .pending };
const Vote = struct { kind: Kind, target: [64]u8 = @splat(0), deadline: i64, electorate: [c.MAX_CLIENTS]Ballot = undefined, count: usize = 0 };
fn timestamp() i64 {
    var calendar: c.qtime_t = undefined;
    return engine.gateway.call(c.G_REAL_TIME, .{&calendar});
}
fn managed() bool {
    return engine.integer("dk3_public") != 0;
}
fn same(a: [64]u8, b: [64]u8) bool {
    return std.mem.eql(u8, &a, &b);
}
fn eligible(world: *data.World, clients: *Clients, member: Member) bool {
    if (member.slot < 0 or member.slot >= clients.entities.len) return false;
    const entity = clients.entities[@intCast(member.slot)] orelse return false;
    const session = world.get(entity, data.Session) catch return false;
    return !session.bot and session.team != .spectator;
}
fn say(slot: i32, message: []const u8) void {
    var buffer: [512]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "print \"{s}\n\"", .{message}) catch return;
    _ = engine.gateway.call(c.G_SEND_SERVER_COMMAND, .{ @as(isize, slot), text.ptr });
}
fn set(name: [:0]const u8, value: [:0]const u8) void {
    _ = engine.gateway.call(c.G_CVAR_SET, .{ name.ptr, value.ptr });
}
fn console(command: [:0]const u8) void {
    _ = engine.gateway.call(c.G_SEND_CONSOLE_COMMAND, .{ @as(isize, c.EXEC_APPEND), command.ptr });
}
fn drop(slot: i32, reason: [:0]const u8) void {
    _ = engine.gateway.call(c.G_DROP_CLIENT, .{ @as(isize, slot), reason.ptr });
}
fn available(member: Member, now: i64) bool {
    return member.joined == 0 or (member.slot < 0 and member.left + 60 < now and member.cooldown <= now and member.banned_until <= now);
}
fn write(path: [:0]const u8, bytes: []const u8) !void {
    var file: c.fileHandle_t = 0;
    _ = engine.gateway.call(c.G_FS_FOPEN_FILE, .{ path.ptr, &file, @as(isize, c.FS_WRITE) });
    if (file == 0) return error.RoomStatusWriteFailed;
    defer _ = engine.gateway.call(c.G_FS_FCLOSE_FILE, .{@as(isize, file)});
    _ = engine.gateway.call(c.G_FS_WRITE, .{ bytes.ptr, @as(isize, @intCast(bytes.len)), @as(isize, file) });
}
fn validIdentity(text: []const u8) bool {
    if (text.len != 64) return false;
    for (text) |byte| if (!std.ascii.isHex(byte)) return false;
    return true;
}
pub const State = struct {
    initialized: bool = false,
    members: [256]Member = @splat(.{}),
    vote: ?Vote = null,
    next_status: i64 = 0,
    serial: u64 = 0,
    warmup_ms: i64 = 0,
    restart_pending: bool = false,
    pub fn init(self: *State) !void {
        self.* = .{};
        if (!@import("multiplayer.zig").enabled()) return;
        self.initialized = true;
        engine.register("g_allowVote", "1", c.CVAR_SERVERINFO);
        engine.register("g_doWarmup", "0", 0);
        engine.register("g_restarted", "0", 0);
        self.warmup_ms = if (engine.integer("g_doWarmup") != 0 and engine.integer("g_restarted") == 0) -1 else 0;
        set("g_restarted", "0");
        engine.config(c.CS_WARMUP, if (self.warmup_ms != 0) "-1" else "0");
        engine.config(c.CS_VOTE_TIME, "");
        if (!managed()) return;
        const bytes = @import("../engine/save_storage.zig").read(allocator, "native-room-members", false) catch |err| switch (err) {
            error.SaveMissingOrUnreadable => return,
            else => return err,
        };
        defer allocator.free(bytes);
        const parsed = try std.json.parseFromSlice([256]Member, allocator, bytes, .{});
        defer parsed.deinit();
        self.members = parsed.value;
        for (&self.members) |*member| {
            if (member.joined != 0 and !validIdentity(&member.identity)) return error.InvalidRoomMembership;
            if (member.slot >= c.MAX_CLIENTS or member.slot < -1) return error.InvalidRoomMembership;
            if (member.session) |*session| {
                if (session.bot or session.appearance >= @import("appearance_catalog").entries.len) return error.InvalidRoomMembership;
                // Admission preserves identity/team through rotation, but a new match
                // owns new scores and deadlines. Same-map reconnects use live members.
                session.score = 0;
                session.deaths = 0;
                session.captures = 0;
                session.respawn_ms = 0;
                session.joined_ms = 0;
                session.ready = false;
                session.advancement = null;
                if (!@import("multiplayer.zig").teams() and session.team != .spectator) session.team = .free;
                if (@import("multiplayer.zig").teams() and session.team == .free) member.session = null;
            }
            if (member.slot >= 0) {
                member.slot = -1;
                member.left = timestamp();
                member.ready = false;
            }
        }
    }
    fn persist(self: *State) !void {
        if (!managed()) return;
        const bytes = try std.json.Stringify.valueAlloc(allocator, self.members, .{});
        defer allocator.free(bytes);
        try @import("../engine/save_storage.zig").write("native-room-members", bytes, false);
    }
    pub fn checkpoint(self: *State, world: *data.World, clients: *Clients) !void {
        if (!self.initialized) return;
        for (&self.members) |*member| if (member.slot >= 0) {
            if (clients.entities[@intCast(member.slot)]) |entity| {
                if (world.get(entity, data.Session) catch null) |session| member.session = session.*;
            }
        };
        try self.persist();
    }
    pub fn unready(self: *State, world: *data.World, clients: *Clients, slot: u16) void {
        if (self.at(slot)) |member| member.ready = false;
        if (clients.entities[slot]) |entity| {
            if (world.get(entity, data.Session) catch null) |session| session.ready = false;
        }
    }
    fn at(self: *State, slot: i32) ?*Member {
        for (&self.members) |*member| if (member.joined != 0 and member.slot == slot) return member;
        return null;
    }
    pub fn connect(self: *State, clients: *Clients, slot: u16, bot: bool) !?[:0]const u8 {
        if (bot or !@import("multiplayer.zig").enabled()) return null;
        var userinfo: [c.MAX_INFO_STRING]u8 = @splat(0);
        _ = engine.gateway.call(c.G_GET_USERINFO, .{ @as(isize, slot), &userinfo, @as(isize, userinfo.len) });
        const supplied = @import("../engine/info.zig").get(std.mem.sliceTo(&userinfo, 0), "dk3_identity") orelse "";
        var id: [64]u8 = undefined;
        if (managed()) {
            if (!validIdentity(supplied)) return "A fresh authenticated room admission is required.";
            @memcpy(&id, supplied);
        } else {
            self.serial += 1;
            var digest: [32]u8 = undefined;
            const seed = [_]u64{ @intCast(timestamp()), @intCast(engine.gateway.call(c.G_MILLISECONDS, .{})), slot, self.serial };
            std.crypto.hash.sha2.Sha256.hash(std.mem.asBytes(&seed), &digest, .{});
            id = std.fmt.bytesToHex(digest, .lower);
        }
        const now = timestamp();
        var free: ?*Member = null;
        for (&self.members) |*member| {
            if (available(member.*, now)) free = member;
            if (member.joined == 0 or !same(member.identity, id)) continue;
            if (member.banned_until > now) return "This identity is temporarily banned from this room.";
            if (member.slot >= 0 and member.slot != slot) return "This identity is already connected.";
            if (member.left + 60 >= now) {
                clients.returning[slot] = member.session;
                if (clients.returning[slot]) |*session| session.ready = false;
            } else {
                member.joined = now;
                member.session = null;
            }
            member.slot = slot;
            member.left = 0;
            member.ready = false;
            try self.persist();
            return null;
        }
        const member = free orelse return "Room membership is full. Retry later.";
        member.* = .{ .identity = id, .joined = now, .slot = slot };
        try self.persist();
        return null;
    }
    pub fn disconnect(self: *State, world: *data.World, clients: *Clients, slot: u16) !void {
        if (self.at(slot)) |member| {
            if (clients.entities[slot]) |entity| {
                if (world.get(entity, data.Session) catch null) |session| member.session = session.*;
            }
            member.slot = -1;
            member.left = timestamp();
            member.ready = false;
            try self.persist();
        }
    }
    fn publishVote(self: *State) !void {
        const vote = self.vote orelse {
            engine.config(c.CS_VOTE_TIME, "");
            return;
        };
        var yes: usize = 0;
        var no: usize = 0;
        for (vote.electorate[0..vote.count]) |ballot| switch (ballot.choice) {
            .yes => yes += 1,
            .no => no += 1,
            .pending => {},
        };
        var buffer: [32]u8 = undefined;
        engine.config(c.CS_VOTE_YES, try std.fmt.bufPrintZ(&buffer, "{d}", .{yes}));
        engine.config(c.CS_VOTE_NO, try std.fmt.bufPrintZ(&buffer, "{d}", .{no}));
    }
    fn finish(self: *State, passed: bool) !void {
        const vote = self.vote orelse return;
        self.vote = null;
        try self.publishVote();
        say(-1, if (passed) "Vote passed." else "Vote failed.");
        if (!passed) return;
        switch (vote.kind) {
            .kick => for (&self.members) |*member| {
                if (member.joined == 0 or !same(member.identity, vote.target)) continue;
                member.banned_until = timestamp() + 900;
                try self.persist();
                if (member.slot >= 0) drop(member.slot, "Removed by vote (15-minute room ban)");
                break;
            },
            .restart => console("map_restart 0\n"),
            .nextmap => console("vstr nextmap\n"),
        }
    }
    pub fn command(self: *State, world: *data.World, clients: *Clients, slot: u16, name: []const u8, level_ms: i64) !bool {
        if (!std.mem.eql(u8, name, "callvote") and !std.mem.eql(u8, name, "vote") and !std.mem.eql(u8, name, "ready")) return false;
        const member = self.at(slot) orelse return true;
        if (!eligible(world, clients, member.*)) {
            say(slot, "Spectators cannot vote or ready for play.");
            return true;
        }
        if (std.mem.eql(u8, name, "ready")) {
            member.ready = !member.ready;
            (try world.get(clients.entities[slot].?, data.Session)).ready = member.ready;
            say(slot, if (member.ready) "Ready." else "Not ready.");
            return true;
        }
        var buffer: [128]u8 = undefined;
        const argument = engine.argv(1, &buffer);
        if (std.mem.eql(u8, name, "vote")) {
            if (self.vote) |*vote| for (vote.electorate[0..vote.count]) |*ballot| if (same(ballot.identity, member.identity)) {
                if (ballot.choice != .pending) {
                    say(slot, "You already voted.");
                    return true;
                }
                if (std.ascii.eqlIgnoreCase(argument, "yes") or std.mem.eql(u8, argument, "1")) ballot.choice = .yes else if (std.ascii.eqlIgnoreCase(argument, "no") or std.mem.eql(u8, argument, "0")) ballot.choice = .no else {
                    say(slot, "Use vote yes or vote no.");
                    return true;
                }
                try self.publishVote();
                return true;
            };
            say(slot, "You are not in an active vote electorate.");
            return true;
        }
        const now = timestamp();
        if (engine.integer("g_allowVote") == 0) {
            say(slot, "Voting is disabled.");
            return true;
        }
        if (self.vote != null) {
            say(slot, "A vote is already active.");
            return true;
        }
        if (now < member.cooldown) {
            say(slot, "Wait before calling another vote.");
            return true;
        }
        var vote: Vote = .{ .kind = .kick, .deadline = now + 30 };
        if (std.ascii.eqlIgnoreCase(argument, "kick") or std.ascii.eqlIgnoreCase(argument, "clientkick")) {
            const target_slot = std.fmt.parseInt(i32, engine.argv(2, &buffer), 10) catch {
                say(slot, "Use callvote kick <player slot>.");
                return true;
            };
            const target = self.at(target_slot) orelse {
                say(slot, "That human player is not connected.");
                return true;
            };
            if (same(member.identity, target.identity)) {
                say(slot, "You cannot kick yourself.");
                return true;
            }
            vote.target = target.identity;
        } else if (std.mem.eql(u8, argument, "map_restart")) vote.kind = .restart else if (std.mem.eql(u8, argument, "nextmap")) vote.kind = .nextmap else {
            say(slot, "Votes: kick <slot>, map_restart, nextmap.");
            return true;
        }
        for (self.members) |candidate| if (candidate.joined != 0 and eligible(world, clients, candidate) and !(vote.kind == .kick and same(candidate.identity, vote.target))) {
            vote.electorate[vote.count] = .{ .identity = candidate.identity, .choice = if (same(candidate.identity, member.identity)) .yes else .pending };
            vote.count += 1;
        };
        if (vote.count < 2) {
            say(slot, "At least two eligible humans besides a kick target must vote.");
            return true;
        }
        member.cooldown = now + 120;
        self.vote = vote;
        try self.persist();
        engine.config(c.CS_VOTE_TIME, try std.fmt.bufPrintZ(&buffer, "{d}", .{@max(1, level_ms)}));
        engine.config(c.CS_VOTE_STRING, switch (vote.kind) {
            .kick => "Remove selected player for 15 minutes",
            .restart => "Restart map",
            .nextmap => "Next map",
        });
        say(-1, "Room vote started. Use vote yes or vote no.");
        try self.publishVote();
        return true;
    }
    pub fn tick(self: *State, world: *data.World, clients: *Clients, level_ms: i64) !void {
        if (!@import("multiplayer.zig").enabled()) return;
        const now = timestamp();
        if (self.vote) |vote| {
            var yes: usize = 0;
            var pending: usize = 0;
            for (vote.electorate[0..vote.count]) |ballot| switch (ballot.choice) {
                .yes => yes += 1,
                .pending => pending += 1,
                .no => {},
            };
            const required = @max(2, vote.count / 2 + 1);
            if (yes >= required) try self.finish(true) else if (now >= vote.deadline or yes + pending < required) try self.finish(false);
        }
        if (self.warmup_ms != 0 and !self.restart_pending) {
            var humans: usize = 0;
            var ready = true;
            for (self.members) |member| if (eligible(world, clients, member)) {
                humans += 1;
                ready = ready and member.ready;
            };
            if (humans == 0 or !ready) {
                self.warmup_ms = -1;
                engine.config(c.CS_WARMUP, "-1");
            } else if (self.warmup_ms < 0) {
                self.warmup_ms = level_ms + 5000;
                var text: [32]u8 = undefined;
                engine.config(c.CS_WARMUP, try std.fmt.bufPrintZ(&text, "{d}", .{self.warmup_ms}));
            } else if (level_ms >= self.warmup_ms) {
                self.restart_pending = true;
                set("g_restarted", "1");
                console("map_restart 0\n");
            }
        }
        if (!managed() or now < self.next_status) return;
        self.next_status = now + 1;
        try self.operatorControls(now);
        var list: [256]api.Presence = undefined;
        var count: usize = 0;
        var humans: u8 = 0;
        for (&self.members) |*member| if (member.joined != 0 and member.banned_until <= now and (member.slot >= 0 or now < member.left + 60)) {
            list[count] = .{ .identity = &member.identity, .joined = member.joined, .left = member.left, .connected = member.slot >= 0, .ready = member.ready, .slot = member.slot };
            count += 1;
            if (member.slot >= 0) {
                humans += 1;
                if (clients.entities[@intCast(member.slot)]) |entity| member.session = (try world.get(entity, data.Session)).*;
            }
        };
        const bytes = try std.json.Stringify.valueAlloc(allocator, .{ .humans = humans, .phase = if (self.warmup_ms != 0) api.Phase.lobby else api.Phase.playing, .members = list[0..count] }, .{});
        defer allocator.free(bytes);
        try write("online-status.json", bytes);
        try self.persist();
    }
    fn operatorControls(self: *State, now: i64) !void {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const bytes = @import("../engine/files.zig").read(.server, &engine.gateway, a, "online-control.json", 65536) catch return;
        const commands = try std.json.parseFromSlice([]const api.Control, a, bytes, .{});
        if (commands.value.len > 64) return error.RoomControlCapacity;
        var room: [65]u8 = @splat(0);
        _ = engine.gateway.call(c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "dk3_room"), &room, @as(isize, room.len) });
        const generation = engine.integer("dk3_generation");
        for (commands.value) |control| {
            if (control.expires <= now or control.generation != generation or !std.mem.eql(u8, control.room, std.mem.sliceTo(&room, 0)) or !validIdentity(control.id) or !validIdentity(control.identity)) continue;
            const receipt = try std.fmt.allocPrintSentinel(a, "control-used/{s}", .{control.id}, 0);
            var used: c.fileHandle_t = 0;
            _ = engine.gateway.call(c.G_FS_FOPEN_FILE, .{ receipt.ptr, &used, @as(isize, c.FS_READ) });
            if (used != 0) {
                _ = engine.gateway.call(c.G_FS_FCLOSE_FILE, .{@as(isize, used)});
                continue;
            }
            var target: ?*Member = null;
            for (&self.members) |*member| if (member.joined != 0 and std.mem.eql(u8, &member.identity, control.identity)) {
                target = member;
                break;
            };
            if (target == null and control.banned_until > now) {
                for (&self.members) |*member| if (available(member.*, now)) {
                    member.* = .{ .joined = now, .left = now };
                    @memcpy(&member.identity, control.identity);
                    target = member;
                    break;
                };
                if (target == null) return error.RoomModerationCapacity;
            }
            if (target) |member| {
                member.banned_until = @max(member.banned_until, control.banned_until);
                try self.persist();
                if (member.slot >= 0) drop(member.slot, "Removed by server operator");
            }
            try write(receipt, "applied");
            var text: [128]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&text, "dk3: operator control {s} applied\n", .{control.id}));
        }
    }
};
