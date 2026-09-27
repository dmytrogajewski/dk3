// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed actor policies; authored numeric tuning remains in supplied aidata.
pub const melee_cycle = @import("melee_cycle.zig");
pub const ragemaster = @import("ragemaster.zig");
pub const skeleton = @import("skeleton.zig");
pub const thief = @import("thief.zig");
pub const prisoners = @import("prisoners.zig");
pub const femgang = @import("femgang.zig");
pub const evasion = @import("evasion.zig");
pub const rocketmp = @import("rocketmp.zig");
pub const battleboar = @import("battleboar.zig");
pub const rocketgang = @import("rocketgang.zig");
pub const missiles = @import("missiles.zig");
pub const shafts = @import("shafts.zig");
pub const archers = @import("archers.zig");
pub const doombat = @import("doombat.zig");
pub const griffon = @import("griffon.zig");
pub const harpy = @import("harpy.zig");
pub const dragon = @import("dragon.zig");
pub const chaingang = @import("chaingang.zig");
pub const deathsphere = @import("deathsphere.zig");
pub const fireballs = @import("fireballs.zig");
pub const psyclaw = @import("psyclaw.zig");
pub const gunners = @import("gunners.zig");
pub const sludge = @import("sludge.zig");
pub const rotworm = @import("rotworm.zig");
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
pub const Kind = enum { civilian, mishima_guard, protopod, skeeter, froginator, thunderskeet, cambot, crox, rockgat, companion, ragemaster, skeleton, satyr, column, dwarf, lycanthir, spider, smallspider, cryotech, surgeon, labmonkey, inmater, lasergat, knight1, knight2, cerberus, piperat, plague_rat, shark, venomvermin, rotworm, centurion, fletcher, battleboar, rocketdude, rocketmp, thief, blackprisoner, whiteprisoner, femgang, sludgeminion, sealcaptain, sealcommando, sealgirl, uzigang, psyclaw, doombat, griffon, harpy, dragon, deathsphere, chaingang };
pub fn sequenceAttack(kind: Kind) bool {
    return groundAttack(kind) or kind == .doombat or kind == .griffon or kind == .harpy or kind == .dragon or kind == .deathsphere or kind == .chaingang;
}
pub fn groundAttack(kind: Kind) bool {
    return switch (kind) {
        .ragemaster, .skeleton, .satyr, .column, .dwarf, .lycanthir, .spider, .smallspider, .cryotech, .labmonkey, .inmater, .lasergat, .knight1, .knight2, .cerberus, .piperat, .plague_rat, .shark, .venomvermin, .rotworm, .centurion, .fletcher, .battleboar, .rocketdude, .rocketmp, .thief, .blackprisoner, .whiteprisoner, .femgang, .sludgeminion, .sealcaptain, .sealcommando, .sealgirl, .uzigang, .psyclaw => true,
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
    .{ .classname = "monster_rotworm", .kind = .rotworm },
    .{ .classname = "monster_centurion", .kind = .centurion },
    .{ .classname = "monster_fletcher", .kind = .fletcher },
    .{ .classname = "monster_battleboar", .kind = .battleboar },
    .{ .classname = "monster_rocketdude", .kind = .rocketdude },
    .{ .classname = "monster_rocketmp", .kind = .rocketmp },
    .{ .classname = "monster_thief", .kind = .thief },
    .{ .classname = "monster_blackprisoner", .kind = .blackprisoner },
    .{ .classname = "monster_whiteprisoner", .kind = .whiteprisoner },
    .{ .classname = "monster_femgang", .kind = .femgang },
    .{ .classname = "monster_sludgeminion", .kind = .sludgeminion },
    .{ .classname = "monster_sealcaptain", .kind = .sealcaptain },
    .{ .classname = "monster_sealcommando", .kind = .sealcommando },
    .{ .classname = "monster_sealgirl", .kind = .sealgirl },
    .{ .classname = "monster_uzigang", .kind = .uzigang },
    .{ .classname = "monster_psyclaw", .kind = .psyclaw },
    .{ .classname = "monster_doombat", .kind = .doombat, .run = "flya" },
    .{ .classname = "monster_griffon", .kind = .griffon, .run = "flya" },
    .{ .classname = "monster_harpy", .kind = .harpy, .run = "flya" },
    .{ .classname = "monster_dragon", .kind = .dragon, .idle = "hover", .run = "flya" },
    .{ .classname = "monster_deathsphere", .kind = .deathsphere, .run = "flya" },
    .{ .classname = "monster_chaingang", .kind = .chaingang, .run = "flya" },
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
    _ = rotworm;
    _ = sludge;
    _ = gunners;
    _ = psyclaw;
    _ = fireballs;
    _ = doombat;
    _ = griffon;
    _ = harpy;
    _ = dragon;
    _ = deathsphere;
    _ = chaingang;
    _ = archers;
    _ = missiles;
    _ = battleboar;
    _ = rocketgang;
    _ = rocketmp;
    _ = evasion;
    _ = thief;
    _ = prisoners;
    _ = femgang;
    _ = wander;
    _ = firefly;
    _ = column;
    _ = companions;
}
