// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit development-only target fixture; never used for authored actors.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const c = abi.c;
pub fn command(name: []const u8, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, player: ?ecs.Entity, table: *const @import("../domain/weapons.zig").Table) !bool {
    if (std.mem.eql(u8, name, "dk3_runtime_face_target")) {
        const owner = player orelse return error.MissingPlayer;
        var argument: [32]u8 = undefined;
        const id = try std.fmt.parseInt(u32, engine.argv(1, &argument), 10);
        const target = world.find(id) orelse return error.MissingTarget;
        const target_position = (try world.get(target, data.Transform)).position;
        const target_body = (try world.get(target, data.Body)).*;
        const owner_slot = (try world.get(owner, data.Binding)).slot;
        const target_slot = (try world.get(target, data.Binding)).slot;
        for ([_]f32{ 96, 64, 160 }) |radius| for (0..8) |direction| {
            const angle = @as(f32, @floatFromInt(direction)) * (std.math.pi / 4.0);
            const candidate = v.add(target_position, .{ @cos(angle) * radius, @sin(angle) * radius, target_body.mins[2] + 24 + 32 });
            const floor = try engine.collisionService().trace(.{ .start = candidate, .end = v.add(candidate, .{ 0, 0, -96 }), .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .slot = owner_slot, .mask = c.MASK_PLAYERSOLID });
            if (floor.start_solid or floor.all_solid or floor.fraction == 1 or floor.normal[2] < 0.7) continue;
            const eye = v.add(floor.end, .{ 0, 0, 22 });
            const aim = try engine.collisionService().trace(.{ .start = eye, .end = v.add(target_position, .{ 0, 0, 8 }), .mins = @splat(0), .maxs = @splat(0), .slot = owner_slot, .mask = c.MASK_SHOT });
            if (aim.fraction < 1 and aim.entity != target_slot) continue;
            (try world.get(owner, data.Transform)).position = floor.end;
            (try world.get(owner, data.Velocity)).linear = @splat(0);
            (try world.get(owner, data.Player)).ground_entity = floor.entity;
            var output: [180]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig combat: fixture player={d:.3},{d:.3},{d:.3} target={d}\n", .{ floor.end[0], floor.end[1], floor.end[2], id }));
            return true;
        };
        return error.NoTargetSpace;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_equip")) {
        const owner = player orelse return error.MissingPlayer;
        var buffer: [16]u8 = undefined;
        const id = try std.fmt.parseInt(u5, engine.argv(1, &buffer), 10);
        if (@import("weapon_catalog").find(id) == null) return error.UnknownWeapon;
        const loadout = try world.get(owner, data.Weapons);
        _ = loadout.acquire(table, id, table.entries[id].ammoMax);
        loadout.weapon = id;
        loadout.weaponTime = 0;
        loadout.weaponstate = 0;
        loadout.dk3GlockClip = 10;
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_target")) {
        const owner = player orelse return error.MissingPlayer;
        const pose = (try world.get(owner, data.Transform)).*;
        const height = (try world.get(owner, data.Player)).view_height;
        const start = @import("../domain/combat.zig").eye(pose.position, height);
        const binding = (try world.get(owner, data.Binding)).*;
        const hit = try engine.collisionService().trace(.{ .start = start, .end = v.add(start, v.scale(v.basis(pose.angles).forward, 120)), .mins = @splat(-12), .maxs = @splat(12), .slot = binding.slot, .mask = c.MASK_SHOT });
        if (hit.start_solid or hit.fraction < 0.5) return error.NoTargetSpace;
        const target = try world.create(null, .{ data.Transform{ .position = hit.end }, data.Health{}, data.Body{ .mins = @splat(-12), .maxs = @splat(12), .contents = c.CONTENTS_BODY }, data.MapObject{ .classname = "runtime_target" } });
        errdefer world.destroy(target) catch unreachable;
        const slot = try slots.acquire(target, null);
        errdefer slots.release(slot, target) catch unreachable;
        try world.put(target, data.Binding{ .slot = slot });
        const projection = &projections[slot];
        projection.* = std.mem.zeroes(abi.EntityProjection);
        projection.state.number = slot;
        projection.state.eType = c.ET_DK3_ITEM;
        projection.state.modelindex = try @import("resources.zig").model("models/e1/a_ion.dkm");
        projection.state.pos = @import("../engine/trajectory.zig").stationary(hit.end);
        projection.shared.currentOrigin = hit.end;
        projection.shared.mins = @splat(-12);
        projection.shared.maxs = @splat(12);
        projection.shared.contents = c.CONTENTS_BODY;
        projection.shared.ownerNum = c.ENTITYNUM_NONE;
        engine.link(projection);
        engine.print("dk3 zig combat: target fixture created\n");
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_clear_targets")) {
        const occupants = slots.occupants;
        for (occupants, 0..) |occupant, slot| {
            const entity = occupant orelse continue;
            const object = world.get(entity, data.MapObject) catch continue;
            if (!std.mem.eql(u8, object.classname, "runtime_target")) continue;
            engine.unlink(&projections[slot]);
            try slots.release(@intCast(slot), entity);
            try world.destroy(entity);
        }
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_targets")) {
        for (slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const object = world.get(entity, data.MapObject) catch continue;
            if (!std.mem.eql(u8, object.classname, "runtime_target")) continue;
            var output: [128]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig combat: target={d} health={d}\n", .{ try world.persistentId(entity), (try world.get(entity, data.Health)).current }));
        }
        return true;
    }
    return false;
}
