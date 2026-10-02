// SPDX-License-Identifier: GPL-2.0-or-later
//! Bounded transient transport entities; persistent IDs prevent slot-reuse aliases.
const std = @import("std");
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const c = abi.c;
const ecs = @import("../ecs/world.zig");
pub fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, name: []const u8, position: data.Vec3, subject: u16, channel: u8, now: i64) !void {
    try configuredSound(world, slots, projections, name, position, subject, channel, now, null);
}
pub fn soundOwned(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: u32, name: []const u8, position: data.Vec3, subject: u16, channel: u8, now: i64) !void {
    if (owner == 0) return sound(world, slots, projections, name, position, subject, channel, now);
    const context = @import("region_access.zig").byHandle(@enumFromInt(owner)) orelse return error.SoundWorldUnavailable;
    const scope = try context.select();
    defer scope.deinit();
    try sound(&context.world.?, &context.slots, &context.projection, name, position, subject, channel, now);
}
pub fn configuredSound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, name: []const u8, position: data.Vec3, subject: u16, channel: u8, now: i64, parameters: ?@import("../domain/audio.zig").Parameters) !void {
    if (parameters) |value| if (!value.valid()) return error.InvalidSoundParameters;
    const index = try @import("resources.zig").sound(name);
    const entity = try world.create(null, .{ data.Transform{ .position = position }, data.SoundEvent{ .sound = index, .subject = subject, .channel = channel, .parameters = parameters }, data.Lifetime{ .expires_ms = now + 300 } });
    errdefer world.destroy(entity) catch unreachable;
    const slot = try slots.acquire(entity, null);
    errdefer slots.release(slot, entity) catch unreachable;
    try world.put(entity, data.Binding{ .slot = slot });
    const projection = &projections[slot];
    projection.* = std.mem.zeroes(abi.EntityProjection);
    projection.state.number = slot;
    projection.state.eType = c.ET_EVENTS + c.EV_GENERAL_SOUND;
    projection.state.eventParm = index;
    projection.state.otherEntityNum = subject;
    projection.state.generic1 = channel;
    // A positioned sound has to reach the client even when its emitter is not in the
    // player's potentially-visible set: a sliding panel settles inside its own wall
    // pocket, and server-side visibility would drop the event outright instead of
    // letting it be heard from the next room. Sound events therefore travel to every
    // client and the mixer weighs them by distance, as in the engine's own sound path.
    projection.shared.svFlags = c.SVF_BROADCAST;
    if (parameters) |value| {
        projection.state.frame = @import("../domain/audio.zig").parameter_tag;
        projection.state.angles2 = .{ value.volume, value.minimum, value.maximum };
        projection.state.weapon = @intFromBool(value.nondirectional);
    }
    projection.state.time = @intCast(now);
    projection.state.time2 = @bitCast(try world.persistentId(entity));
    projection.state.pos = @import("../engine/trajectory.zig").stationary(position);
    projection.shared.currentOrigin = position;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}
