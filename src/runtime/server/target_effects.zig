// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/target_effect.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
pub fn initialize(world: *data.World, entity: ecs.Entity, now: i64) !policy.State {
    const object = (try world.get(entity, data.MapObject)).*;
    var state: policy.State = .{ .flags = object.flags };
    state.interval_ms = try prop.milliseconds(object, "frametime", 0.1);
    if (state.interval_ms == 0) state.interval_ms = 100;
    state.duration_ms = try prop.milliseconds(object, "length", 0);
    if (state.duration_ms == 0) state.duration_ms = if (state.flags & 2 != 0) 3000 else state.interval_ms;
    if (state.interval_ms < 0 or state.duration_ms < 0) return error.InvalidTargetEffectTime;
    const count = @trunc(try prop.number(object, "count", -1));
    state.count = if (count <= 0 or count > 64) 10 else @intFromFloat(count);
    const kind = @trunc(try prop.number(object, "type", -1));
    state.kind = if (kind < 0 or kind >= 33) 9 else @intFromFloat(kind);
    var speed = try prop.number(object, "speed", 5);
    if (speed == 0) speed = 5;
    state.speed = @intFromFloat(@mod(@trunc(speed), 256));
    const gravity = @trunc(try prop.number(object, "gravity", 1));
    state.gravity = if (gravity == 0) -250 else if (gravity == 2) 0 else 125;
    if (prop.text(object, "dir")) |value| state.direction = try @import("map.zig").vector(value);
    if (prop.text(object, "_color")) |value| {
        state.color = try @import("map.zig").vector(value);
        if (@import("../domain/vector.zig").length(state.color) == 0) state.color = @splat(0.5);
    }
    state.sound = try @import("resources.zig").sound(prop.text(object, "sound") orelse "");
    if (state.flags & 1 != 0) state.next_ms = now + state.interval_ms;
    try world.put(entity, data.Random{ .state = try world.persistentId(entity) });
    return state;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.target_effect;
    const binding = (try world.get(entity, data.Binding)).*;
    const origin = (try world.get(entity, data.Transform)).position;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = abi.c.ET_GENERAL;
    out.state.generic1 = policy.render_tag;
    out.state.time2 = @bitCast(try world.persistentId(entity));
    out.state.time = @intCast(state.pulse_ms orelse 0);
    out.state.frame = @bitCast(state.serial);
    out.state.pos = @import("../engine/trajectory.zig").stationary(origin);
    out.state.pos.trDelta = if (state.flags & 2 != 0) state.direction else @import("../domain/direction_bytes.zig").quantize(state.direction);
    out.state.apos.trDelta = state.color;
    out.state.origin2 = .{ @floatFromInt(state.count), @floatFromInt(state.kind), @floatFromInt(state.flags) };
    out.state.angles2 = .{ @floatFromInt(state.speed), @as(f32, @floatFromInt(state.duration_ms)) * 0.001, state.gravity };
    out.shared.contents = 0;
    out.shared.currentOrigin = origin;
    out.shared.ownerNum = abi.c.ENTITYNUM_NONE;
    out.shared.mins = @splat(-1);
    out.shared.maxs = @splat(1);
    out.shared.svFlags = if (state.visible) 0 else abi.c.SVF_NOCLIENT;
    engine.link(out);
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    if (!(try world.get(entity, data.WorldControl)).action.target_effect.use(now)) return;
    try pulse(world, slots, projections, entity, now);
}
fn pulse(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const random = (try world.get(entity, data.Random)).next();
    (try world.get(entity, data.WorldControl)).action.target_effect.pulse(now, random);
    const state = (try world.get(entity, data.WorldControl)).action.target_effect;
    if (state.flags & 2 == 0 and @import("multiplayer.zig").enabled() and engine.integer("p_sendparticles") == 0) (try world.get(entity, data.WorldControl)).action.target_effect.visible = false;
    try publish(world, entity, projections);
    if (state.sound != 0) try @import("events.zig").configuredSound(world, slots, projections, @import("resources.zig").soundName(state.sound), (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, abi.c.CHAN_AUTO, now, .{ .volume = 0.75 });
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const state = &(try world.get(entity, data.WorldControl)).action.target_effect;
    if (state.next_ms != null and now >= state.next_ms.?) {
        try pulse(world, slots, projections, entity, now);
        return;
    }
    if (state.visible and state.pulse_ms != null and now - state.pulse_ms.? > 300) {
        state.visible = false;
        try publish(world, entity, projections);
    }
}
