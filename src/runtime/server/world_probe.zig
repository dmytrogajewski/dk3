// SPDX-License-Identifier: GPL-2.0-or-later
//! Development diagnostics for world state; only admitted in explicit probe mode.
const std = @import("std");
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
pub fn diagnostics(world: *data.World, slots: *Slots, projections: []const abi.EntityProjection) !void {
    var text: [400]u8 = undefined;
    for (slots.occupants, 0..) |occupant, slot| {
        const entity = occupant orelse continue;
        const object = world.get(entity, data.MapObject) catch continue;
        const id = try world.persistentId(entity);
        const center = @import("../domain/vector.zig").scale(@import("../domain/vector.zig").add(projections[slot].shared.absmin, projections[slot].shared.absmax), 0.5);
        if (world.get(entity, data.Hazard)) |hazard| engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig hazard: id={d} name={s} enabled={d} center={d:.3},{d:.3},{d:.3}\n", .{ id, object.targetname, @intFromBool(hazard.enabled), center[0], center[1], center[2] })) else |_| {}
        if (world.get(entity, data.Destructible)) |state| engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig destructible: id={d} health={d} broken={d} hidden={d} center={d:.3},{d:.3},{d:.3}\n", .{ id, (try world.get(entity, data.Health)).current, @intFromBool(state.broken), @intFromBool(state.hidden), center[0], center[1], center[2] })) else |_| {}
        if (world.get(entity, data.TargetSequence)) |state| engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig sequence: id={d} name={s} active={d} cursor={d}/{d} start={d}\n", .{ id, object.targetname, @intFromBool(state.active), state.cursor, state.events.len, state.started_ms })) else |_| {}
    }
}
