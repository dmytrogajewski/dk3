// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 10;
pub const spec: profiles.Spec = .{ // sunflare
    .projectile = .{ .gravity = true },
    .visual = .{ .projectile_model = "models/e2/we_sunprj.dkm", .blast_sound = "e2/we_sflareexplodea.wav", .spin = true },
    .world_model = "models/e2/a_sflare.dkm",
    .animation = .{
        .view_model = "models/e2/w_sflare.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e2/we_sflareshoota.wav",
        .ready = "e2/we_sflareready.wav",
        .away = "e2/we_sflareaway.wav",
        .hum = "e2/we_sflareamba.wav",
        .idle = .{ "e2/we_sflareamba.wav", null, null },
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_sunflare", .label = "Sunflare", .episode = 2, .interval = 900 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
