// SPDX-License-Identifier: GPL-2.0-or-later
//! Credited kills belong to death dispatch, independently of corpse animation.
const std = @import("std");
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
fn ammunition(world: *data.World, attacker: @import("../ecs/world.zig").Entity, episode: u8, table: *const @import("../domain/weapons.zig").Table) !void {
    if ((world.get(attacker, data.Player) catch null) == null) return;
    const loadout = try world.get(attacker, data.Weapons);
    for (@import("weapon_catalog").entries) |entry| {
        if (entry.episode != episode or entry.spec.credited_kill_ammo == 0) continue;
        if (loadout.ammo[entry.id] == 0 and loadout.dk3Inventory & (@as(i32, 1) << entry.id) == 0) continue;
        _ = @import("inventory_rules").addAmmo(&loadout.ammo[entry.id], table.entries[entry.id].ammoMax, entry.spec.credited_kill_ammo, 0);
    }
}
pub fn kill(world: *data.World, receipt: data.Hurt, base_health: i32, episode: u8, table: *const @import("../domain/weapons.zig").Table) !void {
    const attacker = @import("region_access.zig").find(world, receipt.source) orelse return;
    const character = attacker.get(data.Character) catch return;
    const amount = @divTrunc(base_health * @as(i32, episode), 10);
    const sword_kill = receipt.weapon == @import("weapon_catalog").daikatana.id;
    const levels = if (sword_kill) 0 else try character.award(amount);
    const sword = @import("weapon_catalog").swordExperience(receipt.weapon, base_health);
    if (attacker.get(data.Weapons) catch null) |loadout| loadout.dk3SwordExperience = try std.math.add(i32, loadout.dk3SwordExperience, sword);
    if (!sword_kill and amount > 0) try ammunition(attacker.world, attacker.entity, episode, table);
    if (engine.integer("developer") > 0) {
        var message: [192]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig progression: player={d} experience={d} sword={d} level={d} gained={d} points={d}\n", .{ receipt.source, character.experience, if (attacker.get(data.Weapons) catch null) |loadout| loadout.dk3SwordExperience else 0, character.level, levels, character.points }));
    }
}

/// Multiplayer rewards use spent opponent attributes, rather than monster health.
pub fn playerKill(world: *data.World, victim: @import("../ecs/world.zig").Entity, receipt: data.Hurt, episode: u8, table: *const @import("../domain/weapons.zig").Table) !void {
    const attacker = world.find(receipt.source) orelse return;
    if (attacker.index == victim.index or (world.get(attacker, data.Session) catch null) == null) return;
    if (receipt.weapon == @import("weapon_catalog").daikatana.id) {
        const loadout = try world.get(attacker, data.Weapons);
        const base_health = (try world.get(victim, data.Health)).maximum;
        loadout.dk3SwordExperience = try std.math.add(i32, loadout.dk3SwordExperience, @import("weapon_catalog").swordExperience(receipt.weapon, base_health));
        return;
    }
    try ammunition(world, attacker, episode, table);
    if (engine.integer("dm_use_skill_system") == 0) return;
    const opponent = (try world.get(victim, data.Character)).*;
    var level: i32 = 0;
    for (opponent.attributes) |attribute| level += attribute;
    const limit = engine.integer("dm_levellimit");
    _ = try (try world.get(attacker, data.Character)).awardLimited(100 * (level + 1), if (limit <= 0) 25 else @min(limit, 24) + 1);
}
