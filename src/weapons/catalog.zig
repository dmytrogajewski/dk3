// SPDX-License-Identifier: GPL-2.0-or-later
//! Read-only concrete weapon descriptions, shared without linking legacy behavior.
pub const weapons = .{ @import("descriptions/disruptor.zig"), @import("descriptions/ion.zig"), @import("descriptions/c4.zig"), @import("descriptions/shotcycler.zig"), @import("descriptions/sidewinder.zig"), @import("descriptions/shockwave.zig"), @import("descriptions/gas_hands.zig"), @import("descriptions/sword.zig"), @import("descriptions/discus.zig"), @import("descriptions/sunflare.zig"), @import("descriptions/venom.zig"), @import("descriptions/hammer.zig"), @import("descriptions/trident.zig"), @import("descriptions/zeus.zig"), @import("descriptions/silverclaw.zig"), @import("descriptions/bolter.zig"), @import("descriptions/stavros.zig"), @import("descriptions/ballista.zig"), @import("descriptions/wyndrax.zig"), @import("descriptions/nightmare.zig"), @import("descriptions/glock.zig"), @import("descriptions/ripgun.zig"), @import("descriptions/slugger.zig"), @import("descriptions/kineticore.zig"), @import("descriptions/novabeam.zig"), @import("descriptions/metamaser.zig"), @import("descriptions/cordite.zig"), @import("descriptions/flashlight.zig") };
pub const Spec = @import("profiles.zig").Spec;
pub const ballistics = @import("ballistics.zig");
pub fn flightState(id: u5) !ballistics.State {
    inline for (weapons) |W| if (id == W.id) {
        if (W.spec.combat == .ion) return .ion;
        if (@hasDecl(W, "flight_tag")) return @unionInit(ballistics.State, W.flight_tag, .{});
    };
    return error.MissingProjectilePolicy;
}
pub fn flightMotion(id: u5, state: *ballistics.State, frame: ballistics.Frame) !ballistics.Motion {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "flight_tag")) {
            if (state.* != @field(@import("std").meta.Tag(ballistics.State), W.flight_tag)) return error.InvalidProjectileState;
            return W.flightMotion(&@field(state, W.flight_tag), frame);
        }
    };
    return error.MissingProjectilePolicy;
}
pub fn flightContact(id: u5, contact: ballistics.Contact) !ballistics.Response {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "flightContact")) return W.flightContact(contact);
    };
    return error.MissingProjectilePolicy;
}
pub fn flightLaunch(id: u5, offset: [3]f32, sequence: i32, attack: u8) ballistics.Launch {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "flightLaunch")) return W.flightLaunch(sequence, attack);
    };
    return .{ .muzzle = offset };
}
pub const impact_rules = @import("impact.zig");
pub fn impact(id: u5, context: impact_rules.Context) impact_rules.Cue {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "impact")) return W.impact(context);
        return impact_rules.standard(W.spec.impact, context);
    };
    return .{};
}
pub const Entry = struct { id: u5, classname: [:0]const u8, label: [:0]const u8, episode: u8, interval: i32, spec: Spec };
pub const entries = blk: {
    var result: [weapons.len]Entry = undefined;
    for (weapons, 0..) |W, i| result[i] = .{ .id = W.id, .classname = W.identity.classname, .label = W.identity.label, .episode = W.identity.episode, .interval = W.identity.interval, .spec = W.spec };
    break :blk result;
};
pub fn find(id: u5) ?*const Entry {
    for (&entries) |*entry| if (entry.id == id) return entry;
    return null;
}
pub fn starting(episode: u8) u5 {
    for (entries) |entry| if (entry.spec.start_episode == episode) return entry.id;
    return 1;
}

pub fn update(controller: anytype) void {
    inline for (weapons) |W| if (controller.ps.weapon == W.id) {
        W.update(controller);
        return;
    };
}
pub fn isReloading(ps: anytype) bool {
    inline for (weapons) |W| if (ps.weapon == W.id) {
        if (@hasDecl(W, "isReloading")) return W.isReloading(ps);
        return false;
    };
    return false;
}
pub const presentation = @import("presentation.zig");

pub const transitions = @import("controller.zig");
pub const Shot = @import("shot.zig").Shot;

pub const values = @import("values.zig");

pub const gas = @import("gas_rules.zig");

pub const character = @import("character_rules.zig");
test {
    _ = presentation;
    _ = transitions;
    _ = gas;
    _ = character;
    _ = values;
    _ = @import("sword_rules.zig");
    inline for (weapons) |W| _ = W;
}

test "projectile classes retain water/acceleration state and grenade damping is time invariant" {
    const std = @import("std");
    var rocket = try flightState(5);
    var frame: ballistics.Frame = .{ .age_ms = 0, .delta_ms = 0, .distance = 0, .wet = true, .was_wet = false, .velocity = .{ 900, 0, 0 } };
    try std.testing.expectEqual(@as(f32, 300), (try flightMotion(5, &rocket, frame)).velocity[0]);
    frame.age_ms = 600;
    frame.distance = 600;
    frame.velocity[0] = 300;
    frame.wet = false;
    try std.testing.expectEqual(@as(f32, 300), (try flightMotion(5, &rocket, frame)).velocity[0]);
    var dry = try flightState(5);
    frame.velocity[0] = 900;
    try std.testing.expectEqual(@as(f32, 1800), (try flightMotion(5, &dry, frame)).velocity[0]);
    frame.velocity[0] = 1800;
    try std.testing.expectEqual(@as(f32, 1800), (try flightMotion(5, &dry, frame)).velocity[0]);
    var grenade = try flightState(27);
    frame = .{ .age_ms = 400, .delta_ms = 100, .distance = 100, .wet = true, .was_wet = true, .velocity = .{ 400, 400, 40 } };
    const whole = try flightMotion(27, &grenade, frame);
    frame.delta_ms = 20;
    for (0..5) |_| frame.velocity = (try flightMotion(27, &grenade, frame)).velocity;
    try std.testing.expectApproxEqAbs(whole.velocity[0], frame.velocity[0], 0.001);
    try std.testing.expectEqual(@as(f32, 40), frame.velocity[2]);
    try std.testing.expectEqual(@as(f32, 800), whole.gravity);
    try std.testing.expectError(error.InvalidProjectileState, flightMotion(16, &rocket, frame));
    try std.testing.expectEqual(ballistics.Response.direct, try flightContact(16, .{ .damageable = true, .living = true, .brush = false }));
    try std.testing.expectEqual(ballistics.Response.remove, try flightContact(16, .{ .damageable = false, .living = false, .brush = true }));
}
