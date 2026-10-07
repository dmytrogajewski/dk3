// SPDX-License-Identifier: GPL-2.0-or-later
//! Parent identity and pose composition; no engine collision calls here.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const pose = @import("../domain/poses.zig");
const v = @import("../domain/vector.zig");
const prop = @import("properties.zig");
const names = @import("names.zig");
pub fn spawn(world: *data.World, projections: []@import("../engine/abi.zig").EntityProjection) !void {
    var entities: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (prop.nonempty(object, "parenttarget")) {
            entities[count] = entity;
            count += 1;
        };
    }
    for (entities[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        const matches = try names.named(world, prop.text(object, "parenttarget").?);
        const own_id = try world.persistentId(entity);
        var parent_id: ?u32 = null;
        for (matches.ids[0..matches.count]) |id| {
            if (id == own_id) continue;
            const parent = world.find(id).?;
            const parent_object = (try world.get(parent, data.MapObject)).*;
            if (!std.mem.startsWith(u8, parent_object.classname, "func_")) continue;
            _ = world.get(parent, data.Binding) catch continue;
            parent_id = id;
            break;
        }
        const id = parent_id orelse return error.InvalidAttachmentParent;
        const parent = world.find(id).?;
        const offset = v.add((try world.get(entity, data.Transform)).position, v.scale(authored(world, parent), -1));
        try world.put(entity, data.Attachment{ .parent_id = id, .offset = offset });
    }
    for (entities[0..count]) |entity| {
        var ancestor = entity;
        for (0..ecs.max_entities) |_| {
            const attachment = world.get(ancestor, data.Attachment) catch break;
            ancestor = world.find(attachment.parent_id) orelse break;
            if (ancestor.index == entity.index and ancestor.generation == entity.generation) return error.CyclicAttachment;
        } else return error.CyclicAttachment;
    }
    // A parent that spawn already moved off its authored place (a START_OPEN
    // door resting at its other end, a platform resting low) carries what
    // rides on it there too, as if it had moved: e1m4a's console keys sit on
    // keypads that start slid into the desk.
    var carried: [ecs.max_entities]u32 = undefined;
    var carried_count: usize = 0;
    for (entities[0..count]) |entity| {
        const attachment = world.get(entity, data.Attachment) catch continue;
        if (std.mem.indexOfScalar(u32, carried[0..carried_count], attachment.parent_id) != null) continue;
        carried[carried_count] = attachment.parent_id;
        carried_count += 1;
        const parent = world.find(attachment.parent_id) orelse continue;
        if (world.get(parent, data.Attachment)) |_| continue else |_| {}
        const assembly = try carry(world, parent) orelse continue;
        try @import("pusher.zig").publishAssembly(world, projections, &assembly);
    }
}
/// Move what rides on `parent` from where the map authored the parent to
/// where it rests now; null when spawn left it in place.
fn carry(world: *data.World, parent: ecs.Entity) !?Assembly {
    const current = (try world.get(parent, data.Transform)).*;
    const origin = authored(world, parent);
    if (v.length(v.subtract(origin, current.position)) < 0.01) return null;
    (try world.get(parent, data.Transform)).position = origin;
    var assembly = try prepare(world, &.{.{ .entity = parent, .destination = current }}, 0, false);
    try assembly.commit(world);
    return assembly;
}
/// Saves written before spawn carried riders of displaced parents hold those
/// riders where the parent was authored, not where it rests (e1m4a's console
/// keys out in front of the desk). Put each rider of a sliding mover back
/// where the map places it relative to its parent; consistent saves stay.
pub fn reconcile(world: *data.World) !void {
    var entities: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{ data.Attachment, data.Transform, data.MapObject }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            entities[count] = entity;
            count += 1;
        };
    }
    for (entities[0..count]) |entity| {
        const attachment = try world.get(entity, data.Attachment);
        const object = (try world.get(entity, data.MapObject)).*;
        // Only what the map rides on its parent; a charge stuck on a door
        // in play has no authored place to go back to.
        if (!prop.nonempty(object, "parenttarget")) continue;
        const parent = world.find(attachment.parent_id) orelse continue;
        const parent_mover = (world.get(parent, data.Mover) catch continue).*;
        if (parent_mover.angular) continue;
        const parent_object = (world.get(parent, data.MapObject) catch continue).*;
        const parent_position = (world.get(parent, data.Transform) catch continue).position;
        const own_mover = world.get(entity, data.Mover) catch null;
        if (own_mover) |mover| if (mover.angular) continue;
        const rest = if (own_mover) |mover| mover.closed else (world.get(entity, data.Transform) catch continue).position;
        const shift = v.subtract(v.subtract(parent_position, try mapOrigin(parent_object)), v.subtract(rest, try mapOrigin(object)));
        attachment.offset = v.subtract(try mapOrigin(object), try mapOrigin(parent_object));
        if (v.length(shift) < 0.5) continue;
        const transform = world.get(entity, data.Transform) catch continue;
        transform.position = v.add(transform.position, shift);
        if (own_mover) |mover| {
            mover.closed = v.add(mover.closed, shift);
            mover.opened = v.add(mover.opened, shift);
            mover.motion.base = v.add(mover.motion.base, shift);
            mover.motion.end = v.add(mover.motion.end, shift);
        }
    }
}
fn mapOrigin(object: data.MapObject) !v.Vec3 {
    const text = prop.text(object, "origin") orelse return @splat(0);
    var result: v.Vec3 = @splat(0);
    var fields = std.mem.tokenizeScalar(u8, text, ' ');
    for (&result) |*axis| axis.* = std.fmt.parseFloat(f32, fields.next() orelse break) catch return @splat(0);
    return result;
}
/// Where a part was authored in the map: a sliding mover's brush before spawn
/// moved it to its closed end; anything else where it stands.
fn authored(world: *data.World, entity: ecs.Entity) v.Vec3 {
    const position = (world.get(entity, data.Transform) catch unreachable).position;
    const mover = (world.get(entity, data.Mover) catch return position).*;
    const object = (world.get(entity, data.MapObject) catch return position).*;
    return @import("movers.zig").authoredPosition(object, mover) orelse position;
}
pub fn attached(world: *data.World, entity: ecs.Entity) bool {
    const attachment = world.get(entity, data.Attachment) catch return false;
    return world.find(attachment.parent_id) != null;
}
pub const Move = struct { entity: ecs.Entity, destination: data.Transform };
pub const Part = struct { entity: ecs.Entity, id: u32, before: data.Transform, after: data.Transform, parent: ?usize = null, resolved: enum { fresh, visiting, complete } = .fresh };
pub const Assembly = struct {
    parts: [ecs.max_entities]Part = undefined,
    count: usize = 0,
    pub fn find(self: *const Assembly, id: u32) ?usize {
        for (self.parts[0..self.count], 0..) |part, i| if (part.id == id) return i;
        return null;
    }
    fn resolve(self: *Assembly, index: usize) !void {
        const part = &self.parts[index];
        if (part.resolved == .complete) return;
        if (part.resolved == .visiting) return error.CyclicAttachment;
        part.resolved = .visiting;
        if (part.parent) |parent_index| {
            try self.resolve(parent_index);
            const parent = self.parts[parent_index];
            part.after = .{ .position = pose.point(part.after.position, parent.before, parent.after), .angles = pose.orientation(part.after.angles, parent.before.angles, parent.after.angles) };
        }
        part.resolved = .complete;
    }
    pub fn commit(self: *Assembly, world: *data.World) !void {
        for (self.parts[0..self.count]) |part| {
            (try world.get(part.entity, data.Transform)).* = part.after;
            if (part.parent) |index| {
                const parent = self.parts[index];
                if (world.get(part.entity, data.Mover)) |mover| {
                    if (mover.angular) {
                        mover.closed = pose.orientation(mover.closed, parent.before.angles, parent.after.angles);
                        mover.opened = pose.orientation(mover.opened, parent.before.angles, parent.after.angles);
                        mover.motion.base = pose.orientation(mover.motion.base, parent.before.angles, parent.after.angles);
                        mover.motion.end = pose.orientation(mover.motion.end, parent.before.angles, parent.after.angles);
                    } else {
                        mover.closed = pose.point(mover.closed, parent.before, parent.after);
                        mover.opened = pose.point(mover.opened, parent.before, parent.after);
                        mover.motion.base = pose.point(mover.motion.base, parent.before, parent.after);
                        mover.motion.end = pose.point(mover.motion.end, parent.before, parent.after);
                    }
                } else |_| {}
                if (world.get(part.entity, data.Secret)) |secret| {
                    secret.closed = pose.point(secret.closed, parent.before, parent.after);
                    secret.first = pose.point(secret.first, parent.before, parent.after);
                    secret.opened = pose.point(secret.opened, parent.before, parent.after);
                    secret.motion.base = pose.point(secret.motion.base, parent.before, parent.after);
                    secret.motion.end = pose.point(secret.motion.end, parent.before, parent.after);
                } else |_| {}
                if (world.get(part.entity, data.Rotation)) |rotation| {
                    rotation.base = pose.orientation(rotation.base, parent.before.angles, parent.after.angles);
                    rotation.rate = pose.rotate(rotation.rate, parent.before.angles, parent.after.angles);
                } else |_| {}
                if (world.get(part.entity, data.Train)) |train| {
                    train.position.base = pose.point(train.position.base, parent.before, parent.after);
                    train.position.end = pose.point(train.position.end, parent.before, parent.after);
                    train.angles.base = pose.orientation(train.angles.base, parent.before.angles, parent.after.angles);
                    train.angles.end = pose.orientation(train.angles.end, parent.before.angles, parent.after.angles);
                } else |_| {}
            }
        }
    }
    pub fn delay(self: *const Assembly, world: *data.World, elapsed: u32) !void {
        for (self.parts[0..self.count]) |part| {
            if (world.get(part.entity, data.Mover)) |mover| mover.motion.start_ms += elapsed else |_| {}
            if (world.get(part.entity, data.Rotation)) |rotation| rotation.started_ms += elapsed else |_| {}
            if (world.get(part.entity, data.Secret)) |secret| secret.motion.start_ms += elapsed else |_| {}
            if (world.get(part.entity, data.Train)) |train| {
                train.position.start_ms += elapsed;
                train.angles.start_ms += elapsed;
            } else |_| {}
        }
    }
};
pub fn prepare(world: *data.World, moves: []const Move, now: i64, sample_children: bool) !Assembly {
    var result: Assembly = .{};
    for (moves) |move| {
        const id = try world.persistentId(move.entity);
        if (result.find(id) != null) return error.DuplicateAssemblyPart;
        if (result.count == result.parts.len) return error.AssemblyCapacity;
        result.parts[result.count] = .{ .entity = move.entity, .id = id, .before = (try world.get(move.entity, data.Transform)).*, .after = move.destination };
        result.count += 1;
    }
    var added = true;
    while (added) {
        added = false;
        var query = world.queryAccess(data.World.mask(.{ data.Attachment, data.Transform }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.Attachment), view.read(data.Transform)) |entity, attachment, transform| {
            const parent = result.find(attachment.parent_id) orelse continue;
            const id = try world.persistentId(entity);
            if (result.find(id) != null) continue;
            if (result.count == result.parts.len) return error.AssemblyCapacity;
            var destination = transform;
            if (sample_children) {
                if (world.get(entity, data.Mover)) |mover| {
                    if (mover.moving()) {
                        if (mover.angular) destination.angles = mover.motion.sample(now) else destination.position = mover.motion.sample(now);
                    }
                } else |_| {}
                if (world.get(entity, data.Secret)) |secret| {
                    if (secret.moving()) destination.position = secret.motion.sample(now);
                } else |_| {}
                if (world.get(entity, data.Rotation)) |rotation| destination.angles = rotation.sample(now) else |_| {}
                if (world.get(entity, data.Train)) |train| {
                    if (train.phase == .moving) destination = .{ .position = train.position.sample(now), .angles = train.angles.sample(now) };
                } else |_| {}
            }
            result.parts[result.count] = .{ .entity = entity, .id = id, .before = transform, .after = destination, .parent = parent };
            result.count += 1;
            added = true;
        };
    }
    for (result.parts[0..result.count]) |*part| {
        if (world.get(part.entity, data.Attachment)) |attachment| part.parent = result.find(attachment.parent_id) else |_| {}
    }
    for (0..result.count) |index| try result.resolve(index);
    return result;
}

