// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit transport mapping shared by authoritative and predicted movement.
const c = @import("abi.zig").c;
const move = @import("../domain/player_move.zig");
const data = @import("../domain/components.zig");
pub const version = "dk3-zig-" ++ @import("runtime_build").identity;
pub fn command(input: c.usercmd_t, delta: *[3]i32) move.Command {
    var angles: [3]f32 = undefined;
    for (&angles, 0..) |*angle, i| {
        var value: i16 = @truncate(input.angles[i] +% delta[i]);
        if (i == 0) {
            if (value > 16000) {
                value = 16000;
                delta[i] = 16000 -% input.angles[i];
            }
            if (value < -16000) {
                value = -16000;
                delta[i] = -16000 -% input.angles[i];
            }
        }
        angle.* = @as(f32, @floatFromInt(value)) * (360.0 / 65536.0);
    }
    return .{ .time_ms = input.serverTime, .weapon = input.weapon, .angles = angles, .forward = input.forwardmove, .right = input.rightmove, .up = input.upmove, .attack = input.buttons & c.BUTTON_ATTACK != 0, .use = input.buttons & c.BUTTON_USE_HOLDABLE != 0, .talking = input.buttons & c.BUTTON_TALK != 0 };
}
pub fn parameters(slot: u16) move.Parameters {
    return .{ .slot = slot, .mask = c.MASK_PLAYERSOLID, .water_mask = c.MASK_WATER, .solid_mask = c.CONTENTS_SOLID };
}
pub fn read(ps: *const c.playerState_t) move.Player {
    return .{ .command_ms = ps.commandTime, .delta_angles = ps.delta_angles, .mode = switch (ps.pm_type) {
        c.PM_NORMAL => .normal,
        c.PM_DEAD => .dead,
        c.PM_SPECTATOR => .spectator,
        c.PM_NOCLIP => .noclip,
        else => .frozen,
    }, .ducked = ps.pm_flags & c.PMF_DUCKED != 0, .jump_held = ps.pm_flags & c.PMF_JUMP_HELD != 0, .respawned = ps.pm_flags & c.PMF_RESPAWNED != 0, .view_height = @floatFromInt(ps.viewheight), .ground_entity = @intCast(ps.groundEntityNum), .timer = if (ps.pm_flags & c.PMF_TIME_WATERJUMP != 0) .water_jump else if (ps.pm_flags & c.PMF_TIME_KNOCKBACK != 0) .knockback else if (ps.pm_flags & c.PMF_TIME_LAND != 0) .land else .none, .timer_ms = @intCast(@max(0, ps.pm_time)) };
}
pub fn write(ps: *c.playerState_t, player: move.Player, transform: data.Transform, velocity: data.Velocity) void {
    ps.commandTime = @intCast(player.command_ms);
    ps.delta_angles = player.delta_angles;
    ps.pm_type = switch (player.mode) {
        .normal => c.PM_NORMAL,
        .dead => c.PM_DEAD,
        .spectator => c.PM_SPECTATOR,
        .noclip => c.PM_NOCLIP,
        .frozen => c.PM_FREEZE,
    };
    ps.pm_flags = 0;
    if (player.ducked) ps.pm_flags |= c.PMF_DUCKED;
    if (player.jump_held) ps.pm_flags |= c.PMF_JUMP_HELD;
    if (player.respawned) ps.pm_flags |= c.PMF_RESPAWNED;
    ps.pm_flags |= switch (player.timer) {
        .none => @as(i32, 0),
        .land => c.PMF_TIME_LAND,
        .knockback => c.PMF_TIME_KNOCKBACK,
        .water_jump => c.PMF_TIME_WATERJUMP,
    };
    ps.pm_time = @intCast(player.timer_ms);
    ps.origin = transform.position;
    ps.viewangles = transform.angles;
    ps.velocity = velocity.linear;
    ps.viewheight = @intFromFloat(player.view_height);
    ps.groundEntityNum = player.ground_entity;
}
pub fn readWeapons(ps: *const c.playerState_t) data.Weapons {
    var state: data.Weapons = .{};
    inline for (.{ "dk3Inventory", "ammo", "weapon", "weaponTime", "weaponstate", "dk3Burst", "dk3Charge", "dk3NovaSpent", "dk3WeaponSequence", "dk3AttackHeld", "dk3GlockClip", "dk3SwordExperience" }) |field| @field(state, field) = @field(ps, field);
    state.gas_until_ms = ps.powerups[c.PW_DK3_GASHANDS];
    state.event_sequence = @bitCast(ps.eventSequence);
    return state;
}
pub fn writeWeapons(ps: *c.playerState_t, state: data.Weapons) void {
    inline for (.{ "dk3Inventory", "ammo", "weapon", "weaponTime", "weaponstate", "dk3Burst", "dk3Charge", "dk3NovaSpent", "dk3WeaponSequence", "dk3AttackHeld", "dk3GlockClip", "dk3SwordExperience" }) |field| @field(ps, field) = @field(state, field);
    ps.powerups[c.PW_DK3_GASHANDS] = @intCast(state.gas_until_ms);
    ps.eventSequence = @bitCast(state.event_sequence);
}

