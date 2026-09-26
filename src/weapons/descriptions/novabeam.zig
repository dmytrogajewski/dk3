// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 25;
pub const spec: profiles.Spec = .{
    .ammo_class = "ammo_novabeam", // novabeam
    .visual = .{ .impact_sprite = "models/e4/we_novahit.sp2" },
    .world_model = "models/e4/a_nova.dkm",
    .animation = .{
        .view_model = "models/e4/w_novabeam.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .alternate = "shootb",
        .raise_ms = 500,
        .drop_ms = 450,
    },
    .audio = .{
        .fire = "e4/we_novafirea.wav",
        .ready = "e4/we_novaready.wav",
        .away = "e4/we_novaaway.wav",
        .finish = "e4/we_novafireb.wav",
    },
};
pub const identity = .{ .classname = "weapon_novabeam", .label = "Novabeam", .episode = 4, .interval = 80 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.duration_ms = lifetime(controller.boost(), controller.lifetime(id)) + 200;
    if (controller.ps.ammo[id] >= controller.ammoCost(id)) result.cost = 0;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}

pub fn lifetime(boost: i32, seconds: f32) i32 {
    const duration = if (seconds > 0) seconds * 1000 else 2000;
    if (boost <= 0) return @intFromFloat(duration);
    return @intFromFloat(duration / (@as(f32, @floatFromInt(boost + 1)) * 0.5));
}
