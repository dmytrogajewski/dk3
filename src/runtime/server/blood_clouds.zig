// SPDX-License-Identifier: GPL-2.0-or-later
//! Dopefish's successful bite leaves a delayed, finite cloud and physical fragments.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("../domain/blood_cloud.zig");
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, victim: ecs.Entity, attacker: ecs.Entity, now: i64) !void {
    if (engine.integer("sv_violence") != 0) return;
    const body = (try world.get(attacker, data.Body)).*;
    const attack_pose = (try world.get(attacker, data.Transform)).*;
    const pose = (try world.get(victim, data.Transform)).*;
    const mass = (try world.get(victim, data.Body)).mass;
    var extent = v.scale(v.subtract(body.maxs, body.mins), 1.15);
    // Reference cloud height uses the attacker's absolute upper Z, even below zero.
    extent[2] = (attack_pose.position[2] + body.maxs[2]) * 0.5;
    const entity = try world.create(null, .{ data.Transform{ .position = pose.position }, data.MapObject{ .classname = "effect_blood_cloud" }, data.Random{ .state = try world.persistentId(victim) ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) }, data.WorldControl{ .action = .{ .blood_cloud = .{ .next_ms = now + 200, .extent = extent, .mass = mass } } } });
    try @import("weapon_entities.zig").bind(world, slots, projections, entity, "");
    try publish(world, entity, projections);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.WorldControl)).action.blood_cloud;
    if (state.until_ms) |until| {
        if (now >= until) try @import("weapon_entities.zig").remove(world, slots, projections, entity);
        return;
    }
    if (now < state.next_ms) return;
    state.next_ms = now;
    state.until_ms = now + 500;
    (try world.get(entity, data.WorldControl)).action.blood_cloud = state;
    try @import("actor_gibs.zig").burst(world, slots, projections, entity, .{ .mass = state.mass, .mins = @splat(0), .maxs = @splat(0) }, .{}, .{}, "", @splat(0), (try world.get(entity, data.Transform)).position, now);
    try publish(world, entity, projections);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.blood_cloud;
    const slot = (try world.get(entity, data.Binding)).slot;
    const origin = (try world.get(entity, data.Transform)).position;
    const out = &projections[slot];
    out.state.number = slot;
    out.state.eType = abi.c.ET_GENERAL;
    out.state.generic1 = policy.render_tag;
    out.state.time2 = @bitCast(try world.persistentId(entity));
    out.state.time = @intCast(state.next_ms);
    out.state.origin2 = state.extent;
    out.state.pos = @import("../engine/trajectory.zig").stationary(origin);
    out.shared.currentOrigin = origin;
    out.shared.contents = 0;
    out.shared.ownerNum = abi.c.ENTITYNUM_NONE;
    out.shared.svFlags = if (state.until_ms == null) abi.c.SVF_NOCLIENT else abi.c.SVF_BROADCAST;
    engine.link(out);
}
