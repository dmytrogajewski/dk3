// SPDX-License-Identifier: GPL-2.0-or-later
//! Serialized transactional room authority; no game simulation or executable commands.
const std = @import("std");
const api = @import("api.zig");
const identity = @import("identity.zig");
const Store = @import("store.zig").Store;
const permanent = @import("permanent.zig");
pub const Config = struct {
    bind: []const u8 = "127.0.0.1:8090",
    database: []const u8,
    admin_token: []const u8,
    public_url: []const u8,
    rooms_per_address: u16 = 4,
    max_rooms: u16 = 128,
    permanent_rooms: []const permanent.Config = &.{},
};
pub const Result = struct { status: std.http.Status = .ok, body: []const u8 };
const Session = struct { identity: []const u8, expires: i64 };
const Enrollment = struct { token_hash: []const u8, worker: api.Worker, permanent_rooms: bool = false };
const RequestRecord = struct { room: []const u8, payload_hash: []const u8 };
const RoomSecret = struct { access_code: []const u8, address: []const u8 };
const Bucket = struct { start: i64, count: u32 };
const Ban = struct { identity: []const u8, expires: i64, reason: []const u8 };
pub const Coordinator = struct {
    store: Store,
    config: Config,
    mutex: std.Io.Mutex = .init,
    last_sweep: i64 = 0,
    pub fn init(config: Config, allocator: std.mem.Allocator) !Coordinator {
        if (config.admin_token.len < 32 or config.max_rooms == 0 or config.rooms_per_address == 0) return error.InvalidConfig;
        if (config.permanent_rooms.len > config.max_rooms) return error.InvalidConfig;
        for (config.permanent_rooms, 0..) |room, index| {
            if (!validId(room.id) or !validText(room.name, 64) or std.mem.indexOfAny(u8, room.name, "\\\";+") != null or !validId(room.region) or room.players < 2 or room.players > 32 or room.skill < 1 or room.skill > 5 or room.map_minutes == 0 or room.map_minutes > 1440 or room.maps.len == 0 or room.maps.len > 64) return error.InvalidConfig;
            for (room.maps) |map| if (!validId(map)) return error.InvalidConfig;
            for (config.permanent_rooms[0..index]) |prior| if (equal(prior.id, room.id)) return error.InvalidConfig;
        }
        return .{ .store = try Store.open(try allocator.dupeZ(u8, config.database)), .config = config };
    }
    pub fn deinit(self: *Coordinator) void {
        self.store.close();
    }
    pub fn handle(self: *Coordinator, io: std.Io, a: std.mem.Allocator, method: std.http.Method, path: []const u8, bearer: []const u8, address: []const u8, body: []const u8) Result {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.dispatch(io, a, method, path, bearer, address, body) catch |err| .{
            .status = switch (@as(anyerror, err)) {
                error.Unauthorized, error.Expired => .unauthorized,
                error.Forbidden, error.Banned => .forbidden,
                error.NotFound => .not_found,
                error.Capacity, error.RateLimited => .too_many_requests,
                error.Conflict, error.Incompatible, error.NoWorker => .conflict,
                error.Database, error.DatabaseOpen, error.OutOfMemory => .internal_server_error,
                else => .bad_request,
            },
            .body = std.json.Stringify.valueAlloc(a, api.Failure{ .code = @errorName(err), .message = message(err) }, .{}) catch "{\"code\":\"Unavailable\"}",
        };
    }
    fn message(err: anyerror) []const u8 {
        return switch (err) {
            error.NoWorker => "No healthy compatible worker has capacity in the requested region.",
            error.Incompatible => "Protocol, rules, gameplay data, or cosmetic profile is incompatible.",
            error.Capacity => "Room or host capacity is exhausted.",
            error.RateLimited => "Request limit reached; retry later.",
            error.Expired => "Authentication or room admission expired; reconnect.",
            error.Database, error.DatabaseOpen, error.OutOfMemory => "The room service is temporarily unavailable.",
            else => "The request could not be accepted.",
        };
    }
    fn parse(comptime T: type, a: std.mem.Allocator, body: []const u8) !T {
        if (body.len > 65536) return error.InvalidLength;
        return (try std.json.parseFromSlice(T, a, body, .{ .allocate = .alloc_always })).value;
    }
    fn load(self: *Coordinator, comptime T: type, a: std.mem.Allocator, kind: []const u8, id: []const u8) !?T {
        const data = try self.store.get(a, kind, id) orelse return null;
        return try parse(T, a, data);
    }
    fn save(self: *Coordinator, a: std.mem.Allocator, kind: []const u8, id: []const u8, value: anytype) !void {
        try self.store.put(kind, id, try std.json.Stringify.valueAlloc(a, value, .{}));
    }
    fn reply(a: std.mem.Allocator, value: anytype) !Result {
        return .{ .body = try std.json.Stringify.valueAlloc(a, value, .{}) };
    }
    fn hash(value: []const u8) [64]u8 {
        var result: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(value, &result, .{});
        return std.fmt.bytesToHex(result, .lower);
    }
    fn equal(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
    fn tokenEqual(a: []const u8, b: []const u8) bool {
        const ah = hash(a);
        const bh = hash(b);
        return std.crypto.timing_safe.eql([64]u8, ah, bh);
    }
    fn validText(text: []const u8, max: usize) bool {
        if (text.len == 0 or text.len > max or !std.unicode.utf8ValidateSlice(text)) return false;
        for (text) |ch| if (ch < 32 or ch == 127) return false;
        return true;
    }
    fn validId(text: []const u8) bool {
        if (text.len == 0 or text.len > 64) return false;
        for (text) |ch| if (!std.ascii.isAlphanumeric(ch) and ch != '-' and ch != '_') return false;
        return true;
    }
    fn rate(self: *Coordinator, a: std.mem.Allocator, address: []const u8, now: i64, limit: u32) !void {
        const key = hash(address);
        var bucket = try self.load(Bucket, a, "rate", &key) orelse Bucket{ .start = now, .count = 0 };
        if (now < bucket.start or now - bucket.start >= 60) bucket = .{ .start = now, .count = 0 };
        if (bucket.count >= limit) return error.RateLimited;
        bucket.count += 1;
        try self.save(a, "rate", &key, bucket);
    }
    fn authenticate(self: *Coordinator, a: std.mem.Allocator, bearer: []const u8, now: i64) !Session {
        if (bearer.len != 64) return error.Unauthorized;
        const key = hash(bearer);
        const session = try self.load(Session, a, "sessions", &key) orelse return error.Unauthorized;
        if (session.expires <= now) return error.Expired;
        if (try self.load(Ban, a, "bans", session.identity)) |ban| if (ban.expires == 0 or ban.expires > now) return error.Banned;
        return session;
    }
    fn worker(self: *Coordinator, a: std.mem.Allocator, bearer: []const u8) !Enrollment {
        const key = hash(bearer);
        for (try self.store.list(a, "workers")) |record| {
            const enrollment = try parse(Enrollment, a, record.data);
            if (tokenEqual(enrollment.token_hash, &key)) return enrollment;
        }
        return error.Unauthorized;
    }
    fn publicRoom(self: *Coordinator, a: std.mem.Allocator, room: api.Room, now: i64) !bool {
        if (room.phase == .ended or room.phase == .failed or room.phase == .draining) return false;
        const enrollment = try self.load(Enrollment, a, "workers", room.worker) orelse return false;
        return !enrollment.worker.draining and enrollment.worker.heartbeat > now - 30;
    }
    fn dispatch(self: *Coordinator, io: std.Io, a: std.mem.Allocator, method: std.http.Method, path: []const u8, bearer: []const u8, address: []const u8, body: []const u8) !Result {
        const now: i64 = @intCast(@divTrunc(std.Io.Clock.real.now(io).nanoseconds, std.time.ns_per_s));
        if (method == .GET and equal(path, "/healthz")) return reply(a, .{ .status = "ok", .api = api.version });
        if (now - self.last_sweep >= 60) {
            // JSON fields are our own versioned records; timestamps are integers.
            try self.store.exec(try std.fmt.allocPrintSentinel(a, "DELETE FROM records WHERE kind IN ('sessions','challenges','tickets','ticket_ready') AND json_extract(data,'$.expires') <= {d}; DELETE FROM records WHERE kind='rate' AND json_extract(data,'$.start') < {d};", .{ now, now - 120 }, 0));
            try self.store.exec(try std.fmt.allocPrintSentinel(a, "DELETE FROM records WHERE kind='controls' AND json_extract(data,'$.expires') <= {d}; " ++
                "DELETE FROM records WHERE kind='bans' AND json_extract(data,'$.expires') > 0 AND json_extract(data,'$.expires') <= {d}; " ++
                "DELETE FROM records WHERE kind IN ('presence','room_secrets') AND id IN (SELECT id FROM records WHERE kind='rooms' AND json_extract(data,'$.terminal_at') < {d}); " ++
                "DELETE FROM records WHERE kind='requests' AND json_extract(data,'$.room') IN (SELECT id FROM records WHERE kind='rooms' AND json_extract(data,'$.terminal_at') < {d}); " ++
                "DELETE FROM records WHERE kind='rooms' AND json_extract(data,'$.terminal_at') < {d}; " ++
                "DELETE FROM records WHERE kind='audit' AND id NOT IN (SELECT id FROM records WHERE kind='audit' ORDER BY id DESC LIMIT 2048);", .{ now, now, now - 86400, now - 86400, now - 86400 }, 0));
            self.last_sweep = now;
        }
        // Unauthenticated traffic shares an address budget. Enrolled workers get
        // their own larger budget so admission ACKs do not starve heartbeats.
        if (std.mem.startsWith(u8, path, "/v1/workers/")) {
            const enrolled = self.worker(a, bearer) catch {
                try self.rate(a, address, now, 120);
                return error.Unauthorized;
            };
            try self.rate(a, try std.fmt.allocPrint(a, "worker:{s}", .{enrolled.worker.id}), now, 8192);
        } else try self.rate(a, address, now, 120);
        if (method == .POST and equal(path, "/v1/challenges")) {
            const input = try parse(struct { public_key: []const u8 }, a, body);
            _ = try identity.hex(32, input.public_key);
            const pending = try self.store.list(a, "challenges");
            var count: usize = 0;
            for (pending) |record| {
                const challenge = try parse(api.Challenge, a, record.data);
                if (challenge.expires <= now) try self.store.remove("challenges", record.id) else count += 1;
            }
            if (count >= 1024) return error.Capacity;
            const id = try identity.token(io);
            const nonce = try identity.token(io);
            const challenge: api.Challenge = .{ .id = &id, .public_key = input.public_key, .message = try std.fmt.allocPrint(a, "dk3-login-v1\n{s}\n{s}\n{s}", .{ self.config.public_url, id, nonce }), .expires = now + 60 };
            try self.save(a, "challenges", &id, challenge);
            return reply(a, challenge);
        }
        if (method == .POST and equal(path, "/v1/login")) {
            const login = try parse(api.Login, a, body);
            const challenge = try self.load(api.Challenge, a, "challenges", login.challenge) orelse return error.Unauthorized;
            try self.store.remove("challenges", login.challenge);
            if (challenge.expires <= now) return error.Expired;
            identity.verify(challenge.public_key, login.signature, challenge.message) catch return error.Unauthorized;
            const id = try identity.identifier(challenge.public_key);
            const token = try identity.token(io);
            const key = hash(&token);
            const credential: api.Credential = .{ .identity = &id, .token = &token, .expires = now + 3600 };
            try self.save(a, "sessions", &key, Session{ .identity = &id, .expires = credential.expires });
            return reply(a, credential);
        }
        if (method == .GET and equal(path, "/v1/rooms")) {
            var rooms: std.ArrayList(api.Room) = .empty;
            for (try self.store.list(a, "rooms")) |record| {
                const room = try parse(api.Room, a, record.data);
                if (room.config.privacy == .public and try self.publicRoom(a, room, now)) try rooms.append(a, room);
            }
            return reply(a, .{ .rooms = rooms.items });
        }
        if (method == .POST and equal(path, "/v1/rooms")) {
            const session = try self.authenticate(a, bearer, now);
            const request = try parse(api.Create, a, body);
            if (!validId(request.request_id) or !validText(request.config.name, 64) or std.mem.indexOfAny(u8, request.config.name, "\\\";+") != null or !validId(request.config.region) or !validId(request.config.map) or request.config.slots < 2 or request.config.slots > 32 or request.config.bots >= request.config.slots or request.config.skill < 1 or request.config.skill > 5 or request.config.rotation.len > 64) return error.InvalidRoom;
            const request_key = try std.fmt.allocPrint(a, "{s}:{s}", .{ session.identity, request.request_id });
            const payload_hash = hash(body);
            if (try self.load(RequestRecord, a, "requests", request_key)) |previous| {
                if (!equal(previous.payload_hash, &payload_hash)) return error.Conflict;
                const room = try self.load(api.Room, a, "rooms", previous.room) orelse return error.NotFound;
                const secret = try self.load(RoomSecret, a, "room_secrets", room.id) orelse return error.NotFound;
                return reply(a, .{ .room = room, .access_code = secret.access_code });
            }
            const existing = try self.store.list(a, "rooms");
            var active_rooms: usize = 0;
            var address_rooms: usize = 0;
            for (existing) |record| {
                const room = try parse(api.Room, a, record.data);
                if (room.phase == .ended or room.phase == .failed) continue;
                active_rooms += 1;
                if (equal(room.owner, session.identity)) return error.Capacity;
                if (try self.load(RoomSecret, a, "room_secrets", room.id)) |secret| if (equal(secret.address, address)) {
                    address_rooms += 1;
                };
            }
            if (active_rooms >= self.config.max_rooms or address_rooms >= self.config.rooms_per_address) return error.Capacity;
            const allocation = try self.selectWorker(a, request.config, request.compatibility, false, now);
            const host = allocation.worker;
            const selected_port = allocation.port;
            const id = try identity.token(io);
            const access_code = try identity.token(io);
            const endpoint = if (std.mem.indexOfScalar(u8, host.address, ':') != null) try std.fmt.allocPrint(a, "[{s}]:{d}", .{ host.address, selected_port }) else try std.fmt.allocPrint(a, "{s}:{d}", .{ host.address, selected_port });
            const room: api.Room = .{ .id = &id, .owner = session.identity, .worker = host.id, .generation = 1, .endpoint = endpoint, .config = request.config, .compatibility = request.compatibility, .created = now, .empty_since = now };
            try self.store.exec("BEGIN IMMEDIATE");
            errdefer self.store.exec("ROLLBACK") catch {};
            try self.save(a, "rooms", &id, room);
            try self.save(a, "room_secrets", &id, RoomSecret{ .access_code = &access_code, .address = address });
            try self.save(a, "requests", request_key, RequestRecord{ .room = &id, .payload_hash = &payload_hash });
            try self.store.exec("COMMIT");
            return reply(a, .{ .room = room, .access_code = if (room.config.privacy == .private) @as([]const u8, &access_code) else "" });
        }
        if (method == .POST and equal(path, "/v1/join")) {
            const session = try self.authenticate(a, bearer, now);
            const request = try parse(api.Join, a, body);
            const room = try self.load(api.Room, a, "rooms", request.room) orelse return error.NotFound;
            if (!try self.publicRoom(a, room, now) or room.phase == .allocating) return error.NoWorker;
            const enrollment = try self.load(Enrollment, a, "workers", room.worker) orelse return error.NoWorker;
            if (!room.compatibility.compatible(request.compatibility) or !contains(enrollment.worker.cosmetics, request.compatibility.cosmetic)) return error.Incompatible;
            const secret = try self.load(RoomSecret, a, "room_secrets", room.id) orelse return error.NotFound;
            if (room.config.privacy == .private and !equal(room.owner, session.identity) and !tokenEqual(secret.access_code, request.access_code)) return error.Forbidden;
            var reservations: usize = 0;
            for (try self.store.list(a, "tickets")) |record| {
                const ticket = try parse(api.Ticket, a, record.data);
                if (ticket.expires <= now) {
                    try self.store.remove("tickets", record.id);
                    continue;
                }
                if (equal(ticket.room, room.id)) {
                    if (equal(ticket.identity, session.identity)) return reply(a, .{ .ticket = ticket, .endpoint = room.endpoint });
                    reservations += 1;
                }
            }
            var reserved_reconnects: usize = 0;
            var replacing: usize = 0;
            if (try self.load([]api.Presence, a, "presence", room.id)) |presence| for (presence) |member| {
                if (equal(member.identity, session.identity)) {
                    if (member.connected) replacing = 1;
                } else if (!member.connected and member.left + 60 > now) reserved_reconnects += 1;
            };
            if ((@as(usize, room.humans) -| replacing) + reservations + reserved_reconnects + room.config.bots >= room.config.slots) return error.Capacity;
            const id = try identity.token(io);
            const client_key = try identity.token(io);
            const server_key = try identity.token(io);
            const ticket: api.Ticket = .{ .id = &id, .identity = session.identity, .room = room.id, .generation = room.generation, .expires = now + 30, .client_key = &client_key, .server_key = &server_key };
            try self.save(a, "tickets", &id, ticket);
            return reply(a, .{ .ticket = ticket, .endpoint = room.endpoint });
        }
        if (method == .POST and equal(path, "/v1/workers/heartbeat")) {
            var enrollment = try self.worker(a, bearer);
            const heartbeat = try parse(permanent.Heartbeat, a, body);
            if (heartbeat.rooms.len > enrollment.worker.capacity) return error.Capacity;
            try self.store.exec("BEGIN IMMEDIATE");
            errdefer self.store.exec("ROLLBACK") catch {};
            enrollment.worker.heartbeat = now;
            enrollment.permanent_rooms = heartbeat.permanent_rooms;
            try self.save(a, "workers", enrollment.worker.id, enrollment);
            for (heartbeat.rooms) |event| {
                var room = try self.load(api.Room, a, "rooms", event.room) orelse continue;
                if (!equal(room.worker, enrollment.worker.id) or room.generation != event.generation) continue;
                if (room.phase == .ended or room.phase == .failed) continue;
                if (event.humans > room.config.slots or event.phase == .allocating) return error.InvalidState;
                if (event.members.len > 256) return error.InvalidState;
                var owner_present = now < room.created + 60;
                var successor: ?api.Presence = null;
                var humans: usize = 0;
                for (event.members) |member| {
                    _ = try identity.hex(32, member.identity);
                    if (member.joined <= 0 or member.joined > now + 5 or member.left > now + 5) return error.InvalidState;
                    if (member.connected) humans += 1;
                    if (equal(member.identity, room.owner) and (member.connected or member.left + 60 > now)) owner_present = true;
                    if (member.connected and (successor == null or member.joined < successor.?.joined)) successor = member;
                }
                if (humans != event.humans) return error.InvalidState;
                if (!owner_present and !try self.isPermanent(a, room.id)) if (successor) |member| {
                    room.owner = member.identity;
                };
                try self.save(a, "presence", room.id, event.members);
                // A stop decision is sticky until the worker acknowledges exit.
                // Stale status must never resurrect a draining allocation.
                if (room.phase != .draining or event.phase == .ended or event.phase == .failed) room.phase = event.phase;
                if (room.phase == .ended or room.phase == .failed) room.terminal_at = now;
                room.humans = event.humans;
                if (room.humans > 0) room.empty_since = null else if (room.empty_since == null) {
                    room.empty_since = now;
                }
                try self.save(a, "rooms", room.id, room);
            }
            if (heartbeat.maps.len > enrollment.worker.capacity) return error.InvalidState;
            for (heartbeat.maps) |report| {
                var room = try self.load(api.Room, a, "rooms", report.room) orelse continue;
                if (!equal(room.worker, enrollment.worker.id) or room.generation != report.generation or room.phase == .ended or room.phase == .failed) continue;
                const binding = try self.load(permanent.Binding, a, "permanent_rooms", room.id) orelse return error.InvalidState;
                if (!contains(binding.maps, report.map)) return error.InvalidState;
                room.config.map = report.map;
                try self.save(a, "rooms", room.id, room);
            }
            try self.reconcilePermanent(a, now);
            var rooms: std.ArrayList(api.Room) = .empty;
            var permanent_assignments: std.ArrayList(permanent.Assignment) = .empty;
            for (try self.store.list(a, "rooms")) |record| {
                var room = try parse(api.Room, a, record.data);
                if (!equal(room.worker, enrollment.worker.id) or room.phase == .ended or room.phase == .failed) continue;
                if (room.empty_since) |since| if (now - since >= 300 and !try self.isPermanent(a, room.id)) {
                    room.phase = .draining;
                    try self.save(a, "rooms", room.id, room);
                };
                try rooms.append(a, room);
                if (try self.load(permanent.Binding, a, "permanent_rooms", room.id)) |binding| {
                    if (self.permanentConfig(binding.key)) |config| try permanent_assignments.append(a, .{ .room = room.id, .generation = room.generation, .players = config.players, .map_seconds = @as(u32, config.map_minutes) * 60 });
                }
            }
            var tickets: std.ArrayList(api.Ticket) = .empty;
            for (try self.store.list(a, "tickets")) |record| {
                const ticket = try parse(api.Ticket, a, record.data);
                if (ticket.expires <= now) continue;
                for (rooms.items) |room| if (room.phase != .draining and equal(ticket.room, room.id) and ticket.generation == room.generation) {
                    try tickets.append(a, ticket);
                    break;
                };
            }
            var controls: std.ArrayList(api.Control) = .empty;
            for (try self.store.list(a, "controls")) |record| {
                const control = try parse(api.Control, a, record.data);
                if (control.expires <= now) continue;
                for (rooms.items) |room| if (equal(control.room, room.id) and control.generation == room.generation and room.phase != .draining) {
                    try controls.append(a, control);
                    break;
                };
            }
            try self.store.exec("COMMIT");
            if (!enrollment.permanent_rooms) return reply(a, .{ .rooms = rooms.items, .tickets = tickets.items, .controls = controls.items, .draining = enrollment.worker.draining });
            return reply(a, .{ .rooms = rooms.items, .tickets = tickets.items, .controls = controls.items, .permanent = permanent_assignments.items, .draining = enrollment.worker.draining });
        }
        if (method == .POST and equal(path, "/v1/admission")) {
            const session = try self.authenticate(a, bearer, now);
            const request = try parse(struct { ticket: []const u8 }, a, body);
            const ticket = try self.load(api.Ticket, a, "tickets", request.ticket) orelse return error.Expired;
            if (!equal(ticket.identity, session.identity)) return error.Forbidden;
            if (ticket.expires <= now) return error.Expired;
            return reply(a, .{ .ready = (try self.store.get(a, "ticket_ready", ticket.id)) != null });
        }
        if (method == .POST and equal(path, "/v1/workers/ready")) {
            const enrollment = try self.worker(a, bearer);
            const request = try parse(struct { tickets: []const []const u8 }, a, body);
            if (request.tickets.len > 1024) return error.Capacity;
            for (request.tickets) |id| {
                const ticket = try self.load(api.Ticket, a, "tickets", id) orelse continue;
                const room = try self.load(api.Room, a, "rooms", ticket.room) orelse continue;
                if (!equal(room.worker, enrollment.worker.id)) return error.Forbidden;
                try self.save(a, "ticket_ready", id, .{ .expires = ticket.expires });
            }
            return reply(a, .{ .accepted = true });
        }
        if (method == .POST and equal(path, "/v1/workers/controlled")) {
            const enrollment = try self.worker(a, bearer);
            const request = try parse(struct { control: []const u8 }, a, body);
            const control = try self.load(api.Control, a, "controls", request.control) orelse return reply(a, .{ .accepted = true });
            const room = try self.load(api.Room, a, "rooms", control.room) orelse return error.NotFound;
            if (!equal(room.worker, enrollment.worker.id)) return error.Forbidden;
            try self.store.remove("controls", control.id);
            return reply(a, .{ .accepted = true });
        }
        if (method == .POST and equal(path, "/v1/workers/consume")) {
            const enrollment = try self.worker(a, bearer);
            const request = try parse(struct { ticket: []const u8 }, a, body);
            const ticket = try self.load(api.Ticket, a, "tickets", request.ticket) orelse return error.NotFound;
            const room = try self.load(api.Room, a, "rooms", ticket.room) orelse return error.NotFound;
            if (!equal(room.worker, enrollment.worker.id)) return error.Forbidden;
            try self.store.remove("tickets", ticket.id);
            return reply(a, .{ .accepted = true });
        }
        if (std.mem.startsWith(u8, path, "/v1/operator/")) {
            if (!tokenEqual(bearer, self.config.admin_token)) return error.Unauthorized;
            if (method == .GET and equal(path, "/v1/operator/status")) {
                var rooms: std.ArrayList(api.Room) = .empty;
                var workers: std.ArrayList(api.Worker) = .empty;
                for (try self.store.list(a, "rooms")) |record| try rooms.append(a, try parse(api.Room, a, record.data));
                for (try self.store.list(a, "workers")) |record| try workers.append(a, (try parse(Enrollment, a, record.data)).worker);
                return reply(a, .{ .time = now, .rooms = rooms.items, .workers = workers.items, .pending_admissions = (try self.store.list(a, "tickets")).len, .pending_controls = (try self.store.list(a, "controls")).len });
            }
            if (method == .GET and equal(path, "/v1/operator/audit")) return reply(a, .{ .events = try self.store.list(a, "audit") });
            if (method != .POST) return error.NotFound;
            if (equal(path, "/v1/operator/enroll")) {
                const request = try parse(struct { worker: api.Worker, token: []const u8 }, a, body);
                const host = request.worker;
                if (try self.load(Enrollment, a, "workers", host.id)) |previous| {
                    if (!previous.worker.draining) return error.Conflict;
                    for (try self.store.list(a, "rooms")) |record| {
                        const room = try parse(api.Room, a, record.data);
                        if (equal(room.worker, host.id) and room.phase != .ended and room.phase != .failed) return error.Conflict;
                    }
                }
                if (!validId(host.id) or !validId(host.region) or request.token.len < 32 or host.capacity == 0 or host.capacity > 256 or @as(u32, host.first_port) + host.capacity > 65535 or host.maps.len == 0 or host.cosmetics.len == 0 or host.compatibility.protocol != api.protocol) return error.InvalidWorker;
                if (host.maps.len > 512 or host.cosmetics.len > 16) return error.InvalidWorker;
                for (host.maps) |map| if (!validId(map.name) or map.modes == 0 or map.modes & ~@as(u8, 7) != 0) return error.InvalidWorker;
                _ = try std.Io.net.IpAddress.parse(host.address, host.first_port);
                var enrolled = host;
                enrolled.heartbeat = 0;
                const key = hash(request.token);
                try self.save(a, "workers", host.id, Enrollment{ .token_hash = &key, .worker = enrolled });
                try self.audit(io, a, now, "enroll", .{ .worker = host.id });
                return reply(a, .{ .enrolled = host.id });
            }
            if (equal(path, "/v1/operator/drain") or equal(path, "/v1/operator/revoke")) {
                const request = try parse(struct { worker: []const u8 }, a, body);
                var enrollment = try self.load(Enrollment, a, "workers", request.worker) orelse return error.NotFound;
                enrollment.worker.draining = true;
                if (equal(path, "/v1/operator/revoke")) enrollment.token_hash = "revoked";
                try self.save(a, "workers", request.worker, enrollment);
                try self.audit(io, a, now, if (equal(path, "/v1/operator/revoke")) "revoke" else "drain", .{ .worker = request.worker });
                return reply(a, .{ .draining = request.worker });
            }
            if (equal(path, "/v1/operator/ban")) {
                const ban = try parse(Ban, a, body);
                _ = try identity.hex(32, ban.identity);
                if (!validText(ban.reason, 200) or ban.expires < 0) return error.InvalidBan;
                try self.store.exec("BEGIN IMMEDIATE");
                errdefer self.store.exec("ROLLBACK") catch {};
                try self.save(a, "bans", ban.identity, ban);
                for (try self.store.list(a, "rooms")) |record| {
                    const room = try parse(api.Room, a, record.data);
                    if (room.phase == .ended or room.phase == .failed or room.phase == .draining) continue;
                    try self.queueControl(io, a, now, room, ban.identity, ban.reason, if (ban.expires == 0) std.math.maxInt(i32) else ban.expires);
                }
                try self.audit(io, a, now, "ban", ban);
                try self.store.exec("COMMIT");
                return reply(a, .{ .banned = ban.identity });
            }
            if (equal(path, "/v1/operator/kick")) {
                const request = try parse(struct { room: []const u8, identity: []const u8, reason: []const u8, ban_seconds: u32 = 900 }, a, body);
                _ = try identity.hex(32, request.identity);
                if (!validText(request.reason, 200) or request.ban_seconds > 86400) return error.InvalidBan;
                const room = try self.load(api.Room, a, "rooms", request.room) orelse return error.NotFound;
                if (room.phase == .ended or room.phase == .failed or room.phase == .draining) return error.Conflict;
                try self.store.exec("BEGIN IMMEDIATE");
                errdefer self.store.exec("ROLLBACK") catch {};
                try self.queueControl(io, a, now, room, request.identity, request.reason, now + request.ban_seconds);
                try self.audit(io, a, now, "kick", request);
                try self.store.exec("COMMIT");
                return reply(a, .{ .queued = true });
            }
            if (equal(path, "/v1/operator/end")) {
                const request = try parse(struct { room: []const u8, reason: []const u8 }, a, body);
                if (!validText(request.reason, 200)) return error.InvalidReason;
                var room = try self.load(api.Room, a, "rooms", request.room) orelse return error.NotFound;
                if (room.phase != .ended and room.phase != .failed) room.phase = .draining;
                try self.save(a, "rooms", room.id, room);
                try self.audit(io, a, now, "end", request);
                return reply(a, .{ .draining = room.id });
            }
        }
        return error.NotFound;
    }
    fn audit(self: *Coordinator, io: std.Io, a: std.mem.Allocator, now: i64, action: []const u8, detail: anytype) !void {
        const nonce = try identity.token(io);
        try self.save(a, "audit", try std.fmt.allocPrint(a, "{d}-{s}", .{ now, nonce }), .{ .time = now, .action = action, .detail = detail });
    }
    fn queueControl(self: *Coordinator, io: std.Io, a: std.mem.Allocator, now: i64, room: api.Room, guest_id: []const u8, reason: []const u8, banned_until: i64) !void {
        const pending = try self.store.list(a, "controls");
        if (pending.len >= 1024) return error.Capacity;
        var room_pending: usize = 0;
        for (pending) |record| if (equal((try parse(api.Control, a, record.data)).room, room.id)) {
            room_pending += 1;
        };
        if (room_pending >= 64) return error.Capacity;
        const id = try identity.token(io);
        try self.save(a, "controls", &id, api.Control{ .id = &id, .room = room.id, .generation = room.generation, .identity = guest_id, .reason = reason, .expires = now + 300, .banned_until = banned_until });
    }
    const Allocation = struct { worker: api.Worker, port: u16 };
    fn selectWorker(self: *Coordinator, a: std.mem.Allocator, config: api.RoomConfig, compatibility: ?api.Compatibility, require_permanent: bool, now: i64) !Allocation {
        const existing = try self.store.list(a, "rooms");
        var active: usize = 0;
        for (existing) |record| {
            const room = try parse(api.Room, a, record.data);
            if (room.phase != .ended and room.phase != .failed) active += 1;
        }
        if (active >= self.config.max_rooms) return error.NoWorker;
        var selected: ?api.Worker = null;
        var selected_used: usize = 0;
        var selected_port: u16 = 0;
        for (try self.store.list(a, "workers")) |record| {
            const enrolled = try parse(Enrollment, a, record.data);
            if (require_permanent and !enrolled.permanent_rooms) continue;
            const candidate = enrolled.worker;
            if (candidate.draining or candidate.heartbeat <= now - 30 or !equal(candidate.region, config.region) or (if (compatibility) |wanted| !candidate.compatibility.compatible(wanted) else false)) continue;
            if (!contains(candidate.cosmetics, if (compatibility) |wanted| wanted.cosmetic else candidate.compatibility.cosmetic) or !supportsMap(candidate.maps, config.map, config.mode)) continue;
            var valid_rotation = true;
            for (config.rotation) |map_name| if (!validId(map_name) or !supportsMap(candidate.maps, map_name, config.mode)) {
                valid_rotation = false;
                break;
            };
            if (!valid_rotation) continue;
            var used: usize = 0;
            var ports: [256]bool = @splat(false);
            for (existing) |room_record| {
                const room = try parse(api.Room, a, room_record.data);
                if (!equal(room.worker, candidate.id) or room.phase == .ended or room.phase == .failed) continue;
                used += 1;
                const suffix = std.mem.lastIndexOfScalar(u8, room.endpoint, ':') orelse continue;
                const port = std.fmt.parseInt(u16, room.endpoint[suffix + 1 ..], 10) catch continue;
                if (port >= candidate.first_port and port - candidate.first_port < ports.len) ports[port - candidate.first_port] = true;
            }
            if (used >= candidate.capacity) continue;
            if (selected == null or candidate.capacity - used > selected.?.capacity - selected_used) {
                var port_index: usize = 0;
                while (port_index < candidate.capacity and ports[port_index]) : (port_index += 1) {}
                selected = candidate;
                selected_used = used;
                selected_port = candidate.first_port + @as(u16, @intCast(port_index));
            }
        }
        return .{ .worker = selected orelse return error.NoWorker, .port = selected_port };
    }
    fn isPermanent(self: *Coordinator, a: std.mem.Allocator, id: []const u8) !bool {
        return (try self.store.get(a, "permanent_rooms", id)) != null;
    }
    fn permanentConfig(self: *Coordinator, key: []const u8) ?permanent.Config {
        for (self.config.permanent_rooms) |config| if (equal(config.id, key)) return config;
        return null;
    }
    // Runs within the heartbeat transaction. Never release an uncertain process's
    // allocation, even when its worker has stopped responding.
    fn reconcilePermanent(self: *Coordinator, a: std.mem.Allocator, now: i64) !void {
        for (try self.store.list(a, "permanent_rooms")) |record| {
            const binding = try parse(permanent.Binding, a, record.data);
            const config = self.permanentConfig(binding.key);
            var changed = config == null or !config.?.enabled;
            if (config) |wanted| {
                const revision = hash(try std.json.Stringify.valueAlloc(a, wanted, .{}));
                changed = changed or !equal(binding.config_hash, &revision);
            }
            if (changed) if (try self.load(api.Room, a, "rooms", record.id)) |old| {
                var room = old;
                if (room.phase != .ended and room.phase != .failed and room.phase != .draining) {
                    room.phase = .draining;
                    try self.save(a, "rooms", room.id, room);
                }
            };
        }
        for (self.config.permanent_rooms) |config| {
            if (!config.enabled) continue;
            const id = hash(try std.fmt.allocPrint(a, "dk3-permanent:{s}", .{config.id}));
            const previous = try self.load(permanent.Binding, a, "permanent_rooms", &id);
            if (try self.load(api.Room, a, "rooms", &id)) |old| {
                if (old.phase != .ended and old.phase != .failed) continue;
                if (now < (old.terminal_at orelse now) + 30) continue;
            }
            const allocation = self.selectWorker(a, config.room(), null, true, now) catch |err| switch (err) {
                error.NoWorker => continue,
                else => return err,
            };
            const host = allocation.worker;
            const revision = hash(try std.json.Stringify.valueAlloc(a, config, .{}));
            const generation = if (previous) |binding| binding.generation + 1 else 1;
            const endpoint = if (std.mem.indexOfScalar(u8, host.address, ':') != null) try std.fmt.allocPrint(a, "[{s}]:{d}", .{ host.address, allocation.port }) else try std.fmt.allocPrint(a, "{s}:{d}", .{ host.address, allocation.port });
            const room: api.Room = .{ .id = &id, .owner = &id, .worker = host.id, .generation = generation, .endpoint = endpoint, .config = config.room(), .compatibility = host.compatibility, .created = now, .empty_since = null };
            try self.save(a, "rooms", &id, room);
            try self.save(a, "room_secrets", &id, RoomSecret{ .access_code = "", .address = "server" });
            try self.store.remove("presence", &id);
            try self.save(a, "permanent_rooms", &id, permanent.Binding{ .key = config.id, .config_hash = &revision, .generation = generation, .maps = config.maps });
        }
    }
    fn contains(values: []const []const u8, value: []const u8) bool {
        for (values) |item| if (equal(item, value)) return true;
        return false;
    }
    fn supportsMap(maps: []const api.Map, name: []const u8, mode: api.Mode) bool {
        for (maps) |map| if (equal(map.name, name) and map.modes & (@as(u8, 1) << @intFromEnum(mode)) != 0) return true;
        return false;
    }
};

const Fixture = struct {
    const operator = "test-operator-credential-at-least-32-bytes";
    const worker_token = "test-worker-credential-at-least-32-bytes";
    const guest_token = "a" ** 64;
    const guest_id = "b" ** 64;
    const compatibility: api.Compatibility = .{ .schema = "test-schema", .rules = "test-rules", .gameplay = "test-gameplay", .cosmetic = "stock-v1" };
    a: std.mem.Allocator,
    coordinator: Coordinator,
    now: i64,
    fn init(a: std.mem.Allocator) !Fixture {
        var self: Fixture = .{ .a = a, .coordinator = try Coordinator.init(.{ .database = ":memory:", .admin_token = operator, .public_url = "https://192.0.2.1" }, a), .now = @intCast(@divTrunc(std.Io.Clock.real.now(std.testing.io).nanoseconds, std.time.ns_per_s)) };
        const key = Coordinator.hash(guest_token);
        try self.coordinator.save(a, "sessions", &key, Session{ .identity = guest_id, .expires = self.now + 3600 });
        const worker_config: api.Worker = .{ .id = "test-worker", .region = "default", .address = "192.0.2.1", .compatibility = compatibility, .cosmetics = &.{"stock-v1"}, .maps = &.{.{ .name = "e1dm1", .modes = 1 }} };
        _ = try self.request(.ok, "/v1/operator/enroll", operator, .{ .worker = worker_config, .token = worker_token });
        _ = try self.request(.ok, "/v1/workers/heartbeat", worker_token, api.Heartbeat{});
        return self;
    }
    fn request(self: *Fixture, status_code: std.http.Status, path: []const u8, token: []const u8, value: anytype) ![]const u8 {
        const response = self.coordinator.handle(std.testing.io, self.a, .POST, path, token, "192.0.2.2", try std.json.Stringify.valueAlloc(self.a, value, .{}));
        try std.testing.expectEqual(status_code, response.status);
        return response.body;
    }
    fn create(self: *Fixture) !api.Room {
        const data = try self.request(.ok, "/v1/rooms", guest_token, api.Create{ .request_id = "request-1", .config = .{ .name = "Test room", .region = "default", .mode = .dm, .map = "e1dm1" }, .compatibility = compatibility });
        return (try Coordinator.parse(struct { room: api.Room, access_code: []const u8 }, self.a, data)).room;
    }
    fn report(self: *Fixture, room: api.Room, phase: api.Phase) !void {
        _ = try self.request(.ok, "/v1/workers/heartbeat", worker_token, api.Heartbeat{ .rooms = &.{.{ .room = room.id, .generation = room.generation, .phase = phase, .humans = 0 }} });
    }
    fn current(self: *Fixture, id: []const u8) !api.Room {
        return (try self.coordinator.load(api.Room, self.a, "rooms", id)).?;
    }
};
test "operator stop is sticky until process exit and does not free uncertain capacity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var fixture = try Fixture.init(arena.allocator());
    defer fixture.coordinator.deinit();
    const room = try fixture.create();
    const retry = try fixture.create();
    try std.testing.expectEqualStrings(room.id, retry.id);
    try fixture.report(room, .lobby);
    _ = try fixture.request(.ok, "/v1/operator/end", Fixture.operator, .{ .room = room.id, .reason = "Test shutdown" });
    try fixture.report(room, .playing);
    try std.testing.expectEqual(api.Phase.draining, (try fixture.current(room.id)).phase);
    _ = try fixture.request(.conflict, "/v1/join", Fixture.guest_token, api.Join{ .room = room.id, .compatibility = Fixture.compatibility });
    _ = try fixture.request(.too_many_requests, "/v1/rooms", Fixture.guest_token, api.Create{ .request_id = "request-2", .config = room.config, .compatibility = Fixture.compatibility });
    try fixture.report(room, .ended);
    try std.testing.expect((try fixture.current(room.id)).terminal_at != null);
    try fixture.report(room, .playing);
    try std.testing.expectEqual(api.Phase.ended, (try fixture.current(room.id)).phase);
    _ = try fixture.request(.ok, "/v1/rooms", Fixture.guest_token, api.Create{ .request_id = "request-2", .config = room.config, .compatibility = Fixture.compatibility });
}
test "empty expiry drains and invalid heartbeat rolls back every event" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var fixture = try Fixture.init(arena.allocator());
    defer fixture.coordinator.deinit();
    var room = try fixture.create();
    room.empty_since = fixture.now - 301;
    try fixture.coordinator.save(fixture.a, "rooms", room.id, room);
    try fixture.report(room, .lobby);
    try std.testing.expectEqual(api.Phase.draining, (try fixture.current(room.id)).phase);
    var enrollment = (try fixture.coordinator.load(Enrollment, fixture.a, "workers", "test-worker")).?;
    enrollment.worker.capacity = 2;
    enrollment.worker.heartbeat = fixture.now - 9;
    try fixture.coordinator.save(fixture.a, "workers", "test-worker", enrollment);
    const before = try fixture.coordinator.store.get(fixture.a, "workers", "test-worker");
    _ = try fixture.request(.bad_request, "/v1/workers/heartbeat", Fixture.worker_token, api.Heartbeat{ .rooms = &.{
        .{ .room = room.id, .generation = 1, .phase = .playing, .humans = 0 },
        .{ .room = room.id, .generation = 1, .phase = .lobby, .humans = 40 },
    } });
    try std.testing.expectEqualStrings(before.?, (try fixture.coordinator.store.get(fixture.a, "workers", "test-worker")).?);
    try std.testing.expectEqual(api.Phase.draining, (try fixture.current(room.id)).phase);
}
test "moderation queues survive retries, require operator authority and acknowledge by worker" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var fixture = try Fixture.init(arena.allocator());
    defer fixture.coordinator.deinit();
    const room = try fixture.create();
    const request = .{ .room = room.id, .identity = Fixture.guest_id, .reason = "Test moderation" };
    _ = try fixture.request(.unauthorized, "/v1/operator/kick", Fixture.guest_token, request);
    _ = try fixture.request(.ok, "/v1/operator/kick", Fixture.operator, request);
    const controls = try fixture.coordinator.store.list(fixture.a, "controls");
    try std.testing.expectEqual(@as(usize, 1), controls.len);
    const command = try Coordinator.parse(api.Control, fixture.a, controls[0].data);
    try std.testing.expectEqualStrings(Fixture.guest_id, command.identity);
    try std.testing.expectEqual(@as(u64, 1), command.generation);
    try fixture.report(room, .lobby);
    try std.testing.expectEqual(@as(usize, 1), (try fixture.coordinator.store.list(fixture.a, "controls")).len);
    _ = try fixture.request(.unauthorized, "/v1/workers/controlled", Fixture.guest_token, .{ .control = command.id });
    _ = try fixture.request(.ok, "/v1/workers/controlled", Fixture.worker_token, .{ .control = command.id });
    _ = try fixture.request(.ok, "/v1/workers/controlled", Fixture.worker_token, .{ .control = command.id });
    try std.testing.expectEqual(@as(usize, 0), (try fixture.coordinator.store.list(fixture.a, "controls")).len);
}
test "guest proof is single use and cannot authenticate another challenge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var fixture = try Fixture.init(arena.allocator());
    defer fixture.coordinator.deinit();
    const pair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(@splat(7));
    const public = std.fmt.bytesToHex(pair.public_key.toBytes(), .lower);
    const data = try fixture.request(.ok, "/v1/challenges", "", .{ .public_key = &public });
    const challenge = try Coordinator.parse(api.Challenge, fixture.a, data);
    const signature = std.fmt.bytesToHex((try pair.sign(challenge.message, null)).toBytes(), .lower);
    const proof = api.Login{ .challenge = challenge.id, .signature = &signature };
    _ = try fixture.request(.ok, "/v1/login", "", proof);
    _ = try fixture.request(.unauthorized, "/v1/login", "", proof);
    const other_data = try fixture.request(.ok, "/v1/challenges", "", .{ .public_key = &public });
    const other = try Coordinator.parse(api.Challenge, fixture.a, other_data);
    _ = try fixture.request(.unauthorized, "/v1/login", "", api.Login{ .challenge = other.id, .signature = &signature });
}

