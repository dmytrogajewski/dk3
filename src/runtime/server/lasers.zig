// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/laser.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
pub fn initialize(object: data.MapObject, pose: data.Transform, now: i64) !policy.State {
    var damage: i32 = 1;
    // Both accepted damage names obey authored order.
    for (object.properties) |property| if (std.ascii.eqlIgnoreCase(property.key, "damage") or std.ascii.eqlIgnoreCase(property.key, "dmg")) {
        damage = @intFromFloat(try prop.number(object, property.key, 1));
    };
    if (damage < 0) return error.InvalidLaserDamage;
    const angles = pose.angles;
    return .{ .enabled = object.flags & 1 != 0, .next_ms = now + 100, .direction = if (angles[1] == -1) .{ 0, 0, 1 } else if (angles[1] == -2) .{ 0, 0, -1 } else v.basis(angles).forward, .endpoint = pose.position, .damage = if (damage == 0) 1 else damage, .sound = try @import("resources.zig").sound(prop.text(object, "sound") orelse "") };
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.laser;
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = c.ET_GENERAL;
    out.state.generic1 = policy.render_tag;
    out.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    out.state.origin2 = state.endpoint;
    out.state.angles2 = state.normal;
    out.state.frame = state.spark_count;
    out.state.time = @intCast(state.spark_ms orelse 0);
    out.state.time2 = @bitCast(try world.persistentId(entity));
    out.state.loopSound = if (state.enabled and state.initialized) state.sound else 0;
    out.shared.currentOrigin = pose.position;
    out.shared.mins = @splat(-8);
    out.shared.maxs = @splat(8);
    out.shared.contents = 0;
    out.shared.ownerNum = c.ENTITYNUM_NONE;
    out.shared.svFlags = if (state.enabled and state.initialized) c.SVF_BROADCAST else c.SVF_NOCLIENT;
    engine.link(out);
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    (try world.get(entity, data.WorldControl)).action.laser.toggle(now);
    try step(world, slots, projections, entity, now);
    try publish(world, entity, projections);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.WorldControl)).action.laser;
    if (now < state.next_ms or (state.initialized and !state.enabled)) return;
    const object = (try world.get(entity, data.MapObject)).*;
    const origin = (try world.get(entity, data.Transform)).position;
    if (!state.initialized) {
        if (object.target.len > 0) {
            const found = try @import("names.zig").named(world, object.target);
            if (found.count > 0) state.target = found.ids[0];
        }
        state.initialized = true;
    }
    if (state.enabled) {
        const spark_count: u8 = if (state.changed) 8 else 4;
        if (world.find(state.target)) |target| {
            var point = (try world.get(target, data.Transform)).position;
            if (world.get(target, data.Binding) catch null) |binding| {
                const body = projections[binding.slot].shared;
                point = v.scale(v.add(body.absmin, body.absmax), 0.5);
            }
            const direction = v.normalize(v.subtract(point, origin));
            if (v.length(v.subtract(direction, state.direction)) > 0) state.changed = true;
            state.direction = direction;
        }
        const end = v.add(origin, v.scale(state.direction, 2048));
        const slot = (try world.get(entity, data.Binding)).slot;
        var hidden: [ecs.max_entities]u16 = undefined;
        var count: usize = 0;
        // Ignore all penetrated bodies during this ray; restoration is unconditional
        // even if damage or tracing fails. Map solids and other objects stop the ray.
        defer for (hidden[0..count]) |hidden_slot| if (slots.occupants[hidden_slot] != null) { engine.link(&projections[hidden_slot]); };
        var start = origin;
        while (count < hidden.len) {
            const hit = try engine.collisionService().trace(.{ .start = start, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
            state.endpoint = hit.end;
            if (hit.fraction == 1 and !hit.start_solid) break;
            const victim = if (hit.entity < slots.occupants.len) slots.occupants[hit.entity] else null;
            if (victim) |other| {
                _ = try @import("damage.zig").apply(world, other, state.damage, now, .{ .source = try world.persistentId(entity) });
                if ((world.get(other, data.Actor) catch null) != null or (world.get(other, data.Player) catch null) != null) {
                    engine.unlink(&projections[hit.entity]);
                    hidden[count] = hit.entity;
                    count += 1;
                    start = hit.end;
                    continue;
                }
            }
            if (state.changed) {
                state.changed = false;
                state.spark_ms = now;
                state.normal = hit.normal;
                state.spark_count = spark_count;
            }
            break;
        }
        state.next_ms = now + 100;
    }
    (try world.get(entity, data.WorldControl)).action.laser = state;
    try publish(world, entity, projections);
}
