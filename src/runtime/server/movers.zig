// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const v = @import("../domain/vector.zig");
const prop = @import("properties.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const pusher = @import("pusher.zig");
const audio = @import("../domain/audio.zig");
const c = abi.c;
fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
/// The clipper widens every inline brush hull by one unit per side, so a committed
/// bmodel bound measures two units more than the authored brush on each axis.
/// Travel has to measure the authored brush: an authored `lip` names the distance
/// the brush stays proud of the wall, and the reference server state derives its
/// mover size by contracting the loaded model hull by the same amount on each axis
/// precisely so that door and button lips come out as authored. Carrying the
/// spread instead sinks shallow panels wholly behind the wall surface, which is
/// what made the wall buttons in Solitary look like they vanished when used.
fn authoredExtents(body: data.Body) v.Vec3 {
    const hull = v.subtract(body.maxs, body.mins);
    return .{ hull[0] - 2, hull[1] - 2, hull[2] - 2 };
}
/// Reference travel for a sliding brush: its authored extent along the movement
/// axis less the authored lip (DOOR.CPP: movedir * (DotProduct(|movedir|, size) - lip)).
fn travelDistance(direction: v.Vec3, size: v.Vec3, lip: f32) f32 {
    var distance: f32 = -lip;
    for (0..3) |axis| distance += @abs(direction[axis]) * size[axis];
    return distance;
}
fn directionFor(object: data.MapObject) !v.Vec3 {
    const yaw = try prop.number(object, "angle", 0);
    const angles = if (prop.text(object, "angles")) |text| try @import("map.zig").vector(text) else v.Vec3{ 0, yaw, 0 };
    return if (yaw == -1) .{ 0, 0, 1 } else if (yaw == -2) .{ 0, 0, -1 } else v.basis(angles).forward;
}
fn remapPoint(point: v.Vec3, old_closed: v.Vec3, old_opened: v.Vec3, closed: v.Vec3, opened: v.Vec3) v.Vec3 {
    const old_delta = v.subtract(old_opened, old_closed);
    const length = v.dot(old_delta, old_delta);
    const fraction = if (length > 0) v.dot(v.subtract(point, old_closed), old_delta) / length else 0;
    return v.add(point, v.add(v.subtract(closed, old_closed), v.scale(v.subtract(v.subtract(opened, closed), old_delta), fraction)));
}
/// Upgrade only the recognized spread-hull formula. Archives made after the
/// original fix lack a version too; their already-correct endpoints stay intact.
/// Remap mid-travel poses without changing state, deadlines or target delivery.
fn restoreTravel(object: data.MapObject, body: data.Body, mover: *data.Mover, transform: *data.Transform) !void {
    if (mover.travel_version != 0) return;
    defer mover.travel_version = 1;
    if (mover.angular) return;
    const button = eq(object.classname, "func_button");
    const lip = try prop.number(object, "lip", if (button) 4 else 8);
    const hull = v.subtract(body.maxs, body.mins);
    const old_closed = mover.closed;
    const old_opened = mover.opened;
    const delta = v.subtract(old_opened, old_closed);
    var closed = old_closed;
    var opened = old_opened;
    if (mover.platform) {
        if (prop.text(object, "height") != null or @abs(delta[2] - (hull[2] - lip)) > 0.01) return;
        closed[2] = opened[2] - (hull[2] - 2 - lip);
    } else {
        const direction = try directionFor(object);
        const old_distance = travelDistance(direction, hull, lip);
        if (@abs(v.length(delta) - @abs(old_distance)) > 0.01 or old_distance == 0) return;
        // The saved axis includes start-open reversal and parent rotation.
        const axis = v.scale(delta, 1 / old_distance);
        opened = v.add(closed, v.scale(axis, travelDistance(direction, authoredExtents(body), lip)));
    }
    transform.position = remapPoint(transform.position, old_closed, old_opened, closed, opened);
    mover.motion.base = remapPoint(mover.motion.base, old_closed, old_opened, closed, opened);
    mover.motion.end = remapPoint(mover.motion.end, old_closed, old_opened, closed, opened);
    mover.closed = closed;
    mover.opened = opened;
}
/// Pure staged admission, shared by active, resident and visited save worlds.
pub fn admit(world: *data.World) !void {
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Body, data.Mover, data.Transform }), 0, data.World.mask(.{ data.Mover, data.Transform }));
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.MapObject), view.read(data.Body), view.write(data.Mover), view.write(data.Transform)) |object, body, *mover, *transform| {
        try restoreTravel(object, body, mover, transform);
    };
}
/// Authored press/pop-back audio is registered while the map is admitted so the
/// first use cannot wait on a late sound configstring. Missing means silent.
fn authoredSound(object: data.MapObject, key: []const u8) !u16 {
    const path = prop.text(object, key) orelse return 0;
    if (path.len == 0) return 0;
    return @import("resources.zig").sound(path);
}
/// Motion audio is authored under one pair of keys for the door family and another for
/// platforms and trains; either name fills the corresponding slot.
fn authoredMotion(object: data.MapObject, door_key: []const u8, mover_key: []const u8) !u16 {
    const door = try authoredSound(object, door_key);
    if (door != 0) return door;
    return authoredSound(object, mover_key);
}
/// Authored loudness and attenuation distances for a mover's own audio. Movers without any
/// of the three keys keep the ordinary mixer defaults, and an unusable authored set is
/// discarded rather than reaching the client as malformed parameters.
fn authoredParameters(object: data.MapObject) !?audio.Parameters {
    const volume = try prop.number(object, "volume", -1);
    const minimum = try prop.number(object, "min", -1);
    const maximum = try prop.number(object, "max", -1);
    if (volume < 0 and minimum < 0 and maximum < 0) return null;
    const value: audio.Parameters = .{
        .volume = if (volume < 0) 1 else @min(1, volume),
        .minimum = if (minimum < 0) 256 else minimum,
        .maximum = if (maximum < 0) 648 else maximum,
    };
    return if (value.valid()) value else null;
}
/// Platforms always carry their motion sound, and any mover with the authored loop flag
/// does too; everything else plays its motion sound once per transition.
fn loopsWhileMoving(classname: []const u8, flags: u32, platform: bool) bool {
    return platform or flags & 128 != 0 or (eq(classname, "func_door_rotate") and flags & 2048 != 0);
}
fn bindSounds(object: data.MapObject, mover: *data.Mover) !void {
    const button = eq(object.classname, "func_button");
    mover.use_sound = if (button) try authoredSound(object, "sound_use") else 0;
    mover.return_sound = if (button) try authoredSound(object, "sound_return") else 0;
    mover.opening_sound = if (button) 0 else try authoredMotion(object, "sound_opening", "sound_up");
    mover.closing_sound = if (button) 0 else try authoredMotion(object, "sound_closing", "sound_down");
    mover.opened_sound = if (button) 0 else try authoredMotion(object, "sound_open_finish", "sound_top");
    mover.closed_sound = if (button) 0 else try authoredMotion(object, "sound_close_finish", "sound_bottom");
    mover.loop_sounds = loopsWhileMoving(object.classname, object.flags, mover.platform);
    mover.sound_parameters = if (button) null else try authoredParameters(object);
}
/// Resolve authored audio after the saved resource prefix has been installed.
/// Missing old fields cannot suppress the current map's immutable sound keys.
pub fn restoreSounds(world: *data.World) !void {
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Mover }), 0, data.World.mask(.{data.Mover}));
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.MapObject), view.write(data.Mover)) |object, *mover| {
        try bindSounds(object, mover);
        mover.loop_carrier = 0;
    };
}
/// Where a sliding mover's brush was authored, before spawn moved it to its
/// closed end (a platform rests low; a START_OPEN door swaps its ends);
/// null for a rotating door, whose position spawn leaves alone.
pub fn authoredPosition(object: data.MapObject, mover: data.Mover) ?v.Vec3 {
    if (mover.angular) return null;
    const swapped = object.flags & 1 != 0 and !eq(object.classname, "func_button");
    return if (mover.platform != swapped) mover.opened else mover.closed;
}
pub fn spawn(world: *data.World, slots: *const Slots, projections: []abi.EntityProjection) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const object = (try world.get(entity, data.MapObject)).*;
        const rotating = eq(object.classname, "func_door_rotate");
        const platform = eq(object.classname, "func_plat");
        const button = eq(object.classname, "func_button");
        if (!rotating and !platform and !button and !eq(object.classname, "func_door") and !eq(object.classname, "func_water")) continue;
        const transform = (try world.get(entity, data.Transform)).*;
        const body = (try world.get(entity, data.Body)).*;
        var closed = if (rotating) transform.angles else transform.position;
        var opened = closed;
        const lip = try prop.number(object, "lip", if (button) 4 else 8);
        const size = authoredExtents(body);
        if (rotating) {
            const axis: usize = if (object.flags & 128 != 0) 2 else if (object.flags & 256 != 0) 0 else 1;
            opened[axis] += (try prop.number(object, "distance", 90)) * @as(f32, if (object.flags & 2 != 0) -1 else 1);
        } else if (platform) {
            closed[2] -= try prop.number(object, "height", size[2] - lip);
        } else {
            const direction = try directionFor(object);
            opened = v.add(closed, v.scale(direction, travelDistance(direction, size, lip)));
        }
        if (object.flags & 1 != 0 and !button) std.mem.swap(v.Vec3, &closed, &opened);
        const speed = try prop.number(object, "speed", if (button) 40 else 100);
        var mover: data.Mover = .{ .closed = closed, .opened = opened, .travel_version = 1, .motion = .{ .base = closed, .end = closed, .curve = if (try prop.number(object, "boing", 0) != 0) .bounce else if (try prop.number(object, "accelerate", 0) != 0) .accelerate else .linear }, .angular = rotating, .platform = platform, .speed = if (speed > 0) speed else if (button) 40 else 100, .wait_ms = try prop.milliseconds(object, "wait", if (button) 1 else 3), .delay_ms = if (std.mem.startsWith(u8, object.classname, "func_door")) @max(0, try prop.milliseconds(object, "delay", 0)) else 0, .toggle = object.flags & (8 | 32) != 0, .return_both = object.flags & 64 != 0, .force = (try prop.number(object, "forcemove", 0) != 0) or (!rotating and object.flags & 512 != 0), .damage = @intFromFloat(try prop.number(object, "damage", try prop.number(object, "dmg", 2))), .group = try world.persistentId(entity) };
        try bindSounds(object, &mover);
        try world.put(entity, mover);
        const actual = try world.get(entity, data.Transform);
        if (rotating) actual.angles = closed else {
            actual.position = closed;
            actual.angles = @splat(0);
        }
        try publish(world, entity, projections);
    }
    // Stable, transitive grouping by explicit team or touching doors with equal targetname.
    var changed = true;
    while (changed) {
        changed = false;
        for (slots.occupants, 0..) |left, i| {
            const a = left orelse continue;
            const ma = world.get(a, data.Mover) catch continue;
            const oa = (try world.get(a, data.MapObject)).*;
            for (slots.occupants[i + 1 ..]) |right| {
                const b = right orelse continue;
                const mb = world.get(b, data.Mover) catch continue;
                if (ma.group == mb.group) continue;
                const ob = (try world.get(b, data.MapObject)).*;
                const team = prop.text(oa, "team") orelse "";
                var match = team.len > 0 and eq(team, prop.text(ob, "team") orelse "");
                if (!match and oa.flags & 4 == 0 and ob.flags & 4 == 0 and std.mem.startsWith(u8, oa.classname, "func_door") and std.mem.startsWith(u8, ob.classname, "func_door") and eq(oa.targetname, ob.targetname)) {
                    const pa = &projections[(try world.get(a, data.Binding)).slot];
                    const pb = &projections[(try world.get(b, data.Binding)).slot];
                    match = true;
                    for (0..3) |axis| if (pa.shared.absmin[axis] > pb.shared.absmax[axis] + 1 or pb.shared.absmin[axis] > pa.shared.absmax[axis] + 1) {
                        match = false;
                        break;
                    };
                }
                if (match) {
                    const group = @min(ma.group, mb.group);
                    ma.group = group;
                    mb.group = group;
                    changed = true;
                }
            }
        }
    }
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const mover = (try world.get(entity, data.Mover)).*;
    const transform = (try world.get(entity, data.Transform)).*;
    const projection = &projections[(try world.get(entity, data.Binding)).slot];
    projection.shared.currentOrigin = transform.position;
    projection.shared.currentAngles = transform.angles;
    const wire = @import("../engine/trajectory.zig");
    projection.state.pos = wire.stationary(transform.position);
    projection.state.apos = wire.stationary(transform.angles);
    if (mover.moving()) {
        if (mover.angular) projection.state.apos = wire.fromMotion(mover.motion) else projection.state.pos = wire.fromMotion(mover.motion);
    }
    // A looping motion sound never rides the brush itself: an inline brush is placed by its
    // own world coordinates, so its entity origin is nowhere near the panel. The loop lives
    // on a carrier offset to the brush's audible middle, kept by `finish`.
    projection.state.loopSound = 0;
    engine.link(projection);
}
fn start(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, group: u32, opened: bool, now: i64, delayed: bool) !void {
    var duration: i32 = 1;
    var queued: [ecs.max_entities]Queued = undefined;
    var queued_count: usize = 0;
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const mover = world.get(entity, data.Mover) catch continue;
        if (mover.group != group) continue;
        const transform = (try world.get(entity, data.Transform)).*;
        duration = @max(duration, try mover.duration(opened, if (mover.angular) transform.angles else transform.position));
    }
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const mover = world.get(entity, data.Mover) catch continue;
        if (mover.group != group) continue;
        const transform = (try world.get(entity, data.Transform)).*;
        mover.start(opened, if (mover.angular) transform.angles else transform.position, now, duration, delayed);
        try publish(world, entity, projections);
        // Sound entities claim slots, so starts are collected and emitted after this pass.
        if (!mover.loop_sounds) {
            queued[queued_count] = .{ .entity = entity, .index = if (opened) mover.opening_sound else mover.closing_sound, .parameters = mover.sound_parameters };
            queued_count += 1;
        }
    }
    for (queued[0..queued_count]) |sound| try emit(world, slots, projections, sound.entity, sound.index, now, sound.parameters);
}
/// Authored mover audio belongs to the brush the player acted on, which is not
/// necessarily the group master that carries the transition.
/// A brush entity's own origin is model-local, so authored mover audio must travel
/// from the audible centre of its committed world bounds instead.
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, index: u16, now: i64, parameters: ?audio.Parameters) !void {
    if (index == 0) return;
    const slot = (try world.get(entity, data.Binding)).slot;
    const bounds = projections[slot].shared;
    const point = v.scale(v.add(bounds.absmin, bounds.absmax), 0.5);
    try @import("events.zig").configuredSound(world, slots, projections, @import("resources.zig").soundName(index), point, slot, c.CHAN_AUTO, now, parameters);
}
/// Audible middle of a travelling brush together with the trajectory of that middle. The
/// offset between the committed world bounds and the entity position is the brush's own
/// centre, which stays constant for the whole travel, so shifting the brush trajectory by it
/// keeps the loop locked to the panel as it slides.
fn audioMotion(world: *data.World, entity: ecs.Entity, mover: *const data.Mover, projections: []abi.EntityProjection) !struct { point: v.Vec3, path: abi.c.trajectory_t } {
    const bounds = projections[(try world.get(entity, data.Binding)).slot].shared;
    const centre = v.scale(v.add(bounds.absmin, bounds.absmax), 0.5);
    var path = @import("../engine/trajectory.zig").fromMotion(mover.motion);
    path.trBase = v.add(path.trBase, v.subtract(centre, (try world.get(entity, data.Transform)).position));
    return .{ .point = centre, .path = path };
}
/// One travelling brush whose looping motion sound needs a carrier created for it.
const Carrier = struct { entity: ecs.Entity, index: u16 };
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, activator: u32, now: i64) !void {
    const original = world.get(entity, data.Mover) catch return;
    const master = world.find(original.group) orelse return error.MissingMoverMaster;
    const mover = try world.get(master, data.Mover);
    const object = (try world.get(master, data.MapObject)).*;
    if (!@import("keys.zig").allows(world, object, activator)) return;
    const pressed = original.use_sound;
    if (try mover.use(now, activator)) |opened| {
        try start(world, slots, projections, mover.group, opened, now, true);
        if (opened) try emit(world, slots, projections, entity, pressed, now, original.sound_parameters);
    }
}
/// Audio starts are collected during a mover pass and emitted afterwards, because a
/// sound event claims its own entity slot and the pass iterates the slot occupants.
const Queued = struct { entity: ecs.Entity, index: u16, parameters: ?audio.Parameters };
pub const Arrivals = struct { entities: [ecs.max_entities]ecs.Entity = undefined, count: usize = 0 };
pub fn prepare(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const mover = world.get(entity, data.Mover) catch continue;
        if (mover.group != try world.persistentId(entity) or !mover.return_at.due(now)) continue;
        const returning = mover.return_sound;
        const pop_back = mover.state != .closed;
        try start(world, slots, projections, mover.group, mover.state == .closed, now, false);
        if (pop_back) try emit(world, slots, projections, entity, returning, now, mover.sound_parameters);
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64, elapsed: u32) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const master = world.get(entity, data.Mover) catch continue;
        if (master.group != try world.persistentId(entity) or @import("attachments.zig").attached(world, entity)) continue;
        var moves: [ecs.max_entities]pusher.Move = undefined;
        var count: usize = 0;
        for (slots.occupants) |part_occupant| {
            const part = part_occupant orelse continue;
            const mover = world.get(part, data.Mover) catch continue;
            if (mover.group != master.group) continue;
            var transform = (try world.get(part, data.Transform)).*;
            if (mover.moving()) {
                if (mover.angular) transform.angles = mover.motion.sample(now) else transform.position = mover.motion.sample(now);
            }
            moves[count] = .{ .entity = part, .destination = transform };
            count += 1;
        }
        if (try pusher.push(world, slots, projections, moves[0..count], now, elapsed)) |blocker| {
            // Daikatana's button_blocked does nothing: a pressed button neither
            // hurts nor gives way; it waits until whatever holds it has moved
            // (e1m3b's worker typing at the console a button is set in).
            if (eq((try world.get(entity, data.MapObject)).classname, "func_button")) continue;
            if (engine.integer("developer") >= 2) {
                var text: [160]u8 = undefined;
                const blocker_pose = world.get(blocker, data.Transform) catch null;
                const at: data.Vec3 = if (blocker_pose) |pose| pose.position else @splat(0);
                engine.print(std.fmt.bufPrintZ(&text, "dk3 zig mover blocked: id={d} blocker={d} at={d:.0},{d:.0},{d:.0} state={s}\n", .{ try world.persistentId(entity), try world.persistentId(blocker), at[0], at[1], at[2], @tagName(master.state) }) catch "");
            }
            _ = try @import("damage.zig").apply(world, blocker, master.damage, now, .{});
            if (!master.force and master.moving()) try start(world, slots, projections, master.group, master.state == .closing, now, false);
        }
    }
}
pub fn finish(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !Arrivals {
    var arrivals: Arrivals = .{};
    var settling: [ecs.max_entities]Queued = undefined;
    var settling_count: usize = 0;
    var wanted: [ecs.max_entities]Carrier = undefined;
    var wanted_count: usize = 0;
    var retired: [ecs.max_entities]u32 = undefined;
    var retired_count: usize = 0;
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        const mover = world.get(entity, data.Mover) catch continue;
        if (mover.moving() and mover.motion.finished(now)) {
            const arrival = if (mover.state == .opening) mover.opened_sound else mover.closed_sound;
            if (try mover.reached(now, mover.group == try world.persistentId(entity))) {
                arrivals.entities[arrivals.count] = entity;
                arrivals.count += 1;
            }
            if (arrival != 0) {
                settling[settling_count] = .{ .entity = entity, .index = arrival, .parameters = mover.sound_parameters };
                settling_count += 1;
            }
        }
        const looping: u16 = if (mover.moving() and mover.loop_sounds) (if (mover.state == .opening) mover.opening_sound else mover.closing_sound) else 0;
        const held = if (mover.loop_carrier == 0) null else world.find(mover.loop_carrier);
        const live = if (held) |found| world.alive(found) else false;
        if (looping == 0 or !live) {
            if (mover.loop_carrier != 0) {
                retired[retired_count] = mover.loop_carrier;
                retired_count += 1;
                mover.loop_carrier = 0;
            }
            if (looping != 0) {
                wanted[wanted_count] = .{ .entity = entity, .index = looping };
                wanted_count += 1;
            }
        } else {
            const motion = try audioMotion(world, entity, mover, projections);
            try @import("events.zig").stepLoop(world, projections, mover.loop_carrier, looping, motion.path, motion.point, mover.sound_parameters, now);
        }
        try publish(world, entity, projections);
    }
    // Carriers are withdrawn before the arrival sound starts, then new ones take their slots,
    // because a created or destroyed carrier claims a slot and this pass walks the occupants.
    for (retired[0..retired_count]) |carrier| try @import("events.zig").stopLoop(world, slots, projections, carrier);
    for (wanted[0..wanted_count]) |request| {
        const mover = try world.get(request.entity, data.Mover);
        const motion = try audioMotion(world, request.entity, mover, projections);
        mover.loop_carrier = try @import("events.zig").startLoop(world, slots, projections, @import("resources.zig").soundName(request.index), motion.path, motion.point, (try world.get(request.entity, data.Binding)).slot, mover.sound_parameters, now);
    }
    // Emitted after publishing so a carried motion sound is already withdrawn when the
    // arrival sound starts on the same tick.
    for (settling[0..settling_count]) |sound| try emit(world, slots, projections, sound.entity, sound.index, now, sound.parameters);
    return arrivals;
}

