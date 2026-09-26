// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 2;
pub const spec: profiles.Spec = .{
    .combat = .{ .ion = .{ .radius = 2, .water_radius = 64, .bounce_retention = 1.25, .max_bounces = 3, .cleanup_ms = 30000 } },
    .companion_episode = 1,
    .ammo_class = "ammo_ionpack", // ion
    .ammo_pack = 50,
    .projectile = .{ .water_collision = true, .loop_sound = "e1/we_ionflyby.wav" },
    .visual = .{ .projectile_model = "models/e1/we_ionbl.dkm", .impact_sprite = "models/e1/we_ionexpl.sp2", .blast_sound = "e1/we_ionexplodea.wav", .color = .{ 0, 0.8, 0 } },
    .world_model = "models/e1/a_ion.dkm",
    .animation = .{
        .view_model = "models/e1/w_ionblaster.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 300,
        .drop_ms = 350,
    },
    .audio = .{
        .ammo_pickup = "global/i_ionammo.wav",
        .fire = "e1/we_ionshootb.wav",
        .ready = "e1/we_ionready.wav",
        .away = "e1/we_ionaway.wav",
        .hum = "e1/we_ionamba.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_ionblaster", .label = "Ion blaster", .episode = 1, .interval = 500 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
