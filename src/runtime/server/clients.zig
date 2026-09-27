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
    returning: [c.MAX_CLIENTS]?data.Session = @splat(null),
    episode: u8 = 1,
    poses: [3]?@import("../domain/player_pose.zig").Set = @splat(null),
    pub fn begin(self: *Clients, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, states: []c.playerState_t, index: usize, now: i64, journey: ?@import("../domain/travel.zig").Journey) !void {
        if (index >= self.entities.len) return error.InvalidClient;
        var session: data.Session = .{ .team = @import("multiplayer.zig").chooseTeam(world), .joined_ms = now };
        if (self.returning[index]) |prior| {
            session = prior;
            session.respawn_ms = 0;
            self.returning[index] = null;
        }
        if (self.entities[index]) |previous| if (world.get(previous, data.Session) catch null) |member| {
            session = member.*;
            session.respawn_ms = 0;
            session.advancement = (try world.get(previous, data.Character)).advancement((try world.get(previous, data.Weapons)).dk3SwordExperience);
        };
        session.pose = .{};
        try self.disconnect(world, slots, projections, index, now);
        const multiplayer = @import("multiplayer.zig").enabled();
        const transform = if (multiplayer) try @import("multiplayer.zig").spawnPose(world, session, @intCast(index), session.deaths + @as(u32, @intCast(index))) else try arrivalPose(world, journey, @intCast(index));
        const entity = try world.create(null, .{ transform, data.Velocity{}, data.Player{ .command_ms = now, .respawned = true }, data.Health{}, data.Hurt{}, data.Keys{}, data.Character{}, data.Ailments{}, data.Body{ .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .contents = c.CONTENTS_BODY, .collision_mask = c.MASK_PLAYERSOLID }, data.Binding{ .slot = @intCast(index) }, data.Weapons{} });
        errdefer world.destroy(entity) catch unreachable;
        _ = try slots.acquire(entity, @intCast(index));
        self.entities[index] = entity;
        if (multiplayer) {
            try world.put(entity, session);
            try self.userinfo(world, index);
            const joined = try world.get(entity, data.Session);
            const advancement = joined.advancement orelse @import("../domain/multiplayer.zig").initialAdvancement(joined.appearance);
            joined.advancement = advancement;
            (try world.get(entity, data.Character)).* = data.Character.fromAdvancement(advancement);
            (try world.get(entity, data.Weapons)).dk3SwordExperience = advancement.sword;
            const maximum = 100 + 20 * advancement.attributes[@intFromEnum(@import("../domain/character.zig").Attribute.vita)];
            (try world.get(entity, data.Health)).* = .{ .current = maximum, .maximum = maximum };
            if (session.team == .spectator) {
                (try world.get(entity, data.Player)).mode = .spectator;
                (try world.get(entity, data.Body)).contents = 0;
            } else try @import("multiplayer.zig").telefrag(world, entity, now);
        }
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
        try self.publish(world, projections, states, index, now);
        engine.print("dk3 zig: player entered isolated movement runtime\n");
    }
    pub fn arrivalPose(world: *data.World, journey: ?@import("../domain/travel.zig").Journey, index: u16) !data.Transform {
        const spawn = try @import("spawns.zig").select(world, if (journey) |value| value.spawn else "");
        var transform = spawn.pose;
        transform.position[2] += 9;
        if (journey) |value| if (value.kind == .submap) {
            transform.angles = value.angles;
            if (spawn.flags & 1 == 0) {
                const position = @import("../domain/vector.zig").add(transform.position, value.offset);
                const clear = try engine.collisionService().trace(.{ .start = position, .end = position, .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .slot = index, .mask = c.MASK_PLAYERSOLID });
                if (!clear.start_solid and !clear.all_solid) transform.position = position else engine.print("dk3 travel: obstructed exit offset; using authored landing\n");
            }
        };
        return transform;
    }
    pub fn arrive(self: *Clients, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, states: []c.playerState_t, arrival: @import("campaign.zig").Arrival, actors: *@import("actors.zig").Actors, now: i64) !void {
        const entity = self.entities[0] orelse return error.MissingTraveler;
        const pose = try arrivalPose(world, arrival.journey, 0);
        try @import("monitors.zig").detach(world, entity);
        try @import("ballista.zig").detach(world, entity);
        try @import("weapon_actions.zig").cancel(world, slots, projections, entity);
        try arrival.traveler.apply(world, entity);
        (try world.get(entity, data.Transform)).* = pose;
        try @import("companions.zig").start(actors, world, slots, projections, entity, arrival.journey.spawn, if (arrival.journey.kind == .submap) arrival.journey.companions else null, now);
        try @import("companions.zig").arrive(actors, world, slots, projections, entity, arrival.traveler, arrival.journey, now);
        (try world.get(entity, data.Velocity)).* = .{};
        (try world.get(entity, data.Hurt)).* = .{};
        (try world.get(entity, data.Body)).* = .{ .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .contents = c.CONTENTS_BODY, .collision_mask = c.MASK_PLAYERSOLID };
        const player = try world.get(entity, data.Player);
        player.* = .{ .command_ms = now, .respawned = true };
        var input: c.usercmd_t = undefined;
        engine.usercmd(0, &input);
        for (pose.angles, 0..) |angle, i| player.delta_angles[i] = @as(i32, @intFromFloat(@mod(angle, 360) * (65536.0 / 360.0))) -% input.angles[i];
        self.episode = arrival.traveler.episode;
        try self.publish(world, projections, states, 0, now);
        try @import("campaign.zig").disarmArrival(world, projections, entity);
        engine.send(0, "dk3_restored");
        var text: [128]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig: traveler entered authored landing health={d} weapon={d}\n", .{ (try world.get(entity, data.Health)).current, (try world.get(entity, data.Weapons)).weapon }));
    }
    pub fn disconnect(self: *Clients, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, index: usize, now: i64) !void {
        if (index >= self.entities.len) return error.InvalidClient;
        if (self.entities[index]) |entity| {
            try @import("multiplayer.zig").release(world, projections, entity, now);
            try @import("monitors.zig").detach(world, entity);
            try @import("ballista.zig").detach(world, entity);
            try @import("weapon_actions.zig").cancel(world, slots, projections, entity);
            engine.unlink(&projections[index]);
            try slots.release(@intCast(index), entity);
            try world.destroy(entity);
            self.entities[index] = null;
        }
    }
    pub fn think(self: *Clients, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, states: []c.playerState_t, index: usize, now: i64) !void {
        if (index >= self.entities.len) return error.InvalidClient;
        const entity = self.entities[index] orelse return;
        var input: c.usercmd_t = undefined;
        engine.usercmd(@intCast(index), &input);
        if (world.get(entity, data.Session) catch null) |session| {
            const force = engine.integer("g_forcerespawn");
            if ((try world.get(entity, data.Player)).mode == .dead and (try world.get(entity, data.Hurt)).feedback.death_handled and now >= session.respawn_ms and ((input.buttons & c.BUTTON_ATTACK != 0 or input.upmove > 0) or (force > 0 and now >= session.respawn_ms + @as(i64, force) * 1000))) {
                return self.begin(world, slots, projections, states, index, now, null);
            }
        }
        input.serverTime = @intCast(std.math.clamp(@as(i64, input.serverTime), now - 1000, now + 200));
        const player = try world.get(entity, data.Player);
        bridge.holdView(player, (try world.get(entity, data.Transform)).angles, input);
        const command = bridge.command(input, &player.delta_angles);
        const character = (try world.get(entity, data.Character)).*;
        const ailments = (try world.get(entity, data.Ailments)).*;
        (try world.get(entity, data.Health)).maximum = 100 + 20 * character.attribute(.vita, now);
        if ((try world.get(entity, data.Health)).current <= 0) player.mode = if (ailments.petrified_frame != null) .frozen else .dead;
        if (command.time_ms <= player.command_ms) return;
        const transform = try world.get(entity, data.Transform);
        const velocity = try world.get(entity, data.Velocity);
        var motion: @import("../domain/slide.zig").State = .{ .position = transform.position, .velocity = velocity.linear };
        if (ailments.mask & 128 != 0) motion.velocity = @splat(0);
        var events: weapons.Events = .{};
        var weapon_context: weapons.Context = .{ .ps = try world.get(entity, data.Weapons), .healthy = (try world.get(entity, data.Health)).current > 0, .single_player = engine.integer("g_gametype") == c.GT_SINGLE_PLAYER, .table = &self.weapon_table, .events = &events, .service = engine.collisionService(), .slot = @intCast(index), .shot_mask = c.MASK_SHOT, .attack_boost = character.attribute(.attack, command.time_ms) };
        const result = try @import("../domain/player_move.zig").runWithHook(player, &motion, command, bridge.characterParameters(@intCast(index), character, ailments, command.time_ms), engine.collisionService(), weapon_context.hook());
        for (events.values[0..events.count], 0..) |event, i| {
            const sequence = weapon_context.ps.event_sequence -% @as(u32, @intCast(events.count - i));
            states[index].events[sequence & (c.MAX_PS_EVENTS - 1)] = switch (event) {
                .fired => c.EV_FIRE_WEAPON,
                .no_ammo => c.EV_NOAMMO,
            };
            states[index].eventParms[sequence & (c.MAX_PS_EVENTS - 1)] = switch (event) {
                .fired => |shot| shot.weapon,
                .no_ammo => 0,
            };
        }
        transform.position = motion.position;
        transform.angles = command.angles;
        velocity.linear = motion.velocity;
        const body = try world.get(entity, data.Body);
        body.mins = result.mins;
        body.maxs = result.maxs;
        body.grounded = player.ground_entity != c.ENTITYNUM_NONE;
        try self.publish(world, projections, states, index, now);
        for (result.events[0..result.event_count]) |event| switch (event) {
            .land => |speed| try @import("environment.zig").land(world, entity, speed, now),
            else => {},
        };
        // Dispatch after movement/projection: spawning events may relocate ECS columns.
        for (events.values[0..events.count]) |event| switch (event) {
            .fired => |shot| try @import("combat.zig").fire(world, slots, projections, entity, shot, &self.weapon_table, now),
            .no_ammo => {},
        };
    }
    pub fn userinfo(self: *Clients, world: *data.World, index: usize) !void {
        const entity = self.entities[index] orelse return;
        const session = world.get(entity, data.Session) catch return;
        var buffer: [c.MAX_INFO_STRING]u8 = @splat(0);
        _ = engine.gateway.call(c.G_GET_USERINFO, .{ @as(isize, @intCast(index)), &buffer, @as(isize, buffer.len) });
        const info = std.mem.sliceTo(&buffer, 0);
        const catalog = @import("appearance_catalog");
        const prior_appearance = session.appearance;
        session.appearance = @intCast(catalog.parse(@import("../engine/info.zig").get(info, "model") orelse "hiro/0") orelse 0);
        if (session.team == .red or session.team == .blue) session.appearance = @import("../domain/multiplayer.zig").appearance(session.appearance, @import("multiplayer.zig").teamColor(world, session.team));
        if (prior_appearance % 3 != session.appearance % 3) session.pose = .{};
        const selection = catalog.entries[session.appearance];
        if (self.poses[session.appearance % 3] == null) {
            var path: [128]u8 = undefined;
            const bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, std.heap.c_allocator, try std.fmt.bufPrintZ(&path, "{s}.anim", .{selection.model}), 1024 * 1024);
            defer std.heap.c_allocator.free(bytes);
            self.poses[session.appearance % 3] = try @import("../domain/player_pose.zig").Set.read(bytes);
        }
        (try world.get(entity, data.Binding)).model = try @import("resources.zig").model(selection.model);
        var text: [c.MAX_INFO_STRING]u8 = undefined;
        const supplied = @import("../engine/info.zig").get(info, "name") orelse "Player";
        var clean: [32]u8 = undefined;
        var length: usize = 0;
        for (supplied) |byte| {
            if (length == clean.len) break;
            if (byte < 32 or byte == 127 or byte == '\"' or byte == '\\' or byte == ';') continue;
            clean[length] = byte;
            length += 1;
        }
        engine.config(c.CS_PLAYERS + @as(i32, @intCast(index)), try std.fmt.bufPrintZ(&text, "\\n\\{s}\\t\\{d}\\model\\{s}\\skin\\{s}", .{ clean[0..length], @intFromEnum(session.team), selection.model, selection.skin }));
    }
    pub fn publish(self: *Clients, world: *data.World, projections: []abi.EntityProjection, states: []c.playerState_t, index: usize, now: i64) !void {
        const entity = self.entities[index].?;
        const transform = (try world.get(entity, data.Transform)).*;
        const velocity = (try world.get(entity, data.Velocity)).*;
        const body = (try world.get(entity, data.Body)).*;
        const inventory = (try world.get(entity, data.Weapons)).*;
        const ps = &states[index];
        bridge.write(ps, (try world.get(entity, data.Player)).*, transform, velocity);
        const health = (try world.get(entity, data.Health)).*;
        ps.stats[c.STAT_HEALTH] = health.current;
        ps.stats[c.STAT_MAX_HEALTH] = health.maximum;
        ps.stats[c.STAT_ARMOR] = health.armor;
        // This native protocol carries the current blend in the existing byte.
        // Authoritative state also restores correctly after an injury save.
        ps.damageCount = @intFromFloat((try world.get(entity, data.Hurt)).feedback.alpha(now) * 255);
        ps.dk3ArmorAbsorption = health.absorption;
        const keys = (try world.get(entity, data.Keys)).*;
        ps.dk3Keys = @bitCast(keys.mask);
        ps.dk3Quest = @bitCast(keys.quest);
        const character = (try world.get(entity, data.Character)).*;
        const ailments = (try world.get(entity, data.Ailments)).*;
        bridge.writeCharacter(ps, character, ailments);
        ps.speed = @intFromFloat(bridge.characterParameters(@intCast(index), character, ailments, ps.commandTime).speed);
        ps.dk3Episode = self.episode;
        if (world.get(entity, data.Session) catch null) |session| {
            session.advancement = character.advancement(inventory.dk3SwordExperience);
            ps.persistant[c.PERS_TEAM] = @intFromEnum(session.team);
            ps.persistant[c.PERS_SCORE] = session.score;
            ps.persistant[c.PERS_KILLED] = @intCast(session.deaths);
            ps.persistant[c.PERS_CAPTURES] = @intCast(session.captures);
            ps.dk3Objective = 0;
            ps.dk3ObjectiveUntil = 0;
            if (@import("multiplayer.zig").held(world, try world.persistentId(entity))) |flag| {
                ps.dk3Objective = @intFromEnum(flag.team);
                ps.dk3ObjectiveUntil = @intCast(flag.deadline orelse 0);
            }
        }
        bridge.writeWeapons(ps, inventory);
        const projection = &projections[index];
        projection.state.number = @intCast(index);
        projection.state.clientNum = @intCast(index);
        projection.state.eType = c.ET_PLAYER;
        projection.state.eFlags = ps.eFlags;
        projection.state.modelindex = (try world.get(entity, data.Binding)).model;
        projection.state.angles2 = @splat(1);
        projection.state.dk3Team = ps.persistant[c.PERS_TEAM];
        projection.shared.svFlags = if ((try world.get(entity, data.Player)).mode == .spectator or @import("nharre_reaper.zig").frozen(world, entity)) c.SVF_NOCLIENT else 0;
        projection.state.pos.trType = c.TR_INTERPOLATE;
        projection.state.pos.trBase = transform.position;
        projection.state.apos.trType = c.TR_INTERPOLATE;
        projection.state.apos.trBase = .{ 0, transform.angles[1], 0 };
        if (world.get(entity, data.Session) catch null) |session| {
            const pose_set = &(self.poses[session.appearance % 3] orelse return error.MissingPlayerAnimation);
            const player = (try world.get(entity, data.Player)).*;
            const weapon = @import("weapon_catalog").find(@intCast(inventory.weapon)) orelse return error.UnknownPlayerWeapon;
            projection.state.frame = pose_set.frame(&session.pose, .{ .velocity = velocity.linear, .yaw = transform.angles[1], .ducked = player.ducked, .jumping = player.jump_held and player.ground_entity == c.ENTITYNUM_NONE and player.water_level < 2, .dead = health.current <= 0, .fired_ms = inventory.last_fire_ms }, weapon.spec.player_grip, now);
        }
        projection.state.generic1 = if (ailments.stone) @import("actor_catalog").medusa.stone_tag else 0;
        if (ailments.petrified_frame) |frame| projection.state.frame = frame;
        ps.loopSound = if (ailments.warp != null) try @import("resources.zig").sound(@import("actor_catalog").psyclaw.loop_sound) else 0;
        projection.state.loopSound = ps.loopSound;
        projection.state.groundEntityNum = ps.groundEntityNum;
        projection.state.weapon = if (health.current <= 0) 0 else ps.weapon;
        projection.shared.currentOrigin = transform.position;
        projection.shared.currentAngles = transform.angles;
        projection.shared.mins = body.mins;
        projection.shared.maxs = body.maxs;
        projection.shared.contents = @bitCast(body.contents);
        projection.shared.ownerNum = c.ENTITYNUM_NONE;
        if (world.get(entity, data.Session) catch null) |session| if (session.bot) {
            projection.shared.svFlags |= c.SVF_BOT;
        };
        engine.link(projection);
    }
};
