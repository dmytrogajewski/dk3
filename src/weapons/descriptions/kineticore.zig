// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 24;
pub const spec: profiles.Spec = .{
    .player_grip = .shoulder,
    .combat = .projectile,
    .projectile = .{ .mins = @splat(-8), .maxs = @splat(8), .inertial = true, .recoil = 90, .collide_owner_after_bounce = true, .remove_when_resting = true, .loop_sound = "e4/we_kcoreflybya.wav" },
    .ammo_class = "ammo_kineticore", // kineticore
    .visual = .{ .projectile_model = "models/e4/we_kcoreshot.sp2", .projectile_sprite = "models/e4/we_kcoreshot.sp2", .projectile_scale = 0.8, .impact_sprite = "models/e4/we_kcorehitb.sp2", .color = .{ 0.2, 0.65, 1 } },
    .world_model = "models/e4/a_kcore.dkm",
    .animation = .{
        .view_model = "models/e4/w_kcore.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", "ambc" },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e4/we_kcoreshoota.wav",
        .ready = "e4/we_kcoreready.wav",
        .away = "e4/we_kcoreaway.wav",
    },
    .burst_shots = 5,
    .burst_recovery_ms = 1300,
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_kineticore", .label = "Kineticore", .episode = 4, .interval = 100 };

const ballistic = @import("../ballistics.zig");
pub const flight_tag = "kineticore";
pub const BallisticState = struct { recovered_ms: i64 = 0 };
pub fn flightMotion(extra: *BallisticState, frame: ballistic.Frame) ballistic.Motion {
    const vector = @import("../vector.zig");
    var velocity = frame.velocity;
    const ticks = @divTrunc(@max(0, frame.age_ms - extra.recovered_ms), 100);
    if (ticks > 0) {
        extra.recovered_ms += ticks * 100;
        const speed = vector.length(velocity);
        if (speed > 0 and speed < frame.speed) {
            const recovered = if (ticks >= 128) frame.speed else @min(frame.speed, speed * @import("std").math.pow(f32, 2, @as(f32, @floatFromInt(ticks))));
            velocity = vector.scale(vector.normal(velocity), recovered);
        }
    }
    return .{ .velocity = velocity };
}
pub fn flightContact(contact: ballistic.Contact) ballistic.Response {
    return if (contact.damageable) .direct else .{ .bounce = 1 };
}
pub fn flightDamage(hit: ballistic.Hit) ballistic.Damage {
    const remaining = @as(f32, @floatFromInt(@max(0, hit.lifetime_ms - hit.age_ms))) / @as(f32, @floatFromInt(@max(1, hit.lifetime_ms)));
    return .{ .amount = @max(5, (2 + hit.damage * remaining) * (if (hit.self_hit) @as(f32, 0.5) else 1)), .effect = .{ .freeze = 0.2 } };
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    return .{ .sound = "e4/we_kcorehita.wav", .sprite = if (context.kind == .flesh) spec.visual.impact_sprite else null, .particles = 8, .color = spec.visual.color };
}

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
