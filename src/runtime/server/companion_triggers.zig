// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored party actions. Animation precedes movement; teleport never clips a body.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Actors = @import("actors.zig").Actors;
const party = @import("companions.zig");
const policy = @import("actor_catalog").companions;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;

pub fn owns(classname: []const u8) bool {
    for ([_][]const u8{ "trigger_superfly_spawn", "trigger_mikiko_spawn", "trigger_sidekick", "trigger_sidekick_stop", "trigger_sidekick_teleport" }) |name| if (std.mem.eql(u8, classname, name)) return true;
    return false;
}
pub fn spawn(world: *data.World, projections: []abi.EntityProjection) !void {
    var ids: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (owns(object.classname)) {
            ids[count] = entity;
            count += 1;
        };
    }
    for (ids[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        try world.put(entity, data.Trigger{ .limit = if (std.mem.eql(u8, object.classname, "trigger_sidekick_teleport")) 0 else 1, .wait_ms = 200 });
        if (std.mem.endsWith(u8, object.classname, "_spawn")) if (world.get(entity, data.Binding) catch null) |binding| {
            // Supplied rescue volumes use their upper corner as the spawn origin.
            (try world.get(entity, data.Transform)).position = projections[binding.slot].shared.absmax;
            (try world.get(entity, data.Body)).contents = 0;
            projections[binding.slot].shared.contents = 0;
            engine.link(&projections[binding.slot]);
        };
    }
}
fn destination(world: *data.World, object: data.MapObject) !v.Vec3 {
    if (object.target.len > 0) {
        const target = @import("scripts.zig").named(world, object.target) orelse return error.MissingCompanionDestination;
        return (try world.get(target, data.Transform)).position;
    }
    return .{ try prop.number(object, "x", 0), try prop.number(object, "y", 0), try prop.number(object, "z", 0) };
}
pub fn use(actors: *Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) !void {
    const trigger = try world.get(entity, data.Trigger);
    if (now < trigger.ready_ms or (trigger.limit > 0 and trigger.uses >= trigger.limit)) return;
    const object = (try world.get(entity, data.MapObject)).*;
    const owner = if (world.find(activator)) |candidate| if ((world.get(candidate, data.Player) catch null) != null) candidate else slots.occupants[0] else slots.occupants[0];
    if (std.mem.endsWith(u8, object.classname, "_spawn")) {
        const identity: policy.Identity = if (std.mem.eql(u8, object.classname, "trigger_mikiko_spawn")) .mikiko else .superfly;
        if (party.find(world, identity) == null) {
            const pose = (try world.get(entity, data.Transform)).*;
            const actor = try actors.spawnDynamic(world, slots, projections, @tagName(identity), pose.position, pose.angles, now);
            if (owner) |player| (try world.get(actor, data.Companion)).owner = try world.persistentId(player);
        }
    } else if (std.mem.eql(u8, object.classname, "trigger_sidekick")) {
        const name = prop.text(object, "sidekick") orelse object.targetname;
        const identity = std.meta.stringToEnum(policy.Identity, name) orelse return error.InvalidCompanionIdentity;
        if (party.find(world, identity)) |actor| (try world.get(actor, data.Companion)).enabled = try prop.number(object, "toggle", 0) != 0;
    } else {
        const teleport = std.mem.eql(u8, object.classname, "trigger_sidekick_teleport");
        const point = try destination(world, object);
        var voiced = false;
        // The reference gives the second party member the shared teleport line first.
        const identities: [2]policy.Identity = if (teleport) .{ .mikiko, .superfly } else .{ .superfly, .mikiko };
        for (identities) |identity| {
            const follower = party.find(world, identity) orelse continue;
            if ((try world.get(follower, data.Health)).current <= 0) continue;
            const state = try world.get(follower, data.Companion);
            if (!teleport and (state.stopped or state.authored == .stop)) continue;
            if (owner) |player| state.owner = try world.persistentId(player);
            state.authored = if (teleport) .teleport else .stop;
            state.stopped = false;
            state.destination = point;
            state.target = 0;
            state.collecting = 0;
            state.collect_forced = false;
            state.yielding_until_ms = 0;
            state.animation_until = null;
            state.after_teleport = if (object.flags & 1 != 0) .stay else if (object.flags & 2 != 0) .follow else state.order;
            const actor = try world.get(follower, data.Actor);
            actor.mode = .idle;
            actor.scripted_pose = null;
            if (prop.text(object, "animation")) |name| if (name.len > 0) {
                const sequence = try actors.findSequence(actor.definition, name) orelse return error.MissingCompanionAnimation;
                actor.scripted_pose = sequence;
                actor.scripted_ms = now;
                state.animation_until = now + sequence.duration();
            };
            // Sound event creation is structural; retain no component pointers across it.
            if (!voiced) if (prop.text(object, "sound")) |sound| if (sound.len > 0) {
                const pose = (try world.get(follower, data.Transform)).position;
                const slot = (try world.get(follower, data.Binding)).slot;
                try @import("events.zig").sound(world, slots, projections, sound, pose, slot, c.CHAN_VOICE, now);
                voiced = true;
            };
        }
    }
    const used = try world.get(entity, data.Trigger);
    used.uses += 1;
    used.ready_ms = now + used.wait_ms;
}
/// Reference search envelope with a checked failure result. An occupied destination
/// leaves the action pending instead of consuming uninitialized coordinates.
pub fn clearSpot(world: *data.World, entity: ecs.Entity, origin: v.Vec3) !?v.Vec3 {
    const body = (try world.get(entity, data.Body)).*;
    const slot = (try world.get(entity, data.Binding)).slot;
    const service = engine.collisionService();
    const clear = try service.trace(.{ .start = origin, .end = v.add(origin, .{ 0, 0, 6 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
    if (!clear.start_solid and !clear.all_solid and clear.fraction == 1) return clear.end;
    const yaw = (try world.get(entity, data.Transform)).angles[1];
    for (0..8) |direction| {
        const forward = v.basis(.{ -5, yaw + @as(f32, @floatFromInt(direction)) * 45, 0 }).forward;
        var distance: f32 = 128;
        while (distance > 32) : (distance -= 8) {
            const end = v.add(origin, v.add(v.scale(forward, distance), .{ 0, 0, 8 }));
            const start = v.add(origin, v.scale(v.normalize(v.subtract(end, origin)), distance * 0.75));
            const hit = try service.trace(.{ .start = start, .end = end, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
            if (!hit.start_solid and !hit.all_solid and hit.fraction == 1) return hit.end;
        }
    }
    return null;
}
pub fn advance(world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, now: i64) !bool {
    const state = try world.get(entity, data.Companion);
    if (state.authored == .none) return false;
    actor.threat = 0;
    actor.mode = .idle;
    if (state.animation_until) |deadline| {
        if (now < deadline) return true;
        state.animation_until = null;
        actor.scripted_pose = null;
    }
    switch (state.authored) {
        .none => unreachable,
        .stop => {
            if (v.length(state.destination) > 0 and v.length(v.subtract(pose.position, state.destination)) > 24) {
                actor.threat_position = state.destination;
                actor.mode = .chase;
            } else {
                state.order = .stay;
                state.stopped = true;
                state.authored = .none;
            }
        },
        .teleport => {
            if (now < state.next_ms) return true;
            state.next_ms = now + 100;
            const point = try clearSpot(world, entity, state.destination) orelse return true;
            pose.position = point;
            state.motor = .{ .command_ms = now, .ducked = state.motor.ducked };
            state.jump_started_ms = 0;
            (try world.get(entity, data.Velocity)).linear = @splat(0);
            actor.route = .{};
            state.order = state.after_teleport;
            state.authored = .none;
        },
    }
    return true;
}
