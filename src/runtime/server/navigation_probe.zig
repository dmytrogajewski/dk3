// SPDX-License-Identifier: GPL-2.0-or-later
//! Read-only route diagnostics and an explicitly isolated pursuit fixture.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
pub fn pickupRoutes(world: *data.World, slots: *const @import("../engine/slots.zig").Slots, service: @import("../domain/navigation.zig").Service) !void {
    var text: [512]u8 = undefined;
    for (slots.occupants[0..c.MAX_CLIENTS], 0..) |occupant, slot| {
        const player = occupant orelse continue;
        const position = (try world.get(player, data.Transform)).position;
        const body = (try world.get(player, data.Body)).*;
        const from = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &position, @as(isize, @intCast(slot)) });
        var query = world.queryAccess(data.World.mask(.{ data.Transform, data.Body, data.MapObject }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.Transform), view.read(data.Body), view.read(data.MapObject)) |item, pose, bounds, object| {
            if (world.get(item, data.Pickup) catch null) |pickup| {
                if (!pickup.visible or pickup.kind != .weapon) continue;
            } else if (world.get(item, data.Objective) catch null) |objective| {
                if (objective.phase != .home and objective.phase != .dropped) continue;
            } else continue;
            const aligned = @import("../domain/navigation_input.zig").pickupPoint(pose.position, bounds.mins, body.mins);
            const raw_area = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &pose.position, @as(isize, c.ENTITYNUM_NONE) });
            const aligned_area = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &aligned, @as(isize, c.ENTITYNUM_NONE) });
            const raw_route = try service.next(.{ .position = position, .destination = pose.position, .slot = @intCast(slot), .player = true });
            const aligned_route = try service.next(.{ .position = position, .destination = aligned, .slot = @intCast(slot), .player = true });
            engine.print(try std.fmt.bufPrintZ(&text, "dk3 pickup route: slot={d} item={d} class={s} from={d} raw_area={d} aligned_area={d} raw_route={d} aligned_route={d} raw_z={d:.3} aligned_z={d:.3}\n", .{ slot, try world.persistentId(item), object.classname, from, raw_area, aligned_area, @intFromBool(raw_route != null), @intFromBool(aligned_route != null), pose.position[2], aligned[2] }));
        };
    }
    engine.print("dk3 pickup routes complete\n");
}
pub fn chase(world: *data.World, player: ecs.Entity, now: i64) !void {
    var argument: [32]u8 = undefined;
    const id = try std.fmt.parseInt(u32, engine.argv(1, &argument), 10);
    const entity = world.find(id) orelse return error.MissingActor;
    _ = try world.get(entity, data.Actor);
    const position = (try world.get(entity, data.Transform)).position;
    const slot = (try world.get(entity, data.Binding)).slot;
    const owner_slot = (try world.get(player, data.Binding)).slot;
    const from = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &position, @as(isize, slot) });
    var areas: [2048]i32 = undefined;
    const mins = v.add(position, .{ -640, -640, -32 });
    const maxs = v.add(position, .{ 640, 640, 64 });
    const count = engine.gateway.call(c.BOTLIB_AAS_BBOX_AREAS, .{ &mins, &maxs, &areas, @as(isize, areas.len) });
    if (count < 0 or count > areas.len) return error.InvalidNavigationAreas;
    var best: ?v.Vec3 = null;
    var cost: isize = 1000;
    for (areas[0..@intCast(count)]) |area| {
        var info = std.mem.zeroes(c.aas_areainfo_t);
        if (engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, area), &info }) == 0) continue;
        var candidate = info.center;
        candidate[2] = position[2] + 32;
        const floor = try engine.collisionService().trace(.{ .start = candidate, .end = v.add(candidate, .{ 0, 0, -64 }), .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .slot = owner_slot, .mask = c.MASK_PLAYERSOLID });
        if (floor.start_solid or floor.fraction == 1 or floor.normal[2] < 0.7 or @abs(floor.end[2] - position[2]) > 16) continue;
        candidate = floor.end;
        const distance = v.length(v.subtract(candidate, position));
        if (distance < 192 or distance > 640) continue;
        const to = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &candidate, @as(isize, owner_slot) });
        const time = engine.gateway.call(c.BOTLIB_AAS_AREA_TRAVEL_TIME_TO_GOAL_AREA, .{ from, &position, to, @as(isize, c.TFL_WALK | c.TFL_BARRIERJUMP | c.TFL_JUMP | c.TFL_AIR) });
        if (time <= 0 or time >= cost) continue;
        const sight = try engine.collisionService().trace(.{ .start = v.add(position, .{ 0, 0, 24 }), .end = v.add(candidate, .{ 0, 0, 16 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
        if (sight.fraction == 1 or sight.start_solid) continue;
        best = candidate;
        cost = time;
    }
    const goal = best orelse return error.NoOccludedNavigationGoal;
    (try world.get(player, data.Transform)).position = goal;
    (try world.get(player, data.Velocity)).linear = @splat(0);
    (try world.get(player, data.Health)).current = 1000;
    const actor = try world.get(entity, data.Actor);
    actor.threat = try world.persistentId(player);
    actor.threat_position = goal;
    actor.threat_seen_ms = now;
    actor.route = .{};
    var text: [240]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig navigation fixture: actor={d} start={d:.3},{d:.3},{d:.3} goal={d:.3},{d:.3},{d:.3} travel={d} occluded=1\n", .{ id, position[0], position[1], position[2], goal[0], goal[1], goal[2], cost }));
}
