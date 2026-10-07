// SPDX-License-Identifier: GPL-2.0-or-later
//! Physical bot subgoals for authored route controls. Never fires remote targets.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const nav = @import("../domain/navigation.zig");
const v = @import("../domain/vector.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const prop = @import("properties.zig");
const Slots = @import("../engine/slots.zig").Slots;
pub const Control = struct { id: u32, obstacle: u32, route_obstacle: u32, point: v.Vec3, action: enum { use, touch, shoot } };
pub const Passage = struct { id: u32, point: v.Vec3 };
/// Authored teleporter recovery for a physically blocked AAS route. Reaching
/// the trigger is ordinary walking, qualified through every intervening hull.
pub fn teleportPassage(world: *data.World, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, toward: v.Vec3, goal: v.Vec3, service: nav.Service, now: i64) !?Passage {
    const pose = (try world.get(actor, data.Transform)).*;
    const body = (try world.get(actor, data.Body)).*;
    const slot = (try world.get(actor, data.Binding)).slot;
    const id = try world.persistentId(actor);
    const obstruction = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(v.normalize(v.subtract(toward, pose.position)), 80)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID });
    if (obstruction.fraction == 1) return null;
    const steering = @import("../domain/navigation_input.zig");
    var hazards: [256]steering.Bounds = undefined;
    var hazard_count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{ data.Hazard, data.Binding }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.Hazard), view.read(data.Binding)) |hazard, binding| {
            if (!hazard.enabled) continue;
            if (hazard_count == hazards.len) return null;
            const bounds = projections[binding.slot].shared;
            hazards[hazard_count] = .{ .mins = bounds.absmin, .maxs = bounds.absmax };
            hazard_count += 1;
        };
    }
    var selected: ?Passage = null;
    var nearest: f32 = 640;
    var query = world.queryAccess(data.World.mask(.{ data.WorldControl, data.MapObject, data.Binding }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.WorldControl), view.read(data.MapObject), view.read(data.Binding)) |entity, control, object, binding| {
        if (control.action != .teleport or now < control.ready_ms) continue;
        if (!try @import("world_controls.zig").touches(world, entity, actor) or !@import("keys.zig").allows(world, object, id)) continue;
        const box = projections[binding.slot].shared;
        if (box.contents & c.CONTENTS_TRIGGER == 0) continue;
        // A thin trigger can sit against a wall. Touching it requires hull
        // overlap, not putting the player's origin inside the brush centre.
        var contact = pose.position;
        for (0..3) |axis| contact[axis] = std.math.clamp(contact[axis], box.absmin[axis] - body.maxs[axis] + 1, box.absmax[axis] - body.mins[axis] - 1);
        const distance = nav.horizontalDistance(pose.position, contact);
        if (distance >= nearest) continue;
        const target = try @import("teleports.zig").destination(world, entity);
        if (v.length(v.subtract(target.position, pose.position)) < 128) continue;
        if (try service.next(.{ .position = target.position, .destination = goal, .slot = slot, .player = true, .allow_slime_escape = true }) == null) continue;
        const point = try steering.walkPath(engine.collisionService(), .{ .start = pose.position, .end = contact, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID }, c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO, hazards[0..hazard_count]) orelse continue;
        var overlaps = true;
        for (0..3) |axis| if (point[axis] + body.maxs[axis] <= box.absmin[axis] or point[axis] + body.mins[axis] >= box.absmax[axis]) {
            overlaps = false;
        };
        if (!overlaps) continue;
        selected = .{ .id = try world.persistentId(entity), .point = point };
        nearest = distance;
    };
    return selected;
}
pub fn completed(world: *data.World, control: Control) bool {
    const obstacle = world.find(control.route_obstacle) orelse return true;
    if (world.get(obstacle, data.Mover) catch null) |mover| if (mover.state == .open or mover.state == .opening) return true;
    // A train lift is sent (or called) once it moves.
    if (world.get(obstacle, data.Train) catch null) |train| return train.phase == .moving or train.phase == .teleporting;
    // A navigation gate (toggled wall, damaging volume, breakable, sliding
    // floor or door) is done when it no longer blocks.
    if (gates.closedNow(world, gate_projections, obstacle)) |closed| return !closed;
    _ = world.get(obstacle, data.Mover) catch return true;
    return false;
}
/// Projections for gate checks in `completed` (set by `unblock`).
var gate_projections: []const @import("../engine/abi.zig").EntityProjection = &.{};
const gates = @import("navigation_gates.zig");
/// The authored control to operate first for a goal the live route cannot
/// reach: the route with every navigation gate open crosses a closed gate;
/// seek what opens it (a button, trigger or shot whose authored chain reaches
/// it, with nested prerequisites), or shoot it if it is a breakable.
pub fn unblock(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, state: *gates.State, actor: ecs.Entity, goal: v.Vec3, service: nav.Service, now: i64, avoided: u32) !?Control {
    var waiting = false;
    return unblockWaiting(world, slots, projections, state, actor, goal, service, now, avoided, &waiting);
}
/// `unblock`, also telling whether the gate in the way is already moving
/// (a door opening, a floor sliding out): then there is nothing to operate.
pub fn unblockWaiting(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, state: *gates.State, actor: ecs.Entity, goal: v.Vec3, service: nav.Service, now: i64, avoided: u32, waiting: *bool) !?Control {
    gate_projections = projections;
    waiting.* = false;
    return unblockToward(world, slots, projections, state, actor, goal, service, now, avoided, waiting, 0);
}
/// Where a player waits for the first closed gate on its way to `goal`: the
/// near side of a door a teammate is opening, or one already moving.
pub fn gateFront(world: *data.World, state: *gates.State, actor: ecs.Entity, goal: v.Vec3) !?v.Vec3 {
    const pose = (try world.get(actor, data.Transform)).*;
    const slot = (try world.get(actor, data.Binding)).slot;
    const block = state.blocking(pose.position, slot, goal) orelse return null;
    return block.near;
}
fn unblockToward(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, state: *gates.State, actor: ecs.Entity, goal: v.Vec3, service: nav.Service, now: i64, avoided: u32, waiting: *bool, depth: usize) anyerror!?Control {
    if (depth == 4) return null;
    const pose = (try world.get(actor, data.Transform)).*;
    const slot = (try world.get(actor, data.Binding)).slot;
    const gate = (state.blocking(pose.position, slot, goal) orelse return null).gate;
    if (gate.id == avoided) return null;
    const entity = world.find(gate.id) orelse return null;
    if (world.get(entity, data.Mover) catch null) |mover| if (mover.moving()) {
        waiting.* = true;
        return null;
    };
    const diagnostic = engine.integer("developer") >= 2;
    if (engine.integer("developer") >= 1) {
        var text: [192]u8 = undefined;
        const object = (try world.get(entity, data.MapObject)).*;
        engine.print(std.fmt.bufPrintZ(&text, "dk3 navigation plan: depth={d} gate={s} #{d} {s} targetname={s}\n", .{ depth, @tagName(gate.kind), gate.id & 0xffffff, object.classname, object.targetname }) catch "");
    }
    // A control reachable as the gates stand now comes first (the button on
    // this side of a door). Failing that, one is chosen as if every gate were
    // open: it lies behind another closed gate, planned for next.
    if (try gateControl(world, slots, projections, actor, entity, gate, service, now, avoided, diagnostic)) |control| return control;
    var control: Control = undefined;
    {
        state.open();
        defer state.restore();
        control = try gateControl(world, slots, projections, actor, entity, gate, service, now, avoided, diagnostic) orelse return null;
    }
    const next = (state.blocking(pose.position, slot, control.point) orelse return null).gate;
    if (next.id == gate.id) return null;
    return unblockToward(world, slots, projections, state, actor, control.point, service, now, avoided, waiting, depth + 1);
}
fn gateControl(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, entity: ecs.Entity, gate: gates.Gate, service: nav.Service, now: i64, avoided: u32, diagnostic: bool) !?Control {
    if (gate.kind == .breakable) {
        const breakable = try world.get(entity, data.Destructible);
        if (breakable.shootable) {
            var obstructions: [approach_points]u16 = @splat(c.ENTITYNUM_NONE);
            const point = try approach(world, entity, actor, .shoot, service, projections, diagnostic, &obstructions) orelse return null;
            return .{ .id = gate.id, .obstacle = gate.id, .route_obstacle = gate.id, .point = point, .action = .shoot };
        }
        // One only another breakable's blast brings down (e1m3b's logo
        // wall, fired by a charged panel above it): find what fires it.
    }
    var dependencies: [64]u32 = undefined;
    var control = try seekObstacle(world, slots, projections, actor, entity, service, now, avoided, diagnostic, &dependencies, 0) orelse return null;
    control.route_obstacle = gate.id;
    return control;
}
/// Finishing a prerequisite does not finish the original blocked route. Resolve
/// the next real control from the current world state, retaining the route goal.
pub fn advance(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, control: Control, service: nav.Service, now: i64) !?Control {
    if (completed(world, control)) return null;
    const obstacle = world.find(control.route_obstacle) orelse return null;
    var dependencies: [64]u32 = undefined;
    var next = try seekObstacle(world, slots, projections, actor, obstacle, service, now, 0, false, &dependencies, 0) orelse return null;
    next.route_obstacle = control.route_obstacle;
    return next;
}
pub fn aim(world: *data.World, control: Control) !?v.Vec3 {
    const entity = world.find(control.id) orelse return null;
    if (world.get(entity, data.Health) catch null) |health| if (health.current <= 0) return null;
    if (world.get(entity, data.Mover) catch null) |mover| if (mover.state == .open or mover.state == .opening) return null;
    if (world.find(control.obstacle)) |obstacle| {
        if (world.get(obstacle, data.Mover) catch null) |mover| if (mover.state == .open or mover.state == .opening) return null;
    } else return null;
    return try center(world, entity);
}
pub fn center(world: *data.World, entity: ecs.Entity) !v.Vec3 {
    const pose = (try world.get(entity, data.Transform)).*;
    const body = world.get(entity, data.Body) catch return pose.position;
    return v.add(pose.position, v.scale(v.add(body.mins, body.maxs), 0.5));
}
/// Stay inside a lift shaft until its authored travel brings the rider to the
/// requested floor. Running into the upper landing early can block the pusher.
pub fn ridePoint(world: *data.World, slots: *const Slots, actor: ecs.Entity, ground: u16, destination: v.Vec3) !?v.Vec3 {
    if (ground >= slots.occupants.len) return null;
    const platform = slots.occupants[ground] orelse return null;
    // A train lift carries its rider while it moves: stay at its middle.
    if (world.get(platform, data.Train) catch null) |train| {
        if (train.phase != .moving) return null;
        var middle = try center(world, platform);
        middle[2] = (try world.get(actor, data.Transform)).position[2];
        return middle;
    }
    const mover = world.get(platform, data.Mover) catch return null;
    if (mover.angular or @abs(mover.opened[2] - mover.closed[2]) < 18) return null;
    if (@abs(mover.opened[0] - mover.closed[0]) > 1 or @abs(mover.opened[1] - mover.closed[1]) > 1) return null;
    const rider = (try world.get(actor, data.Transform)).position;
    if (@abs(destination[2] - rider[2]) <= 18) return null;
    const pose = (try world.get(platform, data.Transform)).position;
    // Only wait for real travel. A stationary upper landing does not promise
    // another descent merely because the final objective lies on a lower floor.
    const endpoint = if (mover.moving()) mover.motion.end else if (mover.return_at.at_ms != null) (if (mover.state == .open) mover.closed else mover.opened) else return null;
    if (@abs(destination[2] - (rider[2] + endpoint[2] - pose[2])) >= @abs(destination[2] - rider[2]) - 18) return null;
    var point = try center(world, platform);
    point[2] = rider[2];
    return point;
}
fn linked(source: data.MapObject, target: []const u8) bool {
    if (target.len == 0) return false;
    if (std.mem.eql(u8, source.target, target)) return true;
    for ([_][]const u8{ "target2", "target3", "target4" }) |key| if (prop.text(source, key)) |name| if (std.mem.eql(u8, name, target)) return true;
    return false;
}
/// Follow only authored forwarding controls. Script programs and changetargets
/// are not presumed to fire their epairs; the target router remains authoritative.
fn chain(world: *data.World, source: ecs.Entity, obstacle: ecs.Entity, actor: u32, now: i64, visited: *[64]u32, depth: usize) !bool {
    if (source.index == obstacle.index) return true;
    if (depth == visited.len) return false;
    const id = try world.persistentId(source);
    if (std.mem.indexOfScalar(u32, visited[0..depth], id) != null) return false;
    visited[depth] = id;
    const object = (try world.get(source, data.MapObject)).*;
    if (!@import("keys.zig").allows(world, object, actor)) return false;
    // Event generators fan out to their timed targets like a relay.
    const sequence = world.get(source, data.TargetSequence) catch null;
    // A breakable fires its targets (and removes its killtargets) as it breaks.
    const forwards = sequence != null or std.mem.eql(u8, object.classname, "func_button") or std.mem.eql(u8, object.classname, "trigger_relay") or std.mem.eql(u8, object.classname, "trigger_multiple") or std.mem.eql(u8, object.classname, "trigger_once") or std.mem.eql(u8, object.classname, "trigger_counter") or std.mem.eql(u8, object.classname, "func_explosive");
    if (!forwards) return false;
    if (world.get(source, data.Trigger) catch null) |trigger| if (now < trigger.ready_ms or (trigger.limit > 0 and trigger.uses >= trigger.limit)) return false;
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, target| {
        const timed = if (sequence) |events| for (events.events) |event| {
            if (target.targetname.len != 0 and std.mem.eql(u8, event.target, target.targetname)) break true;
        } else false else false;
        if (!timed and !linked(object, target.targetname)) {
            // Removing the obstacle opens it too (relays that kill laser beams).
            if (entity.index == obstacle.index and target.targetname.len != 0) if (prop.text(object, "killtarget")) |name| if (std.mem.eql(u8, name, target.targetname)) return true;
            continue;
        }
        if (!@import("keys.zig").allows(world, target, actor)) continue;
        if (try chain(world, entity, obstacle, actor, now, visited, depth + 1)) return true;
    };
    return false;
}
pub fn seek(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, toward: v.Vec3, service: nav.Service, now: i64, avoided: u32) !?Control {
    return seekInternal(world, slots, projections, actor, toward, service, now, avoided, false);
}
pub fn diagnose(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, toward: v.Vec3, service: nav.Service, now: i64) !void {
    _ = try seekInternal(world, slots, projections, actor, toward, service, now, 0, true);
}
fn seekInternal(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, toward: v.Vec3, service: nav.Service, now: i64, avoided: u32, diagnostic: bool) !?Control {
    const pose = (try world.get(actor, data.Transform)).*;
    const body = (try world.get(actor, data.Body)).*;
    const slot = (try world.get(actor, data.Binding)).slot;
    var direction = v.subtract(toward, pose.position);
    const ground = (try world.get(actor, data.Player)).ground_entity;
    const platform = if (ground < slots.occupants.len) slots.occupants[ground] else null;
    const descending_lift = direction[2] < -18 and (if (platform) |entity| (world.get(entity, data.Mover) catch null) != null else false);
    // The next AAS descent can be underneath the platform we stand on. Keep
    // that trace's vertical component so the actual lift, not an imaginary
    // horizontal wall, owns the request for its authored control.
    if (!descending_lift) direction[2] = 0;
    direction = v.normalize(direction);
    var hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, 80)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID });
    // A hull grazing a doorway's jamb meets the wall first: look again with a
    // slim body above step height for the door straight ahead.
    if (hit.fraction < 1 and hit.entity >= slots.occupants.len) {
        const slim = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, 80)), .mins = .{ -4, -4, body.mins[2] + 18 }, .maxs = .{ 4, 4, body.maxs[2] }, .slot = slot, .mask = c.MASK_PLAYERSOLID });
        if (slim.fraction < 1 and slim.entity < slots.occupants.len) hit = slim;
    }
    if (diagnostic) {
        var text: [160]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 control seek: slot={d} hit_slot={d} fraction={d:.3} solid={d}\n", .{ slot, hit.entity, hit.fraction, @intFromBool(hit.start_solid) }));
    }
    if (hit.fraction == 1 or hit.entity >= slots.occupants.len) return null;
    const obstacle = slots.occupants[hit.entity] orelse return null;
    var dependencies: [64]u32 = undefined;
    var control = try seekObstacle(world, slots, projections, actor, obstacle, service, now, avoided, diagnostic, &dependencies, 0) orelse return null;
    const mover = world.get(obstacle, data.Mover) catch return null;
    control.route_obstacle = if (world.find(mover.group)) |master| try world.persistentId(master) else try world.persistentId(obstacle);
    return control;
}
fn seekObstacle(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, blocked: ecs.Entity, service: nav.Service, now: i64, avoided: u32, diagnostic: bool, dependencies: *[64]u32, depth: usize) anyerror!?Control {
    var obstacle = blocked;
    // Doors act as one group; other gates (walls, damaging volumes) are their own.
    if (world.get(obstacle, data.Mover) catch null) |mover| {
        if (mover.moving()) return null;
        if (world.find(mover.group)) |master| obstacle = master;
    }
    const obstacle_id = try world.persistentId(obstacle);
    if (depth == dependencies.len or std.mem.indexOfScalar(u32, dependencies[0..depth], obstacle_id) != null) return null;
    dependencies[depth] = obstacle_id;
    const pose = (try world.get(actor, data.Transform)).*;
    const id = try world.persistentId(actor);
    var result: ?Control = null;
    var nearest: f32 = std.math.inf(f32);
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Body, data.Transform, data.Binding }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject), view.read(data.Binding)) |entity, object, binding| {
        const control_id = try world.persistentId(entity);
        if (world.get(entity, data.Mover) catch null) |motion| if (motion.state == .open or motion.moving()) continue;
        if (control_id == avoided or !@import("keys.zig").allows(world, object, id)) continue;
        var action: @FieldType(Control, "action") = .use;
        if (std.mem.eql(u8, object.classname, "func_button") or entity.index == obstacle.index) {
            if (try prop.number(object, "health", 0) > 0) {
                if ((world.get(entity, data.Health) catch continue).current <= 0) continue;
                action = .shoot;
            } else if (std.mem.eql(u8, object.classname, "func_button") and object.flags & 1 != 0) {
                // A beam that switches damage on is never a control.
                if (gates.tripwire(world, object)) continue;
                action = .touch;
            } else if (entity.index == obstacle.index and object.targetname.len != 0) continue;
        } else if ((std.mem.eql(u8, object.classname, "trigger_multiple") or std.mem.eql(u8, object.classname, "trigger_once")) and object.flags & 1 == 0 and projections[binding.slot].shared.contents & c.CONTENTS_TRIGGER != 0) {
            action = .touch;
        } else if (std.mem.eql(u8, object.classname, "func_explosive") and object.targetname.len == 0 and (object.target.len != 0 or prop.text(object, "killtarget") != null)) {
            // A breakable panel whose authored chain does the work (e1m3b's
            // lightning box above the laser corridor).
            const state = world.get(entity, data.Destructible) catch continue;
            if (state.broken or state.hidden or !state.shootable) continue;
            action = .shoot;
        } else continue;
        var visited: [64]u32 = undefined;
        const chained = try chain(world, entity, obstacle, id, now, &visited, 0);
        if (engine.integer("developer") >= 2 and std.mem.eql(u8, object.classname, "func_button")) {
            var text: [192]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&text, "dk3 control candidate: obstacle={d} control={d} {s} target={s} chained={d}\n", .{ obstacle.index, entity.index, object.classname, object.target, @intFromBool(chained) }) catch "");
        }
        if (!chained) continue;
        var obstructions: [approach_points]u16 = @splat(c.ENTITYNUM_NONE);
        if (try approach(world, entity, actor, action, service, projections, diagnostic, &obstructions)) |point| {
            const distance = v.length(v.subtract(point, pose.position));
            if (distance >= nearest) continue;
            nearest = distance;
            result = .{ .id = control_id, .obstacle = obstacle_id, .route_obstacle = obstacle_id, .point = point, .action = action };
        } else for (obstructions, 0..) |blocked_slot, index| {
            if (blocked_slot >= slots.occupants.len or std.mem.indexOfScalar(u16, obstructions[0..index], blocked_slot) != null) continue;
            const blocker = slots.occupants[blocked_slot] orelse continue;
            // A control may itself sit behind another authored door. Walk to that
            // door's real control first; normal use/contact still performs every step.
            const prerequisite = try seekObstacle(world, slots, projections, actor, blocker, service, now, avoided, diagnostic, dependencies, depth + 1) orelse continue;
            const distance = v.length(v.subtract(prerequisite.point, pose.position));
            if (distance >= nearest) continue;
            nearest = distance;
            result = prerequisite;
        }
    };
    return result;
}
/// One step of riding the lift a route's next reachability takes from its
/// entrance (the standing point on the lift at its lower stop).
pub const Lift = union(enum) {
    /// Walk onto the lift: it waits at the entrance.
    board: v.Vec3,
    /// Stay at the lift's middle while it travels or rises on its own.
    hold: v.Vec3,
    /// Operate this control: it sends the lift up, or calls it down.
    operate: Control,
    /// The lift is away and nothing reachable calls it: wait for it.
    wait,
    /// The lift stands away and this rider may not call it: go round.
    away,
};
/// What a lift rider's movement state says (a player's or a companion's own
/// motor), and whether it may operate controls itself.
pub const Rider = struct {
    ground: u16,
    view_height: f32,
    collision: @import("../domain/collision.zig").Collision,
    /// A rider that never presses buttons waits for someone else to send it.
    operate: bool = true,
};
pub fn liftStep(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, rider: Rider, entrance: v.Vec3, service: nav.Service, now: i64) !?Lift {
    const ground = rider.ground;
    const lift = findLift(world, projections, entrance, if (ground < slots.occupants.len) slots.occupants[ground] else null) orelse return null;
    const lift_slot = (try world.get(lift, data.Binding)).slot;
    const box = projections[lift_slot].shared;
    const pose = (try world.get(actor, data.Transform)).*;
    const player: struct { ground_entity: u16, view_height: f32 } = .{ .ground_entity = rider.ground, .view_height = rider.view_height };
    const middle: v.Vec3 = .{ (box.absmin[0] + box.absmax[0]) / 2, (box.absmin[1] + box.absmax[1]) / 2, pose.position[2] };
    const moving = if (world.get(lift, data.Mover) catch null) |mover| mover.moving() else if (world.get(lift, data.Train) catch null) |train| train.phase == .moving or train.phase == .teleporting else false;
    if (engine.integer("developer") >= 2) {
        var text: [192]u8 = undefined;
        engine.print(std.fmt.bufPrintZ(&text, "dk3 lift step: lift={d} slot={d} ground={d} moving={d} z={d:.0} entrance_z={d:.0}\n", .{ lift.index, lift_slot, player.ground_entity, @intFromBool(moving), pose.position[2], entrance[2] }) catch "");
    }
    var dependencies: [64]u32 = undefined;
    if (player.ground_entity == lift_slot) {
        if (moving) return .{ .hold = middle };
        // Aboard and stopped at the entrance level: set it going.
        if (@abs(pose.position[2] - entrance[2]) < 40) {
            if (!rider.operate) return .{ .hold = middle };
            // Aboard, only a control the lift carries sends it with the rider:
            // a call button on the landing sends it away without them.
            if (try carriedControl(world, projections, actor, lift, box, service, now) orelse try seekObstacle(world, slots, projections, actor, lift, service, now, 0, engine.integer("developer") >= 2, &dependencies, 0)) |found| {
                // Press a button the lift carries from on the lift: from a spot
                // overhanging its edge the moving floor can catch the rider
                // against the landing. The middle serves when it is clear (a
                // platform may carry its button on a console there) and in reach.
                var control = found;
                const body = (try world.get(actor, data.Body)).*;
                const over = control.point[0] + body.mins[0] >= box.absmin[0] and control.point[0] + body.maxs[0] <= box.absmax[0] and control.point[1] + body.mins[1] >= box.absmin[1] and control.point[1] + body.maxs[1] <= box.absmax[1];
                if (!over) if (world.find(control.id)) |button| if (v.length(v.subtract(try center(world, button), v.add(middle, .{ 0, 0, player.view_height }))) < 80) {
                    const room = try rider.collision.trace(.{ .start = middle, .end = middle, .mins = body.mins, .maxs = body.maxs, .slot = (try world.get(actor, data.Binding)).slot, .mask = c.MASK_PLAYERSOLID });
                    if (!room.start_solid and !room.all_solid) control.point = middle;
                };
                return .{ .operate = control };
            }
            return .{ .hold = middle };
        }
        // Stopped elsewhere: arrived, the route goes on from here.
        return null;
    }
    const body = (try world.get(actor, data.Body)).*;
    // An entrance on the landing beside it: its floor is level with the landing.
    // A cage lift (a train with walls and a roof) has its floor well below
    // the top of its box: find the floor inside it at the landing's height.
    var floor_z = box.absmax[2];
    const feet = entrance[2] + body.mins[2];
    const inside = try rider.collision.trace(.{ .start = .{ middle[0], middle[1], feet + 40 }, .end = .{ middle[0], middle[1], feet - 40 }, .mins = .{ -4, -4, 0 }, .maxs = .{ 4, 4, 0 }, .slot = (try world.get(actor, data.Binding)).slot, .mask = c.MASK_PLAYERSOLID });
    if (!inside.start_solid and inside.fraction < 1 and inside.entity == lift_slot and inside.normal[2] > 0.7) floor_z = inside.end[2];
    const level = @abs(floor_z - feet) < 20;
    // Never wait over the shaft or under the lift while it is not level with
    // the landing (a raised lift comes down, a lower one comes up through
    // whoever stands there): step out to the entrance beside it.
    const overlapping = pose.position[0] + body.maxs[0] > box.absmin[0] and pose.position[0] + body.mins[0] < box.absmax[0] and pose.position[1] + body.maxs[1] > box.absmin[1] and pose.position[1] + body.mins[1] < box.absmax[1];
    if (overlapping and (moving or !level)) return .{ .board = entrance };
    if (moving) return .wait;
    // The lift stands at the entrance when its floor is under that point.
    const below = try rider.collision.trace(.{ .start = v.add(entrance, .{ 0, 0, 8 }), .end = v.add(entrance, .{ 0, 0, -48 }), .mins = body.mins, .maxs = body.maxs, .slot = (try world.get(actor, data.Binding)).slot, .mask = c.MASK_PLAYERSOLID });
    if ((below.fraction < 1 and below.entity == lift_slot) or level) return .{ .board = .{ middle[0], middle[1], entrance[2] } };
    if (!rider.operate) return .away;
    if (try seekObstacle(world, slots, projections, actor, lift, service, now, 0, false, &dependencies, 0)) |control| return .{ .operate = control };
    return .wait;
}
/// A button riding on `lift` (inside its footprint) whose chain reaches it,
/// with a standing point to press it from.
fn carriedControl(world: *data.World, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, lift: ecs.Entity, box: anytype, service: nav.Service, now: i64) !?Control {
    const id = try world.persistentId(actor);
    const lift_id = try world.persistentId(lift);
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Binding }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject), view.read(data.Binding)) |entity, object, binding| {
        if (!std.mem.eql(u8, object.classname, "func_button") or binding.slot >= projections.len) continue;
        if (world.get(entity, data.Mover) catch null) |motion| if (motion.state == .open or motion.moving()) continue;
        const own = projections[binding.slot].shared;
        const middle = v.scale(v.add(own.absmin, own.absmax), 0.5);
        if (middle[0] < box.absmin[0] - 8 or middle[0] > box.absmax[0] + 8 or middle[1] < box.absmin[1] - 8 or middle[1] > box.absmax[1] + 8) continue;
        var visited: [64]u32 = undefined;
        if (!try chain(world, entity, lift, id, now, &visited, 0)) continue;
        var obstructions: [approach_points]u16 = @splat(c.ENTITYNUM_NONE);
        const point = try approach(world, entity, actor, .use, service, projections, false, &obstructions) orelse continue;
        return .{ .id = try world.persistentId(entity), .obstacle = lift_id, .route_obstacle = lift_id, .point = point, .action = .use };
    };
    return null;
}
/// The lift (a mover or train) whose footprint holds `point` across, or that
/// it stands beside (a lift link's entrance can lie on the landing next to it).
fn findLift(world: *data.World, projections: []const @import("../engine/abi.zig").EntityProjection, point: v.Vec3, standing: ?ecs.Entity) ?ecs.Entity {
    var best: ?ecs.Entity = null;
    var nearest: f32 = std.math.inf(f32);
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Binding }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Binding)) |entity, binding| {
        if (binding.slot >= projections.len) continue;
        // Something that lifts: a train, or a mover travelling up and down
        // (not a door or button beside the shaft).
        const is_lift = (world.get(entity, data.Train) catch null) != null or if (world.get(entity, data.Mover) catch null) |mover| !mover.angular and @abs(mover.opened[2] - mover.closed[2]) > @max(@abs(mover.opened[0] - mover.closed[0]), @abs(mover.opened[1] - mover.closed[1])) else false;
        if (!is_lift) continue;
        const box = projections[binding.slot].shared;
        if (engine.integer("developer") >= 3) {
            var text: [192]u8 = undefined;
            engine.print(std.fmt.bufPrintZ(&text, "dk3 lift candidate: slot={d} linked={d} box={d:.0},{d:.0},{d:.0}..{d:.0},{d:.0},{d:.0} point={d:.0},{d:.0},{d:.0}\n", .{ binding.slot, box.linked, box.absmin[0], box.absmin[1], box.absmin[2], box.absmax[0], box.absmax[1], box.absmax[2], point[0], point[1], point[2] }) catch "");
        }
        if (box.linked == 0) continue;
        if (point[0] < box.absmin[0] - 32 or point[0] > box.absmax[0] + 32 or point[1] < box.absmin[1] - 32 or point[1] > box.absmax[1] + 32) continue;
        // The lift underfoot is the one to ride.
        if (standing) |entity_under| if (entity_under.index == entity.index) return entity;
        const distance = @abs((box.absmin[2] + box.absmax[2]) / 2 - point[2]);
        if (distance < nearest) {
            nearest = distance;
            best = entity;
        }
    };
    return best;
}
/// Candidate standing points `approach` tries around a control.
pub const approach_points = 13;
/// Nearest supported, reachable standing point from which `action` can operate `target`.
pub fn approach(world: *data.World, target: ecs.Entity, actor: ecs.Entity, action: @FieldType(Control, "action"), service: nav.Service, projections: []const @import("../engine/abi.zig").EntityProjection, diagnostic: bool, obstructions: *[approach_points]u16) !?v.Vec3 {
    const pose = (try world.get(actor, data.Transform)).*;
    const body = (try world.get(actor, data.Body)).*;
    const target_slot = (try world.get(target, data.Binding)).slot;
    const box = projections[target_slot].shared;
    const middle = v.scale(v.add(box.absmin, box.absmax), 0.5);
    const margin: f32 = if (action == .shoot) 96 else if (action == .touch) 2 else 32;
    const probe: Stand = .{
        .world = world,
        .target = target,
        .action = action,
        .service = service,
        .diagnostic = diagnostic,
        .pose = pose,
        .body = body,
        .view_height = (try world.get(actor, data.Player)).view_height,
        .slot = (try world.get(actor, data.Binding)).slot,
        .target_slot = target_slot,
        .middle = middle,
        // A shot at an explosive (a barrel, a charged panel) is fired from
        // outside the worst of its blast.
        .blast = if (action != .shoot) 0 else if (world.get(target, data.Scenery) catch null) |scenery| (if (scenery.explosive) 100 else 0) else if (world.get(target, data.Destructible) catch null) |destructible| (if (destructible.damage > 0) destructible.radius else 0) else 0,
    };
    var chosen: ?v.Vec3 = null;
    var distance: f32 = std.math.inf(f32);
    if (action == .shoot) {
        // A shooter stands anywhere with a line to it: out along eight
        // directions from its edge, the first good spot on each (a target
        // down a narrow corridor is in sight only from along it).
        const half = @max(box.absmax[0] - box.absmin[0], box.absmax[1] - box.absmin[1]) / 2 + body.maxs[0];
        for (0..8) |way| {
            const angle = @as(f32, @floatFromInt(way)) * std.math.pi / 4;
            // Close rings first, then farther out down a long corridor (a
            // panel behind a gated stretch is shot from its near end).
            var ring: f32 = 8;
            while (ring <= 640) : (ring += if (ring < 200) 16 else 48) {
                var blocker: u16 = c.ENTITYNUM_NONE;
                const point = try probe.check(.{ middle[0] + @cos(angle) * (half + ring), middle[1] + @sin(angle) * (half + ring), middle[2] }, &blocker);
                if (ring == 8) obstructions[1 + way] = blocker;
                const found = point orelse continue;
                const length = v.length(v.subtract(pose.position, found));
                if (length < distance) {
                    chosen = found;
                    distance = length;
                }
                break;
            }
        }
    } else {
        // Beside each face at the action's margin and close up, and off each
        // corner: a button recessed in a wall is in sight only from in front.
        var points: [approach_points]v.Vec3 = @splat(middle);
        for ([_]f32{ margin, 4 }, 0..) |gap, row| {
            points[1 + row * 4][0] = box.absmin[0] - body.maxs[0] - gap;
            points[2 + row * 4][0] = box.absmax[0] - body.mins[0] + gap;
            points[3 + row * 4][1] = box.absmin[1] - body.maxs[1] - gap;
            points[4 + row * 4][1] = box.absmax[1] - body.mins[1] + gap;
        }
        for (0..4) |corner| {
            points[9 + corner][0] = if (corner & 1 == 0) box.absmin[0] - body.maxs[0] - margin * 0.7 else box.absmax[0] - body.mins[0] + margin * 0.7;
            points[9 + corner][1] = if (corner & 2 == 0) box.absmin[1] - body.maxs[1] - margin * 0.7 else box.absmax[1] - body.mins[1] + margin * 0.7;
        }
        // A trigger is also touched from its middle.
        for (points, 0..) |candidate, index| {
            if (index == 0 and action != .touch) continue;
            const found = try probe.check(candidate, &obstructions[index]) orelse continue;
            const length = v.length(v.subtract(pose.position, found));
            if (length < distance) {
                chosen = found;
                distance = length;
            }
        }
    }
    // Where the player stands may already do.
    if (action != .touch) if (try probe.check(pose.position, &obstructions[0])) |found| return found;
    return chosen;
}
/// A standing point with a navigation area from which a player's hull meets
/// the volume `mins..maxs`: its centre, else just outside each face (a thin
/// exit strip set against the end of the walkable space has its centre where
/// no area reaches, yet a player in front of it touches it).
pub fn touchPoint(mins: v.Vec3, maxs: v.Vec3, slot: u16) !?v.Vec3 {
    return touchPointFrom(mins, maxs, slot, null);
}
/// `touchPoint`, preferring a point the route from `from` reaches (the
/// centre of a trigger set against a console can lie in an area of its own).
pub fn touchPointFrom(mins: v.Vec3, maxs: v.Vec3, slot: u16, from: ?struct { position: v.Vec3, service: nav.Service }) !?v.Vec3 {
    const navigation = @import("../engine/navigation.zig");
    const hull_mins: v.Vec3 = .{ -15, -15, -24 };
    const hull_maxs: v.Vec3 = .{ 15, 15, 32 };
    var centre = v.scale(v.add(mins, maxs), 0.5);
    centre[2] = @min(maxs[2], mins[2] - hull_mins[2] + 8);
    var first: ?v.Vec3 = null;
    var candidates: [5]v.Vec3 = @splat(centre);
    candidates[1][0] = mins[0] - hull_maxs[0] + 1;
    candidates[2][0] = maxs[0] - hull_mins[0] - 1;
    candidates[3][1] = mins[1] - hull_maxs[1] + 1;
    candidates[4][1] = maxs[1] - hull_mins[1] - 1;
    for (candidates) |candidate| {
        var point = candidate;
        const floor = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -512 }), .mins = hull_mins, .maxs = hull_maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID });
        if (floor.start_solid or floor.all_solid) continue;
        if (floor.fraction < 1) point = floor.end;
        // The hull there must still meet the volume.
        if (point[2] + hull_maxs[2] < mins[2] or point[2] + hull_mins[2] > maxs[2]) continue;
        if (navigation.destinationArea(point) == 0) continue;
        const origin = from orelse return point;
        if (first == null) first = point;
        if (try origin.service.next(.{ .position = origin.position, .destination = point, .slot = slot, .player = true }) != null) return point;
    }
    return first;
}
/// A civilian whose body stands in a control's travel (a worker typing at the
/// console a button is set in): the control cannot move while he is there.
pub fn civilianBlocker(world: *data.World, projections: []const @import("../engine/abi.zig").EntityProjection, control: ecs.Entity) !?u32 {
    const mover = world.get(control, data.Mover) catch return null;
    if (mover.angular or mover.state == .open) return null;
    const binding = world.get(control, data.Binding) catch return null;
    if (binding.slot >= projections.len) return null;
    const box = projections[binding.slot].shared;
    const pose = (try world.get(control, data.Transform)).position;
    var low = box.absmin;
    var high = box.absmax;
    for ([_]v.Vec3{ mover.closed, mover.opened }) |end| for (0..3) |axis| {
        low[axis] = @min(low[axis], box.absmin[axis] + end[axis] - pose[axis]) - 1;
        high[axis] = @max(high[axis], box.absmax[axis] + end[axis] - pose[axis]) + 1;
    };
    var query = world.queryAccess(data.World.mask(.{ data.Actor, data.Health, data.Transform, data.Body }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Actor), view.read(data.Health), view.read(data.Transform), view.read(data.Body)) |entity, actor, health, transform, body| {
        if (health.current <= 0 or @import("actor_catalog").entries[actor.definition].kind != .civilian) continue;
        var overlaps = true;
        for (0..3) |axis| if (transform.position[axis] + body.mins[axis] >= high[axis] or transform.position[axis] + body.maxs[axis] <= low[axis]) {
            overlaps = false;
        };
        if (overlaps) return try world.persistentId(entity);
    };
    return null;
}
/// A health station (hosportal and kin): used up close, facing it.
pub fn isStation(world: *data.World, entity: ecs.Entity) bool {
    const control = world.get(entity, data.WorldControl) catch return false;
    return control.action == .healer;
}
/// One candidate standing point for `approach`.
const Stand = struct {
    world: *data.World,
    target: ecs.Entity,
    action: @FieldType(Control, "action"),
    service: nav.Service,
    diagnostic: bool,
    pose: data.Transform,
    body: data.Body,
    view_height: f32,
    slot: u16,
    target_slot: u16,
    middle: v.Vec3,
    blast: f32,

    /// The floor under `candidate` if the action works from there and the
    /// route reaches it; `obstruction` names what hid or held it.
    fn check(self: Stand, candidate: v.Vec3, obstruction: *u16) !?v.Vec3 {
        var text: [512]u8 = undefined;
        // Buttons and triggers are operated from the floor below them; a
        // shooter may stand anywhere up to its own height.
        var top = candidate;
        const base = (if (self.action == .shoot) @max(self.pose.position[2], self.middle[2]) else self.middle[2]);
        // From above the control, lower when a lintel or ledge is in the way.
        // Bodies are not floors: a monster in front of a button moves on.
        var found: ?@import("../domain/collision.zig").Trace = null;
        var blocker: ?u16 = null;
        for ([_]f32{ 48, 16, -16 }) |rise| {
            top[2] = base + rise;
            // A shot may come from far below a control set high on a wall
            // (a box at the ceiling over a keypad).
            const depth: f32 = if (self.action == .shoot) 640 else 256;
            const support = try @import("../domain/navigation_input.zig").supportedPoint(engine.collisionService(), .{ .start = top, .end = v.add(top, .{ 0, 0, -depth }), .mins = self.body.mins, .maxs = self.body.maxs, .slot = self.slot, .mask = @as(u32, c.MASK_PLAYERSOLID) & ~@as(u32, c.CONTENTS_BODY) });
            if (support.floor) |hit| {
                found = hit;
                break;
            }
            if (blocker == null) blocker = support.obstruction;
        }
        const floor = found orelse {
            obstruction.* = blocker orelse c.ENTITYNUM_NONE;
            return null;
        };
        if (self.diagnostic) engine.print(try std.fmt.bufPrintZ(&text, "dk3 control floor: slot={d} control={d} point={d:.2},{d:.2},{d:.2} fraction={d:.3} solid={d} normal_z={d:.3}\n", .{ self.slot, try self.world.persistentId(self.target), floor.end[0], floor.end[1], floor.end[2], floor.fraction, @intFromBool(floor.start_solid or floor.all_solid), floor.normal[2] }));
        if (try engine.collisionService().contents(v.add(floor.end, .{ 0, 0, self.body.mins[2] + 1 }), self.slot) & (c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO) != 0) return null;
        const eye = v.add(floor.end, .{ 0, 0, self.view_height });
        // Actors and corpses move or can be cleared; only geometry hides a control.
        // A shot is a bolt-sized box: an edge the sight line just clears
        // stops it.
        const bolt: f32 = if (self.action == .shoot) 3 else 0;
        const sight = try engine.collisionService().trace(.{ .start = eye, .end = self.middle, .mins = @splat(-bolt), .maxs = @splat(bolt), .slot = self.slot, .mask = @as(u32, c.MASK_SHOT) & ~@as(u32, c.CONTENTS_BODY | c.CONTENTS_CORPSE) });
        if (self.diagnostic) engine.print(try std.fmt.bufPrintZ(&text, "dk3 control sight: slot={d} control={d} hit_slot={d} target_slot={d} range={d:.3}\n", .{ self.slot, try self.world.persistentId(self.target), sight.entity, self.target_slot, v.length(v.subtract(sight.end, eye)) }));
        // A clear line to the middle counts: decorations are not in the shot mask.
        if (self.action != .touch and sight.entity != self.target_slot and sight.fraction < 1) {
            obstruction.* = sight.entity;
            return null;
        }
        if (self.blast > 0 and v.length(v.subtract(floor.end, self.middle)) < self.blast / 2) return null;
        if (self.action == .use and v.length(v.subtract(sight.end, eye)) > 88) return null;
        // A health station heals only a recipient within 64 of its origin.
        if (self.action == .use and isStation(self.world, self.target)) if (v.length(v.subtract((try self.world.get(self.target, data.Transform)).position, floor.end)) > 56) return null;
        var reachable = try self.service.next(.{ .position = self.pose.position, .destination = floor.end, .slot = self.slot, .player = true }) != null;
        // A short level walk needs no route: a control carried on the lift the
        // player stands on lies in shaft space the area graph leaves empty.
        if (!reachable and nav.horizontalDistance(self.pose.position, floor.end) < 128 and @abs(floor.end[2] - self.pose.position[2]) < 18) {
            reachable = try @import("../domain/navigation_input.zig").walkPath(engine.collisionService(), .{ .start = self.pose.position, .end = floor.end, .mins = self.body.mins, .maxs = self.body.maxs, .slot = self.slot, .mask = c.MASK_PLAYERSOLID }, c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO, &.{}) != null;
        }
        if (self.diagnostic) engine.print(try std.fmt.bufPrintZ(&text, "dk3 control approach: slot={d} control={d} reachable={d}\n", .{ self.slot, try self.world.persistentId(self.target), @intFromBool(reachable) }));
        return if (reachable) floor.end else null;
    }
};
/// Give an occupied narrow lane to the teammate ahead, with a traced safe floor.
pub fn yieldPoint(world: *data.World, slots: *Slots, actor: ecs.Entity, toward: v.Vec3) !?v.Vec3 {
    const pose = (try world.get(actor, data.Transform)).*;
    const body = (try world.get(actor, data.Body)).*;
    const slot = (try world.get(actor, data.Binding)).slot;
    const team = (try world.get(actor, data.Session)).*;
    const forward = v.normalize(.{ toward[0] - pose.position[0], toward[1] - pose.position[1], 0 });
    const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(forward, 56)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID });
    if (hit.fraction == 1 or hit.entity >= slots.occupants.len) return null;
    const other = slots.occupants[hit.entity] orelse return null;
    const member = (world.get(other, data.Session) catch return null).*;
    if (!@import("../domain/multiplayer.zig").allied(team, member)) return null;
    // Human teammates retain priority; two bots choose one yielding participant.
    if (member.bot and slot < hit.entity) return null;
    const side: v.Vec3 = .{ -forward[1], forward[0], 0 };
    for ([_]f32{ 1, -1 }) |sign| {
        const point = v.add(v.add(pose.position, v.scale(side, sign * 48)), v.scale(forward, -24));
        const passage = try engine.collisionService().trace(.{ .start = pose.position, .end = point, .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID });
        if (passage.fraction < 1 or passage.start_solid or passage.all_solid) continue;
        const floor = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -40 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID });
        if (floor.fraction == 1 or floor.normal[2] < 0.7 or floor.start_solid or floor.all_solid) continue;
        if (try engine.collisionService().contents(v.add(floor.end, .{ 0, 0, body.mins[2] + 1 }), slot) & (c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO) != 0) continue;
        return floor.end;
    }
    return null;
}

