// SPDX-License-Identifier: GPL-2.0-or-later
//! Native match lifecycle, teams, scoring and authored objective geometry.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/multiplayer.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const c = abi.c;
pub fn enabled() bool {
    return engine.integer("g_gametype") != c.GT_SINGLE_PLAYER;
}
pub fn teams() bool {
    return engine.integer("g_gametype") >= c.GT_TEAM;
}
fn bomb() bool {
    return engine.integer("g_gametype") == c.GT_DK3_DEATHTAG;
}
fn objectiveMode() bool {
    return engine.integer("g_gametype") == c.GT_CTF or bomb();
}
fn broadcast(text: [:0]const u8) void {
    _ = engine.gateway.call(c.G_SEND_SERVER_COMMAND, .{ @as(isize, -1), text.ptr });
}
pub fn chooseTeam(world: *data.World) rules.Team {
    if (!teams()) return .free;
    var counts: [2]usize = @splat(0);
    var query = world.queryAccess(data.World.mask(.{data.Session}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.Session)) |session| {
        if (session.team == .red) counts[0] += 1;
        if (session.team == .blue) counts[1] += 1;
    };
    return if (counts[0] <= counts[1]) .red else .blue;
}
pub fn spawnPose(world: *data.World, session: data.Session, slot: u16, serial: u32) !data.Transform {
    var best: ?data.Transform = null;
    var best_score: f32 = -std.math.inf(f32);
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject), view.read(data.Transform)) |entity, object, pose| {
        const team_spawn = if (session.team == .red) "info_player_team1" else "info_player_team2";
        const appropriate = if (objectiveMode() and session.team != .spectator) std.mem.eql(u8, object.classname, team_spawn) else std.mem.eql(u8, object.classname, "info_player_deathmatch") or std.mem.startsWith(u8, object.classname, "info_player_team");
        if (!appropriate) continue;
        var candidate = pose;
        candidate.position[2] += 9;
        const hit = try engine.collisionService().trace(.{ .start = candidate.position, .end = candidate.position, .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .slot = slot, .mask = c.MASK_SOLID });
        if (hit.start_solid or hit.all_solid) continue;
        var nearest: f32 = 65536;
        var people = world.queryAccess(data.World.mask(.{ data.Player, data.Transform, data.Health }), 0, 0);
        {
            defer people.deinit();
            while (people.next()) |row| for (row.entities(), row.read(data.Player), row.read(data.Transform), row.read(data.Health)) |person, player, point, health| {
                if (player.mode == .spectator or health.current <= 0 or (try world.get(person, data.Binding)).slot == slot) continue;
                nearest = @min(nearest, v.length(v.subtract(point.position, candidate.position)));
            };
        }
        const id = try world.persistentId(entity);
        const tie: f32 = @as(f32, @floatFromInt((id *% 1664525 +% serial *% 1013904223) & 1023)) / 1024;
        const score = nearest + tie;
        if (score > best_score) {
            best = candidate;
            best_score = score;
        }
    };
    return best orelse error.MissingMultiplayerSpawn;
}
pub fn telefrag(world: *data.World, entity: ecs.Entity, now: i64) !void {
    const pose = (try world.get(entity, data.Transform)).*;
    const id = try world.persistentId(entity);
    var occupants: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var people = world.queryAccess(data.World.mask(.{ data.Player, data.Transform, data.Health }), 0, 0);
        defer people.deinit();
        while (people.next()) |row| for (row.entities(), row.read(data.Transform)) |other, point| {
            if (other.index == entity.index) continue;
            const delta = v.subtract(point.position, pose.position);
            if (@abs(delta[0]) < 30 and @abs(delta[1]) < 30 and @abs(delta[2]) < 56) {
                occupants[count] = other;
                count += 1;
            }
        };
    }
    for (occupants[0..count]) |other| _ = try @import("damage.zig").apply(world, other, 100000, now, .{ .source = id, .bypass_armor = true, .bypass_protection = true });
}
pub const State = struct {
    warmup: bool = false,
    started_ms: i64 = 0,
    intermission_ms: ?i64 = null,
    next_score_ms: i64 = 0,
    score: [2]i32 = @splat(0),
    pub fn spawn(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, episode: u8, now: i64) !void {
        _ = episode;
        self.* = .{ .started_ms = now };
        if (!enabled()) return;
        engine.register("fraglimit", "20", c.CVAR_SERVERINFO);
        engine.register("capturelimit", "8", c.CVAR_SERVERINFO);
        engine.register("timelimit", "10", c.CVAR_SERVERINFO);
        engine.register("dm_falling_damage", "1", c.CVAR_SERVERINFO | c.CVAR_LATCH);
        engine.register("g_friendlyFire", "0", c.CVAR_SERVERINFO);
        engine.register("g_forcerespawn", "20", 0);
        engine.config(c.CS_INTERMISSION, "0");
        if (!objectiveMode()) return;
        var candidates: [ecs.max_entities]ecs.Entity = undefined;
        var count: usize = 0;
        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
        {
            defer query.deinit();
            while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.mem.eql(u8, object.classname, "item_flag_team1") or std.mem.eql(u8, object.classname, "item_flag_team2")) {
                candidates[count] = entity;
                count += 1;
            };
        }
        var found: [2]bool = @splat(false);
        for (candidates[0..count]) |entity| {
            const object = (try world.get(entity, data.MapObject)).*;
            const red = std.mem.eql(u8, object.classname, "item_flag_team1");
            const index: usize = if (red) 0 else 1;
            if (found[index]) return error.DuplicateTeamObjective;
            found[index] = true;
            const pose = (try world.get(entity, data.Transform)).*;
            const model = if (bomb()) rules.pack_model else rules.flag_model;
            const team: rules.Team = if (red) .red else .blue;
            const supplied_color = try @import("properties.zig").number(object, "flagcolor", 0);
            const tint = rules.color(team, if (supplied_color >= 1 and supplied_color < 9) @intFromFloat(supplied_color) else 0);
            const slot = try slots.acquire(entity, null);
            try world.put(entity, data.Binding{ .slot = slot, .model = try @import("resources.zig").model(model) });
            try world.put(entity, data.Body{ .mins = .{ -10, -10, -10 }, .maxs = .{ 10, 8, 10 }, .contents = c.CONTENTS_TRIGGER });
            try world.put(entity, data.Objective{ .team = team, .color = tint, .home = pose.position, .angles = pose.angles, .airborne = true, .stepped_ms = now });
            try project(world, projections, entity);
        }
        if (!found[0] or !found[1]) return error.MissingTeamObjective;
    }
    pub fn step(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, now: i64) !void {
        if (!enabled()) return;
        if (self.warmup) {
            self.started_ms = now;
            return;
        }
        if (self.intermission_ms) |since| {
            if (now - since >= 10000) {
                var next: [256]u8 = @splat(0);
                _ = engine.gateway.call(c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "nextmap"), &next, @as(isize, next.len) });
                const command: [:0]const u8 = if (next[0] == 0) "map_restart 0\n" else "vstr nextmap\n";
                _ = engine.gateway.call(c.G_SEND_CONSOLE_COMMAND, .{ @as(isize, c.EXEC_APPEND), command.ptr });
                self.intermission_ms = now + 3600000;
            }
            return;
        }
        if (objectiveMode()) {
            const occupants = slots.occupants;
            for (occupants) |occupant| {
                const entity = occupant orelse continue;
                if ((world.get(entity, data.Objective) catch null) == null) continue;
                try self.objective(world, slots, projections, router, entity, now);
            }
        }
        if (now >= self.next_score_ms) {
            self.next_score_ms = now + 1000;
            var buffer: [64]u8 = undefined;
            engine.config(c.CS_SCORES1, try std.fmt.bufPrintZ(&buffer, "{d}", .{self.score[0]}));
            engine.config(c.CS_SCORES2, try std.fmt.bufPrintZ(&buffer, "{d}", .{self.score[1]}));
            var highest: i32 = 0;
            var query = world.queryAccess(data.World.mask(.{data.Session}), 0, 0);
            {
                defer query.deinit();
                while (query.next()) |view| for (view.read(data.Session)) |session| {
                    highest = @max(highest, session.score);
                };
            }
            const time_limit = engine.integer("timelimit");
            const score_limit = engine.integer(if (objectiveMode() and !bomb()) "capturelimit" else "fraglimit");
            const reached = score_limit > 0 and (if (objectiveMode()) @max(self.score[0], self.score[1]) else highest) >= score_limit;
            const rotation_seconds = engine.integer("dk3_rotationSeconds");
            const rotation_due = rotation_seconds > 0 and now - self.started_ms >= @as(i64, rotation_seconds) * 1000;
            if (reached or rotation_due or (time_limit > 0 and now - self.started_ms >= @as(i64, time_limit) * 60000)) {
                self.intermission_ms = now;
                engine.config(c.CS_INTERMISSION, "1");
                broadcast("cp \"Match complete\"");
                for (slots.occupants[0..c.MAX_CLIENTS]) |occupant| if (occupant) |player| {
                    try @import("weapon_actions.zig").cancel(world, slots, projections, player);
                    (try world.get(player, data.Player)).mode = .frozen;
                    (try world.get(player, data.Velocity)).linear = @splat(0);
                };
            }
        }
    }
    fn objective(self: *State, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, entity: ecs.Entity, now: i64) !void {
        var state = (try world.get(entity, data.Objective)).*;
        var pose = (try world.get(entity, data.Transform)).*;
        if (state.carrier) |id| {
            const carrier = world.find(id);
            if (carrier == null or !living(world, carrier.?)) {
                state.drop(bomb(), now);
                toss(&state, try world.persistentId(entity), now);
            } else {
                const carrier_pose = (try world.get(carrier.?, data.Transform)).*;
                pose.position = carrier_pose.position;
                pose.angles = .{ 0, carrier_pose.angles[1], 0 };
                const session = (try world.get(carrier.?, data.Session)).*;
                const carrier_slot = (try world.get(carrier.?, data.Binding)).slot;
                for (slots.occupants) |other| {
                    const zone = other orelse continue;
                    const object = world.get(zone, data.MapObject) catch continue;
                    if (!std.mem.eql(u8, object.classname, "trigger_capture")) continue;
                    if (!rules.acceptsCapture(object.flags, session.team, bomb())) continue;
                    const zone_slot = (try world.get(zone, data.Binding)).slot;
                    if (!@import("interactions.zig").overlap(&projections[carrier_slot], &projections[zone_slot], 0)) continue;
                    if (!bomb() and !home(world, session.team)) continue;
                    const points_float = if (bomb()) try @import("properties.zig").number(object.*, "points", 1) else 1;
                    if (points_float < 1 or points_float > 100) return error.InvalidCapturePoints;
                    const points: i32 = @intFromFloat(points_float);
                    self.score[if (session.team == .red) @as(usize, 0) else 1] += points;
                    const member = try world.get(carrier.?, data.Session);
                    if (!bomb()) member.score += 5;
                    member.captures += 1;
                    if (!bomb()) try captureBonuses(world, carrier.?, zone, session.team);
                    state.capture(bomb(), now);
                    if (!bomb()) {
                        pose.position = state.home;
                        pose.angles = state.angles;
                        state.airborne = true;
                        state.stepped_ms = now;
                    }
                    try @import("events.zig").sound(world, slots, projections, "global/bossdeath6.wav", carrier_pose.position, carrier_slot, c.CHAN_ANNOUNCER, now);
                    if (bomb()) pose.position = v.scale(v.add(projections[zone_slot].shared.absmin, projections[zone_slot].shared.absmax), 0.5);
                    (try world.get(entity, data.Objective)).* = state;
                    try router.fire(world, slots, projections, zone, id, now);
                    broadcast(if (session.team == .red) "cp \"Red team scores\"" else "cp \"Blue team scores\"");
                    break;
                }
            }
        }
        try flight(world, entity, &state, &pose, now);
        // Publish the newly dropped position before testing contact this frame.
        (try world.get(entity, data.Objective)).* = state;
        (try world.get(entity, data.Transform)).* = pose;
        try project(world, projections, entity);
        if (state.phase == .home or state.phase == .dropped) {
            const slot = (try world.get(entity, data.Binding)).slot;
            for (slots.occupants[0..c.MAX_CLIENTS]) |occupant| {
                const player = occupant orelse continue;
                if (!living(world, player)) continue;
                const player_slot = (try world.get(player, data.Binding)).slot;
                if (!@import("interactions.zig").overlap(&projections[slot], &projections[player_slot], 0)) continue;
                const id = try world.persistentId(player);
                const team = (try world.get(player, data.Session)).team;
                // A carrier can return its own dropped flag without giving up the
                // enemy flag. Holding an objective only excludes another pickup.
                if (held(world, id) != null and (bomb() or state.team != team)) continue;
                const was_home = state.phase == .home;
                switch (state.take(id, team, bomb(), now)) {
                    .none => {},
                    .returned => {
                        pose.position = state.home;
                        pose.angles = state.angles;
                        state.airborne = true;
                        state.stepped_ms = now;
                        (try world.get(player, data.Session)).score += 1;
                        try @import("events.zig").sound(world, slots, projections, "global/a_hpick.wav", pose.position, player_slot, c.CHAN_ANNOUNCER, now);
                    },
                    .taken => {
                        try @import("events.zig").sound(world, slots, projections, "global/a_hpick.wav", pose.position, player_slot, c.CHAN_ITEM, now);
                        if (!bomb() or was_home) try @import("events.zig").sound(world, slots, projections, "global/e_alarmb.wav", pose.position, player_slot, c.CHAN_AUTO, now);
                    },
                    .detonate => state.deadline = now,
                }
                if (state.phase == .carried or state.phase == .home) break;
            }
        }
        if (bomb() and state.tick(now)) {
            const subject: u16 = if (state.carrier) |id| if (world.find(id)) |carrier| (try world.get(carrier, data.Binding)).slot else c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
            try @import("events.zig").sound(world, slots, projections, "global/a_ames.wav", pose.position, subject, c.CHAN_AUTO, now);
            if (state.carrier != null) try @import("events.zig").sound(world, slots, projections, "artifacts/goldensoulwait.wav", pose.position, subject, c.CHAN_BODY, now);
        }
        if (state.deadline) |deadline| if (now >= deadline) {
            if (!bomb() or state.phase == .resetting) {
                state.reset();
                pose.position = state.home;
                pose.angles = state.angles;
                state.airborne = true;
                state.stepped_ms = now;
                try @import("events.zig").sound(world, slots, projections, "global/a_hpick.wav", state.home, c.ENTITYNUM_NONE, c.CHAN_ANNOUNCER, now);
            } else {
                state.carrier = null;
                state.phase = .resetting;
                state.deadline = now + 10000;
                state.airborne = false;
                try @import("events.zig").sound(world, slots, projections, "global/e_explode1.wav", pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
                try @import("scenery.zig").explosion(world, slots, projections, pose.position, 1.4, now);
                for (slots.occupants[0..c.MAX_CLIENTS]) |occupant| if (occupant) |player| if (living(world, player) and v.length(v.subtract((try world.get(player, data.Transform)).position, pose.position)) < 400) {
                    _ = try @import("damage.zig").apply(world, player, 1000, now, .{ .source = try world.persistentId(player) });
                };
            }
        };
        if (state.phase == .home and state.deadline == null and !state.airborne) {
            pose.angles = state.angles;
        }
        (try world.get(entity, data.Objective)).* = state;
        (try world.get(entity, data.Transform)).* = pose;
        try project(world, projections, entity);
        var flags: [3:0]u8 = .{ '0', '0', 0 };
        var query = world.queryAccess(data.World.mask(.{data.Objective}), 0, 0);
        {
            defer query.deinit();
            while (query.next()) |view| for (view.read(data.Objective)) |flag| {
                flags[if (flag.team == .red) @as(usize, 0) else 1] = switch (flag.phase) {
                    .home => '0',
                    .carried => '1',
                    else => '2',
                };
            };
        }
        engine.config(c.CS_FLAGSTATUS, flags[0..2 :0]);
    }
};
/// Drop at the carrier's actual last position before the entity is removed.
pub fn release(world: *data.World, projections: []abi.EntityProjection, player: ecs.Entity, now: i64) !void {
    const id = try world.persistentId(player);
    const origin = (try world.get(player, data.Transform)).position;
    var query = world.queryAccess(data.World.mask(.{ data.Objective, data.Transform, data.Binding }), 0, data.World.mask(.{ data.Objective, data.Transform }));
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.write(data.Objective), view.write(data.Transform), view.read(data.Binding)) |entity, *state, *pose, binding| {
        if (state.carrier != id) continue;
        state.drop(bomb(), now);
        _ = binding;
        pose.position = origin;
        pose.angles = .{ 0, (try world.get(player, data.Transform)).angles[1], 0 };
        toss(state, try world.persistentId(entity), now);
        try project(world, projections, entity);
    };
}
fn living(world: *data.World, entity: ecs.Entity) bool {
    const player = world.get(entity, data.Player) catch return false;
    const session = world.get(entity, data.Session) catch return false;
    return player.mode == .normal and session.team != .spectator and (world.get(entity, data.Health) catch return false).current > 0;
}
fn home(world: *data.World, team: rules.Team) bool {
    var query = world.queryAccess(data.World.mask(.{data.Objective}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.Objective)) |objective| if (objective.team == team) return objective.phase == .home;
    return false;
}
pub fn held(world: *data.World, id: u32) ?data.Objective {
    var query = world.queryAccess(data.World.mask(.{data.Objective}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.Objective)) |objective| if (objective.carrier == id) return objective;
    return null;
}
fn project(world: *data.World, projections: []abi.EntityProjection, entity: ecs.Entity) !void {
    const state = (try world.get(entity, data.Objective)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const body = (try world.get(entity, data.Body)).*;
    const projection = &projections[binding.slot];
    projection.* = std.mem.zeroes(abi.EntityProjection);
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_DK3_ITEM;
    projection.state.modelindex = binding.model;
    projection.state.dk3Team = @intFromEnum(state.team);
    projection.state.generic1 = if (bomb()) 0 else rules.color(state.team, state.color);
    projection.state.frame = rules.stand_frame;
    if (state.carrier) |id| if (world.find(id)) |player| {
        projection.state.frame = rules.carry_frames[@import("appearance_catalog").character((try world.get(player, data.Session)).appearance)];
    };
    projection.state.dk3Carrier = if (state.carrier) |id| if (world.find(id)) |player| @as(i32, (try world.get(player, data.Binding)).slot) + 1 else 0 else 0;
    projection.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = if (state.phase == .home or state.phase == .dropped) c.CONTENTS_TRIGGER else 0;
    projection.shared.svFlags = if (state.phase == .resetting) c.SVF_NOCLIENT else 0;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}

fn toss(state: *data.Objective, id: u32, now: i64) void {
    var random: data.Random = .{ .state = id ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) };
    state.velocity = .{ random.next() * 400 - 200, random.next() * 400 - 200, random.next() * 250 + 250 };
}
fn flight(world: *data.World, entity: ecs.Entity, state: *data.Objective, pose: *data.Transform, now: i64) !void {
    if (!state.airborne) return;
    const body = (try world.get(entity, data.Body)).*;
    const slot = (try world.get(entity, data.Binding)).slot;
    while (state.stepped_ms < now and state.airborne) {
        const elapsed = @min(now - state.stepped_ms, 50);
        const seconds = @as(f32, @floatFromInt(elapsed)) * 0.001;
        state.stepped_ms += elapsed;
        var end = v.add(pose.position, v.scale(state.velocity, seconds));
        end[2] -= 400 * seconds * seconds;
        state.velocity[2] -= 800 * seconds;
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = end, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID });
        if (hit.start_solid or hit.all_solid) {
            // An obstructed throw must not place an objective through a wall.
            state.velocity = @splat(0);
            state.airborne = false;
            break;
        }
        pose.position = hit.end;
        if (hit.fraction < 1) {
            state.velocity = @import("../domain/scenery.zig").contact(state.velocity, hit.normal, false);
            if (hit.normal[2] > 0.7) {
                state.airborne = false;
                state.velocity = @splat(0);
            }
        }
    }
}
fn captureBonuses(world: *data.World, capturer: ecs.Entity, zone: ecs.Entity, team: rules.Team) !void {
    var query = world.queryAccess(data.World.mask(.{ data.Session, data.Transform, data.Binding }), 0, data.World.mask(.{data.Session}));
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.write(data.Session)) |player, *member| {
        if (member.team != team) continue;
        member.score += 5;
        if (player.index == capturer.index) continue;
        if (try @import("ctf_scoring.zig").visible(world, zone, player)) member.score += 1;
    };
}