test "permanent rooms require capable workers and preserve the old client schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a);
    defer fixture.coordinator.deinit();
    fixture.coordinator.config.permanent_rooms = &.{.{ .id = "always-dm", .name = "Always DM", .maps = &.{"e1dm1"} }};
    // An old worker continues receiving its exact existing response schema.
    const legacy = try fixture.request(.ok, "/v1/workers/heartbeat", Fixture.worker_token, api.Heartbeat{});
    _ = try Coordinator.parse(struct { rooms: []api.Room, tickets: []api.Ticket, controls: []api.Control, draining: bool }, a, legacy);
    try std.testing.expectEqual(@as(usize, 0), (try fixture.coordinator.store.list(a, "rooms")).len);
    _ = try fixture.request(.ok, "/v1/workers/heartbeat", Fixture.worker_token, permanent.Heartbeat{ .permanent_rooms = true });
    const records = try fixture.coordinator.store.list(a, "rooms");
    try std.testing.expectEqual(@as(usize, 1), records.len);
    var room = try fixture.current(records[0].id);
    try std.testing.expectEqual(@as(u8, 16), room.config.slots);
    try std.testing.expectEqual(@as(u8, 0), room.config.bots); // No human slots reserved for replaceable bots.
    room.empty_since = fixture.now - 1000;
    try fixture.coordinator.save(a, "rooms", room.id, room);
    _ = try fixture.request(.ok, "/v1/workers/heartbeat", Fixture.worker_token, permanent.Heartbeat{ .permanent_rooms = true, .rooms = &.{.{ .room = room.id, .generation = room.generation, .phase = .playing, .humans = 0 }} });
    room = try fixture.current(room.id);
    try std.testing.expectEqual(api.Phase.playing, room.phase);
    const listing = fixture.coordinator.handle(std.testing.io, a, .GET, "/v1/rooms", "", "192.0.2.2", "");
    const parsed = try Coordinator.parse(struct { rooms: []api.Room }, a, listing.body);
    try std.testing.expectEqual(@as(usize, 1), parsed.rooms.len);
    _ = try fixture.request(.ok, "/v1/join", Fixture.guest_token, api.Join{ .room = room.id, .compatibility = Fixture.compatibility });
}

