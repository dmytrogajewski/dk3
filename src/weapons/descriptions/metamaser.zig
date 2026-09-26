// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 26;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_metamaser", // metamaser
    .projectile = .{ .gravity = true, .action_delay_ms = 300, .lifetime_ms = 19000 },
    .visual = .{ .projectile_model = "models/e4/we_mmprj.dkm", .impact_sprite = "models/e4/we_mmaserexp.sp2", .color = .{ 0.9, 0.2, 1 } },
    .world_model = "models/e4/a_mmaser.dkm",
    .animation = .{
        .view_model = "models/e4/w_mmaser.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", null, null },
        .raise_ms = 400,
        .drop_ms = 250,
    },
    .audio = .{
        .fire = "e2/we_sflareshoota.wav",
        .ready = "e4/we_metaready.wav",
        .away = "e4/we_metaaway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_metamaser", .label = "Metamaser", .episode = 4, .interval = 1000 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
