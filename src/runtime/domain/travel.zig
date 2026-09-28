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
    companions: u2 = 0,
};
pub const Request = struct { exit: u32, player: u32 };
pub const Exit = struct {
    latched: bool = false,
    ready_ms: i64 = 0,
    ending_player: u32 = 0,
    ending_started: ?i64 = null,
    camera: data.Transform = .{},
};
pub fn kind(source: []const u8, destination: []const u8) Kind {
    if (source.len < 2 or destination.len < 2 or source[1] != destination[1]) return .episode;
    const prefix = destination.len - 1;
    if (destination[prefix] != 'a' or (source.len >= prefix and std.mem.eql(u8, source[0..prefix], destination[0..prefix]))) return .submap;
    return .chapter;
}
pub const Follower = struct {
    persistent_id: u32 = 0,
    classname: []const u8,
    offset: data.Vec3 = @splat(0),
    angles: data.Vec3 = @splat(0),
    state: data.Companion,
    health: data.Health,
    weapons: data.Weapons,
    character: data.Character,
    keys: data.Keys,
    ailments: data.Ailments,
    pub fn capture(world: *data.World, entity: @import("../ecs/world.zig").Entity, origin: data.Vec3) !Follower {
        const pose = (try world.get(entity, data.Transform)).*;
        return .{ .persistent_id = try world.persistentId(entity), .offset = @import("vector.zig").subtract(pose.position, origin), .angles = pose.angles, .classname = @import("actor_catalog").entries[(try world.get(entity, data.Actor)).definition].classname, .state = (try world.get(entity, data.Companion)).*, .health = (try world.get(entity, data.Health)).*, .weapons = (try world.get(entity, data.Weapons)).*, .character = (try world.get(entity, data.Character)).*, .keys = (try world.get(entity, data.Keys)).*, .ailments = (try world.get(entity, data.Ailments)).* };
    }
};
pub const Traveler = struct {
    companions: [2]?Follower = @splat(null),
    health: data.Health,
    weapons: data.Weapons,
    character: data.Character,
    keys: data.Keys,
    ailments: data.Ailments,
    episode: u8,
    at_ms: i64,
    pub fn capture(world: *data.World, player: @import("../ecs/world.zig").Entity, episode: u8, now: i64) !Traveler {
        var result: Traveler = .{ .health = (try world.get(player, data.Health)).*, .weapons = (try world.get(player, data.Weapons)).*, .character = (try world.get(player, data.Character)).*, .keys = (try world.get(player, data.Keys)).*, .ailments = (try world.get(player, data.Ailments)).*, .episode = episode, .at_ms = now };
        var query = world.queryAccess(data.World.mask(.{data.Companion}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.Companion)) |entity, state| {
            if (state.owner != try world.persistentId(player)) continue;
            result.companions[@intFromEnum(state.identity)] = try Follower.capture(world, entity, (try world.get(player, data.Transform)).position);
        };
        return result;
    }
    pub fn selectParty(self: *Traveler, journey: Journey) void {
        if (journey.kind != .submap) return;
        for (&self.companions, 0..) |*follower, index| if (journey.companions & (@as(u2, 1) << @as(u1, @intCast(index))) == 0) {
            follower.* = null;
        };
    }
    pub fn arrive(self: *Traveler, episode: u8, now: i64, table: *const @import("weapons.zig").Table) !void {
        const delta = try std.math.sub(i64, now, self.at_ms);
        try @import("snapshot_time.zig").rebase(.character, &self.character, delta);
        self.character.liquid = .{};
        self.character.sound_environment = 0;
        try @import("snapshot_time.zig").rebase(.weapons, &self.weapons, delta);
        for (&self.companions) |*maybe| if (maybe.*) |*follower| {
            try @import("snapshot_time.zig").rebase(.character, &follower.character, delta);
            follower.character.liquid = .{};
            try @import("snapshot_time.zig").rebase(.weapons, &follower.weapons, delta);
            follower.state.motor = .{ .command_ms = now };
            follower.state.jump_started_ms = 0;
            follower.state.target = 0;
            follower.state.collecting = 0;
            follower.state.collect_forced = false;
            follower.state.collect_scan_ms = now;
            follower.state.collect_until_ms = 0;
            follower.state.avoided_item = 0;
            follower.state.avoid_until_ms = 0;
            follower.state.yielding_until_ms = 0;
            follower.state.selected_weapon = 0;
            follower.state.owner = 0;
            follower.state.order = .follow;
            follower.state.authored = .none;
            follower.state.animation_until = null;
            follower.state.stopped = false;
            follower.state.next_ms = now;
            follower.state.last_ms = now;
            follower.ailments.cure();
            follower.weapons.weaponTime = 0;
            follower.weapons.weaponstate = 0;
            follower.weapons.dk3AttackHeld = 0;
            if (episode != self.episode) {
                follower.keys = .{};
                follower.weapons = .{};
                if (episode == 1 and !follower.state.carrying) {
                    const initial = catalog.starting(episode);
                    _ = follower.weapons.acquire(table, initial, table.entries[initial].initialAmmo);
                }
            }
        };
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

test "submap party selection honors exit flags and retains continuing birth identities" {
    const t = std.testing;
    const mikiko: Follower = .{ .persistent_id = 0x1000010, .classname = "mikiko", .state = .{ .identity = .mikiko }, .health = .{ .current = 61 }, .weapons = .{}, .character = .{}, .keys = .{}, .ailments = .{} };
    const superfly: Follower = .{ .persistent_id = 0x1000011, .classname = "superfly", .state = .{ .identity = .superfly }, .health = .{ .current = 72 }, .weapons = .{}, .character = .{}, .keys = .{}, .ailments = .{} };
    var traveler: Traveler = .{ .companions = .{ mikiko, superfly }, .health = .{}, .weapons = .{}, .character = .{}, .keys = .{}, .ailments = .{}, .episode = 3, .at_ms = 1000 };
    var chapter = traveler;
    traveler.selectParty(.{ .destination = "e3m1b", .kind = .submap, .companions = 2 });
    try t.expectEqual(null, traveler.companions[0]);
    try t.expectEqual(superfly.persistent_id, traveler.companions[1].?.persistent_id);
    try t.expectEqual(@as(i32, 72), traveler.companions[1].?.health.current);
    try traveler.arrive(3, 2000, &.{});
    try t.expectEqual(superfly.persistent_id, traveler.companions[1].?.persistent_id);
    chapter.selectParty(.{ .destination = "e3m2a", .kind = .chapter });
    try t.expectEqual(mikiko.persistent_id, chapter.companions[0].?.persistent_id);
    try t.expectEqual(superfly.persistent_id, chapter.companions[1].?.persistent_id);
}
