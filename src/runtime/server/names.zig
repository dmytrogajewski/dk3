// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
pub const Named = struct { ids: [ecs.max_entities]u32 = undefined, count: usize = 0 };
pub fn named(world: *data.World, name: []const u8) !Named {
    var result: Named = .{};
    const context = @import("region_access.zig").contextFor(world);
    const scope_name = if (context) |owner| std.mem.sliceTo(&owner.map_name, 0) else "";
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (std.mem.eql(u8, name, object.targetname) and (object.authoring_map.len == 0 or std.mem.eql(u8, object.authoring_map, scope_name))) {
        result.ids[result.count] = try world.persistentId(entity);
        result.count += 1;
    };
    if (context) |owner| {
        var candidates = @import("region_access.zig").Damageables.init(world, &owner.slots);
        while (candidates.next()) |ref| {
            if (ref.world == world) continue;
            const object = ref.get(data.MapObject) catch continue;
            if (!std.mem.eql(u8, object.authoring_map, scope_name) or !std.mem.eql(u8, object.targetname, name)) continue;
            if (result.count == result.ids.len) return error.TargetNameCapacity;
            result.ids[result.count] = try ref.id();
            result.count += 1;
        }
    }
    std.mem.sort(u32, result.ids[0..result.count], {}, std.sort.asc(u32));
    return result;
}
