// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 3;
pub const spec: profiles.Spec = .{
    .splash_hazard = true,
    .ammo_class = "ammo_c4", // c4
    .projectile = .{ .gravity = true, .splash_scale = 1, .splash_radius = 300 },
    .visual = .{ .projectile_model = "models/e1/we_c4prj.dkm", .blast_sound = "global/e_explode1.wav", .color = .{ 1, 0.5, 0 }, .glow = false },
    .companion_pickup = false,
    .world_model = "models/e1/a_c4.dkm",
    .animation = .{
        .view_model = "models/e1/w_c4.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e1/we_c4shoota.wav",
        .ready = "e1/we_c4ready.wav",
        .away = "e1/we_c4away.wav",
        .idle = .{ null, "e1/we_c4ambb.wav", null },
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_c4", .label = "C4 Vizatergo", .episode = 1, .interval = 1350 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
