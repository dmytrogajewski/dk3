// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const engine = @import("../engine/server.zig");
const rules = @import("../domain/spawn_filter.zig");
const c = @import("../engine/abi.zig").c;
pub fn apply(world: *data.World) !void {
    const settings: rules.Settings = .{
        .mode = switch (engine.integer("g_gametype")) {
            c.GT_SINGLE_PLAYER => .single_player,
            c.GT_CTF => .ctf,
            c.GT_DK3_DEATHTAG => .deathtag,
            else => .deathmatch,
        },
        .skill = engine.integer("g_spSkill"),
        .dedicated = engine.integer("dedicated") != 0,
        .max_clients = engine.integer("sv_maxclients"),
    };
    try applySettings(world, settings);
}
pub fn applySettings(world: *data.World, settings: rules.Settings) !void {
    var excluded: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, data.World.mask(.{data.MapObject}));
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.write(data.MapObject)) |entity, *object| {
            if (try rules.include(object.*, settings)) {
                object.flags = rules.behaviorFlags(object.flags);
            } else {
                excluded[count] = entity;
                count += 1;
            }
        };
    }
    // Every authored ID was allocated before filtering; exclusions never renumber the map.
    for (excluded[0..count]) |entity| try world.destroy(entity);
}

test "filter removes excluded entities without renumbering retained or future IDs" {
    const std = @import("std");
    var world = data.World.init(std.testing.allocator, 8);
    defer world.deinit();
    _ = try world.create(null, .{data.MapObject{ .classname = "weapon_ionblaster", .flags = 0x7000 }});
    const kept = try world.create(null, .{data.MapObject{ .classname = "item_keycard_cell", .flags = 0x8005 }});
    _ = try world.create(null, .{data.MapObject{ .classname = "func_button", .properties = &.{.{ .key = "coop", .value = "1" }} }});
    try applySettings(&world, .{});
    try std.testing.expectEqual(@as(usize, 1), world.count());
    try std.testing.expectEqual(@as(u32, 2), try world.persistentId(kept));
    try std.testing.expectEqual(@as(u32, 5), (try world.get(kept, data.MapObject)).flags);
    const next = try world.create(null, .{data.MapObject{ .classname = "player" }});
    try std.testing.expectEqual(@as(u32, 4), try world.persistentId(next));
}
