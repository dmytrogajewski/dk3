// SPDX-License-Identifier: GPL-2.0-or-later
//! Bounded transient transport entities; persistent IDs prevent slot-reuse aliases.
const std = @import("std");
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const c = abi.c;
pub fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, name: []const u8, position: data.Vec3, subject: u16, channel: u8, now: i64) !void {
    const index = try @import("resources.zig").sound(name);
    const entity = try world.create(null, .{ data.Transform{ .position = position }, data.SoundEvent{ .sound = index, .subject = subject, .channel = channel }, data.Lifetime{ .expires_ms = now + 300 } });
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
    projection.state.time = @intCast(now);
    projection.state.time2 = @bitCast(try world.persistentId(entity));
    projection.state.pos = @import("../engine/trajectory.zig").stationary(position);
    projection.shared.currentOrigin = position;
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn expire(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants, 0..) |occupant, slot| {
        const entity = occupant orelse continue;
        _ = world.get(entity, data.SoundEvent) catch continue;
        const deadline = (try world.get(entity, data.Lifetime)).expires_ms;
        if (deadline > now) continue;
        engine.unlink(&projections[slot]);
        try slots.release(@intCast(slot), entity);
        try world.destroy(entity);
    }
}
