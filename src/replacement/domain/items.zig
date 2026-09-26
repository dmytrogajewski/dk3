// SPDX-License-Identifier: GPL-2.0-or-later
//! Acquisition policies own inventory changes; world visibility/targets stay outside.
const std = @import("std");
const catalog = @import("item_catalog");
const weapons = @import("weapons.zig");
const weapon_catalog = @import("weapon_catalog");
pub const Keys = catalog.Keys;
pub const Health = struct { current: i32 = 100, maximum: i32 = 100, armor: i32 = 0, absorption: i32 = 0 };
pub const Kind = union(enum) { key: u5, weapon: u5, ammunition: u5, health: i32, soul, armor: struct { capacity: i32, absorption: i32 } };
pub const Pickup = struct { kind: Kind, amount: i32 = 0, visible: bool = true, respawn_ms: ?i64 = null };
pub fn classify(name: []const u8) ?Kind {
    if (catalog.keyIndex(name)) |index| return .{ .key = index };
    for (weapon_catalog.entries) |entry| {
        if (std.ascii.eqlIgnoreCase(name, entry.classname) or (entry.id == 3 and std.ascii.eqlIgnoreCase(name, "weapon_c4viz"))) return .{ .weapon = entry.id };
        if (entry.spec.ammo_class) |ammo| if (std.ascii.eqlIgnoreCase(name, ammo)) return .{ .ammunition = entry.id };
    }
    if (std.mem.eql(u8, name, "item_goldensoul")) return .soul;
    if (std.mem.startsWith(u8, name, "item_health_")) {
        const amount = std.fmt.parseInt(i32, name[12..], 10) catch return null;
        if (amount <= 0 or amount > 1000) return null;
        return .{ .health = amount };
    }
    const Armor = struct { name: []const u8, capacity: i32, absorption: i32 };
    for ([_]Armor{
        .{ .name = "item_plasteel_armor", .capacity = 200, .absorption = 75 },
        .{ .name = "item_chromatic_armor", .capacity = 100, .absorption = 50 },
        .{ .name = "item_silver_armor", .capacity = 150, .absorption = 65 },
        .{ .name = "item_gold_armor", .capacity = 200, .absorption = 75 },
        .{ .name = "item_chainmail_armor", .capacity = 125, .absorption = 50 },
        .{ .name = "item_black_adamant_armor", .capacity = 250, .absorption = 80 },
        .{ .name = "item_kevlar_armor", .capacity = 100, .absorption = 40 },
        .{ .name = "item_ebonite_armor", .capacity = 200, .absorption = 75 },
        .{ .name = "item_megashield", .capacity = 400, .absorption = 75 },
    }) |armor| if (std.mem.eql(u8, name, armor.name)) return .{ .armor = .{ .capacity = armor.capacity, .absorption = armor.absorption } };
    return null;
}
pub fn give(pickup: Pickup, keys: *Keys, health: *Health, loadout: *weapons.State, table: *const weapons.Table, now: i64, single_player: bool) bool {
    if (health.current <= 0 or !pickup.visible) return false;
    switch (pickup.kind) {
        .key => |index| {
            _ = keys.collect(index);
            return true;
        },
        .weapon => |id| {
            if (id == 7 and single_player) {
                const deadline = (weapon_catalog.gas.extend(loadout.gas_until_ms, now, table.entries[id].lifetime) catch return false) orelse return false;
                loadout.gas_until_ms = deadline;
                loadout.dk3Inventory |= @as(i32, 1) << id;
                loadout.weapon = id;
                loadout.weaponstate = 1; // public WEAPON_RAISING state
                loadout.weaponTime = weapon_catalog.find(id).?.spec.animation.raise_ms;
                return true;
            }
            if (!loadout.acquire(table, id, if (pickup.amount > 0) pickup.amount else table.entries[id].initialAmmo)) return false;
            return true;
        },
        .ammunition => |id| {
            const entry = weapon_catalog.find(id).?;
            const maximum = table.entries[id].ammoMax;
            const pack = if (entry.spec.ammo_pack > 0) entry.spec.ammo_pack else table.entries[id].initialAmmo;
            return @import("inventory_rules").addAmmo(&loadout.ammo[id], maximum, pickup.amount, pack);
        },
        .health, .soul => {
            const maximum = health.maximum + @as(i32, if (pickup.kind == .soul) 100 else 0);
            if (health.current >= maximum) return false;
            const amount = if (pickup.amount > 0) pickup.amount else if (pickup.kind == .soul) 100 else pickup.kind.health;
            health.current = @intCast(@min(@as(i64, maximum), @as(i64, health.current) + amount));
            return true;
        },
        .armor => |armor| {
            const amount = if (pickup.amount > 0) pickup.amount else armor.capacity;
            if (health.armor >= amount and health.absorption >= armor.absorption) return false;
            health.armor = amount;
            health.absorption = armor.absorption;
            return true;
        },
    }
}
pub fn respawnDelay(name: []const u8, single_player: bool) ?i64 {
    if (single_player) return null;
    if (std.mem.eql(u8, name, "item_goldensoul")) return 60000;
    if (std.mem.eql(u8, name, "item_megashield")) return 300000;
    return 30000;
}
test "pickups preserve full inventory and health; ammunition does not grant ownership" {
    var keys: Keys = .{};
    var health: Health = .{};
    var loadout: weapons.State = .{};
    var table: weapons.Table = .{};
    table.entries[2].ammoMax = 100;
    table.entries[2].initialAmmo = 20;
    const ammo: Pickup = .{ .kind = classify("ammo_ionpack").?, .amount = std.math.maxInt(i32) };
    try std.testing.expect(give(ammo, &keys, &health, &loadout, &table, 0, true));
    try std.testing.expectEqual(@as(i32, 100), loadout.ammo[2]);
    try std.testing.expectEqual(@as(i32, 0), loadout.dk3Inventory);
    try std.testing.expect(!give(ammo, &keys, &health, &loadout, &table, 0, true));
    try std.testing.expect(!give(.{ .kind = .{ .health = 25 } }, &keys, &health, &loadout, &table, 0, true));
    try std.testing.expect(give(.{ .kind = .soul }, &keys, &health, &loadout, &table, 0, true));
    try std.testing.expectEqual(@as(i32, 200), health.current);
    try std.testing.expect(give(.{ .kind = classify("item_plasteel_armor").? }, &keys, &health, &loadout, &table, 0, true));
    try std.testing.expectEqual(@as(i32, 75), health.absorption);
}

test "Gas Hands pickups accumulate bounded duration and force the raising state" {
    var keys: Keys = .{};
    var health: Health = .{};
    var loadout: weapons.State = .{};
    var table: weapons.Table = .{};
    table.entries[7].lifetime = 60;
    const pickup: Pickup = .{ .kind = .{ .weapon = 7 } };
    try std.testing.expect(give(pickup, &keys, &health, &loadout, &table, 1000, true));
    try std.testing.expectEqual(@as(i64, 61000), loadout.gas_until_ms);
    try std.testing.expect(give(pickup, &keys, &health, &loadout, &table, 2000, true));
    try std.testing.expectEqual(@as(i64, 121000), loadout.gas_until_ms);
    try std.testing.expectEqual(@as(i32, 1550), loadout.weaponTime);
    loadout.gas_until_ms = 3602000;
    try std.testing.expect(!give(pickup, &keys, &health, &loadout, &table, 2000, true));
}
