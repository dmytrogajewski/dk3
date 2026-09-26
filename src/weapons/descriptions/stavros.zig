// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 17;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_stavros", // stavros
    .projectile = .{ .direct_scale = 0, .splash_scale = 1, .splash_radius = 200, .lifetime_ms = 12000, .loop_sound = "global/e_torchd.wav" },
    .visual = .{ .projectile_model = "models/e3/we_fball.dkm", .blast_sound = "global/e_explode1.wav" },
    .world_model = "models/e3/a_stav.dkm",
    .animation = .{
        .view_model = "models/e3/w_stavros.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 300,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e3/we_stavefire.wav",
        .ready = "e3/we_staveready.wav",
        .away = "e3/we_staveaway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_stavros", .label = "Stavros staff", .episode = 3, .interval = 900 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
