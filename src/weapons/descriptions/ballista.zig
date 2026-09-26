// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 18;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_ballista", // ballista
    .projectile = .{ .splash_scale = 0.5, .splash_radius = 128 },
    .visual = .{ .projectile_model = "models/e3/we_balprj.dkm" },
    .world_model = "models/e3/a_bal.dkm",
    .animation = .{
        .view_model = "models/e3/w_bal.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .raise_ms = 300,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e3/we_ballistafirea.wav",
        .ready = "e3/we_ballistaready.wav",
        .away = "e3/we_ballistaaway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_ballista", .label = "Ballista", .episode = 3, .interval = 2050 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
