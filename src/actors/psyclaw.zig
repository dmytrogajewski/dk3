// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
pub const attacks = [_][]const u8{ "ataka", "atakb" };
pub const State = struct {
    protected_until_ms: i64 = 0,
    jump_started_ms: ?i64 = null,
    reduced: bool = false,
    horizontal: [2]f32 = @splat(0),
    emit_ms: i64 = 0,
};
pub const Sphere = struct {
    damage: f32,
    small: bool,
    scale: f32,
    multiplier: f32 = 1.45,
    color: i8 = 0,
    color_direction: i8 = 0,
    next_ms: i64,
    pub fn pulse(self: *Sphere) void {
        if (self.scale > (if (self.small) @as(f32, 2) else 3)) self.multiplier = 0.9 else if (self.scale < (if (self.small) @as(f32, 0.8) else 1.15)) self.multiplier = 1.1;
        self.scale *= self.multiplier;
        self.color += self.color_direction;
        if (self.color >= 25) self.color_direction = -8 else if (self.color <= 0) self.color_direction = 8;
    }
    pub fn tint(self: Sphere) [3]f32 {
        const blend = @as(f32, @floatFromInt(self.color)) * 0.04;
        return .{ 0.45 * (1 - blend), -0.15 + 1.15 * blend, 1 - blend };
    }
};
pub const Warp = struct { source: u32, until_ms: i64, next_ms: i64, random: u32 };
pub const Visual = struct { fov: f32 = 0, roll: f32 = 0, blend: [4]f32 = @splat(0) };
pub const model = "models/e1/me_psyclaw.dkm";
pub const render_tag = 10014;
pub const loop_sound = "global/e_atmospheref.wav";
pub fn warped(until: i64, now: i64) bool {
    return until > now;
}
pub fn visual(until: i64, now: i64) Visual {
    if (!warped(until, now)) return .{};
    const elapsed = std.math.clamp(8000 - (until - now), 0, 8000);
    const count: usize = @intCast(@divTrunc(elapsed, 100));
    var result: Visual = .{};
    for (0..count) |tick| {
        const remaining = 8000 - @as(i64, @intCast(tick + 1)) * 100;
        const fade = std.math.clamp(@as(f32, @floatFromInt(remaining)) / 3000, 0, 1);
        // One-degree phase offset, thirty-degree samples. Bound the complete
        // twelve-sample cycle instead of the reference out-of-bounds thirteenth.
        const angle = @as(f32, @floatFromInt(1 + tick % 12 * 30)) * std.math.pi / 180;
        const sine = @round(@sin(angle) * 1000) * 0.001;
        const cosine = @round(@cos(angle) * 1000) * 0.001;
        if (remaining >= 3000) result.fov += 5 * sine else result.fov -= std.math.clamp(result.fov, -0.5, 0.5);
        result.roll += 6 * fade * cosine;
        const phase = (tick + 1) % 10;
        const color = @as(f32, @floatFromInt(if (phase <= 5) phase * 5 else (10 - phase) * 5)) * 0.03;
        result.blend = .{ 0.25 * (1 - color), @max(0, -0.15 + color), 1 - color, 0.35 * fade };
    }
    return result;
}
test "psyclaw view distortion expires and sphere pulse reverses at its own bounds" {
    const t = std.testing;
    try t.expectEqualDeep(Visual{}, visual(8100, 8100));
    try t.expect(visual(8100, 1200).blend[3] > 0);
    var sphere: Sphere = .{ .damage = 10, .small = false, .scale = 3.1, .next_ms = 100 };
    sphere.pulse();
    try t.expect(sphere.scale < 3.1);
    try t.expectEqual(@as(f32, 0.9), sphere.multiplier);
}