pub fn teamColor(world: *data.World, team: rules.Team) u8 {
    var query = world.queryAccess(data.World.mask(.{data.Objective}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.Objective)) |objective| if (objective.team == team) return rules.color(team, objective.color);
    return rules.color(team, 0);
}

test "spawn telefrag kills overlapping occupants but preserves newcomer and distant players" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 3);
    defer world.deinit();
    const newcomer = try world.create(1, .{ data.Player{}, data.Transform{}, data.Health{ .current = 100, .maximum = 100 } });
    const occupant = try world.create(2, .{ data.Player{}, data.Transform{ .position = .{ 15, 0, 0 } }, data.Health{ .current = 100, .maximum = 100 }, data.Hurt{}, data.Character{ .invincible_until = 10000 } });
    const distant = try world.create(3, .{ data.Player{}, data.Transform{ .position = .{ 100, 0, 0 } }, data.Health{ .current = 100, .maximum = 100 } });
    try telefrag(&world, newcomer, 1000);
    try t.expectEqual(.dead, (try world.get(occupant, data.Player)).mode);
    try t.expectEqual(@as(u32, 1), (try world.get(occupant, data.Hurt)).source);
    try t.expectEqual(@as(i32, 100), (try world.get(newcomer, data.Health)).current);
    try t.expectEqual(@as(i32, 100), (try world.get(distant, data.Health)).current);
}
