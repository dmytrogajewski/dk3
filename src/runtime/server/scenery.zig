// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored episode decorations: collision, animation, breakage and moving debris.
const std = @import("std");
const data = @import("../domain/components.zig");
const policy = @import("../domain/scenery.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");

pub fn spawn(allocator: std.mem.Allocator, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    var tables: [4]?[]const u8 = @splat(null);
    var entities: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (policy.owns(object.classname)) {
            entities[count] = entity;
            count += 1;
        };
    }
    for (entities[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        const episode = object.classname[6] - '1';
        if (tables[episode] == null) {
            var path: [64]u8 = undefined;
            tables[episode] = try @import("../engine/files.zig").read(.server, &engine.gateway, allocator, try std.fmt.bufPrintZ(&path, "dk3/tables/e{d}decoinfo.cfg", .{episode + 1}), 4 * 1024 * 1024);
        }
        const definition = try policy.find(tables[episode].?, object.model);
        const material: policy.Material = if (object.flags & 8 != 0) .wood else if (object.flags & 16 != 0) .metal else if (object.flags & 32 != 0) .glass else if (object.flags & 64 != 0) .flesh else definition.material;
        const scale = try prop.number(object, "scale", 1);
        var state: data.Scenery = .{
            .model = definition.model,
            .movement = definition.movement,
            .material = material,
            .started_ms = now,
            .scale = @splat(if (scale < 0.01) 1 else scale),
            .breakable = object.flags & 2 == 0 and (material != .unbreakable or definition.exploding or object.flags & 1 != 0),
            .explosive = object.flags & 1 != 0,
            .damage = @max(0, try prop.number(object, "damage", 25)),
            .alpha = if (object.flags & 256 != 0) std.math.clamp(try prop.number(object, "alpha", 1), 0, 1) else 1,
            .spin = .{ try prop.number(object, "y_speed", 0), try prop.number(object, "z_speed", 0), try prop.number(object, "x_speed", 0) },
        };
        const sequence: usize = @intFromFloat(std.math.clamp(try prop.number(object, "animseq", 0), 0, 4));
        if (definition.count > sequence) {
            state.sequence = definition.sequences[sequence].frames;
            state.looping = definition.sequences[sequence].looping;
        } else if (definition.count == 0) state.sequence = .{ .last = @intFromFloat(std.math.clamp(try prop.number(object, "frame", 0), 0, 65535)), .fps = 20 };
        var body: data.Body = .{
            .mins = @splat(std.math.inf(f32)),
            .maxs = @splat(-std.math.inf(f32)),
            .contents = if (definition.solid) c.CONTENTS_SOLID else 0,
            .collision_mask = c.MASK_PLAYERSOLID,
            .mass = @max(1, try prop.number(object, "mass", definition.mass)),
        };
        const angles = (try world.get(entity, data.Transform)).angles;
        for (0..8) |corner| {
            const point = @import("../domain/poses.zig").rotate(.{ if (corner & 1 == 0) definition.mins[0] else definition.maxs[0], if (corner & 2 == 0) definition.mins[1] else definition.maxs[1], if (corner & 4 == 0) definition.mins[2] else definition.maxs[2] }, @splat(0), angles);
            for (point, 0..) |value, axis| {
                body.mins[axis] = @min(body.mins[axis], value);
                body.maxs[axis] = @max(body.maxs[axis], value);
            }
        }
        try world.put(entity, state);
        try world.put(entity, body);
        try world.put(entity, data.Velocity{});
        try world.put(entity, data.Random{ .state = try world.persistentId(entity) });
        if (state.breakable) {
            const health: i32 = @intFromFloat(@max(1, try prop.number(object, "health", @floatFromInt(definition.health))));
            try world.put(entity, data.Health{ .current = health, .maximum = health });
            try world.put(entity, data.Hurt{});
        }
        try @import("weapon_entities.zig").bind(world, slots, projections, entity, state.model);
        try publish(world, entity, projections, now);
    }
}

pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const state = (try world.get(entity, data.Scenery)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    projection.state.frame = state.sequence.frame(now - state.started_ms, state.looping);
    projection.state.generic1 = if (state.explosion) policy.explosion_tag else policy.render_tag;
    projection.state.time2 = @intFromFloat(state.alpha * 255);
    projection.state.angles2 = state.scale;
    projection.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = @bitCast(body.contents);
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    if (state.broken) projection.shared.svFlags |= c.SVF_NOCLIENT;
    engine.link(projection);
}

