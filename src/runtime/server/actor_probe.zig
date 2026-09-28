// SPDX-License-Identifier: GPL-2.0-or-later
//! Controlled setup uses real class-owned actors. Failed hull setup is explicit;
//! these commands never establish ordinary campaign traversal acceptance.
const std = @import("std");
const data = @import("../domain/components.zig");
const Context = @import("world_context.zig").Context;
const engine = @import("../engine/server.zig");
const access = @import("region_access.zig");
pub fn command(name: []const u8, context: *Context, now: i64) !bool {
    if (std.mem.eql(u8, name, "dk3_runtime_actor_ground")) {
        var argument: [32]u8 = undefined;
        const id = try std.fmt.parseInt(u32, engine.argv(1, &argument), 10);
        const ref = access.find(&context.world.?, id) orelse return error.MissingActor;
        const owner = access.contextFor(ref.world) orelse return error.ActorProbeOwnerMissing;
        const scope = try owner.select();
        defer scope.deinit();
        const point = (try ref.get(data.Transform)).position;
        const body = (try ref.get(data.Body)).*;
        const slot = (try ref.get(data.Binding)).slot;
        const hit = try engine.collisionService().trace(.{ .start = point, .end = @import("../domain/vector.zig").add(point, .{ 0, 0, -0.25 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        var output: [384]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&output, "dk3 actor ground: id={d} fraction={d:.4} start={d} all={d} entity={d} normal={d:.3},{d:.3},{d:.3} mins={d:.1},{d:.1},{d:.1} maxs={d:.1},{d:.1},{d:.1}\n", .{ id, hit.fraction, @intFromBool(hit.start_solid), @intFromBool(hit.all_solid), hit.entity, hit.normal[0], hit.normal[1], hit.normal[2], body.mins[0], body.mins[1], body.mins[2], body.maxs[0], body.maxs[1], body.maxs[2] }));
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_actor_spawn")) {
        var buffer: [96]u8 = undefined;
        const requested_map = engine.argv(6, &buffer);
        if (requested_map.len > 0) {
            const destination = access.byName(requested_map) orelse return error.ActorFixtureWorldUnavailable;
            if (destination != context) {
                const scope = try destination.select();
                defer scope.deinit();
                try destination.expose(now);
                return command(name, destination, now);
            }
        }
        const classname = engine.argv(1, &buffer);
        _ = @import("actor_catalog").find(classname) orelse return error.UnknownActorFixture;
        const owned_name = try context.world.?.allocator.dupe(u8, classname);
        var point: data.Vec3 = undefined;
        for (&point, 0..) |*axis, i| {
            axis.* = try std.fmt.parseFloat(f32, engine.argv(@intCast(i + 2), &buffer));
            if (!std.math.isFinite(axis.*) or @abs(axis.*) > 1048576) return error.InvalidActorFixturePosition;
        }
        const yaw = try std.fmt.parseFloat(f32, engine.argv(5, &buffer));
        if (!std.math.isFinite(yaw)) return error.InvalidActorFixtureAngle;
        const entity = try context.systems.actors.spawnDynamic(&context.world.?, &context.slots, &context.projection, owned_name, point, .{ 0, yaw, 0 }, now);
        errdefer @import("weapon_entities.zig").remove(&context.world.?, &context.slots, &context.projection, entity) catch unreachable;
        const body = (try context.world.?.get(entity, data.Body)).*;
        const slot = (try context.world.?.get(entity, data.Binding)).slot;
        const hit = try engine.collisionService().trace(.{ .start = point, .end = point, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        if (hit.start_solid or hit.all_solid) return error.ObstructedActorFixture;
        const seed_text = engine.argv(7, &buffer);
        const seed = if (seed_text.len > 0) try std.fmt.parseInt(u32, seed_text, 10) else (try context.world.?.get(entity, data.Random)).state;
        (try context.world.?.get(entity, data.Random)).state = seed;
        const grounded = std.mem.eql(u8, engine.argv(8, &buffer), "ground");
        if (grounded) {
            var end = point;
            end[2] -= 128;
            const floor = try engine.collisionService().trace(.{ .start = point, .end = end, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
            if (floor.start_solid or floor.all_solid or floor.fraction == 1 or floor.normal[2] < 0.7) return error.MissingActorFixtureFloor;
            point = floor.end;
            (try context.world.?.get(entity, data.Transform)).position = point;
            (try context.world.?.get(entity, data.Body)).grounded = true;
            (try context.world.?.get(entity, data.Actor)).ground_entity = floor.entity;
            try context.systems.actors.publish(&context.world.?, entity, &context.projection, now);
        }
        var feet = point;
        feet[2] += body.mins[2] + 1;
        const water = try engine.collisionService().contents(feet, slot) & @import("../engine/abi.zig").c.MASK_WATER;
        var output: [256]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&output, "dk3 actor fixture: id={d} class={s} map={s} hull-clear=1 seed={d} grounded={d} water={d}\n", .{ try context.world.?.persistentId(entity), owned_name, std.mem.sliceTo(&context.map_name, 0), seed, @intFromBool(grounded), water }));
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_region_actors")) {
        var candidates = access.Damageables.init(&context.world.?, &context.slots);
        while (candidates.next()) |ref| {
            const actor = ref.get(data.Actor) catch continue;
            const owner = access.contextFor(ref.world) orelse return error.ActorProbeOwnerMissing;
            const point = (try ref.get(data.Transform)).position;
            var output: [320]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&output, "dk3 region actor: id={d} map={s} class={s} health={d} threat={d} mode={s} pos={d:.3},{d:.3},{d:.3} step={d} owner={d} home={s}\n", .{ try ref.id(), std.mem.sliceTo(&owner.map_name, 0), @import("actor_catalog").entries[actor.definition].classname, (try ref.get(data.Health)).current, actor.threat, @tagName(actor.mode), point[0], point[1], point[2], actor.stepped_ms orelse -1, if (ref.get(data.Companion) catch null) |companion| companion.owner else 0, (try ref.get(data.MapObject)).authoring_map }));
        }
        engine.print("dk3 region actors complete\n");
        return true;
    }
    return false;
}