pub fn characterParameters(slot: u16, character: data.Character, ailments: data.Ailments, now: i64) move.Parameters {
    var result = parameters(slot);
    result.speed = @floatFromInt(@as(i32, @intFromFloat(result.speed * @import("weapon_catalog").character.movementFactor(character.attribute(.speed, now)))));
    result.jump_speed *= @import("weapon_catalog").character.movementFactor(character.attribute(.acro, now));
    if (ailments.mask & 4 != 0) result.speed = @floatFromInt(@as(i32, @intFromFloat(result.speed * (1 - 0.8 * ailments.freeze_level))));
    if (ailments.mask & 128 != 0) result.speed = 0;
    return result;
}
pub fn readCharacter(ps: *const c.playerState_t) data.Character {
    var result: data.Character = .{ .attributes = ps.dk3Attributes, .invincible_until = ps.dk3InvincibleUntil, .invisible_until = ps.powerups[c.PW_INVIS], .environment_until = ps.dk3EnvUntil, .rings = @as(u32, @bitCast(ps.dk3Status)) & (16 | 32 | 64), .save_gems = ps.dk3SaveGems, .level = ps.dk3Level, .experience = ps.dk3Experience, .points = ps.dk3AttributePoints };
    for (&result.boost_until, ps.dk3BoostUntil) |*deadline, value| deadline.* = value;
    return result;
}
pub fn writeCharacter(ps: *c.playerState_t, character: data.Character, ailments: data.Ailments) void {
    ps.dk3Attributes = character.attributes;
    for (&ps.dk3BoostUntil, character.boost_until) |*deadline, value| deadline.* = @intCast(value);
    ps.dk3InvincibleUntil = @intCast(character.invincible_until);
    ps.powerups[c.PW_INVIS] = @intCast(character.invisible_until);
    ps.dk3EnvUntil = @intCast(character.environment_until);
    ps.dk3Status = @bitCast(character.rings | ailments.mask);
    ps.dk3FreezeLevel = ailments.freeze_level;
    ps.dk3SaveGems = character.save_gems;
    ps.dk3Level = character.level;
    ps.dk3Experience = character.experience;
    ps.dk3AttributePoints = character.points;
}

test "character projections round-trip and use integer speed with float jump scaling" {
    const std = @import("std");
    var character: data.Character = .{ .attributes = .{ 1, 2, 0, 0, 3 }, .boost_until = .{ 0, 0, 1000, 1000, 0 }, .rings = 16, .save_gems = 2 };
    var ps = std.mem.zeroes(c.playerState_t);
    writeCharacter(&ps, character, .{});
    try std.testing.expectEqualDeep(character, readCharacter(&ps));
    const boosted = characterParameters(0, character, .{}, 999);
    try std.testing.expectEqual(@as(f32, 345), boosted.speed);
    try std.testing.expectApproxEqAbs(@as(f32, 291.6), boosted.jump_speed, 0.001);
    try std.testing.expectEqual(@as(f32, 320), characterParameters(0, character, .{}, 1000).speed);
    character.attributes[2] = 5;
    try std.testing.expectEqual(@as(f32, 448), characterParameters(0, character, .{}, 1000).speed);
}