fn fragments(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const state = (try world.get(entity, data.Scenery)).*;
    if (state.material == .unbreakable) return;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    var random = (try world.get(entity, data.Random)).*;
    const sizes = v.subtract(body.maxs, body.mins);
    const flesh = state.material == .flesh;
    const large: usize = if (flesh) @intFromFloat(@min(6, body.mass / 100)) else if (body.mass >= 400) @intFromFloat(@min(7, body.mass / 100)) else 0;
    const small: usize = if (flesh) 0 else @intFromFloat(@min(16, body.mass / 30));
    for (0..large + small) |index| {
        const big = index < large;
        var path: [64]u8 = undefined;
        const model = if (flesh) ([_][]const u8{ "models/global/e_gibtorso.dkm", "models/global/e_gibleg.dkm", "models/global/e_gibfoot.dkm", "models/global/e_gibhand.dkm", "models/global/e_gibhead.dkm", "models/global/e_gibchest.dkm" })[index] else try std.fmt.bufPrint(&path, "models/global/e_{s}{d}.dkm", .{ switch (state.material) {
            .wood => "wood",
            .metal => "metal",
            .glass => "glass",
            else => unreachable,
        }, if (big) @as(u8, 1) else 2 });
        // Registry owns its copy; dynamic state uses a stable model name below.
        const model_index = try @import("resources.zig").model(model);
        const model_name = @import("resources.zig").modelName(model_index);
        var origin = pose.position;
        var scale: v.Vec3 = undefined;
        var direction: v.Vec3 = undefined;
        var spin: v.Vec3 = undefined;
        for (0..3) |axis| {
            origin[axis] += (random.next() - 0.5) * sizes[axis] * 0.5;
            scale[axis] = if (flesh) 1 else if (big) 1 + random.next() * 2 else 0.5 + random.next();
            direction[axis] = random.next() * 2 - 1;
            spin[axis] = random.next() * 600;
        }
        var velocity = v.scale(v.normalize(direction), if (big) 250 else 350);
        for (&velocity) |*value| value.* += (random.next() - 0.5) * 100;
        velocity[2] += 100;
        const fragment = try world.create(null, .{ data.Transform{ .position = origin }, data.Velocity{ .linear = velocity }, data.Body{ .mins = @splat(0), .maxs = @splat(0), .collision_mask = c.MASK_SOLID }, data.Scenery{
            .model = model_name,
            .movement = .bounce,
            .started_ms = now,
            .scale = scale,
            .spin = spin,
            .alpha = if (state.material == .glass) 0.75 else 1,
            .fragment = true,
            .expires_ms = now + 5000 + @as(i64, @intFromFloat(random.next() * 5000)),
        } });
        try @import("weapon_entities.zig").bind(world, slots, projections, fragment, model_name);
        try publish(world, fragment, projections, now);
    }
    var sound: [64]u8 = undefined;
    const path = if (flesh) try std.fmt.bufPrint(&sound, "global/m_gibslop{c}.wav", .{@as(u8, 'a') + @as(u8, @intFromFloat(random.next() * 4))}) else try std.fmt.bufPrint(&sound, "global/e_{s}breaks{c}.wav", .{ switch (state.material) {
        .wood => "wood",
        .metal => "metal",
        .glass => "glass",
        else => unreachable,
    }, @as(u8, 'a') + @as(u8, @intFromFloat(random.next() * 5)) });
    try @import("events.zig").sound(world, slots, projections, path, pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
    (try world.get(entity, data.Random)).* = random;
}

fn destroy(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, entity: ecs.Entity, now: i64) !void {
    const state = (try world.get(entity, data.Scenery)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const attacker = (try world.get(entity, data.Hurt)).source;
    const binding = (try world.get(entity, data.Binding)).*;
    (try world.get(entity, data.Body)).contents = 0;
    projections[binding.slot].shared.contents = 0;
    engine.link(&projections[binding.slot]);
    if (state.explosive) {
        try @import("area_damage.zig").apply(world, slots, .{ .owner = attacker, .weapon = 0, .origin = pose.position, .damage = state.damage, .radius = 100, .skip_slot = binding.slot, .self_scale = 1 }, now);
        try @import("events.zig").sound(world, slots, projections, "global/e_explode1.wav", pose.position, c.ENTITYNUM_NONE, c.CHAN_AUTO, now);
        try explosion(world, slots, projections, pose.position, 1, now);
    }
    try fragments(world, slots, projections, entity, now);
    // Capture the drop before targets can delete the decoration itself.
    const spawnname = prop.text((try world.get(entity, data.MapObject)).*, "spawnname") orelse "";
    if (spawnname.len > 0) {
        const actors = router.actors orelse return error.MissingActorDefinitions;
        if (@import("actor_catalog").find(spawnname) != null) _ = try actors.spawnDynamic(world, slots, projections, spawnname, pose.position, pose.angles, now) else if (std.mem.startsWith(u8, spawnname, "monster_")) return error.UnknownActorClass else _ = try @import("items.zig").spawnDynamic(world, slots, projections, spawnname, pose, now, actors.episode);
    }
    (try world.get(entity, data.Scenery)).broken = true;
    try publish(world, entity, projections, now);
    // Keep an inert source identity for delayed targets and visited-world restoration.
    try router.fire(world, slots, projections, entity, attacker, now);
}

pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, now: i64, elapsed: u32) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        const state = world.get(entity, data.Scenery) catch continue;
        if (state.broken) continue;
        if (state.gib != null and try @import("actor_gibs.zig").update(world, entity, state, (try world.get(entity, data.Body)).*, now)) {
            try @import("weapon_entities.zig").remove(world, slots, projections, entity);
            continue;
        }
        if (state.expires_ms) |deadline| if (now >= deadline) {
            try @import("weapon_entities.zig").remove(world, slots, projections, entity);
            continue;
        };
        if (state.breakable and (try world.get(entity, data.Health)).current <= 0) {
            if (state.breaking_ms == null) state.breaking_ms = now + 100 + @as(i64, @intFromFloat((try world.get(entity, data.Random)).next() * 4)) * 100;
            if (now >= state.breaking_ms.?) {
                try destroy(world, slots, projections, router, entity, now);
                continue;
            }
        }
        const pose = try world.get(entity, data.Transform);
        const body = try world.get(entity, data.Body);
        const velocity = try world.get(entity, data.Velocity);
        const slot = (try world.get(entity, data.Binding)).slot;
        if (!@import("attachments.zig").attached(world, entity)) {
            if (!body.grounded or !state.fragment) pose.angles = v.add(pose.angles, v.scale(state.spin, @as(f32, @floatFromInt(elapsed)) * 0.001));
            if (state.movement != .stationary) {
                var remaining = elapsed;
                while (remaining > 0) {
                    const delta = @as(f32, @floatFromInt(@min(remaining, 50))) * 0.001;
                    remaining -= @min(remaining, 50);
                    velocity.linear[2] -= 800 * delta;
                    const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity.linear, delta)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
                    if (hit.start_solid or hit.all_solid) {
                        velocity.linear = @splat(0);
                        break;
                    }
                    pose.position = hit.end;
                    body.grounded = false;
                    if (hit.fraction < 1) {
                        velocity.linear = if (state.gib != null) try @import("actor_gibs.zig").contact(world, entity, state, velocity.linear, hit.normal) else policy.contact(velocity.linear, hit.normal, state.movement == .bounce);
                        body.grounded = hit.normal[2] > 0.7 and velocity.linear[2] == 0;
                        projections[slot].state.groundEntityNum = if (body.grounded) hit.entity else c.ENTITYNUM_NONE;
                    }
                }
            }
        }
        try publish(world, entity, projections, now);
    }
}

pub fn explosion(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, origin: data.Vec3, scale: f32, now: i64) !void {
    const effect = try world.create(null, .{ data.Transform{ .position = origin }, data.Velocity{}, data.Body{ .mins = @splat(0), .maxs = @splat(0) }, data.Scenery{ .model = "models/global/we_expl.sp2", .started_ms = now, .scale = @splat(scale), .explosion = true, .sequence = .{ .last = 6 }, .expires_ms = now + 700 } });
    errdefer world.destroy(effect) catch unreachable;
    try @import("weapon_entities.zig").bind(world, slots, projections, effect, "models/global/we_expl.sp2");
    try publish(world, effect, projections, now);
}
