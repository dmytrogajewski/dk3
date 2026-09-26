// SPDX-License-Identifier: GPL-2.0-or-later
//! Called once from actor death dispatch, independently of damage and corpse animation.
const std = @import("std");
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
pub fn kill(world: *data.World, receipt: data.Hurt, base_health: i32, episode: u8) !void {
    const attacker = world.find(receipt.source) orelse return;
    const character = world.get(attacker, data.Character) catch return;
    const amount = @divTrunc(base_health * @as(i32, episode), 10);
    const levels = try character.award(amount);
    const sword = @import("weapon_catalog").swordExperience(receipt.weapon, base_health);
    if (world.get(attacker, data.Weapons) catch null) |loadout| loadout.dk3SwordExperience = try std.math.add(i32, loadout.dk3SwordExperience, sword);
    if (engine.integer("developer") > 0) {
        var message: [192]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig progression: player={d} experience={d} sword={d} level={d} gained={d} points={d}\n", .{ receipt.source, character.experience, if (world.get(attacker, data.Weapons) catch null) |loadout| loadout.dk3SwordExperience else 0, character.level, levels, character.points }));
    }
}
