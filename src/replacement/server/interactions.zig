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
    const trace = try engine.collisionService().trace(.{ .start = start, .end = v.add(start, v.scale(v.basis(transform.angles).forward, 96)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(player_entity, data.Binding)).slot, .mask = c.MASK_SHOT });
    if (trace.entity >= slots.occupants.len) return;
    const target = slots.occupants[trace.entity] orelse return;
    const object = (world.get(target, data.MapObject) catch return).*;
    if (std.mem.startsWith(u8, object.classname, "trigger_")) return;
    if (object.targetname.len != 0 and !std.mem.eql(u8, object.classname, "func_button")) return;
    try router.activate(world, slots, projections, target, try world.persistentId(player_entity), now);
}
fn overlap(a: *const abi.EntityProjection, b: *const abi.EntityProjection, padding: f32) bool {
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
        const trigger = world.get(entity, data.Trigger) catch null;
        const mover = world.get(entity, data.Mover) catch null;
        const button_touch = std.mem.eql(u8, object.classname, "func_button") and object.flags & 1 != 0;
        if (trigger != null) {
            if (trigger.?.counter or object.flags & 1 != 0 or projection.shared.contents & c.CONTENTS_TRIGGER == 0) continue;
        } else if (mover) |motion| {
            if (!button_touch and (motion.group != try world.persistentId(entity) or object.targetname.len != 0 or (!motion.platform and object.flags & 16 == 0))) continue;
            if (prop.nonempty(object, "keyname") or try prop.number(object, "health", 0) > 0) continue;
        } else continue;
        for (occupants[0..Slots.clients]) |client| {
            const actor = client orelse continue;
            if (!world.alive(entity) or !world.alive(actor)) break;
            const player = (world.get(actor, data.Player) catch continue).*;
            if (player.mode != .normal or (try world.get(actor, data.Health)).current <= 0) continue;
            const body = &projections[(try world.get(actor, data.Binding)).slot];
            const padding: f32 = if (trigger != null or button_touch) 1 else 48;
            if (!overlap(body, projection, padding)) continue;
            if (mover) |motion| if (motion.platform and player.ground_entity != binding.slot) continue;
            try router.activate(world, slots, projections, entity, try world.persistentId(actor), now);
            // Structural target actions invalidate component addresses. Revisit next frame.
            break;
        }
    }
}
