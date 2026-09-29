// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 8;
pub const spec: profiles.Spec = .{
    .player_grip = .pistol,
    .combat = .melee,
    .campaign_equipment = true,
    .world_model = "models/global/a_daikatana.dkm",
    // Frame 4's hilt runs from (1.6,-8.2,2.4) to (6.4,-6.3,9.9).
    .skeletal_grip_origin = .{ 4, -7.2, 6 },
    .audio = .{ .ready = "global/we_swordwhoosha.wav", .away = "global/we_swordwhooshc.wav" },
    .animation = .{
        .view_model = "models/global/w_daikatana.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "ataka",
        .scale_fire_rate = false,
        .idle = .{ "amba", null, null },
        .raise_ms = 600,
        .drop_ms = 500,
    },
};
pub const identity = .{ .classname = "weapon_daikatana", .label = "Daikatana", .episode = 0, .interval = 420 };

pub fn meleePlan(sequence: i32, experience: i32) !@import("../melee.zig").Plan {
    const index: usize = @intCast(sequence & 7);
    if (index >= sword.swings.len or sword.swings[index].hits == 0 or experience < 0) return error.InvalidSwordSwing;
    const swing = sword.swings[index];
    const milliseconds = sword.frameTime(experience);
    return .{ .hits = @intCast(swing.hits), .delays_ms = .{ @intCast(swing.damageFrame[0] * milliseconds), @intCast(swing.damageFrame[1] * milliseconds) }, .from = swing.from, .to = swing.to, .radius = 16 };
}
pub fn attackAnimation(sequence: i32, experience: i32) profiles.AttackAnimation {
    const index: usize = @intCast(sequence & 7);
    return .{ .pose = if (index < sword.swings.len) sword.swings[index].pose orelse spec.animation.fire else spec.animation.fire, .rate = @intCast(@divTrunc(1000, sword.frameTime(experience))) };
}
pub fn fireSound(_: i32, serial: u32) ?[:0]const u8 {
    const sounds = [_][:0]const u8{ "global/we_swordwhoosha.wav", "global/we_swordwhooshb.wav", "global/we_swordwhooshc.wav", "global/we_swordwhooshd.wav", "global/we_swordwhooshe.wav", "global/we_swordwhooshf.wav" };
    return sounds[serial % sounds.len];
}
pub fn meleeDamage(hit: @import("../melee.zig").Hit) @import("../melee.zig").Damage {
    const std = @import("std");
    const vector = @import("../vector.zig");
    for ([_][]const u8{ "monster_column", "monster_medusa", "monster_cerberus" }) |name| if (std.mem.eql(u8, name, hit.victim_class)) return .{ .amount = 0 };
    var forward = hit.forward;
    var facing = hit.facing;
    forward[2] = 0;
    facing[2] = 0;
    const alignment = vector.dot(vector.normal(forward), vector.normal(facing));
    var result: @import("../melee.zig").Damage = .{ .amount = hit.damage + @as(f32, @floatFromInt((sword.level(hit.experience) - 1) * 10)) };
    if (alignment >= 0.85) result.amount *= 2 else if (alignment <= -0.85 and hit.defending) {
        result.amount *= 0.5;
        const sounds = [_][:0]const u8{ "global/we_swordwclanka.wav", "global/we_swordwclankb.wav", "global/we_swordwclankc.wav", "global/we_swordwclankd.wav", "global/we_swordwclanke.wav" };
        result.sound = sounds[hit.serial % sounds.len];
    }
    return result;
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    const flesh = [_][:0]const u8{ "global/we_swordstaba.wav", "global/we_swordstabb.wav", "global/we_swordstabc.wav", "global/we_swordstabd.wav" };
    const solid = [_][:0]const u8{ "global/m_swordhita.wav", "global/m_swordhitb.wav", "global/m_swordhitc.wav", "global/m_swordhitd.wav", "global/m_swordhite.wav" };
    return .{ .sound = if (context.kind == .flesh) flesh[context.serial % flesh.len] else solid[context.serial % solid.len] };
}
pub fn swordExperience(health: i32) i32 {
    return @divTrunc(health, 20);
}

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn update(controller: anytype) void {
    const ps = controller.ps;
    if (!controller.pressed() and ps.dk3Burst == 0) {
        ps.dk3AttackHeld = 0;
        if (ps.weaponTime <= 0) {
            if (((ps.dk3WeaponSequence >> 3) & 15) != 0) {
                ps.dk3WeaponSequence &= 7;
                const factor: f32 = 1 - 0.1 * @as(f32, @floatFromInt(controller.boost()));
                ps.weaponTime += @intFromFloat(500 * factor);
            }
            ps.weaponstate = state.ready;
            ps.dk3NovaSpent = 0;
        }
        return;
    }
    ps.dk3AttackHeld = @intFromBool(controller.pressed());
    if (ps.weaponTime <= 0) fireSwing(controller);
}

fn fireSwing(controller: anytype) void {
    const ps = controller.ps;
    const level = sword.level(ps.dk3SwordExperience);
    const chain = (ps.dk3WeaponSequence >> 3) & 15;
    const previous = if (chain != 0) ps.dk3WeaponSequence & 7 else -1;
    const selected = if (chain >= 2 * level) -1 else sword.select(previous, @bitCast(controller.now()));
    if (selected < 0) {
        ps.dk3WeaponSequence &= 7;
        ps.weaponstate = state.ready;
        const factor: f32 = 1 - 0.1 * @as(f32, @floatFromInt(controller.boost()));
        ps.weaponTime += @intFromFloat(1000 * factor);
        return;
    }
    ps.dk3WeaponSequence = selected | ((chain + 1) << 3);
    ps.weaponstate = state.firing;
    controller.fireEvent();
    const duration = sword.swings[@intCast(selected)].followThrough * sword.frameTime(ps.dk3SwordExperience);
    ps.weaponTime += duration;
}
