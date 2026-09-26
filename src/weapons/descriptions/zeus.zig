// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 14;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_zeus", // zeus
    .ammo_pack = 1,
    .companion_pickup = false,
    .visual = .{ .color = .{ 0.2, 0.65, 1 } },
    .world_model = "models/e2/a_zeus.dkm",
    .animation = .{
        .view_model = "models/e2/w_zeuseye.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ null, null, null },
        .raise_ms = 750,
        .drop_ms = 500,
    },
    .audio = .{
        .fire = "e2/we_zeusshoot.wav",
        .ready = "e2/we_zeusready.wav",
        .away = "e2/we_zeusaway.wav",
    },
};
pub const identity = .{ .classname = "weapon_zeus", .label = "Eye of Zeus", .episode = 2, .interval = 8000 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
