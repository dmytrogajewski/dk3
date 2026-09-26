// SPDX-License-Identifier: GPL-2.0-or-later
//! Native schema 1. Named portable records contain typed JSON values, never memory
//! layouts, pointers, archetype rows or jobs. Decode into an isolated world first.
const std = @import("std");
const data = @import("components.zig");
const ecs = @import("../ecs/world.zig");
const stream = @import("save_stream.zig");
pub const schema = 1;
pub const maximum = 64 * 1024 * 1024;
pub const model_limit = 512;
pub const sound_limit = 1024;
pub const archive_limit = 128;
pub const world_limit = 8 * 1024 * 1024;
pub const Archive = struct { map: []const u8, bytes: []const u8 };
pub const Resources = struct { models: []const []const u8 = &.{}, sounds: []const []const u8 = &.{} };
pub const Header = struct {
    at_ms: i64,
    next_id: u32,
    player_id: u32,
    episode: u8,
    resources: Resources = .{},
    pending: @import("target_actions.zig").Queue = @splat(null),
    journey: ?@import("travel.zig").Journey = null,
};
pub const Loaded = struct {
    arena: *std.heap.ArenaAllocator,
    world: data.World,
    header: Header,
    map: []const u8,
    skill: u8,
    visited: []const Archive = &.{},
    pub fn deinit(self: *Loaded, allocator: std.mem.Allocator) void {
        self.world.deinit();
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }
    pub fn rebase(self: *Loaded, now: i64) !void {
        const delta = try std.math.sub(i64, now, self.header.at_ms);
        var query = self.world.queryAccess(0, 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            inline for (std.meta.fields(data.Component)) |field| if (self.world.get(entity, field.type) catch null) |value| {
                try @import("snapshot_time.zig").rebase(@field(data.ComponentId, field.name), value, delta);
                try bounded(value.*);
            };
        };
        for (&self.header.pending) |*entry| if (entry.*) |*action| {
            action.due_ms = try std.math.add(i64, action.due_ms, delta);
        };
        self.header.at_ms = now;
        try bounded(self.header);
    }
};
pub fn validName(name: []const u8) bool {
    if (name.len == 0 or name.len >= 48) return false;
    for (name) |char| if (!(char >= 'a' and char <= 'z') and !(char >= '0' and char <= '9') and char != '_' and char != '-') return false;
    return true;
}
fn json(writer: *stream.Writer, allocator: std.mem.Allocator, name: []const u8, value: anytype) !void {
    try bounded(value);
    const bytes = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(bytes);
    try writer.raw(.{ .name = name, .kind = .bytes, .count = bytes.len, .data = bytes });
}
pub fn capture(allocator: std.mem.Allocator, storage: []u8, world: *data.World, map: []const u8, skill: u8, header: Header) ![]const u8 {
    return captureCampaign(allocator, storage, world, map, skill, header, &.{});
}
pub fn captureCampaign(allocator: std.mem.Allocator, storage: []u8, world: *data.World, map: []const u8, skill: u8, header: Header, visited: []const Archive) ![]const u8 {
    if (!validName(map) or skill < 1 or skill > 5 or world.query_depth != 0) return error.InvalidSnapshotContext;
    var writer = try stream.Writer.init(storage);
    try writer.record("campaign", 0);
    try writer.raw(.{ .name = "map", .kind = .text, .count = map.len, .data = map });
    try writer.integers("skill", &.{skill});
    try writer.integers("native_schema", &.{schema});
    try json(&writer, allocator, "state", header);
    // Stable persistent-ID ordering, independent of archetype relocation.
    var ids: [ecs.max_entities]u32 = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(0, data.World.mask(.{data.SoundEvent}), 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            ids[count] = try world.persistentId(entity);
            count += 1;
        };
    }
    std.mem.sort(u32, ids[0..count], {}, std.sort.asc(u32));
    for (ids[0..count]) |id| {
        const entity = world.find(id).?;
        try writer.record("native_entity", id);
        inline for (std.meta.fields(data.Component)) |field| if (world.get(entity, field.type) catch null) |value| {
            try json(&writer, allocator, field.name, value.*);
        };
    }
    if (visited.len > archive_limit) return error.ArchiveCapacity;
    for (visited, 1..) |archive, id| {
        if (!validName(archive.map) or std.mem.eql(u8, archive.map, map) or archive.bytes.len > world_limit) return error.InvalidArchive;
        try writer.record("visited_level", @intCast(id));
        try writer.raw(.{ .name = "map", .kind = .text, .count = archive.map.len, .data = archive.map });
        try writer.raw(.{ .name = "snapshot", .kind = .bytes, .count = archive.bytes.len, .data = archive.bytes });
    }
    return writer.finish();
}
fn parse(comptime T: type, allocator: std.mem.Allocator, field: stream.Field) !T {
    if (field.kind != .bytes or field.data.len > 1024 * 1024) return error.InvalidSnapshotField;
    const result = try std.json.parseFromSliceLeaky(T, allocator, field.data, .{ .allocate = .alloc_always, .max_value_len = 65536 });
    try bounded(result);
    return result;
}
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !Loaded {
    return decodeWorld(allocator, bytes, true);
}
fn decodeWorld(allocator: std.mem.Allocator, bytes: []const u8, allow_visited: bool) anyerror!Loaded {
    if (bytes.len > maximum) return error.SnapshotCapacity;
    var reader = try stream.Reader.init(bytes);
    const campaign = (try reader.nextRecord()) orelse return error.MissingCampaign;
    if (!std.mem.eql(u8, campaign.name, "campaign") or campaign.id != 0) return error.MissingCampaign;
    const arena = try allocator.create(std.heap.ArenaAllocator);
    errdefer allocator.destroy(arena);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const strings = arena.allocator();
    var map: ?[]const u8 = null;
    var skill: ?u8 = null;
    var version: ?i32 = null;
    var header: ?Header = null;
    while (try reader.nextField()) |field| {
        if (std.mem.eql(u8, field.name, "map")) {
            if (field.kind != .text or !validName(field.data)) return error.InvalidSaveMap;
            map = try strings.dupe(u8, field.data);
        } else if (std.mem.eql(u8, field.name, "skill")) {
            const value = try field.integer(0);
            if (field.count != 1 or value < 1 or value > 5) return error.InvalidSaveSkill;
            skill = @intCast(value);
        } else if (std.mem.eql(u8, field.name, "native_schema")) {
            if (field.count != 1) return error.InvalidSnapshotSchema;
            version = try field.integer(0);
        } else if (std.mem.eql(u8, field.name, "state")) header = try parse(Header, strings, field) else return error.UnsupportedSnapshotField;
    }
    if (version == null or version.? != schema) return error.UnsupportedSnapshotSchema;
    var world = data.World.init(allocator, 1024);
    errdefer world.deinit();
    var archives: std.ArrayList(Archive) = .empty;
    while (try reader.nextRecord()) |record| {
        if (std.mem.eql(u8, record.name, "visited_level")) {
            if (!allow_visited or archives.items.len >= archive_limit or record.id != archives.items.len + 1) return error.InvalidArchive;
            const name_field = (try reader.nextField()) orelse return error.InvalidArchive;
            const content = (try reader.nextField()) orelse return error.InvalidArchive;
            if (!std.mem.eql(u8, name_field.name, "map") or name_field.kind != .text or !validName(name_field.data) or !std.mem.eql(u8, content.name, "snapshot") or content.kind != .bytes or content.data.len > world_limit or try reader.nextField() != null) return error.InvalidArchive;
            if (std.mem.eql(u8, name_field.data, map orelse return error.InvalidSaveMap)) return error.InvalidArchive;
            for (archives.items) |prior| if (std.mem.eql(u8, prior.map, name_field.data)) return error.DuplicateArchive;
            var nested = try decodeWorld(allocator, content.data, false);
            defer nested.deinit(allocator);
            if (nested.header.journey != null or !std.mem.eql(u8, nested.map, name_field.data)) return error.InvalidArchive;
            try archives.append(strings, .{ .map = try strings.dupe(u8, name_field.data), .bytes = try strings.dupe(u8, content.data) });
            continue;
        }
        if (archives.items.len != 0) return error.InvalidSnapshotRecord;
        if (!std.mem.eql(u8, record.name, "native_entity") or record.id == 0) return error.InvalidSnapshotRecord;
        const entity = try world.create(record.id, .{});
        while (try reader.nextField()) |field| {
            var known = false;
            inline for (std.meta.fields(data.Component)) |component| if (std.mem.eql(u8, field.name, component.name)) {
                if (known) return error.DuplicateComponent;
                try world.put(entity, try parse(component.type, strings, field));
                known = true;
            };
            if (!known) return error.UnsupportedSnapshotComponent;
        }
    }
    const state = header orelse return error.MissingSnapshotState;
    if (state.next_id < world.next_id or state.next_id == std.math.maxInt(u32)) return error.InvalidNextIdentity;
    world.next_id = state.next_id;
    var result: Loaded = .{ .arena = arena, .world = world, .header = state, .map = map orelse return error.InvalidSaveMap, .skill = skill orelse return error.InvalidSaveSkill, .visited = archives.items };
    try validate(&result);
    return result;
}
// Reject non-finite/unbounded data before it can reach physics or renderer casts.
fn bounded(value: anytype) anyerror!void {
    switch (@typeInfo(@TypeOf(value))) {
        .float => if (!std.math.isFinite(value) or @abs(value) > 100000000) {
            return error.InvalidSnapshotNumber;
        },
        .int => |info| if (info.bits > 32 and (value < @as(i128, std.math.minInt(i32)) or value > std.math.maxInt(i32))) {
            return error.InvalidSnapshotNumber;
        },
        .array => for (value) |element| try bounded(element),
        .pointer => |info| {
            if (info.size != .slice) @compileError("snapshot pointer is not an owned slice");
            if (value.len > (if (info.child == u8) @as(usize, 65536) else 4096)) return error.SnapshotSliceLimit;
            if (info.child == u8) {
                if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidSnapshotString;
            } else for (value) |element| try bounded(element);
        },
        .@"struct" => |info| inline for (info.fields) |field| try bounded(@field(value, field.name)),
        .@"union" => switch (value) {
            inline else => |payload| try bounded(payload),
        },
        .optional => if (value) |present| {
            try bounded(present);
        },
        .@"enum", .bool, .void => {},
        else => @compileError("unsupported snapshot value"),
    }
}
fn require(world: *data.World, entity: ecs.Entity, comptime types: anytype) !void {
    inline for (types) |T| _ = try world.get(entity, T);
}
pub fn validate(snapshot: *Loaded) !void {
    const world = &snapshot.world;
    if (snapshot.header.episode < 1 or snapshot.header.episode > 4 or snapshot.header.at_ms < 0) return error.InvalidCampaignState;
    if (snapshot.header.journey) |journey| {
        if (!validName(journey.destination) or std.mem.eql(u8, snapshot.map, journey.destination) or journey.spawn.len >= 64 or @import("travel.zig").kind(snapshot.map, journey.destination) != journey.kind) return error.InvalidJourney;
        for (journey.spawn) |char| if (char < 32 or char == '"' or char == '\\') return error.InvalidJourney;
        for (journey.offset) |axis| if (@abs(axis) > 8192) return error.InvalidJourney;
    }
    if (snapshot.header.resources.models.len >= model_limit or snapshot.header.resources.sounds.len >= sound_limit) return error.InvalidResources;
    inline for (.{ snapshot.header.resources.models, snapshot.header.resources.sounds }) |names| for (names, 0..) |name, i| {
        if (name.len == 0 or name.len >= 64 or std.mem.indexOf(u8, name, "..") != null or name[0] == '/') return error.InvalidResources;
        for (names[0..i]) |prior| if (std.ascii.eqlIgnoreCase(prior, name)) return error.DuplicateSavedResource;
    };
    const player = world.find(snapshot.header.player_id) orelse return error.MissingSavedPlayer;
    try require(world, player, .{ data.Transform, data.Velocity, data.Player, data.Body, data.Binding, data.Health, data.Weapons, data.Character, data.Ailments, data.Keys, data.Hurt });
    if ((try world.get(player, data.Binding)).slot != 0) return error.InvalidSavedPlayerSlot;
    var occupied: [ecs.max_entities]bool = @splat(false);
    var players: usize = 0;
    var query = world.queryAccess(0, 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities()) |entity| {
        _ = try world.get(entity, data.Transform);
        if (world.get(entity, data.Binding) catch null) |binding| {
            if (binding.slot >= occupied.len or occupied[binding.slot] or (binding.slot > 0 and binding.slot < 64)) return error.InvalidSavedBinding;
            occupied[binding.slot] = true;
            if ((world.get(entity, data.Projectile) catch null) == null) try require(world, entity, .{data.Body});
        }
        if (world.get(entity, data.Body) catch null) |body| for (body.mins, body.maxs) |low, high| if (low > high or @abs(low) > 8192 or @abs(high) > 8192) return error.InvalidSavedBounds;
        if ((world.get(entity, data.Exit) catch null) != null) {
            try require(world, entity, .{ data.MapObject, data.Binding, data.Body });
            if (!std.mem.eql(u8, (try world.get(entity, data.MapObject)).classname, "trigger_changelevel")) return error.InvalidSavedExit;
        }
        if (world.get(entity, data.Health) catch null) |health| if (health.current < -1000000 or health.current > 1000000 or health.maximum < 1 or health.maximum > 1000000 or health.armor < 0 or health.armor > 1000000) return error.InvalidSavedHealth;
        if (world.get(entity, data.Mover) catch null) |mover| if (mover.motion.duration_ms <= 0 or mover.speed <= 0) return error.InvalidSavedMover;
        if (world.get(entity, data.Train) catch null) |train| if (train.position.duration_ms <= 0 or train.angles.duration_ms <= 0 or train.speed <= 0) return error.InvalidSavedTrain;
        if (world.get(entity, data.Secret) catch null) |secret| if (secret.motion.duration_ms <= 0 or secret.speed <= 0) return error.InvalidSavedSecret;
        if (world.get(entity, data.Player) catch null) |state| {
            players += 1;
            if (try world.persistentId(entity) != snapshot.header.player_id or state.timer_ms > 2147483647 or state.view_height < -64 or state.view_height > 128 or state.ground_entity > 2047) return error.InvalidSavedPlayer;
        }
        if (world.get(entity, data.Weapons) catch null) |weapons| {
            if (weapons.weapon < 1 or weapons.weapon > 28 or weapons.weaponstate < 0 or weapons.weaponstate > 3 or weapons.dk3GlockClip < 0 or weapons.dk3GlockClip > 10) return error.InvalidSavedWeapons;
            for (weapons.ammo) |amount| if (amount < 0 or amount > 1000000) return error.InvalidSavedWeapons;
        }
        if (world.get(entity, data.Actor) catch null) |actor| {
            if (actor.definition >= @import("actor_catalog").entries.len or actor.guard.pose >= 3 or actor.guard.rounds > 8) return error.InvalidSavedActor;
            try require(world, entity, .{ data.Velocity, data.Body, data.Health, data.Hurt, data.Binding, data.MapObject });
            if (@import("actor_catalog").find((try world.get(entity, data.MapObject)).classname) != actor.definition) return error.InvalidSavedActorClass;
        }
        if (world.get(entity, data.Projectile) catch null) |projectile| {
            if (projectile.weapon != 2 or projectile.damage < 0 or projectile.damage > 1000000) return error.InvalidSavedProjectile;
            try require(world, entity, .{ data.Binding, data.Velocity });
        }
        if (world.get(entity, data.Pickup) catch null) |pickup| {
            try require(world, entity, .{ data.Binding, data.Body, data.ItemMotion, data.MapObject });
            switch (pickup.kind) {
                .weapon, .ammunition => |id| if (id == 0 or id > 28) {
                    return error.InvalidSavedPickup;
                },
                .key => |id| if (id >= @import("item_catalog").keys.len) {
                    return error.InvalidSavedPickup;
                },
                else => {},
            }
        }
        if (world.get(entity, data.TargetSequence) catch null) |sequence| {
            if (sequence.events.len > 128 or sequence.cursor > sequence.events.len) return error.InvalidSavedSequence;
            for (sequence.events) |event| if (event.delay_ms < 0 or event.delay_ms > 3600000) return error.InvalidSavedSequence;
        }
        if (world.get(entity, data.Character) catch null) |character| {
            for (character.attributes) |attribute| if (attribute < 0 or attribute > 5) return error.InvalidSavedCharacter;
            if (character.level < 1 or character.level > 25 or character.points < 0 or character.experience < 0 or character.save_gems < 0) return error.InvalidSavedCharacter;
        }
    };
    if (players != 1) return error.InvalidSavedPlayer;
}

