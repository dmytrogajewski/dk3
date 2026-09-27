// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed actor policies; authored numeric tuning remains in supplied aidata.
pub const melee_cycle = @import("melee_cycle.zig");
pub const ragemaster = @import("ragemaster.zig");
pub const skeleton = @import("skeleton.zig");
pub const vermin = @import("vermin.zig");
pub const shark = @import("shark.zig");
pub const wander = @import("wander.zig");
pub const weapon = @import("weapon.zig");
pub const cerberus = @import("cerberus.zig");
pub const rats = @import("rats.zig");
pub const knights = @import("knights.zig");
pub const laser = @import("laser.zig");
pub const inmater = @import("inmater.zig");
pub const lasergat = @import("lasergat.zig");
pub const labmonkey = @import("labmonkey.zig");
pub const surgeon = @import("surgeon.zig");
pub const cryotech = @import("cryotech.zig");
pub const spider = @import("spider.zig");
pub const firefly = @import("firefly.zig");
pub const lycanthir = @import("lycanthir.zig");
pub const dwarf = @import("dwarf.zig");
pub const satyr = @import("satyr.zig");
pub const column = @import("column.zig");
pub const companions = @import("companions.zig");
pub const mishima = @import("mishima_guard.zig");
pub const protopod = @import("protopod.zig");
pub const skeeter = @import("skeeter.zig");
pub const froginator = @import("froginator.zig");
pub const thunderskeet = @import("thunderskeet.zig");
pub const rockgat = @import("rockgat.zig");
pub const crox = @import("crox.zig");
pub const cambot = @import("cambot.zig");
pub const Kind = enum { civilian, mishima_guard, protopod, skeeter, froginator, thunderskeet, cambot, crox, rockgat, companion, ragemaster, skeleton, satyr, column, dwarf, lycanthir, spider, smallspider, cryotech, surgeon, labmonkey, inmater, lasergat, knight1, knight2, cerberus, piperat, plague_rat, shark, venomvermin };
pub fn groundAttack(kind: Kind) bool {
    return switch (kind) {
        .ragemaster, .skeleton, .satyr, .column, .dwarf, .lycanthir, .spider, .smallspider, .cryotech, .labmonkey, .inmater, .lasergat, .knight1, .knight2, .cerberus, .piperat, .plague_rat, .shark, .venomvermin => true,
        else => false,
    };
}
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
    .{ .classname = "monster_protopod", .kind = .protopod, .run = "amba", .death = "hatcha" },
    .{ .classname = "monster_slaughterskeet", .kind = .skeeter, .run = "flya", .death = "diea" },
    .{ .classname = "monster_froginator", .kind = .froginator },
    .{ .classname = "monster_thunderskeet", .kind = .thunderskeet, .run = "flya" },
    .{ .classname = "monster_cambot", .kind = .cambot, .run = "flya" },
    .{ .classname = "monster_crox", .kind = .crox },
    .{ .classname = "monster_rockgat", .kind = .rockgat, .idle = "up", .run = "up", .death = "up" },
    .{ .classname = "mikiko", .kind = .companion, .idle = "aamba" },
    .{ .classname = "superfly", .kind = .companion, .idle = "aamba" },
    .{ .classname = "mikikofly", .kind = .companion },
    .{ .classname = "monster_ragemaster", .kind = .ragemaster },
    .{ .classname = "monster_skeleton", .kind = .skeleton },
    .{ .classname = "monster_satyr", .kind = .satyr },
    .{ .classname = "monster_column", .kind = .column },
    .{ .classname = "monster_dwarf", .kind = .dwarf },
    .{ .classname = "monster_lycanthir", .kind = .lycanthir },
    .{ .classname = "monster_spider", .kind = .spider },
    .{ .classname = "monster_smallspider", .kind = .smallspider },
    .{ .classname = "monster_cryotech", .kind = .cryotech },
    .{ .classname = "monster_surgeon", .kind = .surgeon },
    .{ .classname = "monster_labmonkey", .kind = .labmonkey },
    .{ .classname = "monster_inmater", .kind = .inmater },
    .{ .classname = "monster_lasergat", .kind = .lasergat, .idle = "shoota", .run = "shoota", .death = "shoota" },
    .{ .classname = "monster_knight1", .kind = .knight1 },
    .{ .classname = "monster_knight2", .kind = .knight2 },
    .{ .classname = "monster_cerberus", .kind = .cerberus },
    .{ .classname = "monster_piperat", .kind = .piperat },
    .{ .classname = "monster_plague_rat", .kind = .plague_rat },
    .{ .classname = "monster_shark", .kind = .shark, .run = "swima" },
    .{ .classname = "monster_venomvermin", .kind = .venomvermin },
};
pub fn find(name: []const u8) ?u8 {
    for (entries, 0..) |entry, i| if (@import("std").mem.eql(u8, name, entry.classname)) return @intCast(i);
    return null;
}

test {
    _ = mishima;
    _ = protopod;
    _ = skeeter;
    _ = froginator;
    _ = thunderskeet;
    _ = cambot;
    _ = crox;
    _ = rockgat;
    _ = melee_cycle;
    _ = ragemaster;
    _ = skeleton;
    _ = satyr;
    _ = dwarf;
    _ = lycanthir;
    _ = spider;
    _ = cryotech;
    _ = surgeon;
    _ = labmonkey;
    _ = inmater;
    _ = lasergat;
    _ = laser;
    _ = knights;
    _ = cerberus;
    _ = rats;
    _ = shark;
    _ = vermin;
    _ = wander;
    _ = firefly;
    _ = column;
    _ = companions;
}
