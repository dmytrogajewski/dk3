// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 13;
pub const spec: profiles.Spec = .{
    .protects_water = true,
    .ammo_class = "ammo_tritips", // trident
    .ammo_pack = 30,
    .projectile = .{ .direct_scale = 0, .splash_scale = 1, .splash_radius = 100 },
    .visual = .{ .projectile_model = "models/e2/we_tritip.dkm", .color = .{ 0.4, 0.4, 0.9 }, .blast_sound = "global/e_wexplodee.wav", .glow = false },
    .world_model = "models/e2/a_tri.dkm",
    .animation = .{
        .view_model = "models/e2/w_trident.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", null, null },
        .raise_ms = 600,
        .drop_ms = 600,
    },
    .audio = .{
        .fire = "e2/we_tridentfirea.wav",
        .ready = "e2/we_tridentready.wav",
        .away = "e2/we_tridentaway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_trident", .label = "Trident of Poseidon", .episode = 2, .interval = 750 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.cost = @max(1, @min(3, controller.ps.ammo[id]));
    result.sequence = result.cost;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
