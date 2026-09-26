// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 1;
pub const spec: profiles.Spec = .{
    .equipped = false,
    .inventory_view_model = true,
    .start_episode = 1, // disruptor
    .world_model = "models/e1/a_tazer.dkm",
    .animation = .{
        .view_model = "models/e1/w_tglove.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 700,
        .drop_ms = 700,
    },
    .audio = .{
        .fire = "e1/we_dgloveshoota.wav",
        .ready = "e1/we_dgloveready.wav",
        .away = "e1/we_dgloveaway.wav",
        .idle = .{ "e1/we_dgloveamba.wav", "e1/we_dgloveambb.wav", null },
    },
};
pub const identity = .{ .classname = "weapon_disruptor", .label = "Disruptor", .episode = 1, .interval = 650 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    const seed: u32 = @bitCast(controller.now());
    result.sequence = @intCast(((seed *% 1103515245 +% 12345) >> 16) & 1);
    result.duration_ms = controller.scaled(if (result.sequence == 0) 600 else 500) + 100;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
