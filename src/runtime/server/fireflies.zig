// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("actor_catalog").firefly;
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    var sources: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.mem.eql(u8, object.classname, policy.classname)) {
            sources[count] = entity;
            count += 1;
        };
    }
    for (sources[0..count]) |source| {
        const object = (try world.get(source, data.MapObject)).*;
        const pose = (try world.get(source, data.Transform)).*;
        const id = try world.persistentId(source);
        var random: data.Random = .{ .state = id };
        const flies: usize = @intFromFloat(std.math.clamp(try prop.number(object, "count", 4), 1, 10));
        const color = if (prop.text(object, "_color")) |text| try @import("map.zig").vector(text) else @as(v.Vec3, @splat(1));
        for (0..flies) |_| {
            const scale = try prop.number(object, "scale", 0.5);
            const state: data.Firefly = .{
                .source = id,
                .shape = policy.shape(object.flags),
                .distance = std.math.clamp(try prop.number(object, "distance", 75), 20, 200),
                .speed = std.math.clamp(try prop.number(object, "velocity", 55), 1, 500),
                .scale = if (scale == 0) 1 else @max(0.01, scale),
                .color = color,
                .displayed_color = color,
                .color2 = if (prop.text(object, "color2")) |text| try @import("map.zig").vector(text) else @splat(0),
                .maximum_alpha = std.math.clamp(try prop.number(object, "alpha_level", 0.75), 0, 1),
                .delta_alpha = std.math.clamp(try prop.number(object, "delta_alpha", 0), 0, 1),
                .personality = @max(0.25, random.next()),
                .next_ms = now + 400 + @as(i64, @intFromFloat(random.next() * 500)),
                .previous = pose.position,
            };
            const fly = try world.create(null, .{ pose, state, data.Random{ .state = random.state }, data.Velocity{}, data.Body{ .mins = @splat(-1), .maxs = @splat(1), .collision_mask = c.MASK_WATER } });
            try @import("weapon_entities.zig").bind(world, slots, projections, fly, policy.models[state.shape]);
            try publish(world, fly, projections);
        }
    }
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.Firefly)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    projection.state.generic1 = policy.render_tag;
    projection.state.frame = state.shape;
    projection.state.time2 = @intFromFloat(std.math.clamp(state.alpha, 0, 1) * 255);
    projection.state.angles2 = .{ state.scale, 0, 0 };
    projection.state.origin2 = state.displayed_color;
    projection.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    projection.shared.currentOrigin = pose.position;
    projection.shared.mins = @splat(-1);
    projection.shared.maxs = @splat(1);
    projection.shared.contents = 0;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64, elapsed: u32) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        const state = world.get(entity, data.Firefly) catch continue;
        const source = world.find(state.source) orelse {
            try @import("weapon_entities.zig").remove(world, slots, projections, entity);
            continue;
        };
        const pose = try world.get(entity, data.Transform);
        const velocity = try world.get(entity, data.Velocity);
        const random = try world.get(entity, data.Random);
        if (now >= state.next_ms) {
            state.next_ms = now + 100;
            state.alpha_count += 1;
            if (state.alpha_count >= @as(u3, @intFromFloat(state.personality * 5))) {
                state.alpha_count = 0;
                state.alpha += if (state.alpha_up) state.delta_alpha else -state.delta_alpha;
                if (state.alpha < 0.01) state.alpha_up = true;
                if (state.alpha > state.maximum_alpha) state.alpha_up = false;
            }
            if (v.dot(state.color2, state.color2) > 0) {
                const from = if (state.color_forward) state.color else state.color2;
                const to = if (state.color_forward) state.color2 else state.color;
                state.displayed_color = v.add(from, v.scale(v.subtract(to, from), @min(1, state.color_fraction)));
                if (state.color_fraction >= 1) {
                    state.color_forward = !state.color_forward;
                    state.color_fraction = 0;
                }
                state.color_fraction += state.personality * 0.25;
            }
            const home = (try world.get(source, data.Transform)).position;
            const delta = v.subtract(home, pose.position);
            velocity.linear = state.direction;
            if (v.length(delta) >= state.distance or std.mem.eql(f32, &pose.position, &state.previous)) {
                state.outward = false;
                state.direction = v.scale(v.normalize(delta), state.speed);
                if (random.next() > 0.5) state.personality = @max(0.25, random.next());
            }
            if (!state.outward and v.length(delta) <= 10) {
                state.outward = true;
                for (&state.direction) |*axis| axis.* = (random.next() * 2 - 1) * state.speed;
                if (random.next() > 0.5) state.personality = @max(0.25, random.next());
            }
            state.previous = pose.position;
            const phase = (1 + @as(f32, @floatFromInt(state.phase)) * 30) * std.math.pi / 180;
            const strength = state.speed / (2 * state.personality);
            if (random.next() > state.personality) velocity.linear[1] += @cos(phase) * strength else velocity.linear[0] += @sin(phase) * strength;
            velocity.linear[2] += @sin(phase) * strength;
            state.phase = if (state.phase == 11) 0 else state.phase + 1;
        }
        try @import("actor_flight.zig").move(pose, (try world.get(entity, data.Body)).*, velocity, (try world.get(entity, data.Binding)).slot, elapsed);
        try publish(world, entity, projections);
    }
}