test "train teleport carries nested attachments and rebases child door endpoints" {
    var world = data.World.init(std.testing.allocator, 16);
    defer world.deinit();
    const parent = try world.create(10, .{data.Transform{}});
    const child = try world.create(11, .{ data.Transform{ .position = .{ 20, 0, 0 } }, data.Attachment{ .parent_id = 10, .offset = .{ 20, 0, 0 } }, data.Mover{ .closed = .{ 20, 0, 0 }, .opened = .{ 20, 0, 100 }, .motion = .{ .base = .{ 20, 0, 0 }, .end = .{ 20, 0, 100 } }, .group = 11 } });
    const rack = try world.create(12, .{ data.Transform{ .position = .{ 25, 0, 0 } }, data.Attachment{ .parent_id = 11, .offset = .{ 5, 0, 0 } } });
    var assembly = try prepare(&world, &.{.{ .entity = parent, .destination = .{ .position = .{ 100, 200, 300 } } }}, 1000, false);
    try std.testing.expectEqual(@as(usize, 3), assembly.count);
    // Preparation alone must not alter authoritative state (collision may reject it).
    try std.testing.expectEqual(data.Vec3{ 25, 0, 0 }, (try world.get(rack, data.Transform)).position);
    try assembly.commit(&world);
    try std.testing.expectEqual(data.Vec3{ 125, 200, 300 }, (try world.get(rack, data.Transform)).position);
    try std.testing.expectEqual(data.Vec3{ 120, 200, 400 }, (try world.get(child, data.Mover)).opened);
}
test "attachment cycles are rejected before pose publication" {
    var world = data.World.init(std.testing.allocator, 16);
    defer world.deinit();
    const parent = try world.create(1, .{ data.Transform{}, data.Attachment{ .parent_id = 2, .offset = @splat(0) } });
    _ = try world.create(2, .{ data.Transform{}, data.Attachment{ .parent_id = 1, .offset = @splat(0) } });
    try std.testing.expectError(error.CyclicAttachment, prepare(&world, &.{.{ .entity = parent, .destination = .{} }}, 0, false));
}

