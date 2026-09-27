// SPDX-License-Identifier: GPL-2.0-or-later
//! Party lane yielding and physical, unlocked door use. No catch-up teleport.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const v = @import("../domain/vector.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const Slots = @import("../engine/slots.zig").Slots;
const std = @import("std");
pub fn prepare(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, body: data.Body, now: i64) !void {
    const companion = try world.get(entity, data.Companion);
    if (!companion.enabled or companion.stopped or companion.authored != .none or body.motion_owner != null or actor.scripted_pose != null) return;
    const slot = (try world.get(entity, data.Binding)).slot;
    if (now < companion.yielding_until_ms) {
        actor.mode = .chase;
        actor.threat_position = companion.yield_position;
        return;
    }
    var yielding_to: ?ecs.Entity = null;
    if (world.find(companion.owner)) |owner| {
        const leader = (try world.get(owner, data.Transform)).*;
        const motion = (try world.get(owner, data.Velocity)).linear;
        const delta = v.subtract(pose.position, leader.position);
        // Yield only when occupying the leader's movement lane, even on Stay.
        if (v.length(delta) < 96 and v.length(motion) > 20 and v.dot(v.normalize(motion), v.normalize(delta)) > 0.5) yielding_to = owner;
    }
    if (actor.mode == .chase) {
        const toward = if (actor.route.waypoint) |point| point.point else actor.threat_position;
        const direction = v.normalize(.{ toward[0] - pose.position[0], toward[1] - pose.position[1], 0 });
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, 64)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        if (hit.fraction < 1 and hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |obstacle| {
            if (world.get(obstacle, data.Mover) catch null) |mover| {
                const object = (try world.get(obstacle, data.MapObject)).*;
                if ((std.mem.eql(u8, object.classname, "func_door") or std.mem.eql(u8, object.classname, "func_door_rotating")) and object.targetname.len == 0 and !mover.toggle and !mover.moving() and mover.state == .closed and try @import("properties.zig").number(object, "health", 0) <= 0) {
                    // Companion-owned keys are checked by mover use, just as for
                    // any other activator. Never borrow the player's inventory.
                    try @import("movers.zig").use(world, slots, projections, obstacle, try world.persistentId(entity), now);
                    return; // Mover sounds may relocate ECS component columns.
                }
            } else if ((world.get(obstacle, data.Player) catch null) != null or ((world.get(obstacle, data.Companion) catch null) != null and hit.entity < slot)) {
                yielding_to = obstacle;
            }
        };
    }
    if (yielding_to) |other| {
        const other_pose = (try world.get(other, data.Transform)).*;
        var heading = pose;
        heading.angles[1] = other_pose.angles[1];
        const roll: f32 = if (companion.identity == .mikiko) 0 else 1;
        if (try @import("actor_motion.zig").sidestepDistance(heading, body, slot, roll, 64)) |point| {
            if (try engine.collisionService().contents(v.add(point, .{ 0, 0, body.mins[2] + 1 }), slot) & (c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO) != 0) return;
            companion.yield_position = point;
            companion.yielding_until_ms = now + 1000;
            actor.route = .{};
            actor.mode = .chase;
            actor.threat_position = point;
        }
    }
}

