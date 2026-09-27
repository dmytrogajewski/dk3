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
    episode: u8 = 1,
    allocator: std.mem.Allocator = undefined,
    event_bytes: []const u8 = "",
    animations: [catalog.entries.len]bool = @splat(false),
    metadata: [catalog.entries.len][]const u8 = @splat(""),
    air_routes: @import("air_routes.zig").Routes = .{},
    air_ready: bool = false,
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
                if (catalog.find(object.classname) != null) {
                    candidates[count] = entity;
                    count += 1;
                }
            };
        }
        for (candidates[0..count]) |entity| try self.spawnOne(world, slots, projections, entity, now);
    }
    fn ensure(self: *Actors, id: u8) !void {
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
            .froginator => &catalog.froginator.attacks,
            else => &.{},
        };
        for (attacks, 0..) |attack, i| {
            definition.attacks[i] = try animation.find(metadata, attack) orelse return error.MissingActorAttack;
            const row = try self.event(policy.classname, attack);
            definition.attack_sounds[i] = row.field("sound1") orelse "";
            const strike = try row.number("strike1", 0);
            if (strike < 0 or strike > @as(f32, @floatFromInt(definition.attacks[i].last - definition.attacks[i].first))) return error.InvalidActorStrike;
            definition.strikes[i] = @intFromFloat(strike);
            const second = try row.number("strike2", 0);
            if (second < 0 or second > @as(f32, @floatFromInt(definition.attacks[i].last - definition.attacks[i].first))) return error.InvalidActorStrike;
            definition.second_strikes[i] = if (second > 0) @intFromFloat(second) else null;
            definition.attack_sound_ms[i] = @intFromFloat(try row.number("frame1", 0) * 1000 / @as(f32, @floatFromInt(definition.attacks[i].fps)));
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
        const id = catalog.find(object.classname) orelse return error.UnknownActorClass;
        try self.ensure(id);
        const definition = self.table.definitions[id];
        const health = try @import("properties.zig").number(object, "health", @floatFromInt(definition.health));
        if (health <= 0) return error.InvalidActorHealth;
        try world.put(entity, data.Actor{ .unique = @import("properties.zig").text(object, "uniqueid") orelse "", .ignore_player = object.flags & 16 != 0, .path = if (object.flags & 2 != 0 and object.target.len > 0) if (@import("scripts.zig").named(world, object.target)) |point| try world.persistentId(point) else 0 else 0, .definition = id, .changed_ms = now, .think_ms = now, .guard = .{ .random = try world.persistentId(entity) } });
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
        try self.publish(world, entity, projections, now);
    }
    pub fn spawnDynamic(self: *Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, classname: []const u8, position: v.Vec3, angles: v.Vec3, now: i64) !ecs.Entity {
        const entity = try world.create(null, .{ data.MapObject{ .classname = classname }, data.Transform{ .position = position, .angles = angles } });
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
        const sequence = if (actor.scripted_pose != null and actor.mode != .dead) actor.scripted_pose.? else if (hatching) definition.hatch else switch (actor.mode) {
            .idle => definition.idle,
            .flee, .chase => if (actor.path != 0 and actor.moving_pose != null) actor.moving_pose.? else definition.run,
            .attack => definition.attacks[if (policy.kind == .froginator) actor.frog.pose() else actor.guard.pose],
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
        projection.state.frame = sequence.frame(now - (if (actor.scripted_pose != null and actor.mode != .dead) actor.scripted_ms else if (policy.kind == .froginator and actor.mode == .attack) actor.frog.started_ms else if (policy.kind == .skeeter and (actor.mode == .attack or hatching)) actor.skeeter.started_ms else if (policy.kind == .mishima_guard and (actor.mode == .attack or actor.mode == .reload)) actor.guard.started_ms else actor.changed_ms), !hatching and (actor.mode == .idle or actor.mode == .flee or actor.mode == .chase));
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
            if (dead and actor.mode != .dead) {
                actor.mode = .dead;
                actor.changed_ms = now;
                body.contents = c.CONTENTS_CORPSE;
                // Retain supplied horizontal bounds; final-pose corpse bounds remain to qualify.
                body.maxs[2] = @min(body.maxs[2], 0);
            }
            const policy = catalog.entries[actor.definition];
            if (!dead and @import("nightmare.zig").frozen(world, entity)) {
                try self.publish(world, entity, projections, now);
                continue;
            }
            const script = world.get(entity, data.Script) catch null;
            const acting = script != null and script.?.active;
            const following = actor.path != 0 and (actor.ignore_player or actor.threat == 0);
            if (!dead and body.motion_owner == null and (acting or following)) {
                var velocity = (try world.get(entity, data.Velocity)).*;
                const definition = self.table.definitions[actor.definition];
                const speed = if (policy.kind == .civilian) definition.walk_speed else definition.speed;
                const point = if (!acting and following) try @import("scripts.zig").path(world, slots, projections, router, entity, &actor, pose, speed, now) else null;
                actor.mode = if (point != null) .chase else .idle;
                if (policy.kind == .skeeter) {
                    velocity.linear = @splat(0);
                    if (point) |destination| if (try self.air_routes.next(pose.position, destination, body, binding.slot)) |waypoint| {
                        const delta = v.subtract(waypoint, pose.position);
                        velocity.linear = v.scale(v.normalize(delta), @min(speed, v.length(delta) * 10));
                        pose.angles[1] = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
                    };
                    try @import("actor_flight.zig").move(&pose, body, &velocity, binding.slot, elapsed);
                } else {
                    if (point) |destination| actor.threat_position = destination;
                    try @import("actor_motion.zig").step(&actor, &pose, &body, &velocity, navigation, actor.threat_position, speed, binding.slot, now, elapsed);
                }
                (try world.get(entity, data.Actor)).* = actor;
                (try world.get(entity, data.Transform)).* = pose;
                (try world.get(entity, data.Velocity)).* = velocity;
                (try world.get(entity, data.Body)).* = body;
                try self.publish(world, entity, projections, now);
                continue;
            }
            if (!dead and policy.kind == .mishima_guard) try @import("hostiles.zig").guard(world, slots, projections, entity, &actor, &pose, self.table.definitions[actor.definition], now);
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
            var velocity = (try world.get(entity, data.Velocity)).*;
            if (!dead and policy.kind == .froginator and body.motion_owner == null) try @import("froginators.zig").think(world, slots, projections, entity, &actor, &pose, body, &velocity, self.table.definitions[actor.definition], now);
            const threat = if (world.find(actor.threat)) |source| (try world.get(source, data.Transform)).position else actor.threat_position;
            const slow = if (world.get(entity, data.Ailments) catch null) |ailment| 1 - 0.8 * ailment.freeze_level else 1;
            if (!dead and policy.kind == .protopod) try @import("skeeters.zig").pod(self, world, slots, projections, entity, &actor, pose, &body, now);
            if (!dead and policy.kind == .froginator and actor.frog.phase == .jump and body.motion_owner == null) {
                try @import("froginators.zig").jump(&actor, &pose, &body, &velocity, binding.slot, elapsed);
            } else if (!dead and policy.kind == .skeeter and body.motion_owner == null) {
                try @import("skeeters.zig").fly(self, world, slots, projections, entity, &actor, &pose, body, &velocity, now, elapsed);
            } else try @import("actor_motion.zig").step(&actor, &pose, &body, &velocity, navigation, threat, self.table.definitions[actor.definition].speed * slow, binding.slot, now, elapsed);
            (try world.get(entity, data.Actor)).* = actor;
            (try world.get(entity, data.Transform)).* = pose;
            (try world.get(entity, data.Velocity)).* = velocity;
            (try world.get(entity, data.Body)).* = body;
            try self.publish(world, entity, projections, now);
            if (dead and !actor.death_dispatched) {
                (try world.get(entity, data.Actor)).death_dispatched = true;
                try @import("progression.zig").kill(world, hurt, self.table.definitions[actor.definition].health, self.episode);
                try router.fire(world, slots, projections, entity, hurt.source, now);
            }
        }
    }
};
pub fn diagnostics(world: *data.World, slots: *const Slots) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const actor = world.get(entity, data.Actor) catch continue;
        const pose = (try world.get(entity, data.Transform)).*;
        var text: [384]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig actor: id={d} state={s} health={d} pos={d:.3},{d:.3},{d:.3} threat={d} witness={d} class={s} unique={s} path={d} ignore={d}\n", .{ try world.persistentId(entity), @tagName(actor.mode), (try world.get(entity, data.Health)).current, pose.position[0], pose.position[1], pose.position[2], actor.threat, actor.witness_ms, catalog.entries[actor.definition].classname, actor.unique, actor.path, @intFromBool(actor.ignore_player) }));
    }
}
