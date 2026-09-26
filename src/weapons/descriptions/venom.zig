// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 11;
pub const spec: profiles.Spec = .{
    .combat = .projectile,
    .projectile = .{ .mins = .{ -8, -8, -2 }, .maxs = .{ 8, 8, 14 }, .inertial = true, .lifetime_scale = 2, .action_delay_ms = 350, .contact_when_resting = true, .resting_lifetime_scale = 0.5 },
    .companion_episode = 2,
    .ammo_class = "ammo_venomous", // venom
    .visual = .{ .projectile_model = "models/e2/we_3dvenom.dkm", .resting_sprite = "models/e2/we_venstand.sp2", .sprite_additive = false, .impact_sprite = "models/e2/we_vendis.sp2", .color = .{ 0.35, 1, 0.2 }, .glow = false },
    .world_model = "models/e2/a_venom.dkm",
    .animation = .{
        .view_model = "models/e2/w_venomous.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .alternate = "melee",
        .raise_ms = 500,
        .drop_ms = 500,
    },
    .audio = .{
        .fire = "e2/we_venomshoota.wav",
        .ready = "e2/we_venomready.wav",
        .away = "e2/we_venomaway.wav",
        .variants = .{ "e2/we_venomshoota.wav", "e2/we_venomshootb.wav", "e2/we_venomshootc.wav" },
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_venomous", .label = "Venomous", .episode = 2, .interval = 450 };

const ballistic = @import("../ballistics.zig");
pub const flight_tag = "venom";
pub const BallisticState = struct {};
pub fn combatFor(sequence: i32) profiles.Combat {
    return if (sequence == 128) .melee else .projectile;
}
pub fn meleePlan(_: i32, _: i32) !@import("../melee.zig").Plan {
    return .{ .delays_ms = .{ 200, 0 }, .height = 4, .crouching_height = 4, .range = 150, .body_trace = true, .inertial = true, .scale_timing = true };
}
fn poison(damage: f32, duration_ms: u32, victim: []const u8) @import("../affliction.zig").Effect {
    if (@import("std").mem.eql(u8, victim, "monster_medusa")) return .none;
    return .{ .poison = .{ .damage = damage * 0.1, .duration_ms = duration_ms } };
}
pub fn meleeDamage(hit: @import("../melee.zig").Hit) @import("../melee.zig").Damage {
    return .{ .amount = hit.damage * 1.3, .effect = poison(hit.damage, hit.lifetime_ms, hit.victim_class) };
}
pub fn flightDamage(hit: ballistic.Hit) ballistic.Damage {
    return .{ .amount = hit.damage, .effect = poison(hit.damage, @intCast(@divTrunc(hit.lifetime_ms, 2)), hit.victim_class) };
}
pub fn flightLaunch(tuning: @import("../values.zig").Values, sequence: i32, attack: u8) ballistic.Launch {
    var muzzle = if (sequence & 1 == 0) tuning.muzzle else tuning.alternate_muzzle;
    muzzle[1] += 10;
    return .{ .muzzle = muzzle, .pitch = -5 / (1 + @as(f32, @floatFromInt(attack))) };
}
pub fn flightMotion(_: *BallisticState, frame: ballistic.Frame) ballistic.Motion {
    return .{ .velocity = frame.velocity, .gravity = 160, .remove = frame.wet };
}
pub fn flightContact(contact: ballistic.Contact) ballistic.Response {
    return if (contact.damageable) .direct else .{ .bounce = 0.6 };
}
pub fn attackAnimation(sequence: i32, _: i32) profiles.AttackAnimation {
    return .{ .pose = if (sequence == 128) "melee" else if (sequence & 1 == 0) "shoot" else "shoota", .rate = 20 };
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    const splashed = context.kind == .flesh or context.kind == .water;
    return .{ .sound = if (splashed) (if (context.serial & 1 == 0) "e2/we_venomdripa.wav" else "e2/we_venomdripb.wav") else "e2/we_venomhit.wav", .sprite = if (splashed) spec.visual.impact_sprite else null, .color = spec.visual.color };
}

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    if (controller.venomBite()) {
        result.cost = 0;
        result.sequence = 128;
    } else result.sequence = (controller.ps.dk3WeaponSequence + 1) & 1;
    result.duration_ms = controller.scaled(if (result.sequence == 128) 400 else 350) + 100;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
