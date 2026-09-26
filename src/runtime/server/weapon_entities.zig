// SPDX-License-Identifier: GPL-2.0-or-later
//! Slot lifetime for engine-visible weapon entities.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const Slots = @import("../engine/slots.zig").Slots;
const abi = @import("../engine/abi.zig");
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
