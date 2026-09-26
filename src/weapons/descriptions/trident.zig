// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 13;
pub const spec: profiles.Spec = .{
    .combat = .trident,
    .protects_water = true,
    .ammo_class = "ammo_tritips", // trident
    .ammo_pack = 30,
    .projectile = .{ .mins = @splat(0), .maxs = @splat(0), .direct_scale = 0, .splash_scale = 1, .splash_radius = 100, .lifetime_ms = 60000 },
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
    .muzzle = .{ .model = "models/e2/we_mftrdnt.sp2", .sprite = true, .scale = 0.15, .color = .{ 0.8, 0.8, 1 } },
};
pub const identity = .{ .classname = "weapon_trident", .label = "Trident of Poseidon", .episode = 2, .interval = 750 };

const shot_rules = @import("../shot.zig");
const v = @import("../vector.zig");
const flight = @import("../ballistics.zig");
pub const flight_tag = "trident";
pub const Tip = enum { left, middle, right };
pub const BallisticState = struct {
    kind: Tip = .middle,
    leader: u32 = 0,
    left: u32 = 0,
    right: u32 = 0,
    forward: v.Vec = .{ 1, 0, 0 },
    right_axis: v.Vec = .{ 0, -1, 0 },
    next_ms: i64 = 100,
    reversed: bool = false,
    charged: bool = false,
    steering_speed: f32 = 0,
};
pub fn flightLaunch(tuning: @import("../values.zig").Values, sequence: i32, _: u8) flight.Launch {
    return .{ .muzzle = switch (sequence) {
        0 => tuning.muzzle,
        2 => tuning.third_muzzle,
        else => tuning.alternate_muzzle,
    } };
}
pub fn flightMotion(_: *BallisticState, frame: flight.Frame) flight.Motion {
    return .{ .velocity = frame.velocity };
}
pub fn outerVelocity(tip: *BallisticState, age: i64, speed: f32) v.Vec {
    const direction: f32 = (if (tip.kind == .left) @as(f32, -1) else 1) * (if (tip.reversed) @as(f32, -1) else 1);
    const result = v.add(v.scale(tip.forward, speed), v.scale(tip.right_axis, direction * 200));
    if (age >= 180) tip.reversed = true;
    return result;
}
pub fn blastDamage(base: f32, wet: bool, charged: bool) f32 {
    return base * (if (wet) @as(f32, 2) else 1) * (if (charged) @as(f32, 10) else 1);
}
pub fn flightScale(flags: i32) f32 {
    return 3 * (if (flags & 8 != 0) @as(f32, 2) else 1) * (if (flags & 16 != 0) @as(f32, 2) else 1);
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    if (context.trail) return .{ .sound = if (context.sequence & 1 == 0) "global/e_lightningb.wav" else "global/e_lightningc.wav", .color = .{ 0.4, 0.4, 0.9 }, .light_radius = 200, .light_ms = 200 };
    return .{ .sound = spec.visual.blast_sound, .sprite = "models/e1/we_shockring.sp2", .sprite_scale = if (context.charged) 3 else 1, .oriented = true, .alpha = 153, .additive = false, .color = .{ 0.4, 0.4, 0.9 }, .light_radius = 150, .light_ms = 200 };
}
test "trident reverses after expansion and combines water and charge bonuses" {
    const std = @import("std");
    var tip: BallisticState = .{ .kind = .left };
    try std.testing.expectEqual(v.Vec{ 1200, 200, 0 }, outerVelocity(&tip, 100, 1200));
    try std.testing.expectEqual(v.Vec{ 1200, 200, 0 }, outerVelocity(&tip, 200, 1200));
    try std.testing.expectEqual(v.Vec{ 1200, -200, 0 }, outerVelocity(&tip, 300, 1200));
    try std.testing.expectEqual(@as(f32, 400), blastDamage(20, true, true));
    const tuning: @import("../values.zig").Values = .{ .muzzle = .{ -14, 10, 12 }, .alternate_muzzle = .{ 1, 10, 18 }, .third_muzzle = .{ 15, 10, 16 } };
    try std.testing.expectEqual(tuning.third_muzzle, flightLaunch(tuning, 2, 0).muzzle);
}
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.cost = @max(1, @min(3, controller.ps.ammo[id]));
    result.sequence = result.cost;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