test "campaign saves own flat archives and validate nested worlds before admission" {
    const memory = std.testing.allocator;
    var world = data.World.init(memory, 16);
    defer world.deinit();
    _ = try world.create(7, .{ data.Transform{}, data.Velocity{}, data.Player{}, data.Body{}, data.Binding{ .slot = 0 }, data.Health{}, data.Hurt{}, data.Weapons{ .weapon = 1 }, data.Character{}, data.Ailments{}, data.Keys{} });
    const header: Header = .{ .at_ms = 1000, .episode = 1, .player_id = 7, .next_id = world.next_id };
    var child_buffer: [32768]u8 = undefined;
    var parent_buffer: [65536]u8 = undefined;
    var outer_buffer: [98304]u8 = undefined;
    const child = try capture(memory, &child_buffer, &world, "e1m3a", 3, header);
    const parent = try captureCampaign(memory, &parent_buffer, &world, "e1m3b", 3, header, &.{.{ .map = "e1m3a", .bytes = child }});
    var loaded = try decode(memory, parent);
    defer loaded.deinit(memory);
    const outer = try captureCampaign(memory, &outer_buffer, &world, "e1m4a", 3, header, &.{.{ .map = "e1m3b", .bytes = parent }});
    try std.testing.expectError(error.InvalidArchive, decode(memory, outer));
    child_buffer[child.len - 1] ^= 1;
    const corrupt = try captureCampaign(memory, &parent_buffer, &world, "e1m3b", 3, header, &.{.{ .map = "e1m3a", .bytes = child }});
    try std.testing.expectError(error.Checksum, decode(memory, corrupt));
    try std.testing.expectEqual(@as(usize, 1), loaded.visited.len);
    try std.testing.expectEqualStrings("e1m3a", loaded.visited[0].map);
    var retained = try decode(memory, loaded.visited[0].bytes);
    defer retained.deinit(memory);
    try std.testing.expectEqual(@as(i32, 100), (try retained.world.get(retained.world.find(7).?, data.Health)).current);
}

