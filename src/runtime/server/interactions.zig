// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Router = @import("targets.zig").Router;
const prop = @import("properties.zig");
const c = abi.c;
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, player_entity: ecs.Entity, now: i64) !void {
    const player = (try world.get(player_entity, data.Player)).*;
    if (player.mode != .normal or (try world.get(player_entity, data.Health)).current <= 0) return;
    const transform = (try world.get(player_entity, data.Transform)).*;
    const v = @import("../domain/vector.zig");
    var start = transform.position;
    start[2] += player.view_height;
    const trace = try @import("region_collision.zig").trace(.{ .start = start, .end = v.add(start, v.scale(v.basis(transform.angles).forward, 96)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(player_entity, data.Binding)).slot, .mask = c.MASK_SHOT });
    const target = @import("region_access.zig").victim(world, slots, trace) orelse return;
    const object = (target.get(data.MapObject) catch return).*;
    if (std.mem.startsWith(u8, object.classname, "trigger_")) return;
    if (object.targetname.len != 0 and !std.mem.eql(u8, object.classname, "func_button") and !@import("healers.zig").owns(object.classname)) return;
    try router.activateReference(world, slots, projections, target, null, try world.persistentId(player_entity), now);
}
pub fn overlap(a: *const abi.EntityProjection, b: *const abi.EntityProjection, padding: f32) bool {
    for (0..3) |axis| if (a.shared.absmax[axis] + padding < b.shared.absmin[axis] or a.shared.absmin[axis] - padding > b.shared.absmax[axis]) return false;
    return true;
}
pub fn touch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, now: i64) !void {
    // Copy handles because target routing may destroy entities and release slots.
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        const object = (world.get(entity, data.MapObject) catch continue).*;
        const binding = (world.get(entity, data.Binding) catch continue).*;
        const projection = &projections[binding.slot];
        if (world.get(entity, data.Exit) catch null) |exit| {
            var touching: ?ecs.Entity = null;
            for (occupants[0..c.MAX_CLIENTS]) |client| {
                const actor = client orelse continue;
                const player = world.get(actor, data.Player) catch continue;
                if (player.mode != .normal or (try world.get(actor, data.Health)).current <= 0) continue;
                if (overlap(&projections[(try world.get(actor, data.Binding)).slot], projection, 0)) {
                    touching = actor;
                    break;
                }
            }
            if (touching) |player| {
                if (!exit.latched) {
                    exit.latched = true;
                    try router.activate(world, slots, projections, entity, try world.persistentId(player), now);
                }
            } else exit.latched = false;
            continue;
        }
        if (world.get(entity, data.WorldControl) catch null) |control| {
            const debris = control.action == .debris and control.action.debris.active;
            if (!debris and projection.shared.contents & c.CONTENTS_TRIGGER == 0) continue;
            for (occupants) |candidate| {
                const other = candidate orelse continue;
                if (!world.alive(entity) or !world.alive(other)) break;
                if (!try @import("world_controls.zig").touches(world, entity, other)) continue;
                if ((world.get(other, data.Health) catch continue).current <= 0) continue;
                if ((world.get(other, data.Player) catch null)) |player| if (player.mode != .normal) continue;
                const body = &projections[(try world.get(other, data.Binding)).slot];
                if (overlap(body, projection, if (debris) 1 else 0)) try @import("world_controls.zig").touch(world, slots, projections, router, entity, other, now);
            }
            continue;
        }
        const trigger = world.get(entity, data.Trigger) catch null;
        const mover = world.get(entity, data.Mover) catch null;
        const sequence = if (world.get(entity, data.TargetSequence)) |state| state.* else |_| null;
        const button_touch = std.mem.eql(u8, object.classname, "func_button") and object.flags & 1 != 0;
        if (sequence) |state| {
            if (!state.touch or state.active) continue;
        } else if (trigger != null) {
            const companion_trigger = @import("companion_triggers.zig").owns(object.classname);
            if (companion_trigger and trigger.?.uses > 0) continue;
            if (trigger.?.counter or (!companion_trigger and object.flags & (if (std.mem.eql(u8, object.classname, "trigger_script")) @as(u32, 2) else 1) != 0) or projection.shared.contents & c.CONTENTS_TRIGGER == 0) continue;
        } else if (mover) |motion| {
            if (!button_touch and (motion.group != try world.persistentId(entity) or object.targetname.len != 0 or (!motion.platform and object.flags & 16 == 0))) continue;
            if (try prop.number(object, "health", 0) > 0) continue;
        } else continue;
        for (occupants) |client| {
            const actor = client orelse continue;
            if (!world.alive(entity) or !world.alive(actor)) break;
            const player = if (world.get(actor, data.Player)) |value| value.* else |_| null;
            if (player) |state| {
                if (state.mode != .normal) continue;
            } else if (sequence == null or !sequence.?.actor_allowed or (world.get(actor, data.Actor) catch null) == null) continue;
            if ((try world.get(actor, data.Health)).current <= 0) continue;
            const body = &projections[(try world.get(actor, data.Binding)).slot];
            const padding: f32 = if (trigger != null or sequence != null or button_touch) 1 else 48;
            if (!overlap(body, projection, padding)) continue;
            if (mover) |motion| if (motion.platform and (player == null or player.?.ground_entity != binding.slot)) continue;
            try router.activate(world, slots, projections, entity, try world.persistentId(actor), now);
            // Structural target actions invalidate component addresses. Revisit next frame.
            break;
        }
    }
}
