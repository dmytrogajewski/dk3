// SPDX-License-Identifier: GPL-2.0-or-later
//! Body poses retain each character's supplied grip and carrying sequences.
const animation = @import("animation.zig");
const std = @import("std");
const catalog = @import("weapon_catalog");
pub const Playback = struct {
    sequence: animation.Sequence,
    started: i64,
    looping: bool = true,
    pub fn frame(self: Playback, now: i64) u16 {
        return self.sequence.frame(now - self.started, self.looping);
    }
};

test "companion cues share the published shot and jump clocks without restarting movement" {
    const poses: Set = .{
        .idle = @splat(.{ .first = 0, .last = 9 }),
        .run = @splat(.{ .first = 10, .last = 19 }),
        .jump = @splat(.{ .first = 20, .last = 29 }),
        .attack = @splat(.{ .first = 30, .last = 39 }),
        .crouch = @splat(.{ .first = 40, .last = 49 }),
        .crouch_walk = @splat(.{ .first = 50, .last = 59 }),
        .crouch_attack = @splat(.{ .first = 60, .last = 69 }),
        .swim = .{ .first = 70, .last = 79 },
    };
    const firing = poses.select(0, false, false, false, false, 500, 1000, 0, 1200);
    try std.testing.expectEqual(@as(u16, 32), firing.frame(1200));
    try std.testing.expectEqual(@as(i64, 1000), firing.started);
    try std.testing.expect(!firing.looping);
    const second = poses.select(0, false, false, true, false, 500, 1500, 0, 1700);
    try std.testing.expectEqual(@as(u16, 62), second.frame(1700));
    try std.testing.expectEqual(@as(i64, 1500), second.started);
    const running = poses.select(0, true, false, false, false, 500, 1000, 0, 1200);
    try std.testing.expectEqual(@as(u16, 12), running.frame(1200));
    try std.testing.expect(running.looping);
    const jumping = poses.select(0, false, true, false, false, 500, 1000, 0, 1200);
    try std.testing.expectEqual(@as(u16, 27), jumping.frame(1200));
    try std.testing.expect(!jumping.looping);
}
pub const Set = struct {
    idle: [3]animation.Sequence,
    run: [3]animation.Sequence,
    jump: [3]animation.Sequence,
    attack: [3]animation.Sequence,
    crouch: [3]animation.Sequence,
    crouch_walk: [3]animation.Sequence,
    crouch_attack: [3]animation.Sequence,
    swim: ?animation.Sequence,
    pain: [3]?animation.Sequence = @splat(null),
    pub fn read(bytes: []const u8, carrying: bool) !Set {
        var result: Set = undefined;
        result.swim = if (carrying) null else try animation.find(bytes, "swim") orelse return error.MissingCompanionSwim;
        for (0..3) |grip| {
            var buffer: [32]u8 = undefined;
            const suffix = if (grip == 0) "" else if (grip == 1) "a" else "b";
            result.pain[grip] = try animation.find(bytes, if (grip == 2) "hitb" else "hita");
            result.idle[grip] = try animation.find(bytes, if (carrying) "amba" else try std.fmt.bufPrint(&buffer, "aamb{s}", .{suffix})) orelse return error.MissingCompanionIdle;
            result.run[grip] = try animation.find(bytes, if (carrying) "runa" else try std.fmt.bufPrint(&buffer, "run{s}", .{suffix})) orelse return error.MissingCompanionRun;
            result.jump[grip] = try animation.find(bytes, if (carrying) "jumpa" else try std.fmt.bufPrint(&buffer, "ajump{s}", .{suffix})) orelse return error.MissingCompanionJump;
            result.crouch[grip] = try animation.find(bytes, if (carrying) "camb" else try std.fmt.bufPrint(&buffer, "camb{s}", .{suffix})) orelse return error.MissingCompanionCrouch;
            result.crouch_walk[grip] = try animation.find(bytes, if (carrying) "cwalk" else try std.fmt.bufPrint(&buffer, "cwalk{s}", .{suffix})) orelse return error.MissingCompanionCrouchWalk;
            result.crouch_attack[grip] = if (carrying) result.crouch[grip] else try animation.find(bytes, try std.fmt.bufPrint(&buffer, "catak{s}", .{suffix})) orelse return error.MissingCompanionCrouchAttack;
            result.attack[grip] = if (carrying) result.idle[grip] else try animation.find(bytes, try std.fmt.bufPrint(&buffer, "atak{s}", .{suffix})) orelse return error.MissingCompanionAttack;
        }
        return result;
    }
    pub fn select(self: Set, weapon: i32, moving: bool, jumping: bool, ducked: bool, swimming: bool, jump_started: i64, last_fire: ?i64, changed: i64, now: i64) Playback {
        const grip = weaponGrip(weapon);
        if (swimming) if (self.swim) |sequence| return .{ .sequence = sequence, .started = changed };
        if (ducked) {
            if (moving) return .{ .sequence = self.crouch_walk[grip], .started = changed };
            if (last_fire) |at| if (now >= at and now - at < self.crouch_attack[grip].duration()) return .{ .sequence = self.crouch_attack[grip], .started = at, .looping = false };
            return .{ .sequence = self.crouch[grip], .started = changed };
        }
        if (jumping) return .{ .sequence = self.jump[grip], .started = jump_started, .looping = false };
        if (moving) return .{ .sequence = self.run[grip], .started = changed };
        if (last_fire) |at| if (now >= at and now - at < self.attack[grip].duration()) return .{ .sequence = self.attack[grip], .started = at, .looping = false };
        return .{ .sequence = self.idle[grip], .started = changed };
    }
};
pub fn weaponGrip(weapon: i32) usize {
    const entry = if (weapon > 0 and weapon < 32) catalog.find(@intCast(weapon)) else null;
    return if (entry) |item| switch (item.spec.player_grip) {
        .glove => 0,
        .pistol => 1,
        .rifle, .shoulder => 2,
    } else 0;
}
