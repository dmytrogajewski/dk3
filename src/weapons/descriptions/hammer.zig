// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 12;
pub const spec: profiles.Spec = .{
    .player_grip = .rifle,
    .combat = .hammer,
    .bot_charge_ms = 900,
    .bot_range = 110,
    .start_episode = 2, // hammer
    .visual = .{},
    .world_model = "models/e2/a_hammer.dkm",
    .animation = .{
        .view_model = "models/e2/w_hammer.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .rate = 40,
        .scale_fire_rate = false,
        .charge = .{ .max_frame = 18, .frame_ms = 100, .sound = "e2/we_hammerr.wav", .sound_ms = 500 },
        .idle = .{ null, null, null },
        .raise_ms = 300,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e2/we_hammerd.wav",
        .ready = "e2/we_hammerready.wav",
        .away = "e2/we_hammeraway.wav",
    },
};
pub const Action = struct {
    owner: u32,
    damage: f32,
    range: f32,
    charge_ms: i32,
    next_ms: i64,
    quake_until_ms: ?i64 = null,
};
pub const quake_visual = .{ .sprite = "models/e1/we_shockring.sp2", .rings = 6, .duration_ms = 750, .duration_step_ms = 75, .start_scale = 0.2, .end_scale = 60.0, .alpha = 102 };
pub fn chargeFrame(milliseconds: i32) f32 {
    return @as(f32, @floatFromInt(@import("std").math.clamp(milliseconds, 0, 1800))) / 100;
}
pub fn strikeDelay(milliseconds: i32) i64 {
    return @intFromFloat((23 - chargeFrame(milliseconds)) * 25);
}
pub fn chargeScale(milliseconds: i32) f32 {
    return chargeFrame(milliseconds) / 18;
}
pub fn quakeStrength(distance: f32, remaining_ms: i64, damage: f32, monster: bool) f32 {
    if (distance * 0.7 >= 450 or remaining_ms <= 0) return 0;
    return (450 - distance * 0.7) * 0.25 * (0.25 + @as(f32, @floatFromInt(@min(remaining_ms, 6000))) / 6000) * damage * 0.01 * (if (monster) @as(f32, 4) else 1);
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    const sounds = [_][:0]const u8{ "global/e_explodea.wav", "global/e_exploded.wav", "global/e_explodee.wav", "global/e_explodef.wav", "global/e_explodeg.wav", "global/e_explodel.wav", "global/e_explodem.wav" };
    return .{ .sound = sounds[context.serial % sounds.len], .mark = if (context.kind == .flesh or context.kind == .metal) null else "models/global/we_scorch.sp2/0@mark", .radius = 20, .particles = 12, .color = .{ 0.4, 0.2, 0.1 }, .light_radius = 250 };
}
test "hammer release timing and quake strength depend on charge and remaining time" {
    const std = @import("std");
    try std.testing.expectEqual(@as(i64, 125), strikeDelay(1800));
    try std.testing.expectEqual(@as(i64, 350), strikeDelay(900));
    try std.testing.expectEqual(@as(f32, 0.5), chargeScale(900));
    try std.testing.expectEqual(@as(f32, 0), quakeStrength(650, 6000, 100, true));
    try std.testing.expectEqual(quakeStrength(100, 6000, 100, false) * 4, quakeStrength(100, 6000, 100, true));
}
pub const identity = .{ .classname = "weapon_hammer", .label = "Hammer of Hephaestus", .episode = 2, .interval = 700 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var shot = shot_rules.standard(controller);
    shot.duration_ms = @as(i32, @intFromFloat((31 - chargeFrame(controller.ps.dk3Charge)) * 25)) + 50;
    return shot;
}

pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (controller.pressed()) {
        if (ps.dk3AttackHeld == 0 and ps.weaponTime > 0) return;
        if (ps.dk3AttackHeld == 0) ps.dk3Charge = 0;
        ps.dk3Charge = @min(ps.dk3Charge + controller.msec, 1800);
        ps.dk3AttackHeld = 1;
        return;
    }
    if (ps.dk3AttackHeld == 0) {
        controller.release();
        return;
    }
    if (ps.weaponTime <= 0) {
        ps.dk3AttackHeld = 0;
        controller.fire(@This(), predictionShot(controller));
    }
}
