// SPDX-License-Identifier: GPL-2.0-or-later
//! Read-only concrete weapon descriptions, shared without linking legacy behavior.
pub const weapons = .{ @import("descriptions/disruptor.zig"), @import("descriptions/ion.zig"), @import("descriptions/c4.zig"), @import("descriptions/shotcycler.zig"), @import("descriptions/sidewinder.zig"), @import("descriptions/shockwave.zig"), @import("descriptions/gas_hands.zig"), @import("descriptions/sword.zig"), @import("descriptions/discus.zig"), @import("descriptions/sunflare.zig"), @import("descriptions/venom.zig"), @import("descriptions/hammer.zig"), @import("descriptions/trident.zig"), @import("descriptions/zeus.zig"), @import("descriptions/silverclaw.zig"), @import("descriptions/bolter.zig"), @import("descriptions/stavros.zig"), @import("descriptions/ballista.zig"), @import("descriptions/wyndrax.zig"), @import("descriptions/nightmare.zig"), @import("descriptions/glock.zig"), @import("descriptions/ripgun.zig"), @import("descriptions/slugger.zig"), @import("descriptions/kineticore.zig"), @import("descriptions/novabeam.zig"), @import("descriptions/metamaser.zig"), @import("descriptions/cordite.zig"), @import("descriptions/flashlight.zig") };
pub const Spec = @import("profiles.zig").Spec;
pub const ballistics = @import("ballistics.zig");
pub const melee = @import("melee.zig");
pub const affliction = @import("affliction.zig");
pub const ion = @import("descriptions/ion.zig");
pub const c4 = @import("descriptions/c4.zig");
pub const hammer = @import("descriptions/hammer.zig");
pub const shockwave = @import("descriptions/shockwave.zig");
pub const trident = @import("descriptions/trident.zig");
pub const ballista = @import("descriptions/ballista.zig");
pub const novabeam = @import("descriptions/novabeam.zig");
pub const flashlight = @import("descriptions/flashlight.zig");
pub const discus = @import("descriptions/discus.zig");
pub const sunflare = @import("descriptions/sunflare.zig");
pub const stavros = @import("descriptions/stavros.zig");
pub const zeus = @import("descriptions/zeus.zig");
pub const wyndrax = @import("descriptions/wyndrax.zig");
pub const nightmare = @import("descriptions/nightmare.zig");
pub const metamaser = @import("descriptions/metamaser.zig");
pub fn flightScale(id: u5, flags: i32) f32 {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "flightScale")) return W.flightScale(flags);
        return W.spec.visual.projectile_scale;
    };
    return 1;
}
pub fn combatFor(id: u5, sequence: i32) @import("profiles.zig").Combat {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "combatFor")) return W.combatFor(sequence);
        return W.spec.combat;
    };
    return .pending;
}
pub fn meleePlan(id: u5, sequence: i32, experience: i32) !melee.Plan {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "meleePlan")) return W.meleePlan(sequence, experience);
    };
    return error.MissingMeleePolicy;
}
pub fn meleeDamage(id: u5, hit: melee.Hit) melee.Damage {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "meleeDamage")) return W.meleeDamage(hit);
    };
    return .{ .amount = hit.damage };
}
pub fn swordExperience(id: u5, health: i32) i32 {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "swordExperience")) return W.swordExperience(health);
    };
    return 0;
}
pub fn fireSound(id: u5, sequence: i32, serial: u32) ?[:0]const u8 {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "fireSound")) return W.fireSound(sequence, serial);
        return W.spec.audio.fire;
    };
    return null;
}
pub fn attackAnimation(id: u5, sequence: i32, experience: i32) @import("profiles.zig").AttackAnimation {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "attackAnimation")) return W.attackAnimation(sequence, experience);
        const pose = if (sequence >= 0 and sequence < W.spec.animation.fire_variants.len) W.spec.animation.fire_variants[@intCast(sequence)] orelse W.spec.animation.fire else W.spec.animation.fire;
        return .{ .pose = pose, .rate = W.spec.animation.rate };
    };
    return .{ .pose = "", .rate = 20 };
}
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
pub fn flightDamage(id: u5, hit: ballistics.Hit) ballistics.Damage {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "flightDamage")) return W.flightDamage(hit);
        return .{ .amount = hit.damage * W.spec.projectile.direct_scale };
    };
    return .{ .amount = 0 };
}
pub fn flightLaunch(id: u5, tuning: values.Values, sequence: i32, attack: u8) ballistics.Launch {
    inline for (weapons) |W| if (id == W.id) {
        if (@hasDecl(W, "flightLaunch")) return W.flightLaunch(tuning, sequence, attack);
    };
    return .{ .muzzle = tuning.muzzle };
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
    for (weapons, 0..) |W, i| {
        if (W.spec.combat == .projectile and (!@hasDecl(W, "flight_tag") or !@hasDecl(W, "flightMotion") or !@hasDecl(W, "flightContact"))) @compileError("projectile class must own its flight/contact contract");
        if (W.spec.combat == .melee and !@hasDecl(W, "meleePlan")) @compileError("melee class must own its strike plan");
        result[i] = .{ .id = W.id, .classname = W.identity.classname, .label = W.identity.label, .episode = W.identity.episode, .interval = W.identity.interval, .spec = W.spec };
    }
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

test "melee classes own delayed windows, directional defense, immunities and sword rewards" {
    const std = @import("std");
    const claw = try meleePlan(15, 2, 0);
    try std.testing.expectEqual(@as(u16, 250), claw.delays_ms[0]);
    try std.testing.expect(claw.sound_on_strike and !claw.require_selected);
    const sword = try meleePlan(8, 9, 0);
    try std.testing.expectEqualSlices(u16, &.{ 252, 648 }, &sword.delays_ms);
    try std.testing.expectEqualSlices(u16, &.{ 140, 360 }, &(try meleePlan(8, 9, 3000)).delays_ms);
    try std.testing.expectError(error.InvalidSwordSwing, meleePlan(8, 3, 0));
    var hit: melee.Hit = .{ .damage = 40, .experience = 750, .victim_class = "monster_mishimaguard", .forward = .{ 1, 0, 0 }, .facing = .{ 1, 0, 0 }, .defending = false, .serial = 0 };
    try std.testing.expectEqual(@as(f32, 120), meleeDamage(8, hit).amount);
    hit.facing = .{ -1, 0, 0 };
    try std.testing.expectEqual(@as(f32, 60), meleeDamage(8, hit).amount);
    hit.defending = true;
    const parry = meleeDamage(8, hit);
    try std.testing.expectEqual(@as(f32, 30), parry.amount);
    try std.testing.expect(parry.sound != null);
    hit.victim_class = "monster_medusa";
    try std.testing.expectEqual(@as(f32, 0), meleeDamage(8, hit).amount);
    try std.testing.expectEqual(@as(i32, 5), swordExperience(8, 100));
    try std.testing.expectEqual(@as(i32, 0), swordExperience(15, 100));
}

test "Venomous owns alternate muzzles and bite poison; Kineticore ages and recovers speed" {
    const std = @import("std");
    const tuning: values.Values = .{ .muzzle = .{ -6, 30, 12 }, .alternate_muzzle = .{ 7, 30, 14 } };
    try std.testing.expectEqual([3]f32{ -6, 40, 12 }, flightLaunch(11, tuning, 0, 0).muzzle);
    try std.testing.expectEqual([3]f32{ 7, 40, 14 }, flightLaunch(11, tuning, 1, 0).muzzle);
    try std.testing.expect(combatFor(11, 128) == .melee);
    try std.testing.expect(combatFor(11, 0) == .projectile);
    const poison = flightDamage(11, .{ .damage = 30, .age_ms = 10, .lifetime_ms = 10000 });
    try std.testing.expectEqual(@as(u32, 5000), poison.effect.poison.duration_ms);
    try std.testing.expectEqual(@as(f32, 3), poison.effect.poison.damage);
    try std.testing.expectEqual(@as(f32, 14), flightDamage(24, .{ .damage = 12, .age_ms = 0, .lifetime_ms = 1500 }).amount);
    try std.testing.expectEqual(@as(f32, 8), flightDamage(24, .{ .damage = 12, .age_ms = 750, .lifetime_ms = 1500 }).amount);
    try std.testing.expectEqual(@as(f32, 5), flightDamage(24, .{ .damage = 12, .age_ms = 750, .lifetime_ms = 1500, .self_hit = true }).amount);
    var core = try flightState(24);
    var frame: ballistics.Frame = .{ .age_ms = 100, .delta_ms = 20, .distance = 10, .wet = false, .was_wet = false, .velocity = .{ 100, 0, 0 }, .speed = 300 };
    frame.velocity = (try flightMotion(24, &core, frame)).velocity;
    try std.testing.expectEqual(@as(f32, 200), frame.velocity[0]);
    try std.testing.expectEqual(@as(f32, 200), (try flightMotion(24, &core, frame)).velocity[0]);
    frame.age_ms = 200;
    try std.testing.expectEqual(@as(f32, 300), (try flightMotion(24, &core, frame)).velocity[0]);
    frame.age_ms = 2000000000;
    try std.testing.expectEqual(@as(f32, 300), (try flightMotion(24, &core, frame)).velocity[0]);
    var venom = try flightState(11);
    frame.wet = true;
    try std.testing.expect((try flightMotion(11, &venom, frame)).remove);
}

test "Discus steering clocks preserve return, drop and melee contracts" {
    const std = @import("std");
    var disc: discus.BallisticState = .{};
    try std.testing.expect(!disc.tick(99, true));
    try std.testing.expect(disc.tick(100, true));
    try std.testing.expectEqual(@as(f32, 750), disc.speed);
    try std.testing.expect(!disc.tick(100, true));
    try std.testing.expect(disc.tick(200, false));
    try std.testing.expectEqual(@as(f32, 937.5), disc.speed);
    disc.home(.{ 0, 10, 0 }, true);
    try std.testing.expectEqual([3]f32{ 0, 1, 0 }, disc.forward);
    try std.testing.expect(disc.mustDrop(5000));
    disc.drop(7, 5000);
    try std.testing.expect(disc.pickup_only and disc.dropped and disc.target == 7);
    try std.testing.expectEqual(@as(i64, 10000), disc.drop_ms);
    try std.testing.expect(combatFor(9, 128) == .melee);
    try std.testing.expectEqualStrings("shootd", attackAnimation(9, 129, 0).pose);
    try std.testing.expectEqual(@as(u16, 250), (try meleePlan(9, 128, 0)).delays_ms[0]);
    try std.testing.expectEqual([3]f32{ 10, 30, 15 }, discus.meleeOrigin(.{ 10, 20, 30 }, .{ 0, 10, 10 }, true));
}

test "Sunflare flame count owns damage radius and water equilibrium" {
    const std = @import("std");
    var flame: sunflare.BallisticState = .{};
    flame.ignite(500);
    try std.testing.expect(flame.phase == .settling);
    try std.testing.expectEqual(@as(f32, 12), flame.damage(4));
    flame.burn(600, 0.999);
    try std.testing.expectEqual(@as(u8, 9), flame.flames);
    try std.testing.expectEqual(@as(f32, 150), flame.radius());
    try std.testing.expectEqual(@as(f32, 18.75), flame.damage(4));
    const equilibrium = sunflare.buoyancy(.{ 0, 0, 0 }, 1.85 / 2.0, 1, 0.02);
    try std.testing.expectApproxEqAbs(@as(f32, 0), equilibrium[2], 0.0001);
    try std.testing.expect(sunflare.buoyancy(.{ 0, 0, 0 }, 1, 1, 0.02)[2] > 0);
    try std.testing.expect(sunflare.buoyancy(.{ 0, 0, 0 }, 0, 1, 0.02)[2] < 0);
}

test "Stavros growth preserves staged acceleration and multiplayer fragment suppression" {
    const std = @import("std");
    var meteor: stavros.BallisticState = .{ .maximum_speed = 525, .angular_delta = .{ 10, 20, 30 } };
    var angles: [3]f32 = @splat(0);
    var velocity: [3]f32 = .{ 26.25, 0, 0 };
    try std.testing.expectEqual(velocity, meteor.tick(99, velocity, &angles));
    velocity = meteor.tick(100, velocity, &angles);
    try std.testing.expectApproxEqAbs(@as(f32, 45.9375), velocity[0], 0.0001);
    try std.testing.expectEqual([3]f32{ 10, 20, 30 }, angles);
    try std.testing.expectEqual([3]f32{ -5, 5, 15 }, meteor.angular_delta);
    try std.testing.expectEqual(velocity, meteor.tick(100, velocity, &angles));
    for (2..9) |tick| velocity = meteor.tick(@intCast(tick * 100), velocity, &angles);
    try std.testing.expectApproxEqAbs(@as(f32, 1), meteor.scale[0], 0.0001);
    try std.testing.expect(velocity[0] > meteor.maximum_speed); // Gold accelerates without clamping the last multiplication.
    try std.testing.expectEqual(@as(u8, 6), stavros.fragments(true, 0.99));
    try std.testing.expectEqual(@as(u8, 0), stavros.fragments(false, 0.99));
    meteor.fragment = true;
    const scale = meteor.scale;
    try std.testing.expectEqual(velocity, meteor.tick(1000, velocity, &angles));
    try std.testing.expectEqual(scale, meteor.scale);
}

test "Zeus graph never revisits a target and attenuates damage by consumed zaps" {
    const std = @import("std");
    var chain: zeus.Chain = .{ .owner = 99, .damage = 300, .range = 1500, .ammo_cost = 1, .ready_ms = 1750, .expires_ms = 7250 };
    try std.testing.expect(chain.reserve(1));
    try std.testing.expect(!chain.reserve(1));
    for (2..21) |identity| try std.testing.expect(chain.reserve(@intCast(identity)));
    try std.testing.expect(!chain.reserve(21));
    for (0..20) |index| {
        const expected: f32 = if (index > 15) 75 else if (index > 10) 150 else if (index > 5) 225 else 300;
        try std.testing.expectEqual(expected, chain.zap());
    }
    try std.testing.expectEqual(@as(u8, 0), chain.active);
    try std.testing.expectEqual(@as(u8, 20), chain.zaps);
    try std.testing.expect(!chain.reserve(1));
    try std.testing.expectEqual(@as(u32, 875), zeus.releaseDelay(2));
}

test "Wisp retains four distinct targets, preserves the close orbit and ends its fade" {
    const std = @import("std");
    const Random = struct {
        pub fn next(_: *@This()) f32 {
            return 0.5;
        }
    };
    var random: Random = .{};
    var wisp: wyndrax.BallisticState = .{};
    for (1..5) |id| try std.testing.expect(wisp.include(@intCast(id)));
    wisp.targets[0] = 0;
    try std.testing.expect(!wisp.include(4)); // A hole must not duplicate a later target.
    try std.testing.expect(wisp.include(5));
    try std.testing.expect(!wisp.include(6));
    try std.testing.expectEqual(@as(f32, -150), wisp.steer(.{ 1, 0, 0 }, 63, &random)[0]);
    try std.testing.expectEqual(@as(f32, 0), wisp.steer(.{ 1, 0, 0 }, 64, &random)[0]);
    try std.testing.expectEqual(@as(f32, 150), wisp.steer(.{ 1, 0, 0 }, 100, &random)[0]);
    for (0..18) |_| try std.testing.expect(!wisp.fade());
    try std.testing.expect(wisp.fade());
}

test "Nightmare bounds the marked list and derives search and strike time from supplied frames" {
    const std = @import("std");
    var ritual: nightmare.Ritual = .{ .owner = 1, .damage = 300, .range = 2000, .born_ms = 0, .next_ms = 3200, .phase_ms = 0 };
    for (2..12) |id| try std.testing.expect(ritual.mark(@intCast(id)));
    try std.testing.expect(!ritual.mark(12));
    try std.testing.expect(!ritual.mark(2));
    try std.testing.expectEqual(@as(i64, 3200), nightmare.searchDelay(1));
    try std.testing.expectEqual(@as(i64, 1700), nightmare.searchDelay(2));
    ritual.advance(.reaping, 1000, nightmare.strike_ms);
    try std.testing.expectEqual(@as(i64, 5200), ritual.next_ms);
}

test "Metamaser locks, charges and destruction bands retain class limits" {
    const std = @import("std");
    var cube: metamaser.BallisticState = .{ .charges = 6, .end_ms = 19000 };
    cube.settle(800);
    try std.testing.expectEqual(@as(i64, 3800), cube.arm_ms);
    for (1..13) |id| try std.testing.expect(cube.include(@intCast(id), 1000));
    try std.testing.expect(!cube.include(13, 1000));
    for (1..5) |id| try std.testing.expect(cube.lock(@intCast(id), 1100, 0.5));
    try std.testing.expect(!cube.lock(5, 1100, 0.5));
    try std.testing.expectEqual(@as(i64, 1850), cube.acquired[0].until_ms);
    cube.forget(1);
    try std.testing.expect(cube.lock(5, 1100, 0.5));
    cube.die(5000);
    try std.testing.expectEqual(@as(i64, 10000), cube.end_ms);
    cube.die(6000);
    try std.testing.expectEqual(@as(i64, 10000), cube.end_ms);
    try std.testing.expectEqual(@as(f32, 0), metamaser.ringDamage(40, 1000, 180, 0, false));
    const full = metamaser.ringDamage(40, 1000, 200, 0, false);
    try std.testing.expect(full > 0);
    try std.testing.expectEqual(full * 0.5, metamaser.ringDamage(40, 1000, 200, 0, true));
    try std.testing.expectEqual(@as(f32, 0), metamaser.ringDamage(40, 1000, 200, 64, false));
    for (entries) |entry| try std.testing.expect(entry.spec.combat != .pending);
}
