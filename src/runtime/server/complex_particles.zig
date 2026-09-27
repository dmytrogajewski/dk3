// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/complex_particles.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
pub fn initialize(world: *data.World, entity: ecs.Entity, now: i64) !policy.State {
    const object = (try world.get(entity, data.MapObject)).*;
    var random: data.Random = .{ .state = try world.persistentId(entity) };
    var state: policy.State = .{ .flags = object.flags, .outside = object.flags & 4096 != 0, .next_ms = now + 1750 + @as(i64, @intFromFloat(random.next() * 1500)) };
    for (object.properties) |property| {
        if (std.ascii.eqlIgnoreCase(property.key, "count")) state.count = @intFromFloat(std.math.clamp(@trunc(try prop.number(object, property.key, 1)), 1, 10));
        if (std.ascii.eqlIgnoreCase(property.key, "spread")) state.spread = @intFromFloat(std.math.clamp(@trunc(try prop.number(object, property.key, 2)), -32768, 32767));
        if (std.ascii.eqlIgnoreCase(property.key, "velocity")) state.velocity = std.math.clamp(@trunc(try prop.number(object, property.key, 35)), 1, 1000);
        if (std.ascii.eqlIgnoreCase(property.key, "radius")) state.radius = @trunc(try prop.number(object, property.key, 0));
        if (std.ascii.eqlIgnoreCase(property.key, "scale")) state.scale = std.math.clamp(try prop.number(object, property.key, 1), 0.01, 200);
        if (std.ascii.eqlIgnoreCase(property.key, "gravity")) state.gravity = try prop.number(object, property.key, 0);
        if (std.ascii.eqlIgnoreCase(property.key, "stoptime")) state.duration_ms = try prop.milliseconds(object, property.key, 0);
        if (std.ascii.eqlIgnoreCase(property.key, "emission")) state.frequency = @max(0.01, try prop.number(object, property.key, 0));
        if (std.ascii.eqlIgnoreCase(property.key, "emissiontime")) state.emission_time = @max(0.01, try prop.number(object, property.key, 12));
        if (std.ascii.eqlIgnoreCase(property.key, "alpha_level")) state.alpha = @max(0.01, try prop.number(object, property.key, 0.75));
        if (std.ascii.eqlIgnoreCase(property.key, "delta_alpha")) { state.fade = try prop.number(object, property.key, 0.75); if (state.fade <= 0.01) state.fade = 0.75; }
        if (std.ascii.eqlIgnoreCase(property.key, "_color")) state.color = try @import("map.zig").vector(property.value);
    }
    try world.put(entity, random);
    return state;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.particles;
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = c.ET_GENERAL;
    out.state.generic1 = policy.render_tag;
    out.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    out.state.pos.trDelta = state.color;
    out.state.apos = @import("../engine/trajectory.zig").stationary(state.direction);
    out.state.apos.trDelta = state.acceleration;
    out.state.apos.trTime = @bitCast(state.frequency);
    out.state.apos.trDuration = @bitCast(state.emission_time);
    out.state.angles2 = .{ state.velocity, state.scale, state.radius };
    out.state.origin2 = .{ state.alpha, state.fade, @floatFromInt(state.count) };
    out.state.frame = state.spread;
    out.state.weapon = @bitCast(state.flags);
    out.state.time = @intCast(state.started_ms);
    out.state.time2 = @bitCast(try world.persistentId(entity));
    out.shared.currentOrigin = pose.position;
    out.shared.mins = @splat(-8); out.shared.maxs = @splat(8);
    out.shared.ownerNum = c.ENTITYNUM_NONE;
    out.shared.contents = 0;
    out.shared.svFlags = if (state.tracked) 0 else c.SVF_NOCLIENT;
    engine.link(out);
}
pub fn use(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    (try world.get(entity, data.WorldControl)).action.particles.use(now);
    try publish(world, entity, projections);
}
fn visible(world: *data.World, slots: *const Slots, origin: v.Vec3) bool {
    var query = world.queryAccess(data.World.mask(.{data.Cinematic}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.Cinematic)) |state| if (state.active) { return true; };
    for (slots.occupants[0..c.MAX_CLIENTS]) |occupant| if (occupant) |player| {
        var point = (world.get(player, data.Transform) catch continue).position;
        if (world.get(player, data.Body) catch null) |body| if (body.motion_owner) |owner| if (world.find(owner)) |controller| {
            if (world.get(controller, data.Monitor) catch null) |monitor| if (monitor.viewer == (world.persistentId(player) catch 0)) { point = monitor.origin; };
        };
        if (v.length(v.subtract(point, origin)) < 1000 and engine.inPvs(origin, point)) return true;
    };
    return false;
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.WorldControl)).action.particles;
    if (state.next_ms == null or now < state.next_ms.?) return;
    const object = (try world.get(entity, data.MapObject)).*;
    const origin = (try world.get(entity, data.Transform)).position;
    switch (state.phase) {
        .parse => {
            if (engine.integer("gib_enable") == 0 and try prop.number(object, "violence", 0) != 0) { try @import("weapon_entities.zig").remove(world, slots, projections, entity); return; }
            if (object.target.len > 0) {
                const targets = try @import("names.zig").named(world, object.target);
                state.direction = origin;
                if (targets.count > 0) state.direction = v.normalize(v.subtract((try world.get(world.find(targets.ids[0]).?, data.Transform)).position, origin));
            }
            for (object.properties) |property| if (std.ascii.eqlIgnoreCase(property.key, "gravitydir")) {
                const targets = try @import("names.zig").named(world, property.value);
                if (targets.count > 0) {
                    const target = world.find(targets.ids[0]).?;
                    state.acceleration = v.normalize(v.subtract((try world.get(target, data.Transform)).position, origin));
                    // The authored class consumes this helper, including when several emitters name it.
                    if ((world.get(target, data.Binding) catch null) != null) try @import("weapon_entities.zig").remove(world, slots, projections, target) else try world.destroy(target);
                }
            };
            state.acceleration = v.scale(state.acceleration, state.gravity);
            if (state.flags & 1024 != 0) { state.phase = .idle; state.next_ms = null; } else {
                state.phase = .spawn;
                state.on = state.flags & 2048 != 0;
                state.next_ms = now + 500 + @as(i64, @intFromFloat((try world.get(entity, data.Random)).next() * 1000));
            }
        },
        .spawn => state.start(now),
        .check => state.check(visible(world, slots, origin), now),
        .idle => {},
    }
    (try world.get(entity, data.WorldControl)).action.particles = state;
    try publish(world, entity, projections);
}