test "old saved button travel is repaired without replaying targets or resetting dwell" {
    const t = std.testing;
    const object: data.MapObject = .{ .classname = "func_button", .properties = &.{ .{ .key = "angle", .value = "180" }, .{ .key = "lip", .value = "3" } } };
    const body: data.Body = .{ .mins = .{ -1001, -9, -9 }, .maxs = .{ -995, 9, 9 } };
    var mover: data.Mover = .{ .closed = @splat(0), .opened = .{ -3, 0, 0 }, .motion = .{ .base = .{ -1.5, 0, 0 }, .end = .{ -3, 0, 0 }, .start_ms = 1000, .duration_ms = 150 }, .state = .opening, .return_at = .{ .at_ms = 3000 }, .owner = 433, .group = 75 };
    var pose: data.Transform = .{ .position = .{ -2.25, 0, 0 } };
    try restoreTravel(object, body, &mover, &pose);
    try t.expectApproxEqAbs(@as(f32, -1), mover.opened[0], 0.001);
    try t.expectApproxEqAbs(@as(f32, -0.75), pose.position[0], 0.001);
    try t.expectApproxEqAbs(@as(f32, -0.5), mover.motion.base[0], 0.001);
    try t.expectEqual(@as(i64, 1000), mover.motion.start_ms);
    try t.expectEqual(@as(i32, 150), mover.motion.duration_ms);
    try t.expectEqual(@as(?i64, 3000), mover.return_at.at_ms);
    try t.expectEqual(@as(u32, 433), mover.owner);
    try t.expectEqual(@import("../domain/movers.zig").State.opening, mover.state);
    const once = mover;
    try restoreTravel(object, body, &mover, &pose);
    try t.expectEqualDeep(once, mover);
    // A corrected archive from sequence 323 has no marker either.
    mover.travel_version = 0;
    try restoreTravel(object, body, &mover, &pose);
    try t.expectEqualDeep(once, mover);
}

