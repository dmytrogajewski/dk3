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
            if (try engine.collisionService().contents(v.add(point, .{ 0, 0, body.mins[2] + 1 }), slot) & (c.CONTENTS_LAVA | c.CONTENTS_SLIME) != 0) return;
            companion.yield_position = point;
            companion.yielding_until_ms = now + 1000;
            actor.route = .{};
            actor.mode = .chase;
            actor.threat_position = point;
        }
    }
}
