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
    pub fn spawn(self: *Actors, allocator: std.mem.Allocator, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
        const bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, "dk3/tables/aidata.cfg", 4 * 1024 * 1024);
        self.table = try rules.Table.parse(bytes);
        const event_bytes = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, "dk3/tables/actor_events.cfg", 4 * 1024 * 1024);
        var animations: [catalog.entries.len]bool = @splat(false);
        var candidates: [ecs.max_entities]ecs.Entity = undefined;
        var count: usize = 0;
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
        {
            defer query.deinit();
            while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| {
                if (catalog.find(object.classname) != null) {
                    candidates[count] = entity;
                    count += 1;
                }
            };
        }
        for (candidates[0..count]) |entity| {
            const object = (try world.get(entity, data.MapObject)).*;
            const id = catalog.find(object.classname).?;
            const definition = &self.table.definitions[id];
            if (!definition.loaded) return error.MissingActorDefinition;
            if (!animations[id]) {
                var path: [80]u8 = undefined;
                const name = try std.fmt.bufPrintZ(&path, "{s}.anim", .{definition.model});
                const metadata = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, name, 1 << 20);
                const policy = catalog.entries[id];
                definition.idle = try @import("../domain/animation.zig").find(metadata, policy.idle) orelse return error.MissingActorIdle;
                definition.run = try @import("../domain/animation.zig").find(metadata, policy.run) orelse return error.MissingActorRun;
                definition.death = try @import("../domain/animation.zig").find(metadata, policy.death) orelse return error.MissingActorDeath;
                if (policy.kind == .mishima_guard) {
                    for (catalog.mishima.attacks, 0..) |attack, i| {
                        definition.attacks[i] = try @import("../domain/animation.zig").find(metadata, attack) orelse return error.MissingActorAttack;
                        var reader = try @import("../domain/tables.zig").Reader.init(event_bytes);
                        var found = false;
                        while (try reader.next()) |row| {
                            if (!std.mem.eql(u8, row.field("classname") orelse "", policy.classname) or !std.mem.eql(u8, row.field("animation") orelse "", attack)) continue;
                            definition.attack_sounds[i] = row.field("sound1") orelse "";
                            const frame = try row.number("strike1", 1);
                            if (frame < 0 or frame > @as(f32, @floatFromInt(definition.attacks[i].last - definition.attacks[i].first))) return error.InvalidActorStrike;
                            definition.strikes[i] = @intFromFloat(frame);
                            found = true;
                            break;
                        }
                        if (!found) return error.MissingActorAttackEvent;
                    }
                    definition.reload = try @import("../domain/animation.zig").find(metadata, catalog.mishima.reload_animation) orelse return error.MissingActorReload;
                }
                animations[id] = true;
            }
            const health = try @import("properties.zig").number(object, "health", @floatFromInt(definition.health));
            if (health <= 0) return error.InvalidActorHealth;
            try world.put(entity, data.Actor{ .definition = id, .changed_ms = now, .guard = .{ .random = try world.persistentId(entity) } });
            try world.put(entity, data.Hurt{});
            try world.put(entity, data.Health{ .current = @intFromFloat(health), .maximum = @intFromFloat(health) });
            try world.put(entity, data.Velocity{});
            try world.put(entity, data.Body{ .mins = definition.mins, .maxs = definition.maxs, .contents = c.CONTENTS_BODY, .collision_mask = c.MASK_PLAYERSOLID });
            const model = try @import("resources.zig").model(definition.model);
            const slot = try slots.acquire(entity, null);
            try world.put(entity, data.Binding{ .slot = slot, .model = model });
            projections[slot] = std.mem.zeroes(abi.EntityProjection);
            try self.publish(world, entity, projections, now);
        }
    }
    fn publish(self: *const Actors, world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
        const actor = (try world.get(entity, data.Actor)).*;
        const definition = self.table.definitions[actor.definition];
        const pose = (try world.get(entity, data.Transform)).*;
        const body = (try world.get(entity, data.Body)).*;
        const binding = (try world.get(entity, data.Binding)).*;
        const sequence = switch (actor.mode) {
            .idle => definition.idle,
            .flee, .chase => definition.run,
            .attack => definition.attacks[actor.guard.pose],
            .reload => definition.reload,
            .dead => definition.death,
        };
        const projection = &projections[binding.slot];
        projection.state.number = binding.slot;
        projection.state.eType = c.ET_GENERAL;
        projection.state.modelindex = binding.model;
        projection.state.angles2 = definition.scale;
        projection.state.groundEntityNum = actor.ground_entity;
        projection.state.frame = sequence.frame(now - (if (actor.mode == .attack or actor.mode == .reload) actor.guard.started_ms else actor.changed_ms), actor.mode == .idle or actor.mode == .flee or actor.mode == .chase);
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
            const threat = if (world.find(actor.threat)) |source| (try world.get(source, data.Transform)).position else actor.threat_position;
            try @import("actor_motion.zig").step(&actor, &pose, &body, &velocity, navigation, threat, self.table.definitions[actor.definition].speed, binding.slot, now, elapsed);
            (try world.get(entity, data.Actor)).* = actor;
            (try world.get(entity, data.Transform)).* = pose;
            (try world.get(entity, data.Velocity)).* = velocity;
            (try world.get(entity, data.Body)).* = body;
            try self.publish(world, entity, projections, now);
            if (dead and !actor.death_dispatched) {
                (try world.get(entity, data.Actor)).death_dispatched = true;
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
        var text: [240]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig actor: id={d} state={s} health={d} pos={d:.3},{d:.3},{d:.3} threat={d} witness={d}\n", .{ try world.persistentId(entity), @tagName(actor.mode), (try world.get(entity, data.Health)).current, pose.position[0], pose.position[1], pose.position[2], actor.threat, actor.witness_ms }));
    }
}
