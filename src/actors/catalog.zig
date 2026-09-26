// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed actor policies; authored numeric tuning remains in supplied aidata.
pub const mishima = @import("mishima_guard.zig");
pub const Kind = enum { civilian, mishima_guard };
pub const Definition = struct {
    kind: Kind = .civilian,
    classname: []const u8,
    idle: []const u8 = "amba",
    run: []const u8 = "runa",
    death: []const u8 = "diea",
    witness_range: f32 = 512,
    panic_ms: i64 = 6000,
};
pub const entries = [_]Definition{
    .{ .classname = "monster_skinnyworker" },
    .{ .classname = "monster_fatworker" },
    .{ .classname = "monster_prisoner" },
    .{ .classname = "monster_prisonerb" },
    .{ .classname = "monster_mishimaguard", .kind = .mishima_guard },
};
pub fn find(name: []const u8) ?u8 {
    for (entries, 0..) |entry, i| if (@import("std").mem.eql(u8, name, entry.classname)) return @intCast(i);
    return null;
}

test {
    _ = mishima;
}
