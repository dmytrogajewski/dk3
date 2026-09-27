// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored burst windows and chase/hover cycle for the bridge's heavy flier.
const std = @import("std");
pub const attack = "ataka";
pub const spray_model = "models/global/e_flyellow.sp2";
pub const spray_sound = "global/e_warploopb.wav";
pub const spray_tag: i32 = -1;
pub const State = struct {
    phase: enum { chase, attack, hover } = .chase,
    started_ms: i64 = 0,
    next_shot: u3 = 0,
    sounded: bool = false,
    pub fn enter(self: *State, phase: @FieldType(State, "phase"), now: i64) void {
        self.phase = phase;
        self.started_ms = now;
        self.next_shot = 0;
        self.sounded = false;
    }
    pub fn shots(self: *State, now: i64, first: u16, fps: u16) u3 {
        const frames = [_]u16{ 27, 28, 31, 32 };
        var count: u3 = 0;
        while (self.next_shot < frames.len and now >= self.started_ms + @divTrunc(@as(i64, frames[self.next_shot] - first) * 1000, fps)) {
            self.next_shot += 1;
            count += 1;
        }
        return count;
    }
};
pub const Spray = struct {
    owner: u32,
    alternate: bool,
    born_ms: i64,
    stepped_ms: i64,
    next_ms: i64,
    phase: u4 = 0,
    scale: f32 = 1.4,
    delta: f32 = -0.25,
    pub fn tick(self: *Spray, velocity: *[3]f32) bool {
        var sound = false;
        if (self.scale < 0.3) self.delta = 0.25 else if (self.scale > 0.85) {
            self.delta = -0.25;
            sound = self.alternate;
        }
        self.scale += self.delta;
        // The reference indexes a twelve-entry trigonometric cycle at index 12.
        // Wrap at twelve so the correction cannot read unrelated memory.
        const angle = (1 + 30 * @as(f32, @floatFromInt(self.phase))) * std.math.pi / 180;
        const wave = if (self.alternate) @sin(angle) else @cos(angle);
        velocity[0] += 10 * wave;
        velocity[1] += 5 * wave;
        self.phase = (self.phase + 1) % 12;
        return sound;
    }
};
pub fn blast(distance: f32, owner: bool) f32 {
    return 40 * @max(0, 1 - distance * distance / (256 * 256)) * (if (owner) @as(f32, 0.5) else 1);
}
test "thunderskeet emits four authored shots once and applies quadratic splash" {
    var state: State = .{};
    state.enter(.attack, 1000);
    try std.testing.expectEqual(@as(u3, 0), state.shots(1699, 20, 10));
    try std.testing.expectEqual(@as(u3, 1), state.shots(1700, 20, 10));
    try std.testing.expectEqual(@as(u3, 3), state.shots(2200, 20, 10));
    try std.testing.expectEqual(@as(u3, 0), state.shots(2500, 20, 10));
    try std.testing.expectEqual(@as(f32, 30), blast(128, false));
    try std.testing.expectEqual(@as(f32, 15), blast(128, true));
    var spray: Spray = .{ .owner = 1, .alternate = true, .born_ms = 0, .stepped_ms = 0, .next_ms = 200 };
    var velocity: [3]f32 = .{ 128, 0, 0 };
    for (0..100) |_| {
        _ = spray.tick(&velocity);
        try std.testing.expect(spray.phase < 12);
    }
}
