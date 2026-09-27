// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored emitters own their channels, random sequence and restoration state.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const audio = @import("../domain/audio.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const prop = @import("properties.zig");
const resources = @import("resources.zig");
pub fn owns(name: []const u8) bool {
    return std.mem.eql(u8, name, "target_speaker") or std.mem.eql(u8, name, "sound_ambient");
}
pub fn initialize(object: data.MapObject, seed: u32, now: i64) !audio.Speaker {
    const ambient = std.mem.eql(u8, object.classname, "sound_ambient");
    var state: audio.Speaker = .{ .random = seed };
    for (object.properties) |property| {
        if (state.count == state.sounds.len or std.mem.indexOf(u8, property.key, "sound") == null) continue;
        // These paths also travel in a quoted reliable command.
        for (property.value) |ch| if (ch < 32 or ch == '"' or ch == ';') return error.InvalidSpeakerPath;
        state.sounds[state.count] = try resources.sound(property.value);
        state.count += 1;
    }
    state.parameters.volume = try prop.number(object, "volume", if (ambient) 0.5 else 1);
    if (state.parameters.volume == 0) state.parameters.volume = 1;
    state.parameters.volume = try audio.wireVolume(state.parameters.volume);
    state.parameters.minimum = @trunc(try prop.number(object, "min", 256));
    state.parameters.maximum = @trunc(try prop.number(object, "max", 648));
    if (state.parameters.minimum == 0) state.parameters.minimum = 256;
    if (state.parameters.maximum == 0) state.parameters.maximum = 648;
    if (state.parameters.minimum >= state.parameters.maximum) state.parameters.minimum = 0;
    if (!state.parameters.valid()) return error.InvalidSpeakerParameters;
    const delay = @trunc(try prop.number(object, "delay", 0));
    const minimum = @trunc(try prop.number(object, "mindelay", 0));
    if (delay < 0 or minimum < 0) return error.InvalidSpeakerDelay;
    state.delay_secs = @intFromFloat(delay);
    state.minimum_secs = @intFromFloat(minimum);
    state.start(if (ambient) 1 else object.flags, object.targetname.len != 0, now);
    return state;
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.speaker;
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = audio.parameter_tag;
    projection.state.loopSound = if (state.active) state.sounds[0] else 0;
    projection.state.angles2 = .{ state.parameters.volume, state.parameters.minimum, state.parameters.maximum };
    projection.state.weapon = @intFromBool(state.parameters.nondirectional);
    projection.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    projection.shared.currentOrigin = pose.position;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    projection.shared.contents = 0;
    projection.shared.svFlags = if (state.active and state.parameters.nondirectional) c.SVF_BROADCAST else if (!state.active) c.SVF_NOCLIENT else 0;
    engine.link(projection);
}
fn play(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const state = &(try world.get(entity, data.WorldControl)).action.speaker;
    if (state.count == 0) return;
    const index = state.sounds[state.draw(state.count)];
    if (index == 0) return;
    const point = (try world.get(entity, data.Transform)).position;
    const slot = (try world.get(entity, data.Binding)).slot;
    const name = resources.soundName(index);
    if (state.reliable) {
        const params = state.parameters;
        var buffer: [512]u8 = undefined;
        const command = try std.fmt.bufPrintZ(&buffer, "dk3_sound \"{s}\" {d} {d} {d} {d} {d} {d} {d} {d}", .{ name, slot, point[0], point[1], point[2], params.volume, params.minimum, params.maximum, @intFromBool(params.nondirectional) });
        _ = engine.gateway.call(c.G_SEND_SERVER_COMMAND, .{ @as(isize, -1), command.ptr });
    } else {
        try @import("events.zig").configuredSound(world, slots, projections, name, point, slot, c.CHAN_VOICE, now, state.parameters);
    }
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const state = &(try world.get(entity, data.WorldControl)).action.speaker;
    if (state.next_ms == null and state.timed) state.next_ms = now + 100;
    if (state.loopable) {
        state.active = !state.active;
        try publish(world, entity, projections);
    } else try play(world, slots, projections, entity, now);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const state = &(try world.get(entity, data.WorldControl)).action.speaker;
    const due = state.next_ms orelse return;
    if (now < due) return;
    try play(world, slots, projections, entity, now);
    const current = &(try world.get(entity, data.WorldControl)).action.speaker;
    current.next_ms = now + current.interval();
}