test "route controls follow authored relay chains without bypassing locks or scripts" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 8);
    defer world.deinit();
    _ = try world.create(1, .{data.Keys{}});
    const button = try world.create(2, .{data.MapObject{ .classname = "func_button", .target = "relay" }});
    const relay = try world.create(3, .{data.MapObject{ .classname = "trigger_relay", .targetname = "relay", .target = "door" }});
    const door = try world.create(4, .{data.MapObject{ .classname = "func_door", .targetname = "door" }});
    var visited: [64]u32 = undefined;
    try t.expect(try chain(&world, button, door, 1, 0, &visited, 0));
    (try world.get(door, data.MapObject)).properties = &.{.{ .key = "keyname", .value = "item_control_card_red" }};
    try t.expect(!try chain(&world, button, door, 1, 0, &visited, 0));
    (try world.get(door, data.MapObject)).properties = &.{};
    (try world.get(relay, data.MapObject)).classname = "trigger_script";
    try t.expect(!try chain(&world, button, door, 1, 0, &visited, 0));
    (try world.get(relay, data.MapObject)).classname = "trigger_relay";
    (try world.get(relay, data.MapObject)).target = "relay";
    try t.expect(!try chain(&world, button, door, 1, 0, &visited, 0));
}

test "an open prerequisite keeps the original blocked route active" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 4);
    defer world.deinit();
    const root = try world.create(110, .{data.Mover{ .closed = @splat(0), .opened = .{ 0, 0, 128 }, .motion = .{} }});
    const prerequisite = try world.create(321, .{data.Mover{ .closed = @splat(0), .opened = .{ 0, 0, 128 }, .motion = .{}, .state = .open }});
    const control: Control = .{ .id = 507, .obstacle = 321, .route_obstacle = 110, .point = @splat(0), .action = .use };
    try t.expect(!completed(&world, control));
    try world.destroy(prerequisite);
    try t.expect(!completed(&world, control));
    (try world.get(root, data.Mover)).state = .opening;
    try t.expect(completed(&world, control));
    (try world.get(root, data.Mover)).state = .closing;
    try t.expect(!completed(&world, control));
    try world.destroy(root);
    try t.expect(completed(&world, control));
}

