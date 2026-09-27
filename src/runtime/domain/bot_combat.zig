// SPDX-License-Identifier: GPL-2.0-or-later
//! Inventory-based bot decisions; attacks still run through ordinary player input.
const std = @import("std");
const catalog = @import("weapon_catalog");
const weapons = @import("weapons.zig");
pub fn select(loadout: weapons.State, table: *const weapons.Table, distance: ?f32) u5 {
    var selected: u5 = @intCast(loadout.weapon);
    var best: f32 = -1;
    for (catalog.entries) |entry| {
        const tuning = table.entries[entry.id];
        if (!entry.spec.auto_select or tuning.damage <= 0 or loadout.dk3Inventory & (@as(i32, 1) << entry.id) == 0 or loadout.ammo[entry.id] < tuning.ammoCost) continue;
        var score = tuning.damage;
        if (distance) |range| {
            const reach = entry.spec.bot_range orelse tuning.range;
            if (range > reach) score *= 0.01;
            if (entry.spec.splash_hazard and range < entry.spec.projectile.splash_radius) score *= 0.01;
        }
        // Avoid switching between equivalent choices every command.
        if (entry.id == loadout.weapon) score *= 1.25;
        if (score > best) {
            best = score;
            selected = entry.id;
        }
    }
    return selected;
}
pub fn ranged(loadout: weapons.State, table: *const weapons.Table) bool {
    for (catalog.entries) |entry| {
        const tuning = table.entries[entry.id];
        if (!entry.spec.auto_select or tuning.damage <= 0 or loadout.dk3Inventory & (@as(i32, 1) << entry.id) == 0 or loadout.ammo[entry.id] < tuning.ammoCost) continue;
        if ((entry.spec.bot_range orelse tuning.range) > 128) return true;
    }
    return false;
}
pub fn attack(loadout: weapons.State, table: *const weapons.Table, distance: f32) bool {
    const entry = catalog.find(@intCast(loadout.weapon)) orelse return false;
    if (!entry.spec.auto_select or loadout.weaponstate == 1 or loadout.weaponstate == 2) return false;
    const tuning = table.entries[entry.id];
    if (tuning.damage <= 0 or distance > (entry.spec.bot_range orelse tuning.range)) return false;
    if (entry.spec.splash_hazard and distance < entry.spec.projectile.splash_radius) return false;
    if (entry.spec.bot_charge_ms > 0 and loadout.dk3Charge >= entry.spec.bot_charge_ms) return false;
    return loadout.ammo[entry.id] >= tuning.ammoCost;
}
test "bots reject unavailable ammunition and flashlight and release a charged Hammer" {
    var loadout: weapons.State = .{ .weapon = 1, .dk3Inventory = (1 << 1) | (1 << 2) | (1 << 28) };
    var table: weapons.Table = .{};
    table.entries[1] = .{ .damage = 15, .range = 128 };
    table.entries[2] = .{ .damage = 30, .range = 1000, .ammoCost = 2 };
    table.entries[28] = .{ .damage = 100, .range = 2000, .ammoCost = 1 };
    loadout.ammo[2] = 1;
    loadout.ammo[28] = 100;
    try std.testing.expectEqual(@as(u5, 1), select(loadout, &table, 500));
    loadout.ammo[2] = 2;
    try std.testing.expectEqual(@as(u5, 2), select(loadout, &table, 500));
    loadout.weapon = catalog.hammer.id;
    table.entries[loadout.weapon] = .{ .damage = 50, .range = 128 };
    try std.testing.expect(attack(loadout, &table, 80));
    loadout.dk3Charge = 900;
    try std.testing.expect(!attack(loadout, &table, 80));
}
