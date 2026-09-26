// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 4;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_shells", // shotcycler
    .ammo_pack = 24,
    .world_model = "models/e1/a_shot.dkm",
    .animation = .{
        .view_model = "models/e1/w_shotcycler.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "ambc", null, null },
        .rate = 22,
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .ammo_pickup = "global/i_scyclerammo.wav",
        .fire = "e1/we_shotcyclershoota.wav",
        .ready = "e1/we_shotcyclerready.wav",
        .away = "e1/we_shotcycleraway.wav",
        .finish = "e1/we_shotcyclershootb.wav",
        .idle = .{ "e1/we_shotcycleramba.wav", null, null },
    },
    .burst_shots = 6,
    .burst_recovery_ms = 1800,
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_shotcycler", .label = "Shotcycler-6", .episode = 1, .interval = 270 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
