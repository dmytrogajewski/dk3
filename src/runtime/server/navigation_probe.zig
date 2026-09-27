// SPDX-License-Identifier: GPL-2.0-or-later
//! Read-only route diagnostics and an explicitly isolated pursuit fixture.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
pub fn corridor(world: *data.World, slots: *const @import("../engine/slots.zig").Slots, entity: ecs.Entity, toward: v.Vec3) !void {
    const position = (try world.get(entity, data.Transform)).position;
    const body = (try world.get(entity, data.Body)).*;
    const player = (try world.get(entity, data.Player)).*;
    const slot = (try world.get(entity, data.Binding)).slot;
    const delta = v.subtract(toward, position);
    const end = v.add(position, v.scale(v.normalize(.{ delta[0], delta[1], 0 }), 80));
    const hit = try engine.collisionService().trace(.{ .start = position, .end = end, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
    const obstacle = if (hit.entity < slots.occupants.len) slots.occupants[hit.entity] else null;
    const object = if (obstacle) |other| world.get(other, data.MapObject) catch null else null;
    const area = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &position, @as(isize, slot) });
    const goal_area = engine.gateway.call(c.BOTLIB_AI_REACHABILITY_AREA, .{ &toward, @as(isize, c.ENTITYNUM_NONE) });
    var text: [512]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 bot corridor: slot={d} from_area={d} goal_area={d} ground={d} water={d} ducked={d} fraction={d:.4} solid={d} obstacle={d} class={s} normal={d:.3},{d:.3},{d:.3}\n", .{ slot, area, goal_area, player.ground_entity, player.water_level, @intFromBool(player.ducked), hit.fraction, @intFromBool(hit.start_solid or hit.all_solid), if (obstacle) |other| try world.persistentId(other) else 0, if (object) |value| value.classname else if (hit.entity == c.ENTITYNUM_WORLD) "world" else "none", hit.normal[0], hit.normal[1], hit.normal[2] }));
}
/// Follow real AAS edges without moving any actor. A repeated area invalidates
/// the route even when each individual lookup reports a reachable destination.
pub fn route() !void {
    var argument: [32]u8 = undefined;
    const from = try std.fmt.parseInt(i32, engine.argv(1, &argument), 10);
    const goal = try std.fmt.parseInt(i32, engine.argv(2, &argument), 10);
    var origin = std.mem.zeroes(c.aas_areainfo_t);
    var target = std.mem.zeroes(c.aas_areainfo_t);
    if (from <= 0 or goal <= 0 or engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, from), &origin }) == 0 or engine.gateway.call(c.BOTLIB_AAS_AREA_INFO, .{ @as(isize, goal), &target }) == 0) return error.InvalidNavigationAreas;
    const flags = c.TFL_WALK | c.TFL_BARRIERJUMP | c.TFL_JUMP | c.TFL_AIR | c.TFL_CROUCH | c.TFL_LADDER | c.TFL_SWIM | c.TFL_WATER | c.TFL_WALKOFFLEDGE | c.TFL_TELEPORT | c.TFL_ELEVATOR | c.TFL_FUNCBOB;
    var seen: [1024]i32 = undefined;
    var count: usize = 0;
    var area = from;
    var point = origin.center;
    var status: []const u8 = "limit";
    var message: [256]u8 = undefined;
    while (count < seen.len) {
        if (area == goal) {
            status = "reached";
            break;
        }
        if (std.mem.indexOfScalar(i32, seen[0..count], area) != null) {
            status = "cycle";
            break;
        }
        seen[count] = area;
        count += 1;
        var step = std.mem.zeroes(c.aas_predictroute_t);
        _ = engine.gateway.call(c.BOTLIB_AAS_PREDICT_ROUTE, .{ &step, @as(isize, area), &point, @as(isize, goal), @as(isize, flags), @as(isize, 1), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0), @as(isize, 0) });
        if (step.stopevent == c.RSE_NOROUTE or step.time <= 0) {
            status = "unreachable";
            break;
        }
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 route edge: from={d} to={d} flags={d}\n", .{ area, step.endarea, step.endtravelflags }));
        area = step.endarea;
        point = step.endpos;
    }
    engine.print(try std.fmt.bufPrintZ(&message, "dk3 route complete: from={d} goal={d} end={d} edges={d} status={s}\n", .{ from, goal, area, count, status }));
}
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
