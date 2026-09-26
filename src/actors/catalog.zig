// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed actor policies; authored numeric tuning remains in supplied aidata.
pub const Civilian = struct {
    classname: []const u8,
    idle: []const u8 = "amba",
    run: []const u8 = "runa",
    death: []const u8 = "diea",
    witness_range: f32 = 512,
    panic_ms: i64 = 6000,
};
pub const civilians = [_]Civilian{
    .{ .classname = "monster_skinnyworker" },
    .{ .classname = "monster_fatworker" },
    .{ .classname = "monster_prisoner" },
    .{ .classname = "monster_prisonerb" },
};
pub fn civilian(name: []const u8) ?u8 {
    for (civilians, 0..) |entry, i| if (@import("std").mem.eql(u8, name, entry.classname)) return @intCast(i);
    return null;
}
