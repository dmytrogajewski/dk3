// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 27;
pub const spec: profiles.Spec = .{
    .combat = .projectile,
    .splash_hazard = true,
    .ammo_class = "ammo_cordite", // cordite
    .projectile = .{ .direct_scale = 0, .splash_scale = 1, .splash_radius = 150, .lifetime_ms = 3000, .mins = @splat(-4), .maxs = .{ 4, 4, 12 } },
    .visual = .{ .projectile_model = "models/e4/we_ripgren.dkm", .blast_sound = "global/e_explode1.wav" },
    .world_model = "models/e4/a_cslug.dkm",
    .animation = .{
        .view_model = "models/e4/w_slugger.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shootb",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 250,
        .drop_ms = 250,
    },
    .audio = .{
        .fire = "e4/we_ripgunshootb.wav",
        .ready = "e4/we_ripgunready.wav",
        .away = "e4/we_ripgunaway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_cordite", .label = "Cordite", .episode = 4, .interval = 2000 };

const ballistic = @import("../ballistics.zig");
const vector = @import("../vector.zig");
pub const flight_tag = "cordite";
pub const BallisticState = struct {};
pub fn flightLaunch(_: @import("../values.zig").Values, _: i32, attack: u8) ballistic.Launch {
    return .{ .muzzle = .{ 10, 5, 15 }, .pitch = -5 / (1 + @as(f32, @floatFromInt(attack))) };
}
pub fn flightMotion(_: *BallisticState, frame: ballistic.Frame) ballistic.Motion {
    var velocity = frame.velocity;
    if (frame.wet) {
        const friction = @import("std").math.pow(f32, 0.5, @as(f32, @floatFromInt(frame.delta_ms)) / 100);
        velocity[0] *= friction;
        velocity[1] *= friction;
        if (@abs(velocity[2]) > 50) velocity[2] *= friction;
    }
    return .{ .velocity = velocity, .gravity = if (frame.age_ms >= 380) 800 else 0 };
}
pub fn flightContact(contact: ballistic.Contact) ballistic.Response {
    return if (contact.living) .explode else .{ .bounce = 0.6 };
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    if (context.detonation) return @import("../impact.zig").explosion(spec.visual, context);
    const sounds = [_][:0]const u8{ "e4/we_ripgunhita.wav", "e4/we_ripgunhitb.wav", "e4/we_ripgunhitc.wav", "e4/we_ripgunhitd.wav", "e4/we_ripgunhite.wav", "e4/we_ripgunhitf.wav" };
    return .{ .sound = sounds[context.serial % sounds.len] };
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
