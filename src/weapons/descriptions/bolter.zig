// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 16;
pub const spec: profiles.Spec = .{
    .companion_episode = 3,
    .ammo_class = "ammo_bolts", // bolter
    .visual = .{ .projectile_model = "models/e3/we_bolt.dkm" },
    .world_model = "models/e3/a_bolter.dkm",
    .animation = .{
        .view_model = "models/e3/w_bolter.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 400,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e3/we_bolterfire.wav",
        .ready = "e3/we_bolterready.wav",
        .away = "e3/we_bolteraway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_bolter", .label = "Bolter", .episode = 3, .interval = 600 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.sequence = (controller.ps.dk3WeaponSequence ^ 1) & 1;
    result.cost = if (result.sequence == 1 and controller.ps.ammo[id] > 0) 0 else 1;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
