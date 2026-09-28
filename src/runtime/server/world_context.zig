// SPDX-License-Identifier: GPL-2.0-or-later
//! Stable map-local ownership. A region retains these allocations across travel.
const std = @import("std");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const component = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const worlds = @import("../engine/worlds.zig");
const resources = @import("resources.zig");
const snapshot = @import("../domain/snapshot.zig");
pub const Context = struct {
    targets: @import("targets.zig").Router = .{},
    systems: @import("world_systems.zig").State = .{},
    bots: @import("bots.zig").State = .{},
    clients: @import("clients.zig").Clients = .{},
    arena: ?std.heap.ArenaAllocator = null,
    world: ?component.World = null,
    projection: [c.MAX_GENTITIES]abi.EntityProjection = undefined,
    players: [c.MAX_CLIENTS]c.playerState_t = undefined,
    presentation: @import("region_presentation.zig").State = .{},
    slots: @import("../engine/slots.zig").Slots = .{},
    restored_arena: ?*std.heap.ArenaAllocator = null,
    restore_pending: ?@import("../domain/snapshot.zig").Loaded = null,
    configuration: @import("configuration.zig").State = .{},
    resources: @import("resources.zig").State = .{},
    prepared_at: i64 = 0,
    stepped_at: i64 = 0,
    handle: ?worlds.Handle = null,
    network_id: u32 = 0,
    activated: bool = false,
    running: bool = false,
    map_name: [c.MAX_QPATH]u8 = @splat(0),

    pub const Scope = struct {
        world: worlds.Handle,
        resource_owner: *resources.State,
        pub fn deinit(self: Scope) void {
            worlds.select(self.world) catch @panic("lost scoped world owner");
            _ = resources.select(self.resource_owner);
        }
    };
    pub fn select(self: *Context) !Scope {
        const previous = worlds.current();
        try worlds.select(self.handle orelse return error.WorldNotAttached);
        return .{ .world = previous, .resource_owner = resources.select(&self.resources) };
    }

    /// Creates authored entities without stepping encounters or admitting players.
    /// The caller owns the matching engine context and releases it on failure.
    pub fn prepare(handle: worlds.Handle, namespace: u7, now: i64, table: *const @import("../domain/weapons.zig").Table, saved: ?*snapshot.Loaded) !*Context {
        const self = try std.heap.c_allocator.create(Context);
        self.* = .{};
        errdefer self.destroy();
        const previous_world = worlds.current();
        try worlds.select(handle);
        defer worlds.select(previous_world) catch @panic("lost active server world");
        const previous_resources = resources.select(&self.resources);
        defer _ = resources.select(previous_resources);
        // Older flat archives did not record an asset checksum. Their saved
        // class/resource contracts still undergo normal admission below.
        if (saved) |value| if (value.header.asset_crc != 0 and value.header.asset_crc != @as(u32, @truncate(@as(usize, @bitCast(engine.gateway.call(c.G_DK3_WORLD_CHECKSUM_V1, .{})))))) return error.ResidentAssetMismatch;
        self.prepared_at = now;
        self.stepped_at = now;
        self.handle = handle;
        self.network_id = @intFromEnum(handle);
        self.arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
        self.world = component.World.initNamespaced(std.heap.c_allocator, 1024, namespace);
        @memset(std.mem.asBytes(&self.projection), 0);
        @memset(std.mem.asBytes(&self.players), 0);
        for (&self.projection, 0..) |*entity, i| {
            entity.state.number = @intCast(i);
            entity.shared.ownerNum = c.ENTITYNUM_NONE;
        }
        engine.locate(&self.projection, &self.players);
        self.clients.weapon_table = table.*;
        var name_buffer: [c.MAX_QPATH]u8 = undefined;
        const name = engine.mapName(&name_buffer);
        @memcpy(self.map_name[0..name.len], name);
        if (name.len >= 2 and name[0] == 'e' and name[1] >= '1' and name[1] <= '4') self.clients.episode = name[1] - '0';
        engine.config(c.CS_GAME_VERSION, @import("../engine/player_state.zig").version);
        engine.config(c.CS_DK3_SKY, "1");
        while (try @import("map.zig").read(self.arena.?.allocator(), engine)) |object| {
            if (std.mem.eql(u8, object.binding.classname, "worldspawn")) {
                var value: [64]u8 = undefined;
                engine.config(c.CS_DK3_LOADSCREEN, try std.fmt.bufPrintZ(&value, "{s}", .{@import("properties.zig").text(object.binding, "loadscreen") orelse ""}));
            }
            _ = try self.world.?.create(null, .{ object.binding, object.transform });
        }
        try self.systems.spawn(self.arena.?.allocator(), &self.world.?, &self.slots, &self.projection, now, self.clients.episode, table, false, true);
        self.targets.scripts = &self.systems.scripts;
        self.targets.cinematics = &self.systems.cinematics;
        self.targets.actors = &self.systems.actors;
        if (saved) |value| {
            try @import("persistence.zig").admit(value, &self.systems);
            try value.rebase(now);
            try self.install(value, now);
        }
        return self;
    }
    pub fn capture(self: *Context, allocator: std.mem.Allocator) !snapshot.Archive {
        const prior = worlds.current();
        try worlds.select(self.handle orelse return error.WorldNotAttached);
        defer worlds.select(prior) catch @panic("lost active world");
        const previous_resources = resources.select(&self.resources);
        defer _ = resources.select(previous_resources);
        var name: [c.MAX_QPATH]u8 = undefined;
        const map = try allocator.dupe(u8, engine.mapName(&name));
        const buffer = try allocator.alloc(u8, snapshot.world_limit);
        const header: snapshot.Header = .{ .at_ms = self.stepped_at, .next_id = self.world.?.next_id, .player_id = if (self.clients.entities[0]) |player| try self.world.?.persistentId(player) else 0, .episode = self.clients.episode, .namespace = @intCast(self.world.?.id_first >> 24), .asset_crc = @truncate(@as(usize, @bitCast(engine.gateway.call(c.G_DK3_WORLD_CHECKSUM_V1, .{})))), .activated = self.activated, .resources = try resources.capture(allocator), .pending = self.targets.pending };
        return .{ .map = map, .bytes = try snapshot.capture(allocator, buffer, &self.world.?, map, @intCast(std.math.clamp(engine.integer("g_spSkill"), 1, 5)), header) };
    }
    /// The entire region is decoded, linked and admitted before this commit.
    pub fn install(self: *Context, saved: *snapshot.Loaded, now: i64) !void {
        const prior = worlds.current();
        try worlds.select(self.handle.?);
        defer worlds.select(prior) catch @panic("lost active world");
        const previous_resources = resources.select(&self.resources);
        defer _ = resources.select(previous_resources);
        self.presentation.clear(self);
        for (&self.projection) |*entity| if (entity.shared.linked != 0) engine.unlink(entity);
        self.world.?.deinit();
        if (self.restored_arena) |arena| {
            arena.deinit();
            std.heap.c_allocator.destroy(arena);
        }
        self.world = saved.world;
        self.restored_arena = saved.arena;
        saved.ownership_transferred = true;
        self.activated = saved.header.activated;
        self.running = false;
        self.stepped_at = now;
        self.targets = .{ .pending = saved.header.pending, .scripts = &self.systems.scripts, .cinematics = &self.systems.cinematics, .actors = &self.systems.actors };
        try resources.restore(saved.header.resources);
        try self.systems.actors.prepareParty();
        try @import("persistence.zig").project(&self.world.?, &self.slots, &self.projection, &self.clients, &self.players, &self.systems, saved.header, now);
        self.players[0].dk3World = @bitCast(self.network_id);
        try self.auditRestore(now);
    }
    /// Read-only evidence at the actual restoration boundary, before controllers
    /// can retire an already gibbed corpse or resume an unfinished encounter.
    pub fn auditRestore(self: *Context, now: i64) !void {
        if (engine.integer("dk3_runtime_restore_audit") == 0) return;
        var message: [192]u8 = undefined;
        for (self.slots.occupants) |maybe| if (maybe) |entity| {
            _ = self.world.?.get(entity, component.Actor) catch continue;
            const health = try self.world.?.get(entity, component.Health);
            engine.print(try std.fmt.bufPrintZ(&message, "dk3 restore actor: map={s} id={d} health={d} at={d}\n", .{ std.mem.sliceTo(&self.map_name, 0), try self.world.?.persistentId(entity), health.current, now }));
        };
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 restore actors complete: map={s} at={d}\n", .{ std.mem.sliceTo(&self.map_name, 0), now }));
    }
    pub fn awaken(self: *Context, now: i64) !void {
        const delta = try std.math.sub(i64, now, self.stepped_at);
        var query = self.world.?.queryAccess(0, 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            inline for (std.meta.fields(component.Component)) |field| if (self.world.?.get(entity, field.type) catch null) |value| {
                try @import("../domain/snapshot_time.zig").rebase(@field(component.ComponentId, field.name), value, delta);
            };
        };
        for (&self.targets.pending) |*entry| if (entry.*) |*action| {
            action.due_ms = try std.math.add(i64, action.due_ms, delta);
        };
        self.activated = true;
        self.stepped_at = now;
    }
    pub fn expose(self: *Context, now: i64) !void {
        if (!self.running) try self.awaken(now);
        self.running = true;
    }
    pub fn destroy(self: *Context) void {
        self.configuration.deinit();
        self.systems.deinit(false);
        if (self.restore_pending) |*saved| saved.deinit(std.heap.c_allocator);
        if (self.world) |*value| value.deinit();
        if (self.restored_arena) |strings| {
            strings.deinit();
            std.heap.c_allocator.destroy(strings);
        }
        if (self.arena) |*value| value.deinit();
        std.heap.c_allocator.destroy(self);
    }
};
