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
        // Superfly's set ends at death7 (Mikiko has death8).
        .burning => if (identity == .mikiko) ([_][]const u8{ "death6.wav", "death7.wav", "death8.wav" })[@as(usize, variation) % 3] else ([_][]const u8{ "death5.wav", "death6.wav", "death7.wav" })[@as(usize, variation) % 3],
        .water_death => "waterdeath.wav",
        .extreme_death => "udeath.wav",
    };
}

test "companion voices stay within each sidekick's recorded set" {
    const std = @import("std");
    // Superfly recorded death1-death7 and pain1-pain7; Mikiko death1-death8 and pain1-pain8.
    for ([_]Identity{ .mikiko, .superfly }) |identity| {
        const last: u8 = if (identity == .mikiko) '8' else '7';
        for (std.enums.values(Voice)) |kind| for (0..4) |variation| {
            const name = voice(identity, kind, @intCast(variation));
            if (std.mem.startsWith(u8, name, "death") or std.mem.startsWith(u8, name, "pain")) {
                const digit = name[std.mem.indexOfAny(u8, name, "0123456789").?];
                try std.testing.expect(digit <= last);
            }
        };
    }
}
