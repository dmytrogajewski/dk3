// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 5;
pub const spec: profiles.Spec = .{
    .combat = .projectile,
    .splash_hazard = true,
    .ammo_class = "ammo_rockets", // sidewinder
    .ammo_pack = 18,
    .burst_shots = 2,
    .burst_recovery_ms = 1150,
    .projectile = .{ .direct_scale = 0, .splash_scale = 1, .mins = @splat(-2), .maxs = @splat(2), .recoil = 90, .aim_range = 4000, .self_splash = 0.4 },
    .visual = .{ .projectile_model = "models/e1/we_swrocket.dkm", .projectile_scale = 1.5, .blast_sound = "e1/we_sidewinderexp.wav", .color = .{ 0.8, 0.4, 0.2 } },
    .world_model = "models/e1/a_swindr.dkm",
    .animation = .{
        .view_model = "models/e1/w_sidewinder.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .hold_fire = true,
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .ammo_pickup = "global/i_swinderammo.wav",
        .fire = "e1/we_sidewindershoota.wav",
        .ready = "e1/we_sidewinderready.wav",
        .away = "e1/we_sidewinderaway.wav",
        .idle = .{ "e1/we_sidewinderamba.wav", "e1/we_sidewinderamba.wav", null },
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_sidewinder", .label = "Sidewinder", .episode = 1, .interval = 1350 };

const ballistic = @import("../ballistics.zig");
const vector = @import("../vector.zig");
pub const flight_tag = "sidewinder";
pub const BallisticState = struct { accelerated: bool = false };
pub fn flightLaunch(_: @import("../values.zig").Values, sequence: i32, _: u8) ballistic.Launch {
    return .{ .muzzle = if (sequence == 0) .{ 10, 10, 9 } else .{ 10, 8, 11 }, .roll = if (sequence == 0) 90 else 0 };
}
pub fn flightMotion(state_value: *BallisticState, frame: ballistic.Frame) ballistic.Motion {
    var velocity = frame.velocity;
    if (!state_value.accelerated) {
        if (frame.age_ms == 0 and frame.wet) {
            velocity = vector.scale(velocity, 1.0 / 3.0);
            state_value.accelerated = true;
        } else if (frame.distance >= 400) {
            velocity = vector.scale(velocity, 2);
            state_value.accelerated = true;
        }
    }
    return .{ .velocity = velocity };
}
pub fn flightContact(_: ballistic.Contact) ballistic.Response {
    return .explode;
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    return @import("../impact.zig").explosion(spec.visual, context);
}

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var shot = shot_rules.standard(controller);
    shot.duration_ms = controller.scaled(100);
    shot.sequence = if (controller.ps.dk3Burst == 0) 0 else 1;
    return shot;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
