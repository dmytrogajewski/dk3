// SPDX-License-Identifier: GPL-2.0-or-later
//! Slot lifetime for engine-visible weapon entities.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const Slots = @import("../engine/slots.zig").Slots;
const abi = @import("../engine/abi.zig");
pub const Effect = struct { weapon: u5, owner: u32, endpoint: data.Vec3 = @splat(0), phase: i32 = 0, strength: f32 = 1, born_ms: i64 = 0, end_ms: i64 = 0 };
pub fn effect(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, value: Effect) !void {
    const c = abi.c;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_DK3_EFFECT;
    projection.state.weapon = value.weapon;
    projection.state.otherEntityNum = if (world.find(value.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    projection.state.generic1 = @bitCast(try world.persistentId(entity));
    projection.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.state.origin2 = value.endpoint;
    projection.state.angles2[0] = value.strength;
    projection.state.frame = value.phase;
    projection.state.time = @intCast(value.born_ms);
    projection.state.time2 = @intCast(value.end_ms);
    projection.shared.currentOrigin = pose.position;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    projection.shared.contents = 0;
    @import("../engine/server.zig").link(projection);
}
pub fn bind(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, model: []const u8) !void {
    const index = try @import("resources.zig").model(model);
    const slot = try slots.acquire(entity, null);
    errdefer slots.release(slot, entity) catch unreachable;
    try world.put(entity, data.Binding{ .slot = slot, .model = index });
    projections[slot] = @import("std").mem.zeroes(abi.EntityProjection);
}
pub fn remove(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity) !void {
    const slot = (try world.get(entity, data.Binding)).slot;
    @import("../engine/server.zig").unlink(&projections[slot]);
    try slots.release(slot, entity);
    try world.destroy(entity);
}

/// Retire the actual spatial owner, never a same-numbered slot in the caller.
pub fn removeReference(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, target: @import("../domain/world_references.zig").Ref) !void {
    if (target.world == world) return remove(world, slots, projections, target.entity);
    const context = @import("region_access.zig").contextFor(target.world) orelse return error.WeaponWorldUnavailable;
    const scope = try context.select();
    defer scope.deinit();
    return remove(target.world, &context.slots, &context.projection, target.entity);
}
