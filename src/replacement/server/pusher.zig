// SPDX-License-Identifier: GPL-2.0-or-later
//! Serial collision transaction. Nothing is published to ECS before every push succeeds.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const c = abi.c;
pub const Move = struct { entity: ecs.Entity, destination: data.Transform };
const Backup = struct { slot: u16, origin: v.Vec3, angles: v.Vec3, ground: i32, yaw_delta: i32 = 0 };
pub fn push(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection, moves: []const Move) !?ecs.Entity {
    var saved: [ecs.max_entities]Backup = undefined;
    var count: usize = 0;
    var seen: [ecs.max_entities]bool = @splat(false);
    var committed = false;
    defer if (!committed) {
        for (saved[0..count]) |before| {
            const projection = &projections[before.slot];
            projection.shared.currentOrigin = before.origin;
            projection.shared.currentAngles = before.angles;
            projection.state.groundEntityNum = before.ground;
            engine.link(projection);
        }
    };
    // Move all brush parts before testing riders against the new assembly.
    for (moves) |move| {
        const slot = (try world.get(move.entity, data.Binding)).slot;
        if (seen[slot]) return error.DuplicateMoverPart;
        seen[slot] = true;
        const projection = &projections[slot];
        saved[count] = .{ .slot = slot, .origin = projection.shared.currentOrigin, .angles = projection.shared.currentAngles, .ground = projection.state.groundEntityNum };
        count += 1;
        projection.shared.currentOrigin = move.destination.position;
        projection.shared.currentAngles = move.destination.angles;
        engine.link(projection);
    }
    for (moves, 0..) |move, part_index| {
        const before = saved[part_index];
        const projection = &projections[before.slot];
        const translation = v.add(move.destination.position, v.scale(before.origin, -1));
        const rotation = v.add(move.destination.angles, v.scale(before.angles, -1));
        const axes = v.basis(rotation);
        const up = v.cross(axes.right, axes.forward);
        // Engine slots give stable iteration order; includes riders outside swept bounds.
        for (slots.occupants, 0..) |occupant, index| {
            const entity = occupant orelse continue;
            if (seen[index]) continue;
            const player = world.get(entity, data.Player) catch continue;
            if (player.mode == .noclip or player.mode == .spectator) continue;
            const other = &projections[index];
            const riding = player.ground_entity == before.slot;
            if (!riding) {
                var intersects = true;
                for (0..3) |axis| if (other.shared.absmin[axis] >= projection.shared.absmax[axis] or other.shared.absmax[axis] <= projection.shared.absmin[axis]) {
                    intersects = false;
                    break;
                };
                if (!intersects) continue;
                const occupied = try engine.collisionService().trace(.{ .start = other.shared.currentOrigin, .end = other.shared.currentOrigin, .mins = other.shared.mins, .maxs = other.shared.maxs, .slot = @intCast(index), .mask = c.MASK_PLAYERSOLID });
                if (!occupied.start_solid) continue;
            }
            const old = other.shared.currentOrigin;
            const offset = v.add(old, v.scale(before.origin, -1));
            const rotated = v.add(v.add(v.scale(axes.forward, offset[0]), v.scale(axes.right, -offset[1])), v.scale(up, offset[2]));
            const destination = v.add(v.add(old, translation), v.add(rotated, v.scale(offset, -1)));
            const hit = try engine.collisionService().trace(.{ .start = destination, .end = destination, .mins = other.shared.mins, .maxs = other.shared.maxs, .slot = @intCast(index), .mask = c.MASK_PLAYERSOLID });
            if (hit.start_solid) {
                const remains = try engine.collisionService().trace(.{ .start = old, .end = old, .mins = other.shared.mins, .maxs = other.shared.maxs, .slot = @intCast(index), .mask = c.MASK_PLAYERSOLID });
                if (!remains.start_solid) {
                    saved[count] = .{ .slot = @intCast(index), .origin = old, .angles = other.shared.currentAngles, .ground = other.state.groundEntityNum };
                    count += 1;
                    seen[index] = true;
                    other.state.groundEntityNum = c.ENTITYNUM_NONE;
                    continue;
                }
                return entity;
            }
            saved[count] = .{ .slot = @intCast(index), .origin = old, .angles = other.shared.currentAngles, .ground = other.state.groundEntityNum, .yaw_delta = @intFromFloat(rotation[1] * 65536 / 360) };
            count += 1;
            seen[index] = true;
            other.shared.currentOrigin = destination;
            if (!riding) other.state.groundEntityNum = c.ENTITYNUM_NONE;
            engine.link(other);
        }
    }
    for (saved[0..count]) |before| {
        const entity = slots.occupants[before.slot].?;
        const projection = &projections[before.slot];
        (try world.get(entity, data.Transform)).* = .{ .position = projection.shared.currentOrigin, .angles = projection.shared.currentAngles };
        if (world.get(entity, data.Player)) |player| {
            player.ground_entity = @intCast(projection.state.groundEntityNum);
            player.delta_angles[1] +%= before.yaw_delta;
        } else |_| {}
    }
    committed = true;
    return null;
}
