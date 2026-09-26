// SPDX-License-Identifier: GPL-2.0-or-later
//! Parent identity and pose composition; no engine collision calls here.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const pose = @import("../domain/poses.zig");
const v = @import("../domain/vector.zig");
const prop = @import("properties.zig");
const names = @import("names.zig");
pub fn spawn(world: *data.World) !void {
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
        const offset = v.add((try world.get(entity, data.Transform)).position, v.scale((try world.get(parent, data.Transform)).position, -1));
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