test "permanent restart requires terminal acknowledgment and backoff; removal drains" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a);
    defer fixture.coordinator.deinit();
    fixture.coordinator.config.permanent_rooms = &.{.{ .id = "always-dm", .name = "Always DM", .maps = &.{"e1dm1"} }};
    _ = try fixture.request(.ok, "/v1/workers/heartbeat", Fixture.worker_token, permanent.Heartbeat{ .permanent_rooms = true });
    const id = (try fixture.coordinator.store.list(a, "rooms"))[0].id;
    const initial = try fixture.current(id);
    _ = try fixture.request(.ok, "/v1/operator/end", Fixture.operator, .{ .room = id, .reason = "Test restart" });
    try fixture.report(initial, .playing);
    try std.testing.expectEqual(api.Phase.draining, (try fixture.current(id)).phase);
    try fixture.report(initial, .failed);
    _ = try fixture.request(.ok, "/v1/workers/heartbeat", Fixture.worker_token, permanent.Heartbeat{ .permanent_rooms = true });
    try std.testing.expectEqual(initial.generation, (try fixture.current(id)).generation);
    var terminal = try fixture.current(id);
    terminal.terminal_at = fixture.now - 31;
    try fixture.coordinator.save(a, "rooms", id, terminal);
    _ = try fixture.request(.ok, "/v1/workers/heartbeat", Fixture.worker_token, permanent.Heartbeat{ .permanent_rooms = true });
    const replacement = try fixture.current(id);
    try std.testing.expectEqual(initial.generation + 1, replacement.generation);
    try std.testing.expectEqual(api.Phase.allocating, replacement.phase);
    // A delayed old-process heartbeat cannot overwrite the new generation.
    try fixture.report(initial, .playing);
    try std.testing.expectEqual(api.Phase.allocating, (try fixture.current(id)).phase);
    fixture.coordinator.config.permanent_rooms = &.{};
    _ = try fixture.request(.ok, "/v1/workers/heartbeat", Fixture.worker_token, permanent.Heartbeat{ .permanent_rooms = true });
    try std.testing.expectEqual(api.Phase.draining, (try fixture.current(id)).phase);
    try fixture.report(replacement, .ended);
    try std.testing.expectEqual(api.Phase.ended, (try fixture.current(id)).phase);
}