test "attached rotating child advances inside the parent collision proposal" {
    var world = data.World.init(std.testing.allocator, 16);
    defer world.deinit();
    const parent = try world.create(1, .{data.Transform{}});
    const child = try world.create(2, .{ data.Transform{ .position = .{ 10, 0, 0 } }, data.Attachment{ .parent_id = 1, .offset = .{ 10, 0, 0 } }, data.Rotation{ .base = @splat(0), .rate = .{ 0, 90, 0 }, .active = true } });
    var assembly = try prepare(&world, &.{.{ .entity = parent, .destination = .{ .position = .{ 0, 0, 100 } } }}, 1000, true);
    try std.testing.expectEqual(data.Vec3{ 0, 90, 0 }, assembly.parts[assembly.find(2).?].after.angles);
    try std.testing.expectEqual(data.Vec3{ 10, 0, 100 }, assembly.parts[assembly.find(2).?].after.position);
    try assembly.delay(&world, 50);
    try std.testing.expectEqual(@as(i64, 50), (try world.get(child, data.Rotation)).started_ms);
    try std.testing.expectEqual(data.Vec3{ 10, 0, 0 }, (try world.get(child, data.Transform)).position);
}

test "keys on a keypad that starts slid into its desk ride in and out with it" {
    var world = data.World.init(std.testing.allocator, 16);
    defer world.deinit();
    // A START_OPEN keypad (e1m4a's console): authored out at y = 2, resting
    // 24 further into the desk until its trigger slides it out again.
    const keypad = try world.create(20, .{ data.Transform{ .position = .{ 0, 26, 0 } }, data.MapObject{ .classname = "func_door", .targetname = "lameass", .flags = 1 }, data.Mover{ .closed = .{ 0, 26, 0 }, .opened = .{ 0, 2, 0 }, .motion = .{ .base = .{ 0, 26, 0 }, .end = .{ 0, 26, 0 } }, .group = 20 } });
    const key = try world.create(21, .{ data.Transform{}, data.MapObject{ .classname = "func_button" }, data.Attachment{ .parent_id = 20, .offset = .{ 0, -2, 0 } }, data.Mover{ .closed = @splat(0), .opened = .{ 0, 10, 0 }, .motion = .{ .base = @splat(0), .end = @splat(0) }, .group = 21 } });
    try std.testing.expectEqual(data.Vec3{ 0, 2, 0 }, authored(&world, keypad));
    _ = (try carry(&world, keypad)).?;
    try std.testing.expectEqual(data.Vec3{ 0, 26, 0 }, (try world.get(keypad, data.Transform)).position);
    try std.testing.expectEqual(data.Vec3{ 0, 24, 0 }, (try world.get(key, data.Transform)).position);
    try std.testing.expectEqual(data.Vec3{ 0, 34, 0 }, (try world.get(key, data.Mover)).opened);
    // Sliding out brings the key back to its authored place on the keypad's
    // front edge, not 24 units out in front of the desk.
    var out = try prepare(&world, &.{.{ .entity = keypad, .destination = .{ .position = .{ 0, 2, 0 } } }}, 0, false);
    try out.commit(&world);
    try std.testing.expectEqual(data.Vec3{ 0, 0, 0 }, (try world.get(key, data.Transform)).position);
    try std.testing.expectEqual(@as(?Assembly, null), try carry(&world, key));
}

