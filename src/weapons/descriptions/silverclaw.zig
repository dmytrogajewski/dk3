// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 15;
pub const spec: profiles.Spec = .{
    .combat = .melee,
    .equipped = false,
    .start_episode = 3, // silverclaw
    .world_model = "models/e3/a_claw.dkm",
    .animation = .{
        .view_model = "models/e3/w_silverclaw.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .fire_variants = .{ "shoota", "shootb", "shootc", null },
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

pub fn meleePlan(_: i32, _: i32) !@import("../melee.zig").Plan {
    return .{ .delays_ms = .{ 250, 0 }, .height = 12, .crouching_height = -13, .sound_on_strike = true, .require_selected = false };
}
pub fn fireSound(sequence: i32, _: u32) ?[:0]const u8 {
    return spec.audio.variants[@intCast(@mod(sequence, 3))];
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    const flesh = context.kind == .flesh;
    return .{ .sound = if (flesh) "e3/we_sclawhit2.wav" else "e3/we_sclawhit1.wav", .mark = if (flesh or context.kind == .water) null else "models/global/we_clwmark2.sp2/0@mark", .radius = 9, .angle_degrees = ([_]f32{ 220, 135, 0 })[@intCast(@mod(context.sequence, 3))], .particles = if (flesh) 0 else 5, .color = .{ 0.8, 0.9, 1 } };
}

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
