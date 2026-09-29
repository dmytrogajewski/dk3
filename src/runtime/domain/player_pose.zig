// SPDX-License-Identifier: GPL-2.0-or-later
//! Remote body poses use the supplied character sequences and weapon-owned grip.
const std = @import("std");
const animation = @import("animation.zig");
const Grip = @import("weapon_catalog").PlayerGrip;
const v = @import("vector.zig");
pub const Pose = enum { idle, run, crouch, crouch_walk, jump, moving_jump, stop, crouch_in, crouch_out, dead };
pub const State = struct {
    pose: Pose = .idle,
    grip: Grip = .glove,
    started_ms: i64 = 0,
    reverse: bool = false,
    initialized: bool = false,
};
pub const Input = struct { velocity: v.Vec3, yaw: f32, ducked: bool, jumping: bool, dead: bool, fired_ms: ?i64 = null };
pub const Set = struct {
    frames: [3][std.meta.fields(Pose).len]animation.Sequence,
    attacks: [3][2]animation.Sequence,
    pub fn read(bytes: []const u8) !Set {
        var result: Set = undefined;
        for (&result.frames, 0..) |*poses, grip| inline for (std.meta.fields(Pose)) |field| {
            const pose: Pose = @enumFromInt(field.value);
            const base = switch (pose) {
                .idle => "aamb",
                .run => "run",
                .crouch => "camb",
                .crouch_walk => "cwalk",
                .jump => "ajump",
                .moving_jump => "bjump",
                .stop => "rstopl",
                .crouch_in => "cin",
                .crouch_out => "cout",
                .dead => "dieb",
            };
            var buffer: [24]u8 = undefined;
            const name = try std.fmt.bufPrint(&buffer, "{s}{s}", .{ base, if (pose == .dead or grip == 0) @as([]const u8, "") else if (grip == 1) "a" else "b" });
            const found = try animation.find(bytes, name);
            // Hiro and Superfly author ajump but no bjump sequence. Use their
            // supplied jump for both motions; never display unrelated frame zero.
            poses[field.value] = found orelse if (pose == .moving_jump) poses[@intFromEnum(Pose.jump)] else return error.MissingPlayerAnimation;
        };
        for (&result.attacks, 0..) |*stances, grip| for (stances, 0..) |*attack, crouching| {
            var name: [16]u8 = undefined;
            attack.* = try animation.find(bytes, try std.fmt.bufPrint(&name, "{s}atak{s}", .{ if (crouching == 1) @as([]const u8, "c") else "", if (grip == 0) @as([]const u8, "") else if (grip == 1) "a" else "b" })) orelse return error.MissingPlayerAttackAnimation;
        };
        return result;
    }
    pub fn sequence(self: *const Set, pose: Pose, grip: Grip) animation.Sequence {
        return self.frames[
            switch (grip) {
                .glove => @as(usize, 0),
                .pistol => 1,
                .rifle, .shoulder => 2,
            }
        ][@intFromEnum(pose)];
    }
    pub fn frame(self: *const Set, state: *State, input: Input, grip: Grip, now: i64) u16 {
        return self.playback(state, input, grip, now).frame(now);
    }
    pub fn respawnAt(self: *const Set, state: State, eligible_ms: i64) i64 {
        return if (state.pose == .dead) @max(eligible_ms, state.started_ms + self.sequence(.dead, state.grip).duration() + 300) else eligible_ms;
    }
    pub fn playback(self: *const Set, state: *State, input: Input, grip: Grip, now: i64) animation.Playback {
        const moving = @abs(input.velocity[0]) > 1 or @abs(input.velocity[1]) > 1;
        const wanted: Pose = if (input.dead) .dead else if (input.jumping) (if (moving) .moving_jump else .jump) else if (input.ducked) (if (moving) .crouch_walk else .crouch) else if (moving) .run else .idle;
        const yaw = std.math.atan2(input.velocity[1], input.velocity[0]) * 180 / std.math.pi;
        const backwards = moving and @abs(@mod(yaw - input.yaw + 180, 360) - 180) >= 145;
        const reverse = backwards and (wanted == .run or wanted == .crouch_walk);
        const transitioning = state.pose == .stop or state.pose == .crouch_in or state.pose == .crouch_out;
        const target: Pose = if (state.pose == .crouch_in) .crouch else .idle;
        const running_transition = transitioning and wanted == target and grip == state.grip and now - state.started_ms < self.sequence(state.pose, state.grip).duration();
        if (!running_transition and (!state.initialized or wanted != state.pose or grip != state.grip or reverse != state.reverse)) {
            const transition: ?Pose = if (!state.initialized or grip != state.grip) null else if (state.pose == .run and wanted == .idle) .stop else if (state.pose == .idle and wanted == .crouch) .crouch_in else if (state.pose == .crouch and wanted == .idle) .crouch_out else null;
            state.* = .{ .pose = transition orelse wanted, .grip = grip, .started_ms = now, .reverse = reverse, .initialized = true };
        }
        const sequence_value = self.sequence(state.pose, state.grip);
        const looping = switch (state.pose) {
            .dead, .stop, .crouch_in, .crouch_out => false,
            else => true,
        };
        if (!input.dead and !input.jumping and !moving) if (input.fired_ms) |at| {
            const index: usize = switch (grip) {
                .glove => 0,
                .pistol => 1,
                .rifle, .shoulder => 2,
            };
            const attack = self.attacks[index][@intFromBool(input.ducked)];
            if (now >= at and now - at < attack.duration()) return .{ .sequence = attack, .started = at, .looping = false };
        };
        return .{ .sequence = sequence_value, .started = state.started_ms, .looping = looping, .reverse = state.reverse };
    }
};

