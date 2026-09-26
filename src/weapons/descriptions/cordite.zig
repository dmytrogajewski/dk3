// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 27;
pub const spec: profiles.Spec = .{
    .splash_hazard = true,
    .ammo_class = "ammo_cordite", // cordite
    .projectile = .{ .direct_scale = 0, .splash_scale = 1, .splash_radius = 150, .lifetime_ms = 3000 },
    .visual = .{ .projectile_model = "models/e4/we_ripgren.dkm", .blast_sound = "global/e_explode1.wav" },
    .world_model = "models/e4/a_cslug.dkm",
    .animation = .{
        .view_model = "models/e4/w_slugger.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shootb",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 250,
        .drop_ms = 250,
    },
    .audio = .{
        .fire = "e4/we_ripgunshootb.wav",
        .ready = "e4/we_ripgunready.wav",
        .away = "e4/we_ripgunaway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_cordite", .label = "Cordite", .episode = 4, .interval = 2000 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