/// A looping mover sound cannot ride the brush it belongs to: a compiled inline brush is
/// placed by its own world coordinates, so the brush entity's origin sits at the map origin
/// rather than at the panel, and a loop offered from there would be heard from the wrong
/// side of the level. The loop therefore travels on a carrier of its own, offset to the
/// audible middle of the brush and following the brush's trajectory. Authored loudness
/// applies when present, and the ordinary attenuation distances otherwise, which are the
/// same distances the reference server uses for mover audio without authored keys.
pub fn startLoop(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, name: []const u8, path: abi.c.trajectory_t, point: data.Vec3, subject: u16, parameters: ?@import("../domain/audio.zig").Parameters, now: i64) !u32 {
    const index = try @import("resources.zig").sound(name);
    const entity = try world.create(null, .{ data.Transform{ .position = point }, data.SoundEvent{ .sound = index, .subject = subject, .channel = c.CHAN_AUTO, .parameters = parameters }, data.Lifetime{ .expires_ms = now + 300 } });
    errdefer world.destroy(entity) catch unreachable;
    const slot = try slots.acquire(entity, null);
    errdefer slots.release(slot, entity) catch unreachable;
    try world.put(entity, data.Binding{ .slot = slot });
    try linkLoop(world, entity, index, path, point, parameters, projections);
    return try world.persistentId(entity);
}
/// Re-offers a carrier for one more frame, moving it with the brush. The transient expiry
/// withdraws a carrier whose mover stopped or vanished without retiring it.
pub fn stepLoop(world: *data.World, projections: []abi.EntityProjection, carrier: u32, index: u16, path: abi.c.trajectory_t, point: data.Vec3, parameters: ?@import("../domain/audio.zig").Parameters, now: i64) !void {
    const entity = world.find(carrier) orelse return;
    if (!world.alive(entity)) return;
    (try world.get(entity, data.Lifetime)).expires_ms = now + 300;
    (try world.get(entity, data.Transform)).position = point;
    // A reversal can change which motion sound is authored, so the carrier follows suit.
    (try world.get(entity, data.SoundEvent)).sound = index;
    try linkLoop(world, entity, index, path, point, parameters, projections);
}
pub fn stopLoop(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, carrier: u32) !void {
    const entity = world.find(carrier) orelse return;
    if (!world.alive(entity)) return;
    const slot = (try world.get(entity, data.Binding)).slot;
    engine.unlink(&projections[slot]);
    try slots.release(slot, entity);
    try world.destroy(entity);
}
fn linkLoop(world: *data.World, entity: ecs.Entity, index: u16, path: abi.c.trajectory_t, point: data.Vec3, parameters: ?@import("../domain/audio.zig").Parameters, projections: []abi.EntityProjection) !void {
    const audio = @import("../domain/audio.zig");
    const value: @import("../domain/audio.zig").Parameters = parameters orelse .{};
    const slot = (try world.get(entity, data.Binding)).slot;
    const projection = &projections[slot];
    projection.* = std.mem.zeroes(abi.EntityProjection);
    projection.state.number = slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = audio.parameter_tag;
    projection.state.loopSound = index;
    projection.state.angles2 = .{ value.volume, value.minimum, value.maximum };
    projection.state.weapon = @intFromBool(value.nondirectional);
    projection.state.pos = path;
    projection.shared.currentOrigin = point;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    projection.shared.svFlags = c.SVF_BROADCAST;
    engine.link(projection);
}
pub fn expire(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants, 0..) |occupant, slot| {
        const entity = occupant orelse continue;
        if ((world.get(entity, data.SoundEvent) catch null) == null and (world.get(entity, data.ImpactEvent) catch null) == null) continue;
        const deadline = (try world.get(entity, data.Lifetime)).expires_ms;
        if (deadline > now) continue;
        engine.unlink(&projections[slot]);
        try slots.release(@intCast(slot), entity);
        try world.destroy(entity);
    }
}
pub fn impact(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, value: data.ImpactEvent, position: data.Vec3, now: i64) !void {
    const entity = try world.create(null, .{ data.Transform{ .position = position }, value, data.Lifetime{ .expires_ms = now + 300 } });
    errdefer world.destroy(entity) catch unreachable;
    const slot = try slots.acquire(entity, null);
    errdefer slots.release(slot, entity) catch unreachable;
    try world.put(entity, data.Binding{ .slot = slot });
    const projection = &projections[slot];
    projection.* = std.mem.zeroes(abi.EntityProjection);
    projection.state.number = slot;
    projection.state.eType = c.ET_EVENTS + c.EV_DK3_IMPACT;
    projection.state.weapon = value.weapon;
    projection.state.eventParm = @intFromEnum(value.kind);
    projection.state.frame = @as(i32, @intFromBool(value.charged)) | (@as(i32, @intFromBool(value.detonation)) << 1) | (@as(i32, @intFromBool(value.trail)) << 2) | (@as(i32, @intFromBool(value.no_blood)) << 3);
    projection.state.generic1 = value.sequence;
    projection.state.origin2 = value.normal;
    projection.state.time = @intCast(now);
    projection.state.time2 = @bitCast(try world.persistentId(entity));
    projection.state.pos = @import("../engine/trajectory.zig").stationary(position);
    projection.shared.currentOrigin = position;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn impactOwned(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: u32, value: data.ImpactEvent, position: data.Vec3, now: i64) !void {
    if (owner == 0) return impact(world, slots, projections, value, position, now);
    const context = @import("region_access.zig").byHandle(@enumFromInt(owner)) orelse return error.ImpactWorldUnavailable;
    const scope = try context.select();
    defer scope.deinit();
    try impact(&context.world.?, &context.slots, &context.projection, value, position, now);
}