test "portable native snapshots own strings and preserve IDs before rebasing" {
    const allocator = std.testing.allocator;
    var world = data.World.init(allocator, 16);
    defer world.deinit();
    const player = try world.create(7, .{ data.Transform{}, data.Velocity{}, data.Player{}, data.Body{}, data.Binding{ .slot = 0 }, data.Health{}, data.Hurt{}, data.Weapons{ .weapon = 1 }, data.Character{ .boost_until = .{ 0, 1300, 0, 0, 0 } }, data.Ailments{}, data.Keys{} });
    _ = player;
    const mover = try world.create(42, .{ data.Transform{}, data.MapObject{ .classname = "func_train", .target = "next" }, data.Train{ .phase = .dwelling, .action = .{ .at_ms = 2000 }, .next_target = "next" } });
    _ = mover;
    world.next_id = 100;
    var bytes: [65536]u8 = undefined;
    const saved = try capture(allocator, &bytes, &world, "e1m3a", 3, .{ .at_ms = 1000, .episode = 1, .player_id = 7, .next_id = 100 });
    var loaded = try decode(allocator, saved);
    defer loaded.deinit(allocator);
    @memset(&bytes, 0);
    try std.testing.expectEqual(@as(u32, 100), loaded.world.next_id);
    try std.testing.expectEqualStrings("next", (try loaded.world.get(loaded.world.find(42).?, data.Train)).next_target);
    try loaded.rebase(9000);
    try std.testing.expectEqual(@as(?i64, 10000), (try loaded.world.get(loaded.world.find(42).?, data.Train)).action.at_ms);
    try std.testing.expectEqual(@as(i64, 9300), (try loaded.world.get(loaded.world.find(7).?, data.Character)).boost_until[1]);
    try std.testing.expectEqual(@as(i64, 1300), (try world.get(world.find(7).?, data.Character)).boost_until[1]);
    try world.put(world.find(42).?, data.Binding{ .slot = 0 });
    try world.put(world.find(42).?, data.Body{});
    const duplicate_slot = try capture(allocator, &bytes, &world, "e1m3a", 3, .{ .at_ms = 1000, .episode = 1, .player_id = 7, .next_id = 100 });
    try std.testing.expectError(error.InvalidSavedBinding, decode(allocator, duplicate_slot));
    try std.testing.expectEqual(@as(i32, 100), (try world.get(world.find(7).?, data.Health)).current);
}
