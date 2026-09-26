// SPDX-License-Identifier: GPL-2.0-or-later
//! Named authored landings and ordinary starts share deterministic selection.
const std = @import("std");
const data = @import("../domain/components.zig");
pub const Spawn = struct { pose: data.Transform, flags: u32 };
pub fn select(world: *data.World, name: []const u8) !Spawn {
    var selected: ?Spawn = null;
    var priority: u8 = 0;
    var identity: u32 = std.math.maxInt(u32);
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject), view.read(data.Transform)) |entity, object, pose| {
        const start = std.mem.eql(u8, object.classname, "info_player_start");
        if (!start and !std.mem.eql(u8, object.classname, "info_player_deathmatch")) continue;
        const candidate: u8 = if (!start) 1 else if (name.len != 0 and std.ascii.eqlIgnoreCase(object.targetname, name)) 4 else if (object.targetname.len == 0) 3 else 2;
        const id = try world.persistentId(entity);
        if (candidate > priority or (candidate == priority and id < identity)) {
            priority = candidate;
            identity = id;
            selected = .{ .pose = pose, .flags = object.flags };
        }
    };
    return selected orelse error.MissingPlayerSpawn;
}
test "arrival chooses named start and fallback ignores archetype iteration order" {
    var world = data.World.init(std.testing.allocator, 8);
    defer world.deinit();
    _ = try world.create(8, .{ data.Transform{ .position = .{ 8, 0, 0 } }, data.MapObject{ .classname = "info_player_start", .targetname = "from_b", .flags = 1 } });
    _ = try world.create(4, .{ data.Transform{ .position = .{ 4, 0, 0 } }, data.MapObject{ .classname = "info_player_start" } });
    _ = try world.create(2, .{ data.Transform{ .position = .{ 2, 0, 0 } }, data.MapObject{ .classname = "info_player_start", .targetname = "other" }, data.Keys{} });
    try std.testing.expectEqual(@as(f32, 8), (try select(&world, "from_b")).pose.position[0]);
    try std.testing.expectEqual(@as(u32, 1), (try select(&world, "from_b")).flags);
    try std.testing.expectEqual(@as(f32, 4), (try select(&world, "missing")).pose.position[0]);
    try std.testing.expectEqual(@as(f32, 4), (try select(&world, "")).pose.position[0]);
}
