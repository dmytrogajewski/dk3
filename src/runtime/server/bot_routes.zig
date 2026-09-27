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
pub const Control = struct { id: u32, obstacle: u32, point: v.Vec3, action: enum { use, touch, shoot } };
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
    const forwards = std.mem.eql(u8, object.classname, "func_button") or std.mem.eql(u8, object.classname, "trigger_relay") or std.mem.eql(u8, object.classname, "trigger_multiple") or std.mem.eql(u8, object.classname, "trigger_once") or std.mem.eql(u8, object.classname, "trigger_counter");
    if (!forwards) return false;
    if (world.get(source, data.Trigger) catch null) |trigger| if (now < trigger.ready_ms or (trigger.limit > 0 and trigger.uses >= trigger.limit)) return false;
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, target| {
        if (!linked(object, target.targetname)) continue;
        if (!@import("keys.zig").allows(world, target, actor)) continue;
        if (try chain(world, entity, obstacle, actor, now, visited, depth + 1)) return true;
    };
    return false;
}
pub fn seek(world: *data.World, slots: *Slots, projections: []const @import("../engine/abi.zig").EntityProjection, actor: ecs.Entity, toward: v.Vec3, service: nav.Service, now: i64, avoided: u32) !?Control {
    const pose = (try world.get(actor, data.Transform)).*;
    const body = (try world.get(actor, data.Body)).*;
    const slot = (try world.get(actor, data.Binding)).slot;
    var direction = v.subtract(toward, pose.position);
    direction[2] = 0;
    direction = v.normalize(direction);
    const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, 80)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID });
    if (hit.fraction == 1 or hit.entity >= slots.occupants.len) return null;
    var obstacle = slots.occupants[hit.entity] orelse return null;
    const mover = world.get(obstacle, data.Mover) catch return null;
    if (mover.moving()) return null;
    if (world.find(mover.group)) |master| obstacle = master;
    const obstacle_id = try world.persistentId(obstacle);
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
                action = .touch;
            } else if (entity.index == obstacle.index and object.targetname.len != 0) continue;
        } else if ((std.mem.eql(u8, object.classname, "trigger_multiple") or std.mem.eql(u8, object.classname, "trigger_once")) and object.flags & 1 == 0 and projections[binding.slot].shared.contents & c.CONTENTS_TRIGGER != 0) {
            action = .touch;
        } else continue;
        var visited: [64]u32 = undefined;
        if (!try chain(world, entity, obstacle, id, now, &visited, 0)) continue;
        const point = try approach(world, entity, actor, action, service, projections) orelse continue;
        const distance = v.length(v.subtract(point, pose.position));
        if (distance >= nearest) continue;
        nearest = distance;
        result = .{ .id = control_id, .obstacle = obstacle_id, .point = point, .action = action };
    };
    return result;
}
fn approach(world: *data.World, target: ecs.Entity, actor: ecs.Entity, action: @FieldType(Control, "action"), service: nav.Service, projections: []const @import("../engine/abi.zig").EntityProjection) !?v.Vec3 {
    const pose = (try world.get(actor, data.Transform)).*;
    const body = (try world.get(actor, data.Body)).*;
    const player = (try world.get(actor, data.Player)).*;
    const slot = (try world.get(actor, data.Binding)).slot;
    const target_slot = (try world.get(target, data.Binding)).slot;
    const box = projections[target_slot].shared;
    const middle = v.scale(v.add(box.absmin, box.absmax), 0.5);
    const margin: f32 = if (action == .shoot) 96 else if (action == .touch) 2 else 32;
    var points: [5]v.Vec3 = @splat(middle);
    points[1][0] = box.absmin[0] - body.maxs[0] - margin;
    points[2][0] = box.absmax[0] - body.mins[0] + margin;
    points[3][1] = box.absmin[1] - body.maxs[1] - margin;
    points[4][1] = box.absmax[1] - body.mins[1] + margin;
    if (action != .touch) points[0] = pose.position;
    var chosen: ?v.Vec3 = null;
    var distance: f32 = std.math.inf(f32);
    for (points) |candidate| {
        var top = candidate;
        top[2] = @max(pose.position[2], middle[2]) + 48;
        const floor = try engine.collisionService().trace(.{ .start = top, .end = v.add(top, .{ 0, 0, -256 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_PLAYERSOLID });
        if (floor.start_solid or floor.all_solid or floor.fraction == 1 or floor.normal[2] < 0.7) continue;
        if (try engine.collisionService().contents(v.add(floor.end, .{ 0, 0, body.mins[2] + 1 }), slot) & (c.CONTENTS_LAVA | c.CONTENTS_SLIME) != 0) continue;
        const eye = v.add(floor.end, .{ 0, 0, player.view_height });
        const sight = try engine.collisionService().trace(.{ .start = eye, .end = middle, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
        if (action != .touch and sight.entity != target_slot) continue;
        if (action == .use and v.length(v.subtract(sight.end, eye)) > 88) continue;
        if (try service.next(.{ .position = pose.position, .destination = floor.end, .slot = slot, .player = true }) == null) continue;
        const length = v.length(v.subtract(pose.position, floor.end));
        if (length < distance) {
            chosen = floor.end;
            distance = length;
        }
    }
    return chosen;
}
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
        if (try engine.collisionService().contents(v.add(floor.end, .{ 0, 0, body.mins[2] + 1 }), slot) & (c.CONTENTS_LAVA | c.CONTENTS_SLIME) != 0) continue;
        return floor.end;
    }
    return null;
}

test "route controls follow authored relay chains without bypassing locks or scripts" {
    const t = std.testing;
    var world = try data.World.init(t.allocator);
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
