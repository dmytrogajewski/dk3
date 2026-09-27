// SPDX-License-Identifier: GPL-2.0-or-later
//! Body poses retain each character's supplied grip and carrying sequences.
const animation = @import("animation.zig");
const std = @import("std");
const catalog = @import("weapon_catalog");
pub const Set = struct {
    idle: [3]animation.Sequence,
    run: [3]animation.Sequence,
    jump: [3]animation.Sequence,
    attack: [3]animation.Sequence,
    crouch: [3]animation.Sequence,
    crouch_walk: [3]animation.Sequence,
    crouch_attack: [3]animation.Sequence,
    swim: ?animation.Sequence,
    pub fn read(bytes: []const u8, carrying: bool) !Set {
        var result: Set = undefined;
        result.swim = if (carrying) null else try animation.find(bytes, "swim") orelse return error.MissingCompanionSwim;
        for (0..3) |grip| {
            var buffer: [32]u8 = undefined;
            const suffix = if (grip == 0) "" else if (grip == 1) "a" else "b";
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
    pub fn frame(self: Set, weapon: i32, moving: bool, jumping: bool, ducked: bool, swimming: bool, jump_started: i64, last_fire: ?i64, changed: i64, now: i64) u16 {
        const entry = if (weapon > 0 and weapon < 32) catalog.find(@intCast(weapon)) else null;
        const grip: usize = if (entry) |item| switch (item.spec.player_grip) {
            .glove => 0,
            .pistol => 1,
            .rifle, .shoulder => 2,
        } else 0;
        if (swimming) if (self.swim) |sequence| return sequence.frame(now - changed, true);
        if (ducked) {
            if (moving) return self.crouch_walk[grip].frame(now - changed, true);
            if (last_fire) |at| if (now >= at and now - at < self.crouch_attack[grip].duration()) return self.crouch_attack[grip].frame(now - at, false);
            return self.crouch[grip].frame(now - changed, true);
        }
        if (jumping) return self.jump[grip].frame(now - jump_started, false);
        if (moving) return self.run[grip].frame(now - changed, true);
        if (last_fire) |at| if (now >= at and now - at < self.attack[grip].duration()) return self.attack[grip].frame(now - at, false);
        return self.idle[grip].frame(now - changed, true);
    }
};
