// SPDX-License-Identifier: GPL-2.0-or-later
//! Guest identity and room operations shared by the native browser and CLI.
const std = @import("std");
const api = @import("api.zig");
const identity = @import("identity.zig");
const Http = @import("http.zig").Client;
const Ed25519 = std.crypto.sign.Ed25519;
pub const Config = struct {
    coordinator: []const u8,
    ca_file: ?[]const u8 = null,
    identity_file: []const u8,
    compatibility: api.Compatibility,
};
pub const Joined = struct { ticket: api.Ticket, endpoint: []const u8 };
pub const Created = struct { room: api.Room, access_code: []const u8 };
pub const Client = struct {
    http: Http,
    config: Config,
    allocator: std.mem.Allocator,
    pub fn init(a: std.mem.Allocator, io: std.Io, config: Config) !Client {
        return .{ .http = try Http.init(a, io, config.coordinator, "", config.ca_file), .config = config, .allocator = a };
    }
    pub fn deinit(self: *Client) void {
        self.http.deinit();
    }
    pub fn login(self: *Client) !void {
        const a = self.allocator;
        const io = self.http.transport.io;
        var seed: [32]u8 = undefined;
        defer std.crypto.secureZero(u8, &seed);
        const path = self.config.identity_file;
        const encoded = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(128)) catch |err| switch (err) {
            error.FileNotFound => block: {
                try io.randomSecure(&seed);
                const key = std.fmt.bytesToHex(seed, .lower);
                if (std.fs.path.dirname(path)) |directory| try std.Io.Dir.cwd().createDirPath(io, directory);
                std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = &key, .flags = .{ .exclusive = true, .permissions = @enumFromInt(0o600) } }) catch |create_error| switch (create_error) {
                    // Another client may have created this persistent identity concurrently.
                    error.PathAlreadyExists => {},
                    else => return create_error,
                };
                break :block try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(128));
            },
            else => return err,
        };
        seed = try identity.hex(32, std.mem.trim(u8, encoded, " \r\n"));
        var pair = try Ed25519.KeyPair.generateDeterministic(seed);
        defer std.crypto.secureZero(u8, &pair.secret_key.bytes);
        const public = std.fmt.bytesToHex(pair.public_key.toBytes(), .lower);
        const challenge = try self.http.call(a, api.Challenge, "/v1/challenges", .{ .public_key = &public });
        if (!std.mem.eql(u8, challenge.public_key, &public)) return error.InvalidChallenge;
        const prefix = try std.fmt.allocPrint(a, "dk3-login-v1\n{s}\n{s}\n", .{ self.http.base, challenge.id });
        if (!std.mem.startsWith(u8, challenge.message, prefix)) return error.InvalidChallenge;
        const signature = std.fmt.bytesToHex((try pair.sign(challenge.message, null)).toBytes(), .lower);
        const credential = try self.http.call(a, api.Credential, "/v1/login", api.Login{ .challenge = challenge.id, .signature = &signature });
        const expected = try identity.identifier(&public);
        if (!std.mem.eql(u8, &expected, credential.identity)) return error.InvalidIdentity;
        self.http.token = credential.token;
    }
    pub fn list(self: *Client) ![]api.Room {
        return (try self.http.get(self.allocator, struct { rooms: []api.Room }, "/v1/rooms")).rooms;
    }
    pub fn create(self: *Client, request_id: []const u8, config: api.RoomConfig) !Created {
        return self.http.call(self.allocator, Created, "/v1/rooms", api.Create{ .request_id = request_id, .config = config, .compatibility = self.config.compatibility });
    }
    pub fn join(self: *Client, room: []const u8, access_code: []const u8) !Joined {
        const joined = try self.http.call(self.allocator, Joined, "/v1/join", api.Join{ .room = room, .access_code = access_code, .compatibility = self.config.compatibility });
        for (0..25) |_| {
            const status = try self.http.call(self.allocator, struct { ready: bool }, "/v1/admission", .{ .ticket = joined.ticket.id });
            if (status.ready) return joined;
            try self.http.transport.io.sleep(.fromSeconds(1), .awake);
        }
        return error.AdmissionNotReady;
    }
};
