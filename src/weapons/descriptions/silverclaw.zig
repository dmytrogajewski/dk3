// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 15;
pub const spec: profiles.Spec = .{
    .equipped = false,
    .start_episode = 3, // silverclaw
    .world_model = "models/e3/a_claw.dkm",
    .animation = .{
        .view_model = "models/e3/w_silverclaw.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", "ambc" },
        .raise_ms = 300,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e3/we_sclawshoota.wav",
        .ready = "e3/we_sclawready.wav",
        .away = "e3/we_sclawaway.wav",
        .variants = .{ "e3/we_sclawshoota.wav", "e3/we_sclawshootb.wav", "e3/we_sclawshootc.wav" },
    },
};
pub const identity = .{ .classname = "weapon_silverclaw", .label = "Silverclaw", .episode = 3, .interval = 950 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.sequence = @mod(@divTrunc(controller.now(), 7), 3);
    result.duration_ms = controller.scaled(([_]c_int{ 850, 600, 1000 })[@intCast(result.sequence)]) + 100;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
