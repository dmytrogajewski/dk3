// SPDX-License-Identifier: GPL-2.0-or-later
const root = @import("root");
pub const Side = enum { shared, server, client };
pub const side: Side = if (@hasDecl(root, "weapon_side")) root.weapon_side else .shared;
pub const c = @cImport({
    @cDefine("DK3_GAME", "1");
    switch (side) {
        .server => @cInclude("g_local.h"),
        .client => {
            @cDefine("CGAME", "1");
            @cInclude("cg_local.h");
        },
        .shared => @cInclude("g_local.h"),
    }
    @cInclude("dk_weapons.h");
    @cInclude("dk_effects.h");
    @cInclude("dk_tables.h");
    @cInclude("dk_inventory.h");
});
