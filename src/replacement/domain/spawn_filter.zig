// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored mode/difficulty restrictions, separate from behavior registration.
const std = @import("std");
const Object = @import("components.zig").MapObject;
pub const Mode = enum { single_player, deathmatch, ctf, deathtag };
pub const Settings = struct { mode: Mode = .single_player, skill: i32 = 2, dedicated: bool = false, max_clients: i32 = 8 };
fn number(object: Object, key: []const u8) !?i32 {
    for (object.properties) |property| if (std.mem.eql(u8, property.key, key)) return std.fmt.parseInt(i32, property.value, 10) catch error.InvalidSpawnRestriction;
    return null;
}
pub fn include(object: Object, settings: Settings) !bool {
    const restrictions = [_]struct { key: []const u8, enabled: bool }{
        .{ .key = "coop", .enabled = false },
        .{ .key = "ctf", .enabled = settings.mode == .ctf },
        .{ .key = "deathtag", .enabled = settings.mode == .deathtag },
        .{ .key = "dedicated", .enabled = settings.dedicated },
    };
    for (restrictions) |restriction| if (try number(object, restriction.key)) |value| if ((value != 0) != restriction.enabled) return false;
    if (settings.mode == .single_player) {
        const excluded: u32 = if (settings.skill <= 2) 0x1000 else if (settings.skill == 3) 0x2000 else 0x4000;
        return object.flags & excluded == 0;
    }
    if (object.flags & 0x8000 != 0 or std.mem.startsWith(u8, object.classname, "monster_")) return false;
    if (try number(object, "maxplayers")) |maximum| if (maximum != settings.max_clients) return false;
    return true;
}
pub fn behaviorFlags(flags: u32) u32 {
    return flags & ~@as(u32, 0xf000);
}
test "single-player difficulty, co-op exclusions and multiplayer restrictions" {
    const coop: Object = .{ .classname = "func_button", .properties = &.{.{ .key = "coop", .value = "1" }} };
    try std.testing.expect(!try include(coop, .{}));
    const item: Object = .{ .classname = "weapon_ionblaster", .flags = 0x7000 };
    for ([_]i32{ 1, 2, 3, 4, 5 }) |skill| try std.testing.expect(!try include(item, .{ .skill = skill }));
    try std.testing.expect(try include(item, .{ .mode = .deathmatch }));
    try std.testing.expect(!try include(.{ .classname = "monster_worker" }, .{ .mode = .deathmatch }));
    try std.testing.expectEqual(@as(u32, 5), behaviorFlags(0x8005));
}
