// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 16;
pub const spec: profiles.Spec = .{
    .combat = .projectile,
    .projectile = .{ .mins = @splat(-4), .maxs = @splat(4), .inertial = true },
    .companion_episode = 3,
    .ammo_class = "ammo_bolts", // bolter
    .visual = .{ .projectile_model = "models/e3/we_bolt.dkm", .projectile_scale = 2, .glow = false },
    .world_model = "models/e3/a_bolter.dkm",
    .animation = .{
        .view_model = "models/e3/w_bolter.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 400,
        .drop_ms = 300,
    },
    .audio = .{
        .fire = "e3/we_bolterfire.wav",
        .ready = "e3/we_bolterready.wav",
        .away = "e3/we_bolteraway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_bolter", .label = "Bolter", .episode = 3, .interval = 600 };

const ballistic = @import("../ballistics.zig");
const vector = @import("../vector.zig");
pub const flight_tag = "bolter";
pub const BallisticState = struct {};
pub fn flightMotion(_: *BallisticState, frame: ballistic.Frame) ballistic.Motion {
    var velocity = frame.velocity;
    if (frame.wet and !frame.was_wet) velocity = vector.scale(velocity, 0.5);
    if (!frame.wet and frame.was_wet and vector.length(velocity) > 1000) velocity = vector.scale(vector.normal(velocity), 1000);
    return .{ .velocity = velocity };
}
pub fn flightContact(contact: ballistic.Contact) ballistic.Response {
    if (contact.damageable) return .direct;
    return if (contact.brush) .remove else .{ .stick = 5000 };
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    return .{ .sound = switch (context.kind) {
        .flesh, .water => null,
        .metal => "e3/we_bolterhitmetal.wav",
        .wood => "e3/we_bolterhitwood.wav",
        else => "e3/we_bolterhit.wav",
    }, .particles = if (context.kind == .metal) 5 else 0, .color = .{ 0.8, 0.9, 1 } };
}

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.sequence = (controller.ps.dk3WeaponSequence ^ 1) & 1;
    result.cost = if (result.sequence == 1 and controller.ps.ammo[id] > 0) 0 else 1;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
