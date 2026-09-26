// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 9;
pub const spec: profiles.Spec = .{ // discus
    .visual = .{ .projectile_model = "models/e2/we_discus.dkm", .spin = true },
    .world_model = "models/e2/a_discus.dkm",
    .animation = .{
        .view_model = "models/e2/w_discus.dkm",
        .ready = "readya",
        .away = "awaya",
        .fire = "shootb",
        .idle = .{ "amba", "ambb", null },
        .alternate = "shootc",
        .raise_ms = 400,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e2/we_discfire.wav",
        .ready = "e2/we_discreadya.wav",
        .away = "e2/we_discawaya.wav",
    },
    .projectile = .{ .loop_sound = "e2/we_discshoota.wav" },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_discus", .label = "Discus of Daedalus", .episode = 2, .interval = 650 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    if (controller.discusMelee()) {
        result.cost = 0;
        result.sequence = 128 + @mod(@divTrunc(controller.now(), 50), 2);
    }
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
