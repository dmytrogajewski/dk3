// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored one-shot monster factories and actor death outputs.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Actors = @import("actors.zig").Actors;
const prop = @import("properties.zig");

fn monsterObject(allocator: std.mem.Allocator, source: data.MapObject, classname: []const u8, flags: u32) !data.MapObject {
    var pairs: std.ArrayList(data.Property) = .empty;
    defer pairs.deinit(allocator);
    for (source.properties) |pair| {
        if (std.mem.eql(u8, pair.key, "classname")) continue;
        try pairs.append(allocator, .{ .key = if (std.mem.eql(u8, pair.key, "monsterclass")) "classname" else if (std.mem.eql(u8, pair.key, "muniqueid")) "uniqueid" else pair.key, .value = pair.value });
    }
    return .{ .classname = classname, .targetname = source.targetname, .target = source.target, .flags = flags, .properties = try pairs.toOwnedSlice(allocator) };
}
pub fn use(actors: *Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, source: ?ecs.Entity, now: i64) !void {
    const object = (try world.get(entity, data.MapObject)).*;
    const classname = prop.text(object, "monsterclass") orelse return error.MissingSpawnClass;
    var pose = (try world.get(entity, data.Transform)).*;
    pose.position[2] += 0.03125; // Reference dynamic-spawn collision epsilon.
    if (@import("actor_catalog").find(classname) != null) {
        var flags = object.flags;
        if (source) |other| if ((world.get(other, data.Actor) catch null) != null) {
            flags = (try world.get(other, data.MapObject)).flags;
        };
        _ = try actors.spawnAuthored(world, slots, projections, try monsterObject(actors.allocator, object, classname, flags), pose, now);
    } else {
        _ = try @import("items.zig").spawnDynamic(world, slots, projections, classname, pose, now, actors.episode);
    }
    if (prop.text(object, "sound")) |sound| try @import("events.zig").sound(world, slots, projections, sound, pose.position, abi.c.ENTITYNUM_NONE, abi.c.CHAN_AUTO, now);
    if (slots.find(entity)) |slot| {
        engine.unlink(&projections[slot]);
        try slots.release(slot, entity);
    }
    try world.destroy(entity);
}
pub fn death(actors: *Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, entity: ecs.Entity, now: i64) !void {
    const object = (try world.get(entity, data.MapObject)).*;
    var pose = (try world.get(entity, data.Transform)).*;
    const identity = try world.persistentId(entity);
    if (prop.text(object, "deathtarget")) |name| try router.fireNamed(world, slots, projections, name, entity, identity, now);
    if (prop.text(object, "spawnname")) |classname| {
        if (classname.len == 0) return;
        pose.position[2] += 0.03125;
        if (@import("actor_catalog").find(classname) != null) {
            _ = try actors.spawnDynamic(world, slots, projections, classname, pose.position, pose.angles, now);
        } else {
            if (std.mem.startsWith(u8, classname, "monster_")) return error.UnknownActorClass;
            _ = try @import("items.zig").spawnDynamic(world, slots, projections, classname, pose, now, actors.episode);
        }
    }
}
test "authored monster factory preserves death outputs and maps the unique id" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try monsterObject(arena.allocator(), .{ .classname = "target_monster_spawn", .targetname = "tskeetspawn", .flags = 16, .properties = &.{
        .{ .key = "classname", .value = "target_monster_spawn" },
        .{ .key = "monsterclass", .value = "monster_thunderskeet" },
        .{ .key = "muniqueid", .value = "tskeet" },
        .{ .key = "deathtarget", .value = "tskeetdead" },
        .{ .key = "spawnname", .value = "item_megashield" },
    } }, "monster_thunderskeet", 2);
    try std.testing.expectEqualStrings("monster_thunderskeet", result.classname);
    try std.testing.expectEqualStrings("monster_thunderskeet", prop.text(result, "classname").?);
    try std.testing.expectEqualStrings("tskeet", prop.text(result, "uniqueid").?);
    try std.testing.expectEqualStrings("tskeetdead", prop.text(result, "deathtarget").?);
    try std.testing.expectEqualStrings("item_megashield", prop.text(result, "spawnname").?);
    try std.testing.expectEqualStrings("tskeetspawn", result.targetname);
    try std.testing.expectEqual(@as(u32, 2), result.flags);
}
