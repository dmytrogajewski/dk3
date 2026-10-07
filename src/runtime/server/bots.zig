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
const skill = @import("../domain/bot_skill.zig");
const pilot = @import("bot_pilot.zig");
const Brain = struct {
    next_ms: i64 = 0,
    /// Pickup being fetched, until when it is reconsidered, and one let be.
    goal: u32 = 0,
    goal_ms: i64 = 0,
    avoided: u32 = 0,
    avoid_until: i64 = 0,
    /// The objective (or the carrier escorted) has no route even past every
    /// gate: pursue items and enemies meanwhile.
    objective_skip_until: i64 = 0,
    /// Where the enemy fought was last seen (chased when nothing else calls).
    last_seen: ?v.Vec3 = null,
    /// Where the current firing stand began (a held fight in deathmatch).
    stand: ?v.Vec3 = null,
    skill: i32 = skill.fallback,
    /// Locomotion, perception, aim and fire: the shared bot pilot.
    pilot: pilot.Pilot = .{},
    report: pilot.Report = .{},
    /// Cone actually in force on the last brain step, so the override shows up in evidence.
    cone: f32 = 0,
    fn reset(self: *Brain, now: i64) void {
        var fresh = self.pilot;
        fresh.reset();
        fresh.receipt = null;
        self.* = .{ .next_ms = now + 50, .skill = self.skill, .pilot = fresh };
    }
};
pub const State = struct {
    brains: [c.MAX_CLIENTS]?Brain = @splat(null),
    next_population: i64 = 0,
    serial: usize = 0,
    ladder: i32 = 0,
    /// Read-only route evidence for normal-input match diagnostics.
    pub fn report(self: *const State, world: *data.World, slots: *const Slots, clients: *const Clients, now: i64) !void {
        var buffer: [1024]u8 = undefined;
        for (self.brains, 0..) |maybe, index| if (maybe) |brain| {
            const route = brain.pilot.route;
            const waypoint = route.waypoint orelse nav.Waypoint{ .point = @splat(0) };
            // The view is what the cone is measured against, so it must be visible in the evidence.
            var view_yaw: f32 = std.math.nan(f32);
            var view_pitch: f32 = std.math.nan(f32);
            if (clients.entities[index]) |entity| if (world.get(entity, data.Transform) catch null) |pose| {
                view_yaw = pose.angles[1];
                view_pitch = pose.angles[0];
            };
            engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 bot route: slot={d} skill={d} ({s}) fov={d:.0} view={d:.1},{d:.1} scan={d} alert={d} target={d} seen_ms={d} goal={d} avoided={d} destination={d:.2},{d:.2},{d:.2} waypoint={d:.2},{d:.2},{d:.2} valid={d} areas={d},{d} jump={d} crouch={d} ladder={d} blocked={d} progress_ms={d} refresh_ms={d} jump_until={d} control={d} yielding={d} passage={d}\n", .{
                index,                                                                        brain.skill,                                          skill.tier(brain.skill),
                if (brain.cone > 0) brain.cone else skill.profile(brain.skill).field_of_view, view_yaw,                                             view_pitch,
                pilot.sweep_headings[brain.pilot.sweep_index],                                @intFromBool(now < brain.pilot.alert_until),          brain.pilot.target,
                brain.pilot.seen_ms,                                                          brain.goal,                                           brain.avoided,
                route.destination[0],                                                         route.destination[1],                                 route.destination[2],
                waypoint.point[0],                                                            waypoint.point[1],                                    waypoint.point[2],
                @intFromBool(route.waypoint != null),                                         waypoint.from_area,                                   waypoint.to_area,
                @intFromBool(waypoint.jump),                                                  @intFromBool(waypoint.crouch),                        @intFromBool(waypoint.ladder),
                @intFromBool(route.blocked),                                                  route.progress_ms,                                    route.refresh_ms,
                brain.pilot.jump_until,                                                       if (brain.pilot.control) |control| control.id else 0, @intFromBool(brain.pilot.yield_point != null),
                if (brain.pilot.passage) |passage| passage.route.id else 0,
            }));
            engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 bot pilot: slot={d} hazard={d} dodging={d} stand={d} no_route={d} routeless={d} give_up={d} skip_ms={d}\n", .{ index, brain.report.avoided_exit, @intFromBool(brain.report.dodging), @intFromBool(brain.stand != null), @intFromBool(brain.report.no_route), @intFromBool(brain.report.routeless), brain.report.give_up_ms, @max(0, brain.objective_skip_until - now) }));
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
        const text = try std.fmt.bufPrintZ(&info, "\\name\\Bot {d} {s}\\model\\{s}\\skill\\{d}\\dk3_runtime_build\\{s}", .{ self.serial + 1, skill.tier(self.ladder), appearance.selection, self.ladder, @import("../engine/player_state.zig").version });
        _ = engine.gateway.call(c.G_SET_USERINFO, .{ allocated, text.ptr });
        try clients.begin(world, slots, projections, states, index, now, null);
        (try world.get(clients.entities[index].?, data.Session)).bot = true;
        projections[index].shared.svFlags |= c.SVF_BOT;
        self.brains[index] = .{ .skill = self.ladder, .pilot = .{ .level = self.ladder, .seed = @as(u32, @truncate(@as(u64, @bitCast(now)) + index * 7919 + 1)), .step_ms = now } };
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
            const control = brain.pilot.control orelse continue;
            if (control.route_obstacle != obstacle) continue;
            if ((world.get(other, data.Health) catch continue).current <= 0) continue;
            const session = (world.get(other, data.Session) catch continue).*;
            if (@import("../domain/multiplayer.zig").allied(team, session)) return true;
        }
        return false;
    }
    pub fn step(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, states: []c.playerState_t, clients: *Clients, router: *@import("targets.zig").Router, service: nav.Service, gates: *@import("navigation_gates.zig").State, now: i64) !void {
        _ = router;
        if (!@import("multiplayer.zig").enabled()) return;
        engine.register("bot_minplayers", "0", 0);
        engine.register("dk3_bot_skill", "5", c.CVAR_SERVERINFO);
        engine.register("dk3_bot_fov", "0", 0);
        const level = skill.normalize(engine.integer("dk3_bot_skill"));
        if (now >= self.next_population) {
            self.next_population = now + 1000;
            if (self.ladder != 0 and self.ladder != level) for (&self.brains) |*maybe| if (maybe.*) |*brain| {
                brain.skill = level;
                brain.pilot.level = level;
                brain.pilot.target = 0;
                brain.pilot.alert_until = 0;
                brain.last_seen = null;
            };
            self.ladder = level;
            // Multiplayer maps have no other difficulty writer, so the ten-level
            // ladder also sets the five-level scale used by authored actors here.
            const actor = skill.singlePlayer(level);
            if (engine.integer("g_spSkill") != actor) {
                var scale: [16]u8 = undefined;
                _ = engine.gateway.call(c.G_CVAR_SET, .{ @as([*:0]const u8, "g_spSkill"), (try std.fmt.bufPrintZ(&scale, "{d}", .{actor})).ptr });
            }
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
            if (player.mode == .dead) {
                brain.reset(now);
                var steering = try brain.pilot.steer(try self.frame(world, slots, projections, clients, service, gates, index, entity, player, session, now), .{ .attack_when_dead = true });
                // A dead player requests respawn with attack on every step.
                steering.command.attack = true;
                @import("bot_input.zig").submit(@intCast(index), steering.command, player.delta_angles, now);
                continue;
            }
            brain.pilot.level = brain.skill;
            const fov = engine.integer("dk3_bot_fov");
            brain.cone = if (fov > 0) std.math.clamp(@as(f32, @floatFromInt(fov)), 1, 359) else skill.profile(brain.skill).field_of_view;
            const policy = skill.profile(brain.skill);
            // The enemy fought last step: remembered where it was, then forgotten.
            if (brain.report.enemy != 0) {
                if (world.find(brain.report.enemy)) |seen| brain.last_seen = (try world.get(seen, data.Transform)).position;
            } else if (now - brain.pilot.seen_ms > policy.memory_ms) brain.last_seen = null;
            const loadout = (try world.get(entity, data.Weapons)).*;
            var destination: ?v.Vec3 = null;
            var objective = false;
            if (now >= brain.objective_skip_until) if (objectiveGoal(world, entity)) |goal| {
                destination = goal;
                objective = true;
            };
            const health = (try world.get(entity, data.Health)).*;
            const resupply = health.current * 2 < health.maximum or !@import("../domain/bot_combat.zig").ranged(loadout, &clients.weapon_table);
            if (resupply) {
                destination = null;
                objective = false;
            }
            const old_pickup = if (world.find(brain.goal)) |goal| world.get(goal, data.Pickup) catch null else null;
            if (destination == null and (now >= brain.goal_ms or old_pickup == null or !old_pickup.?.visible)) {
                brain.goal = try pickupGoal(world, entity, &clients.weapon_table, service, if (now < brain.avoid_until) brain.avoided else 0, resupply, now);
                brain.goal_ms = now + 5000;
            }
            var fetching = false;
            if (destination == null) if (world.find(brain.goal)) |goal| {
                destination = @import("../domain/navigation_input.zig").pickupPoint((try world.get(goal, data.Transform)).position, (try world.get(goal, data.Body)).mins, (try world.get(entity, data.Body)).mins);
                fetching = true;
            };
            if (destination == null and resupply) destination = objectiveGoal(world, entity);
            if (destination == null) if (brain.pilot.target != 0) {
                destination = brain.last_seen;
            };
            var intent: pilot.Intent = .{ .destination = destination, .engage_range = std.math.inf(f32) };
            // Deathmatch stance: an enemy in sight is fought from a firing
            // stand, strafing on a short tether; objectives and resupply keep
            // moving and fight on the way.
            if (brain.report.enemy != 0 and !objective and !resupply) {
                if (brain.stand == null) brain.stand = pose.position;
                intent.destination = null;
                intent.leash = brain.stand;
            } else brain.stand = null;
            const steering = try brain.pilot.steer(try self.frame(world, slots, projections, clients, service, gates, index, entity, player, session, now), intent);
            brain.report = steering.report;
            if (steering.report.give_up_ms > 0) brain.objective_skip_until = now + steering.report.give_up_ms;
            // A pickup the route cannot get closer to is let be for a while.
            if (fetching and brain.pilot.control == null and steering.report.blocked and now - brain.pilot.route.progress_ms >= 3000) {
                brain.avoided = brain.goal;
                brain.avoid_until = now + 10000;
                brain.goal = 0;
                brain.goal_ms = now;
            }
            if (fetching and destination != null and v.length(v.subtract(destination.?, pose.position)) < 32) {
                brain.goal = 0;
                brain.goal_ms = now;
            }
            if (steering.command.use and engine.integer("developer") > 0) if (brain.pilot.control) |control| {
                engine.print(try std.fmt.bufPrintZ(&message, "dk3 bot control: slot={d} use={d} obstacle={d} route_obstacle={d}\n", .{ index, control.id, control.obstacle, control.route_obstacle }));
            };
            @import("bot_input.zig").submit(@intCast(index), steering.command, player.delta_angles, now);
        }
    }
    /// The pilot's view of a bot client: its player state, the engine's
    /// collision and the client weapon table; enemy players by team, team
    /// coordination over authored controls, looking around and turning to
    /// gunfire as the ladder sets.
    fn frame(self: *const State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, clients: *Clients, service: nav.Service, gates: *@import("navigation_gates.zig").State, index: usize, entity: ecs.Entity, player: data.Player, session: data.Session, now: i64) !pilot.Frame {
        const brain = self.brains[index].?;
        const team = struct {
            var contexts: [c.MAX_CLIENTS]Team = undefined;
        };
        team.contexts[index] = .{ .state = self, .world = world, .clients = clients, .index = index };
        return .{
            .world = world,
            .slots = slots,
            .projections = projections,
            .service = service,
            .collision = engine.collisionService(),
            .table = &clients.weapon_table,
            .slot = @intCast(index),
            .entity = entity,
            .state = player,
            .now = now,
            .gates = gates,
            .capabilities = .{ .exits = false, .nuisance = false, .alert = true, .sweep = true, .conserve_ammo = false, .yield_to_allies = true, .duck_to_shoot = false },
            .targets = .{ .players = .{ .entities = &clients.entities, .session = session } },
            .coordination = .{ .context = &team.contexts[index], .claimed = Team.claimed },
            .field_of_view = brain.cone,
            // Objectives sit beside lethal beams (e1dt1's bomb is 28 units
            // from one): a narrower margin, still clear of contact.
            .lethal_margin = 16,
            .label = "bot",
        };
    }
};
/// A teammate (another bot) already fetching the control that opens a gate.
const Team = struct {
    state: *const State,
    world: *data.World,
    clients: *const Clients,
    index: usize,
    fn claimed(context: *const anyopaque, route_obstacle: u32) bool {
        const self: *const Team = @ptrCast(@alignCast(context));
        return self.state.assigned(self.world, self.clients, self.index, route_obstacle);
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
    state.brains[1] = .{ .pilot = .{ .control = .{ .id = 507, .obstacle = 321, .route_obstacle = 110, .point = @splat(0), .action = .use } } };
    try t.expect(state.assigned(&world, &clients, 0, 110));
    try t.expect(!state.assigned(&world, &clients, 1, 110));
    try t.expect(!state.assigned(&world, &clients, 0, 319));
    (try world.get(helper, data.Health)).current = 0;
    try t.expect(!state.assigned(&world, &clients, 0, 110));
    (try world.get(helper, data.Health)).current = 100;
    (try world.get(helper, data.Session)).team = .blue;
    try t.expect(!state.assigned(&world, &clients, 0, 110));
    (try world.get(helper, data.Session)).team = .red;
    state.brains[1].?.pilot.control = null;
    try t.expect(!state.assigned(&world, &clients, 0, 110));
}
