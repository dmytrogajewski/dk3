// SPDX-License-Identifier: GPL-2.0-or-later
//! Inventory-based bot decisions; attacks still run through ordinary player input.
const std = @import("std");
const catalog = @import("weapon_catalog");
const weapons = @import("weapons.zig");
pub fn select(loadout: weapons.State, table: *const weapons.Table, distance: ?f32) u5 {
    return selectFor(loadout, table, distance, .{});
}
pub const Situation = struct {
    /// The shot would meet water close to the shooter, where an ion bolt
    /// discharges into everything nearby, the shooter included.
    wet: bool = false,
    /// The shooter moves on along a route: proximity charges (C4) left for
    /// prey that never arrives would go off under the shooter later.
    advancing: bool = false,
    /// Keep to a ranged weapon while one can shoot: flyers dart in and out of
    /// melee reach, and every swap to the glove and back costs the fire of a
    /// raise and a drop.
    ranged_first: bool = false,
    /// Weapons (bit per id) this shooter must not use here: a companion's
    /// splash weapons with its leader beside the target, for instance.
    excluded: i32 = 0,
};
pub fn selectFor(loadout: weapons.State, table: *const weapons.Table, distance: ?f32, situation: Situation) u5 {
    var selected: u5 = @intCast(loadout.weapon);
    var best: f32 = -1;
    const keep_range = situation.ranged_first and rangedFor(loadout, table, situation);
    for (catalog.entries) |entry| {
        const tuning = table.entries[entry.id];
        if (!entry.spec.auto_select or tuning.damage <= 0 or loadout.dk3Inventory & (@as(i32, 1) << entry.id) == 0 or loadout.ammo[entry.id] < tuning.ammoCost) continue;
        if (situation.excluded & (@as(i32, 1) << entry.id) != 0) continue;
        if (situation.wet and dischargesInWater(entry.id)) continue;
        if (situation.advancing and entry.spec.combat == .charge) continue;
        if (keep_range and (entry.spec.bot_range orelse tuning.range) <= 128) continue;
        var score = tuning.damage;
        if (distance) |range| {
            const reach = entry.spec.bot_range orelse tuning.range;
            if (range > reach) score *= 0.01;
            // A splash weapon is taken up only with room to spare (an enemy
            // closes in while it is raised) and put away inside its radius.
            const margin: f32 = if (entry.id == loadout.weapon) 1 else 1.6;
            if (entry.spec.splash_hazard and range < entry.spec.projectile.splash_radius * margin) score *= 0.01;
            // A projectile leaves the muzzle ahead of the player: point blank
            // it starts beyond (or inside) the target and misses. Hitscan and
            // melee weapons strike there.
            if (range < 96 and tuning.speed > 0) score *= 0.05;
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
pub fn dischargesInWater(weapon: i32) bool {
    const entry = catalog.find(@intCast(weapon)) orelse return false;
    return entry.spec.combat == .ion;
}
pub fn ranged(loadout: weapons.State, table: *const weapons.Table) bool {
    return rangedFor(loadout, table, .{});
}
/// Whether a weapon the situation allows can still shoot beyond close quarters.
pub fn rangedFor(loadout: weapons.State, table: *const weapons.Table, situation: Situation) bool {
    for (catalog.entries) |entry| {
        const tuning = table.entries[entry.id];
        if (!entry.spec.auto_select or tuning.damage <= 0 or loadout.dk3Inventory & (@as(i32, 1) << entry.id) == 0 or loadout.ammo[entry.id] < tuning.ammoCost) continue;
        if (situation.excluded & (@as(i32, 1) << entry.id) != 0) continue;
        if (situation.wet and dischargesInWater(entry.id)) continue;
        if (situation.advancing and entry.spec.combat == .charge) continue;
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
    table.entries[@intCast(loadout.weapon)] = .{ .damage = 50, .range = 128 };
    try std.testing.expect(attack(loadout, &table, 80));
    loadout.dk3Charge = 900;
    try std.testing.expect(!attack(loadout, &table, 80));
}
test "bots keep the ion blaster out of water and take up C4 only with room to spare" {
    const ion = catalog.ion.id;
    const c4 = catalog.c4.id;
    var loadout: weapons.State = .{ .weapon = ion, .dk3Inventory = (@as(i32, 1) << ion) | (@as(i32, 1) << c4) };
    var table: weapons.Table = .{};
    table.entries[ion] = .{ .damage = 20, .range = 2000 };
    table.entries[c4] = .{ .damage = 100, .range = 2000 };
    loadout.ammo[ion] = 50;
    loadout.ammo[c4] = 5;
    try std.testing.expectEqual(@as(u5, ion), select(loadout, &table, 400));
    try std.testing.expectEqual(@as(u5, c4), select(loadout, &table, 600));
    loadout.weapon = c4;
    try std.testing.expectEqual(@as(u5, c4), select(loadout, &table, 400));
    try std.testing.expectEqual(@as(u5, ion), select(loadout, &table, 200));
    loadout.weapon = ion;
    try std.testing.expect(dischargesInWater(ion));
    try std.testing.expect(selectFor(loadout, &table, 600, .{ .wet = true }) != ion);
    try std.testing.expectEqual(@as(u5, ion), selectFor(loadout, &table, 600, .{ .advancing = true }));
    const glove = catalog.weapons[0].id;
    loadout.dk3Inventory |= @as(i32, 1) << glove;
    table.entries[glove] = .{ .damage = 60, .range = 64 };
    try std.testing.expectEqual(@as(u5, glove), selectFor(loadout, &table, 40, .{ .advancing = true }));
    try std.testing.expectEqual(@as(u5, ion), selectFor(loadout, &table, 40, .{ .advancing = true, .ranged_first = true }));
}
test "bots never select or count an excluded weapon" {
    const ion = catalog.ion.id;
    const c4 = catalog.c4.id;
    var loadout: weapons.State = .{ .weapon = ion, .dk3Inventory = (@as(i32, 1) << ion) | (@as(i32, 1) << c4) };
    var table: weapons.Table = .{};
    table.entries[ion] = .{ .damage = 20, .range = 2000 };
    table.entries[c4] = .{ .damage = 100, .range = 2000 };
    loadout.ammo[ion] = 50;
    loadout.ammo[c4] = 5;
    try std.testing.expectEqual(@as(u5, c4), select(loadout, &table, 600));
    try std.testing.expectEqual(@as(u5, ion), selectFor(loadout, &table, 600, .{ .excluded = @as(i32, 1) << c4 }));
    try std.testing.expect(!rangedFor(loadout, &table, .{ .excluded = (@as(i32, 1) << c4) | (@as(i32, 1) << ion) }));
}