test "permanent map reports follow the allocated rotation and invalid reports roll back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a);
    defer fixture.coordinator.deinit();
    var enrollment = (try fixture.coordinator.load(Enrollment, a, "workers", "test-worker")).?;
    enrollment.worker.maps = &.{ .{ .name = "e1dm1", .modes = 1 }, .{ .name = "e2dm1", .modes = 1 } };
    try fixture.coordinator.save(a, "workers", "test-worker", enrollment);
    fixture.coordinator.config.permanent_rooms = &.{.{ .id = "always-dm", .name = "Always DM", .maps = &.{ "e1dm1", "e2dm1" } }};
    _ = try fixture.request(.ok, "/v1/workers/heartbeat", Fixture.worker_token, permanent.Heartbeat{ .permanent_rooms = true });
    const id = (try fixture.coordinator.store.list(a, "rooms"))[0].id;
    const room = try fixture.current(id);
    for ([_][]const u8{ "e2dm1", "e1dm1" }) |map| {
        _ = try fixture.request(.ok, "/v1/workers/heartbeat", Fixture.worker_token, permanent.Heartbeat{ .permanent_rooms = true, .maps = &.{.{ .room = id, .generation = room.generation, .map = map }} });
        try std.testing.expectEqualStrings(map, (try fixture.current(id)).config.map);
    }
    _ = try fixture.request(.bad_request, "/v1/workers/heartbeat", Fixture.worker_token, permanent.Heartbeat{ .permanent_rooms = true, .maps = &.{.{ .room = id, .generation = room.generation, .map = "unknown" }} });
    try std.testing.expectEqualStrings("e1dm1", (try fixture.current(id)).config.map);
}
