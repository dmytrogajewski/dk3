// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed actor policies; authored numeric tuning remains in supplied aidata.
test "actor presentation owners have distinct render tags" {
    const std = @import("std");
    const declarations = comptime std.meta.declarations(@This());
    inline for (declarations, 0..) |declaration, index| {
        const owner = @field(@This(), declaration.name);
        if (@TypeOf(owner) == type) {
            if (@typeInfo(owner) == .@"struct" and @hasDecl(owner, "render_tag")) {
                inline for (declarations[0..index]) |earlier| {
                    const other = @field(@This(), earlier.name);
                    if (@TypeOf(other) == type) {
                        if (@typeInfo(other) == .@"struct" and @hasDecl(other, "render_tag")) {
                            if (owner.render_tag == other.render_tag) std.debug.print("Duplicate actor render tag: {s} / {s}\n", .{ declaration.name, earlier.name });
                            try std.testing.expect(owner.render_tag != other.render_tag);
                        }
                    }
                }
            }
        }
    }
}
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
pub const garroth = @import("garroth.zig");
pub const medusa = @import("medusa.zig");
pub const nharre = @import("nharre.zig");
pub const kage = @import("kage.zig");
pub const ghost = @import("ghost.zig");
pub const summon_effect = @import("summon_effect.zig");
pub const mikiko = @import("mikiko.zig");
pub const sword_aura_tag = 10023;
pub const stavros = @import("stavros.zig");
pub const meteors = @import("meteors.zig");
pub const wyndrax = @import("wyndrax.zig");
pub const wisp = @import("wisp.zig");
pub const buboid = @import("buboid.zig");
pub const chaingang = @import("chaingang.zig");
pub const deathsphere = @import("deathsphere.zig");
pub const fireballs = @import("fireballs.zig");
pub const psyclaw = @import("psyclaw.zig");
pub const gunners = @import("gunners.zig");
pub const sludge = @import("sludge.zig");
pub const rotworm = @import("rotworm.zig");
pub const vermin = @import("vermin.zig");
pub const fish = @import("fish.zig");
pub const seagull = @import("seagull.zig");
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
pub const perception = @import("perception.zig");
pub const fragments = @import("fragments.zig");
pub const skeeter = @import("skeeter.zig");
pub const froginator = @import("froginator.zig");
pub const thunderskeet = @import("thunderskeet.zig");
pub const rockgat = @import("rockgat.zig");
pub const crox = @import("crox.zig");
pub const cambot = @import("cambot.zig");
pub const Kind = enum { civilian, mishima_guard, protopod, skeeter, froginator, thunderskeet, cambot, crox, rockgat, companion, ragemaster, skeleton, satyr, column, dwarf, lycanthir, spider, smallspider, cryotech, surgeon, labmonkey, inmater, lasergat, knight1, knight2, cerberus, piperat, plague_rat, shark, venomvermin, rotworm, centurion, fletcher, battleboar, rocketdude, rocketmp, thief, blackprisoner, whiteprisoner, femgang, sludgeminion, sealcaptain, sealcommando, sealgirl, uzigang, psyclaw, doombat, griffon, harpy, dragon, deathsphere, chaingang, buboid, wyndrax, garroth, stavros, mikiko, medusa, kage, ghost, nharre, fish, dopefish, seagull };
pub fn sequenceAttack(kind: Kind) bool {
    return groundAttack(kind) or kind == .doombat or kind == .griffon or kind == .harpy or kind == .dragon or kind == .deathsphere or kind == .chaingang or kind == .buboid or kind == .wyndrax or kind == .garroth or kind == .stavros or kind == .mikiko or kind == .medusa or kind == .kage or kind == .ghost or kind == .nharre;
}
pub fn ambient(kind: Kind) bool {
    return kind == .fish or kind == .seagull;
}
pub fn aquatic(kind: Kind) bool {
    return kind == .shark or kind == .fish or kind == .dopefish;
}
pub fn groundAttack(kind: Kind) bool {
    return switch (kind) {
        .ragemaster, .skeleton, .satyr, .column, .dwarf, .lycanthir, .spider, .smallspider, .cryotech, .labmonkey, .inmater, .lasergat, .knight1, .knight2, .cerberus, .piperat, .plague_rat, .shark, .dopefish, .venomvermin, .rotworm, .centurion, .fletcher, .battleboar, .rocketdude, .rocketmp, .thief, .blackprisoner, .whiteprisoner, .femgang, .sludgeminion, .sealcaptain, .sealcommando, .sealgirl, .uzigang, .psyclaw => true,
        else => false,
    };
}
pub const Definition = struct {
    kind: Kind = .civilian,
    classname: []const u8,
    idle: []const u8 = "amba",
    run: []const u8 = "runa",
    death: []const u8 = "diea",
    nitro_immune: bool = false,
    companion_choices: [3]u2 = .{ 0, 1, 2 },
    witness_range: f32 = 512,
    panic_ms: i64 = 6000,
};
pub const entries = [_]Definition{
    .{ .classname = "monster_skinnyworker", .companion_choices = .{ 0, 0, 0 } },
    .{ .classname = "monster_fatworker", .companion_choices = .{ 0, 0, 0 } },
    .{ .classname = "monster_prisoner" },
    .{ .classname = "monster_prisonerb" },
    .{ .classname = "monster_mishimaguard", .kind = .mishima_guard },
    .{ .classname = "monster_protopod", .kind = .protopod, .run = "amba", .death = "hatcha" },
    .{ .classname = "monster_slaughterskeet", .companion_choices = .{ 1, 1, 2 }, .kind = .skeeter, .run = "flya", .death = "diea" },
    .{ .classname = "monster_froginator", .kind = .froginator },
    .{ .classname = "monster_thunderskeet", .companion_choices = .{ 1, 1, 2 }, .kind = .thunderskeet, .run = "flya" },
    .{ .classname = "monster_cambot", .companion_choices = .{ 1, 1, 2 }, .kind = .cambot, .run = "flya" },
    .{ .classname = "monster_crox", .nitro_immune = true, .kind = .crox },
    .{ .classname = "monster_rockgat", .nitro_immune = true, .kind = .rockgat, .idle = "up", .run = "up", .death = "up" },
    .{ .classname = "mikiko", .kind = .companion, .idle = "aamba" },
    .{ .classname = "superfly", .kind = .companion, .idle = "aamba" },
    .{ .classname = "mikikofly", .kind = .companion },
    .{ .classname = "monster_ragemaster", .nitro_immune = true, .kind = .ragemaster },
    .{ .classname = "monster_skeleton", .kind = .skeleton },
    .{ .classname = "monster_satyr", .kind = .satyr },
    .{ .classname = "monster_column", .nitro_immune = true, .companion_choices = .{ 0, 0, 0 }, .kind = .column },
    .{ .classname = "monster_dwarf", .kind = .dwarf },
    .{ .classname = "monster_lycanthir", .companion_choices = .{ 0, 0, 0 }, .kind = .lycanthir },
    .{ .classname = "monster_spider", .kind = .spider },
    .{ .classname = "monster_smallspider", .kind = .smallspider },
    .{ .classname = "monster_cryotech", .kind = .cryotech },
    .{ .classname = "monster_surgeon", .kind = .surgeon },
    .{ .classname = "monster_labmonkey", .kind = .labmonkey },
    .{ .classname = "monster_inmater", .nitro_immune = true, .kind = .inmater },
    .{ .classname = "monster_lasergat", .companion_choices = .{ 1, 1, 2 }, .kind = .lasergat, .idle = "shoota", .run = "shoota", .death = "shoota" },
    .{ .classname = "monster_knight1", .kind = .knight1 },
    .{ .classname = "monster_knight2", .kind = .knight2 },
    .{ .classname = "monster_cerberus", .kind = .cerberus },
    .{ .classname = "monster_piperat", .kind = .piperat },
    .{ .classname = "monster_plague_rat", .companion_choices = .{ 0, 1, 1 }, .kind = .plague_rat },
    .{ .classname = "monster_shark", .kind = .shark, .run = "swima" },
    .{ .classname = "monster_venomvermin", .nitro_immune = true, .kind = .venomvermin },
    .{ .classname = "monster_rotworm", .companion_choices = .{ 0, 1, 1 }, .kind = .rotworm },
    .{ .classname = "monster_centurion", .kind = .centurion },
    .{ .classname = "monster_fletcher", .kind = .fletcher },
    .{ .classname = "monster_battleboar", .nitro_immune = true, .kind = .battleboar },
    .{ .classname = "monster_rocketdude", .kind = .rocketdude },
    .{ .classname = "monster_rocketmp", .kind = .rocketmp },
    .{ .classname = "monster_thief", .kind = .thief },
    .{ .classname = "monster_blackprisoner", .kind = .blackprisoner },
    .{ .classname = "monster_whiteprisoner", .kind = .whiteprisoner },
    .{ .classname = "monster_femgang", .kind = .femgang },
    .{ .classname = "monster_sludgeminion", .nitro_immune = true, .kind = .sludgeminion },
    .{ .classname = "monster_sealcaptain", .kind = .sealcaptain },
    .{ .classname = "monster_sealcommando", .kind = .sealcommando },
    .{ .classname = "monster_sealgirl", .kind = .sealgirl },
    .{ .classname = "monster_uzigang", .kind = .uzigang },
    .{ .classname = "monster_psyclaw", .kind = .psyclaw },
    .{ .classname = "monster_doombat", .companion_choices = .{ 0, 1, 1 }, .kind = .doombat, .run = "flya" },
    .{ .classname = "monster_griffon", .kind = .griffon, .run = "flya" },
    .{ .classname = "monster_harpy", .kind = .harpy, .run = "flya" },
    .{ .classname = "monster_dragon", .kind = .dragon, .idle = "hover", .run = "flya" },
    .{ .classname = "monster_deathsphere", .nitro_immune = true, .companion_choices = .{ 1, 1, 2 }, .kind = .deathsphere, .run = "flya" },
    .{ .classname = "monster_chaingang", .kind = .chaingang, .run = "flya" },
    .{ .classname = "monster_buboid", .kind = .buboid },
    .{ .classname = "monster_wyndrax", .kind = .wyndrax },
    .{ .classname = "monster_garroth", .kind = .garroth },
    .{ .classname = "monster_stavros", .kind = .stavros, .run = "walka" },
    .{ .classname = "monster_mikiko", .kind = .mikiko },
    .{ .classname = "monster_medusa", .kind = .medusa },
    .{ .classname = "monster_kage", .kind = .kage },
    .{ .classname = "monster_ghost", .kind = .ghost, .run = "flya", .death = "flya" },
    .{ .classname = "monster_nharre", .kind = .nharre },
    .{ .classname = "e_goldfish", .kind = .fish, .run = "swima" },
    .{ .classname = "e_greyfish", .kind = .fish, .run = "swima" },
    .{ .classname = "e_guppy", .kind = .fish, .run = "swima" },
    .{ .classname = "e_guppy2", .kind = .fish, .run = "swima" },
    .{ .classname = "e_dopefish", .kind = .dopefish, .idle = "swima", .run = "swima" },
    .{ .classname = "e_seagull", .kind = .seagull, .idle = "stand", .run = "flya" },
};
pub fn find(name: []const u8) ?u8 {
    for (entries, 0..) |entry, i| if (@import("std").mem.eql(u8, name, entry.classname)) return @intCast(i);
    const aliases = .{
        .{ "fish_goldfish", "e_goldfish" }, .{ "goldfish", "e_goldfish" },
        .{ "fish_grayfish", "e_greyfish" }, .{ "e_grayfish", "e_greyfish" },
        .{ "fish_guppy1", "e_guppy" },      .{ "fish_guppy2", "e_guppy2" },
        .{ "fish_dopefish", "e_dopefish" },
    };
    inline for (aliases) |alias| if (@import("std").mem.eql(u8, name, alias[0])) return find(alias[1]);
    return null;
}

test "map fish aliases resolve to the supplied class tuning without becoming hostile wildlife" {
    const t = @import("std").testing;
    try t.expectEqual(find("e_greyfish").?, find("fish_grayfish").?);
    try t.expectEqual(find("e_guppy").?, find("fish_guppy1").?);
    try t.expect(ambient(entries[find("fish_goldfish").?].kind));
    try t.expect(ambient(entries[find("e_seagull").?].kind));
    try t.expect(!ambient(entries[find("fish_dopefish").?].kind));
    try t.expect(groundAttack(entries[find("fish_dopefish").?].kind));
}

test {
    _ = fish;
    _ = seagull;
    _ = nharre;
    _ = kage;
    _ = ghost;
    _ = summon_effect;
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
    _ = buboid;
    _ = wisp;
    _ = wyndrax;
    _ = garroth;
    _ = stavros;
    _ = mikiko;
    _ = medusa;
    _ = meteors;
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