test "an old save's keys out in front of the desk go back onto their keypad" {
    var world = data.World.init(std.testing.allocator, 16);
    defer world.deinit();
    // Saved by the old spawn: the keypad rests 26 into the desk, its key was
    // left where the keypad was authored.
    _ = try world.create(20, .{ data.Transform{ .position = .{ 0, 26, 0 } }, data.MapObject{ .classname = "func_door", .targetname = "lameass", .flags = 1 }, data.Mover{ .closed = .{ 0, 26, 0 }, .opened = .{ 0, 2, 0 }, .motion = .{ .base = .{ 0, 26, 0 }, .end = .{ 0, 26, 0 } }, .group = 20 } });
    const key = try world.create(21, .{ data.Transform{}, data.MapObject{ .classname = "func_button", .properties = &.{.{ .key = "parenttarget", .value = "lameass" }} }, data.Attachment{ .parent_id = 20, .offset = .{ 0, -26, 0 } }, data.Mover{ .closed = @splat(0), .opened = .{ 0, 10, 0 }, .motion = .{ .base = @splat(0), .end = @splat(0) }, .group = 21 } });
    try reconcile(&world);
    try std.testing.expectEqual(data.Vec3{ 0, 26, 0 }, (try world.get(key, data.Transform)).position);
    try std.testing.expectEqual(data.Vec3{ 0, 36, 0 }, (try world.get(key, data.Mover)).opened);
    // Consistent now: a second pass changes nothing.
    try reconcile(&world);
    try std.testing.expectEqual(data.Vec3{ 0, 26, 0 }, (try world.get(key, data.Transform)).position);
}
