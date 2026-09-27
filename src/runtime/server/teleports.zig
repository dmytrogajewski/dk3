// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored relocation with collision-qualified occupancy and ordinary angle transport.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
pub fn move(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, trigger: ecs.Entity, entity: ecs.Entity, scripted: bool, now: i64) !void {
    const object = (try world.get(trigger, data.MapObject)).*;
    const destination = @import("scripts.zig").named(world, object.target) orelse return error.MissingTeleportDestination;
    var target = (try world.get(destination, data.Transform)).*;
    if (std.mem.eql(u8, (try world.get(destination, data.MapObject)).classname, "info_teleport_destination")) target.position[2] += 27;
    const player = world.get(entity, data.Player) catch null;
    const companion = world.get(entity, data.Companion) catch null;
    const motor: ?*data.Player = if (player != null) player else if (companion) |value| &value.motor else null;
    if (!scripted) if (motor) |state| if (now < state.teleport_until_ms) return;
    const body = (try world.get(entity, data.Body)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const service = engine.collisionService();
    // Solid map geometry never becomes a valid destination through telefrag damage.
    const wall = try service.trace(.{ .start = target.position, .end = target.position, .mins = body.mins, .maxs = body.maxs, .slot = binding.slot, .mask = c.MASK_SOLID });
    if (wall.start_solid or wall.all_solid) return;
    const occupants = slots.occupants;
    for (occupants) |maybe| if (maybe) |other| {
        if (other.index == entity.index or (world.get(other, data.Health) catch null) == null) continue;
        const other_body = world.get(other, data.Body) catch continue;
        if (other_body.contents & c.CONTENTS_BODY == 0) continue;
        const position = (try world.get(other, data.Transform)).position;
        var overlaps = true;
        for (0..3) |axis| if (target.position[axis] + body.maxs[axis] <= position[axis] + other_body.mins[axis] or target.position[axis] + body.mins[axis] >= position[axis] + other_body.maxs[axis]) {
            overlaps = false;
        };
        if (!overlaps) continue;
        _ = try @import("damage.zig").apply(world, other, 32000, now, .{ .source = try world.persistentId(entity), .bypass_armor = true, .bypass_protection = true });
        if ((try world.get(other, data.Health)).current > 0) return;
        (try world.get(other, data.Body)).contents = 0;
        const slot = (try world.get(other, data.Binding)).slot;
        projections[slot].shared.contents = 0;
        engine.link(&projections[slot]);
    };
    const origin = (try world.get(entity, data.Transform)).position;
    (try world.get(entity, data.Transform)).* = target;
    const velocity = try world.get(entity, data.Velocity);
    if (!scripted and object.flags & 4 == 0) velocity.linear = v.scale(v.basis(target.angles).forward, v.length(velocity.linear));
    if (motor) |state| {
        state.teleport_until_ms = now + 700;
        state.teleport_bit = !state.teleport_bit;
        state.ground_entity = c.ENTITYNUM_NONE;
        state.water_level = 0;
        state.water_type = 0;
        if (player != null) {
            var input: c.usercmd_t = undefined;
            engine.usercmd(binding.slot, &input);
            for (target.angles, 0..) |angle, axis| state.delta_angles[axis] = @as(i32, @intFromFloat(@mod(angle, 360) * 65536 / 360)) -% input.angles[axis];
        }
    }
    (try world.get(entity, data.Body)).grounded = false;
    if (world.get(entity, data.Actor) catch null) |actor| {
        actor.route = .{};
        actor.ground_entity = c.ENTITYNUM_NONE;
    }
    projections[binding.slot].shared.currentOrigin = target.position;
    projections[binding.slot].shared.currentAngles = target.angles;
    projections[binding.slot].state.pos = @import("../engine/trajectory.zig").stationary(target.position);
    projections[binding.slot].state.apos = @import("../engine/trajectory.zig").stationary(target.angles);
    projections[binding.slot].state.eFlags ^= c.EF_TELEPORT_BIT;
    engine.link(&projections[binding.slot]);
    if (!scripted) {
        try @import("events.zig").sound(world, slots, projections, "global/new_teleport1.wav", origin, binding.slot, c.CHAN_AUTO, now);
        try @import("events.zig").sound(world, slots, projections, "global/new_teleport1.wav", target.position, binding.slot, c.CHAN_AUTO, now);
        try router.fire(world, slots, projections, trigger, try world.persistentId(entity), now);
    }
}
