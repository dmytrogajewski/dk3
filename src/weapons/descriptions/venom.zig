// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 11;
pub const spec: profiles.Spec = .{
    .companion_episode = 2,
    .ammo_class = "ammo_venomous", // venom
    .visual = .{ .projectile_model = "models/e2/we_3dvenom.dkm", .impact_sprite = "models/e2/we_vendis.sp2", .color = .{ 0.35, 1, 0.2 } },
    .world_model = "models/e2/a_venom.dkm",
    .animation = .{
        .view_model = "models/e2/w_venomous.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .alternate = "melee",
        .raise_ms = 500,
        .drop_ms = 500,
    },
    .audio = .{
        .fire = "e2/we_venomshoota.wav",
        .ready = "e2/we_venomready.wav",
        .away = "e2/we_venomaway.wav",
        .variants = .{ "e2/we_venomshoota.wav", "e2/we_venomshootb.wav", "e2/we_venomshootc.wav" },
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_venomous", .label = "Venomous", .episode = 2, .interval = 450 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    if (controller.venomBite()) {
        result.cost = 0;
        result.sequence = 128;
    }
    result.duration_ms = controller.scaled(if (result.sequence == 128) 400 else 350) + 100;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
