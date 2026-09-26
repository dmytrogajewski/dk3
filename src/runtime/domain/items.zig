// SPDX-License-Identifier: GPL-2.0-or-later
//! Acquisition policies own inventory changes; world visibility/targets stay outside.
const std = @import("std");
const catalog = @import("item_catalog");
const weapons = @import("weapons.zig");
const weapon_catalog = @import("weapon_catalog");
const character = @import("character.zig");
pub const Keys = catalog.Keys;
pub const Health = struct { current: i32 = 100, maximum: i32 = 100, armor: i32 = 0, absorption: i32 = 0 };
pub const Kind = union(enum) { boost: character.Attribute, antidote, invincibility, invisibility, environment, ring: u32, save_gem, key: u5, weapon: u5, ammunition: u5, health: i32, soul, armor: struct { capacity: i32, absorption: i32 } };
pub const Pickup = struct { kind: Kind, amount: i32 = 0, visible: bool = true, respawn_ms: ?i64 = null };
pub fn canonicalName(name: []const u8) []const u8 {
    return if (std.mem.eql(u8, name, "item_vitality_boost")) "item_vita_boost" else name;
}
pub fn classify(raw_name: []const u8) ?Kind {
    const name = canonicalName(raw_name);
    inline for (std.meta.fields(character.Attribute)) |field| if (std.mem.eql(u8, name, "item_" ++ field.name ++ "_boost")) return .{ .boost = @enumFromInt(field.value) };
    for ([_]struct { name: []const u8, kind: Kind }{
        .{ .name = "item_antidote", .kind = .antidote },                .{ .name = "item_invincibility", .kind = .invincibility },
        .{ .name = "item_wraithorb", .kind = .invisibility },           .{ .name = "item_envirosuit", .kind = .environment },
        .{ .name = "item_savegem", .kind = .save_gem },                 .{ .name = "item_ring_of_fire", .kind = .{ .ring = 16 } },
        .{ .name = "item_ring_of_lightning", .kind = .{ .ring = 32 } }, .{ .name = "item_ring_of_undead", .kind = .{ .ring = 64 } },
    }) |entry| if (std.mem.eql(u8, name, entry.name)) return entry.kind;
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
pub const Receiver = struct { keys: *Keys, health: *Health, loadout: *weapons.State, character: *character.State, ailments: *character.Ailments };
pub fn give(pickup: Pickup, receiver: Receiver, table: *const weapons.Table, now: i64, single_player: bool) bool {
    const keys = receiver.keys;
    const health = receiver.health;
    const loadout = receiver.loadout;
    if (health.current <= 0 or !pickup.visible) return false;
    switch (pickup.kind) {
        .boost => |which| return receiver.character.boost(which, now),
        .antidote => {
            receiver.ailments.cure();
            return true;
        },
        .invincibility => {
            receiver.character.invincible_until = now + 30000;
            return true;
        },
        .invisibility => {
            receiver.character.invisible_until = now + 60000;
            return true;
        },
        .environment => {
            receiver.character.environment_until = now + 60000;
            return true;
        },
        .ring => |mask| {
            receiver.character.rings |= mask;
            return true;
        },
        .save_gem => {
            if (receiver.character.save_gems == std.math.maxInt(i32)) return false;
            receiver.character.save_gems += 1;
            return true;
        },
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
    if (single_player or std.mem.eql(u8, name, "item_savegem")) return null;
    if (std.mem.eql(u8, name, "item_goldensoul") or std.mem.endsWith(u8, name, "_boost")) return 60000;
    if (std.mem.eql(u8, name, "item_megashield") or std.mem.eql(u8, name, "item_wraithorb") or std.mem.eql(u8, name, "item_invincibility")) return 300000;
    return 30000;
}
test "pickups preserve full inventory and health; ammunition does not grant ownership" {
    var keys: Keys = .{};
    var health: Health = .{};
    var loadout: weapons.State = .{};
    var effects: character.State = .{};
    var ailments: character.Ailments = .{};
    const receiver: Receiver = .{ .keys = &keys, .health = &health, .loadout = &loadout, .character = &effects, .ailments = &ailments };
    var table: weapons.Table = .{};
    table.entries[2].ammoMax = 100;
    table.entries[2].initialAmmo = 20;
    const ammo: Pickup = .{ .kind = classify("ammo_ionpack").?, .amount = std.math.maxInt(i32) };
    try std.testing.expect(give(ammo, receiver, &table, 0, true));
    try std.testing.expectEqual(@as(i32, 100), loadout.ammo[2]);
    try std.testing.expectEqual(@as(i32, 0), loadout.dk3Inventory);
    try std.testing.expect(!give(ammo, receiver, &table, 0, true));
    try std.testing.expect(!give(.{ .kind = .{ .health = 25 } }, receiver, &table, 0, true));
    try std.testing.expect(give(.{ .kind = .soul }, receiver, &table, 0, true));
    try std.testing.expectEqual(@as(i32, 200), health.current);
    try std.testing.expect(give(.{ .kind = classify("item_plasteel_armor").? }, receiver, &table, 0, true));
    try std.testing.expectEqual(@as(i32, 75), health.absorption);
}

test "Gas Hands pickups accumulate bounded duration and force the raising state" {
    var keys: Keys = .{};
    var health: Health = .{};
    var loadout: weapons.State = .{};
    var effects: character.State = .{};
    var ailments: character.Ailments = .{};
    const receiver: Receiver = .{ .keys = &keys, .health = &health, .loadout = &loadout, .character = &effects, .ailments = &ailments };
    var table: weapons.Table = .{};
    table.entries[7].lifetime = 60;
    const pickup: Pickup = .{ .kind = .{ .weapon = 7 } };
    try std.testing.expect(give(pickup, receiver, &table, 1000, true));
    try std.testing.expectEqual(@as(i64, 61000), loadout.gas_until_ms);
    try std.testing.expect(give(pickup, receiver, &table, 2000, true));
    try std.testing.expectEqual(@as(i64, 121000), loadout.gas_until_ms);
    try std.testing.expectEqual(@as(i32, 1550), loadout.weaponTime);
    loadout.gas_until_ms = 3602000;
    try std.testing.expect(!give(pickup, receiver, &table, 2000, true));
}

pub fn pickupSound(kind: Kind, raw_name: []const u8) [:0]const u8 {
    const name = canonicalName(raw_name);
    return switch (kind) {
        .weapon => |id| weapon_catalog.find(id).?.spec.audio.pickup,
        .ammunition => |id| weapon_catalog.find(id).?.spec.audio.ammo_pickup,
        .health => |amount| if (amount >= 50) "global/a_h50pick.wav" else "global/a_hpick.wav",
        .armor => if (std.mem.indexOf(u8, name, "plasteel") != null or std.mem.indexOf(u8, name, "silver") != null or std.mem.indexOf(u8, name, "chainmail") != null) "global/armorpickup2.wav" else "global/armorpickup1.wav",
        .soul => "artifacts/goldensoulpickup.wav",
        .save_gem => "artifacts/savegem_pickup.wav",
        .invisibility => "artifacts/wraithorbpickup.wav",
        .environment => "artifacts/envirosuitpickup.wav",
        .boost => |which| switch (which) {
            .power => "global/a_pboost.wav",
            .attack => "global/a_atkboost.wav",
            .speed => "global/a_sboost.wav",
            .acro => "global/a_aboost.wav",
            .vita => "global/a_vboost.wav",
        },
        else => "global/itempickup1.wav",
    };
}

test "pickup audio resolves weapon class defaults and ammunition overrides" {
    for (weapon_catalog.entries) |entry| {
        try std.testing.expectEqualStrings(entry.spec.audio.pickup, pickupSound(.{ .weapon = entry.id }, entry.classname));
        if (entry.spec.ammo_class) |ammo| try std.testing.expectEqualStrings(entry.spec.audio.ammo_pickup, pickupSound(classify(ammo).?, ammo));
    }
    const cases = .{
        .{ "ammo_ionpack", "global/i_ionammo.wav" },
        .{ "ammo_shells", "global/i_scyclerammo.wav" },
        .{ "ammo_rockets", "global/i_swinderammo.wav" },
        .{ "ammo_shocksphere", "global/i_swaveammo.wav" },
        .{ "ammo_c4", "global/i_c4ammo.wav" },
        .{ "ammo_bullets", "global/i_c4ammo.wav" },
    };
    inline for (cases) |case| try std.testing.expectEqualStrings(case[1], pickupSound(classify(case[0]).?, case[0]));
}
