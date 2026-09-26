// SPDX-License-Identifier: GPL-2.0-or-later
//! Campaign transfer values. A traveler carries inventory, never the old world pose or slots.
const std = @import("std");
const data = @import("components.zig");
const catalog = @import("weapon_catalog");
pub const Kind = enum { chapter, submap, episode };
pub const Journey = struct {
    destination: []const u8,
    spawn: []const u8 = "",
    offset: data.Vec3 = @splat(0),
    angles: data.Vec3 = @splat(0),
    kind: Kind,
};
pub const Request = struct { exit: u32, player: u32 };
pub const Exit = struct { latched: bool = false, ready_ms: i64 = 0 };
pub fn kind(source: []const u8, destination: []const u8) Kind {
    if (source.len < 2 or destination.len < 2 or source[1] != destination[1]) return .episode;
    const prefix = destination.len - 1;
    if (destination[prefix] != 'a' or (source.len >= prefix and std.mem.eql(u8, source[0..prefix], destination[0..prefix]))) return .submap;
    return .chapter;
}
pub const Traveler = struct {
    health: data.Health,
    weapons: data.Weapons,
    character: data.Character,
    keys: data.Keys,
    ailments: data.Ailments,
    episode: u8,
    at_ms: i64,
    pub fn capture(world: *data.World, player: @import("../ecs/world.zig").Entity, episode: u8, now: i64) !Traveler {
        return .{ .health = (try world.get(player, data.Health)).*, .weapons = (try world.get(player, data.Weapons)).*, .character = (try world.get(player, data.Character)).*, .keys = (try world.get(player, data.Keys)).*, .ailments = (try world.get(player, data.Ailments)).*, .episode = episode, .at_ms = now };
    }
    pub fn arrive(self: *Traveler, episode: u8, now: i64, table: *const @import("weapons.zig").Table) !void {
        const delta = try std.math.sub(i64, now, self.at_ms);
        try @import("snapshot_time.zig").rebase(.character, &self.character, delta);
        try @import("snapshot_time.zig").rebase(.weapons, &self.weapons, delta);
        self.at_ms = now;
        self.ailments.mask &= 120;
        self.ailments.freeze_level = 0;
        self.ailments.cure();
        if (episode != self.episode) {
            self.keys = .{};
            const sword_xp = self.weapons.dk3SwordExperience;
            self.weapons = .{ .dk3SwordExperience = sword_xp };
            const initial = catalog.starting(episode);
            _ = self.weapons.acquire(table, initial, table.entries[initial].initialAmmo);
            // Campaign-wide equipment belongs to its class, not an episode-ID switch.
            for (catalog.entries) |entry| if (entry.spec.campaign_equipment) {
                _ = self.weapons.acquire(table, entry.id, table.entries[entry.id].initialAmmo);
            };
            self.episode = episode;
        }
        self.weapons.weaponTime = 0;
        self.weapons.weaponstate = 0;
        self.weapons.dk3AttackHeld = 0;
        self.weapons.dk3Burst = 0;
        self.weapons.dk3Charge = 0;
        self.weapons.dk3NovaSpent = 0;
        self.weapons.event_sequence = 0;
    }
    pub fn apply(self: Traveler, world: *data.World, player: @import("../ecs/world.zig").Entity) !void {
        (try world.get(player, data.Health)).* = self.health;
        (try world.get(player, data.Weapons)).* = self.weapons;
        (try world.get(player, data.Character)).* = self.character;
        (try world.get(player, data.Keys)).* = self.keys;
        (try world.get(player, data.Ailments)).* = self.ailments;
    }
};
test "travel separates submap continuity from chapter and episode reset" {
    try std.testing.expectEqual(Kind.submap, kind("e1m3b", "e1m3a"));
    try std.testing.expectEqual(Kind.submap, kind("e1m3a", "e1m3b"));
    try std.testing.expectEqual(Kind.chapter, kind("e1m3b", "e1m4a"));
    try std.testing.expectEqual(Kind.episode, kind("e1m7a", "e2m1a"));
    var traveler: Traveler = .{ .health = .{ .current = 64 }, .weapons = .{ .weapon = 21, .dk3GlockClip = 3, .dk3AttackHeld = 1, .dk3SwordExperience = 800 }, .character = .{ .boost_until = .{ 0, 31000, 0, 0, 0 } }, .keys = .{ .mask = 1 }, .ailments = .{ .mask = 255, .freeze_level = 1 }, .episode = 1, .at_ms = 1000 };
    const table: @import("weapons.zig").Table = .{};
    try traveler.arrive(1, 100, &table);
    try std.testing.expectEqual(@as(i32, 3), traveler.weapons.dk3GlockClip);
    try std.testing.expectEqual(@as(i64, 30100), traveler.character.boost_until[1]);
    try std.testing.expectEqual(@as(i32, 0), traveler.weapons.dk3AttackHeld);
    try std.testing.expectEqual(@as(u32, 120), traveler.ailments.mask);
    try traveler.arrive(2, 100, &table);
    try std.testing.expectEqual(@as(u32, 0), traveler.keys.mask);
    try std.testing.expectEqual(@as(i32, 800), traveler.weapons.dk3SwordExperience);
    try std.testing.expectEqual(@as(i32, 64), traveler.health.current);
}
