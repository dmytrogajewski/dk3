// SPDX-License-Identifier: GPL-2.0-or-later
//! Private coordinator/worker policy. Public client API and compatibility stay unchanged.
const api = @import("api.zig");
pub const Config = struct {
    id: []const u8,
    name: []const u8,
    region: []const u8 = "default",
    mode: api.Mode = .dm,
    maps: []const []const u8,
    players: u8 = 16,
    skill: u8 = 3,
    map_minutes: u16 = 10,
    enabled: bool = true,
    pub fn room(self: Config) api.RoomConfig {
        return .{ .name = self.name, .region = self.region, .mode = self.mode, .map = self.maps[0], .rotation = self.maps[1..], .slots = self.players, .bots = 0, .skill = self.skill, .timelimit = self.map_minutes, .fraglimit = 0, .capturelimit = 0 };
    }
};
pub const Binding = struct { key: []const u8, config_hash: []const u8, generation: u64, maps: []const []const u8 };
pub const Assignment = struct { room: []const u8, generation: u64, players: u8, map_seconds: u32 };

pub const MapStatus = struct { room: []const u8, generation: u64, map: []const u8 };
pub const Status = struct { map: []const u8, humans: u8, bots: u8 };
pub const Heartbeat = struct { rooms: []const api.Event = &.{}, permanent_rooms: bool = false, maps: []const MapStatus = &.{} };