test "remote pose transitions finish and backward movement reverses authored frames" {
    var set: Set = undefined;
    for (&set.frames) |*poses| for (poses, 0..) |*value, i| {
        value.* = .{ .first = @intCast(i * 10), .last = @intCast(i * 10 + 3) };
    };
    var state: State = .{};
    var input: Input = .{ .velocity = .{ -100, 0, 0 }, .yaw = 0, .ducked = false, .jumping = false, .dead = false };
    try std.testing.expectEqual(@as(u16, 13), set.frame(&state, input, .rifle, 1000));
    try std.testing.expectEqual(@as(u16, 12), set.frame(&state, input, .rifle, 1100));
    input.velocity = @splat(0);
    _ = set.frame(&state, input, .rifle, 1200);
    try std.testing.expectEqual(Pose.stop, state.pose);
    _ = set.frame(&state, input, .rifle, 1599);
    try std.testing.expectEqual(@as(i64, 1200), state.started_ms);
    _ = set.frame(&state, input, .rifle, 1600);
    try std.testing.expectEqual(Pose.idle, state.pose);
    input.dead = true;
    _ = set.frame(&state, input, .rifle, 1700);
    try std.testing.expectEqual(@as(u16, 93), set.frame(&state, input, .rifle, 9999));
    try std.testing.expectEqual(@as(i64, 2400), set.respawnAt(state, 2000));
    try std.testing.expectEqual(@as(i64, 4000), set.respawnAt(state, 4000));
}

test "remote attacks require an actual fire timestamp and use the equipped grip and stance" {
    var set: Set = undefined;
    for (&set.frames) |*poses| for (poses) |*sequence_value| {
        sequence_value.* = .{ .first = 0, .last = 3 };
    };
    for (&set.attacks, 0..) |*stances, grip| for (stances, 0..) |*sequence_value, stance| {
        const first: u16 = @intCast(100 + 20 * grip + 10 * stance);
        sequence_value.* = .{ .first = first, .last = first + 5 };
    };
    var state: State = .{};
    var input: Input = .{ .velocity = @splat(0), .yaw = 0, .ducked = false, .jumping = false, .dead = false };
    try std.testing.expectEqual(@as(u16, 0), set.frame(&state, input, .rifle, 1000));
    input.fired_ms = 1000;
    try std.testing.expectEqual(@as(u16, 141), set.frame(&state, input, .rifle, 1100));
    input.ducked = true;
    try std.testing.expectEqual(@as(u16, 132), set.frame(&state, input, .pistol, 1200));
    input.dead = true;
    try std.testing.expect(set.frame(&state, input, .pistol, 1300) < 100);
}
