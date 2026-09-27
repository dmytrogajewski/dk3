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
        var query = world.queryAccess(0, data.World.mask(.{ data.SoundEvent, data.ImpactEvent }), 0);
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
        if ((world.get(entity, data.SoundEvent) catch null) != null or (world.get(entity, data.ImpactEvent) catch null) != null) return error.SavedTransientEvent;
        _ = try world.get(entity, data.Transform);
        if (world.get(entity, data.Binding) catch null) |binding| {
            if (binding.slot >= occupied.len or occupied[binding.slot] or (binding.slot > 0 and binding.slot < 64)) return error.InvalidSavedBinding;
            occupied[binding.slot] = true;
            if ((world.get(entity, data.Projectile) catch null) == null and (world.get(entity, data.Hammer) catch null) == null and (world.get(entity, data.Shockwave) catch null) == null and (world.get(entity, data.Nova) catch null) == null and (world.get(entity, data.Flashlight) catch null) == null and (world.get(entity, data.Zeus) catch null) == null and (world.get(entity, data.ZeusBolt) catch null) == null and (world.get(entity, data.Nightmare) catch null) == null and (world.get(entity, data.MetaRing) catch null) == null and (world.get(entity, data.MetaLaser) catch null) == null) try require(world, entity, .{data.Body});
        }
        if (world.get(entity, data.Exit) catch null) |exit| {
            if (exit.ending_started != null) {
                const viewer = world.find(exit.ending_player) orelse return error.InvalidSavedEnding;
                if ((try world.get(viewer, data.Body)).motion_owner != try world.persistentId(entity) or (try world.get(viewer, data.Player)).mode != .frozen) return error.InvalidSavedEnding;
            } else if (exit.ending_player != 0) return error.InvalidSavedEnding;
        }
        if (world.get(entity, data.Body) catch null) |body| {
            if (body.mass <= 0 or body.mass > 100000) return error.InvalidSavedMass;
            for (body.mins, body.maxs) |low, high| if (low > high or @abs(low) > 8192 or @abs(high) > 8192) return error.InvalidSavedBounds;
            if (body.motion_owner) |owner_id| {
                const owner = world.find(owner_id) orelse return error.InvalidSavedMotionOwner;
                if (world.get(owner, data.Cinematic) catch null) |cinematic| {
                    if (!cinematic.active or cinematic.viewer != try world.persistentId(entity)) return error.InvalidSavedMotionOwner;
                } else if (world.get(owner, data.Exit) catch null) |exit| {
                    if (exit.ending_started == null or exit.ending_player != try world.persistentId(entity)) return error.InvalidSavedMotionOwner;
                } else if (world.get(owner, data.Monitor) catch null) |monitor| {
                    if (monitor.viewer != try world.persistentId(entity)) return error.InvalidSavedMotionOwner;
                } else if (world.get(owner, data.Nightmare) catch null) |ritual| {
                    if (ritual.victim != try world.persistentId(entity)) return error.InvalidSavedMotionOwner;
                } else {
                    const projectile = world.get(owner, data.Projectile) catch return error.InvalidSavedMotionOwner;
                    if (projectile.flight != .ballista or projectile.flight.ballista.victim != try world.persistentId(entity)) return error.InvalidSavedMotionOwner;
                }
            }
        }
        if ((world.get(entity, data.Exit) catch null) != null) {
            try require(world, entity, .{ data.MapObject, data.Binding, data.Body });
            if (!std.mem.eql(u8, (try world.get(entity, data.MapObject)).classname, "trigger_changelevel")) return error.InvalidSavedExit;
        }
        if (world.get(entity, data.Monitor) catch null) |monitor| {
            try require(world, entity, .{ data.MapObject, data.Binding, data.Body });
            if (!std.mem.eql(u8, (try world.get(entity, data.MapObject)).classname, "func_monitor") or monitor.duration_ms < 750 or monitor.duration_ms > 3600000 or (monitor.viewer == null) != (monitor.until_ms == null)) return error.InvalidSavedMonitor;
            if (monitor.viewer) |viewer_id| {
                const viewer = world.find(viewer_id) orelse return error.InvalidSavedMonitor;
                try require(world, viewer, .{ data.Player, data.Body, data.Health });
                if ((try world.get(viewer, data.Body)).motion_owner != try world.persistentId(entity) or (try world.get(viewer, data.Player)).mode != .frozen) return error.InvalidSavedMonitor;
                if (world.find(monitor.camera) == null or world.find(monitor.target) == null) return error.InvalidSavedMonitor;
            }
        }
        if (world.get(entity, data.ThunderSpray) catch null) |spray| {
            try require(world, entity, .{ data.Transform, data.Velocity, data.Body, data.Binding, data.Lifetime });
            if (spray.owner == 0 or spray.phase >= 12 or spray.scale <= 0 or spray.scale > 2 or spray.next_ms < spray.stepped_ms or spray.stepped_ms < spray.born_ms) return error.InvalidSavedThunderSpray;
        }
        if (world.get(entity, data.HealthTree) catch null) |tree| {
            try require(world, entity, .{ data.MapObject, data.Binding, data.Body, data.Transform, data.Velocity, data.Random, data.Health });
            if (tree.maximum > 5 or tree.fruit > tree.maximum or tree.previous > 5 or !std.mem.eql(u8, (try world.get(entity, data.MapObject)).classname, "misc_healthtree")) return error.InvalidSavedHealthTree;
        }
        if (world.get(entity, data.Script) catch null) |script| {
            if (script.name.len == 0 or script.name.len > 64 or script.remaining < -1 or script.remaining > 10000 or script.depth > script.stack.len) return error.InvalidSavedScript;
        }
        if (world.get(entity, data.Firefly) catch null) |fly| {
            try require(world, entity, .{ data.Binding, data.Body, data.Transform, data.Velocity, data.Random });
            if (fly.source == 0 or fly.distance < 20 or fly.distance > 200 or fly.speed < 1 or fly.speed > 500 or fly.personality < 0.25 or fly.personality > 1 or fly.phase >= 12 or fly.scale <= 0 or fly.scale > 10000 or fly.maximum_alpha < 0 or fly.maximum_alpha > 1 or fly.delta_alpha < 0 or fly.delta_alpha > 1 or fly.color_fraction < 0 or fly.color_fraction > 1.25) return error.InvalidSavedFirefly;
            if (world.find(fly.source)) |source| {
                const classname = if (fly.wisp != null) @import("actor_catalog").wisp.classname else @import("actor_catalog").firefly.classname;
                if (!std.mem.eql(u8, (try world.get(source, data.MapObject)).classname, classname)) return error.InvalidSavedFirefly;
                if (fly.wisp) |wisp| {
                    const swarm = world.get(source, data.WispSwarm) catch return error.InvalidSavedWisp;
                    if (swarm.count > 10 or std.mem.indexOfScalar(u32, swarm.children[0..swarm.count], try world.persistentId(entity)) == null or wisp.blend_after > 5) return error.InvalidSavedWisp;
                    for (wisp.goal ++ wisp.collected_at) |axis| if (!std.math.isFinite(axis)) return error.InvalidSavedWisp;
                }
            }
        }
        if (world.get(entity, data.WispSwarm) catch null) |swarm| {
            try require(world, entity, .{ data.MapObject, data.Transform, data.Random });
            if (swarm.count < 1 or swarm.count > 10 or !std.mem.eql(u8, (try world.get(entity, data.MapObject)).classname, @import("actor_catalog").wisp.classname)) return error.InvalidSavedWisp;
            if (swarm.sending) |index| if (index >= swarm.count) return error.InvalidSavedWisp;
            for (swarm.goal) |axis| if (!std.math.isFinite(axis)) return error.InvalidSavedWisp;
            for (swarm.children[0..swarm.count], 0..) |id, i| {
                if (id == 0 or std.mem.indexOfScalar(u32, swarm.children[0..i], id) != null) return error.InvalidSavedWisp;
                const child = world.find(id) orelse return error.InvalidSavedWisp;
                const fly = world.get(child, data.Firefly) catch return error.InvalidSavedWisp;
                if (fly.source != try world.persistentId(entity) or fly.wisp == null) return error.InvalidSavedWisp;
            }
            for (swarm.children[swarm.count..]) |id| if (id != 0) return error.InvalidSavedWisp;
        }
        if (world.get(entity, data.Scenery) catch null) |scenery| {
            try require(world, entity, .{ data.Transform, data.Velocity, data.Body, data.Binding });
            if (scenery.model.len == 0 or scenery.model.len >= 64 or scenery.sequence.last < scenery.sequence.first or scenery.sequence.fps == 0 or scenery.sequence.fps > 240 or scenery.alpha < 0 or scenery.alpha > 1 or scenery.damage < 0 or scenery.damage > 1000000) return error.InvalidSavedScenery;
            for (scenery.scale) |scale| if (scale <= 0 or scale > 10000) return error.InvalidSavedScenery;
            if (!scenery.fragment and !scenery.explosion) {
                try require(world, entity, .{ data.MapObject, data.Random });
                if (!@import("scenery.zig").owns((try world.get(entity, data.MapObject)).classname)) return error.InvalidSavedScenery;
            } else if (scenery.breakable or (scenery.expires_ms == null and scenery.gib == null)) return error.InvalidSavedScenery;
            if (scenery.gib != null) {
                try require(world, entity, .{data.Random});
                if (!scenery.fragment or scenery.breakable or scenery.explosion or scenery.movement != .bounce) return error.InvalidSavedScenery;
                const skin = scenery.gib.?.skin_model;
                if (scenery.gib.?.robotic != (skin.len > 0) or skin.len >= 64 or (skin.len > 0 and (!std.mem.startsWith(u8, skin, "models/") or std.mem.indexOf(u8, skin, "..") != null))) return error.InvalidSavedScenery;
            }
            if (scenery.breakable) try require(world, entity, .{ data.Health, data.Hurt });
            if (scenery.broken and (!scenery.breakable or (try world.get(entity, data.Health)).current > 0 or (try world.get(entity, data.Body)).contents != 0)) return error.InvalidSavedScenery;
        }
        if (world.get(entity, data.DwarfAxe) catch null) |axe| {
            try require(world, entity, .{ data.Transform, data.Velocity, data.Body, data.Binding });
            if (axe.owner == 0 or axe.damage <= 0 or axe.damage > 1000000 or axe.stepped_ms < axe.born_ms or (axe.phase == .flying) != (axe.contact_ms == null)) return error.InvalidSavedDwarfAxe;
        }
        if (world.get(entity, data.ActorAttack) catch null) |attack| {
            try require(world, entity, .{ data.Transform, data.Velocity, data.Body, data.Binding });
            if (attack.owner == 0 or attack.stepped_ms < attack.born_ms) return error.InvalidSavedActorAttack;
            switch (attack.attack) {
                .meteor => |meteor| {
                    try require(world, entity, .{data.Random});
                    for ([_]f32{ meteor.damage, meteor.radius, meteor.speed, meteor.glow, meteor.bounce_max, meteor.delta }) |value| if (!std.math.isFinite(value)) return error.InvalidSavedActorAttack;
                    if (meteor.damage < 0 or meteor.damage > 1000000 or meteor.radius < 0 or meteor.radius > 1000000 or meteor.speed < 0 or meteor.speed > 65536 or meteor.next_ms <= attack.stepped_ms or meteor.next_ms > attack.stepped_ms + (if (meteor.phase == .impact) @as(i64, 500) else 100) or meteor.glow <= 0 or meteor.glow > 3 or meteor.bounces > 6 or meteor.bounce_max < 0 or meteor.bounce_max > 5) return error.InvalidSavedActorAttack;
                    for (meteor.scale) |axis| if (!std.math.isFinite(axis) or axis <= 0 or axis > 2) return error.InvalidSavedActorAttack;
                    for (meteor.spin ++ meteor.normal) |axis| if (!std.math.isFinite(axis) or @abs(axis) > 360) return error.InvalidSavedActorAttack;
                    if (meteor.phase == .fragment and meteor.damage != 0) return error.InvalidSavedActorAttack;
                },
                .npc_wisp => |wisp| {
                    try require(world, entity, .{ data.Random, data.Health, data.Hurt });
                    if (wisp.target == 0 or wisp.phase >= 12 or !std.math.isFinite(wisp.personality) or @abs(wisp.personality) > 1 or !std.math.isFinite(wisp.alpha) or wisp.alpha <= 0 or wisp.alpha > 1 or !std.math.isFinite(wisp.sprite_scale) or wisp.sprite_scale < 1 or wisp.sprite_scale > 1.5 or wisp.next_ms <= attack.stepped_ms or wisp.next_ms > attack.stepped_ms + 100) return error.InvalidSavedActorAttack;
                    for (wisp.scale) |axis| if (!std.math.isFinite(axis) or axis <= 0 or axis > 4) return error.InvalidSavedActorAttack;
                    for (wisp.forward) |axis| if (!std.math.isFinite(axis) or @abs(axis) > 1.01) return error.InvalidSavedActorAttack;
                },
                .wyndrax_zap => |zap| {
                    if (zap.target == 0 or zap.emitted > 4 or zap.emitted % 2 != 0 or attack.stepped_ms > attack.born_ms + 500) return error.InvalidSavedActorAttack;
                    for (zap.destination) |axis| if (!std.math.isFinite(axis)) return error.InvalidSavedActorAttack;
                },
                .wyndrax_bolt => |bolt| {
                    if (bolt.parent == 0 or bolt.until_ms < attack.born_ms or bolt.until_ms > attack.born_ms + 750 or bolt.next_ms <= attack.stepped_ms or bolt.flare_scale <= 0 or bolt.flare_scale > 5) return error.InvalidSavedActorAttack;
                    const parent = world.find(bolt.parent) orelse return error.InvalidSavedActorAttack;
                    if (bolt.kind == .charge) {
                        try require(world, parent, .{data.Actor});
                        if (bolt.parent != attack.owner) return error.InvalidSavedActorAttack;
                    } else {
                        const source = world.get(parent, data.ActorAttack) catch return error.InvalidSavedActorAttack;
                        if (source.owner != attack.owner or (if (bolt.kind == .zap) source.attack != .wyndrax_zap else source.attack != .npc_wisp)) return error.InvalidSavedActorAttack;
                    }
                    if (bolt.kind != .scenery and bolt.target == 0) return error.InvalidSavedActorAttack;
                    for (bolt.destination ++ bolt.contact ++ bolt.color) |axis| if (!std.math.isFinite(axis)) return error.InvalidSavedActorAttack;
                    if (bolt.flare) |point| for (point) |axis| if (!std.math.isFinite(axis)) return error.InvalidSavedActorAttack;
                },
                .psyclaw_sphere => |sphere| {
                    if (sphere.damage <= 0 or sphere.damage > 1000000 or sphere.scale < 0.5 or sphere.scale > 4.5 or sphere.multiplier < 0.9 or sphere.multiplier > 1.45 or sphere.color < -8 or sphere.color > 33 or sphere.color_direction < -8 or sphere.color_direction > 8 or sphere.next_ms <= attack.stepped_ms or sphere.next_ms > attack.stepped_ms + 100 or attack.stepped_ms > attack.born_ms + 8000) return error.InvalidSavedActorAttack;
                },
                .gunner_burst => |burst| {
                    if (burst.next_ms <= attack.stepped_ms or burst.tuning.damage < 0 or burst.tuning.damage > 1000000 or burst.tuning.random_damage < 0 or burst.tuning.random_damage > 1000000 or burst.tuning.range <= 0 or burst.tuning.range > 65536) return error.InvalidSavedActorAttack;
                    for (burst.tuning.offset) |axis| if (!std.math.isFinite(axis) or @abs(axis) > 1024) return error.InvalidSavedActorAttack;
                    for (burst.tuning.spread) |axis| if (!std.math.isFinite(axis) or axis < 0 or axis > 8192) return error.InvalidSavedActorAttack;
                    if ((burst.kind == .commando or burst.kind == .chaingang) and burst.shots >= 5) return error.InvalidSavedActorAttack;
                    if (burst.next_ms - attack.stepped_ms > (if (burst.kind == .shotgun) @as(i64, 200) else @import("actor_catalog").gunners.burst_tick_ms)) return error.InvalidSavedActorAttack;
                },
                .sludge_glob => |glob| {
                    if (glob.damage <= 0 or glob.damage > 1000000 or glob.contacts > 1 or attack.stepped_ms > attack.born_ms + 3000) return error.InvalidSavedActorAttack;
                    for (glob.spin) |axis| if (!std.math.isFinite(axis) or @abs(axis) > 360) return error.InvalidSavedActorAttack;
                },
                .prisoner_rock => |rock| {
                    if (rock.damage <= 0 or rock.damage > 1000000 or attack.stepped_ms > attack.born_ms + 3000) return error.InvalidSavedActorAttack;
                },
                .shaft => |shaft| {
                    if (shaft.damage <= 0 or shaft.damage > 1000000 or (shaft.phase == .flying) != (shaft.contact_ms == null)) return error.InvalidSavedActorAttack;
                    const expiry = if (shaft.contact_ms) |at| at + 5000 else attack.born_ms + @import("actor_catalog").shafts.flightTime(shaft.kind);
                    if (attack.stepped_ms > expiry) return error.InvalidSavedActorAttack;
                    if (shaft.contact_ms) |at| if (at < attack.born_ms or at > attack.stepped_ms or @import("actor_catalog").shafts.magic(shaft.kind)) return error.InvalidSavedActorAttack;
                },
                .rotworm_spit => |spit| {
                    if (spit.damage <= 0 or spit.damage > 1000000 or attack.stepped_ms > attack.born_ms + 5000) return error.InvalidSavedActorAttack;
                },
                .rocket => |rocket| {
                    if (rocket.damage <= 0 or rocket.damage > 1000000 or rocket.speed <= 0 or rocket.speed > 65536 or rocket.divisor == 0 or rocket.frame > 2 or attack.stepped_ms > attack.born_ms + @import("actor_catalog").missiles.lifetime(rocket.kind) or rocket.next_ms <= attack.stepped_ms or rocket.next_ms > attack.stepped_ms + (if (rocket.kind == .battleboar) @as(i64, 5000) else 100)) return error.InvalidSavedActorAttack;
                },
                .fireball => |fire| {
                    if (fire.damage <= 0 or fire.damage > 1000000 or attack.stepped_ms > attack.born_ms + 5000 or fire.drift_ms <= attack.stepped_ms or fire.drift_ms > attack.stepped_ms + 100) return error.InvalidSavedActorAttack;
                },
                .knight_zap => |zap| {
                    if (zap.target == 0 or zap.emitted > 2 or attack.stepped_ms > attack.born_ms + 500) return error.InvalidSavedActorAttack;
                    for (zap.bolts, 0..) |maybe, i| if (maybe) |bolt| {
                        if (i >= zap.emitted or bolt.born_ms != attack.born_ms + @as(i64, @intCast(i + 1)) * 100 or bolt.next_ms <= bolt.born_ms or bolt.next_ms > bolt.born_ms + 400) return error.InvalidSavedActorAttack;
                    };
                },
                .knight_punch => {},
            }
        }
        if (world.get(entity, data.ActorLaser) catch null) |laser| {
            try require(world, entity, .{ data.Transform, data.Velocity, data.Body, data.Binding });
            if (laser.owner == 0 or laser.damage < 0 or laser.damage > 1000000 or laser.stepped_ms < laser.born_ms or laser.stepped_ms > laser.born_ms + (if (laser.kind == .death) @as(i64, 3000) else 10000)) return error.InvalidSavedActorLaser;
            if (laser.contact_ms) |at| if (at < laser.born_ms) return error.InvalidSavedActorLaser;
        }
        if (world.get(entity, data.CryoSpray) catch null) |spray| {
            try require(world, entity, .{ data.Transform, data.Velocity, data.Body, data.Binding });
            if (spray.owner == 0 or spray.damage < 0 or spray.damage > 1000000 or spray.stepped_ms < spray.born_ms or spray.stepped_ms > spray.born_ms + 800) return error.InvalidSavedCryoSpray;
        }
        if (world.get(entity, data.FrogSpit) catch null) |spit| {
            try require(world, entity, .{ data.Transform, data.Velocity, data.Body, data.Binding, data.Lifetime });
            if (spit.owner == 0 or spit.damage <= 0 or spit.damage > 1000000 or spit.stepped_ms < spit.born_ms) return error.InvalidSavedFrogSpit;
        }
        if (world.get(entity, data.Cinematic) catch null) |playback| {
            if (!validName(playback.name) or (playback.active and playback.finished)) return error.InvalidSavedCinematic;
            try require(world, entity, .{data.MapObject});
        }
        if (world.get(entity, data.Performer) catch null) |performer| {
            try require(world, entity, .{ data.Binding, data.Body });
            if (performer.count > performer.queue.len or performer.unique.len == 0 or performer.unique.len > 32 or performer.walk_speed < 0 or performer.walk_speed > 2000 or performer.run_speed < 0 or performer.run_speed > 2000 or performer.yaw_speed < 0 or performer.yaw_speed > 360) return error.InvalidSavedPerformer;
            inline for (.{ "animation", "idle", "movement" }) |field| {
                const sequence = @field(performer, field);
                if (sequence.last < sequence.first or sequence.fps == 0 or sequence.fps > 240) return error.InvalidSavedPerformerAnimation;
            }
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
            const unarmed_companion = (world.get(entity, data.Companion) catch null) != null and weapons.weapon == 0 and weapons.dk3Inventory == 0;
            if ((!unarmed_companion and weapons.weapon < 1) or weapons.weapon > 28 or weapons.weaponstate < 0 or weapons.weaponstate > 3 or weapons.dk3GlockClip < 0 or weapons.dk3GlockClip > 10 or weapons.dk3SwordExperience < 0) return error.InvalidSavedWeapons;
            for (weapons.ammo) |amount| if (amount < 0 or amount > 1000000) return error.InvalidSavedWeapons;
            if (weapons.last_fire_ms) |at| if (at > snapshot.header.at_ms + 200) return error.InvalidSavedWeapons;
        }
        if (world.get(entity, data.Actor) catch null) |actor| {
            if (actor.definition >= @import("actor_catalog").entries.len or actor.guard.pose >= 3 or actor.guard.rounds > 8 or actor.cambot.wave >= 12 or actor.cambot.back_direction < -1 or actor.cambot.back_direction > 1) return error.InvalidSavedActor;
            const gun = actor.rockgat;
            if (gun.height > 1024 or gun.fire_ms < 10 or gun.fire_ms > 3600000 or gun.range <= 0 or gun.range > 65536 or gun.damage < 0 or gun.damage > 1000000 or gun.random_damage < 0 or gun.random_damage > 1000000) return error.InvalidSavedRockgat;
            for (gun.bursts) |burst| if (burst) |shot| {
                if (shot.remaining == 0 or shot.remaining > 5) return error.InvalidSavedRockgatBurst;
            };
            try require(world, entity, .{ data.Velocity, data.Body, data.Health, data.Hurt, data.Binding, data.MapObject });
            if (actor.doombat.bob > 5 or !std.math.isFinite(actor.doombat.speed) or actor.doombat.speed < 0) return error.InvalidSavedActor;
            for (actor.griffon.destination ++ actor.griffon.previous) |coordinate| if (!std.math.isFinite(coordinate) or @abs(coordinate) > 1048576) return error.InvalidSavedActor;
            for (actor.harpy.destination) |coordinate| if (!std.math.isFinite(coordinate) or @abs(coordinate) > 1048576) return error.InvalidSavedActor;
            for (actor.dragon.breath_direction) |coordinate| if (!std.math.isFinite(coordinate) or @abs(coordinate) > 1.001) return error.InvalidSavedActor;
            for (actor.wyndrax.destination ++ actor.wyndrax.start_position) |axis| if (!std.math.isFinite(axis)) return error.InvalidSavedActor;
            if (!std.math.isFinite(actor.buboid.alpha) or actor.buboid.alpha < 0 or actor.buboid.alpha > 1) return error.InvalidSavedActor;
            if (actor.chaingang.strafe > 5 or actor.chaingang.burst > 22) return error.InvalidSavedActor;
            for (actor.chaingang.destination ++ actor.chaingang.start_position) |coordinate| if (!std.math.isFinite(coordinate) or @abs(coordinate) > 1048576) return error.InvalidSavedActor;
            if (actor.deathsphere.bob > 11 or actor.deathsphere.boost_frame < -1 or actor.deathsphere.boost_frame > 65535) return error.InvalidSavedActor;
            for (actor.deathsphere.destination) |coordinate| if (!std.math.isFinite(coordinate) or @abs(coordinate) > 1048576) return error.InvalidSavedActor;
            if (actor.gibbed and ((try world.get(entity, data.Health)).current > 0 or (try world.get(entity, data.Body)).contents != 0 or actor.mode != .dead)) return error.InvalidSavedActor;
            if (!std.math.isFinite(actor.sludge.ammo) or @abs(actor.sludge.ammo) > 1000000) return error.InvalidSavedActor;
            if (@import("actor_catalog").find((try world.get(entity, data.MapObject)).classname) != actor.definition) return error.InvalidSavedActorClass;
            if (actor.lycanthir.phase != .living and (@import("actor_catalog").entries[actor.definition].kind != .lycanthir or actor.lycanthir.wake_ms < actor.lycanthir.started_ms and actor.lycanthir.phase == .collapsed)) return error.InvalidSavedResurrection;
        }
        if (world.get(entity, data.Companion) catch null) |companion| {
            try require(world, entity, .{ data.Actor, data.Health, data.Weapons, data.Character, data.Keys, data.Ailments });
            const kind = @import("actor_catalog").entries[(try world.get(entity, data.Actor)).definition];
            if (kind.kind != .companion or companion.carrying != std.mem.eql(u8, kind.classname, "mikikofly") or (companion.identity == .mikiko) != std.mem.eql(u8, kind.classname, "mikiko")) return error.InvalidSavedCompanion;
            if (companion.owner != 0) {
                const owner = world.find(companion.owner) orelse return error.InvalidSavedCompanionOwner;
                try require(world, owner, .{data.Player});
            }
            if (companion.animation_until != null and (companion.authored == .none or (try world.get(entity, data.Actor)).scripted_pose == null)) return error.InvalidSavedCompanionAction;
        }
        if (world.get(entity, data.Projectile) catch null) |projectile| {
            if (projectile.lifetime_ms < 0 or projectile.lifetime_ms > 3600000 or projectile.speed < 0 or projectile.speed > 100000) return error.InvalidSavedProjectile;
            const flight = @import("weapon_catalog").flightState(projectile.weapon) catch return error.InvalidSavedProjectile;
            if (std.meta.activeTag(projectile.flight) != std.meta.activeTag(flight) or projectile.damage < 0 or projectile.damage > 1000000) return error.InvalidSavedProjectile;
            try require(world, entity, .{ data.Binding, data.Velocity });
            if (flight != .ion) try require(world, entity, .{data.Lifetime});
            if (projectile.flight == .shockwave and (projectile.flight.shockwave.rings > 6 or projectile.flight.shockwave.next_ms < 0)) return error.InvalidSavedProjectile;
            if (projectile.flight == .trident) {
                const tip = projectile.flight.trident;
                if (tip.next_ms < 0 or tip.steering_speed < 0 or tip.steering_speed > 100000) return error.InvalidSavedProjectile;
                for ([_]u32{ tip.leader, tip.left, tip.right }) |id| if (id != 0) {
                    if (id == try world.persistentId(entity)) return error.InvalidSavedProjectile;
                    if (world.find(id)) |related| {
                        const peer = world.get(related, data.Projectile) catch return error.InvalidSavedProjectile;
                        if (peer.flight != .trident or peer.owner != projectile.owner) return error.InvalidSavedProjectile;
                    }
                };
            }
            if (projectile.flight == .ballista) {
                const bolt = projectile.flight.ballista;
                if (bolt.next_ms < 0 or bolt.release_ms < 0 or bolt.release_ms > 3602000) return error.InvalidSavedProjectile;
                if (bolt.victim) |id| {
                    const victim = world.find(id) orelse return error.InvalidSavedProjectile;
                    try require(world, victim, .{ data.Body, data.Velocity, data.Health });
                    if ((try world.get(victim, data.Body)).motion_owner != try world.persistentId(entity)) return error.InvalidSavedProjectile;
                }
            }
            if (projectile.flight == .discus) {
                const disc = projectile.flight.discus;
                if (disc.next_ms < 0 or disc.drop_ms < 0 or disc.clear > 3 or disc.base_speed <= 0 or disc.base_speed > 100000 or disc.speed < 0 or disc.speed > 100000 or (disc.dropped and !disc.pickup_only)) return error.InvalidSavedProjectile;
                try require(world, entity, .{data.Random});
                if (disc.target) |id| if (world.find(id)) |target| try require(world, target, .{data.Health});
            }
            if (projectile.flight == .sunflare) {
                const flame = projectile.flight.sunflare;
                if (flame.next_ms < 0 or flame.burn_ms < 0 or flame.flames > 9 or ((flame.phase == .burning or flame.phase == .cooling) and flame.flames < 5)) return error.InvalidSavedProjectile;
                try require(world, entity, .{data.Random});
            }
            if (projectile.flight == .stavros) {
                const meteor = projectile.flight.stavros;
                if (meteor.next_ms < 0 or meteor.radius <= 0 or meteor.radius > 8192 or meteor.maximum_speed <= 0 or meteor.maximum_speed > 100000) return error.InvalidSavedProjectile;
                for (meteor.scale) |axis| if (axis <= 0 or axis > 2) return error.InvalidSavedProjectile;
                if (!meteor.fragment) try require(world, entity, .{data.Random});
            }
            if (projectile.flight == .wyndrax) {
                const wisp = projectile.flight.wyndrax;
                if (wisp.next_ms < 0 or wisp.sound_ms < 0 or wisp.sine_ms < 0 or wisp.sine >= 12 or wisp.personality < 0 or wisp.personality > 1 or wisp.alpha <= 0 or wisp.alpha > 1) return error.InvalidSavedProjectile;
                for (wisp.scale) |axis| if (axis <= 0 or axis > 4) return error.InvalidSavedProjectile;
                try require(world, entity, .{data.Random});
                if (wisp.enemy) |id| if (world.find(id)) |target| try require(world, target, .{ data.Health, data.Body, data.Binding });
                for (wisp.targets, 0..) |id, index| if (id != 0) {
                    if (id == projectile.owner or std.mem.indexOfScalar(u32, wisp.targets[0..index], id) != null) return error.InvalidSavedProjectile;
                    if (world.find(id)) |target| try require(world, target, .{ data.Health, data.Binding });
                };
            }
            if (projectile.flight == .metamaser) {
                const cube = projectile.flight.metamaser;
                if (cube.next_ms < 0 or cube.arm_ms < 0 or cube.beep_ms < 0 or cube.pause_ms < 0 or cube.burst_ms < 0 or cube.end_ms < 0 or cube.end_ms > 3605000 or cube.charges < 0 or cube.charges > 120 or cube.bursts > 21 or cube.range <= 0 or cube.range > 8192) return error.InvalidSavedProjectile;
                try require(world, entity, .{ data.Random, data.Body, data.Health, data.Hurt });
                for (cube.targets, 0..) |track, i| if (track.target != 0) {
                    if (track.until_ms < 0) return error.InvalidSavedProjectile;
                    for (cube.targets[0..i]) |previous| if (previous.target == track.target) return error.InvalidSavedProjectile;
                    if (world.find(track.target)) |target| try require(world, target, .{ data.Health, data.Binding });
                };
                for (cube.acquired, 0..) |track, i| if (track.target != 0) {
                    if (track.until_ms < 0 or track.damage_ms < 0 or track.sound_ms < 0) return error.InvalidSavedProjectile;
                    for (cube.acquired[0..i]) |previous| if (previous.target == track.target) return error.InvalidSavedProjectile;
                    var retained = false;
                    for (cube.targets) |target| if (target.target == track.target) {
                        retained = true;
                    };
                    if (!retained) return error.InvalidSavedProjectile;
                };
            }
        }
        if (world.get(entity, data.Melee) catch null) |melee| {
            const plan = melee.plan() catch return error.InvalidSavedMelee;
            if (melee.next_hit >= plan.hits or melee.damage < 0 or melee.damage > 1000000 or melee.experience < 0 or melee.timing_factor < 1 or melee.timing_factor > 3) return error.InvalidSavedMelee;
            const owner = world.find(melee.owner) orelse return error.InvalidSavedMeleeOwner;
            try require(world, owner, .{ data.Player, data.Weapons, data.Binding, data.Health });
            if ((world.get(entity, data.Binding) catch null) != null) return error.InvalidSavedMelee;
        }
        if (world.get(entity, data.WeaponLaunch) catch null) |launch| {
            const class = @import("weapon_catalog").find(launch.weapon) orelse return error.InvalidSavedLaunch;
            const policy = @import("weapon_catalog").combatFor(launch.weapon, launch.sequence);
            if ((policy != .projectile and policy != .shockwave and policy != .ballista and policy != .discus and policy != .sunflare and policy != .wyndrax and policy != .metamaser) or class.spec.projectile.action_delay_ms == 0 or (world.get(entity, data.Binding) catch null) != null) return error.InvalidSavedLaunch;
            const owner = world.find(launch.owner) orelse return error.InvalidSavedLaunch;
            try require(world, owner, .{ data.Player, data.Weapons, data.Health, data.Binding });
        }
        if (world.get(entity, data.Charge) catch null) |charge| {
            const lifetime = std.math.sub(i64, charge.expires_ms, charge.born_ms) catch return error.InvalidSavedCharge;
            if (charge.damage < 0 or charge.damage > 1000000 or lifetime < 0 or lifetime > 3600000) return error.InvalidSavedCharge;
            try require(world, entity, .{ data.Body, data.Binding, data.Velocity, data.Health, data.Random });
            if ((world.get(entity, data.Projectile) catch null) != null) return error.InvalidSavedCharge;
        }
        if (world.get(entity, data.Hammer) catch null) |hammer| {
            if (hammer.damage < 0 or hammer.damage > 1000000 or hammer.range <= 0 or hammer.range > 8192 or hammer.charge_ms < 0 or hammer.charge_ms > 1800) return error.InvalidSavedHammer;
            try require(world, entity, .{data.Random});
            if (hammer.quake_until_ms == null) {
                if ((world.get(entity, data.Binding) catch null) != null) return error.InvalidSavedHammer;
                const owner = world.find(hammer.owner) orelse return error.InvalidSavedHammer;
                try require(world, owner, .{ data.Player, data.Weapons, data.Health, data.Binding });
            } else if ((try world.get(entity, data.Binding)).model != 0) return error.InvalidSavedHammer;
        }
        if (world.get(entity, data.Shockwave) catch null) |wave| {
            if (wave.damage < 0 or wave.damage > 1000000 or wave.count < 1 or wave.count > wave.rings.len or wave.next_ms < wave.born_ms) return error.InvalidSavedWave;
            try require(world, entity, .{ data.Binding, data.Random });
            if ((try world.get(entity, data.Binding)).model != 0) return error.InvalidSavedWave;
            for (wave.rings[0..wave.count]) |ring| if (ring.start_ms < wave.born_ms or ring.start_ms > snapshot.header.at_ms + 200 or ring.inner < -20 or ring.inner > 350 or ring.outer < 0 or ring.outer > 350) return error.InvalidSavedWave;
        }
        if (world.get(entity, data.Nova) catch null) |beam| {
            if (beam.lifetime_ms <= 0 or beam.lifetime_ms > 3600000 or beam.remaining_damage < 0 or beam.remaining_damage > 1000000 or beam.boost > 5 or beam.ammo_cost < 1 or beam.ammo_cost > 32767 or beam.alpha < 0 or beam.alpha > 1) return error.InvalidSavedNova;
            const duration = std.math.sub(i64, beam.expires_ms, beam.born_ms) catch return error.InvalidSavedNova;
            if (duration != @as(i64, beam.lifetime_ms) + 200 or beam.next_ms < beam.born_ms or ((beam.phase == .closing or beam.phase == .finished) != (beam.end_ms != null))) return error.InvalidSavedNova;
            const owner = world.find(beam.owner) orelse return error.InvalidSavedNova;
            try require(world, owner, .{ data.Player, data.Weapons, data.Health, data.Binding });
            if ((try world.get(entity, data.Binding)).model != 0) return error.InvalidSavedNova;
        }
        if (world.get(entity, data.Flashlight) catch null) |light| {
            if (light.strength < 0 or light.strength > 1 or (try world.get(entity, data.Binding)).model != 0) return error.InvalidSavedLight;
            const owner = world.find(light.owner) orelse return error.InvalidSavedLight;
            try require(world, owner, .{ data.Player, data.Weapons, data.Health, data.Binding });
        }
        if (world.get(entity, data.Nightmare) catch null) |ritual| {
            if (ritual.count > @import("weapon_catalog").nightmare.maximum_targets or ritual.cursor > ritual.count or ritual.damage < 0 or ritual.damage > 1000000 or ritual.range <= 0 or ritual.range > 8192 or ritual.previous_view_height < -24 or ritual.previous_view_height > 64 or ritual.next_ms < ritual.phase_ms) return error.InvalidSavedNightmare;
            try require(world, entity, .{data.Binding});
            if ((try world.get(entity, data.Binding)).model != 0) return error.InvalidSavedNightmare;
            const owner = world.find(ritual.owner) orelse return error.InvalidSavedNightmare;
            try require(world, owner, .{ data.Player, data.Weapons, data.Binding, data.Health });
            for (ritual.targets[0..ritual.count], 0..) |id, index| {
                if (id == 0 or std.mem.indexOfScalar(u32, ritual.targets[0..index], id) != null) return error.InvalidSavedNightmare;
                if (world.find(id)) |target| try require(world, target, .{ data.Health, data.Body, data.Binding });
            }
            if ((ritual.phase == .appearing or ritual.phase == .reaping) != (ritual.victim != null)) return error.InvalidSavedNightmare;
            if (ritual.victim) |id| {
                if (ritual.cursor == 0 or ritual.targets[ritual.cursor - 1] != id) return error.InvalidSavedNightmare;
                const target = world.find(id) orelse return error.InvalidSavedNightmare;
                try require(world, target, .{ data.Body, data.Velocity, data.Health, data.Binding });
                if ((try world.get(target, data.Body)).motion_owner != try world.persistentId(entity)) return error.InvalidSavedNightmare;
                if (world.get(target, data.Player) catch null) |victim_player| if (victim_player.mode != .frozen and victim_player.mode != .dead) return error.InvalidSavedNightmare;
            }
        }
        inline for (.{ data.MetaRing, data.MetaLaser }) |T| if (world.get(entity, T) catch null) |effect| {
            if (effect.damage < 0 or effect.damage > 1000000 or effect.cube == 0) return error.InvalidSavedMetaEffect;
            try require(world, entity, .{data.Binding});
            if ((try world.get(entity, data.Binding)).model != 0) return error.InvalidSavedMetaEffect;
            if (T == data.MetaRing) {
                if (effect.next_ms < effect.born_ms) return error.InvalidSavedMetaEffect;
            } else {
                try require(world, entity, .{data.Random});
                // Final burst lasers may expire before their staggered first shot.
                if (effect.next_ms -| effect.expires_ms > 400) return error.InvalidSavedMetaEffect;
            }
            if (world.find(effect.cube)) |cube| {
                const projectile = world.get(cube, data.Projectile) catch return error.InvalidSavedMetaEffect;
                if (projectile.flight != .metamaser or projectile.owner != effect.owner) return error.InvalidSavedMetaEffect;
            }
        };
        if (world.get(entity, data.Zeus) catch null) |chain| {
            if (chain.count > @import("weapon_catalog").zeus.maximum_targets or chain.active > chain.count or chain.zaps > chain.count or @as(u16, chain.active) + chain.zaps > chain.count or chain.damage < 0 or chain.damage > 1000000 or chain.range <= 0 or chain.range > 8192 or chain.ammo_cost <= 0 or chain.ammo_cost > 32767) return error.InvalidSavedZeus;
            if ((chain.phase == .finished) != (chain.closed_ms != null) or (chain.phase == .pending and chain.count != 0) or (chain.phase == .finished and chain.active != 0)) return error.InvalidSavedZeus;
            for (chain.targets[0..chain.count], 0..) |id, i| {
                if (id == 0 or id == chain.owner) return error.InvalidSavedZeus;
                for (chain.targets[0..i]) |previous| if (previous == id) return error.InvalidSavedZeus;
            }
            const owner = world.find(chain.owner) orelse return error.InvalidSavedZeus;
            try require(world, owner, .{ data.Player, data.Weapons, data.Health, data.Binding });
            try require(world, entity, .{ data.Random, data.Binding });
            if ((try world.get(entity, data.Binding)).model != 0) return error.InvalidSavedZeus;
        }
        if (world.get(entity, data.ZeusBolt) catch null) |bolt| {
            const parent = world.find(bolt.chain) orelse return error.InvalidSavedZeusBolt;
            const chain = world.get(parent, data.Zeus) catch return error.InvalidSavedZeusBolt;
            // Check bounds before invoking the class's bounded target-set operations.
            if (chain.count > @import("weapon_catalog").zeus.maximum_targets or chain.owner != bolt.owner or !chain.contains(bolt.target)) return error.InvalidSavedZeusBolt;
            const source = world.find(bolt.source) orelse return error.InvalidSavedZeusBolt;
            const target = world.find(bolt.target) orelse return error.InvalidSavedZeusBolt;
            try require(world, source, .{ data.Health, data.Binding });
            try require(world, target, .{ data.Health, data.Binding });
            try require(world, entity, .{data.Binding});
            if (bolt.next_ms < bolt.born_ms or (try world.get(entity, data.Binding)).model != 0) return error.InvalidSavedZeusBolt;
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
        if (world.get(entity, data.Ailments) catch null) |ailments| {
            try require(world, entity, .{data.Health});
            if (ailments.warp) |warp| {
                try require(world, entity, .{data.Player});
                if (warp.source == 0 or warp.next_ms > warp.until_ms or warp.next_ms < warp.until_ms - 7900) return error.InvalidSavedAilment;
            }
            if (ailments.freeze_level < 0 or ailments.freeze_level > 1) return error.InvalidSavedAilment;
            if (ailments.poison) |poison| if (poison.damage <= 0 or poison.damage > 1000000 or poison.interval_ms < 100 or poison.interval_ms > 3600000 or poison.weapon > 28 or poison.next_ms > poison.until_ms + poison.interval_ms) return error.InvalidSavedAilment;
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
    var world = data.World.init(allocator, 64);
    defer world.deinit();
    const player = try world.create(7, .{ data.Transform{}, data.Velocity{}, data.Player{}, data.Body{}, data.Binding{ .slot = 0 }, data.Health{}, data.Hurt{}, data.Weapons{ .weapon = 1 }, data.Character{ .boost_until = .{ 0, 1300, 0, 0, 0 } }, data.Ailments{}, data.Keys{} });
    var random: data.Random = .{ .state = 92817 };
    _ = random.next();
    try world.put(player, random);
    (try world.get(player, data.Weapons)).last_fire_ms = 700;
    _ = (try world.get(player, data.Ailments)).apply(.{ .poison = .{ .damage = 3, .duration_ms = 5000 } }, 7, 11, 700);
    _ = try world.create(43, .{ data.Transform{}, data.ImpactEvent{ .weapon = 4, .kind = .world, .normal = .{ 0, 0, 1 } }, data.Lifetime{ .expires_ms = 1200 } });
    _ = try world.create(44, .{ data.Transform{}, data.Binding{ .slot = 65 }, data.Velocity{}, data.Projectile{ .owner = 7, .weapon = 5, .damage = 50, .born_ms = 900, .stepped_ms = 1000, .flight = .{ .sidewinder = .{ .accelerated = true } } }, data.Lifetime{ .expires_ms = 5000 } });
    _ = try world.create(45, .{ data.Transform{}, data.Melee{ .owner = 7, .weapon = 8, .sequence = 9, .experience = 0, .damage = 40, .started_ms = 700, .next_hit = 1 } });
    _ = try world.create(46, .{ data.Transform{}, data.WeaponLaunch{ .owner = 7, .weapon = 11, .sequence = 0, .charge = 0, .execute_ms = 1100 } });
    _ = try world.create(47, .{ data.Transform{}, data.Binding{ .slot = 66 }, data.Velocity{}, data.Body{}, data.Health{ .current = 5, .maximum = 5 }, data.Random{ .state = 77 }, data.Charge{ .owner = 7, .damage = 100, .born_ms = 800, .stepped_ms = 1000, .next_ms = 1800, .expires_ms = 20000, .detonate_ms = 1200, .beep_ms = 900, .attached = true } });
    _ = try world.create(48, .{ data.Transform{}, data.Hammer{ .owner = 7, .damage = 100, .range = 128, .charge_ms = 1800, .next_ms = 1100 }, data.Random{ .state = 78 } });
    _ = try world.create(49, .{ data.Transform{}, data.Binding{ .slot = 67 }, data.Hammer{ .owner = 7, .damage = 100, .range = 128, .charge_ms = 1800, .next_ms = 1100, .quake_until_ms = 6100 }, data.Random{ .state = 79 } });
    var wave = data.Shockwave.init(7, 150, 400);
    _ = wave.advance(900);
    _ = try world.create(50, .{ data.Transform{}, data.Binding{ .slot = 68 }, wave, data.Random{ .state = 80 } });
    _ = try world.create(51, .{ data.Transform{}, data.WeaponLaunch{ .owner = 7, .weapon = 6, .sequence = 0, .charge = 0, .execute_ms = 1600 } });
    _ = try world.create(52, .{ data.Transform{}, data.Binding{ .slot = 69 }, data.Velocity{}, data.Projectile{ .owner = 7, .weapon = 6, .damage = 150, .born_ms = 900, .stepped_ms = 1000, .flight = .{ .shockwave = .{ .next_ms = 200, .last_ring = .{ 100, 200, 300 }, .rings = 1, .touched_water = true } } }, data.Lifetime{ .expires_ms = 5000 } });
    _ = try world.create(53, .{ data.Transform{}, data.Binding{ .slot = 70 }, data.Velocity{}, data.Projectile{ .owner = 7, .weapon = 13, .damage = 30, .born_ms = 900, .stepped_ms = 1000, .flight = .{ .trident = .{ .left = 54, .next_ms = 200 } } }, data.Lifetime{ .expires_ms = 5000 } });
    _ = try world.create(54, .{ data.Transform{}, data.Binding{ .slot = 71 }, data.Velocity{}, data.Projectile{ .owner = 7, .weapon = 13, .damage = 30, .born_ms = 900, .stepped_ms = 1000, .flight = .{ .trident = .{ .kind = .left, .leader = 53, .reversed = true } } }, data.Lifetime{ .expires_ms = 5000 } });
    _ = try world.create(55, .{ data.Transform{}, data.Binding{ .slot = 72 }, data.Velocity{}, data.Projectile{ .owner = 7, .weapon = 18, .damage = 80, .born_ms = 900, .stepped_ms = 1000, .stuck = true, .flight = .{ .ballista = .{ .victim = 7, .last_victim = 7, .release_ms = 2100 } } }, data.Lifetime{ .expires_ms = 3000 } });
    (try world.get(player, data.Body)).motion_owner = 55;
    var nova = data.Nova.init(7, .{ .damage = 250, .ammoCost = 2, .lifetime = 2 }, 0, 500);
    _ = nova.advance(800, 100);
    _ = try world.create(56, .{ data.Transform{}, data.Binding{ .slot = 73 }, nova });
    _ = try world.create(57, .{ data.Transform{}, data.Binding{ .slot = 74 }, data.Flashlight{ .owner = 7, .expires_ms = 1150, .strength = 0.75 } });
    _ = try world.create(58, .{ data.Transform{}, data.Binding{ .slot = 75 }, data.Velocity{}, data.Random{ .state = 17 }, data.Projectile{ .owner = 7, .weapon = 9, .damage = 35, .born_ms = 500, .stepped_ms = 1000, .flight = .{ .discus = .{ .target = 7, .reflected = true, .next_ms = 600, .speed = 750 } } }, data.Lifetime{ .expires_ms = 60500 } });
    _ = try world.create(59, .{ data.Transform{}, data.Binding{ .slot = 76 }, data.Velocity{}, data.Random{ .state = 23 }, data.Projectile{ .owner = 7, .weapon = 10, .damage = 4, .born_ms = 500, .stepped_ms = 1000, .flight = .{ .sunflare = .{ .phase = .burning, .burn_ms = 400, .next_ms = 800, .flames = 7, .floating = true } } }, data.Lifetime{ .expires_ms = 10900 } });
    _ = try world.create(60, .{ data.Transform{}, data.Binding{ .slot = 77 }, data.Velocity{}, data.Random{ .state = 25 }, data.Projectile{ .owner = 7, .weapon = 17, .damage = 100, .born_ms = 900, .stepped_ms = 1000, .flight = .{ .stavros = .{ .next_ms = 200, .scale = @splat(0.3), .maximum_speed = 525 } } }, data.Lifetime{ .expires_ms = 12900 } });
    _ = try world.create(61, .{ data.Transform{}, data.Binding{ .slot = 78 }, data.Velocity{}, data.Projectile{ .owner = 7, .weapon = 17, .damage = 50, .born_ms = 900, .stepped_ms = 1000, .bounces = 1, .flight = .{ .stavros = .{ .fragment = true, .radius = 100, .scale = .{ 0.4, 0.5, 0.6 } } } }, data.Lifetime{ .expires_ms = 6900 } });
    var chain: data.Zeus = .{ .owner = 7, .damage = 300, .range = 1500, .ammo_cost = 1, .ready_ms = 800, .expires_ms = 6300, .phase = .active };
    _ = chain.reserve(47);
    _ = try world.create(62, .{ data.Transform{}, data.Binding{ .slot = 79 }, data.Random{ .state = 26 }, chain });
    _ = try world.create(63, .{ data.Transform{}, data.Binding{ .slot = 80 }, data.ZeusBolt{ .owner = 7, .chain = 62, .source = 7, .target = 47, .born_ms = 800, .next_ms = 1100, .phase = .zapping } });
    _ = try world.create(64, .{ data.Transform{}, data.Binding{ .slot = 81 }, data.Random{ .state = 27 }, data.Zeus{ .owner = 7, .damage = 300, .range = 1500, .ammo_cost = 1, .ready_ms = 1800, .expires_ms = 7300 } });
    _ = try world.create(65, .{ data.Transform{}, data.Binding{ .slot = 82 }, data.Velocity{}, data.Random{ .state = 28 }, data.Projectile{ .owner = 7, .weapon = 19, .damage = 3, .born_ms = 700, .stepped_ms = 1000, .lifetime_ms = 5000, .flight = .{ .wyndrax = .{ .enemy = 47, .targets = .{ 47, 0, 0, 0 }, .next_ms = 400, .sine_ms = 450, .sound_ms = 500, .sine = 4, .personality = 0.75 } } }, data.Lifetime{ .expires_ms = 7800 } });
    _ = try world.create(66, .{ data.Transform{}, data.Binding{ .slot = 83 }, data.Nightmare{ .owner = 7, .damage = 300, .range = 2000, .born_ms = 100, .phase_ms = 700, .next_ms = 4900, .phase = .reaping, .targets = .{ 47, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, .count = 1, .cursor = 1, .victim = 47 } });
    (try world.get(world.find(47).?, data.Body)).motion_owner = 66;
    var cube: @import("weapon_catalog").metamaser.BallisticState = .{ .phase = .tracking, .settled = true, .next_ms = 4000, .end_ms = 19000, .charges = 5 };
    _ = cube.include(7, 3500);
    _ = cube.lock(7, 3800, 0.5);
    _ = try world.create(67, .{ data.Transform{}, data.Binding{ .slot = 84 }, data.Velocity{}, data.Body{}, data.Health{ .current = 300, .maximum = 300 }, data.Hurt{}, data.Random{ .state = 29 }, data.Projectile{ .owner = 7, .weapon = 26, .damage = 40, .born_ms = -3000, .stepped_ms = 1000, .lifetime_ms = 19000, .flight = .{ .metamaser = cube } }, data.Lifetime{ .expires_ms = 16000 } });
    _ = try world.create(68, .{ data.Transform{}, data.Binding{ .slot = 85 }, data.MetaRing{ .owner = 7, .cube = 67, .damage = 40, .born_ms = 900, .next_ms = 1050 } });
    _ = try world.create(69, .{ data.Transform{}, data.Binding{ .slot = 86 }, data.Random{ .state = 30 }, data.MetaLaser{ .owner = 7, .cube = 67, .damage = 40, .next_ms = 1100, .expires_ms = 5900 } });
    _ = try world.create(73, .{ data.Transform{}, data.MapObject{ .classname = "info_aiscript" }, data.Script{ .name = "Skeet1Path", .active = true, .index = 2, .due_ms = 1800, .next_ms = 1050, .revision = 4 } });
    _ = try world.create(76, .{ data.Transform{}, data.MapObject{ .classname = "monster_crox" }, data.Actor{ .definition = @import("actor_catalog").find("monster_crox").?, .crox = .{ .swimming = true, .water = 3, .attacking = true, .pose = 1, .started_ms = 500, .cycle_ms = 1800, .wander_until_ms = 3000, .destination = .{ 10, 20, 30 } } }, data.Body{}, data.Binding{ .slot = 91, .model = 1 }, data.Velocity{}, data.Health{}, data.Hurt{}, data.Random{ .state = 3 } });
    var gun: @import("actor_catalog").rockgat.State = .{ .phase = .scanning, .raised = true, .pose_ms = 700, .next_attack_ms = 1150, .next_sound_ms = 1200 };
    try gun.startBurst(950);
    gun.bursts[0].?.remaining = 3;
    _ = try world.create(77, .{ data.Transform{}, data.MapObject{ .classname = "monster_rockgat" }, data.Actor{ .definition = @import("actor_catalog").find("monster_rockgat").?, .rockgat = gun }, data.Body{}, data.Binding{ .slot = 92, .model = 1 }, data.Velocity{}, data.Health{}, data.Hurt{}, data.Random{ .state = 4 } });
    _ = try world.create(75, .{ data.Transform{}, data.Body{ .mins = @splat(-1), .maxs = @splat(1) }, data.Binding{ .slot = 90, .model = 1 }, data.Velocity{ .linear = .{ 180, 0, 0 } }, data.Lifetime{ .expires_ms = 15500 }, data.ThunderSpray{ .owner = 7, .alternate = true, .born_ms = 500, .stepped_ms = 950, .next_ms = 1000, .phase = 11, .scale = 0.4, .delta = 0.25 } });
    _ = try world.create(74, .{ data.Transform{}, data.MapObject{ .classname = "misc_healthtree" }, data.Body{}, data.Binding{ .slot = 89, .model = 1 }, data.Velocity{}, data.Health{ .current = 100, .maximum = 100 }, data.Random{ .state = 8 }, data.HealthTree{ .fruit = 2, .previous = 3, .ready_ms = 1800, .changed_ms = 800 } });
    _ = try world.create(72, .{ data.Transform{}, data.Body{ .mins = @splat(-3), .maxs = @splat(3) }, data.Binding{ .slot = 88, .model = 1 }, data.Velocity{ .linear = .{ 400, 0, 0 } }, data.Lifetime{ .expires_ms = 5500 }, data.FrogSpit{ .owner = 7, .damage = 7, .born_ms = 500, .stepped_ms = 950 } });
    _ = try world.create(70, .{ data.Transform{}, data.MapObject{ .classname = "worldspawn" }, data.Cinematic{ .name = "intro", .shot = 20, .started_ms = 500, .active = true, .sounds = 2, .queued = .{3} ++ @as([127]u16, @splat(0)) } });
    _ = try world.create(71, .{ data.Transform{}, data.Body{}, data.Binding{ .slot = 87, .model = 1 }, data.Performer{ .unique = "oka1", .classname = "cine_osaka", .model = "models/cinematic/c_osaka_intr.dkm", .animation = .{ .first = 10, .last = 20 }, .animation_ms = 800, .next_ms = 1050, .queue = .{42} ++ @as([127]u16, @splat(0)), .count = 1, .started = true, .due_ms = 1900 } });

    const mover = try world.create(42, .{ data.Transform{}, data.MapObject{ .classname = "func_train", .target = "next" }, data.Train{ .phase = .dwelling, .action = .{ .at_ms = 2000 }, .next_target = "next" } });
    _ = mover;
    world.next_id = 100;
    var bytes: [65536]u8 = undefined;
    const saved = try capture(allocator, &bytes, &world, "e1m3a", 3, .{ .at_ms = 1000, .episode = 1, .player_id = 7, .next_id = 100 });
    var loaded = try decode(allocator, saved);
    defer loaded.deinit(allocator);
    @memset(&bytes, 0);
    try std.testing.expectEqual(@as(u32, 100), loaded.world.next_id);
    try std.testing.expect(loaded.world.find(43) == null);
    try std.testing.expectEqual(random.next(), (try loaded.world.get(loaded.world.find(7).?, data.Random)).next());
    try std.testing.expectEqualStrings("next", (try loaded.world.get(loaded.world.find(42).?, data.Train)).next_target);
    try loaded.rebase(9000);
    const charge = (try loaded.world.get(loaded.world.find(47).?, data.Charge)).*;
    try std.testing.expectEqual(@as(?i64, 9200), charge.detonate_ms);
    try std.testing.expectEqual(@as(?i64, 8900), charge.beep_ms);
    try std.testing.expectEqual(@as(i64, 28000), charge.expires_ms);
    try std.testing.expect(charge.attached);
    try std.testing.expectEqual(@as(i64, 9100), (try loaded.world.get(loaded.world.find(48).?, data.Hammer)).next_ms);
    try std.testing.expectEqual(@as(?i64, 14100), (try loaded.world.get(loaded.world.find(49).?, data.Hammer)).quake_until_ms);
    const saved_wave = (try loaded.world.get(loaded.world.find(50).?, data.Shockwave)).*;
    try std.testing.expectEqual(@as(u8, 2), saved_wave.count);
    try std.testing.expectEqual(@as(i64, 8400), saved_wave.born_ms);
    try std.testing.expectEqual(@as(i64, 8900), saved_wave.rings[1].start_ms);
    try std.testing.expectEqual(@as(i64, 8950), saved_wave.next_ms);
    try std.testing.expectEqual(wave.rings[0].inner, saved_wave.rings[0].inner);
    try std.testing.expectEqual(@as(i64, 9600), (try loaded.world.get(loaded.world.find(51).?, data.WeaponLaunch)).execute_ms);
    try std.testing.expectEqual(@as(i64, 200), (try loaded.world.get(loaded.world.find(52).?, data.Projectile)).flight.shockwave.next_ms);
    try std.testing.expectEqual(@as(u32, 54), (try loaded.world.get(loaded.world.find(53).?, data.Projectile)).flight.trident.left);
    try std.testing.expect((try loaded.world.get(loaded.world.find(54).?, data.Projectile)).flight.trident.reversed);
    try std.testing.expectEqual(@as(i64, 2100), (try loaded.world.get(loaded.world.find(55).?, data.Projectile)).flight.ballista.release_ms);
    try std.testing.expectEqual(@as(?u32, 55), (try loaded.world.get(loaded.world.find(7).?, data.Body)).motion_owner);
    const saved_nova = (try loaded.world.get(loaded.world.find(56).?, data.Nova)).*;
    try std.testing.expectEqual(@as(f32, 200), saved_nova.remaining_damage);
    try std.testing.expectEqual(@as(i64, 8900), saved_nova.next_ms);
    try std.testing.expectEqual(@as(i64, 10700), saved_nova.expires_ms);
    try std.testing.expectEqual(@as(i64, 9150), (try loaded.world.get(loaded.world.find(57).?, data.Flashlight)).expires_ms);
    const saved_disc = (try loaded.world.get(loaded.world.find(58).?, data.Projectile)).*;
    try std.testing.expectEqual(@as(i64, 8500), saved_disc.born_ms);
    try std.testing.expectEqual(@as(i64, 600), saved_disc.flight.discus.next_ms);
    try std.testing.expectEqual(@as(?u32, 7), saved_disc.flight.discus.target);
    const saved_flare = (try loaded.world.get(loaded.world.find(59).?, data.Projectile)).flight.sunflare;
    try std.testing.expect(saved_flare.floating and saved_flare.phase == .burning);
    try std.testing.expectEqual(@as(i64, 800), saved_flare.next_ms);
    try std.testing.expectEqual(@as(i64, 18900), (try loaded.world.get(loaded.world.find(59).?, data.Lifetime)).expires_ms);
    try std.testing.expectEqual(@as(i64, 200), (try loaded.world.get(loaded.world.find(60).?, data.Projectile)).flight.stavros.next_ms);
    const saved_fragment = (try loaded.world.get(loaded.world.find(61).?, data.Projectile)).*;
    try std.testing.expect(saved_fragment.flight.stavros.fragment);
    try std.testing.expectEqual(@as(u8, 1), saved_fragment.bounces);
    try std.testing.expectEqual([3]f32{ 0.4, 0.5, 0.6 }, saved_fragment.flight.stavros.scale);
    const saved_chain = (try loaded.world.get(loaded.world.find(62).?, data.Zeus)).*;
    try std.testing.expect(saved_chain.contains(47));
    try std.testing.expectEqual(@as(u8, 1), saved_chain.active);
    try std.testing.expectEqual(@as(u8, 0), saved_chain.zaps);
    const saved_bolt = (try loaded.world.get(loaded.world.find(63).?, data.ZeusBolt)).*;
    try std.testing.expect(saved_bolt.phase == .zapping);
    try std.testing.expectEqual(@as(i64, 9100), saved_bolt.next_ms);
    try std.testing.expectEqual(@as(u32, 62), saved_bolt.chain);
    try std.testing.expectEqual(@as(i64, 9800), (try loaded.world.get(loaded.world.find(64).?, data.Zeus)).ready_ms);
    const script = (try loaded.world.get(loaded.world.find(73).?, data.Script)).*;
    try std.testing.expectEqual(@as(u16, 2), script.index);
    try std.testing.expectEqual(@as(i64, 9800), script.due_ms);
    try std.testing.expectEqual(@as(i64, 9050), script.next_ms);
    const crox = (try loaded.world.get(loaded.world.find(76).?, data.Actor)).crox;
    try std.testing.expect(crox.swimming and crox.attacking and crox.water == 3 and crox.pose == 1);
    try std.testing.expectEqual(@as(i64, 8500), crox.started_ms);
    try std.testing.expectEqual(@as(i64, 9800), crox.cycle_ms);
    try std.testing.expectEqual(@as(i64, 11000), crox.wander_until_ms);
    try std.testing.expectEqual([3]f32{ 10, 20, 30 }, crox.destination.?);
    const turret = (try loaded.world.get(loaded.world.find(77).?, data.Actor)).rockgat;
    try std.testing.expectEqual(@as(i64, 8960), turret.bursts[0].?.next_ms);
    try std.testing.expectEqual(@as(u3, 3), turret.bursts[0].?.remaining);
    try std.testing.expectEqual(@as(i64, 9150), turret.next_attack_ms);
    try std.testing.expectEqual(@as(i64, 9200), turret.next_sound_ms);
    try std.testing.expectEqual(@as(i64, 8700), turret.pose_ms);
    const spray = (try loaded.world.get(loaded.world.find(75).?, data.ThunderSpray)).*;
    try std.testing.expectEqual(@as(i64, 8500), spray.born_ms);
    try std.testing.expectEqual(@as(i64, 8950), spray.stepped_ms);
    try std.testing.expectEqual(@as(i64, 9000), spray.next_ms);
    try std.testing.expectEqual(@as(u4, 11), spray.phase);
    const tree = (try loaded.world.get(loaded.world.find(74).?, data.HealthTree)).*;
    try std.testing.expectEqual(@as(u3, 2), tree.fruit);
    try std.testing.expectEqual(@as(i64, 9800), tree.ready_ms);
    const spit = (try loaded.world.get(loaded.world.find(72).?, data.FrogSpit)).*;
    try std.testing.expectEqual(@as(i64, 8500), spit.born_ms);
    try std.testing.expectEqual(@as(i64, 8950), spit.stepped_ms);
    try std.testing.expectEqual(@as(f32, 7), spit.damage);
    const saved_cinematic = (try loaded.world.get(loaded.world.find(70).?, data.Cinematic)).*;
    try std.testing.expectEqual(@as(i64, 8500), saved_cinematic.started_ms);
    try std.testing.expectEqual(@as(u16, 20), saved_cinematic.shot);
    try std.testing.expectEqual(@as(u16, 3), saved_cinematic.queued[0]);
    const performer = (try loaded.world.get(loaded.world.find(71).?, data.Performer)).*;
    try std.testing.expectEqual(@as(i64, 8800), performer.animation_ms);
    try std.testing.expectEqual(@as(i64, 9900), performer.due_ms);
    try std.testing.expectEqual(@as(u16, 42), performer.queue[0]);
    const saved_wisp = (try loaded.world.get(loaded.world.find(65).?, data.Projectile)).*;
    try std.testing.expectEqual(@as(i64, 8700), saved_wisp.born_ms);
    try std.testing.expectEqual(@as(i64, 400), saved_wisp.flight.wyndrax.next_ms);
    try std.testing.expectEqual(@as(i64, 450), saved_wisp.flight.wyndrax.sine_ms);
    try std.testing.expectEqual(@as(?u32, 47), saved_wisp.flight.wyndrax.enemy);
    try std.testing.expectEqual([4]u32{ 47, 0, 0, 0 }, saved_wisp.flight.wyndrax.targets);
    const saved_ritual = (try loaded.world.get(loaded.world.find(66).?, data.Nightmare)).*;
    try std.testing.expectEqual(@as(i64, 12900), saved_ritual.next_ms);
    try std.testing.expectEqual(@as(?u32, 47), saved_ritual.victim);
    try std.testing.expectEqual(@as(?u32, 66), (try loaded.world.get(loaded.world.find(47).?, data.Body)).motion_owner);
    const saved_cube = (try loaded.world.get(loaded.world.find(67).?, data.Projectile)).flight.metamaser;
    try std.testing.expectEqual(@as(i64, 4550), saved_cube.acquired[0].until_ms);
    try std.testing.expectEqual(@as(i32, 5), saved_cube.charges);
    try std.testing.expectEqual(@as(i64, 9050), (try loaded.world.get(loaded.world.find(68).?, data.MetaRing)).next_ms);
    try std.testing.expectEqual(@as(i64, 9100), (try loaded.world.get(loaded.world.find(69).?, data.MetaLaser)).next_ms);
    const melee = (try loaded.world.get(loaded.world.find(45).?, data.Melee)).*;
    try std.testing.expectEqual(@as(?i64, 8700), (try loaded.world.get(loaded.world.find(7).?, data.Weapons)).last_fire_ms);
    const poison = (try loaded.world.get(loaded.world.find(7).?, data.Ailments)).poison.?;
    try std.testing.expectEqual(@as(i64, 9100), (try loaded.world.get(loaded.world.find(46).?, data.WeaponLaunch)).execute_ms);
    try std.testing.expectEqual(@as(i64, 9700), poison.next_ms);
    try std.testing.expectEqual(@as(i64, 13700), poison.until_ms);
    try std.testing.expectEqual(@as(u8, 1), melee.next_hit);
    try std.testing.expect(!try melee.due(9347));
    try std.testing.expect(try melee.due(9348));
    try std.testing.expect((try loaded.world.get(loaded.world.find(44).?, data.Projectile)).flight.sidewinder.accelerated);
    try std.testing.expectEqual(@as(i64, 13000), (try loaded.world.get(loaded.world.find(44).?, data.Lifetime)).expires_ms);
    try std.testing.expectEqual(@as(?i64, 10000), (try loaded.world.get(loaded.world.find(42).?, data.Train)).action.at_ms);
    try std.testing.expectEqual(@as(i64, 9300), (try loaded.world.get(loaded.world.find(7).?, data.Character)).boost_until[1]);
    try std.testing.expectEqual(@as(i64, 1300), (try world.get(world.find(7).?, data.Character)).boost_until[1]);
    (try world.get(world.find(47).?, data.Charge)).born_ms = std.math.minInt(i64);
    try std.testing.expectError(error.InvalidSnapshotNumber, capture(allocator, &bytes, &world, "e1m3a", 3, .{ .at_ms = 1000, .episode = 1, .player_id = 7, .next_id = 100 }));
    (try world.get(world.find(47).?, data.Charge)).born_ms = 800;
    (try world.get(world.find(47).?, data.Charge)).expires_ms = 3600801;
    const bad_lifetime = try capture(allocator, &bytes, &world, "e1m3a", 3, .{ .at_ms = 1000, .episode = 1, .player_id = 7, .next_id = 100 });
    try std.testing.expectError(error.InvalidSavedCharge, decode(allocator, bad_lifetime));
    (try world.get(world.find(47).?, data.Charge)).expires_ms = 20000;
    try world.put(world.find(42).?, data.Binding{ .slot = 0 });
    try world.put(world.find(42).?, data.Body{});
    const duplicate_slot = try capture(allocator, &bytes, &world, "e1m3a", 3, .{ .at_ms = 1000, .episode = 1, .player_id = 7, .next_id = 100 });
    try std.testing.expectError(error.InvalidSavedBinding, decode(allocator, duplicate_slot));
    try std.testing.expectEqual(@as(i32, 100), (try world.get(world.find(7).?, data.Health)).current);
}

test "monitor restoration retains camera and remaining duration and rejects detached ownership" {
    const memory = std.testing.allocator;
    var world = data.World.init(memory, 8);
    defer world.deinit();
    _ = try world.create(1, .{ data.Transform{ .angles = .{ 0, 45, 0 } }, data.Velocity{}, data.Player{ .mode = .frozen }, data.Body{ .motion_owner = 2 }, data.Binding{ .slot = 0 }, data.Health{}, data.Hurt{}, data.Weapons{ .weapon = 1 }, data.Character{}, data.Ailments{}, data.Keys{} });
    _ = try world.create(2, .{ data.Transform{}, data.Body{}, data.Binding{ .slot = 64 }, data.MapObject{ .classname = "func_monitor" }, data.Monitor{ .duration_ms = 8000, .viewer = 1, .until_ms = 8500, .camera = 3, .target = 4, .origin = .{ 1824, 832, 520 }, .angles = .{ 20, 180, 0 } } });
    _ = try world.create(3, .{ data.Transform{}, data.MapObject{ .classname = "info_camera" } });
    _ = try world.create(4, .{ data.Transform{}, data.MapObject{ .classname = "info_notnull" } });
    var buffer: [32768]u8 = undefined;
    const bytes = try capture(memory, &buffer, &world, "e1m1c", 3, .{ .at_ms = 1000, .next_id = world.next_id, .player_id = 1, .episode = 1 });
    var loaded = try decode(memory, bytes);
    defer loaded.deinit(memory);
    try loaded.rebase(10000);
    const monitor = try loaded.world.get(loaded.world.find(2).?, data.Monitor);
    try std.testing.expectEqual(@as(?i64, 17500), monitor.until_ms);
    try std.testing.expectEqual(@as(i32, 8000), monitor.duration_ms);
    try std.testing.expectEqual(data.Vec3{ 1824, 832, 520 }, monitor.origin);
    try std.testing.expectEqual(data.Vec3{ 0, 45, 0 }, (try loaded.world.get(loaded.world.find(1).?, data.Transform)).angles);
    (try loaded.world.get(loaded.world.find(1).?, data.Body)).motion_owner = null;
    try std.testing.expectError(error.InvalidSavedMonitor, validate(&loaded));
}
