// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 6;
pub const spec: profiles.Spec = .{
    .splash_hazard = true,
    .ammo_class = "ammo_shocksphere", // shockwave
    .ammo_pack = 1,
    .projectile = .{ .direct_scale = 3, .splash_scale = 0.75, .splash_radius = 300 },
    .visual = .{ .projectile_model = "models/e1/we_3dshock.dkm", .impact_sprite = "models/e1/we_shockexp.sp2", .blast_sound = "e1/we_shockwaveexp.wav", .color = .{ 1, 1, 1 }, .glow = false },
    .world_model = "models/e1/a_shokwv.dkm",
    .animation = .{
        .view_model = "models/e1/w_shockwave.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .raise_ms = 400,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e1/we_shockwaveshoota.wav",
        .ready = "e1/we_shockwaveready.wav",
        .away = "e1/we_shockwaveaway.wav",
        .hum = "e1/we_shockwaveamba.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_shockwave", .label = "Shockwave", .episode = 1, .interval = 2850 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