/// Reuse native collision/step/swim/ladder physics with supplied class hull and
/// speed. Routing only submits commands; it never installs a waypoint position.
pub fn move(world: *data.World, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, service: @import("../domain/navigation.zig").Service, definition: @import("../domain/actors.zig").Definition, speed: f32, threat: v.Vec3, slot: u16, now: i64, elapsed: u32) !void {
    const nav = @import("../domain/navigation.zig");
    const movement = @import("../domain/player_move.zig");
    const ground = @import("actor_motion.zig");
    const companion = try world.get(entity, data.Companion);
    const moving = body.motion_owner == null and (actor.mode == .chase or actor.mode == .flee);
    if (moving and actor.mode == .flee) {
        if (!actor.route.fleeing or now >= actor.escape_until or actor.route.blocked or nav.horizontalDistance(pose.position, actor.route.destination) < 24) {
            actor.route = .{ .destination = (try ground.escape(service, pose.position, threat, body.*, slot)) orelse pose.position, .fleeing = true, .progress_ms = now, .progress_position = pose.position };
            actor.escape_until = now + 800;
        }
    } else if (actor.route.fleeing) actor.route = .{};
    var command: movement.Command = .{ .time_ms = now, .angles = .{ 0, pose.angles[1], 0 } };
    var goal: ?nav.Waypoint = null;
    if (moving) {
        const destination = if (actor.mode == .flee) actor.route.destination else actor.threat_position;
        goal = try actor.route.update(service, .{ .position = pose.position, .destination = destination, .slot = slot, .player = true }, now);
        if (try ground.direct(pose.position, destination, body.*, slot)) goal = .{ .point = destination };
        // A visible submerged destination has no ground-floor requirement.
        if (companion.motor.water_level > 1 and try engine.collisionService().contents(destination, slot) & c.MASK_WATER != 0) {
            const clear = try engine.collisionService().trace(.{ .start = pose.position, .end = destination, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
            if (!clear.start_solid and clear.fraction == 1) goal = .{ .point = destination };
        }
    }
    var desired_speed = speed;
    if (goal) |point| {
        const delta = v.subtract(point.point, pose.position);
        const distance = nav.horizontalDistance(point.point, pose.position);
        if (distance > 0.1) {
            pose.angles[1] = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
            command.angles[1] = pose.angles[1];
            command.forward = 127;
            // Arrive without running past a short scripted destination.
            desired_speed = @min(speed, distance * 1000 / @as(f32, @floatFromInt(@max(elapsed, 1))));
        }
        if (companion.motor.water_level > 1) {
            if (distance > 0.1) {
                command.angles[0] = -std.math.atan2(delta[2], distance) * 180 / std.math.pi;
                desired_speed = @min(speed, v.length(delta) * 1000 / @as(f32, @floatFromInt(@max(elapsed, 1))));
            } else if (@abs(delta[2]) > 4) command.up = if (delta[2] > 0) 127 else -127;
        } else if (point.ladder and @abs(delta[2]) > 4) {
            command.up = if (delta[2] > 0) 127 else -127;
        } else if (point.crouch or try @import("../domain/navigation_input.zig").crouch(engine.collisionService(), pose.position, point.point, definition.mins, definition.maxs, slot, body.collision_mask)) {
            command.up = -127;
        } else if (point.jump and body.grounded and now >= actor.jump_ready_ms and !companion.motor.jump_held) {
            command.up = 127;
            actor.jump_ready_ms = now + 700;
        }
    }
    // Cinematic pauses and explicit motion owners must not accumulate commands.
    companion.motor.command_ms = @max(companion.motor.command_ms, now - elapsed);
    companion.motor.mode = if (body.motion_owner != null) .frozen else .normal;
    var motion: @import("../domain/slide.zig").State = .{ .position = pose.position, .velocity = velocity.linear };
    const result = try movement.run(&companion.motor, &motion, command, .{ .speed = desired_speed, .jump_speed = definition.upward_speed, .slot = slot, .mask = body.collision_mask, .water_mask = c.MASK_WATER, .solid_mask = c.CONTENTS_SOLID, .mins = definition.mins, .maxs = definition.maxs, .snap_velocity = false }, engine.collisionService());
    for (result.events[0..result.event_count]) |event| switch (event) {
        .jump => companion.jump_started_ms = now,
        else => {},
    };
    body.mins = result.mins;
    body.maxs = result.maxs;
    actor.ground_entity = companion.motor.ground_entity;
    body.grounded = actor.ground_entity != c.ENTITYNUM_NONE;
    pose.position = motion.position;
    velocity.linear = motion.velocity;
}
