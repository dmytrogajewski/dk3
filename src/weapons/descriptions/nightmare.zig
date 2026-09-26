// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 20;
pub const spec: profiles.Spec = .{ // nightmare
    .projectile = .{ .action_delay_ms = 800, .lifetime_ms = 3000 },
    .visual = .{ .projectile_model = "models/e3/we_nnreaper.dkm", .color = .{ 0.9, 0.2, 1 } },
    .world_model = "models/e3/a_nmare.dkm",
    .animation = .{
        .view_model = "models/e3/w_nmare.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", "ambb", "ambc" },
        .raise_ms = 750,
        .drop_ms = 500,
    },
    .audio = .{
        .fire = "e3/we_chant5.wav",
        .ready = "e3/we_nharreready.wav",
        .away = "e3/we_nharreaway.wav",
    },
};
pub const identity = .{ .classname = "weapon_nightmare", .label = "Nharre's Nightmare", .episode = 3, .interval = 60000 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
