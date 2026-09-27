// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const policy = @import("../domain/earthquake.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const prop = @import("properties.zig");
pub fn initialize(world: *data.World, entity: ecs.Entity) !policy.State {
    const object = (try world.get(entity, data.MapObject)).*;
    var state: policy.State = .{};
    for (object.properties) |property| {
        if (std.ascii.eqlIgnoreCase(property.key, "severity") or std.ascii.eqlIgnoreCase(property.key, "speed")) state.severity = @trunc(try prop.number(object, property.key, 200));
        if (std.ascii.eqlIgnoreCase(property.key, "duration") or std.ascii.eqlIgnoreCase(property.key, "count")) state.duration_ms = try prop.milliseconds(object, property.key, 5);
        if (std.ascii.eqlIgnoreCase(property.key, "radius")) state.radius = try prop.number(object, property.key, 200);
        if (std.ascii.eqlIgnoreCase(property.key, "damage")) state.damage = try prop.number(object, property.key, 0);
        if (std.ascii.eqlIgnoreCase(property.key, "mins")) state.parameters.minimum = try prop.number(object, property.key, 2000);
        if (std.ascii.eqlIgnoreCase(property.key, "maxs")) state.parameters.maximum = try prop.number(object, property.key, 2024);
    }
    if (state.severity == 0) state.severity = 200;
    if (state.radius == 0) state.radius = 200;
    if (state.duration_ms == 0) state.duration_ms = 5000;
    if (state.severity < 0 or state.radius < 0 or state.damage < 0 or state.duration_ms < 0 or !state.parameters.valid() or state.damage * state.severity > 200000000) return error.InvalidEarthquake;
    try world.put(entity, data.Random{ .state = try world.persistentId(entity) });
    return state;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.earthquake;
    const binding = (try world.get(entity, data.Binding)).*;
    const point = (try world.get(entity, data.Transform)).position;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = @import("../domain/audio.zig").parameter_tag;
    projection.state.loopSound = if (state.next_ms != null) state.sound else 0;
    projection.state.angles2 = .{ state.parameters.volume, state.parameters.minimum, state.parameters.maximum };
    projection.state.pos = @import("../engine/trajectory.zig").stationary(point);
    projection.shared.currentOrigin = point;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    projection.shared.contents = 0;
    projection.shared.svFlags = if (state.next_ms != null) 0 else c.SVF_NOCLIENT;
    engine.link(projection);
}
pub fn use(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const state = &(try world.get(entity, data.WorldControl)).action.earthquake;
    state.until_ms = now + state.duration_ms;
    state.next_ms = now + 100;
    var path: [40]u8 = undefined;
    state.sound = try @import("resources.zig").sound(try std.fmt.bufPrint(&path, "global/earthquake_{c}.wav", .{@as(u8, 'a') + @as(u8, @intFromFloat((try world.get(entity, data.Random)).next() * 4))}));
    try publish(world, entity, projections);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const state = (try world.get(entity, data.WorldControl)).action.earthquake;
    if (state.next_ms == null or now < state.next_ms.?) return;
    const source = try world.persistentId(entity);
    const origin = (try world.get(entity, data.Transform)).position;
    var random = (try world.get(entity, data.Random)).*;
    const occupants = slots.occupants;
    for (occupants[0..c.MAX_CLIENTS], 0..) |occupant, slot| {
        const player = occupant orelse continue;
        const motor = world.get(player, data.Player) catch continue;
        if (motor.mode == .noclip or motor.mode == .spectator or (try world.get(player, data.Body)).contents == 0) continue;
        const distance = v.length(v.subtract((try world.get(player, data.Transform)).position, origin));
        if (distance > state.radius) continue;
        const amount = state.damagePerPulse();
        if (amount > 0) _ = try @import("damage.zig").apply(world, player, amount, now, .{ .source = source });
        var kick: v.Vec3 = undefined;
        for (&kick) |*axis| axis.* = @trunc(-(random.next() * 2 - 1) * state.strength(distance) * 8) / 8;
        var command: [192]u8 = undefined;
        engine.send(@intCast(slot), try std.fmt.bufPrintZ(&command, "dk3_quake_kick {d} {d} {d} {d}", .{ now, kick[0], kick[1], kick[2] }));
    }
    if (now >= state.until_ms) {
        try @import("weapon_entities.zig").remove(world, slots, projections, entity);
    } else {
        (try world.get(entity, data.Random)).* = random;
        (try world.get(entity, data.WorldControl)).action.earthquake.next_ms = now + 100;
    }
}
