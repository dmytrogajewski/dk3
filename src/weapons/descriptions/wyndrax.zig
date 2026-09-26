// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 19;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_wisp", // wyndrax
    .visual = .{ .projectile_model = "models/e3/we_wisp.dkm", .color = .{ 0.25, 0.45, 0.85 }, .glow = false },
    .world_model = "models/e3/a_wyndrx.dkm",
    .animation = .{
        .view_model = "models/e3/w_wisp.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", null, null },
        .raise_ms = 600,
        .drop_ms = 400,
    },
    .audio = .{
        .fire = "e3/we_wwispshoota.wav",
        .ready = "e3/we_wwispready.wav",
        .away = "e3/we_wwispaway.wav",
    },
};
pub const identity = .{ .classname = "weapon_wyndrax", .label = "Wyndrax's wisp", .episode = 3, .interval = 1400 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
