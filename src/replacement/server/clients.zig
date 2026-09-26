// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const bridge = @import("../engine/player_state.zig");
const Slots = @import("../engine/slots.zig").Slots;
const c = abi.c;
const weapons = @import("../domain/weapons.zig");
pub const Clients = struct {
    weapon_table: weapons.Table = .{},
    entities: [c.MAX_CLIENTS]?ecs.Entity = @splat(null),
    episode: u8 = 1,
    pub fn begin(self: *Clients, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, states: []c.playerState_t, index: usize, now: i64) !void {
        if (index >= self.entities.len) return error.InvalidClient;
        try self.disconnect(world, slots, projections, index);
        var spawn: ?data.Transform = null;
        var priority: u8 = 0;
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
        {
            defer query.deinit();
            while (query.next()) |view| {
                for (view.read(data.MapObject), view.read(data.Transform)) |object, transform| {
                    const candidate: u8 = if (std.mem.eql(u8, object.classname, "info_player_start")) 2 else if (std.mem.eql(u8, object.classname, "info_player_deathmatch")) 1 else 0;
                    if (candidate > priority) {
                        spawn = transform;
                        priority = candidate;
                    }
                }
                if (priority == 2) break;
            }
        }
        var transform = spawn orelse return error.MissingPlayerSpawn;
        transform.position[2] += 9;
        const entity = try world.create(null, .{ transform, data.Velocity{}, data.Player{ .command_ms = now, .respawned = true }, data.Health{}, data.Body{ .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .contents = c.CONTENTS_BODY, .collision_mask = c.MASK_PLAYERSOLID }, data.Binding{ .slot = @intCast(index) }, data.Weapons{} });
        errdefer world.destroy(entity) catch unreachable;
        _ = try slots.acquire(entity, @intCast(index));
        self.entities[index] = entity;
        const loadout = try world.get(entity, data.Weapons);
        const initial = @import("weapon_catalog").starting(self.episode);
        _ = loadout.acquire(&self.weapon_table, initial, self.weapon_table.entries[initial].initialAmmo);
        var cmd: c.usercmd_t = undefined;
        engine.usercmd(@intCast(index), &cmd);
        for (transform.angles, 0..) |angle, i| (try world.get(entity, data.Player)).delta_angles[i] = @as(i32, @intFromFloat(angle * (65536.0 / 360.0))) -% cmd.angles[i];
        @memset(std.mem.asBytes(&states[index]), 0);
        states[index].clientNum = @intCast(index);
        states[index].speed = 320;
        states[index].gravity = 800;
        states[index].stats[c.STAT_MAX_HEALTH] = 100;
        try self.publish(world, projections, states, index);
        engine.print("dk3 zig: player entered isolated movement runtime\n");
    }
    pub fn disconnect(self: *Clients, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, index: usize) !void {
        if (index >= self.entities.len) return error.InvalidClient;
        if (self.entities[index]) |entity| {
            engine.unlink(&projections[index]);
            try slots.release(@intCast(index), entity);
            try world.destroy(entity);
            self.entities[index] = null;
        }
    }
    pub fn think(self: *Clients, world: *data.World, projections: []abi.EntityProjection, states: []c.playerState_t, index: usize, now: i64) !void {
        if (index >= self.entities.len) return error.InvalidClient;
        const entity = self.entities[index] orelse return;
        var input: c.usercmd_t = undefined;
        engine.usercmd(@intCast(index), &input);
        input.serverTime = @intCast(std.math.clamp(@as(i64, input.serverTime), now - 1000, now + 200));
        const player = try world.get(entity, data.Player);
        const command = bridge.command(input, &player.delta_angles);
        if ((try world.get(entity, data.Health)).current <= 0) player.mode = .dead;
        if (command.time_ms <= player.command_ms) return;
        const transform = try world.get(entity, data.Transform);
        const velocity = try world.get(entity, data.Velocity);
        var motion: @import("../domain/slide.zig").State = .{ .position = transform.position, .velocity = velocity.linear };
        var events: weapons.Events = .{};
        var weapon_context: weapons.Context = .{ .ps = try world.get(entity, data.Weapons), .table = &self.weapon_table, .events = &events, .service = engine.collisionService(), .slot = @intCast(index), .shot_mask = c.MASK_SHOT };
        const result = try @import("../domain/player_move.zig").runWithHook(player, &motion, command, bridge.parameters(@intCast(index)), engine.collisionService(), weapon_context.hook());
        for (events.values[0..events.count], 0..) |event, i| {
            const sequence = weapon_context.ps.event_sequence -% @as(u32, @intCast(events.count - i));
            states[index].events[sequence & (c.MAX_PS_EVENTS - 1)] = switch (event) {
                .fired => c.EV_FIRE_WEAPON,
                .no_ammo => c.EV_NOAMMO,
            };
            states[index].eventParms[sequence & (c.MAX_PS_EVENTS - 1)] = 0;
        }
        transform.position = motion.position;
        transform.angles = command.angles;
        velocity.linear = motion.velocity;
        const body = try world.get(entity, data.Body);
        body.mins = result.mins;
        body.maxs = result.maxs;
        body.grounded = player.ground_entity != c.ENTITYNUM_NONE;
        try self.publish(world, projections, states, index);
    }
    pub fn publish(self: *Clients, world: *data.World, projections: []abi.EntityProjection, states: []c.playerState_t, index: usize) !void {
        const entity = self.entities[index].?;
        const transform = (try world.get(entity, data.Transform)).*;
        const velocity = (try world.get(entity, data.Velocity)).*;
        const body = (try world.get(entity, data.Body)).*;
        const inventory = (try world.get(entity, data.Weapons)).*;
        const ps = &states[index];
        bridge.write(ps, (try world.get(entity, data.Player)).*, transform, velocity);
        ps.stats[c.STAT_HEALTH] = (try world.get(entity, data.Health)).current;
        bridge.writeWeapons(ps, inventory);
        const projection = &projections[index];
        projection.state.number = @intCast(index);
        projection.state.clientNum = @intCast(index);
        projection.state.eType = c.ET_PLAYER;
        projection.state.pos.trType = c.TR_INTERPOLATE;
        projection.state.pos.trBase = transform.position;
        projection.state.apos.trType = c.TR_INTERPOLATE;
        projection.state.apos.trBase = transform.angles;
        projection.state.groundEntityNum = ps.groundEntityNum;
        projection.state.weapon = ps.weapon;
        projection.shared.currentOrigin = transform.position;
        projection.shared.currentAngles = transform.angles;
        projection.shared.mins = body.mins;
        projection.shared.maxs = body.maxs;
        projection.shared.contents = @bitCast(body.contents);
        projection.shared.ownerNum = c.ENTITYNUM_NONE;
        engine.link(projection);
    }
};
