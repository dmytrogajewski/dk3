// SPDX-License-Identifier: GPL-2.0-or-later
//! Continuous healing requires an actual living recipient in range and facing the station.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("item_catalog").hosportal;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
pub fn owns(name: []const u8) bool {
    return std.mem.eql(u8, name, "misc_hosportal") or std.mem.eql(u8, name, "misc_fountain");
}
pub fn initialize(object: data.MapObject) !policy.State {
    const style: i32 = @intFromFloat(try prop.number(object, "style", 0));
    const capacity: i32 = @intFromFloat(try prop.number(object, "max_juice", 100));
    if (style < 0 or style > 2 or capacity < 0) return error.InvalidHealingStation;
    return .{ .kind = if (std.mem.eql(u8, object.classname, "misc_fountain")) .fountain else @enumFromInt(style), .capacity = @intCast(capacity) };
}
pub fn bind(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity) !void {
    const definition = policy.definition((try world.get(entity, data.WorldControl)).action.healer.kind);
    try world.put(entity, data.Body{ .mins = .{ -16, -16, -24 }, .maxs = .{ 16, 16, definition.top }, .contents = c.CONTENTS_SOLID, .collision_mask = c.MASK_SOLID, .mass = 1 });
    // Station health has no destruction callback in the supplied behavior.
    const health: i32 = @intFromFloat(try prop.number((try world.get(entity, data.MapObject)).*, "health", 100));
    try world.put(entity, data.Health{ .current = health, .maximum = @max(1, health) });
    try @import("weapon_entities.zig").bind(world, slots, projections, entity, definition.model);
    try publish(world, entity, projections);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const state = (try world.get(entity, data.WorldControl)).action.healer;
    const binding = (try world.get(entity, data.Binding)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    projection.state.generic1 = policy.render_tag;
    projection.state.frame = state.frame();
    projection.state.weapon = @intFromEnum(state.kind);
    projection.state.time = @intCast(state.effect_ms orelse 0);
    projection.state.time2 = @intFromBool(state.effect_ms != null);
    projection.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = @bitCast(body.contents);
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}
fn eligible(world: *data.World, station: ecs.Entity, recipient: ecs.Entity) !bool {
    const player = world.get(recipient, data.Player) catch null;
    const companion = world.get(recipient, data.Companion) catch null;
    if (player == null and companion == null) return false;
    if (player) |state| if (state.mode != .normal) return false;
    const pose = (try world.get(recipient, data.Transform)).*;
    const delta = v.subtract((try world.get(station, data.Transform)).position, pose.position);
    if (v.length(delta) > 64) return false;
    // The original use predicate compares horizontal yaw against half of 90 degrees.
    // Keep its single-wrap comparison, including the signed seam behavior.
    const yaw = @mod(std.math.atan2(delta[1], delta[0]) * (180.0 / std.math.pi), 360);
    var difference = @abs(@mod(pose.angles[1], 360) - yaw);
    if (difference > 180) difference -= 360;
    return difference <= 45;
}
fn cue(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, event: policy.Cue, now: i64) !void {
    const definition = policy.definition((try world.get(entity, data.WorldControl)).action.healer.kind);
    const name = switch (event) {
        .none => return,
        .effects => definition.particle_sound,
        .recharged => definition.recharged_sound,
        .empty => definition.empty_sound,
    };
    if (name.len == 0) return;
    try @import("events.zig").configuredSound(world, slots, projections, name, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now, .{ .volume = if (event == .effects) 0.85 else 0.5 });
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) !void {
    const recipient = world.find(activator) orelse return;
    const health = world.get(recipient, data.Health) catch return;
    const valid = try eligible(world, entity, recipient);
    const event = (try world.get(entity, data.WorldControl)).action.healer.use(activator, health.current, health.maximum, valid, now);
    try cue(world, slots, projections, entity, event, now);
    try publish(world, entity, projections);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const state = &(try world.get(entity, data.WorldControl)).action.healer;
    const deadline = state.next_ms orelse return;
    if (now < deadline) return;
    const recipient = world.find(state.recipient);
    const health = if (recipient) |other| world.get(other, data.Health) catch null else null;
    const valid = if (recipient) |other| try eligible(world, entity, other) else false;
    const event = state.tick(if (health) |value| &value.current else null, if (health) |value| value.maximum else 0, valid, now);
    try cue(world, slots, projections, entity, event, now);
    try publish(world, entity, projections);
}