test "a lift rider centers below the landing and resumes its route at landing height" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 4);
    defer world.deinit();
    var slots: Slots = .{};
    const platform = try world.create(337, .{ data.Transform{ .position = .{ 0, 0, -98 } }, data.Body{ .mins = .{ 616, 1264, -144 }, .maxs = .{ 712, 1344, 96 } }, data.Mover{ .closed = @splat(0), .opened = .{ 0, 0, -98 }, .motion = .{}, .state = .open, .return_at = .{ .at_ms = 1000 } } });
    const slot = try slots.acquire(platform, null);
    const actor = try world.create(1, .{ data.Player{ .ground_entity = slot }, data.Transform{ .position = .{ 631, 1300, 22 } } });
    const goal: v.Vec3 = .{ 272, 1304, 120 };
    try t.expectEqual(@as(?v.Vec3, .{ 664, 1304, 22 }), try ridePoint(&world, &slots, actor, (try world.get(actor, data.Player)).ground_entity, goal));
    // Ordinary same-height traversal and non-riders remain unaffected.
    try t.expectEqual(@as(?v.Vec3, null), try ridePoint(&world, &slots, actor, (try world.get(actor, data.Player)).ground_entity, .{ 272, 1304, 22 }));
    (try world.get(actor, data.Player)).ground_entity = c.ENTITYNUM_WORLD;
    try t.expectEqual(@as(?v.Vec3, null), try ridePoint(&world, &slots, actor, (try world.get(actor, data.Player)).ground_entity, goal));
    (try world.get(actor, data.Player)).ground_entity = slot;
    (try world.get(platform, data.Transform)).position[2] = 0;
    (try world.get(actor, data.Transform)).position[2] = 120;
    const mover = try world.get(platform, data.Mover);
    mover.state = .closed;
    mover.return_at = .{};
    try t.expectEqual(@as(?v.Vec3, null), try ridePoint(&world, &slots, actor, (try world.get(actor, data.Player)).ground_entity, goal));
    // Reproduce the actual carrier at a stopped upper endpoint. Its capture
    // volume is below both lift endpoints; no descent is currently scheduled.
    const lower_goal: v.Vec3 = .{ 936, -48, -108 };
    try t.expectEqual(@as(?v.Vec3, null), try ridePoint(&world, &slots, actor, (try world.get(actor, data.Player)).ground_entity, lower_goal));
    mover.state = .opening;
    mover.motion.end = mover.opened;
    try t.expectEqual(@as(?v.Vec3, .{ 664, 1304, 120 }), try ridePoint(&world, &slots, actor, (try world.get(actor, data.Player)).ground_entity, lower_goal));
    mover.state = .closing;
    mover.motion.end = mover.closed;
    (try world.get(platform, data.Transform)).position[2] = -98;
    (try world.get(actor, data.Transform)).position[2] = 22;
    try t.expectEqual(@as(?v.Vec3, null), try ridePoint(&world, &slots, actor, (try world.get(actor, data.Player)).ground_entity, lower_goal));
}
