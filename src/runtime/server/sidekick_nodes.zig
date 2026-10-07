// SPDX-License-Identifier: GPL-2.0-or-later
//! Reference sidekick teleport nodes (NODETYPE_TELEPORTSIDEKICK). The first
//! time a player comes within a running stride of one (32 units: the
//! reference's close-distance test at full speed), each living companion is
//! teleported to the node's point and goes on from there with its order.
//! e1m4b's node at the vent exit over the keypad room sends Superfly round to
//! the far end of the casket corridor, whence he walks to the player.
const std = @import("std");
const data = @import("../domain/components.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");

/// Nodes already used since the map (or a save of it) was entered.
pub const State = struct { triggered: u64 = 0 };

pub fn step(state: *State, world: *data.World, slots: *Slots) !void {
    const teleports = @import("authored_nodes.zig").current().teleports;
    for (teleports, 0..) |node, index| {
        if (index >= 64) break;
        const bit = @as(u64, 1) << @intCast(index);
        if (state.triggered & bit != 0) continue;
        const player = near(world, slots, node.position) orelse continue;
        state.triggered |= bit;
        try @import("companion_triggers.zig").teleportParty(world, player, node.point);
    }
}
fn near(world: *data.World, slots: *Slots, point: v.Vec3) ?@import("../ecs/world.zig").Entity {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        _ = world.get(entity, data.Player) catch continue;
        const health = world.get(entity, data.Health) catch continue;
        if (health.current <= 0) continue;
        const pose = world.get(entity, data.Transform) catch continue;
        if (v.length(v.subtract(pose.position, point)) < 32) return entity;
    }
    return null;
}
