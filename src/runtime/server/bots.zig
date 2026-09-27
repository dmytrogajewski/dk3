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
const routes = @import("bot_routes.zig");
const Brain = struct {
    next_ms: i64 = 0,
    goal: u32 = 0,
    goal_ms: i64 = 0,
    route: nav.State = .{},
    jump_until: i64 = 0,
    jump_ready: i64 = 0,
    use_ready: i64 = 0,
    control: ?routes.Control = null,
    control_until: i64 = 0,
    seek_ms: i64 = 0,
    avoided: u32 = 0,
    avoid_until: i64 = 0,
    yield_point: ?v.Vec3 = null,
    yield_until: i64 = 0,
};
pub const State = struct {
    brains: [c.MAX_CLIENTS]?Brain = @splat(null),
    next_population: i64 = 0,
    serial: usize = 0,
    /// Read-only route evidence for normal-input match diagnostics.
    pub fn report(self: *const State, world: *data.World, slots: *const Slots, clients: *const Clients) !void {
        var buffer: [1024]u8 = undefined;
        for (self.brains, 0..) |maybe, index| if (maybe) |brain| {
            const route = brain.route;
            const waypoint = route.waypoint orelse nav.Waypoint{ .point = @splat(0) };
            engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 bot route: slot={d} goal={d} avoided={d} destination={d:.2},{d:.2},{d:.2} waypoint={d:.2},{d:.2},{d:.2} valid={d} areas={d},{d} jump={d} crouch={d} ladder={d} blocked={d} progress_ms={d} refresh_ms={d} jump_until={d} control={d} yielding={d}\n", .{
                index,                                brain.goal,                                     brain.avoided,
                route.destination[0],                 route.destination[1],                           route.destination[2],
                waypoint.point[0],                    waypoint.point[1],                              waypoint.point[2],
                @intFromBool(route.waypoint != null), waypoint.from_area,                             waypoint.to_area,
                @intFromBool(waypoint.jump),          @intFromBool(waypoint.crouch),                  @intFromBool(waypoint.ladder),
                @intFromBool(route.blocked),          route.progress_ms,                              route.refresh_ms,
                brain.jump_until,                     if (brain.control) |control| control.id else 0, @intFromBool(brain.yield_point != null),
            }));
            if (route.blocked) if (clients.entities[index]) |entity| try @import("navigation_probe.zig").corridor(world, slots, entity, if (route.waypoint != null) waypoint.point else route.destination);
        };
    }
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
    fn assigned(self: *const State, world: *data.World, clients: *const Clients, requester: usize, obstacle: u32) bool {
        const player = clients.entities[requester] orelse return false;
        const team = (world.get(player, data.Session) catch return false).*;
        for (self.brains, clients.entities, 0..) |maybe, candidate, index| {
            if (index == requester) continue;
            const other = candidate orelse continue;
            const brain = maybe orelse continue;
            const control = brain.control orelse continue;
            if (control.route_obstacle != obstacle) continue;
            if ((world.get(other, data.Health) catch continue).current <= 0) continue;
            const session = (world.get(other, data.Session) catch continue).*;
            if (@import("../domain/multiplayer.zig").allied(team, session)) return true;
        }
        return false;
    }
    pub fn step(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, states: []c.playerState_t, clients: *Clients, router: *@import("targets.zig").Router, service: nav.Service, now: i64) !void {
        _ = router;
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
            // Bots read gameplay state directly, but must still acknowledge the
            // engine's reliable configstrings/chat just like network clients.
            var message: [1024]u8 = undefined;
            while (engine.gateway.call(c.BOTLIB_GET_CONSOLE_MESSAGE, .{ @as(isize, @intCast(index)), &message, @as(isize, message.len) }) != 0) {}
            if (now < brain.next_ms) continue;
            brain.next_ms = now + 50;
            const player = (try world.get(entity, data.Player)).*;
            const session = (try world.get(entity, data.Session)).*;
            if (player.mode == .frozen or session.team == .spectator) continue;
            const pose = (try world.get(entity, data.Transform)).*;
            var input = std.mem.zeroes(c.usercmd_t);
            input.serverTime = @intCast(now);
            if (player.mode == .dead) {
                brain.* = .{ .next_ms = now + 50 };
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
            const health = (try world.get(entity, data.Health)).*;
            const resupply = health.current * 2 < health.maximum or !@import("../domain/bot_combat.zig").ranged(loadout, &clients.weapon_table);
            if (resupply) destination = null;
            const old_pickup = if (world.find(brain.goal)) |goal| world.get(goal, data.Pickup) catch null else null;
            if (destination == null and (now >= brain.goal_ms or old_pickup == null or !old_pickup.?.visible)) {
                brain.goal = try pickupGoal(world, entity, &clients.weapon_table, service, if (now < brain.avoid_until) brain.avoided else 0, resupply, now);
                brain.goal_ms = now + 5000;
            }
            if (destination == null) if (world.find(brain.goal)) |goal| {
                destination = @import("../domain/navigation_input.zig").pickupPoint((try world.get(goal, data.Transform)).position, (try world.get(goal, data.Body)).mins, (try world.get(entity, data.Body)).mins);
            };
            if (destination == null and resupply) destination = objectiveGoal(world, entity);
            if (destination == null) if (enemy) |other| {
                destination = (try world.get(other, data.Transform)).position;
            };
            var control_aim: ?v.Vec3 = null;
            if (brain.control) |previous| {
                // Keep a remote control goal while the bot makes actual route
                // progress; a fixed trip deadline abandoned cross-base controls.
                brain.control_until = @max(brain.control_until, brain.route.progress_ms + 15000);
                if (routes.completed(world, previous) or now >= brain.control_until) {
                    if (!routes.completed(world, previous)) {
                        brain.avoided = previous.id;
                        brain.avoid_until = now + 10000;
                    }
                    brain.control = null;
                    brain.route = .{};
                } else {
                    var control = previous;
                    control_aim = try routes.aim(world, control);
                    if (control_aim == null) {
                        if (try routes.advance(world, slots, projections, entity, control, service, now)) |next| {
                            control = next;
                            brain.control = next;
                            brain.route = .{};
                            control_aim = try routes.aim(world, next);
                        }
                    }
                    // Delayed relays and moving prerequisite doors retain the
                    // original route request while no next control is ready.
                    destination = if (control_aim == null) pose.position else control.point;
                    if (control.action == .touch and nav.horizontalDistance(pose.position, control.point) < 24 and control_aim != null) destination = control_aim;
                }
            }
            if (now < brain.yield_until) {
                destination = brain.yield_point;
            } else brain.yield_point = null;
            if (brain.control == null) if (destination) |goal| {
                if (try routes.ridePoint(world, slots, entity, goal)) |point| destination = point;
            };
            var movement: v.Vec3 = @splat(0);
            var crouch = false;
            var ladder = false;
            if (destination) |goal| {
                // Prefer every safe route. If none exists, permit swimming out
                // of a slime basin; actual contact still applies authored damage.
                if (try brain.route.update(service, .{ .position = pose.position, .destination = goal, .slot = @intCast(index), .player = true, .allow_slime_escape = true }, now)) |waypoint| {
                    movement = v.subtract(waypoint.point, pose.position);
                    ladder = waypoint.ladder;
                    const hull = (try world.get(entity, data.Body)).*;
                    crouch = waypoint.crouch or try @import("../domain/navigation_input.zig").crouch(engine.collisionService(), pose.position, waypoint.point, hull.mins, .{ hull.maxs[0], hull.maxs[1], 32 }, @intCast(index), hull.collision_mask);
                    if (waypoint.jump and player.ground_entity != c.ENTITYNUM_NONE and now >= brain.jump_ready) {
                        brain.jump_until = now + 200;
                        brain.jump_ready = now + 800;
                    }
                }
                // A raised lift can make successive AAS entrances alternate
                // while the bot still slides sideways at its face. Physical
                // movement alone is not proof that the next floor is reachable.
                // Inspect the actual obstructing mover before trying that ascent;
                // seek still requires a collision and its authored real control.
                // Descending through a raised platform also requires its real
                // control; the next lower AAS point can lie inside that floor.
                const changing_floor = brain.control == null and player.ground_entity != c.ENTITYNUM_NONE and @abs(movement[2]) > 18;
                if ((brain.route.blocked or changing_floor) and now >= brain.seek_ms) {
                    brain.seek_ms = now + 500;
                    const toward = if (brain.route.waypoint) |waypoint| waypoint.point else goal;
                    if (try routes.yieldPoint(world, slots, entity, toward)) |point| {
                        brain.yield_point = point;
                        brain.yield_until = now + 1000;
                        brain.route = .{};
                    } else {
                        const control = try routes.seek(world, slots, projections, entity, toward, service, now, if (now < brain.avoid_until) brain.avoided else 0);
                        if (control != null and (brain.control == null or control.?.id != brain.control.?.id)) {
                            if (brain.control == null and self.assigned(world, clients, index, control.?.route_obstacle)) {
                                // A teammate fetches the remote control while
                                // this bot stays available to cross the door.
                                movement = @splat(0);
                            } else {
                                var next = control.?;
                                if (brain.control) |parent| next.route_obstacle = parent.route_obstacle;
                                brain.control = next;
                                brain.control_until = now + 15000;
                                brain.route = .{};
                            }
                        } else if (brain.control == null and now - brain.route.progress_ms >= 3000 and brain.goal != 0) {
                            brain.avoided = brain.goal;
                            brain.avoid_until = now + 10000;
                            brain.goal = 0;
                            brain.goal_ms = now;
                        }
                    }
                }
                if (brain.control == null and brain.yield_point == null and v.length(v.subtract(goal, pose.position)) < 32) {
                    brain.goal = 0;
                    brain.goal_ms = now;
                }
            }
            var aim = movement;
            if (enemy) |other| {
                aim = v.subtract(v.add((try world.get(other, data.Transform)).position, .{ 0, 0, 12 }), eye);
                if (!player.respawned and selected == loadout.weapon and @import("../domain/bot_combat.zig").attack(loadout, &clients.weapon_table, nearest)) input.buttons |= c.BUTTON_ATTACK;
            }
            var use_control = false;
            if (brain.control) |control| if (control_aim) |point| {
                const delta = v.subtract(point, eye);
                if (control.action != .touch and (control.action == .shoot or v.length(delta) < 144)) {
                    aim = delta;
                    input.buttons &= ~@as(i32, c.BUTTON_ATTACK);
                    const current_forward = v.basis(pose.angles).forward;
                    if (v.dot(current_forward, v.normalize(delta)) > 0.99) {
                        const reach: f32 = if (control.action == .use) 96 else @max(96, v.length(delta) + 8);
                        const hit = try engine.collisionService().trace(.{ .start = eye, .end = v.add(eye, v.scale(current_forward, reach)), .mins = @splat(0), .maxs = @splat(0), .slot = @intCast(index), .mask = c.MASK_SHOT });
                        if (world.find(control.id)) |target| if (hit.entity == (try world.get(target, data.Binding)).slot) {
                            if (control.action == .use and now >= brain.use_ready) {
                                use_control = true;
                                brain.use_ready = now + 1000;
                            } else if (control.action == .shoot and !player.respawned and selected == loadout.weapon and @import("../domain/bot_combat.zig").attack(loadout, &clients.weapon_table, v.length(delta))) input.buttons |= c.BUTTON_ATTACK;
                        };
                    }
                }
            };
            if (v.length(aim) < 0.01) aim = v.basis(pose.angles).forward;
            const angles: v.Vec3 = .{ -std.math.atan2(aim[2], @sqrt(aim[0] * aim[0] + aim[1] * aim[1])) * 180 / std.math.pi, std.math.atan2(aim[1], aim[0]) * 180 / std.math.pi, 0 };
            for (angles, 0..) |angle, axis| input.angles[axis] = @as(i32, @intFromFloat(angle * 65536 / 360)) -% player.delta_angles[axis];
            const axes = v.basis(.{ 0, angles[1], 0 });
            const direction = v.normalize(.{ movement[0], movement[1], 0 });
            input.forwardmove = @intFromFloat(std.math.clamp(v.dot(direction, axes.forward) * 127, -127, 127));
            input.rightmove = @intFromFloat(std.math.clamp(v.dot(direction, axes.right) * 127, -127, 127));
            if (crouch) input.upmove = -127;
            if (now < brain.jump_until) input.upmove = 127;
            if ((ladder or player.water_level >= 2) and @abs(movement[2]) > 8) input.upmove = if (movement[2] > 0) 127 else -127;
            if (use_control) {
                if (engine.integer("developer") > 0) engine.print(try std.fmt.bufPrintZ(&message, "dk3 bot control: slot={d} use={d} obstacle={d} route_obstacle={d}\n", .{ index, brain.control.?.id, brain.control.?.obstacle, brain.control.?.route_obstacle }));
                _ = engine.gateway.call(c.BOTLIB_EA_COMMAND, .{ @as(isize, @intCast(index)), @as([*:0]const u8, "use") });
            }
            _ = engine.gateway.call(c.BOTLIB_USER_COMMAND, .{ @as(isize, @intCast(index)), &input });
        }
    }
};
fn pickupGoal(world: *data.World, player: ecs.Entity, table: *const @import("../domain/weapons.zig").Table, service: nav.Service, avoided: u32, resupply: bool, now: i64) !u32 {
    const origin = (try world.get(player, data.Transform)).position;
    const body = (try world.get(player, data.Body)).*;
    var nearest: f32 = std.math.inf(f32);
    var result: u32 = 0;
    var query = world.queryAccess(data.World.mask(.{ data.Pickup, data.Transform, data.Body }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Pickup), view.read(data.Transform), view.read(data.Body)) |entity, pickup, pose, bounds| {
        if (!pickup.visible or try world.persistentId(entity) == avoided) continue;
        var health = (try world.get(player, data.Health)).*;
        if (resupply) switch (pickup.kind) {
            .health, .soul => if (health.current * 2 >= health.maximum) continue,
            .weapon, .ammunition => if (@import("../domain/bot_combat.zig").ranged((try world.get(player, data.Weapons)).*, table)) continue,
            else => continue,
        };
        var keys = (try world.get(player, data.Keys)).*;
        var loadout = (try world.get(player, data.Weapons)).*;
        var character = (try world.get(player, data.Character)).*;
        var ailments = (try world.get(player, data.Ailments)).*;
        if (!@import("../domain/items.zig").give(pickup, .{ .health = &health, .keys = &keys, .loadout = &loadout, .character = &character, .ailments = &ailments }, table, now, false)) continue;
        const goal = @import("../domain/navigation_input.zig").pickupPoint(pose.position, bounds.mins, body.mins);
        const distance = v.length(v.subtract(origin, goal));
        if (distance < 24 or distance >= nearest) continue;
        if (try service.next(.{ .position = origin, .destination = goal, .slot = (try world.get(player, data.Binding)).slot, .player = true }) == null) continue;
        // Optional loot must not strand the bot in a drop-only pocket whose
        // return requires unprotected slime. Emergency escape remains separate.
        if (try service.next(.{ .position = goal, .destination = origin, .slot = (try world.get(player, data.Binding)).slot, .player = true }) == null) continue;
        nearest = distance;
        result = try world.persistentId(entity);
    };
    return result;
}
fn objectiveGoal(world: *data.World, player: ecs.Entity) ?v.Vec3 {
    const id = world.persistentId(player) catch return null;
    const session = (world.get(player, data.Session) catch return null).*;
    if (session.team != .red and session.team != .blue) return null;
    const origin = (world.get(player, data.Transform) catch return null).position;
    const held = @import("multiplayer.zig").held(world, id);
    const is_bomb = engine.integer("g_gametype") == c.GT_DK3_DEATHTAG;
    var chosen: ?v.Vec3 = null;
    var nearest: f32 = std.math.inf(f32);
    var priority: u8 = 0;
    var query = world.queryAccess(data.World.mask(.{data.Transform}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Transform)) |entity, pose| {
        var rank: u8 = 0;
        var point = pose.position;
        if (world.get(entity, data.Objective) catch null) |objective| {
            if (objective.phase == .home or objective.phase == .dropped) {
                point = @import("../domain/navigation_input.zig").pickupPoint(pose.position, (world.get(entity, data.Body) catch continue).mins, (world.get(player, data.Body) catch continue).mins);
            }
            if (!is_bomb and objective.team == session.team and objective.phase != .home) {
                // Recover the flag (or pursue its carrier) before an impossible capture.
                rank = if (held != null or objective.phase == .dropped) 4 else 3;
            } else if (held == null and (objective.phase == .home or objective.phase == .dropped) and (if (is_bomb) objective.team == session.team else objective.team != session.team)) {
                rank = 2;
            } else if (held == null and objective.phase == .carried and (if (is_bomb) objective.team == session.team else objective.team != session.team)) {
                rank = 1; // Escort the teammate carrying our objective.
            }
        }
        if (held != null) if (world.get(entity, data.MapObject) catch null) |object| if (std.mem.eql(u8, object.classname, "trigger_capture") and @import("../domain/multiplayer.zig").acceptsCapture(object.flags, session.team, is_bomb)) {
            point = routes.center(world, entity) catch continue;
            rank = 3;
        };
        if (rank == 0) continue;
        const distance = v.length(v.subtract(point, origin));
        if (rank > priority or (rank == priority and distance < nearest)) {
            nearest = distance;
            priority = rank;
            chosen = point;
        }
    };
    return chosen;
}

