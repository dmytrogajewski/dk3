// SPDX-License-Identifier: GPL-2.0-or-later
//! Versioned control-plane contracts. Strings are bounded and validated at admission.
pub const version = 1;
pub const protocol = 1346;
pub const Mode = enum { dm, ctf, deathtag };
pub const Privacy = enum { public, private };
pub const Phase = enum { allocating, lobby, playing, draining, ended, failed };
pub const Compatibility = struct {
    protocol: u32 = protocol_version,
    schema: []const u8,
    rules: []const u8,
    gameplay: []const u8,
    cosmetic: []const u8,
    const protocol_version = 1346;
    pub fn compatible(a: Compatibility, b: Compatibility) bool {
        const std = @import("std");
        return a.protocol == b.protocol and std.mem.eql(u8, a.schema, b.schema) and std.mem.eql(u8, a.rules, b.rules) and std.mem.eql(u8, a.gameplay, b.gameplay);
    }
};
pub const RoomConfig = struct {
    name: []const u8,
    region: []const u8,
    mode: Mode,
    map: []const u8,
    slots: u8 = 8,
    bots: u8 = 0,
    skill: u8 = 3,
    privacy: Privacy = .public,
    rotation: []const []const u8 = &.{},
    fraglimit: u16 = 20,
    timelimit: u16 = 20,
    capturelimit: u8 = 5,
};
pub const Room = struct {
    id: []const u8,
    owner: []const u8,
    worker: []const u8,
    generation: u64,
    endpoint: []const u8,
    config: RoomConfig,
    compatibility: Compatibility,
    phase: Phase = .allocating,
    humans: u8 = 0,
    created: i64,
    empty_since: ?i64,
    terminal_at: ?i64 = null,
};
pub const Map = struct { name: []const u8, modes: u8 };
pub const Worker = struct {
    id: []const u8,
    region: []const u8,
    address: []const u8,
    first_port: u16 = 27960,
    capacity: u16 = 1,
    compatibility: Compatibility,
    cosmetics: []const []const u8,
    maps: []const Map,
    heartbeat: i64 = 0,
    draining: bool = false,
};
pub const Ticket = struct {
    id: []const u8,
    identity: []const u8,
    room: []const u8,
    generation: u64,
    expires: i64,
    client_key: []const u8,
    server_key: []const u8,
};
pub const Challenge = struct { id: []const u8, public_key: []const u8, message: []const u8, expires: i64 };
pub const Login = struct { challenge: []const u8, signature: []const u8 };
pub const Credential = struct { identity: []const u8, token: []const u8, expires: i64 };
pub const Create = struct { request_id: []const u8, config: RoomConfig, compatibility: Compatibility };
pub const Join = struct { room: []const u8, compatibility: Compatibility, access_code: []const u8 = "" };
pub const Presence = struct { identity: []const u8, joined: i64, left: i64, connected: bool, ready: bool, slot: i32 };
pub const Event = struct { room: []const u8, generation: u64, phase: Phase, humans: u8, members: []const Presence = &.{} };
pub const Heartbeat = struct { rooms: []const Event = &.{} };
pub const Failure = struct { code: []const u8, message: []const u8 };

/// Control messages bind an authenticated identity and allocation generation.
/// A worker repeats delivery until the game persists and acknowledges the ID.
pub const Control = struct {
    id: []const u8,
    room: []const u8,
    generation: u64,
    identity: []const u8,
    reason: []const u8,
    expires: i64,
    banned_until: i64,
};
