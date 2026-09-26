// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 7;
pub const spec: profiles.Spec = .{
    .equipped = false,
    .companion_pickup = false, // gashands
    .droppable = false,
    .world_model = "models/e1/a_gashand.dkm",
    .animation = .{
        .view_model = "models/e1/w_gashand.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shootb",
        .idle = .{ "amba", null, null },
        .alternate = "shootc",
        .raise_ms = 1550,
        .drop_ms = 1050,
    },
    .audio = .{
        .fire = "e1/we_gasloop.wav",
        .ready = "e1/we_gasstart.wav",
        .away = "e1/we_gasstopa.wav",
    },
};
pub const identity = .{ .classname = "weapon_gashands", .label = "Gas hands", .episode = 1, .interval = 900 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var shot = shot_rules.standard(controller);
    const seed: u32 = @bitCast(controller.now());
    shot.sequence = @intCast(((seed *% 1103515245 +% 12345) >> 16) & 1);
    return shot;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
