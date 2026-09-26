// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
pub const Named = struct { ids: [ecs.max_entities]u32 = undefined, count: usize = 0 };
pub fn named(world: *data.World, name: []const u8) !Named {
    var result: Named = .{};
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.mem.eql(u8, name, object.targetname)) {
        result.ids[result.count] = try world.persistentId(entity);
        result.count += 1;
    };
    std.mem.sort(u32, result.ids[0..result.count], {}, std.sort.asc(u32));
    return result;
}
