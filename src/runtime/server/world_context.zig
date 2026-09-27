// SPDX-License-Identifier: GPL-2.0-or-later
//! Stable map-local ownership. A region retains these allocations across travel.
const std = @import("std");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const component = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const worlds = @import("../engine/worlds.zig");
const resources = @import("resources.zig");
pub const Context = struct {
    targets: @import("targets.zig").Router = .{},
    systems: @import("world_systems.zig").State = .{},
    bots: @import("bots.zig").State = .{},
    clients: @import("clients.zig").Clients = .{},
    arena: ?std.heap.ArenaAllocator = null,
    world: ?component.World = null,
    projection: [c.MAX_GENTITIES]abi.EntityProjection = undefined,
    players: [c.MAX_CLIENTS]c.playerState_t = undefined,
    slots: @import("../engine/slots.zig").Slots = .{},
    restored_arena: ?*std.heap.ArenaAllocator = null,
    restore_pending: ?@import("../domain/snapshot.zig").Loaded = null,
    resources: @import("resources.zig").State = .{},
    prepared_at: i64 = 0,

    /// Creates authored entities without stepping encounters or admitting players.
    /// The caller owns the matching engine context and releases it on failure.
    pub fn prepare(handle: worlds.Handle, now: i64, table: *const @import("../domain/weapons.zig").Table) !*Context {
        const self = try std.heap.c_allocator.create(Context);
        self.* = .{};
        errdefer self.destroy();
        const previous_world = worlds.current();
        try worlds.select(handle);
        defer worlds.select(previous_world) catch @panic("lost active server world");
        const previous_resources = resources.select(&self.resources);
        defer _ = resources.select(previous_resources);
        self.prepared_at = now;
        self.arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
        self.world = component.World.init(std.heap.c_allocator, 1024);
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
        return self;
    }
    pub fn destroy(self: *Context) void {
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
