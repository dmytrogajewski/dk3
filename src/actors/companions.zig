// SPDX-License-Identifier: GPL-2.0-or-later
//! Party identity and explicit orders; shared weapon classes own combat rules.
pub const render_tag = 10029;
pub const Identity = enum { mikiko, superfly };
pub const Order = enum { follow, stay, attack, collect, move };
pub const Authored = enum { none, stop, teleport };
pub const pain_chance: u8 = 75;
pub const Voice = enum { pain, cold, drowning, burning, death, water_death, extreme_death };
pub fn voice(identity: Identity, kind: Voice, variation: u2) []const u8 {
    return switch (kind) {
        .pain => ([_][]const u8{ "pain1.wav", "pain2.wav", "pain3.wav", "pain4.wav" })[variation],
        .death => ([_][]const u8{ "death1.wav", "death2.wav", "death3.wav", "death4.wav" })[variation],
        .cold => if (variation % 2 == 0) "icehurt1.wav" else "icehurt2.wav",
        .drowning => if (identity == .mikiko) (if (variation % 2 == 0) "waterchoke2.wav" else "waterchoke3.wav") else (if (variation % 2 == 0) "waterchoke3.wav" else "waterchoke4.wav"),
        .burning => ([_][]const u8{ "death6.wav", "death7.wav", "death8.wav" })[@as(usize, variation) % 3],
        .water_death => "waterdeath.wav",
        .extreme_death => "udeath.wav",
    };
}
