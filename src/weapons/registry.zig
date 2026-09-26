// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const c = @import("abi.zig").c;
pub const Disruptor = @import("types/disruptor.zig");
pub const Ion = @import("types/ion.zig");
pub const C4 = @import("types/c4.zig");
pub const Shotcycler = @import("types/shotcycler.zig");
pub const Sidewinder = @import("types/sidewinder.zig");
pub const Shockwave = @import("types/shockwave.zig");
pub const GasHands = @import("types/gas_hands.zig");
pub const Sword = @import("types/sword.zig");
pub const Discus = @import("types/discus.zig");
pub const Sunflare = @import("types/sunflare.zig");
pub const Venom = @import("types/venom.zig");
pub const Hammer = @import("types/hammer.zig");
pub const Trident = @import("types/trident.zig");
pub const Zeus = @import("types/zeus.zig");
pub const Silverclaw = @import("types/silverclaw.zig");
pub const Bolter = @import("types/bolter.zig");
pub const Stavros = @import("types/stavros.zig");
pub const Ballista = @import("types/ballista.zig");
pub const Wyndrax = @import("types/wyndrax.zig");
pub const Nightmare = @import("types/nightmare.zig");
pub const Glock = @import("types/glock.zig");
pub const Ripgun = @import("types/ripgun.zig");
pub const Slugger = @import("types/slugger.zig");
pub const Kineticore = @import("types/kineticore.zig");
pub const Novabeam = @import("types/novabeam.zig");
pub const Metamaser = @import("types/metamaser.zig");
pub const Cordite = @import("types/cordite.zig");
pub const Flashlight = @import("types/flashlight.zig");

pub const weapons = .{
    Disruptor, Ion,       C4,      Shotcycler, Sidewinder, Shockwave, GasHands,   Sword,
    Discus,    Sunflare,  Venom,   Hammer,     Trident,    Zeus,      Silverclaw, Bolter,
    Stavros,   Ballista,  Wyndrax, Nightmare,  Glock,      Ripgun,    Slugger,    Kineticore,
    Novabeam,  Metamaser, Cordite, Flashlight,
};

comptime {
    var seen: [c.DK_WEAPON_COUNT]bool = @splat(false);
    seen[c.DK_W_NONE] = true;
    for (weapons) |Weapon| {
        if (!@hasDecl(Weapon, "id") or !@hasDecl(Weapon, "spec") or
            !@hasDecl(Weapon, "update") or !@hasDecl(Weapon, "fire") or
            !@hasDecl(Weapon, "drawView") or !@hasDecl(Weapon, "drawWorld") or
            !@hasDecl(Weapon, "drawProjectile") or !@hasDecl(Weapon, "drawImpact") or
            !@hasDecl(Weapon, "viewCue") or !@hasDecl(Weapon, "audioCue") or
            !@hasDecl(Weapon, "impactCue") or
            !@hasDecl(Weapon, "blastSound"))
            @compileError("weapon type lacks the required interface");
        if (Weapon.id <= c.DK_W_NONE or Weapon.id >= c.DK_WEAPON_COUNT or seen[Weapon.id])
            @compileError("invalid or duplicate weapon ID");
        seen[Weapon.id] = true;
    }
    for (seen) |present| std.debug.assert(present);
}

pub fn update(weapon: c_int, controller: anytype) void {
    inline for (weapons) |Weapon| {
        if (weapon == Weapon.id) {
            Weapon.update(controller);
            return;
        }
    }
}

pub fn isReloading(ps: *const c.playerState_t) bool {
    inline for (weapons) |W| if (ps.weapon == W.id) {
        return if (@hasDecl(W, "isReloading")) W.isReloading(ps) else false;
    };
    return false;
}
pub fn inventoryPrediction(controller: anytype) void {
    inline for (weapons) |W| if (@hasDecl(W, "inventoryPrediction")) W.inventoryPrediction(controller);
}
