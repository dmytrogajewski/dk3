// SPDX-License-Identifier: GPL-2.0-or-later
//! Actor lifecycle and perception. Class combat and shared locomotion are separate systems.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/actors.zig");
const catalog = @import("actor_catalog");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const c = abi.c;
pub const Actors = struct {
    table: rules.Table = .{},
    weapons: @import("../domain/weapons.zig").Table = .{},
    episode: u8 = 1,
    allocator: std.mem.Allocator = undefined,
    event_bytes: []const u8 = "",
    animations: [catalog.entries.len]bool = @splat(false),
    metadata: [catalog.entries.len][]const u8 = @splat(""),
    air_routes: @import("air_routes.zig").Routes = .{},
    air_ready: bool = false,
    water_routes: @import("air_routes.zig").Routes = .{},
    water_ready: bool = false,
    pub fn spawn(self: *Actors, allocator: std.mem.Allocator, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64, episode: u8) !void {
        self.episode = episode;
        self.allocator = allocator;
        const bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, "dk3/tables/aidata.cfg", 4 * 1024 * 1024);
        self.table = try rules.Table.parse(bytes);
        self.event_bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, "dk3/tables/actor_events.cfg", 4 * 1024 * 1024);
        var candidates: [ecs.max_entities]ecs.Entity = undefined;
        var count: usize = 0;
        {
            var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
            defer query.deinit();
            while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| {
                if (std.mem.startsWith(u8, object.classname, "monster_") and !std.mem.eql(u8, object.classname, "monster_path_corner") and !std.mem.eql(u8, object.classname, catalog.firefly.classname) and !std.mem.eql(u8, object.classname, catalog.wisp.classname) and catalog.find(object.classname) == null) {
                    var message: [160]u8 = undefined;
                    engine.print(try std.fmt.bufPrintZ(&message, "dk3 actor: missing native controller for {s}\n", .{object.classname}));
                    return error.UnknownAuthoredActorClass;
                }
                if (catalog.find(object.classname) != null) {
                    candidates[count] = entity;
                    count += 1;
                }
            };
        }
        for (candidates[0..count]) |entity| try self.spawnOne(world, slots, projections, entity, now);
    }
    pub fn ensure(self: *Actors, id: u8) !void {
        if (self.animations[id]) return;
        const definition = &self.table.definitions[id];
        if (!definition.loaded) return error.MissingActorDefinition;
        var path: [80]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&path, "{s}.anim", .{definition.model});
        const metadata = try @import("../engine/files.zig").read(.server, &engine.gateway, self.allocator, name, 1 << 20);
        self.metadata[id] = metadata;
        const policy = catalog.entries[id];
        const animation = @import("../domain/animation.zig");
        definition.idle = try animation.find(metadata, policy.idle) orelse return error.MissingActorIdle;
        definition.run = try animation.find(metadata, policy.run) orelse return error.MissingActorRun;
        definition.death = try animation.find(metadata, policy.death) orelse return error.MissingActorDeath;
        const attacks: []const []const u8 = switch (policy.kind) {
            .mishima_guard => &catalog.mishima.attacks,
            .skeeter => &.{catalog.skeeter.attack},
            .thunderskeet => &.{catalog.thunderskeet.attack},
            .froginator => &catalog.froginator.attacks,
            .crox => &catalog.crox.attacks,
            .cryotech => &catalog.cryotech.attacks,
            .surgeon => &catalog.surgeon.poses,
            .labmonkey => &catalog.labmonkey.attacks,
            .inmater => &catalog.inmater.attacks,
            .lasergat => &catalog.lasergat.attacks,
            .battleboar => &catalog.battleboar.attacks,
            .rocketdude => &catalog.rocketgang.attacks,
            .rocketmp => &catalog.rocketmp.attacks,
            .thief => &catalog.thief.attacks,
            .blackprisoner, .whiteprisoner => &catalog.prisoners.attacks,
            .femgang => &catalog.femgang.attacks,
            .centurion, .fletcher => &catalog.archers.attacks,
            .sealcaptain, .sealcommando, .sealgirl, .uzigang => &catalog.gunners.attacks,
            .doombat => &catalog.doombat.attacks,
            .griffon => &catalog.griffon.attacks,
            .harpy => &catalog.harpy.attacks,
            .dragon => &catalog.dragon.attacks,
            .deathsphere => &catalog.deathsphere.attacks,
            .chaingang => &catalog.chaingang.attacks,
            .buboid => &catalog.buboid.attacks,
            .wyndrax => &catalog.wyndrax.attacks,
            .garroth => &catalog.garroth.attacks,
            .stavros => &catalog.stavros.attacks,
            .psyclaw => &catalog.psyclaw.attacks,
            .sludgeminion => &catalog.sludge.attacks,
            .rotworm => &catalog.rotworm.attacks,
            .venomvermin => &catalog.vermin.attacks,
            .shark => &catalog.shark.attacks,
            .cerberus => &catalog.cerberus.attacks,
            .piperat => &catalog.rats.pipe_attacks,
            .plague_rat => &catalog.rats.plague_attacks,
            .knight1 => &catalog.knights.flame_attacks,
            .knight2 => &catalog.knights.lightning_attacks,
            .ragemaster => &catalog.ragemaster.attacks,
            .skeleton => &catalog.skeleton.attacks,
            .satyr => &catalog.satyr.attacks,
            .column => &catalog.column.attacks,
            .dwarf => &catalog.dwarf.attacks,
            .lycanthir => &catalog.lycanthir.attacks,
            .spider, .smallspider => &catalog.spider.attacks,
            else => &.{},
        };
        for (attacks, 0..) |attack, i| {
            if (policy.kind == .venomvermin and i == 3) {
                definition.vermin_has_leap = (try animation.find(metadata, attack)) != null;
                if (!definition.vermin_has_leap) continue;
            }
            definition.attacks[i] = try animation.find(metadata, attack) orelse return error.MissingActorAttack;
            if ((policy.kind == .spider or policy.kind == .smallspider) and i == 0) definition.attacks[i].fps *= 2;
            // These Wyndrax model sequences have no rows in the supplied CSV;
            // their default strike is first+1 and the class supplies zap audio.
            if (policy.kind == .wyndrax) {
                definition.strikes[i] = 1;
                continue;
            }
            if (policy.kind == .satyr and i >= 3) continue;
            if ((policy.kind == .chaingang and (i == 2 or i == 3)) or policy.kind == .surgeon or (policy.kind == .sludgeminion and i == 3) or (policy.kind == .deathsphere and i == 1)) continue;
            const row = try self.event(policy.classname, attack);
            definition.attack_sounds[i] = row.field("sound1") orelse "";
            definition.second_attack_sounds[i] = row.field("sound2") orelse "";
            if (definition.second_attack_sounds[i].len != 0) definition.second_sound_ms[i] = @intFromFloat(try row.number("frame2", 0) * 1000 / @as(f32, @floatFromInt(definition.attacks[i].fps)));
            if ((policy.kind == .lycanthir and i == 4) or ((policy.kind == .spider or policy.kind == .smallspider) and i == 1)) definition.jump_strike_ms = @intFromFloat(try row.number("frame2", 0) * 1000 / @as(f32, @floatFromInt(definition.attacks[i].fps)));
            if ((policy.kind == .piperat or policy.kind == .plague_rat) and i == 1) definition.jump_strike_ms = @intFromFloat(try row.number("frame2", 0) * 1000 / @as(f32, @floatFromInt(definition.attacks[i].fps)));
            const strike = try row.number("strike1", 0);
            if (strike < 0 or strike > @as(f32, @floatFromInt(definition.attacks[i].last - definition.attacks[i].first))) return error.InvalidActorStrike;
            definition.strikes[i] = @intFromFloat(strike);
            const second = try row.number("strike2", 0);
            if (second < 0 or second > @as(f32, @floatFromInt(definition.attacks[i].last - definition.attacks[i].first))) return error.InvalidActorStrike;
            definition.second_strikes[i] = if (second > 0) @intFromFloat(second) else null;
            if (policy.kind == .venomvermin and (i == 1 or i == 3)) definition.second_strikes[i] = @intFromFloat(second);
            if (policy.kind == .garroth or policy.kind == .psyclaw or policy.kind == .griffon or (policy.kind == .buboid and i < 2)) definition.second_strikes[i] = @intFromFloat(second);
            if (policy.kind == .uzigang or ((policy.kind == .sealcaptain or policy.kind == .sealgirl) and i == 1)) definition.second_strikes[i] = @intFromFloat(second);
            if (policy.kind == .rocketmp and i != 1) definition.second_strikes[i] = @intFromFloat(second);
            if (policy.kind == .blackprisoner or policy.kind == .whiteprisoner) definition.second_strikes[i] = @intFromFloat(second);
            definition.attack_sound_ms[i] = @intFromFloat(try row.number("frame1", 0) * 1000 / @as(f32, @floatFromInt(definition.attacks[i].fps)));
        }
        if (catalog.sequenceAttack(policy.kind)) {
            definition.pain[0] = try animation.find(metadata, "hita");
            definition.pain[1] = try animation.find(metadata, "hitb");
        }
        if (policy.kind == .dwarf or policy.kind == .lycanthir or policy.kind == .knight1 or policy.kind == .knight2 or policy.kind == .plague_rat or policy.kind == .fletcher or policy.kind == .battleboar or policy.kind == .rocketdude or policy.kind == .thief or policy.kind == .blackprisoner or policy.kind == .whiteprisoner or policy.kind == .femgang or policy.kind == .sealcaptain or policy.kind == .sealcommando or policy.kind == .sealgirl or policy.kind == .uzigang) definition.death_b = try animation.find(metadata, "dieb") orelse return error.MissingActorDeath;
        if (policy.kind == .femgang) definition.alternate_idle = try animation.find(metadata, "ambb") orelse return error.MissingFemgangIdle;
        if (policy.kind == .harpy and (definition.attacks[2].first > 191 or definition.attacks[2].last < 209)) return error.InvalidHarpyDrop;
        if (policy.kind == .garroth) {
            try self.ensure(catalog.find("monster_buboid").?);
            definition.death_b = try animation.find(metadata, "dieb") orelse return error.MissingActorDeath;
        }
        if (policy.kind == .buboid) definition.death_b = try animation.find(metadata, "dieb") orelse return error.MissingActorDeath;
        if (policy.kind == .chaingang) definition.death_d = try animation.find(metadata, "diec") orelse return error.MissingActorDeath;
        if (policy.kind == .griffon or policy.kind == .harpy or policy.kind == .chaingang or policy.kind == .buboid or policy.kind == .wyndrax) {
            definition.ground_run = try animation.find(metadata, "runa") orelse return error.MissingGriffonGroundRun;
            if (!self.water_ready) {
                try self.water_routes.initGround(self.allocator);
                self.water_ready = true;
            }
        }
        if (policy.kind == .battleboar) definition.pain_c = try animation.find(metadata, "hitc") orelse return error.MissingBoarPain;
        if (policy.kind == .skeleton) {
            definition.death_b = try animation.find(metadata, "dieb") orelse return error.MissingActorDeath;
            definition.death_d = try animation.find(metadata, "died") orelse return error.MissingActorDeath;
        }
        if (policy.kind == .column) definition.awakening = try animation.find(metadata, "awaken") orelse return error.MissingActorAwakening;
        if (policy.kind == .companion) {
            definition.attacks[0] = try animation.find(metadata, "ataka") orelse definition.idle;
            definition.walk = try animation.find(metadata, "walka") orelse definition.run;
        }
        if (policy.kind == .mishima_guard) definition.reload = try animation.find(metadata, catalog.mishima.reload_animation) orelse return error.MissingActorReload;
        if (policy.kind == .protopod or policy.kind == .skeeter) {
            const hatch = if (policy.kind == .protopod) "hatcha" else catalog.skeeter.hatch;
            definition.hatch = try animation.find(metadata, hatch) orelse return error.MissingActorHatch;
            definition.hatch_sound = (try self.event(policy.classname, hatch)).field("sound1") orelse "";
            if (!self.air_ready) {
                try self.air_routes.init(self.allocator);
                self.air_ready = true;
            }
        }
        if (policy.kind == .thunderskeet) {
            if (definition.attacks[0].first > 27 or definition.attacks[0].last < 32) return error.InvalidThunderBurstAnimation;
            if (!self.air_ready) {
                try self.air_routes.init(self.allocator);
                self.air_ready = true;
            }
        }
        if ((policy.kind == .cambot or policy.kind == .doombat or policy.kind == .griffon or policy.kind == .harpy or policy.kind == .dragon or policy.kind == .deathsphere or policy.kind == .chaingang) and !self.air_ready) {
            try self.air_routes.init(self.allocator);
            self.air_ready = true;
        }
        if (policy.kind == .piperat or policy.kind == .plague_rat or policy.kind == .shark) {
            definition.swim = try animation.find(metadata, "swima") orelse return error.MissingRatSwim;
            if (!self.water_ready) {
                try self.water_routes.initGround(self.allocator);
                self.water_ready = true;
            }
        }
        if (policy.kind == .crox) {
            definition.swim = try animation.find(metadata, "swima") orelse return error.MissingCroxSwim;
            definition.walk = try animation.find(metadata, "walka") orelse return error.MissingCroxWalk;
            definition.death_b = try animation.find(metadata, "dieb") orelse return error.MissingCroxDeath;
            if (definition.walk_speed <= 0 or definition.range <= 0 or definition.damage <= 0) return error.InvalidCroxTuning;
            if (!self.water_ready) {
                try self.water_routes.initGround(self.allocator);
                self.water_ready = true;
            }
        }
        if ((policy.kind == .centurion or policy.kind == .fletcher or policy.kind == .rocketdude or policy.kind == .venomvermin or policy.kind == .blackprisoner or policy.kind == .whiteprisoner or policy.kind == .femgang) and !self.water_ready) {
            try self.water_routes.initGround(self.allocator);
            self.water_ready = true;
        }
        self.animations[id] = true;
        if (policy.kind == .protopod) try self.ensure(catalog.find("monster_slaughterskeet").?);
    }
    pub fn findSequence(self: *Actors, id: u8, name: []const u8) !?@import("../domain/animation.zig").Sequence {
        try self.ensure(id);
        return @import("../domain/animation.zig").find(self.metadata[id], name);
    }
    fn event(self: *Actors, classname: []const u8, name: []const u8) !@import("../domain/tables.zig").Row {
        var reader = try @import("../domain/tables.zig").Reader.init(self.event_bytes);
        while (try reader.next()) |row| if (std.mem.eql(u8, row.field("classname") orelse "", classname) and std.mem.eql(u8, row.field("animation") orelse "", name)) return row;
        return error.MissingActorAttackEvent;
    }
    fn spawnOne(self: *Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
        const object = (try world.get(entity, data.MapObject)).*;
        if (std.mem.eql(u8, object.classname, catalog.wisp.classname)) return @import("wisps.zig").spawnOne(world, slots, projections, entity, now);
        const id = catalog.find(object.classname) orelse return error.UnknownActorClass;
        try self.ensure(id);
        const definition = self.table.definitions[id];
        const health = try @import("properties.zig").number(object, "health", @floatFromInt(definition.health));
        if (health <= 0) return error.InvalidActorHealth;
        try world.put(entity, data.Actor{ .unique = @import("properties.zig").text(object, "uniqueid") orelse "", .ignore_player = object.flags & 16 != 0 or catalog.entries[id].kind == .surgeon, .path = if (object.flags & 2 != 0 and object.target.len > 0) if (@import("scripts.zig").named(world, object.target)) |point| try world.persistentId(point) else 0 else 0, .crox = .{ .start = (try world.get(entity, data.Transform)).position, .cycle_ms = now + definition.idle.duration() }, .definition = id, .changed_ms = now, .think_ms = now, .guard = .{ .random = try world.persistentId(entity) } });
        if (catalog.entries[id].kind == .psyclaw) (try world.get(entity, data.Actor)).psyclaw.protected_until_ms = now + 750;
        if (catalog.entries[id].kind == .shark) (try world.get(entity, data.Actor)).shark.start = (try world.get(entity, data.Transform)).position;
        if (catalog.entries[id].kind == .rockgat) (try world.get(entity, data.Actor)).rockgat = try @import("rockgats.zig").configure(object, now, definition.idle.last);
        try world.put(entity, data.Hurt{});
        try world.put(entity, data.Ailments{});
        try world.put(entity, data.Health{ .current = @intFromFloat(health), .maximum = @intFromFloat(health) });
        try world.put(entity, data.Velocity{});
        try world.put(entity, data.Random{ .state = try world.persistentId(entity) });
        try world.put(entity, data.Body{ .mins = definition.mins, .maxs = definition.maxs, .contents = c.CONTENTS_BODY, .collision_mask = c.MASK_PLAYERSOLID, .mass = definition.mass });
        const model = try @import("resources.zig").model(definition.model);
        const slot = try slots.acquire(entity, null);
        try world.put(entity, data.Binding{ .slot = slot, .model = model });
        projections[slot] = std.mem.zeroes(abi.EntityProjection);
        if (catalog.entries[id].kind == .wyndrax) (try world.get(entity, data.Actor)).wyndrax.start_position = (try world.get(entity, data.Transform)).position;
        if (catalog.entries[id].kind == .buboid) try @import("buboids.zig").initialize(world, entity, now);
        if (catalog.entries[id].kind == .chaingang) try @import("chaingangs.zig").initialize(world, entity, now);
        if (catalog.entries[id].kind == .rotworm) try @import("rotworms.zig").initialize(world, entity, now);
        if (catalog.entries[id].kind == .companion) try @import("companions.zig").initialize(world, entity, self.episode, &self.weapons, now);
        try self.publish(world, entity, projections, now);
    }
    pub fn spawnDynamic(self: *Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, classname: []const u8, position: v.Vec3, angles: v.Vec3, now: i64) !ecs.Entity {
        return self.spawnAuthored(world, slots, projections, .{ .classname = classname }, .{ .position = position, .angles = angles }, now);
    }
    pub fn spawnAuthored(self: *Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, object: data.MapObject, pose: data.Transform, now: i64) !ecs.Entity {
        const entity = try world.create(null, .{ object, pose });
        errdefer world.destroy(entity) catch unreachable;
        try self.spawnOne(world, slots, projections, entity, now);
        return entity;
    }
    pub fn publish(self: *const Actors, world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
        const actor = (try world.get(entity, data.Actor)).*;
        const definition = self.table.definitions[actor.definition];
        const pose = (try world.get(entity, data.Transform)).*;
        const body = (try world.get(entity, data.Body)).*;
        const binding = (try world.get(entity, data.Binding)).*;
        const policy = catalog.entries[actor.definition];
        const hatching = policy.kind == .protopod and (actor.pod.phase == .opening or actor.pod.phase == .shell) or policy.kind == .skeeter and actor.skeeter.phase == .hatching;
        const sequence = if (actor.mode == .dead and actor.death_pose != null) actor.death_pose.? else if (actor.reaction != null and actor.mode != .dead) actor.reaction.? else if (catalog.sequenceAttack(policy.kind) and actor.melee.active) definition.attacks[actor.melee.pose] else if (policy.kind == .crox and actor.mode == .dead and actor.crox.death_b) definition.death_b else if (policy.kind == .crox and actor.mode != .attack and actor.mode != .dead and actor.scripted_pose == null) if (actor.crox.swimming) definition.swim else if (actor.crox.wandering) definition.walk else if (actor.mode == .chase) definition.run else definition.idle else if (actor.scripted_pose != null and actor.mode != .dead) actor.scripted_pose.? else if (hatching) definition.hatch else switch (actor.mode) {
            .idle => if (policy.kind == .femgang and actor.femgang.idle_b) definition.alternate_idle else if (policy.kind == .sludgeminion and actor.sludge.idle_scoop) definition.attacks[2] else definition.idle,
            .flee, .chase => if (actor.path != 0 and actor.moving_pose != null) actor.moving_pose.? else definition.run,
            .attack => definition.attacks[if (catalog.sequenceAttack(policy.kind)) actor.melee.pose else if (policy.kind == .crox) actor.crox.pose else if (policy.kind == .froginator) actor.frog.pose() else actor.guard.pose],
            .reload => definition.reload,
            .dead => definition.death,
        };
        const projection = &projections[binding.slot];
        projection.state.number = binding.slot;
        projection.state.eType = c.ET_GENERAL;
        projection.state.modelindex = binding.model;
        projection.state.angles2 = definition.scale;
        projection.state.generic1 = if (world.get(entity, data.Ailments) catch null) |ailment| @intFromFloat(ailment.freeze_level * 1000) else 0;
        projection.state.groundEntityNum = actor.ground_entity;
        projection.state.time2 = if (policy.kind == .cambot and actor.mode != .dead) if (actor.threat != 0) catalog.cambot.alert_tag else catalog.cambot.idle_tag else 0;
        if (policy.kind == .chaingang and actor.mode != .dead and actor.chaingang.flying) projection.state.time2 = catalog.chaingang.jet_tag;
        if (policy.kind == .deathsphere) projection.state.loopSound = if (actor.mode != .dead and actor.threat_seen_ms > 0) try @import("resources.zig").sound("e1/m_dspherehovera.wav") else 0;
        projection.state.frame = sequence.frame(now - (if (actor.reaction != null and actor.mode != .dead) actor.reaction_started_ms else if (catalog.sequenceAttack(policy.kind) and actor.melee.active) actor.melee.started_ms else if (actor.scripted_pose != null and actor.mode != .dead) actor.scripted_ms else if ((catalog.sequenceAttack(policy.kind)) and actor.mode == .attack) actor.melee.started_ms else if (policy.kind == .crox and actor.mode == .attack) actor.crox.started_ms else if (policy.kind == .thunderskeet and actor.mode == .attack) actor.thunder.started_ms else if (policy.kind == .froginator and actor.mode == .attack) actor.frog.started_ms else if (policy.kind == .skeeter and (actor.mode == .attack or hatching)) actor.skeeter.started_ms else if (policy.kind == .mishima_guard and (actor.mode == .attack or actor.mode == .reload)) actor.guard.started_ms else actor.changed_ms), !hatching and actor.reaction == null and !actor.melee.active and (actor.mode == .idle or actor.mode == .flee or actor.mode == .chase));
        if (policy.kind == .lycanthir) if (@import("lycanthirs.zig").frame(actor, definition, now)) |frame| {
            projection.state.frame = frame;
        };
        if ((policy.kind == .piperat or policy.kind == .plague_rat) and actor.rat.swimming and actor.mode == .chase and actor.scripted_pose == null and !actor.melee.active) projection.state.frame = definition.swim.frame(now - actor.changed_ms, true);
        if (policy.kind == .surgeon and actor.surgeon.active and actor.mode != .dead) projection.state.frame = definition.attacks[actor.surgeon.pose].frame(now - actor.surgeon.started_ms, true);
        if (policy.kind == .griffon and actor.mode != .dead and actor.reaction == null and actor.scripted_pose == null) {
            if (actor.griffon.phase == .leap) projection.state.frame = definition.attacks[4].frame(now - actor.melee.started_ms, true) else if (!actor.griffon.flying and actor.mode == .chase) projection.state.frame = definition.ground_run.frame(now - actor.changed_ms, true);
        }
        if (policy.kind == .chaingang and actor.mode != .dead and actor.reaction == null and actor.scripted_pose == null and !actor.melee.active and actor.mode == .chase and (!actor.chaingang.flying or actor.chaingang.phase == .dodge or actor.chaingang.phase == .approach_land)) projection.state.frame = definition.ground_run.frame(now - actor.changed_ms, true);
        if (policy.kind == .harpy and actor.mode != .dead and actor.reaction == null and actor.scripted_pose == null) {
            switch (actor.harpy.phase) {
                .takeoff, .rising => projection.state.frame = definition.attacks[2].last - (definition.attacks[2].frame(now - actor.melee.started_ms, false) - definition.attacks[2].first),
                .dodge, .approach_land => projection.state.frame = definition.ground_run.frame(now - actor.changed_ms, true),
                .chase => if (!actor.harpy.flying and actor.mode == .chase) {
                    projection.state.frame = definition.ground_run.frame(now - actor.changed_ms, true);
                },
                .attack => if (!actor.melee.active) {
                    projection.state.frame = (if (actor.harpy.flying) definition.run else definition.ground_run).frame(now - actor.harpy.warmup_started_ms, true);
                },
                else => {},
            }
        }
        if (policy.kind == .column and actor.column.phase == .asleep) projection.state.frame = definition.awakening.first;
        if (policy.kind == .lasergat and actor.mode != .attack) projection.state.frame = 1;
        if (policy.kind == .battleboar and actor.mode == .attack and actor.melee.pose == 0 and actor.battleboar.flashed and projection.state.frame > 91 and projection.state.frame < 97 and @mod(@divTrunc(now - actor.melee.started_ms, 50), 2) == 0) projection.state.time2 = catalog.battleboar.flash_tag;
        if (policy.kind == .rockgat) {
            projection.state.frame = actor.rockgat.frame(now);
            for (actor.rockgat.bursts) |burst| if (burst != null) {
                projection.state.time2 = catalog.rockgat.flash_tag;
                break;
            };
        }
        if (policy.kind == .dragon and actor.mode != .dead and actor.scripted_pose == null and actor.reaction == null) {
            if (actor.dragon.phase == .hover) projection.state.frame = definition.attacks[1].frame(now - actor.melee.started_ms, true);
            if (actor.dragon.breath_until_ms) |until| {
                projection.state.time2 = catalog.dragon.breath_tag;
                projection.state.time = @intCast(until - 850);
                projection.state.origin2 = actor.dragon.breath_direction;
            }
        }
        if (policy.kind == .buboid and actor.mode != .dead) {
            if (actor.buboid.phase == .melted) projection.state.modelindex = 0;
            projection.state.time2 = catalog.buboid.melt_tag;
            projection.state.time = @intCast(actor.buboid.started_ms);
            projection.state.origin2 = .{ actor.buboid.alpha, if (actor.buboid.phase == .melting or actor.buboid.phase == .unmelting) @as(f32, 1) else 0, 0 };
        }
        if (policy.kind == .deathsphere and actor.mode != .dead and actor.scripted_pose == null and actor.melee.active and actor.melee.pose == 2) projection.state.frame = definition.attacks[2].frame(now - actor.melee.started_ms, true);
        projection.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
        projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
        projection.shared.currentOrigin = pose.position;
        projection.shared.currentAngles = pose.angles;
        projection.shared.mins = body.mins;
        projection.shared.maxs = body.maxs;
        projection.shared.contents = @bitCast(body.contents);
        projection.shared.ownerNum = c.ENTITYNUM_NONE;
        engine.link(projection);
    }
    fn visible(from: v.Vec3, to: v.Vec3, skip: u16, target: u16) !bool {
        const hit = try engine.collisionService().trace(.{ .start = from, .end = to, .mins = @splat(0), .maxs = @splat(0), .slot = skip, .mask = c.MASK_SOLID });
        return hit.fraction == 1 or hit.entity == target;
    }
    pub fn step(self: *Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, navigation: @import("../domain/navigation.zig").Service, now: i64, elapsed: u32) !void {
        const occupants = slots.occupants;
        for (occupants) |occupant| {
            const entity = occupant orelse continue;
            if (!world.alive(entity)) continue;
            var actor = (world.get(entity, data.Actor) catch continue).*;
            const binding = (try world.get(entity, data.Binding)).*;
            var pose = (try world.get(entity, data.Transform)).*;
            var body = (try world.get(entity, data.Body)).*;
            const hurt = (try world.get(entity, data.Hurt)).*;
            const dead = (try world.get(entity, data.Health)).current <= 0;
            if (dead and actor.gibbed and actor.death_dispatched and now >= actor.changed_ms + 100) {
                try @import("weapon_entities.zig").remove(world, slots, projections, entity);
                continue;
            }
            if (dead and (catalog.entries[actor.definition].kind == .rockgat or catalog.entries[actor.definition].kind == .lasergat)) {
                try @import("progression.zig").kill(world, hurt, self.table.definitions[actor.definition].health, self.episode);
                try @import("actor_spawns.zig").death(self, world, slots, projections, router, entity, now);
                engine.unlink(&projections[binding.slot]);
                try slots.release(binding.slot, entity);
                try world.destroy(entity);
                continue;
            }
            if (dead and actor.mode != .dead) {
                const kind = catalog.entries[actor.definition].kind;
                if ((kind == .griffon or kind == .harpy or kind == .dragon or kind == .deathsphere or (kind == .buboid and actor.buboid.phase == .terminal)) and engine.integer("sv_violence") == 0) {
                    try @import("actor_gibs.zig").spawn(world, slots, projections, entity, now);
                    actor.gibbed = true;
                }
                if (catalog.entries[actor.definition].kind == .rotworm) {
                    pose.angles[0] = 0;
                    actor.rotworm.phase = .ground;
                }
                if (catalog.entries[actor.definition].kind == .dwarf or catalog.entries[actor.definition].kind == .knight1 or catalog.entries[actor.definition].kind == .knight2 or catalog.entries[actor.definition].kind == .plague_rat or catalog.entries[actor.definition].kind == .fletcher or catalog.entries[actor.definition].kind == .battleboar or catalog.entries[actor.definition].kind == .thief or catalog.entries[actor.definition].kind == .femgang or catalog.entries[actor.definition].kind == .sealcaptain or catalog.entries[actor.definition].kind == .sealcommando or catalog.entries[actor.definition].kind == .sealgirl) actor.death_pose = if ((try world.get(entity, data.Random)).next() < 0.5) self.table.definitions[actor.definition].death else self.table.definitions[actor.definition].death_b;
                if (catalog.entries[actor.definition].kind == .blackprisoner or catalog.entries[actor.definition].kind == .whiteprisoner) actor.death_pose = if (hurt.amount < 20 or (try world.get(entity, data.Random)).next() < 0.3) self.table.definitions[actor.definition].death else self.table.definitions[actor.definition].death_b;
                actor.evasion.until_ms = null;
                if (catalog.entries[actor.definition].kind == .rocketdude) if (world.find(hurt.source)) |attacker| {
                    const dot = v.dot(v.basis(pose.angles).forward, v.normalize(v.subtract((try world.get(attacker, data.Transform)).position, pose.position)));
                    actor.death_pose = if (dot > 0.707) self.table.definitions[actor.definition].death_b else self.table.definitions[actor.definition].death;
                };
                if (catalog.entries[actor.definition].kind == .uzigang) {
                    actor.death_pose = self.table.definitions[actor.definition].death_b;
                    if (hurt.amount > 10) if (world.find(hurt.source)) |attacker| {
                        const dot = v.dot(v.basis(pose.angles).forward, v.normalize(v.subtract((try world.get(attacker, data.Transform)).position, pose.position)));
                        if (dot > 0.707) actor.death_pose = self.table.definitions[actor.definition].death;
                    };
                }
                if (catalog.entries[actor.definition].kind == .crox) actor.crox.death_b = (try world.get(entity, data.Random)).next() >= 0.5;
                if (catalog.entries[actor.definition].kind == .skeleton) if (world.find(hurt.source)) |attacker| {
                    const facing = v.dot(v.basis(pose.angles).forward, v.normalize(v.subtract((try world.get(attacker, data.Transform)).position, pose.position)));
                    const definition = self.table.definitions[actor.definition];
                    actor.death_pose = if (@abs(facing) < 0.3) definition.death_b else if (facing > 0) definition.death else definition.death_d;
                };
                if (kind == .garroth) actor.death_pose = if ((try world.get(entity, data.Random)).next() < 0.5) self.table.definitions[actor.definition].death else self.table.definitions[actor.definition].death_b;
                if (kind == .buboid) actor.death_pose = self.table.definitions[actor.definition].death_b;
                if (kind == .chaingang) actor.death_pose = if ((try world.get(entity, data.Random)).next() > 0.33) self.table.definitions[actor.definition].death else self.table.definitions[actor.definition].death_d;
                if (catalog.entries[actor.definition].kind == .lycanthir) actor.death_pose = self.table.definitions[actor.definition].death_b;
                actor.melee.active = false;
                actor.reaction = null;
                actor.reaction_until_ms = null;
                actor.mode = .dead;
                actor.changed_ms = now;
                body.contents = if (actor.gibbed) 0 else c.CONTENTS_CORPSE;
                // Retain supplied horizontal bounds; final-pose corpse bounds remain to qualify.
                body.maxs[2] = @min(body.maxs[2], 0);
            }
            const policy = catalog.entries[actor.definition];
            const rat = policy.kind == .piperat or policy.kind == .plague_rat;
            if (!dead and rat) {
                actor.rat.water = try @import("actor_water.zig").level(pose.position, body, binding.slot);
                actor.rat.swimming = actor.rat.water == 3 or (actor.rat.water > 1 and !body.grounded);
            }
            if (!dead and @import("nightmare.zig").frozen(world, entity)) {
                try self.publish(world, entity, projections, now);
                continue;
            }
            if (!dead and policy.kind == .civilian) {
                if (hurt.revision != actor.receipt) {
                    actor.receipt = hurt.revision;
                    const point = if (world.find(hurt.source)) |source| (try world.get(source, data.Transform)).position else pose.position;
                    actor.panic(hurt.source, point, now);
                }
                // A dead civilian records its last attacker. Only a new, visible death can trigger a witness.
                for (occupants, 0..) |other, other_slot| {
                    const corpse = other orelse continue;
                    if (!world.alive(corpse)) continue;
                    _ = world.get(corpse, data.Actor) catch continue;
                    if ((try world.get(corpse, data.Health)).current > 0) continue;
                    const receipt = (try world.get(corpse, data.Hurt)).*;
                    if (receipt.at_ms <= actor.witness_ms) continue;
                    const point = (try world.get(corpse, data.Transform)).position;
                    if (v.length(v.add(point, v.scale(pose.position, -1))) > catalog.entries[actor.definition].witness_range) continue;
                    if (!try visible(v.add(pose.position, .{ 0, 0, 16 }), point, binding.slot, @intCast(other_slot))) continue;
                    actor.witness_ms = receipt.at_ms;
                    actor.panic(receipt.source, point, now);
                }
                if (actor.mode == .flee and now >= actor.panic_until) {
                    actor.mode = .idle;
                    actor.changed_ms = now;
                }
            }
            if (!dead and policy.kind == .surgeon) try @import("surgeons.zig").think(world, entity, &actor, pose, self.table.definitions[actor.definition], now);
            const script = world.get(entity, data.Script) catch null;
            const reviving = (policy.kind == .lycanthir and actor.lycanthir.phase != .living) or (policy.kind == .buboid and actor.buboid.phase != .living and actor.buboid.phase != .coffin);
            if (!dead and policy.kind == .rotworm and actor.rotworm.phase == .ceiling) {
                try @import("rotworms.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now);
                (try world.get(entity, data.Actor)).* = actor;
                (try world.get(entity, data.Transform)).* = pose;
                try self.publish(world, entity, projections, now);
                continue;
            }
            const acting = !reviving and !actor.surgeon.active and !(policy.kind == .civilian and actor.mode == .flee) and script != null and script.?.active;
            if (!dead and !acting and policy.kind == .cambot and now >= actor.think_ms) try @import("cambots.zig").sense(world, slots, projections, entity, &actor, pose, body, self.table.definitions[actor.definition], now);
            if (!dead and (policy.kind == .rockgat or policy.kind == .lasergat)) {
                if (policy.kind == .lasergat) try @import("lasergats.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now) else try @import("rockgats.zig").step(world, slots, projections, entity, &actor, &pose, now);
                (try world.get(entity, data.Actor)).* = actor;
                (try world.get(entity, data.Transform)).* = pose;
                (try world.get(entity, data.Velocity)).linear = @splat(0);
                try self.publish(world, entity, projections, now);
                continue;
            }
            if (!dead and !acting and actor.path != 0 and policy.kind != .civilian and policy.kind != .surgeon and policy.kind != .companion and policy.kind != .protopod and policy.kind != .cambot) try @import("actor_perception.zig").acquire(world, slots, entity, &actor, pose, self.table.definitions[actor.definition], now);
            const following = !reviving and !(policy.kind == .wyndrax and actor.wyndrax.phase != .combat) and !actor.surgeon.active and actor.mode != .flee and actor.path != 0 and hurt.revision == actor.receipt and (actor.ignore_player or actor.threat == 0);
            if (!dead and body.motion_owner == null and (acting or following)) {
                var velocity = (try world.get(entity, data.Velocity)).*;
                const definition = self.table.definitions[actor.definition];
                const speed = if (policy.kind == .civilian or policy.kind == .surgeon or policy.kind == .cambot) definition.walk_speed else definition.speed;
                const point = if (acting and script.?.moving) script.?.destination else if (!acting and following) try @import("scripts.zig").path(world, slots, projections, router, entity, &actor, pose, speed, now) else null;
                actor.mode = if (point != null) .chase else .idle;
                if (policy.kind == .cambot and now >= actor.think_ms) actor.think_ms = now + 100;
                if (policy.kind == .skeeter or policy.kind == .thunderskeet or policy.kind == .cambot or policy.kind == .doombat or policy.kind == .dragon or policy.kind == .deathsphere or (policy.kind == .griffon and actor.griffon.flying) or (policy.kind == .harpy and actor.harpy.flying) or (policy.kind == .chaingang and actor.chaingang.flying)) {
                    velocity.linear = @splat(0);
                    if (point) |destination| if (try self.air_routes.next(pose.position, destination, body, binding.slot)) |waypoint| {
                        const delta = v.subtract(waypoint, pose.position);
                        velocity.linear = v.scale(v.normalize(delta), @min(speed, v.length(delta) * 10));
                        pose.angles[1] = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
                    };
                    try @import("actor_flight.zig").move(&pose, body, &velocity, binding.slot, elapsed);
                } else {
                    if (point) |destination| actor.threat_position = destination;
                    if (policy.kind == .shark) try @import("sharks.zig").swim(self, &actor, &pose, &body, &velocity, binding.slot, elapsed, 1) else if (rat and actor.rat.swimming) actor.rat.water = try @import("actor_water.zig").move(&self.water_routes, &actor, &pose, &body, &velocity, speed, binding.slot, elapsed) else try @import("actor_motion.zig").step(&actor, &pose, &body, &velocity, navigation, actor.threat_position, speed, binding.slot, now, elapsed);
                }
                if (policy.kind == .cryotech) try @import("cryotechs.zig").ambient(world, slots, projections, entity, &actor, pose, definition, now);
                if (policy.kind == .dragon and actor.path != 0) try @import("dragons.zig").patrol(world, slots, projections, entity, &actor, pose, now);
                (try world.get(entity, data.Actor)).* = actor;
                (try world.get(entity, data.Transform)).* = pose;
                (try world.get(entity, data.Velocity)).* = velocity;
                (try world.get(entity, data.Body)).* = body;
                try self.publish(world, entity, projections, now);
                continue;
            }
            const resurrecting = !dead and policy.kind == .lycanthir and try @import("lycanthirs.zig").revive(world, entity, &actor, pose, &body, self.table.definitions[actor.definition], now);
            if (!dead and !resurrecting and catalog.groundAttack(policy.kind)) {
                switch (policy.kind) {
                    .blackprisoner, .whiteprisoner => try @import("prisoners.zig").think(&self.water_routes, world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .thief => try @import("thieves.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .rocketmp => try @import("rocketmp.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .battleboar => try @import("battleboars.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .rocketdude => try @import("rocketgang.zig").think(&self.water_routes, world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .centurion, .fletcher => try @import("archers.zig").think(&self.water_routes, world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .sealcaptain, .sealcommando, .sealgirl, .uzigang => try @import("gunners.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .psyclaw => try @import("psyclaws.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .sludgeminion => try @import("sludgeminions.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .rotworm => try @import("rotworms.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .venomvermin => try @import("vermin.zig").think(&self.water_routes, world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .shark => try @import("sharks.zig").think(self, world, slots, projections, entity, &actor, &pose, now),
                    .piperat, .plague_rat => try @import("rats.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .knight1, .knight2 => try @import("knights.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .inmater => try @import("inmaters.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .cryotech => try @import("cryotechs.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    .spider, .smallspider => try @import("spiders.zig").think(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                    else => try @import("ground_combat.zig").think(&self.water_routes, world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now),
                }
            }
            if (!dead and policy.kind == .companion) try @import("companions.zig").goal(&self.weapons, world, slots, entity, &actor, &pose, now);
            if (!dead and policy.kind == .mishima_guard) try @import("hostiles.zig").guard(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now);
            var velocity = (try world.get(entity, data.Velocity)).*;
            if (!dead and policy.kind == .froginator and body.motion_owner == null) try @import("froginators.zig").think(world, slots, projections, entity, &actor, &pose, body, &velocity, self.table.definitions[actor.definition], now);
            if (!dead and policy.kind == .crox and body.motion_owner == null) try @import("crox.zig").think(self, world, slots, projections, entity, &actor, &pose, body, &velocity, now);
            const threat = if (world.find(actor.threat)) |source| (try world.get(source, data.Transform)).position else actor.threat_position;
            const slow = if (world.get(entity, data.Ailments) catch null) |ailment| 1 - 0.8 * ailment.freeze_level else 1;
            if (!dead and policy.kind == .protopod) try @import("skeeters.zig").pod(self, world, slots, projections, entity, &actor, pose, &body, now);
            if (!dead and policy.kind == .froginator and actor.frog.phase == .jump and body.motion_owner == null) {
                try @import("froginators.zig").jump(&actor, &pose, &body, &velocity, binding.slot, elapsed);
            } else if (!dead and policy.kind == .shark and body.motion_owner == null) {
                try @import("sharks.zig").swim(self, &actor, &pose, &body, &velocity, binding.slot, elapsed, slow);
            } else if (!dead and rat and actor.rat.swimming and body.motion_owner == null) {
                actor.rat.water = try @import("actor_water.zig").move(&self.water_routes, &actor, &pose, &body, &velocity, self.table.definitions[actor.definition].speed * slow, binding.slot, elapsed);
            } else if (!dead and policy.kind == .crox and actor.crox.swimming and body.motion_owner == null) {
                try @import("crox.zig").swim(self, &actor, &pose, &body, &velocity, self.table.definitions[actor.definition], binding.slot, elapsed, slow);
            } else if (!dead and policy.kind == .griffon and body.motion_owner == null) {
                try @import("griffons.zig").step(self, world, slots, projections, entity, &actor, &pose, &body, &velocity, navigation, now, elapsed, slow);
            } else if (!dead and policy.kind == .harpy and body.motion_owner == null) {
                try @import("harpies.zig").step(self, world, slots, projections, entity, &actor, &pose, &body, &velocity, navigation, now, elapsed, slow);
            } else if (!dead and policy.kind == .dragon and body.motion_owner == null) {
                try @import("dragons.zig").step(world, slots, projections, entity, &actor, &pose, body, &velocity, self.table.definitions[actor.definition], now, elapsed);
            } else if (!dead and policy.kind == .garroth and body.motion_owner == null) {
                try @import("garroths.zig").step(self, world, slots, projections, entity, &actor, &pose, &body, &velocity, navigation, now, elapsed, slow);
            } else if (!dead and policy.kind == .stavros and body.motion_owner == null) {
                try @import("stavros_actor.zig").step(self, world, slots, projections, entity, &actor, &pose, &body, &velocity, navigation, now, elapsed, slow);
            } else if (!dead and policy.kind == .wyndrax and body.motion_owner == null) {
                try @import("wyndrax_actor.zig").step(self, world, slots, projections, entity, &actor, &pose, &body, &velocity, navigation, now, elapsed, slow);
            } else if (!dead and policy.kind == .buboid and body.motion_owner == null) {
                try @import("buboids.zig").step(self, world, slots, projections, entity, &actor, &pose, &body, &velocity, navigation, now, elapsed, slow);
            } else if (!dead and policy.kind == .chaingang and body.motion_owner == null) {
                try @import("chaingangs.zig").step(self, world, slots, projections, entity, &actor, &pose, &body, &velocity, navigation, now, elapsed, slow);
            } else if (dead and policy.kind == .chaingang and actor.chaingang.flying and body.motion_owner == null) {
                try @import("actor_flight.zig").bounce(&pose, body, &velocity, binding.slot, elapsed, 1200, 0.5, true);
            } else if (policy.kind == .deathsphere and body.motion_owner == null) {
                if (dead) try @import("actor_flight.zig").bounce(&pose, body, &velocity, binding.slot, elapsed, 1400, 0.5, true) else try @import("deathspheres.zig").step(self, world, slots, projections, entity, &actor, &pose, body, &velocity, now, elapsed, slow);
            } else if (policy.kind == .doombat and body.motion_owner == null) {
                if (dead) try @import("doombats.zig").motion(&pose, body, &velocity, binding.slot, elapsed, self.table.definitions[actor.definition].speed, true) else try @import("doombats.zig").fly(self, world, slots, projections, entity, &actor, &pose, body, &velocity, now, elapsed);
            } else if (!dead and policy.kind == .cambot and body.motion_owner == null) {
                try @import("cambots.zig").fly(self, world, slots, projections, entity, &actor, &pose, body, &velocity, now, elapsed);
            } else if (!dead and policy.kind == .thunderskeet and body.motion_owner == null) {
                try @import("thunderskeets.zig").fly(self, world, slots, projections, entity, &actor, &pose, body, &velocity, now, elapsed);
            } else if (!dead and policy.kind == .skeeter and body.motion_owner == null) {
                try @import("skeeters.zig").fly(self, world, slots, projections, entity, &actor, &pose, body, &velocity, now, elapsed);
            } else if (!dead and policy.kind == .rotworm and actor.rotworm.phase == .ceiling) {
                velocity.linear = @splat(0);
            } else if (policy.kind == .column and actor.column.phase == .asleep) {
                velocity.linear = @splat(0);
            } else try @import("actor_motion.zig").step(&actor, &pose, &body, &velocity, navigation, threat, (if (policy.kind == .crox and actor.crox.wandering) self.table.definitions[actor.definition].walk_speed else self.table.definitions[actor.definition].speed) * slow, binding.slot, now, elapsed);
            if (!dead and actor.evasion.until_ms != null and actor.evasion.kind == .strafe) pose.angles[1] = actor.evasion.yaw;
            if (!dead and rat and actor.rat.strafe and actor.rat.evasion_until != null) pose.angles[1] = actor.rat.strafe_yaw;
            (try world.get(entity, data.Actor)).* = actor;
            (try world.get(entity, data.Transform)).* = pose;
            (try world.get(entity, data.Velocity)).* = velocity;
            (try world.get(entity, data.Body)).* = body;
            try self.publish(world, entity, projections, now);
            if (dead and !actor.death_dispatched) {
                (try world.get(entity, data.Actor)).death_dispatched = true;
                try @import("progression.zig").kill(world, hurt, self.table.definitions[actor.definition].health, self.episode);
                try @import("actor_spawns.zig").death(self, world, slots, projections, router, entity, now);
            }
        }
    }
};
pub fn diagnostics(self: *const Actors, world: *data.World, slots: *const Slots, now: i64) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const actor = world.get(entity, data.Actor) catch continue;
        const pose = (try world.get(entity, data.Transform)).*;
        const body = (try world.get(entity, data.Body)).*;
        const aim = v.add(pose.position, v.scale(v.add(body.mins, body.maxs), 0.5));
        var sight = false;
        if (slots.occupants[0]) |player| {
            const state = (try world.get(player, data.Player)).*;
            const start = v.add((try world.get(player, data.Transform)).position, .{ 0, 0, state.view_height });
            const trace = try engine.collisionService().trace(.{ .start = start, .end = aim, .mins = @splat(0), .maxs = @splat(0), .slot = 0, .mask = c.MASK_SHOT });
            sight = !trace.start_solid and (trace.fraction == 1 or trace.entity == (try world.get(entity, data.Binding)).slot);
        }
        const velocity = (try world.get(entity, data.Velocity)).linear;
        const definition = self.table.definitions[actor.definition];
        const attack_until: i64 = switch (catalog.entries[actor.definition].kind) {
            .skeeter => if (actor.skeeter.phase == .attack) actor.skeeter.until_ms else 0,
            .froginator => if (actor.frog.phase == .spit or actor.frog.phase == .bite) actor.frog.started_ms + definition.attacks[actor.frog.pose()].duration() else 0,
            .crox => if (actor.crox.attacking) actor.crox.started_ms + definition.attacks[actor.crox.pose].duration() else 0,
            .thunderskeet => if (actor.thunder.phase == .attack) actor.thunder.started_ms + definition.attacks[0].duration() else 0,
            else => 0,
        };
        var pending: usize = 0;
        for (actor.rockgat.bursts) |burst| if (burst != null) {
            pending += 1;
        };
        var text: [768]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig actor: id={d} state={s} health={d} pos={d:.3},{d:.3},{d:.3} threat={d} witness={d} class={s} unique={s} path={d} ignore={d} sight={d} aim={d:.3},{d:.3},{d:.3} velocity={d:.3},{d:.3},{d:.3} frog={s} skeeter={s} ground={d} camera_seen={d} camera_alarm={d} ", .{ try world.persistentId(entity), @tagName(actor.mode), (try world.get(entity, data.Health)).current, pose.position[0], pose.position[1], pose.position[2], actor.threat, actor.witness_ms, catalog.entries[actor.definition].classname, actor.unique, actor.path, @intFromBool(actor.ignore_player), @intFromBool(sight), aim[0], aim[1], aim[2], velocity[0], velocity[1], velocity[2], @tagName(actor.frog.phase), @tagName(actor.skeeter.phase), actor.ground_entity, @intFromBool(actor.cambot.seen), actor.cambot.alarmed }));
        engine.print(try std.fmt.bufPrintZ(&text, "crox_water={d} crox_swim={d} crox_wander={d} crox_pose={d} crox_struck={d} gun={s} gun_shots={d} gun_pending={d} gun_frame={d} now={d} attack_left={d} angles={d:.3},{d:.3},{d:.3}\n", .{ actor.crox.water, @intFromBool(actor.crox.swimming), @intFromBool(actor.crox.wandering), actor.crox.pose, @intFromBool(actor.crox.struck), @tagName(actor.rockgat.phase), actor.rockgat.shots, pending, actor.rockgat.frame(now), now, @max(0, attack_until - now), pose.angles[0], pose.angles[1], pose.angles[2] }));
    }
    engine.print("dk3 zig actor states complete\n");
}