test "saved flush panel returns to its face while keeping the used latch" {
    const t = std.testing;
    const object: data.MapObject = .{ .classname = "func_button" };
    const body: data.Body = .{ .mins = .{ 0, 0, 0 }, .maxs = .{ 6, 18, 18 } };
    var mover: data.Mover = .{ .closed = @splat(0), .opened = .{ 2, 0, 0 }, .motion = .{ .base = @splat(0), .end = .{ 2, 0, 0 } }, .state = .open, .wait_ms = -1000 };
    var pose: data.Transform = .{ .position = .{ 2, 0, 0 } };
    try restoreTravel(object, body, &mover, &pose);
    try t.expectEqual(v.Vec3{ 0, 0, 0 }, pose.position);
    try t.expectEqual(v.Vec3{ 0, 0, 0 }, mover.opened);
    try t.expectEqual(@import("../domain/movers.zig").State.open, mover.state);
    try t.expectEqual(@as(i32, -1000), mover.wait_ms);
}

test "shallow button travel keeps the authored lip proud of the wall" {
    // e1m3a button 27: authored brush 4 x 16 x 16 with lip 3, pressing along -X.
    const hull: data.Body = .{ .mins = .{ 1327, -225, -113 }, .maxs = .{ 1333, -207, -95 } };
    try std.testing.expectEqual(v.Vec3{ 4, 16, 16 }, authoredExtents(hull));
    try std.testing.expectEqual(@as(f32, 1), travelDistance(.{ -1, 0, 0 }, authoredExtents(hull), 3));
}
test "flush buttons with lip equal to the authored thickness do not move at all" {
    // e1m3a camera1 button: authored 4 thick along X with the default lip of 4.
    const hull: data.Body = .{ .mins = .{ 2219, -309, -497 }, .maxs = .{ 2225, -275, -471 } };
    try std.testing.expectEqual(@as(f32, 0), travelDistance(.{ 1, 0, 0 }, authoredExtents(hull), 4));
}
test "sliding brush keeps its audio at the middle of its travel" {
    // e1m3a door 259: authored brush 144 x 76 x 128, opening upward along +Z with the
    // default lip of 8, so its authored travel is 126 - 8 = 118 units.
    const hull: data.Body = .{ .mins = .{ 760, -284, -256 }, .maxs = .{ 904, -208, -128 } };
    const size = authoredExtents(hull);
    const travel = travelDistance(.{ 0, 0, 1 }, size, 8);
    const mover: data.Mover = .{ .closed = .{ 0, 0, 0 }, .opened = v.scale(.{ 0, 0, 1 }, travel), .motion = .{ .base = .{ 0, 0, 0 }, .end = v.scale(.{ 0, 0, 1 }, travel), .duration_ms = 1180 } };
    const wire = @import("../engine/trajectory.zig");
    // A compiled inline brush carries its own world coordinates, so the entity position sits
    // at the map origin while the committed bounds hold the middle of the brush.
    const centre = v.scale(v.add(v.subtract(hull.maxs, .{ 1, 1, 1 }), v.add(hull.mins, .{ 1, 1, 1 })), 0.5);
    try std.testing.expectEqual(v.Vec3{ 832, -246, -192 }, centre);
    var path = wire.fromMotion(mover.motion);
    path.trBase = v.add(path.trBase, centre);
    try std.testing.expectEqual(centre, wire.evaluate(path, 0));
    try std.testing.expectApproxEqAbs(@as(f32, -192) + travel / 2, wire.evaluate(path, @divTrunc(mover.motion.duration_ms, 2))[2], 0.5);
    // The carrier rides a stopping trajectory, so it never drifts past the settled brush.
    try std.testing.expectApproxEqAbs(@as(f32, -192) + travel, wire.evaluate(path, mover.motion.duration_ms + 500)[2], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 832), wire.evaluate(path, mover.motion.duration_ms + 500)[0], 0.001);
}