test "bot resupply routes to a standing origin without moving or granting the weapon" {
    const t = std.testing;
    const Fake = struct {
        calls: usize = 0,
        one_way: bool = false,
        fn next(raw: *anyopaque, request: nav.Request) !?nav.Waypoint {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            // Reproduce the floor weapon: raw model height 112 has no reachable
            // player area; feet at 113 require a player origin at 137.
            if (request.destination[2] != 137) return null;
            if (self.one_way and request.destination[0] == 0) return null;
            return .{ .point = request.destination };
        }
    };
    var fake: Fake = .{};
    const service: nav.Service = .{ .context = &fake, .next_fn = Fake.next };
    var world = data.World.init(t.allocator, 8);
    defer world.deinit();
    const player = try world.create(1, .{ data.Transform{ .position = .{ 0, 0, 137 } }, data.Body{ .mins = .{ -15, -15, -24 } }, data.Binding{ .slot = 0 }, data.Health{}, data.Keys{}, data.Weapons{ .dk3Inventory = 1 << 1 }, data.Character{}, data.Ailments{} });
    const item = try world.create(14, .{ data.Transform{ .position = .{ 128, 0, 112 } }, data.Body{ .mins = .{ -8, -8, 1 } }, data.Pickup{ .kind = .{ .weapon = 2 } } });
    var table: @import("../domain/weapons.zig").Table = .{};
    table.entries[2] = .{ .damage = 15, .range = 1800, .ammoCost = 1, .initialAmmo = 20, .ammoMax = 100 };
    try t.expectEqual(@as(u32, 14), try pickupGoal(&world, player, &table, service, 0, true, 100));
    try t.expectEqual(@as(usize, 2), fake.calls);
    try t.expectEqual(@as(i32, 1 << 1), (try world.get(player, data.Weapons)).dk3Inventory);
    try t.expectEqual(@as(f32, 112), (try world.get(item, data.Transform)).position[2]);
    fake.one_way = true;
    try t.expectEqual(@as(u32, 0), try pickupGoal(&world, player, &table, service, 0, true, 100));
    try t.expectEqual(@as(u32, 0), try pickupGoal(&world, player, &table, service, 14, true, 100));
    (try world.get(item, data.Pickup)).visible = false;
    try t.expectEqual(@as(u32, 0), try pickupGoal(&world, player, &table, service, 0, true, 100));
    try t.expectEqual(@as(usize, 4), fake.calls);
}

test "only a living teammate can reserve an authored control route" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 4);
    defer world.deinit();
    var clients: Clients = .{};
    clients.entities[0] = try world.create(1, .{data.Session{ .team = .red }});
    const helper = try world.create(2, .{ data.Session{ .team = .red }, data.Health{} });
    clients.entities[1] = helper;
    var state: State = .{};
    state.brains[1] = .{ .control = .{ .id = 507, .obstacle = 321, .route_obstacle = 110, .point = @splat(0), .action = .use } };
    try t.expect(state.assigned(&world, &clients, 0, 110));
    try t.expect(!state.assigned(&world, &clients, 1, 110));
    try t.expect(!state.assigned(&world, &clients, 0, 319));
    (try world.get(helper, data.Health)).current = 0;
    try t.expect(!state.assigned(&world, &clients, 0, 110));
    (try world.get(helper, data.Health)).current = 100;
    (try world.get(helper, data.Session)).team = .blue;
    try t.expect(!state.assigned(&world, &clients, 0, 110));
    (try world.get(helper, data.Session)).team = .red;
    state.brains[1].?.control = null;
    try t.expect(!state.assigned(&world, &clients, 0, 110));
}
