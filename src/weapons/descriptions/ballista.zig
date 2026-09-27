// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 18;
pub const spec: profiles.Spec = .{
    .player_grip = .rifle,
    .combat = .ballista,
    .ammo_class = "ammo_ballista", // ballista
    .projectile = .{ .mins = .{ -4, -4, -2 }, .maxs = .{ 4, 4, 2 }, .splash_scale = 0.5, .splash_radius = 128, .action_delay_ms = 150, .recoil = 400, .recoil_on_launch = true, .loop_sound = "e3/we_ballistaflybya.wav" },
    .visual = .{ .projectile_model = "models/e3/we_balprj.dkm", .projectile_scale = 6, .fade_stuck = false, .color = .{ 0.4, 0.2, 0.1 } },
    .world_model = "models/e3/a_bal.dkm",
    .animation = .{
        .view_model = "models/e3/w_bal.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .raise_ms = 300,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e3/we_ballistafirea.wav",
        .ready = "e3/we_ballistaready.wav",
        .away = "e3/we_ballistaaway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_ballista", .label = "Ballista", .episode = 3, .interval = 2050 };

const shot_rules = @import("../shot.zig");
const v = @import("../vector.zig");
const flight = @import("../ballistics.zig");
pub const flight_tag = "ballista";
pub const BallisticState = struct {
    next_ms: i64 = 100,
    velocity: v.Vec = @splat(0),
    previous_position: v.Vec = @splat(0),
    victim: ?u32 = null,
    last_victim: ?u32 = null,
    release_ms: i64 = 0,
    releases: u8 = 0,
    normal: v.Vec = @splat(0),
};
pub fn flightMotion(_: *BallisticState, frame: flight.Frame) flight.Motion {
    return .{ .velocity = if (frame.age_ms == 0 and frame.delta_ms == 0 and frame.wet) v.scale(frame.velocity, 0.5) else frame.velocity };
}
pub fn holdMilliseconds(classname: []const u8, mass: f32) i64 {
    const std = @import("std");
    if (std.mem.eql(u8, classname, "monster_lycanthir") or std.mem.eql(u8, classname, "monster_buboid")) return 250;
    return if (mass >= 200) @intFromFloat(300000 / mass) else 1000;
}
pub fn midsection(offset: v.Vec, mins: v.Vec, maxs: v.Vec) bool {
    var inside: u8 = 0;
    for (0..3) |axis| if (@abs(offset[axis]) <= (maxs[axis] - mins[axis]) * 0.35) {
        inside += 1;
    };
    return inside >= 2;
}
pub fn canPin(forward: v.Vec, normal: v.Vec) bool {
    return @abs(normal[2]) <= 0.1 and v.dot(v.scale(forward, -1), normal) >= 0.85;
}
pub fn impact(_: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    return .{ .particles = 18, .color = .{ 0.5, 0.3, 0.1 }, .light_radius = 150, .light_ms = 150 };
}
test "ballista holds by mass and pins only square wall impacts" {
    const std = @import("std");
    try std.testing.expectEqual(@as(i64, 1500), holdMilliseconds("monster_test", 200));
    try std.testing.expectEqual(@as(i64, 250), holdMilliseconds("monster_buboid", 100));
    try std.testing.expect(midsection(.{ 20, 0, 8 }, .{ -16, -16, -24 }, .{ 16, 16, 32 }));
    try std.testing.expect(canPin(.{ 1, 0, 0 }, .{ -1, 0, 0 }));
    try std.testing.expect(!canPin(.{ 0, 0, -1 }, .{ 0, 0, 1 }));
}
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
