// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/gib_emitter.zig");
const v = @import("../domain/vector.zig");
const prop = @import("properties.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const Slots = @import("../engine/slots.zig").Slots;
pub fn initialize(world: *data.World, entity: ecs.Entity, now: i64) !policy.State {
    const object = (try world.get(entity, data.MapObject)).*;
    var random: data.Random = .{ .state = try world.persistentId(entity) };
    var state: policy.State = .{ .flags = object.flags, .next_ms = now + 1050 + @as(i64, @intFromFloat(random.next() * 1500)) };
    // Authoring keys are case-insensitive.
    for (object.properties) |property| {
        if (std.ascii.eqlIgnoreCase(property.key, "count")) state.count = @intFromFloat(std.math.clamp(@trunc(try prop.number(object, property.key, 3)), 1, 10));
        if (std.ascii.eqlIgnoreCase(property.key, "spread")) state.spread = @trunc(try prop.number(object, property.key, 10));
        if (std.ascii.eqlIgnoreCase(property.key, "velocity")) state.speed = std.math.clamp(@trunc(try prop.number(object, property.key, 85)), 1, 600);
        if (std.ascii.eqlIgnoreCase(property.key, "scale")) state.scale = std.math.clamp(try prop.number(object, property.key, 1), 0.01, 200);
        if (std.ascii.eqlIgnoreCase(property.key, "stoptime")) state.duration_ms = try prop.milliseconds(object, property.key, 1);
        if (std.ascii.eqlIgnoreCase(property.key, "min")) state.parameters.minimum = try prop.number(object, property.key, 128);
        if (std.ascii.eqlIgnoreCase(property.key, "max")) state.parameters.maximum = try prop.number(object, property.key, 512);
        if (std.ascii.eqlIgnoreCase(property.key, "volume")) state.parameters.volume = try @import("../domain/audio.zig").wireVolume(try prop.number(object, property.key, 0.75));
    }
    if (!state.parameters.valid()) return error.InvalidGibSound;
    try world.put(entity, random);
    return state;
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.WorldControl)).action.gib_emitter;
    if (state.next_ms == null or now < state.next_ms.?) return;
    const object = (try world.get(entity, data.MapObject)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    if (!state.initialized) {
        state.initialized = true;
        if (object.target.len > 0) {
            state.direction = pose.position; // Missing named target retains the authored class fallback.
            const targets = try @import("names.zig").named(world, object.target);
            if (targets.count > 0) state.direction = v.normalize(v.subtract((try world.get(world.find(targets.ids[0]).?, data.Transform)).position, pose.position));
        }
        state.next_ms = if (state.flags & 8 != 0) now + 100 else null;
        state.until_ms = now + state.duration_ms;
        (try world.get(entity, data.WorldControl)).action.gib_emitter = state;
        return;
    }
    const emit = state.emit(now);
    (try world.get(entity, data.WorldControl)).action.gib_emitter = state;
    if (!emit or engine.integer("gib_enable") == 0) return;
    var random = (try world.get(entity, data.Random)).*;
    const available = 100 - @min(100, @import("actor_gibs.zig").total(world));
    const robotic = state.flags & 1 != 0;
    const bone = !robotic and state.flags & 2 != 0;
    const model = if (bone) "models/global/g_bone.dkm" else @import("../domain/gibs.zig").model(0);
    for (0..@min(state.count, available)) |index| {
        var angles = pose.angles;
        const directed = v.length(state.direction) != 0;
        if (directed) angles = .{ -std.math.atan2(state.direction[2], @sqrt(state.direction[0] * state.direction[0] + state.direction[1] * state.direction[1])) * 180 / std.math.pi, std.math.atan2(state.direction[1], state.direction[0]) * 180 / std.math.pi, 0 };
        angles[1] += (random.next() * 2 - 1) * state.spread * (if (directed) @as(f32, 0.5) else 1);
        angles[0] += (random.next() * 2 - 1) * state.spread * (if (directed) @as(f32, 0.2) else 1);
        const velocity = v.scale(v.basis(angles).forward, state.speed * (1 + 0.25 * (random.next() * 2 - 1)));
        const bounds: v.Vec3 = if (bone) .{ 0.5, 5, 0.1 } else @splat(2);
        const fragment = try world.create(null, .{
            data.Transform{ .position = pose.position },                                                                                                                                                                                                    data.Velocity{ .linear = velocity },
            data.Body{ .mins = v.scale(bounds, -1), .maxs = bounds, .mass = 10, .contents = c.CONTENTS_SOLID, .collision_mask = c.MASK_DEADSOLID },                                                                                                         data.Random{ .state = random.state ^ @as(u32, @intCast(index)) },
            data.Scenery{ .model = model, .movement = .bounce, .started_ms = now, .scale = @splat(state.scale), .spin = velocity, .fragment = true, .gib = .{ .next_ms = now + 100, .robotic = robotic, .bone = bone, .no_blood = state.flags & 4 != 0 } },
        });
        try @import("weapon_entities.zig").bind(world, slots, projections, fragment, model);
        try @import("scenery.zig").publish(world, fragment, projections, now);
        if (index % 2 != 0) {
            var path: [64]u8 = undefined;
            const sample = try std.fmt.bufPrint(&path, "global/m_gib{s}{c}.wav", .{ if (robotic) @as([]const u8, "surf") else "slop", @as(u8, 'a') + @as(u8, @intFromFloat(random.next() * (if (robotic) @as(f32, 2) else 4))) });
            try @import("events.zig").configuredSound(world, slots, projections, sample, pose.position, (try world.get(fragment, data.Binding)).slot, c.CHAN_AUTO, now, state.parameters);
        }
    }
    (try world.get(entity, data.Random)).* = random;
}
