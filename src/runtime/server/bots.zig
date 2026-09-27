// SPDX-License-Identifier: GPL-2.0-or-later
//! Bots choose goals and submit ordinary user commands to the shared player motor.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const nav = @import("../domain/navigation.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Clients = @import("clients.zig").Clients;
const Brain = struct { next_ms: i64 = 0, goal: u32 = 0, goal_ms: i64 = 0, route: nav.State = .{}, jump_until: i64 = 0, jump_ready: i64 = 0, use_ready: i64 = 0 };
pub const State = struct {
    brains: [c.MAX_CLIENTS]?Brain = @splat(null),
    next_population: i64 = 0,
    serial: usize = 0,
    pub fn add(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, states: []c.playerState_t, clients: *Clients, now: i64) !void {
        const allocated = engine.gateway.call(c.G_BOT_ALLOCATE_CLIENT, .{});
        if (allocated < 0 or allocated >= c.MAX_CLIENTS) return error.NoBotClientSlot;
        const index: usize = @intCast(allocated);
        errdefer _ = engine.gateway.call(c.G_BOT_FREE_CLIENT, .{allocated});
        const appearance = @import("appearance_catalog").entries[self.serial * 7 % @import("appearance_catalog").entries.len];
        var info: [512]u8 = undefined;
        const text = try std.fmt.bufPrintZ(&info, "\\name\\Bot {d}\\model\\{s}\\skill\\3\\dk3_runtime_build\\{s}", .{ self.serial + 1, appearance.selection, @import("../engine/player_state.zig").version });
        _ = engine.gateway.call(c.G_SET_USERINFO, .{ allocated, text.ptr });
        try clients.begin(world, slots, projections, states, index, now, null);
        (try world.get(clients.entities[index].?, data.Session)).bot = true;
        projections[index].shared.svFlags |= c.SVF_BOT;
        self.brains[index] = .{};
        self.serial += 1;
        try clients.userinfo(world, index);
    }
    pub fn remove(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, clients: *Clients, index: usize, now: i64) !void {
        if (self.brains[index] == null) return;
        try clients.disconnect(world, slots, projections, index, now);
        _ = engine.gateway.call(c.G_BOT_FREE_CLIENT, .{@as(isize, @intCast(index))});
        self.brains[index] = null;
        engine.config(c.CS_PLAYERS + @as(i32, @intCast(index)), "");
    }
    pub fn step(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, states: []c.playerState_t, clients: *Clients, router: *@import("targets.zig").Router, service: nav.Service, now: i64) !void {
        if (!@import("multiplayer.zig").enabled()) return;
        engine.register("bot_minplayers", "0", 0);
        if (now >= self.next_population) {
            self.next_population = now + 1000;
            const fill = engine.integer("dk3_fillSlots");
            const requested: usize = @intCast(std.math.clamp(if (fill > 0) fill else engine.integer("bot_minplayers"), 0, engine.integer("sv_maxclients")));
            var count: usize = 0;
            for (clients.entities) |entity| if (entity != null) {
                count += 1;
            };
            if (count < requested) self.add(world, slots, projections, states, clients, now) catch |err| switch (err) {
                error.NoBotClientSlot => {}, // Connected clients may still be completing admission.
                else => return err,
            };
            if (count > requested and requested > 0) for (self.brains, 0..) |brain, i| if (brain != null) {
                try self.remove(world, slots, projections, clients, i, now);
                break;
            };
        }
        for (&self.brains, 0..) |*maybe, index| {
            const brain = if (maybe.*) |*value| value else continue;
            const entity = clients.entities[index] orelse {
                maybe.* = null;
                continue;
            };
            if (now < brain.next_ms) continue;
            brain.next_ms = now + 50;
            const player = (try world.get(entity, data.Player)).*;
            const session = (try world.get(entity, data.Session)).*;
            if (player.mode == .frozen or session.team == .spectator) continue;
            const pose = (try world.get(entity, data.Transform)).*;
            var input = std.mem.zeroes(c.usercmd_t);
            input.serverTime = @intCast(now);
            if (player.mode == .dead) {
                input.buttons = c.BUTTON_ATTACK;
                _ = engine.gateway.call(c.BOTLIB_USER_COMMAND, .{ @as(isize, @intCast(index)), &input });
                continue;
            }
            const loadout = (try world.get(entity, data.Weapons)).*;
            const eye = v.add(pose.position, .{ 0, 0, player.view_height });
            var enemy: ?ecs.Entity = null;
            var nearest: f32 = 1600;
            for (clients.entities) |candidate| {
                const other = candidate orelse continue;
                if (other.index == entity.index or (try world.get(other, data.Health)).current <= 0) continue;
                const member = (try world.get(other, data.Session)).*;
                if (member.team == .spectator or @import("../domain/multiplayer.zig").allied(session, member)) continue;
                const target = v.add((try world.get(other, data.Transform)).position, .{ 0, 0, 12 });
                const distance = v.length(v.subtract(target, eye));
                if (distance >= nearest) continue;
                const trace = try engine.collisionService().trace(.{ .start = eye, .end = target, .mins = @splat(0), .maxs = @splat(0), .slot = @intCast(index), .mask = c.MASK_SHOT });
                if (trace.fraction < 1 and trace.entity != (try world.get(other, data.Binding)).slot) continue;
                nearest = distance;
                enemy = other;
            }
            const selected = @import("../domain/bot_combat.zig").select(loadout, &clients.weapon_table, if (enemy != null) nearest else null);
            input.weapon = selected;
            var destination: ?v.Vec3 = null;
            if (objectiveGoal(world, entity)) |goal| destination = goal;
            if (destination == null and (now >= brain.goal_ms or world.find(brain.goal) == null)) {
                brain.goal = try pickupGoal(world, entity, &clients.weapon_table, now);
                brain.goal_ms = now + 5000;
            }
            if (destination == null) if (world.find(brain.goal)) |goal| {
                destination = (try world.get(goal, data.Transform)).position;
            };
            if (destination == null) if (enemy) |other| {
                destination = (try world.get(other, data.Transform)).position;
            };
            var movement: v.Vec3 = @splat(0);
            if (destination) |goal| {
                if (try brain.route.update(service, .{ .position = pose.position, .destination = goal, .slot = @intCast(index), .player = true }, now)) |waypoint| {
                    movement = v.subtract(waypoint.point, pose.position);
                    if (waypoint.jump and player.ground_entity != c.ENTITYNUM_NONE and now >= brain.jump_ready) {
                        brain.jump_until = now + 200;
                        brain.jump_ready = now + 800;
                    }
                }
                if (v.length(v.subtract(goal, pose.position)) < 32) {
                    brain.goal = 0;
                    brain.goal_ms = now;
                }
            }
            var aim = movement;
            if (enemy) |other| {
                aim = v.subtract(v.add((try world.get(other, data.Transform)).position, .{ 0, 0, 12 }), eye);
                if (!player.respawned and selected == loadout.weapon and @import("../domain/bot_combat.zig").attack(loadout, &clients.weapon_table, nearest)) input.buttons |= c.BUTTON_ATTACK;
            }
            if (v.length(aim) < 0.01) aim = v.basis(pose.angles).forward;
            const angles: v.Vec3 = .{ -std.math.atan2(aim[2], @sqrt(aim[0] * aim[0] + aim[1] * aim[1])) * 180 / std.math.pi, std.math.atan2(aim[1], aim[0]) * 180 / std.math.pi, 0 };
            for (angles, 0..) |angle, axis| input.angles[axis] = @as(i32, @intFromFloat(angle * 65536 / 360)) -% player.delta_angles[axis];
            const axes = v.basis(.{ 0, angles[1], 0 });
            const direction = v.normalize(.{ movement[0], movement[1], 0 });
            input.forwardmove = @intFromFloat(std.math.clamp(v.dot(direction, axes.forward) * 127, -127, 127));
            input.rightmove = @intFromFloat(std.math.clamp(v.dot(direction, axes.right) * 127, -127, 127));
            if (now < brain.jump_until or (player.water_level >= 2 and movement[2] > 8)) input.upmove = 127;
            if (brain.route.blocked and now >= brain.use_ready) {
                brain.use_ready = now + 1000;
                // Same reach and authored key checks as the player's Use action.
                try @import("interactions.zig").use(world, slots, projections, router, entity, now);
            }
            _ = engine.gateway.call(c.BOTLIB_USER_COMMAND, .{ @as(isize, @intCast(index)), &input });
        }
    }
};
fn pickupGoal(world: *data.World, player: ecs.Entity, table: *const @import("../domain/weapons.zig").Table, now: i64) !u32 {
    const origin = (try world.get(player, data.Transform)).position;
    var nearest: f32 = std.math.inf(f32);
    var result: u32 = 0;
    var query = world.queryAccess(data.World.mask(.{ data.Pickup, data.Transform }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Pickup), view.read(data.Transform)) |entity, pickup, pose| {
        if (!pickup.visible) continue;
        var health = (try world.get(player, data.Health)).*;
        var keys = (try world.get(player, data.Keys)).*;
        var loadout = (try world.get(player, data.Weapons)).*;
        var character = (try world.get(player, data.Character)).*;
        var ailments = (try world.get(player, data.Ailments)).*;
        if (!@import("../domain/items.zig").give(pickup, .{ .health = &health, .keys = &keys, .loadout = &loadout, .character = &character, .ailments = &ailments }, table, now, false)) continue;
        const distance = v.length(v.subtract(origin, pose.position));
        if (distance < 24 or distance >= nearest) continue;
        nearest = distance;
        result = try world.persistentId(entity);
    };
    return result;
}
fn objectiveGoal(world: *data.World, player: ecs.Entity) ?v.Vec3 {
    const id = world.persistentId(player) catch return null;
    const session = (world.get(player, data.Session) catch return null).*;
    if (session.team != .red and session.team != .blue) return null;
    const held = @import("multiplayer.zig").held(world, id);
    const is_bomb = engine.integer("g_gametype") == c.GT_DK3_DEATHTAG;
    var query = world.queryAccess(data.World.mask(.{data.Transform}), 0, 0);
    defer query.deinit();
    var capture: ?v.Vec3 = null;
    while (query.next()) |view| for (view.entities(), view.read(data.Transform)) |entity, pose| {
        if (world.get(entity, data.Objective) catch null) |objective| {
            const wanted = if (is_bomb) objective.team == session.team else objective.team != session.team;
            if (held == null and wanted and (objective.phase == .home or objective.phase == .dropped)) return pose.position;
            if (held != null and !is_bomb and objective.team == session.team and objective.phase != .home) return pose.position;
        }
        if (held != null) if (world.get(entity, data.MapObject) catch null) |object| if (std.mem.eql(u8, object.classname, "trigger_capture") and (object.flags & 3 == 0 or object.flags & 3 == @intFromEnum(session.team))) {
            const body = world.get(entity, data.Body) catch continue;
            capture = v.add(pose.position, v.scale(v.add(body.mins, body.maxs), 0.5));
        };
    };
    return capture;
}
