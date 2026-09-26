// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 24;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_kineticore", // kineticore
    .visual = .{ .projectile_model = "models/e4/we_kcoreshot.sp2", .impact_sprite = "models/e4/we_kcorehitb.sp2", .color = .{ 0.2, 0.65, 1 } },
    .world_model = "models/e4/a_kcore.dkm",
    .animation = .{
        .view_model = "models/e4/w_kcore.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", "ambc" },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e4/we_kcoreshoota.wav",
        .ready = "e4/we_kcoreready.wav",
        .away = "e4/we_kcoreaway.wav",
    },
    .burst_shots = 5,
    .burst_recovery_ms = 1300,
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_kineticore", .label = "Kineticore", .episode = 4, .interval = 100 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
