// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored spotlight rays pass through actors without laser damage or contact sparks.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/spotlight.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
pub fn initialize(object: data.MapObject, pose: data.Transform, now: i64) !policy.State {
    var state: policy.State = .{ .enabled = object.flags & 1 != 0, .next_ms = now + 100, .direction = if (pose.angles[1] == -1) .{ 0, 0, 1 } else if (pose.angles[1] == -2) .{ 0, 0, -1 } else v.basis(pose.angles).forward, .endpoint = pose.position };
    state.radius = @trunc(try prop.number(object, "radius", 4));
    if (state.radius == 0) state.radius = 4;
    state.length = @trunc(try prop.number(object, "length", 2048));
    if (state.radius < 0 or state.length < 0) return error.InvalidSpotlight;
    if (prop.text(object, "_color")) |color| {
        var words = std.mem.tokenizeAny(u8, color, " \t");
        for (&state.color) |*channel| {
            channel.* = std.fmt.parseFloat(f32, words.next() orelse return error.InvalidSpotlight) catch return error.InvalidSpotlight;
            if (!std.math.isFinite(channel.*) or channel.* < 0 or channel.* > 1) return error.InvalidSpotlight;
        }
    }
    return state;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.spotlight;
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = c.ET_GENERAL;
    out.state.generic1 = policy.render_tag;
    out.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    out.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    out.state.origin2 = state.endpoint;
    out.state.angles2 = state.color;
    out.state.frame = @intFromFloat(state.radius);
    out.shared.currentOrigin = pose.position;
    out.shared.mins = @splat(-8);
    out.shared.maxs = @splat(8);
    out.shared.contents = 0;
    out.shared.ownerNum = c.ENTITYNUM_NONE;
    out.shared.svFlags = if (state.enabled and state.initialized) c.SVF_BROADCAST else c.SVF_NOCLIENT;
    engine.link(out);
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const state = &(try world.get(entity, data.WorldControl)).action.spotlight;
    if (!state.initialized) return;
    state.enabled = !state.enabled;
    state.next_ms = now;
    try step(world, slots, projections, entity, now);
    try publish(world, entity, projections);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.WorldControl)).action.spotlight;
    if (now < state.next_ms or (state.initialized and !state.enabled)) return;
    const origin = (try world.get(entity, data.Transform)).position;
    if (!state.initialized) {
        const target = (try world.get(entity, data.MapObject)).target;
        if (target.len > 0) {
            const found = try @import("names.zig").named(world, target);
            if (found.count > 0) state.target = found.ids[0];
        }
        state.initialized = true;
    }
    if (state.enabled) {
        var hidden: [ecs.max_entities]u16 = undefined;
        var count: usize = 0;
        defer for (hidden[0..count]) |slot| if (slots.occupants[slot] != null) { engine.link(&projections[slot]); };
        if (world.find(state.target)) |target| {
            var point = (try world.get(target, data.Transform)).position;
            if (world.get(target, data.Binding) catch null) |binding| {
                const body = projections[binding.slot].shared;
                point = v.scale(v.add(body.absmin, body.absmax), 0.5);
                engine.unlink(&projections[binding.slot]);
                hidden[count] = binding.slot;
                count += 1;
            }
            state.direction = v.normalize(v.subtract(point, origin));
        }
        const end = v.add(origin, v.scale(state.direction, state.length));
        var start = origin;
        while (count < hidden.len) {
            const hit = try engine.collisionService().trace(.{ .start = start, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.CONTENTS_SOLID | c.CONTENTS_BODY | c.CONTENTS_CORPSE });
            state.endpoint = hit.end;
            if (hit.fraction == 1 and !hit.start_solid) break;
            if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |other| {
                if ((world.get(other, data.Actor) catch null) != null or (world.get(other, data.Player) catch null) != null) {
                    engine.unlink(&projections[hit.entity]);
                    hidden[count] = hit.entity;
                    count += 1;
                    start = hit.end;
                    continue;
                }
            };
            break;
        }
        state.next_ms = now + 100;
    }
    (try world.get(entity, data.WorldControl)).action.spotlight = state;
    try publish(world, entity, projections);
}
