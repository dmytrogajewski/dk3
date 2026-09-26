// SPDX-License-Identifier: GPL-2.0-or-later
//! Narrow corrections for broken authored circuits, retained from the working port.
const std = @import("std");
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const named = @import("names.zig").named;
pub fn repairHazards(world: *data.World, projections: []abi.EntityProjection) !void {
    var map: [64]u8 = @splat(0);
    _ = engine.gateway.call(abi.c.G_CVAR_VARIABLE_STRING_BUFFER, .{ @as([*:0]const u8, "mapname"), &map, @as(isize, map.len) });
    if (!std.mem.eql(u8, std.mem.sliceTo(&map, 0), "e1m3b")) return;
    // Shooting the supply box removes the laser buttons but the map omits a
    // final reset of their shared damage field. The disabled circuit must stay safe.
    for ([_][]const u8{ "laser1", "laser2", "laser3" }) |name| {
        const buttons = try named(world, name);
        for (buttons.ids[0..buttons.count]) |id| if (world.find(id)) |entity| {
            if (std.mem.eql(u8, (try world.get(entity, data.MapObject)).classname, "func_button")) return;
        };
    }
    const fields = try named(world, "laser_dam");
    for (fields.ids[0..fields.count]) |id| {
        const entity = world.find(id) orelse continue;
        const hazard = world.get(entity, data.Hazard) catch continue;
        if (!hazard.enabled) continue;
        hazard.enabled = false;
        hazard.toggleable = false;
        (try world.get(entity, data.Body)).contents = 0;
        const slot = (try world.get(entity, data.Binding)).slot;
        projections[slot].shared.contents = 0;
        engine.link(&projections[slot]);
        engine.print("dk3 zig: disabled e1m3b laser damage with removed controls\n");
    }
}
