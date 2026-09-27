// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored inventory deletion preserves class ownership and active selection rules.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
pub fn remove(world: *data.World, entity: ecs.Entity, name: []const u8) !void {
    const kind = @import("../domain/items.zig").classify(name) orelse return error.UnknownRemovedInventoryItem;
    switch (kind) {
        .weapon => |id| (try world.get(entity, data.Weapons)).dk3Inventory &= ~(@as(i32, 1) << id),
        .ammunition => |id| (try world.get(entity, data.Weapons)).ammo[id] = 0,
        .key => |id| (try world.get(entity, data.Keys)).mask &= ~(@as(u32, 1) << id),
        .ring => |mask| (try world.get(entity, data.Character)).rings &= ~mask,
        .save_gem => (try world.get(entity, data.Character)).save_gems = 0,
        .invincibility => (try world.get(entity, data.Character)).invincible_until = 0,
        .invisibility => (try world.get(entity, data.Character)).invisible_until = 0,
        .environment => {
            const character = try world.get(entity, data.Character);
            character.environment_charge_ms = 0;
            character.environment_until = 0;
        },
        .boost => |attribute| (try world.get(entity, data.Character)).boost_until[@intFromEnum(attribute)] = 0,
        .antidote, .health, .soul, .armor => return error.NonInventoryItemRemoval,
    }
}

test "authored removal deletes only the named inventory item and prevents further sword ownership" {
    const t = @import("std").testing;
    const catalog = @import("weapon_catalog");
    var world = data.World.init(t.allocator, 2);
    defer world.deinit();
    const sword = @as(i32, 1) << catalog.daikatana.id;
    const ion = @as(i32, 1) << catalog.ion.id;
    const player = try world.create(1, .{ data.Weapons{ .dk3Inventory = sword | ion, .weapon = catalog.daikatana.id }, data.Keys{}, data.Character{}, data.Health{} });
    try remove(&world, player, "weapon_daikatana");
    try t.expectEqual(ion, (try world.get(player, data.Weapons)).dk3Inventory);
    try t.expectEqual(@as(i32, catalog.daikatana.id), (try world.get(player, data.Weapons)).weapon);
    try t.expectEqual(@as(i32, 100), (try world.get(player, data.Health)).current);
    try t.expectError(error.UnknownRemovedInventoryItem, remove(&world, player, "item_missing"));
}
